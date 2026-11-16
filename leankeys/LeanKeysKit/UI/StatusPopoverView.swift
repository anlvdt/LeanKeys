import AppKit
import Combine
import SwiftUI

/// What the status popover reads and does. The app target supplies these closures; tests supply a stub.
public struct StatusPopoverActions {
    public var snapshot: () -> StatusSnapshot
    /// 0 is Telex and 1 is VNI, matching `InputMode.rawValue`.
    public var method: () -> Int
    public var updateReady: () -> Bool
    public var setVietnamese: (Bool) -> Void
    public var setMethod: (Int) -> Void
    public var installUpdate: () -> Void
    public var openSettings: () -> Void
    public var quit: () -> Void
    /// Shortcut suggestions waiting (4B); the line shows only when above 0.
    public var suggestionCount: () -> Int
    public var openSuggestions: () -> Void
    /// The update row (spec §16). nil falls back to `updateReady`: "Cài bản mới" or "Kiểm tra cập nhật".
    public var updatePhase: (() -> PopoverUpdateRow.Phase)?
    /// "Kiểm tra cập nhật" / "Thử lại": check, and install a newer version straight away.
    public var checkForUpdates: () -> Void
    /// The popover closed; a finished check's result can be cleared.
    public var popoverClosed: () -> Void

    public init(
        snapshot: @escaping () -> StatusSnapshot,
        method: @escaping () -> Int,
        updateReady: @escaping () -> Bool,
        setVietnamese: @escaping (Bool) -> Void,
        setMethod: @escaping (Int) -> Void,
        installUpdate: @escaping () -> Void,
        openSettings: @escaping () -> Void,
        quit: @escaping () -> Void,
        suggestionCount: @escaping () -> Int = { 0 },
        openSuggestions: @escaping () -> Void = {},
        updatePhase: (() -> PopoverUpdateRow.Phase)? = nil,
        checkForUpdates: @escaping () -> Void = {},
        popoverClosed: @escaping () -> Void = {}
    ) {
        self.snapshot = snapshot
        self.method = method
        self.updateReady = updateReady
        self.setVietnamese = setVietnamese
        self.setMethod = setMethod
        self.installUpdate = installUpdate
        self.openSettings = openSettings
        self.quit = quit
        self.suggestionCount = suggestionCount
        self.openSuggestions = openSuggestions
        self.updatePhase = updatePhase
        self.checkForUpdates = checkForUpdates
        self.popoverClosed = popoverClosed
    }
}

/// Holds what the popover shows. `reload()` re-reads the engine, so a language change made by Vikey shows up.
public final class StatusPopoverModel: ObservableObject {
    @Published public private(set) var snapshot: StatusSnapshot
    @Published public private(set) var method: Int
    @Published public private(set) var updateReady: Bool
    @Published public private(set) var suggestionCount: Int
    @Published public private(set) var updatePhase: PopoverUpdateRow.Phase

    private let actions: StatusPopoverActions
    /// Set by the controller so the popover closes before Settings opens.
    var closePopover: () -> Void = {}

    public init(actions: StatusPopoverActions) {
        self.actions = actions
        self.snapshot = actions.snapshot()
        self.method = actions.method()
        self.updateReady = actions.updateReady()
        self.suggestionCount = actions.suggestionCount()
        self.updatePhase = Self.updatePhase(actions)
    }

    private static func updatePhase(_ actions: StatusPopoverActions) -> PopoverUpdateRow.Phase {
        actions.updatePhase?() ?? (actions.updateReady() ? .ready : .idle)
    }

    public func reload() {
        snapshot = actions.snapshot()
        method = actions.method()
        updateReady = actions.updateReady()
        suggestionCount = actions.suggestionCount()
        updatePhase = Self.updatePhase(actions)
    }

    /// "Có N gợi ý gõ tắt", or nil when there are none.
    public static func suggestionLine(count: Int) -> String? {
        count > 0 ? "Có \(count) gợi ý gõ tắt" : nil
    }

    var suggestionLine: String? { Self.suggestionLine(count: suggestionCount) }

    public func choose(vietnamese: Bool) {
        if vietnamese != actions.snapshot().vietnamese {
            actions.setVietnamese(vietnamese)
        }
        reload()
    }

    public func choose(method: Int) {
        if method != self.method {
            actions.setMethod(method)
        }
        reload()
    }

    func installUpdate() {
        actions.installUpdate()
    }

    /// The update row's button: check (and install), or install the update already downloaded.
    public func tapUpdateRow() {
        switch PopoverUpdateRow.tapAction(updatePhase) {
        case .check?: actions.checkForUpdates()
        case .install?: actions.installUpdate()
        case nil: return
        }
        reload()
    }

    public func popoverDidClose() {
        actions.popoverClosed()
        reload()
    }

    func openSettings() {
        closePopover()
        actions.openSettings()
    }

    func openSuggestions() {
        closePopover()
        actions.openSuggestions()
    }

    func quit() {
        actions.quit()
    }
}

public struct StatusPopoverView: View {
    /// VoiceOver names of the two pickers (their labels are hidden on screen).
    static let languagePickerTitle = "Ngôn ngữ gõ"
    static let methodPickerTitle = "Kiểu gõ"
    /// Quitting stops Vietnamese typing, so the button says what it quits.
    static let quitLabel = "Thoát LeanKeys"

    @ObservedObject private var model: StatusPopoverModel

    public init(model: StatusPopoverModel) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker(StatusPopoverView.languagePickerTitle, selection: Binding(
                get: { model.snapshot.vietnamese },
                set: { model.choose(vietnamese: $0) }
            )) {
                Text("Tiếng Việt").tag(true)
                Text("English").tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if let autoSwitchLine = model.snapshot.autoSwitchLine {
                Text(autoSwitchLine)
                    .font(.system(size: 11))
                    .foregroundColor(Color(NSColor.secondaryLabelColor))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(model.snapshot.autoSwitchHelp)
            }
            if let warningLine = model.snapshot.warningLine {
                WarningLine(warningLine, help: StatusSnapshot.warningHelp)
            }

            HStack {
                Text(StatusPopoverView.methodPickerTitle)
                Spacer()
                Picker(StatusPopoverView.methodPickerTitle, selection: Binding(
                    get: { model.method },
                    set: { model.choose(method: $0) }
                )) {
                    Text("Telex").tag(0)
                    Text("VNI").tag(1)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
            }

            UpdateRowView(phase: model.updatePhase, tap: { model.tapUpdateRow() })

            if let suggestionLine = model.suggestionLine {
                Button { model.openSuggestions() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "text.badge.plus")
                            .foregroundColor(.accentColor)
                        Text(suggestionLine)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11))
                            .foregroundColor(Color(NSColor.secondaryLabelColor))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(suggestionLine))
            }

            Divider()

            HStack {
                Button("Cài đặt…") { model.openSettings() }
                Spacer()
                Button(StatusPopoverView.quitLabel) { model.quit() }
            }
        }
        .padding(14)
        .frame(width: 280, alignment: .leading)
    }
}

/// Owns the NSPopover shown from the menu-bar status item.
public final class StatusPopoverController: NSObject, NSPopoverDelegate {
    /// A click on the status item closes a transient popover on mouseDown and sends its action on mouseUp.
    /// Opening again within this window would undo that close, so the toggle is ignored.
    static let reopenGap: TimeInterval = 0.3

    private let model: StatusPopoverModel
    private let popover = NSPopover()
    private var lastClose: Date?

    public init(model: StatusPopoverModel) {
        self.model = model
        super.init()
        let host = NSHostingController(rootView: StatusPopoverView(model: model))
        host.sizingOptions = .preferredContentSize
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = host
        model.closePopover = { [weak self] in self?.popover.performClose(nil) }
    }

    public var isShown: Bool { popover.isShown }

    /// Pure decision: open unless the popover closed less than `reopenGap` seconds before `now`.
    public static func shouldOpen(lastClose: Date?, now: Date) -> Bool {
        guard let lastClose else { return true }
        return now.timeIntervalSince(lastClose) >= reopenGap
    }

    public func toggle(relativeTo button: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        guard Self.shouldOpen(lastClose: lastClose, now: Date()) else { return }
        model.reload()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    public func popoverDidClose(_ notification: Notification) {
        lastClose = Date()
        model.popoverDidClose()
    }
}

/// Which click opens the popover and which opens the legacy menu. Option and Control clicks count as right clicks.
public enum StatusClickRoute: Equatable {
    case popover, legacyMenu

    public static func route(type: NSEvent.EventType, modifiers: NSEvent.ModifierFlags) -> StatusClickRoute {
        guard type == .leftMouseUp, !modifiers.contains(.option), !modifiers.contains(.control) else {
            return .legacyMenu
        }
        return .popover
    }
}

/// The update row (spec §16.2): a button, or a status line with a spinner or progress bar, and "Thử lại" on failure.
struct UpdateRowView: View {
    let phase: PopoverUpdateRow.Phase
    let tap: () -> Void

    var body: some View {
        let line = PopoverUpdateRow.line(phase)
        let button = PopoverUpdateRow.buttonTitle(phase)
        VStack(alignment: .leading, spacing: 6) {
            if let line {
                HStack(spacing: 6) {
                    icon
                    Text(line)
                        .font(.system(size: 11))
                        .foregroundColor(Color(NSColor.secondaryLabelColor))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(line)
                    Spacer(minLength: 0)
                    if let button {
                        Button(button, action: tap)
                            .controlSize(.small)
                    }
                }
                .accessibilityElement(children: .combine)
            } else if let button {
                Button(button, action: tap)
            }
            if case let .downloading(progress) = phase {
                if let progress {
                    ProgressView(value: progress).progressViewStyle(.linear)
                } else {
                    ProgressView().progressViewStyle(.linear)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var icon: some View {
        switch phase {
        case .checking, .installing:
            ProgressView().controlSize(.mini)
        case .upToDate:
            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
        case .failed:
            Image(systemName: "exclamationmark.circle").foregroundColor(Color(NSColor.secondaryLabelColor))
        case .downloading:
            Image(systemName: "arrow.down.circle").foregroundColor(.accentColor)
        case .idle, .ready:
            EmptyView()
        }
    }
}
