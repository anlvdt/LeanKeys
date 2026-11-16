import AppKit
import Combine
import LeanKeysKit // LEANKEYS-HOOK: language-sync
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Sound Manager

class SoundManager {
    static let shared = SoundManager()

    // Cache sound instances to prevent issues with rapid toggling
    // Issue #168: sounds not playing when toggling rapidly
    private let enableSound: NSSound?
    private let disableSound: NSSound?
    private var currentSound: NSSound?

    private init() {
        enableSound = NSSound(named: NSSound.Name("Tink"))
        disableSound = NSSound(named: NSSound.Name("Pop"))
    }

    func playToggleSound(enabled: Bool) {
        guard AppState.shared.soundEnabled else { return }

        // Stop any currently playing sound to handle rapid toggling
        currentSound?.stop()

        // Use cached sound instances
        let sound = enabled ? enableSound : disableSound
        currentSound = sound
        sound?.play()
    }
}

// MARK: - Navigation

enum NavigationPage: String, CaseIterable {
    case settings = "Cài đặt"
    case advanced = "Nâng cao"
    case about = "Giới thiệu"

    var icon: String {
        switch self {
        case .settings: "gearshape"
        case .advanced: "wrench.and.screwdriver"
        case .about: "bolt.fill"
        }
    }
}

// MARK: - App State

class AppState: ObservableObject {
    static let shared = AppState()

    private var isSilentUpdate = false
    private var cancellables = Set<AnyCancellable>()

    @Published var isEnabled: Bool {
        didSet {
            RustBridge.setEnabled(isEnabled)
            guard !isSilentUpdate else { return }
            // LEANKEYS-HOOK-BEGIN: language-sync
            // A non-silent change is the user's own (toggle hotkey, menu, settings): off pauses Vikey's auto switch.
            EngineRouter.shared.setEnabled(isEnabled && InputSourceObserver.shared.isAllowedInputSource, explicit: true)
            // LEANKEYS-HOOK-END

            if perAppModeEnabled {
                // Per-app mode: only save per-app state, don't update global
                // Global state stays as "default" for new apps
                if let bundleId = PerAppModeManager.shared.getCurrentBundleId() {
                    savePerAppMode(bundleId: bundleId, enabled: isEnabled)
                } else if let bundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier {
                    savePerAppMode(bundleId: bundleId, enabled: isEnabled)
                }
            } else {
                // Global mode: save global state
                UserDefaults.standard.set(isEnabled, forKey: SettingsKey.enabled)
            }
        }
    }

    @Published private(set) var isSecureInputBlocked = false
    /// App reported by macOS as holding Secure Input; nil when unknown or not blocked.
    @Published private(set) var secureInputHolderName: String?

    var shouldShowSecureInputWarning: Bool {
        SecureInputPresentation.shouldShow(
            engineEnabled: isEnabled || EngineRouter.shared.active == .vikey, // LEANKEYS-HOOK: language-sync
            inputSourceAllowed: InputSourceObserver.shared.isAllowedInputSource,
            secureInputBlocked: isSecureInputBlocked
        )
    }

    func setSecureInputBlocked(_ blocked: Bool, holderName: String? = nil) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.setSecureInputBlocked(blocked, holderName: holderName) }
            return
        }
        secureInputHolderName = blocked ? holderName : nil
        guard isSecureInputBlocked != blocked else { return }
        isSecureInputBlocked = blocked
    }

    @Published var currentMethod: InputMode {
        didSet {
            RustBridge.setMethod(currentMethod.rawValue)
            guard !isSilentUpdate else { return }
            UserDefaults.standard.set(currentMethod.rawValue, forKey: SettingsKey.method)
        }
    }

    @Published var perAppModeEnabled: Bool = true {
        didSet { UserDefaults.standard.set(perAppModeEnabled, forKey: SettingsKey.perAppMode) }
    }

    @Published var autoWShortcut: Bool = true {
        didSet {
            UserDefaults.standard.set(autoWShortcut, forKey: SettingsKey.autoWShortcut)
            RustBridge.setSkipWShortcut(!autoWShortcut)
        }
    }

    @Published var bracketShortcut: Bool = false {
        didSet {
            UserDefaults.standard.set(bracketShortcut, forKey: SettingsKey.bracketShortcut)
            RustBridge.setBracketShortcut(bracketShortcut)
        }
    }

    @Published var restoreShortcutEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(restoreShortcutEnabled, forKey: SettingsKey.restoreShortcutEnabled)
            RustBridge.setRestoreShortcutEnabled(restoreShortcutEnabled)
        }
    }

    @Published var modernTone: Bool = true {
        didSet {
            UserDefaults.standard.set(modernTone, forKey: SettingsKey.modernTone)
            RustBridge.setModernTone(modernTone)
        }
    }

    @Published var englishAutoRestore: Bool = false {
        didSet {
            UserDefaults.standard.set(englishAutoRestore, forKey: SettingsKey.englishAutoRestore)
            RustBridge.setEnglishAutoRestore(englishAutoRestore)
        }
    }

    @Published var autoCapitalize: Bool = false {
        didSet {
            UserDefaults.standard.set(autoCapitalize, forKey: SettingsKey.autoCapitalize)
            updateAutoCapitalizeEngine()
        }
    }

    @Published var autoCapitalizeExcludedApps: Set<String> = [] {
        didSet {
            let array = Array(autoCapitalizeExcludedApps)
            UserDefaults.standard.set(array, forKey: SettingsKey.autoCapitalizeExcludedApps)
            updateAutoCapitalizeEngine()
        }
    }

    @Published var soundEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(soundEnabled, forKey: SettingsKey.soundEnabled)
        }
    }

    @Published var allowForeignConsonants: Bool = false {
        didSet {
            UserDefaults.standard.set(allowForeignConsonants, forKey: SettingsKey.allowForeignConsonants)
            RustBridge.setAllowForeignConsonants(allowForeignConsonants)
        }
    }

    @Published var toggleShortcut: KeyboardShortcut {
        didSet {
            toggleShortcut.save()
            NotificationCenter.default.post(name: .shortcutChanged, object: toggleShortcut)
        }
    }

    @Published var restoreShortcut: KeyboardShortcut {
        didSet {
            restoreShortcut.saveAsRestoreShortcut()
            NotificationCenter.default.post(name: .restoreShortcutChanged, object: restoreShortcut)
        }
    }

    @Published var secondaryToggleShortcut: KeyboardShortcut {
        didSet {
            secondaryToggleShortcut.saveAsSecondaryToggle()
            NotificationCenter.default.post(name: .secondaryShortcutChanged, object: nil)
        }
    }

    @Published var secondaryToggleShortcutEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(secondaryToggleShortcutEnabled, forKey: SettingsKey.secondaryToggleShortcutEnabled)
            NotificationCenter.default.post(name: .secondaryShortcutChanged, object: nil)
        }
    }

    @Published var advancedMode: Bool = false {
        didSet {
            UserDefaults.standard.set(advancedMode, forKey: SettingsKey.advancedMode)
        }
    }

    /// Disable Spotlight/Raycast panel detection for better performance
    @Published var disablePanelDetection: Bool = false {
        didSet {
            UserDefaults.standard.set(disablePanelDetection, forKey: SettingsKey.disablePanelDetection)
        }
    }

    @Published var restartOnClose: Bool = false {
        didSet {
            UserDefaults.standard.set(restartOnClose, forKey: SettingsKey.restartOnClose)
        }
    }

    /// Use cgSessionEventTap instead of cghidEventTap.
    /// Enables Vietnamese input for keystrokes injected at session level (invisible to the
    /// default HID tap): the macOS Accessibility Keyboard / on-screen keyboards (issue #395)
    /// and remote desktop software (RustDesk, AnyDesk, TeamViewer).
    /// Applied immediately via restart().
    @Published var sessionTapMode: Bool = false {
        didSet {
            UserDefaults.standard.set(sessionTapMode, forKey: SettingsKey.sessionTapMode)
            // Skip restart during init: AppState.shared is still being constructed
            // (dispatch_once in progress), so accessing it from restart() → start()
            // would cause recursive lock crash. User-triggered toggles always run
            // after init completes, when isSilentUpdate is false.
            guard !isSilentUpdate else { return }
            KeyboardHookManager.shared.restart()
        }
    }

    /// Per-app profiles: delay preset + method override per bundleId
    @Published var perAppProfiles: [String: PerAppConfig] = [:] {
        didSet {
            if let data = try? JSONEncoder().encode(perAppProfiles) {
                UserDefaults.standard.set(data, forKey: SettingsKey.perAppProfiles)
            }
            clearDetectionCache()
        }
    }

    @Published var shortcuts: [ShortcutItem] = []
    @Published var isLaunchAtLoginEnabled: Bool = false
    @Published var requiresManualLaunchAtLogin: Bool = false

    // MARK: - Init

    init() {
        // Defaults are registered in App.swift's applicationDidFinishLaunching
        // before AppState.shared is accessed

        // Load all settings from UserDefaults
        let defaults = UserDefaults.standard
        isEnabled = defaults.bool(forKey: SettingsKey.enabled)
        currentMethod = InputMode(rawValue: defaults.integer(forKey: SettingsKey.method)) ?? .telex
        toggleShortcut = KeyboardShortcut.load()
        restoreShortcut = KeyboardShortcut.loadRestoreShortcut()
        secondaryToggleShortcut = KeyboardShortcut.loadSecondaryToggle()
        secondaryToggleShortcutEnabled = defaults.bool(forKey: SettingsKey.secondaryToggleShortcutEnabled)
        perAppModeEnabled = defaults.bool(forKey: SettingsKey.perAppMode)
        autoWShortcut = defaults.bool(forKey: SettingsKey.autoWShortcut)
        bracketShortcut = defaults.bool(forKey: SettingsKey.bracketShortcut)
        restoreShortcutEnabled = defaults.bool(forKey: SettingsKey.restoreShortcutEnabled)
        modernTone = defaults.bool(forKey: SettingsKey.modernTone)
        englishAutoRestore = defaults.bool(forKey: SettingsKey.englishAutoRestore)
        autoCapitalize = defaults.bool(forKey: SettingsKey.autoCapitalize)
        if let excludedApps = defaults.stringArray(forKey: SettingsKey.autoCapitalizeExcludedApps) {
            autoCapitalizeExcludedApps = Set(excludedApps)
        }
        soundEnabled = defaults.bool(forKey: SettingsKey.soundEnabled)
        allowForeignConsonants = defaults.bool(forKey: SettingsKey.allowForeignConsonants)
        advancedMode = defaults.bool(forKey: SettingsKey.advancedMode)
        disablePanelDetection = defaults.bool(forKey: SettingsKey.disablePanelDetection)
        restartOnClose = defaults.bool(forKey: SettingsKey.restartOnClose)
        // Silent load: prevent didSet from calling KeyboardHookManager.restart()
        // during init, which would recursively access AppState.shared and crash.
        isSilentUpdate = true
        sessionTapMode = defaults.bool(forKey: SettingsKey.sessionTapMode)
        isSilentUpdate = false
        if let data = defaults.data(forKey: SettingsKey.perAppProfiles),
           let profiles = try? JSONDecoder().decode([String: PerAppConfig].self, from: data)
        {
            perAppProfiles = profiles
        }

        // Sync settings to Rust engine
        syncAllToEngine()

        // Load complex data
        loadShortcuts()

        // Setup observers and services
        setupObservers()
        setupLaunchAtLoginMonitoring()
    }

    private func syncAllToEngine() {
        RustBridge.setEnabled(isEnabled)
        RustBridge.setMethod(currentMethod.rawValue)
        RustBridge.setSkipWShortcut(!autoWShortcut)
        RustBridge.setBracketShortcut(bracketShortcut)
        RustBridge.setRestoreShortcutEnabled(restoreShortcutEnabled)
        RustBridge.setModernTone(modernTone)
        RustBridge.setEnglishAutoRestore(englishAutoRestore)
        updateAutoCapitalizeEngine()
        RustBridge.setAllowForeignConsonants(allowForeignConsonants)
    }

    /// Update auto-capitalize engine state based on global setting and current app exclusion
    func updateAutoCapitalizeEngine() {
        let currentBundleId = PerAppModeManager.shared.getCurrentBundleId()
            ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let isExcluded = currentBundleId.map { autoCapitalizeExcludedApps.contains($0) } ?? false
        RustBridge.setAutoCapitalize(autoCapitalize && !isExcluded)
    }

    /// Check if an app is excluded from auto-capitalize
    func isAppExcludedFromAutoCapitalize(_ bundleId: String) -> Bool {
        autoCapitalizeExcludedApps.contains(bundleId)
    }

    /// Add an app to auto-capitalize exclusion list
    func excludeAppFromAutoCapitalize(_ bundleId: String) {
        autoCapitalizeExcludedApps.insert(bundleId)
    }

    /// Remove an app from auto-capitalize exclusion list
    func includeAppInAutoCapitalize(_ bundleId: String) {
        autoCapitalizeExcludedApps.remove(bundleId)
    }

    /// Track global enabled state before per-app profile override, so we can restore on app switch
    private var profileSavedEnabled: Bool?

    /// Apply per-app profile override when switching apps.
    ///
    /// State machine: Tắt → saves enabled → Bật → force enable
    ///                → No profile → restores from UserDefaults (ground truth)
    ///
    /// Runs BEFORE restorePerAppMode in handleAppSwitch. restorePerAppMode checks
    /// profile.enabled to avoid re-enabling GN when profile has it disabled.
    func applyPerAppProfile(bundleId: String) {
        guard advancedMode, let profile = perAppProfiles[bundleId] else {
            restoreProfileDefaults()
            return
        }

        // No overrides — restore defaults
        guard profile.enabledState != 0 else {
            restoreProfileDefaults()
            return
        }

        // "Tắt" — disable Vietnamese for this app
        if profile.enabledState == -1 {
            if profileSavedEnabled == nil {
                profileSavedEnabled = isEnabled
            }
            RustBridge.setEnabled(false)
            EngineRouter.shared.setEnabled(false, explicit: true) // LEANKEYS-HOOK: language-sync
            setEnabledSilently(false)
            return
        }

        // "Bật" — force enable Vietnamese for this app
        if profile.enabledState == 1 {
            if profileSavedEnabled == nil {
                profileSavedEnabled = isEnabled
            }
            RustBridge.setEnabled(true)
            setEnabledSilently(true)
        }
    }

    private func restoreProfileDefaults() {
        if profileSavedEnabled != nil {
            profileSavedEnabled = nil
            let ground = UserDefaults.standard.bool(forKey: SettingsKey.enabled)
            RustBridge.setEnabled(ground)
            setEnabledSilently(ground)
        }
    }

    private func loadShortcuts() {
        if let data = UserDefaults.standard.data(forKey: SettingsKey.shortcuts),
           let saved = try? JSONDecoder().decode([ShortcutItem].self, from: data)
        {
            shortcuts = saved
        } else {
            shortcuts = [
                ShortcutItem(key: "vn", value: "Việt Nam", isEnabled: false),
                ShortcutItem(key: "hn", value: "Hà Nội", isEnabled: false),
                ShortcutItem(key: "hcm", value: "Hồ Chí Minh", isEnabled: false),
                ShortcutItem(key: "tphcm", value: "Thành phố Hồ Chí Minh", isEnabled: false),
            ]
        }
    }

    // MARK: - Observers

    private func setupObservers() {
        NotificationCenter.default.publisher(for: .inputSourceChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        $shortcuts
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] shortcuts in
                let validShortcuts = shortcuts.filter { !$0.key.isEmpty && !$0.value.isEmpty }
                self?.syncShortcutsToEngine(validShortcuts)
                if let data = try? JSONEncoder().encode(shortcuts) {
                    UserDefaults.standard.set(data, forKey: SettingsKey.shortcuts)
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Launch at Login

    private func setupLaunchAtLoginMonitoring() {
        isLaunchAtLoginEnabled = LaunchAtLoginManager.shared.isEnabled

        // Auto-enable unless user has explicitly disabled it
        let userDisabled = UserDefaults.standard.bool(forKey: SettingsKey.launchAtLoginUserDisabled)
        if !userDisabled, !isLaunchAtLoginEnabled {
            autoEnableLaunchAtLogin()
        }

        // Replaces polling timer that caused backgroundtaskmanagementd spam (#351)
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshLaunchAtLoginStatus()
        }
    }

    private func autoEnableLaunchAtLogin() {
        do {
            try LaunchAtLoginManager.shared.enable()
            refreshLaunchAtLoginStatus()
            requiresManualLaunchAtLogin = false
        } catch {
            // Auto-enable failed, will retry on next launch
            requiresManualLaunchAtLogin = true
        }
    }

    func refreshLaunchAtLoginStatus() {
        let newStatus = LaunchAtLoginManager.shared.isEnabled
        if newStatus != isLaunchAtLoginEnabled {
            isLaunchAtLoginEnabled = newStatus
        }
        // Clear manual requirement flag if now enabled
        if isLaunchAtLoginEnabled {
            requiresManualLaunchAtLogin = false
        }
    }

    func enableLaunchAtLogin() {
        do {
            try LaunchAtLoginManager.shared.enable()
            refreshLaunchAtLoginStatus()
            requiresManualLaunchAtLogin = false
            // Clear user disabled flag when user explicitly enables
            UserDefaults.standard.set(false, forKey: SettingsKey.launchAtLoginUserDisabled)
        } catch {
            requiresManualLaunchAtLogin = true
            openLoginItemsSettings()
        }
    }

    func disableLaunchAtLogin() {
        do {
            try LaunchAtLoginManager.shared.disable()
            refreshLaunchAtLoginStatus()
            // Track that user explicitly disabled
            UserDefaults.standard.set(true, forKey: SettingsKey.launchAtLoginUserDisabled)
        } catch {
            // If disable fails, open settings for manual action
            openLoginItemsSettings()
        }
    }

    func toggleLaunchAtLogin(_ enabled: Bool) {
        if enabled {
            enableLaunchAtLogin()
        } else {
            disableLaunchAtLogin()
        }
    }

    func openLoginItemsSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Per-App Mode

    func savePerAppMode(bundleId: String, enabled: Bool) {
        var modes = UserDefaults.standard.dictionary(forKey: SettingsKey.perAppModes) as? [String: Bool] ?? [:]
        modes[bundleId] = enabled // Store both ON and OFF so hasPerAppMode works correctly
        UserDefaults.standard.set(modes, forKey: SettingsKey.perAppModes)
    }

    func getPerAppMode(bundleId: String) -> Bool {
        let modes = UserDefaults.standard.dictionary(forKey: SettingsKey.perAppModes) as? [String: Bool] ?? [:]
        return modes[bundleId] ?? true
    }

    func hasPerAppMode(bundleId: String) -> Bool {
        let modes = UserDefaults.standard.dictionary(forKey: SettingsKey.perAppModes) as? [String: Bool] ?? [:]
        return modes[bundleId] != nil
    }

    func setEnabledSilently(_ enabled: Bool) {
        isSilentUpdate = true
        isEnabled = enabled
        isSilentUpdate = false
    }

    func toggle() {
        isEnabled.toggle()
    }

    func setMethod(_ method: InputMode) {
        currentMethod = method
    }

    // MARK: - Shortcuts

    func syncShortcutsToEngine(_ validShortcuts: [ShortcutItem]? = nil) {
        let toSync = validShortcuts ?? shortcuts.filter { !$0.key.isEmpty && !$0.value.isEmpty }
        RustBridge.syncShortcuts(toSync.map { ($0.key, $0.value, $0.isEnabled) })
        EngineRouter.shared.setShortcuts(toSync.filter(\.isEnabled).map { ($0.key, $0.value) }) // LEANKEYS-HOOK: shortcut-store
    }
    // LEANKEYS-HOOK-BEGIN: shortcut-store
    /// Adds a gõ tắt the user accepted from a LeanKeys suggestion; the $shortcuts sink saves it and syncs both
    /// engines. False when the trigger is empty or already used, whatever its case.
    func addLearnedShortcut(trigger: String, text: String) -> Bool {
        let key = trigger.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !text.isEmpty,
              !shortcuts.contains(where: { $0.key.lowercased() == key.lowercased() }) else { return false }
        shortcuts.append(ShortcutItem(key: key, value: text, isEnabled: true))
        return true
    }
    // LEANKEYS-HOOK-END

    func exportShortcuts() -> String {
        var lines = [";Gõ Nhanh - Bảng gõ tắt"]
        for shortcut in shortcuts where !shortcut.key.isEmpty {
            // Issue #343: Escape newlines in export so format stays one-entry-per-line
            let escapedValue = shortcut.value.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
            lines.append("\(shortcut.key):\(escapedValue)")
        }
        return lines.joined(separator: "\n")
    }

    func importShortcuts(from content: String) -> Int {
        let lines = content.components(separatedBy: .newlines)
        var imported = 0
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix(";"),
                  let colonIndex = trimmed.firstIndex(of: ":") else { continue }
            let trigger = String(trimmed[..<colonIndex]).trimmingCharacters(in: .whitespaces)
            let rawValue = String(trimmed[trimmed.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
            guard !trigger.isEmpty else { continue }
            // Issue #343: Unescape \\n → newline, \\\\ → backslash
            let replacement = Self.unescapeShortcutValue(rawValue)
            if let idx = shortcuts.firstIndex(where: { $0.key == trigger }) {
                shortcuts[idx].value = replacement
                shortcuts[idx].isEnabled = true
            } else {
                shortcuts.append(ShortcutItem(key: trigger, value: replacement, isEnabled: true))
            }
            imported += 1
        }
        return imported
    }

    /// Unescape shortcut value: \\n → newline, \\\\ → backslash
    private static func unescapeShortcutValue(_ value: String) -> String {
        var result = ""
        var chars = value.makeIterator()
        while let ch = chars.next() {
            if ch == "\\" {
                if let next = chars.next() {
                    switch next {
                    case "n": result.append("\n")
                    case "r": result.append("\r")
                    case "\\": result.append("\\")
                    default: result.append("\\"); result.append(next)
                    }
                } else {
                    result.append("\\")
                }
            } else {
                result.append(ch)
            }
        }
        return result
    }
}

// MARK: - Models

struct ShortcutItem: Identifiable, Codable {
    var id = UUID()
    var key: String
    var value: String
    var isEnabled: Bool = true
}

// MARK: - View Modifiers

struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.controlBackgroundColor).opacity(0.5)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5))
    }
}

extension View {
    func cardBackground() -> some View {
        modifier(CardBackground())
    }
}

// MARK: - Reusable Components

struct SettingsRow<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        HStack { content }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
    }
}

struct SettingsToggleRow: View {
    let title: String
    let subtitle: String?
    let indented: Bool
    let weight: Font.Weight // LEANKEYS-HOOK: settings-engine
    @Binding var isOn: Bool

    init(_ title: String, subtitle: String? = nil, indented: Bool = false, weight: Font.Weight = .regular, isOn: Binding<Bool>) { // LEANKEYS-HOOK: settings-engine
        self.title = title
        self.subtitle = subtitle
        self.indented = indented
        self.weight = weight // LEANKEYS-HOOK: settings-engine
        _isOn = isOn
    }

    var body: some View {
        SettingsRow {
            HStack(spacing: 6) {
                if indented {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: 10))
                        .foregroundColor(Color(NSColor.tertiaryLabelColor))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: weight)) // LEANKEYS-HOOK: settings-engine
                    if let subtitle {
                        Text(subtitle).font(.system(size: 11)).foregroundColor(Color(NSColor.secondaryLabelColor))
                    }
                }
            }
            Spacer()
            Toggle("", isOn: $isOn).toggleStyle(.switch).controlSize(.mini).labelsHidden() // LEANKEYS-HOOK: settings-engine
        }
    }
}

struct KeyCap: View {
    let text: String

    private var displayText: String {
        switch text {
        // Modifiers
        case "⌃": "⌃ control"
        case "⌥": "⌥ option"
        case "⇧": "⇧ shift"
        case "⌘": "⌘ command"
        case "fn": "fn"
        // Special keys
        case "Esc", "⎋": "⎋ esc"
        case "Tab", "⇥": "⇥ tab"
        case "Space", "␣": "␣ space"
        case "Return", "↩": "↩ return"
        case "Delete", "⌫": "⌫ delete"
        default: text
        }
    }

    var body: some View {
        Text(displayText)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(Color(NSColor.secondaryLabelColor))
            .lineLimit(1)
            .fixedSize() // Keep "⌃ control" on one line even when the row is width-constrained
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color(NSColor.controlBackgroundColor).opacity(0.8)))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5))
    }
}

// MARK: - Sheet Components

struct SheetHeader: View {
    let title: String
    let subtitle: String?

    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 15, weight: .semibold))
            if let subtitle {
                Text(subtitle).font(.system(size: 11)).foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

struct SheetToolbar<Actions: View>: View {
    @Environment(\.dismiss) private var dismiss
    let actions: Actions?

    init(@ViewBuilder actions: () -> Actions) {
        self.actions = actions()
    }

    init() where Actions == EmptyView {
        actions = nil
    }

    var body: some View {
        HStack(spacing: 12) {
            if let actions {
                actions
            }
            Spacer()
            Button("Xong") { dismiss() }
                .keyboardShortcut(.escape, modifiers: [])
        }
        .font(.system(size: 12))
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

struct ClickableTextField: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.font = .systemFont(ofSize: 13)
        textField.delegate = context.coordinator
        textField.cell?.lineBreakMode = .byTruncatingTail
        return textField
    }

    func updateNSView(_ nsView: NSTextField, context _: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: ClickableTextField
        init(_ parent: ClickableTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let textField = obj.object as? NSTextField else { return }
            parent.text = textField.stringValue
        }
    }
}

struct DeleteButton: View {
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "trash")
                .font(.system(size: 11))
                .foregroundColor(hovered ? Color(NSColor.secondaryLabelColor) : Color(NSColor.tertiaryLabelColor))
        }
        .buttonStyle(.borderless)
        .onHover { hovered = $0 }
        .help("Xoá")
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context _: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context _: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - Main Settings View

struct MainSettingsView: View {
    @ObservedObject private var appState = AppState.shared
    @State private var selectedPage: NavigationPage = .settings
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                VisualEffectBackground(material: .sidebar, blendingMode: .behindWindow)
                sidebar
            }
            .frame(width: 200)

            ZStack {
                if colorScheme == .dark {
                    VisualEffectBackground(material: .headerView, blendingMode: .behindWindow)
                } else {
                    Color(NSColor.windowBackgroundColor)
                }
                content
            }
        }
        .ignoresSafeArea()
        .frame(width: 700, height: 480)
        .onReceive(NotificationCenter.default.publisher(for: .showSettingsPage)) { notification in
            if let page = notification.object as? NavigationPage {
                selectedPage = page
            }
        }
        .onChange(of: appState.advancedMode) { newValue in
            if !newValue, selectedPage == .advanced {
                selectedPage = .settings
            }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                Image(nsImage: AppMetadata.logo).resizable().frame(width: 96, height: 96)
                Text(AppMetadata.name).font(.system(size: 20, weight: .bold))
                UpdateBadgeView()
            }
            .padding(.top, 40)

            Spacer()

            VStack(spacing: 4) {
                ForEach(NavigationPage.allCases.filter { $0 != .advanced || appState.advancedMode }, id: \.self) { page in
                    NavButton(page: page, isSelected: selectedPage == page) { selectedPage = page }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 20)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch selectedPage {
        case .settings:
            ScrollView(showsIndicators: false) {
                SettingsPageView(appState: appState).padding(28)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .advanced:
            AdvancedSettingsView(appState: appState).padding(28)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .about:
            AboutPageView().padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Update Badge

struct UpdateBadgeView: View {
    @ObservedObject private var updateManager = UpdateManager.shared
    @State private var hovered = false
    @State private var rotation: Double = 0
    /// The badge's words after the version. "Mới nhất" only after a check said so. // LEANKEYS-HOOK: copy
    private var statusText: String { // LEANKEYS-HOOK: copy
        if updateManager.isChecking { return "Đang kiểm tra…" } // LEANKEYS-HOOK: copy
        if updateManager.isReadyToInstall { return "Cài bản mới" } // LEANKEYS-HOOK: copy
        if updateManager.updateAvailable { return "Có bản mới" } // LEANKEYS-HOOK: copy
        if case .upToDate = updateManager.state { return "Mới nhất" } // LEANKEYS-HOOK: copy
        return "Kiểm tra cập nhật" // LEANKEYS-HOOK: copy
    } // LEANKEYS-HOOK: copy

    var body: some View {
        Button { // LEANKEYS-HOOK: copy (a button: keyboard focus, Space, and VoiceOver's button trait)
            if updateManager.isReadyToInstall { // LEANKEYS-HOOK: copy
                updateManager.restartToUpdate() // LEANKEYS-HOOK: copy
            } else { // LEANKEYS-HOOK: copy
                updateManager.checkForUpdatesManually() // LEANKEYS-HOOK: copy
            } // LEANKEYS-HOOK: copy
        } label: { // LEANKEYS-HOOK: copy
        HStack(spacing: 3) {
            Text("v\(AppMetadata.version)")
            if updateManager.isChecking {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .rotationEffect(.degrees(rotation))
                    .onAppear { withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) { rotation = 360 } }
                    .onDisappear { rotation = 0 }
                Text(statusText) // LEANKEYS-HOOK: copy
            } else if updateManager.isReadyToInstall {
                Image(systemName: "arrow.uturn.forward.circle.fill").font(.system(size: 12)).foregroundColor(.orange)
                Text(statusText) // LEANKEYS-HOOK: copy
            } else if updateManager.updateAvailable {
                Image(systemName: "arrow.down.circle.fill").font(.system(size: 12)).foregroundColor(.blue)
                Text(statusText) // LEANKEYS-HOOK: copy
            } else if case .upToDate = updateManager.state { // LEANKEYS-HOOK: copy
                Image(systemName: "checkmark.circle.fill").font(.system(size: 12)).foregroundColor(.green)
                Text("Mới nhất")
            } else { // LEANKEYS-HOOK: copy
                Image(systemName: "arrow.clockwise").font(.system(size: 12)) // LEANKEYS-HOOK: copy
                Text(statusText) // LEANKEYS-HOOK: copy
            }
        }
        .font(.system(size: 11))
        .foregroundColor(Color(NSColor.secondaryLabelColor)) // LEANKEYS-HOOK: copy
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(hovered ? Color(NSColor.controlBackgroundColor).opacity(0.5) : Color.clear))
        .contentShape(Capsule()) // LEANKEYS-HOOK: copy
        } // LEANKEYS-HOOK: copy
        .onHover { h in
            hovered = h
            if h {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .buttonStyle(.plain) // LEANKEYS-HOOK: copy
        .accessibilityLabel(Text("Phiên bản \(AppMetadata.version). \(statusText)")) // LEANKEYS-HOOK: copy
    }
}

// MARK: - Nav Button

struct NavButton: View {
    let page: NavigationPage
    let isSelected: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: page.icon)
                .font(.system(size: 14))
                .foregroundColor(isSelected ? Color(NSColor.labelColor) : Color(NSColor.secondaryLabelColor))
                .frame(width: 20)
            Text(page.rawValue)
                .font(.system(size: 13))
                .foregroundColor(isSelected ? Color(NSColor.labelColor) : Color(NSColor.secondaryLabelColor))
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color(NSColor.controlBackgroundColor).opacity(0.6) :
                    hovered ? Color(NSColor.controlBackgroundColor).opacity(0.4) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .onTapGesture { action() }
    }
}

// MARK: - Settings Page

struct SettingsPageView: View {
    @ObservedObject var appState: AppState
    var part: SettingsPart = .general // LEANKEYS-HOOK: settings-engine
    @State private var isRecordingShortcut = false
    @State private var isRecordingSecondaryShortcut = false
    @State private var isRecordingRestoreShortcut = false
    @State private var showShortcutsSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if part == .general { // LEANKEYS-HOOK: settings-engine
                StatusCard(snapshot: appState.leanStatusSnapshot) // LEANKEYS-HOOK: settings-engine (replaces Gõ Nhanh's Secure Input banner; keep it out on upstream sync)
            } // LEANKEYS-HOOK: settings-engine

            // Bộ gõ
            if part == .general { // LEANKEYS-HOOK: settings-engine
            VStack(spacing: 0) {
                SettingsToggleRow("Bộ gõ tiếng Việt", weight: .semibold, isOn: $appState.isEnabled) // LEANKEYS-HOOK: settings-engine
                Divider().padding(.leading, 12)
                inputMethodRow
                if appState.currentMethod == .telex {
                    if SettingsLayout.showsGoNhanhOnlySettings(active: EngineRouter.shared.active) { // LEANKEYS-HOOK: settings-engine
                    Divider().padding(.leading, 12)
                    SettingsToggleRow("Gõ W thành Ư", indented: true, isOn: $appState.autoWShortcut)
                    Divider().padding(.leading, 12)
                    SettingsToggleRow("Gõ [ ] thành Ơ Ư", indented: true, isOn: $appState.bracketShortcut)
                    Divider().padding(.leading, 12)
                    englishAutoRestoreRow
                    } // LEANKEYS-HOOK: settings-engine
                }
            }
            .cardBackground()
            } // LEANKEYS-HOOK: settings-engine

            // Phím tắt
            if part == .shortcuts { // LEANKEYS-HOOK: settings-engine
            VStack(spacing: 0) {
                ShortcutRecorderRow(shortcut: $appState.toggleShortcut,
                                    isRecording: $isRecordingShortcut)
                Divider().padding(.leading, 12)
                ShortcutRecorderRow(shortcut: $appState.secondaryToggleShortcut,
                                    isRecording: $isRecordingSecondaryShortcut,
                                    title: "Phím tắt bật/tắt thứ hai",
                                    subtitle: "Khi bàn phím rời không có fn",
                                    isEnabled: $appState.secondaryToggleShortcutEnabled,
                                    duplicateOf: appState.toggleShortcut)
                Divider().padding(.leading, 12)
                RestoreShortcutRecorderRow(
                    shortcut: $appState.restoreShortcut,
                    isEnabled: $appState.restoreShortcutEnabled,
                    isRecording: $isRecordingRestoreShortcut
                )
            }
            .cardBackground()
            } // LEANKEYS-HOOK: settings-engine

            // Quy tắc gõ
            if part == .general { // LEANKEYS-HOOK: settings-engine
            VStack(spacing: 0) {
                SettingsToggleRow("Đặt dấu kiểu mới", subtitle: "oà thay vì òa, uý thay vì úy", isOn: $appState.modernTone)
                Divider().padding(.leading, 12)
                SettingsToggleRow("Cho phép phụ âm ngoại", subtitle: "z, w, j, f làm phụ âm đầu", isOn: $appState.allowForeignConsonants)
                if SettingsLayout.showsGoNhanhOnlySettings(active: EngineRouter.shared.active) { // LEANKEYS-HOOK: settings-engine
                Divider().padding(.leading, 12)
                AutoCapitalizeRow(appState: appState)
                } // LEANKEYS-HOOK: settings-engine
            }
            .cardBackground()

            // Mở rộng
            VStack(spacing: 0) {
                shortcutsRow
                Divider().padding(.leading, 12) // LEANKEYS-HOOK: settings-engine
                LearnSettingsSection(model: .shared, part: .general) // LEANKEYS-HOOK: settings-engine
                Divider().padding(.leading, 12)
                SettingsToggleRow("Nhớ trạng thái theo app", subtitle: "Tự bật/tắt khi chuyển ứng dụng", isOn: $appState.perAppModeEnabled)
                Divider().padding(.leading, 12)
                SettingsToggleRow("Âm thanh khi bật/tắt", isOn: $appState.soundEnabled)
            }
            .cardBackground()

            // Hệ thống
            VStack(spacing: 0) {
                LaunchAtLoginToggleRow(appState: appState)
                if SettingsLayout.showsAdvancedModeToggle { // LEANKEYS-HOOK: settings-engine
                Divider().padding(.leading, 12)
                SettingsToggleRow("Hiển thị cài đặt nâng cao", isOn: $appState.advancedMode)
                } // LEANKEYS-HOOK: settings-engine
            }
            .cardBackground()
            } // LEANKEYS-HOOK: settings-engine

            Spacer()
        }
        .sheet(isPresented: $showShortcutsSheet) { ShortcutsSheet(appState: appState) }
    }

    private var inputMethodRow: some View {
        SettingsRow {
            Text("Kiểu gõ").font(.system(size: 13))
            Spacer()
            Picker("", selection: $appState.currentMethod) {
                ForEach(InputMode.allCases, id: \.self) { Text($0.name).tag($0) }
            }
            .labelsHidden()
            .frame(width: 100)
        }
    }

    private var englishAutoRestoreRow: some View {
        SettingsToggleRow("Tự khôi phục tiếng Anh", indented: true, isOn: $appState.englishAutoRestore)
    }

    private var shortcutsRow: some View {
        ShortcutsRowView(appState: appState) { showShortcutsSheet = true }
    }
}

// MARK: - Shortcuts Sheet

struct ShortcutsSheet: View {
    @ObservedObject var appState: AppState

    // Form state
    @State private var formKey: String = ""
    @State private var formValue: String = ""
    @State private var editingId: UUID? = nil // For form editing
    @State private var selectedIds: Set<UUID> = [] // For table multi-selection

    private var isEditing: Bool {
        editingId != nil
    }

    private var canSave: Bool {
        !formKey.isEmpty && !formValue.isEmpty
    }

    private var subtitle: String {
        let enabled = appState.shortcuts.filter(\.isEnabled).count
        let total = appState.shortcuts.count
        return "\(total) mục · \(enabled) đang bật"
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader("Bảng gõ tắt", subtitle: subtitle)
            Divider()
            formSection
            Divider()
            tableContent
            Divider()
            SheetToolbar {
                Button(action: importShortcuts) {
                    Label("Nhập", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderless)
                Button(action: exportShortcuts) {
                    Label("Xuất", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderless)
                .disabled(appState.shortcuts.isEmpty)
            }
        }
        .frame(width: 460, height: 400)
    }

    private var formSection: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Viết tắt").font(.system(size: 11)).foregroundColor(.secondary)
                    TextField("vd: tphcm", text: $formKey)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text("Nội dung").font(.system(size: 11)).foregroundColor(.secondary)
                        Text("(⌥↩ xuống dòng)").font(.system(size: 10)).foregroundColor(Color(NSColor.secondaryLabelColor)) // LEANKEYS-HOOK: copy
                    }
                    // Issue #343: TextEditor for multiline replacement (supports newlines)
                    TextEditor(text: $formValue)
                        .font(.system(size: 13))
                        .frame(height: 44)
                        .scrollContentBackground(.hidden)
                        .padding(4)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color(NSColor.textBackgroundColor)))
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5))
                        .overlay(alignment: .topLeading) {
                            if formValue.isEmpty {
                                Text("vd: Thành phố Hồ Chí Minh")
                                    .font(.system(size: 13))
                                    .foregroundColor(Color(NSColor.placeholderTextColor))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .allowsHitTesting(false)
                            }
                        }
                }
            }
            HStack(spacing: 8) {
                if isEditing {
                    Button("Huỷ") { clearForm() }
                    Button("Xoá", role: .destructive) { deleteSelected() }
                        .foregroundColor(.red)
                }
                Spacer()
                Button(isEditing ? "Cập nhật" : "Thêm") { saveForm() }
                    .disabled(!canSave)
                    .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }

    @ViewBuilder
    private var tableContent: some View {
        if appState.shortcuts.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "text.badge.plus").font(.system(size: 32)).foregroundColor(.secondary)
                Text("Chưa có từ viết tắt").font(.system(size: 13)).foregroundColor(.secondary)
                Text("Điền form ở trên để thêm mới").font(.system(size: 11)).foregroundColor(Color(NSColor.secondaryLabelColor)) // LEANKEYS-HOOK: copy
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Table(appState.shortcuts, selection: $selectedIds) {
                TableColumn("") { item in
                    Toggle("", isOn: Binding(
                        get: { item.isEnabled },
                        set: { newValue in
                            if let idx = appState.shortcuts.firstIndex(where: { $0.id == item.id }) {
                                appState.shortcuts[idx].isEnabled = newValue
                            }
                        }
                    ))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                }
                .width(24)

                TableColumn("Viết tắt") { item in
                    Text(item.key)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(item.isEnabled ? .primary : .secondary)
                }
                .width(min: 80, ideal: 100, max: 140)

                TableColumn("Nội dung") { item in
                    // Issue #343: Show multiline indicator, display first line in table
                    Text(item.value.contains("\n") ? item.value.replacingOccurrences(of: "\n", with: " ↵ ") : item.value)
                        .font(.system(size: 12))
                        .foregroundColor(item.isEnabled ? .primary : .secondary)
                        .lineLimit(1)
                }

                TableColumn("") { item in
                    DeleteButton { deleteItem(item.id) }
                }
                .width(28)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
            .onDeleteCommand { deleteSelected() }
            .onChange(of: selectedIds) { newSelection in
                // Load single selection into form for editing
                if newSelection.count == 1, let id = newSelection.first,
                   let item = appState.shortcuts.first(where: { $0.id == id })
                {
                    selectItem(item)
                } else {
                    clearForm()
                }
            }
        }
    }

    private func selectItem(_ item: ShortcutItem) {
        editingId = item.id
        formKey = item.key
        formValue = item.value
    }

    private func clearForm() {
        editingId = nil
        formKey = ""
        formValue = ""
    }

    private func saveForm() {
        if let id = editingId, let idx = appState.shortcuts.firstIndex(where: { $0.id == id }) {
            // Update existing - only key and value, keep isEnabled unchanged
            appState.shortcuts[idx].key = formKey
            appState.shortcuts[idx].value = formValue
        } else {
            // Add new - default enabled
            appState.shortcuts.append(ShortcutItem(key: formKey, value: formValue, isEnabled: true))
        }
        clearForm()
    }

    private func deleteSelected() {
        guard !selectedIds.isEmpty else { return }
        appState.shortcuts.removeAll { selectedIds.contains($0.id) }
        selectedIds.removeAll()
        clearForm()
    }

    private func deleteItem(_ id: UUID) {
        appState.shortcuts.removeAll { $0.id == id }
        if editingId == id {
            clearForm()
        }
        selectedIds.remove(id)
    }

    private func importShortcuts() {
        // Dispatch panel creation to next run loop to prevent UI blocking
        DispatchQueue.main.async { [weak appState] in
            let panel = NSOpenPanel()
            panel.title = "Nhập từ viết tắt"
            panel.allowedContentTypes = [.plainText]
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false
            panel.begin { response in
                guard response == .OK, let url = panel.url else { return }
                // Read file on background thread
                DispatchQueue.global(qos: .userInitiated).async {
                    guard let content = try? String(contentsOf: url, encoding: .utf8) else { return }
                    DispatchQueue.main.async {
                        _ = appState?.importShortcuts(from: content)
                    }
                }
            }
        }
    }

    private func exportShortcuts() {
        // Dispatch panel creation to next run loop to prevent UI blocking
        DispatchQueue.main.async { [weak appState] in
            let panel = NSSavePanel()
            panel.title = "Xuất từ viết tắt"
            panel.nameFieldStringValue = "gonhanh-shortcuts.txt"
            panel.allowedContentTypes = [.plainText]
            panel.begin { response in
                guard response == .OK, let url = panel.url else { return }
                // Write file on background thread
                DispatchQueue.global(qos: .userInitiated).async {
                    let content = appState?.exportShortcuts() ?? ""
                    try? content.write(to: url, atomically: true, encoding: .utf8)
                }
            }
        }
    }
}

// MARK: - About Page

struct AboutPageView: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            VStack(spacing: 12) {
                Image(nsImage: AppMetadata.logo).resizable().frame(width: 80, height: 80)
                Text(AppMetadata.name).font(.system(size: 20, weight: .bold))
                Text(AppMetadata.tagline).font(.system(size: 13)).foregroundColor(Color(NSColor.secondaryLabelColor)) // LEANKEYS-HOOK: copy
                Text("Phiên bản \(AppMetadata.version)").font(.system(size: 12)).foregroundColor(Color(NSColor.secondaryLabelColor)) // LEANKEYS-HOOK: copy
            }
            HStack(spacing: 12) {
                // LEANKEYS-HOOK: about (Gõ Nhanh's sponsor link removed; Gõ Nhanh is credited in AcknowledgementsSection)
                AboutLink(icon: "ant", title: "Báo lỗi", url: AppMetadata.issuesURL)
                AboutLink(icon: "chevron.left.forwardslash.chevron.right", title: "GitHub", url: AppMetadata.repository)
            }
            // LEANKEYS-HOOK: about (Gõ Nhanh's launch badges removed)
            AcknowledgementsSection() // LEANKEYS-HOOK: about
            Spacer()
            Spacer().frame(height: 12) // LEANKEYS-HOOK: about (Gõ Nhanh's "Phát triển bởi Kha Phan" line removed)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct AboutLink: View {
    let icon: String
    let title: String
    let url: String
    var iconColor: Color?
    @State private var hovered = false

    var body: some View {
        Link(destination: URL(string: url)!) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(iconColor)
                Text(title).font(.system(size: 11))
            }
            .frame(width: 80, height: 60)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor).opacity(hovered ? 0.8 : 0.5)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .foregroundColor(Color(NSColor.labelColor))
        .onHover { hovered = $0 }
    }
}

struct AuthorLink: View {
    let name: String
    let url: String
    @State private var hovered = false

    var body: some View {
        Link(destination: URL(string: url)!) { Text(name).underline(hovered) }
            .buttonStyle(.plain)
            .foregroundColor(Color.accentColor)
            .onHover { hovered = $0 }
    }
}

struct PlatformBadge: View {
    let title: String
    let icon: String
    let url: String
    @Environment(\.colorScheme) private var colorScheme
    @State private var hovered = false

    var body: some View {
        Link(destination: URL(string: url)!) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                Image(systemName: "arrowtriangle.up.fill")
                    .font(.system(size: 6))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
            )
            .opacity(hovered ? 0.7 : 1.0)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .onHover { hovered = $0 }
    }
}

// MARK: - Shortcut Recorder

private let systemShortcuts: Set<String> = [
    "⌘Space", "⌘⇥", "⌘Q", "⌘W", "⌘H", "⌘M",
    "⌘⇧3", "⌘⇧4", "⌘⇧5",
    "⌃↑", "⌃↓", "⌃←", "⌃→",
]

struct ShortcutRecorderRow: View {
    @Binding var shortcut: KeyboardShortcut
    @Binding var isRecording: Bool
    var title = "Bật/tắt bộ gõ"
    var subtitle = "Nhấn để thay đổi"
    /// When provided, shows an on/off switch and blocks recording while off.
    var isEnabled: Binding<Bool>?
    /// Another shortcut this one must not equal (e.g. the primary toggle for the secondary row).
    var duplicateOf: KeyboardShortcut?
    @State private var hovered = false
    @State private var recordedObserver: NSObjectProtocol?
    @State private var cancelledObserver: NSObjectProtocol?
    @State private var windowObserver: NSObjectProtocol?

    private var enabled: Bool { isEnabled?.wrappedValue ?? true }

    private var conflictMessage: String? {
        if let other = duplicateOf, other == shortcut {
            return "Trùng với phím tắt bật/tắt chính"
        }
        if systemShortcuts.contains(shortcut.displayParts.joined()) {
            return "Phím tắt này có thể xung đột với hệ thống"
        }
        return nil
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(Color(NSColor.secondaryLabelColor))
            }
            Spacer()
            HStack(spacing: 8) {
                shortcutDisplay
                if let isEnabled {
                    Toggle("", isOn: isEnabled)
                        .toggleStyle(.switch)
                        .controlSize(.mini) // LEANKEYS-HOOK: settings-engine
                        .labelsHidden()
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background((hovered || isRecording) ? Color(NSColor.controlBackgroundColor).opacity(0.3) : .clear)
        .contentShape(Rectangle())
        .onHover { hovered = enabled && $0 }
        .onTapGesture {
            guard enabled else { return }
            isRecording ? stopRecording() : startRecording()
        }
        .onDisappear { stopRecording() }
        .onChange(of: enabled) { _ in
            if isRecording {
                stopRecording()
            }
        }
    }

    private var shortcutDisplay: some View {
        HStack(spacing: 4) {
            if isRecording {
                Text("Nhấn phím...")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.accentColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 4).stroke(Color.accentColor, lineWidth: 1))
            } else {
                ForEach(shortcut.displayParts, id: \.self) { KeyCap(text: $0) }
                if let conflictMessage {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.orange)
                        .help(conflictMessage)
                }
            }
        }
        .opacity(enabled ? 1.0 : 0.5)
    }

    private func startRecording() {
        isRecording = true
        recordedObserver = NotificationCenter.default.addObserver(forName: .shortcutRecorded, object: nil, queue: .main) { notification in
            if let captured = notification.object as? KeyboardShortcut {
                shortcut = captured
            }
            stopRecording()
        }
        cancelledObserver = NotificationCenter.default.addObserver(forName: .shortcutRecordingCancelled, object: nil, queue: .main) { _ in stopRecording() }
        windowObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: nil, queue: .main) { _ in stopRecording() }
        startShortcutRecording()
    }

    private func stopRecording() {
        stopShortcutRecording()
        [recordedObserver, cancelledObserver, windowObserver].compactMap { $0 }.forEach { NotificationCenter.default.removeObserver($0) }
        recordedObserver = nil
        cancelledObserver = nil
        windowObserver = nil
        isRecording = false
    }
}

// MARK: - Restore Shortcut Recorder Row

struct RestoreShortcutRecorderRow: View {
    @Binding var shortcut: KeyboardShortcut
    @Binding var isEnabled: Bool
    @Binding var isRecording: Bool
    @State private var hovered = false
    @State private var recordedObserver: NSObjectProtocol?
    @State private var cancelledObserver: NSObjectProtocol?
    @State private var windowObserver: NSObjectProtocol?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Hoàn tác dấu vừa gõ").font(.system(size: 13))
                Text("Nhấn để thay đổi")
                    .font(.system(size: 11))
                    .foregroundColor(Color(NSColor.secondaryLabelColor))
            }
            Spacer()
            HStack(spacing: 8) {
                shortcutDisplay
                Toggle("", isOn: $isEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.mini) // LEANKEYS-HOOK: settings-engine
                    .labelsHidden()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background((hovered || isRecording) ? Color(NSColor.controlBackgroundColor).opacity(0.3) : .clear)
        .contentShape(Rectangle())
        .onHover { hovered = isEnabled && $0 } // Only hover effect when enabled
        .onTapGesture {
            guard isEnabled else { return } // Disable click when OFF
            isRecording ? stopRecording() : startRecording()
        }
        .onDisappear { stopRecording() }
        .onChange(of: isEnabled) { _ in
            if isRecording {
                stopRecording()
            }
        }
    }

    private var shortcutDisplay: some View {
        HStack(spacing: 4) {
            if isRecording {
                Text("Nhấn phím...")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.accentColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 4).stroke(Color.accentColor, lineWidth: 1))
            } else {
                ForEach(shortcut.displayParts, id: \.self) { KeyCap(text: $0) }
            }
        }
        .opacity(isEnabled ? 1.0 : 0.5)
    }

    private func startRecording() {
        isRecording = true
        recordedObserver = NotificationCenter.default.addObserver(forName: .shortcutRecorded, object: nil, queue: .main) { notification in
            if let captured = notification.object as? KeyboardShortcut {
                shortcut = captured
            }
            stopRecording()
        }
        cancelledObserver = NotificationCenter.default.addObserver(forName: .shortcutRecordingCancelled, object: nil, queue: .main) { _ in stopRecording() }
        windowObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: nil, queue: .main) { _ in stopRecording() }
        startRestoreShortcutRecording() // Use restore-specific recording that allows single keys
    }

    private func stopRecording() {
        stopShortcutRecording()
        [recordedObserver, cancelledObserver, windowObserver].compactMap { $0 }.forEach { NotificationCenter.default.removeObserver($0) }
        recordedObserver = nil
        cancelledObserver = nil
        windowObserver = nil
        isRecording = false
    }
}

// MARK: - Shortcuts Row View

struct ShortcutsRowView: View {
    @ObservedObject var appState: AppState
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Bảng gõ tắt").font(.system(size: 13))
                Text(appState.shortcuts.isEmpty
                    ? "Chưa có từ viết tắt"
                    : "\(appState.shortcuts.filter(\.isEnabled).count)/\(appState.shortcuts.count) đang bật")
                    .font(.system(size: 11))
                    .foregroundColor(Color(NSColor.secondaryLabelColor))
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color(NSColor.tertiaryLabelColor))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(hovered ? Color(NSColor.controlBackgroundColor).opacity(0.3) : .clear)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .onTapGesture { action() }
    }
}

// MARK: - Auto Capitalize Row

struct AutoCapitalizeRow: View {
    @ObservedObject var appState: AppState
    @State private var showSheet = false
    @State private var hovered = false

    var body: some View {
        SettingsRow {
            VStack(alignment: .leading, spacing: 2) {
                Text("Tự viết hoa đầu câu").font(.system(size: 13))
                if appState.autoCapitalize {
                    Text(subtitleText)
                        .font(.system(size: 11))
                        .foregroundColor(hovered ? Color(NSColor.labelColor) : Color(NSColor.secondaryLabelColor))
                        .onHover { hovered = $0 }
                        .onTapGesture { showSheet = true }
                }
            }
            Spacer()
            Toggle("", isOn: $appState.autoCapitalize).toggleStyle(.switch).controlSize(.mini).labelsHidden() // LEANKEYS-HOOK: settings-engine
        }
        .sheet(isPresented: $showSheet) {
            AutoCapitalizeExcludedAppsSheet(appState: appState)
        }
    }

    private var subtitleText: String {
        if appState.autoCapitalizeExcludedApps.isEmpty {
            "Loại trừ ứng dụng"
        } else {
            "Loại trừ \(appState.autoCapitalizeExcludedApps.count) ứng dụng"
        }
    }
}

// MARK: - Auto Capitalize Excluded Apps Sheet

struct AutoCapitalizeExcludedAppsSheet: View {
    @ObservedObject var appState: AppState
    @State private var allApps: [AppToggleItem] = []

    private var subtitle: String {
        let count = appState.autoCapitalizeExcludedApps.count
        return count == 0 ? "Chưa có ứng dụng nào" : "\(count) ứng dụng đang loại trừ"
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader("Loại trừ viết hoa", subtitle: subtitle)
            Divider()
            if allApps.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "app.badge.checkmark")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary)
                    Text("Không có ứng dụng đang chạy")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(allApps, id: \.bundleId) { app in
                        AppToggleRow(
                            name: app.name,
                            icon: app.icon,
                            isExcluded: appState.autoCapitalizeExcludedApps.contains(app.bundleId)
                        ) { isExcluded in
                            if isExcluded {
                                appState.excludeAppFromAutoCapitalize(app.bundleId)
                            } else {
                                appState.includeAppInAutoCapitalize(app.bundleId)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
            Divider()
            SheetToolbar()
        }
        .frame(width: 460, height: 400)
        .onAppear { loadApps() }
    }

    /// Load and sort apps only on appear - no re-sorting on toggle
    private func loadApps() {
        let excluded = appState.autoCapitalizeExcludedApps

        // Get running apps
        var apps: [AppToggleItem] = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> AppToggleItem? in
                guard let bundleId = app.bundleIdentifier,
                      bundleId != Bundle.main.bundleIdentifier else { return nil }
                return AppToggleItem(
                    bundleId: bundleId,
                    name: app.localizedName ?? bundleId,
                    icon: app.icon
                )
            }

        // Add excluded apps not currently running
        for bundleId in excluded where !apps.contains(where: { $0.bundleId == bundleId }) {
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first
            let name = running?.localizedName ?? bundleId.components(separatedBy: ".").last ?? bundleId
            apps.append(AppToggleItem(bundleId: bundleId, name: name, icon: running?.icon))
        }

        // Sort once: excluded first, then alphabetically
        allApps = apps.sorted { a, b in
            let aExcluded = excluded.contains(a.bundleId)
            let bExcluded = excluded.contains(b.bundleId)
            if aExcluded != bExcluded {
                return aExcluded
            }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }
}

struct AppToggleItem {
    let bundleId: String
    let name: String
    let icon: NSImage?
}

struct AppToggleRow: View {
    let name: String
    let icon: NSImage?
    let isExcluded: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(spacing: 12) {
            // App icon
            Group {
                if let icon {
                    Image(nsImage: icon).resizable()
                } else {
                    Image(systemName: "app.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 28, height: 28)

            // App name only
            Text(name)
                .font(.system(size: 13))
                .lineLimit(1)

            Spacer()

            // Toggle switch
            Toggle("", isOn: Binding(
                get: { isExcluded },
                set: { onToggle($0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini) // LEANKEYS-HOOK: settings-engine
            .labelsHidden()
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Launch at Login Toggle Row

struct LaunchAtLoginToggleRow: View {
    @ObservedObject var appState: AppState

    var body: some View {
        SettingsRow {
            Text("Khởi động cùng hệ thống").font(.system(size: 13))
            Spacer()
            Toggle("", isOn: Binding(
                get: { appState.isLaunchAtLoginEnabled },
                set: { appState.toggleLaunchAtLogin($0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini) // LEANKEYS-HOOK: settings-engine
            .labelsHidden()
        }
    }
}

// MARK: - Preview

#Preview { MainSettingsView() }
// LEANKEYS-HOOK-BEGIN: settings-engine
extension AppState {
    /// What the status card shows: the language typing now, the auto-switch state, and any Secure Input block.
    var leanStatusSnapshot: StatusSnapshot {
        StatusSnapshot(
            vietnamese: isEnabled,
            autoSwitchApplies: EngineRouter.shared.active == .vikey,
            autoSwitchOn: EngineRouter.shared.autoSwitchOn,
            blocked: shouldShowSecureInputWarning,
            blockingApp: secureInputHolderName.flatMap { $0.isEmpty ? nil : $0 }
        )
    }
}

enum LeanSettingsWindow {
    static func root() -> some View {
        SettingsRootView(
            logo: AppMetadata.logo,
            name: AppMetadata.name,
            version: AppMetadata.version,
            badge: AnyView(UpdateBadgeView()),
            general: AnyView(SettingsPageView(appState: .shared, part: .general)),
            shortcuts: AnyView(SettingsPageView(appState: .shared, part: .shortcuts)),
            advanced: AnyView(AdvancedSettingsView(appState: .shared)),
            about: AnyView(AboutPageView()),
            pageRequests: NotificationCenter.default.publisher(for: .showSettingsPage)
                .compactMap { ($0.object as? NavigationPage)?.rawValue }
                .compactMap { SettingsPage(legacyRawValue: $0) }
                .eraseToAnyPublisher()
        )
    }
}
// LEANKEYS-HOOK-END
