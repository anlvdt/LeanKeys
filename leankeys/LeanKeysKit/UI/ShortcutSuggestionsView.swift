import AppKit
import SwiftUI

/// The list opened from "Có N gợi ý gõ tắt": each learned phrase with its suggested trigger and Thêm · Sửa · Bỏ qua.
/// Nothing is added until Thêm is pressed.
public struct ShortcutSuggestionsView: View {
    static let title = "Gợi ý gõ tắt"
    static let emptyLine = "Không còn gợi ý nào."
    static let addLabel = "Thêm"
    static let editLabel = "Sửa"
    static let dismissLabel = "Bỏ qua"

    @ObservedObject private var model: ShortcutSuggestionsModel

    public init(model: ShortcutSuggestionsModel) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Self.title).font(.system(size: 13, weight: .semibold))
            if model.rows.isEmpty {
                Text(Self.emptyLine)
                    .font(.system(size: 12))
                    .foregroundColor(Color(NSColor.secondaryLabelColor))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(model.rows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 { Divider().padding(.leading, 12) }
                        SuggestionRowView(row: row, model: model)
                    }
                }
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.controlBackgroundColor).opacity(0.5)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5))
            }
        }
        .padding(16)
        .frame(width: 440, alignment: .leading)
    }

    static func kindLabel(_ kind: PhraseKind) -> String {
        switch kind {
        case .phone: return "Số điện thoại"
        case .taxCode: return "Mã số thuế"
        case .address: return "Địa chỉ"
        case .email: return "Email"
        case .phrase: return "Cụm từ"
        }
    }
}

private struct SuggestionRowView: View {
    let row: SuggestionRow
    @ObservedObject var model: ShortcutSuggestionsModel
    @State private var editing = false
    @State private var draft = ""
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(row.candidate.text)
                .font(.system(size: 13))
                .lineLimit(1)
                .truncationMode(.middle)
                .help(row.candidate.text)
            HStack(spacing: 8) {
                if editing {
                    TextField("", text: $draft)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(width: 110)
                        .onSubmit(saveEdit)
                } else {
                    Text(row.trigger)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color(NSColor.quaternaryLabelColor)))
                }
                Text("\(ShortcutSuggestionsView.kindLabel(row.candidate.kind)) · \(row.candidate.count) lần")
                    .font(.system(size: 11))
                    .foregroundColor(Color(NSColor.secondaryLabelColor))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Button(ShortcutSuggestionsView.addLabel, action: add)
                    .keyboardShortcut(editing ? .defaultAction : nil)
                Button(ShortcutSuggestionsView.editLabel, action: startEdit)
                    .disabled(editing)
                Button(ShortcutSuggestionsView.dismissLabel) { model.dismiss(row) }
            }
            .controlSize(.small)
            if let problem {
                WarningLine(problem)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func startEdit() {
        draft = row.trigger
        problem = nil
        editing = true
    }

    private func saveEdit() {
        problem = model.edit(row, trigger: draft)
        if problem == nil { editing = false }
    }

    private func add() {
        if editing {
            saveEdit()
            guard problem == nil else { return }
        }
        problem = model.accept(row)
    }
}

/// The window that hosts `ShortcutSuggestionsView`. Trigger names are computed as it opens (main thread, on the
/// click that opened it), never per keystroke.
public enum ShortcutSuggestionsWindow {
    private static var window: NSWindow?

    public static func show(_ model: ShortcutSuggestionsModel) {
        model.prepareSuggestions()
        if window == nil {
            let host = NSHostingController(rootView: ShortcutSuggestionsView(model: model))
            host.sizingOptions = .preferredContentSize
            let made = NSWindow(contentViewController: host)
            made.title = ShortcutSuggestionsView.title
            made.styleMask = [.titled, .closable]
            made.isReleasedWhenClosed = false
            made.center()
            window = made
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct ShortcutSuggestionsView_Previews: PreviewProvider {
    static var previews: some View {
        let model = ShortcutSuggestionsModel.preview(candidates: ShortcutSuggestionsModel.sampleCandidates)
        Group {
            ShortcutSuggestionsView(model: model).preferredColorScheme(.light).previewDisplayName("Sáng")
            ShortcutSuggestionsView(model: model).preferredColorScheme(.dark).previewDisplayName("Tối")
        }
    }
}

extension ShortcutSuggestionsModel {
    /// Fake data for previews and review images; never real personal data.
    static let sampleCandidates = [
        Candidate(id: "sample-phone", text: "0900 000 000", kind: .phone, count: 4),
        Candidate(id: "sample-address", text: "Số 1 đường Mẫu, phường Ví Dụ, quận 1", kind: .address, count: 3),
    ]

    /// A model that learns nothing and touches no store, showing `candidates` (with triggers) as if learning were on.
    static func preview(candidates: [Candidate] = [], enabled: Bool = true) -> ShortcutSuggestionsModel {
        let suite = "LeanKeys.preview"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set(enabled, forKey: enabledKey)
        defaults.set(true, forKey: consentKey)
        let model = ShortcutSuggestionsModel(
            defaults: defaults,
            makeLearner: { _ in PreviewLearner() },
            eraseStore: {},
            onLearnerQueue: { _ in },
            onMain: { $0() },
            suggest: { candidate, taken in
                let base = candidate.kind == .phone ? "sdt" : candidate.kind == .address ? "dchi" : "gt"
                return taken.contains(base) ? base + "2" : base
            }
        )
        model.publish(candidates)
        model.prepareSuggestions()
        return model
    }
}

private final class PreviewLearner: PhraseLearning {
    var enabled = false
    var excludedBundleIDs: Set<String> = []
    var ready: [Candidate] { [] }
    func observe(_ phrase: CommittedPhrase, context: LearnContext) {}
    func accept(_ c: Candidate) {}
    func dismiss(_ c: Candidate) {}
    func eraseAll() {}
}
