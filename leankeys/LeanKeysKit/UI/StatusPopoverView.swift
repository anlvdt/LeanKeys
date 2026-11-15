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

    public init(
        snapshot: @escaping () -> StatusSnapshot,
        method: @escaping () -> Int,
        updateReady: @escaping () -> Bool,
        setVietnamese: @escaping (Bool) -> Void,
        setMethod: @escaping (Int) -> Void,
        installUpdate: @escaping () -> Void,
        openSettings: @escaping () -> Void,
        quit: @escaping () -> Void
    ) {
        self.snapshot = snapshot
        self.method = method
        self.updateReady = updateReady
        self.setVietnamese = setVietnamese
        self.setMethod = setMethod
        self.installUpdate = installUpdate
        self.openSettings = openSettings
        self.quit = quit
    }
}

/// Holds what the popover shows. `reload()` re-reads the engine, so a language change made by Vikey shows up.
public final class StatusPopoverModel: ObservableObject {
    @Published public private(set) var snapshot: StatusSnapshot
    @Published public private(set) var method: Int
    @Published public private(set) var updateReady: Bool

    private let actions: StatusPopoverActions
    /// Set by the controller so the popover closes before Settings opens.
    var closePopover: () -> Void = {}

    public init(actions: StatusPopoverActions) {
        self.actions = actions
        self.snapshot = actions.snapshot()
        self.method = actions.method()
        self.updateReady = actions.updateReady()
    }

    public func reload() {
        snapshot = actions.snapshot()
        method = actions.method()
        updateReady = actions.updateReady()
    }

    public func choose(vietnamese: Bool) {
        if vietnamese != snapshot.vietnamese {
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

    func openSettings() {
        closePopover()
        actions.openSettings()
    }

    func quit() {
        actions.quit()
    }
}

public struct StatusPopoverView: View {
    @ObservedObject private var model: StatusPopoverModel

    public init(model: StatusPopoverModel) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("", selection: Binding(
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
            }
            if let warningLine = model.snapshot.warningLine {
                Text(warningLine)
                    .font(.system(size: 11))
                    .foregroundColor(.orange)
            }

            HStack {
                Text("Kiểu gõ")
                Spacer()
                Picker("", selection: Binding(
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

            if model.updateReady {
                Button("Cài bản mới") { model.installUpdate() }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            HStack {
                Button("Cài đặt…") { model.openSettings() }
                Spacer()
                Button("Thoát") { model.quit() }
            }
        }
        .padding(14)
        .frame(width: 280, alignment: .leading)
    }
}

/// Owns the NSPopover shown from the menu-bar status item.
public final class StatusPopoverController {
    private let model: StatusPopoverModel
    private let popover = NSPopover()

    public init(model: StatusPopoverModel) {
        self.model = model
        let host = NSHostingController(rootView: StatusPopoverView(model: model))
        host.sizingOptions = .preferredContentSize
        popover.behavior = .transient
        popover.contentViewController = host
        model.closePopover = { [weak self] in self?.popover.performClose(nil) }
    }

    public var isShown: Bool { popover.isShown }

    public func toggle(relativeTo button: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        model.reload()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
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
