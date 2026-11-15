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

    /// The Vikey-only note shows under "Tự động" only: with "Chỉ dùng Gõ Nhanh" every Gõ Nhanh setting works.
    public var showsVikeyNote: Bool { selected == .vikey }

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

/// The "Engine gõ" card on the Advanced page, collapsed by default: LeanKeys picks the engine itself ("Tự động" is
/// Vikey, falling back to Gõ Nhanh for VNI or when Vikey cannot start), so most users never open it.
/// Mirrors Gõ Nhanh's CardBackground, which lives in the app target.
public struct EngineSettingsSection: View {
    static let title = "Engine gõ"
    static let automaticLabel = "Tự động (khuyên dùng)"
    static let goNhanhOnlyLabel = "Chỉ dùng Gõ Nhanh"
    /// Spec §3.5: one line on screen; the list of hidden Gõ Nhanh-only settings is in `vikeyNoteDetail`.
    static let vikeyNote = "Ở chế độ Tự động, các mục chỉ dành cho Gõ Nhanh được ẩn."
    /// Tooltip (ⓘ) for `vikeyNote`.
    static let vikeyNoteDetail = "Các mục chỉ dành cho Gõ Nhanh: Tự khôi phục tiếng Anh, VNI, gõ tắt, tự viết hoa đầu câu, phím W→Ư và phím [ ]."

    @StateObject private var model: EngineSettingsModel
    @State private var isExpanded = false

    /// `onEngineChanged` runs after each switch; the app passes a closure that clears Gõ Nhanh's word buffer.
    public init(onEngineChanged: @escaping () -> Void = {}) {
        _model = StateObject(wrappedValue: EngineSettingsModel(onEngineChanged: onEngineChanged))
    }

    public var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                Picker("", selection: $model.selected) {
                    Text(Self.automaticLabel).font(.system(size: 13)).tag(EngineKind.vikey)
                    Text(Self.goNhanhOnlyLabel).font(.system(size: 13)).tag(EngineKind.gonhanh)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                if model.showsVikeyNote {
                    HStack(spacing: 4) {
                        Text(Self.vikeyNote)
                            .font(.system(size: 11))
                            .foregroundColor(Color(NSColor.secondaryLabelColor))
                            .lineLimit(1)
                        Image(systemName: "info.circle")
                            .font(.system(size: 11))
                            .foregroundColor(Color(NSColor.secondaryLabelColor))
                            .help(Self.vikeyNoteDetail)
                    }
                    .padding(.leading, 20)
                }
                if let reason = model.vikeyDisabledReason {
                    Text(reason)
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 20)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
        } label: {
            Text(Self.title).font(.system(size: 13, weight: .medium))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.controlBackgroundColor).opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5))
        .onAppear { model.refresh() }
    }
}
