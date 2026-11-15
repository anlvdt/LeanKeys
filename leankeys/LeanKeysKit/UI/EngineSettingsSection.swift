import AppKit
import Combine
import SwiftUI

/// Backs the "Engine gõ" picker: writes the choice to the router and says why Vikey is not typing, if it isn't.
public final class EngineSettingsModel: ObservableObject {
    static let vniReason = "Vikey không hỗ trợ VNI — đang dùng Gõ Nhanh"
    static let initFailedReason = "Không khởi động được engine Vikey — đang dùng Gõ Nhanh"

    private let router: EngineRouter
    private let onEngineChanged: () -> Void
    private var defaultsObserver: AnyCancellable?

    /// Changing it switches the router right away and calls `onEngineChanged`; re-selecting the same engine does neither.
    @Published public var selected: EngineKind {
        didSet {
            guard selected != oldValue else { return }
            router.selected = selected
            onEngineChanged()
        }
    }

    /// Shown under the picker while Vikey is selected but Gõ Nhanh types; nil otherwise. Read live from the router.
    public var vikeyDisabledReason: String? {
        switch router.fallbackReason {
        case "vni": return Self.vniReason
        case "vikey-init-failed": return Self.initFailedReason
        default: return nil
        }
    }

    public init(router: EngineRouter = .shared, onEngineChanged: @escaping () -> Void = {}) {
        self.router = router
        self.onEngineChanged = onEngineChanged
        selected = router.selected
        // Gõ Nhanh's method picker calls RustBridge.setMethod (and so the router) before it writes UserDefaults,
        // so a defaults change is the cue to re-render with the router's current fallback.
        defaultsObserver = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .sink { [weak self] _ in
                if Thread.isMainThread {
                    self?.refresh()
                } else {
                    DispatchQueue.main.async { self?.refresh() }
                }
            }
    }

    /// Asks the view to re-read `vikeyDisabledReason`.
    public func refresh() {
        objectWillChange.send()
    }
}

/// The "Engine gõ" card. Mirrors Gõ Nhanh's SettingsRow + CardBackground, which live in the app target.
public struct EngineSettingsSection: View {
    @StateObject private var model: EngineSettingsModel

    /// `onEngineChanged` runs after each switch; the app passes a closure that clears Gõ Nhanh's word buffer.
    public init(onEngineChanged: @escaping () -> Void = {}) {
        _model = StateObject(wrappedValue: EngineSettingsModel(onEngineChanged: onEngineChanged))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Engine gõ").font(.system(size: 13))
            Picker("", selection: $model.selected) {
                Text("Gõ Nhanh (mặc định)").font(.system(size: 13)).tag(EngineKind.gonhanh)
                Text("Vikey — tự chuyển Việt/Anh theo ngữ cảnh").font(.system(size: 13)).tag(EngineKind.vikey)
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            Text("Khi dùng Vikey, các mục Tự khôi phục tiếng Anh và VNI của Gõ Nhanh không có tác dụng.")
                .font(.system(size: 11))
                .foregroundColor(Color(NSColor.secondaryLabelColor))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 20)
            if let reason = model.vikeyDisabledReason {
                Text(reason)
                    .font(.system(size: 11))
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 20)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.controlBackgroundColor).opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5))
        .onAppear { model.refresh() }
    }
}
