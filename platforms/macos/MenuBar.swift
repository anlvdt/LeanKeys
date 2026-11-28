import Cocoa
import Combine
import LeanKeysKit // LEANKEYS-HOOK: language-sync
import SwiftUI

// MARK: - Notifications

extension Notification.Name {
    static let showSettingsPage = Notification.Name("showSettingsPage")
}

// MARK: - Menu Bar Controller

class MenuBarController: NSObject, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private var updateMenuItem: NSMenuItem!
    private var stateObserver: NSObjectProtocol?

    private var onboardingWindow: NSWindow?
    private var grantWatcher: GrantWatcher? // LEANKEYS-HOOK: onboarding
    private var settingsWindow: NSWindow?

    private let appState = AppState.shared
    private var cancellables = Set<AnyCancellable>()
    private var pendingRestart: DispatchWorkItem?
    private lazy var secureInputIcon = createSecureInputIcon()
    // LEANKEYS-HOOK-BEGIN: menubar-popover
    private var legacyMenu: NSMenu?
    private var popoverModel: StatusPopoverModel?
    private var statusPopover: StatusPopoverController?
    private var isShowingLegacyMenu = false
    // LEANKEYS-HOOK-END

    override init() {
        super.init()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        setupMenu()
        setupNotifications()
        updateStatusButton()
        FirstRun.performIfNeeded(enableLaunchAtLogin: { try LaunchAtLoginManager.shared.enable() }) // LEANKEYS-HOOK: onboarding
        ReturningUser.record(isTrusted: AXIsProcessTrusted()) // LEANKEYS-HOOK: onboarding

        if UserDefaults.standard.bool(forKey: SettingsKey.hasCompletedOnboarding), AXIsProcessTrusted() {
            startEngine()
        } else {
            showOnboarding()
        }
    }

    // MARK: - Setup

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onboardingDidComplete),
            name: .onboardingCompleted,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleToggleVietnamese),
            name: .toggleVietnamese,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInputSourceChanged),
            name: .inputSourceChanged,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShowSettingsPage),
            name: .showSettingsPage,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShortcutChanged),
            name: .shortcutChanged,
            object: nil
        )

        // Observe AppState changes via Combine
        appState.$isEnabled
            .combineLatest(appState.$currentMethod)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in
                self?.updateStatusButton()
                self?.updateMenu()
            }
            .store(in: &cancellables)

        appState.$isSecureInputBlocked
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusButton()
                self?.updateMenu()
            }
            .store(in: &cancellables)
    }

    @objc private func handleShowSettingsPage() {
        showSettings()
    }

    private func setupMenu() {
        let menu = NSMenu()

        // Header with toggle
        let header = NSMenuItem()
        header.view = createHeaderView()
        header.tag = 1
        menu.addItem(header)
        menu.addItem(.separator())

        // Input methods
        let telex = NSMenuItem(title: InputMode.telex.name, action: #selector(selectTelex), keyEquivalent: "")
        telex.target = self
        telex.tag = 10
        menu.addItem(telex)

        let vni = NSMenuItem(title: InputMode.vni.name, action: #selector(selectVNI), keyEquivalent: "")
        vni.target = self
        vni.tag = 11
        menu.addItem(vni)
        menu.addItem(.separator())

        // Settings
        let settings = NSMenuItem(title: "Cài đặt…", action: #selector(showSettings), keyEquivalent: "") // LEANKEYS-HOOK: copy
        settings.target = self
        menu.addItem(settings)

        // About
        let about = NSMenuItem(title: "Về \(AppMetadata.name)", action: #selector(showAbout), keyEquivalent: "") // LEANKEYS-HOOK: copy
        about.target = self
        menu.addItem(about)

        // Update
        updateMenuItem = NSMenuItem(title: "Kiểm tra cập nhật…", action: #selector(handleUpdateAction), keyEquivalent: "") // LEANKEYS-HOOK: copy
        updateMenuItem.target = self
        menu.addItem(updateMenuItem)
        menu.addItem(.separator())

        // Quit
        let quit = NSMenuItem(title: "Thoát \(AppMetadata.name)", action: #selector(NSApp.terminate), keyEquivalent: "q")
        menu.addItem(quit)

        // LEANKEYS-HOOK-BEGIN: menubar-popover
        legacyMenu = menu
        statusItem.button?.target = self
        statusItem.button?.action = #selector(handleStatusClick(_:))
        _ = statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        // 4B: the mirror's phrases go to the learner (on its own queue); accepted suggestions go to AppState's gõ tắt.
        ShortcutSuggestionsModel.shared.start(
            router: .shared,
            existingTriggers: { AppState.shared.shortcuts.map(\.key) },
            existingReplacements: { AppState.shared.shortcuts.map(\.value) },
            addShortcut: { AppState.shared.addLearnedShortcut(trigger: $0, text: $1) }
        )
        // LEANKEYS-HOOK-END
        updateMenu()
    }

    private var statusSubtitle: String {
        if appState.shouldShowSecureInputWarning {
            if let holder = appState.secureInputHolderName {
                return "Tạm dừng · \(holder) đang chặn gõ tiếng Việt" // LEANKEYS-HOOK: copy
            }
            return "Tạm dừng · Một ô mật khẩu đang chặn gõ" // LEANKEYS-HOOK: copy
        }
        let mode = appState.isEnabled ? appState.currentMethod.name : "English" // LEANKEYS-HOOK: copy
        return "\(mode) · \(appState.toggleShortcut.displayParts.joined())"
    }

    /// Header: icon + bold title + subtitle on left, toggle switch on right
    private func createHeaderView() -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 0, height: 44))
        container.autoresizingMask = [.width] // Stretch to menu width

        let iconView = NSImageView(image: AppMetadata.logo)
        iconView.imageScaling = .scaleProportionallyUpOrDown

        let titleLabel = NSTextField(labelWithString: "\(AppMetadata.name) \(AppMetadata.version)") // LEANKEYS-HOOK: copy (version in the right-click menu)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)

        let subtitle = NSTextField(labelWithString: statusSubtitle)
        subtitle.font = .systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor
        subtitle.tag = 100 // For in-place updates

        let toggleView = NSHostingView(rootView: MenuBarToggle())

        for view in [iconView, titleLabel, subtitle, toggleView] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
        }

        let padding: CGFloat = 14
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(greaterThanOrEqualToConstant: 250),
            container.heightAnchor.constraint(equalToConstant: 44),
            iconView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: padding),
            iconView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 32),
            iconView.heightAnchor.constraint(equalToConstant: 32),
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 5),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: toggleView.leadingAnchor, constant: -8),
            subtitle.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitle.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),
            subtitle.trailingAnchor.constraint(lessThanOrEqualTo: toggleView.leadingAnchor, constant: -8),
            toggleView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -padding),
            toggleView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])

        return container
    }

    private func updateMenu() {
        guard let menu = statusItem.menu ?? legacyMenu else { return } // LEANKEYS-HOOK: menubar-popover

        // Update subtitle in-place (preserves toggle animation)
        if let headerView = menu.item(withTag: 1)?.view,
           let subtitle = headerView.viewWithTag(100) as? NSTextField
        {
            subtitle.stringValue = statusSubtitle
            headerView.frame.size.width = headerView.fittingSize.width
        }

        menu.item(withTag: 10)?.state = appState.currentMethod == .telex ? .on : .off
        menu.item(withTag: 11)?.state = appState.currentMethod == .vni ? .on : .off
    }

    @objc private func selectTelex() {
        appState.setMethod(.telex)
    }

    @objc private func selectVNI() {
        appState.setMethod(.vni)
    }

    @objc private func handleUpdateAction() {
        if UpdateManager.shared.isReadyToInstall {
            UpdateManager.shared.restartToUpdate()
        } else {
            UpdateManager.shared.checkForUpdatesManually()
        }
    }

    private func syncUpdateMenuItem() {
        let mgr = UpdateManager.shared
        let title = if mgr.isReadyToInstall {
            "Cài bản mới \(mgr.pendingVersion) và mở lại" // LEANKEYS-HOOK: copy
        } else if mgr.isChecking {
            "Đang kiểm tra cập nhật…" // LEANKEYS-HOOK: copy
        } else {
            "Kiểm tra cập nhật…" // LEANKEYS-HOOK: copy
        }
        updateMenuItem.title = title
        // Also sync the main menu bar item (tag 999)
        NSApp.mainMenu?.item(at: 0)?.submenu?.item(withTag: 999)?.title = title
    }

    @objc private func showAbout() {
        showSettings()
        // Switch to About page after window is shown
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NotificationCenter.default.post(name: .showSettingsPage, object: NavigationPage.about)
        }
    }

    private func startEngine() {
        RustBridge.initialize()
        KeyboardHookManager.shared.start()
        RustBridge.setEnabled(appState.isEnabled)
        RustBridge.setMethod(appState.currentMethod.rawValue)
        // LEANKEYS-HOOK-BEGIN: language-sync
        // Vikey switched language by itself: mirror it in the menu bar icon only. Silent, so the automatic switch
        // is never saved as a per-app or global choice (ruling R25); the didSet's EngineRouter.setEnabled is not
        // explicit and leaves auto switch on.
        NotificationCenter.default.addObserver(forName: .leanKeysLanguageChanged, object: nil, queue: .main) { [weak self] note in
            guard let self, let on = note.userInfo?["vietnamese"] as? Bool, appState.isEnabled != on else { return }
            appState.setEnabledSilently(on)
        }
        // LEANKEYS-HOOK-END

        // Sync all engine settings (these were loaded before engine was ready)
        RustBridge.setModernTone(appState.modernTone)
        RustBridge.setSkipWShortcut(!appState.autoWShortcut)
        RustBridge.setBracketShortcut(appState.bracketShortcut)
        RustBridge.setRestoreShortcutEnabled(appState.restoreShortcutEnabled)
        RustBridge.setEnglishAutoRestore(appState.englishAutoRestore)
        RustBridge.setAutoCapitalize(appState.autoCapitalize)
        RustBridge.setAllowForeignConsonants(appState.allowForeignConsonants)

        // Sync shortcuts and start per-app mode manager
        appState.syncShortcutsToEngine()
        PerAppModeManager.shared.start()

        // Background auto-update (check every 1h, download silently)
        UpdateManager.shared.startBackgroundUpdates()

        // Observe update state to sync menu item
        stateObserver = NotificationCenter.default.addObserver(
            forName: .updateStateChanged, object: nil, queue: .main
        ) { [weak self] _ in self?.syncUpdateMenuItem() }
    }

    // MARK: - Status Button

    private func updateStatusButton() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let button = statusItem.button else { return }
            button.title = ""

            let isSecureInputBlocked = appState.shouldShowSecureInputWarning
            if isSecureInputBlocked {
                MenuBarIconAnimator.prepare(button) // LEANKEYS-HOOK: menubar-popover
                button.image = secureInputIcon
                button.setAccessibilityLabel(StatusItemAccessibility.label(blocked: true, iconText: "")) // LEANKEYS-HOOK: copy
            } else {
                let observer = InputSourceObserver.shared
                let text: String = if observer.isAllowedInputSource {
                    // ABC keyboard: show V (enabled) or E (disabled)
                    appState.isEnabled ? "V" : "E"
                } else {
                    // Non-ABC keyboard: show input source character
                    observer.currentDisplayChar
                }
                MenuBarIconAnimator.prepare(button) // LEANKEYS-HOOK: menubar-popover
                button.image = createStatusIcon(text: text)
                button.setAccessibilityLabel(StatusItemAccessibility.label(blocked: false, iconText: text)) // LEANKEYS-HOOK: copy
            }
            // LEANKEYS-HOOK-BEGIN: menubar-popover
            // Vikey can switch language while the popover is open; re-read so its segmented control follows.
            if let statusPopover, statusPopover.isShown { popoverModel?.reload() }
            // LEANKEYS-HOOK-END
            button.toolTip = isSecureInputBlocked
                ? SecureInputPresentation.tooltip(holderName: appState.secureInputHolderName)
                : nil
        }
    }

    private func createSecureInputIcon() -> NSImage {
        let width: CGFloat = 22
        let height: CGFloat = 16
        let image = NSImage(size: NSSize(width: width, height: height))

        image.lockFocus()

        let rect = NSRect(x: 0, y: 0, width: width, height: height)
        let path = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
        NSColor.black.setFill()
        path.fill()

        if let symbol = NSImage(
            systemSymbolName: "lock.fill",
            accessibilityDescription: "Tạm dừng gõ tiếng Việt" // LEANKEYS-HOOK: copy
        )?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 10, weight: .bold)) {
            let symbolSize = symbol.size
            let symbolRect = NSRect(
                x: (width - symbolSize.width) / 2,
                y: (height - symbolSize.height) / 2,
                width: symbolSize.width,
                height: symbolSize.height
            )
            symbol.draw(
                in: symbolRect,
                from: .zero,
                operation: .destinationOut,
                fraction: 1
            )
        }

        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    private func createStatusIcon(text: String) -> NSImage {
        let width: CGFloat = 22
        let height: CGFloat = 16
        let image = NSImage(size: NSSize(width: width, height: height))

        image.lockFocus()

        // Draw rounded rect background (black for template)
        let rect = NSRect(x: 0, y: 0, width: width, height: height)
        let path = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
        NSColor.black.setFill()
        path.fill()

        // Cut out text as transparent
        let font = NSFont.systemFont(ofSize: 13, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black,
        ]
        let textSize = text.size(withAttributes: attrs)
        let textRect = NSRect(
            x: (width - textSize.width) / 2,
            y: (height - textSize.height) / 2,
            width: textSize.width,
            height: textSize.height
        )
        NSGraphicsContext.current?.compositingOperation = .destinationOut
        text.draw(in: textRect, withAttributes: attrs)

        image.unlockFocus()

        // Template image: macOS auto-adjusts color for light/dark menu bar
        image.isTemplate = true
        return image
    }

    // MARK: - Event Handlers
    // LEANKEYS-HOOK-BEGIN: menubar-popover
    /// Built on the first click, not at launch. The model is kept here because StatusPopoverController does not expose it.
    private func statusPopoverController() -> StatusPopoverController {
        if let statusPopover { return statusPopover }
        // Closures read AppState and UpdateManager directly. Only the ones that need this controller capture self, weakly.
        let model = StatusPopoverModel(actions: StatusPopoverActions(
            snapshot: { AppState.shared.leanStatusSnapshot },
            method: { AppState.shared.currentMethod.rawValue },
            updateReady: { UpdateManager.shared.isReadyToInstall },
            setVietnamese: { [weak self] vietnamese in
                guard AppState.shared.isEnabled != vietnamese else { return }
                self?.handleToggleVietnamese()
            },
            setMethod: { raw in
                guard let mode = InputMode(rawValue: raw) else { return }
                AppState.shared.setMethod(mode)
            },
            installUpdate: { UpdateManager.shared.installFromPopoverNow() },
            openSettings: { [weak self] in self?.showSettings() },
            quit: { NSApp.terminate(nil) },
            suggestionCount: { ShortcutSuggestionsModel.shared.suggestionCount },
            openSuggestions: { ShortcutSuggestionsWindow.show(.shared) },
            updatePhase: { UpdateManager.shared.popoverPhase },
            checkForUpdates: { UpdateManager.shared.checkFromPopover() },
            popoverClosed: { UpdateManager.shared.popoverClosed() },
            version: { AppMetadata.version },
            toggleShortcut: { AppState.shared.toggleShortcut.displayParts.joined() },
            autoFix: { AppState.shared.autoFix },
            setAutoFix: { AppState.shared.autoFix = $0 },
            newVersion: {
                StatusPopoverModel.displayedNewVersion(UpdateManager.shared.pendingVersion,
                                                       ready: UpdateManager.shared.isReadyToInstall)
            },
            privacyNotice: { UndoLearning.shared.privacyNoticePending },
            enableLearning: {
                UndoLearning.shared.askConsentAndEnable { title, text, confirm, cancel in
                    let alert = NSAlert()
                    alert.messageText = title
                    alert.informativeText = text
                    alert.addButton(withTitle: confirm)
                    alert.addButton(withTitle: cancel)
                    NSApp.activate(ignoringOtherApps: true)
                    return alert.runModal() == .alertFirstButtonReturn
                }
            },
            dismissPrivacyNotice: { UndoLearning.shared.dismissPrivacyNotice() }
        ))
        // Check, download progress and install show while the popover is open (spec §16).
        NotificationCenter.default.publisher(for: .updateStateChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak model] _ in model?.reload() }
            .store(in: &cancellables)
        // A suggestion can appear while the popover is open.
        ShortcutSuggestionsModel.shared.$candidates
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak model] _ in model?.reload() }
            .store(in: &cancellables)
        let controller = StatusPopoverController(model: model)
        popoverModel = model
        statusPopover = controller
        return controller
    }

    /// Left click opens the popover. Right click and Option or Control click open the legacy menu.
    @objc private func handleStatusClick(_ sender: Any?) {
        guard !isShowingLegacyMenu, let button = statusItem.button else { return }
        let route = NSApp.currentEvent.map { StatusClickRoute.route(type: $0.type, modifiers: $0.modifierFlags) } ?? .popover
        switch route {
        case .popover:
            statusPopoverController().toggle(relativeTo: button)
        case .legacyMenu:
            // performClick runs the menu modally, so it can be removed again right after.
            // The flag stops a re-sent button action from recursing into this branch.
            isShowingLegacyMenu = true
            defer { isShowingLegacyMenu = false }
            statusItem.menu = legacyMenu
            button.performClick(nil)
            statusItem.menu = nil
        }
    }
    // LEANKEYS-HOOK-END

    @objc private func handleToggleVietnamese() {
        appState.toggle()
        SoundManager.shared.playToggleSound(enabled: appState.isEnabled)
    }

    @objc private func handleInputSourceChanged() {
        updateStatusButton()
        updateMenu()
    }

    @objc private func handleShortcutChanged() {
        updateMenu()
    }

    @objc private func onboardingDidComplete() {
        updateStatusButton()
        startEngine()
        enableLaunchAtLogin()
    }

    private func enableLaunchAtLogin() {
        do {
            try LaunchAtLoginManager.shared.enable()
        } catch {
            print("[LaunchAtLogin] Error: \(error)")
        }
    }

    // MARK: - Windows

    private func showOnboarding() {
        if onboardingWindow == nil {
            // LEANKEYS-HOOK-BEGIN: onboarding
            // One screen (spec §13.3). Once Accessibility is granted, relaunch like Gõ Nhanh's onboarding does:
            // an event tap made in this process could still fail and raise a modal alert; the new process starts
            // the engine through the hasCompletedOnboarding branch above. The watcher owns the relaunch, not the
            // window, so it still happens when the window is hidden or closed, and only once (ruling R3).
            let isGranted: () -> Bool = {
                AccessibilityGrant.isGranted(axTrusted: AXIsProcessTrusted, tapProbe: AccessibilityGrant.probeEventTap)
            }
            let relaunch: () -> Void = {
                // At most one relaunch per 60 s (LeanKeys.lastGrantRelaunch): a refused relaunch only logs.
                let now = Date()
                let last = UserDefaults.standard.object(forKey: GrantWatcher.lastRelaunchKey) as? Date
                guard GrantWatcher.shouldRelaunch(last: last, now: now) else {
                    NSLog("[LeanKeys] grant relaunch skipped: the previous relaunch was under 60 s ago")
                    return
                }
                UserDefaults.standard.set(now, forKey: GrantWatcher.lastRelaunchKey)
                ReturningUser.record(isTrusted: true)
                UserDefaults.standard.set(true, forKey: SettingsKey.permissionGranted)
                UserDefaults.standard.set(true, forKey: SettingsKey.hasCompletedOnboarding)
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/bin/sh")
                task.arguments = ["-c", "sleep 0.5 && open \"$1\"", "_", Bundle.main.bundlePath]
                try? task.run()
                NSApp.terminate(nil)
            }
            if grantWatcher == nil {
                grantWatcher = GrantWatcher(isGranted: isGranted, onGranted: relaunch)
                grantWatcher?.start()
            }
            // A returning user whose grant was lost: reset LeanKeys' own stale entry once per launch (this block
            // runs once per window). tccutil returns fast, so the synchronous wait here is acceptable.
            var resetDone = false
            if ReturningUser.wasTrusted(), !isGranted() {
                resetDone = TCCReset.run(bundleID: Bundle.main.bundleIdentifier ?? "io.github.anlvdt.leankeys")
            }
            let view = LeanOnboardingView(
                isTrusted: isGranted,
                openSettings: {
                    AccessibilityGrant.requestPrompt()
                    NSWorkspace.shared.open(AccessibilityGrant.settingsURL)
                },
                onDone: { [weak self] in self?.grantWatcher?.fireIfGranted() },
                wasTrusted: ReturningUser.wasTrusted(),
                resetDone: resetDone
            )
            // LEANKEYS-HOOK-END
            let controller = NSHostingController(rootView: view)
            onboardingWindow = NSWindow(contentViewController: controller)
            onboardingWindow?.title = AppMetadata.name
            onboardingWindow?.styleMask = [.titled, .closable]
            onboardingWindow?.setContentSize(controller.view.fittingSize)
            onboardingWindow?.center()
        }
        onboardingWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showSettings() {
        if settingsWindow == nil {
            let controller = NSHostingController(rootView: LeanSettingsWindow.root()) // LEANKEYS-HOOK: settings-engine
            controller.view.wantsLayer = true
            controller.view.layer?.backgroundColor = .clear
            let window = NSWindow(contentViewController: controller)
            window.title = "Cài đặt \(AppMetadata.name)" // LEANKEYS-HOOK: copy
            window.styleMask = NSWindow.StyleMask([.titled, .closable, .miniaturizable, .fullSizeContentView])
            window.standardWindowButton(.zoomButton)?.isHidden = true
            window.setContentSize(NSSize(width: 700, height: 480))
            window.center()
            window.isReleasedWhenClosed = false
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = true
            window.isMovableByWindowBackground = true
            window.delegate = self
            settingsWindow = window
        }
        // Show app in menu bar temporarily
        NSApp.setActivationPolicy(.regular)
        setupMainMenu() // Set menu before showing window
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
        // Override default menu after window is shown (macOS may reset it)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.setupMainMenu()
        }
        // Clear auto-focus on TextFields
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.settingsWindow?.makeFirstResponder(nil)
        }
    }

    private func setupMainMenu() {
        // Clear existing menu first
        NSApp.mainMenu = nil
        let mainMenu = NSMenu()

        // App menu (shows app name in menu bar)
        let appMenu = NSMenu(title: AppMetadata.name)
        let appMenuItem = NSMenuItem(title: AppMetadata.name, action: nil, keyEquivalent: "")
        appMenuItem.submenu = appMenu

        // About
        let aboutItem = NSMenuItem(
            title: "Về \(AppMetadata.name)",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        appMenu.addItem(aboutItem)

        appMenu.addItem(NSMenuItem.separator())

        // Check for updates
        let mainUpdateItem = NSMenuItem(
            title: updateMenuItem.title,
            action: #selector(handleUpdateAction),
            keyEquivalent: ""
        )
        mainUpdateItem.tag = 999
        mainUpdateItem.target = self
        appMenu.addItem(mainUpdateItem)

        appMenu.addItem(NSMenuItem.separator())

        // Settings
        let settingsItem = NSMenuItem(
            title: "Cài đặt…", // LEANKEYS-HOOK: copy
            action: #selector(showSettings),
            keyEquivalent: ""
        )
        settingsItem.target = self
        appMenu.addItem(settingsItem)

        appMenu.addItem(NSMenuItem.separator())

        // Close window (⌘W)
        appMenu.addItem(NSMenuItem(title: "Đóng cửa sổ", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))

        // Quit (⌘Q)
        let quitItem = NSMenuItem(
            title: "Thoát \(AppMetadata.name)",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenu.addItem(quitItem)

        mainMenu.addItem(appMenuItem)

        // Edit menu (required for copy/paste in TextFields)
        let editMenu = NSMenu(title: "Sửa")
        let editMenuItem = NSMenuItem(title: "Sửa", action: nil, keyEquivalent: "")
        editMenuItem.submenu = editMenu

        editMenu.addItem(NSMenuItem(title: "Hoàn tác", action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "Làm lại", action: Selector(("redo:")), keyEquivalent: "Z"))
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(NSMenuItem(title: "Cắt", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Sao chép", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Dán", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Chọn tất cả", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))

        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }

    // MARK: - Restart Management

    func cancelPendingRestart() {
        pendingRestart?.cancel()
        pendingRestart = nil
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window === settingsWindow else { return }

        window.contentViewController = nil
        settingsWindow = nil
        NSApp.setActivationPolicy(.accessory)

        // Restart app to reclaim memory if enabled
        // Use deferred restart: if app is quitting, applicationWillTerminate
        // will cancel this before it runs
        guard SettingsLayout.advancedSettingsApply(advancedMode: AppState.shared.advancedMode), // LEANKEYS-HOOK: settings-engine (copy audit I2)
              AppState.shared.restartOnClose else { return }
        let path = Bundle.main.bundleURL.path
        let work = DispatchWorkItem { [weak self] in
            guard self?.pendingRestart?.isCancelled == false else { return }
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/sh")
            task.arguments = ["-c", "sleep 0.5 && open \"$1\"", "_", path] // LEANKEYS-HOOK: settings-engine
            try? task.run()
            NSApp.terminate(nil)
        }
        pendingRestart = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
    }
}

// MARK: - Menu Bar Toggle (SwiftUI)

/// Observes AppState so the toggle reflects the actual enabled state.
/// Uses explicit Binding so sound only plays on direct toggle clicks (not keyboard shortcut or per-app restore).
struct MenuBarToggle: View {
    @ObservedObject private var appState = AppState.shared

    var body: some View {
        Toggle("", isOn: Binding(
            get: { appState.isEnabled },
            set: { newValue in
                appState.isEnabled = newValue
                SoundManager.shared.playToggleSound(enabled: newValue)
            }
        ))
        .toggleStyle(.switch)
        .labelsHidden()
    }
}
