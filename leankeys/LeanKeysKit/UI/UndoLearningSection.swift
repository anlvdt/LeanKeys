import AppKit
import SwiftUI

/// 4C settings card on Nâng cao (spec 12.3): the two switches and the learned words. Copies the look of
/// `LearnSettingsSection`'s advanced card.
public struct UndoLearningSection: View {
    static let title = "Tự sửa và tự học"
    static let doubleKeyFixTitle = "⌫ sửa phím gõ đúp"
    static let learningTitle = "Tự học từ hoàn tác"
    static let listTitle = "Từ đã học"
    static let emptyText = "Chưa có từ nào"
    static let removeAllLabel = "Xoá tất cả"
    static let removeAllConfirmTitle = "Xoá mọi từ đã học?"
    static let removeAllConfirm = "Xoá"
    static let removeAllCancel = "Huỷ"

    /// Rows are a fixed height so the list can be lazy and still size itself; past `maxListHeight` it scrolls.
    private static let rowHeight: CGFloat = 24
    private static let maxListHeight: CGFloat = 240

    @ObservedObject private var model: UndoLearning
    @State private var confirmRemoveAll = false

    public init(model: UndoLearning) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(Self.title)
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 4)

            toggleRow(Self.doubleKeyFixTitle, isOn: $model.doubleKeyFix)
            Divider().padding(.leading, 12)
            toggleRow(Self.learningTitle, isOn: $model.learning)
            Divider().padding(.leading, 12)

            VStack(alignment: .leading, spacing: 6) {
                Text(Self.listTitle).font(.system(size: 13))
                if model.rules.isEmpty {
                    Text(Self.emptyText)
                        .font(.system(size: 12))
                        .foregroundColor(Color(NSColor.secondaryLabelColor))
                        .padding(.leading, 8)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(model.rules) { rule in
                                ruleRow(rule).frame(height: Self.rowHeight)
                            }
                        }
                    }
                    .frame(height: min(CGFloat(model.rules.count) * Self.rowHeight, Self.maxListHeight))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider().padding(.leading, 12)

            HStack {
                Button(Self.removeAllLabel) { confirmRemoveAll = true }
                    .controlSize(.small)
                    .disabled(model.rules.isEmpty)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.controlBackgroundColor).opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5))
        .alert(Self.removeAllConfirmTitle, isPresented: $confirmRemoveAll) {
            Button(Self.removeAllConfirm, role: .destructive) { model.removeAll() }
            Button(Self.removeAllCancel, role: .cancel) {}
        }
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title).font(.system(size: 13))
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .accessibilityLabel(Text(title))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func ruleRow(_ rule: UndoRule) -> some View {
        HStack(spacing: 6) {
            Text(rule.text).font(.system(size: 12)).lineLimit(1)
            if !rule.previous.isEmpty {
                Text("sau \"\(rule.previous)\"")
                    .font(.system(size: 11))
                    .foregroundColor(Color(NSColor.secondaryLabelColor))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Text("\(rule.count) lần")
                .font(.system(size: 11))
                .foregroundColor(Color(NSColor.secondaryLabelColor))
                .monospacedDigit()
            Button { model.remove(rule) } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("Xoá \(rule.text)"))
        }
        .padding(.leading, 8)
    }
}

extension UndoLearning {
    /// Fake data for previews and review images: a memory-only book and a throwaway defaults suite, never the real
    /// store or `UserDefaults.standard`. Each record is one ⌫⌫ undo of `text` typed after `previous`.
    static func preview(records: [(text: String, previous: String)] = []) -> UndoLearning {
        let suite = "LeanKeys.preview.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var tick = Date(timeIntervalSince1970: 1_800_000_000)
        let book = UndoRuleBook(store: nil, now: {
            tick += 60
            return tick
        })
        for record in records {
            book.record(before: record.text, previous: record.previous, reverse: false)
        }
        return UndoLearning(book: book, defaults: defaults, context: {
            LearnContext(bundleID: nil, secureInput: false, secureField: false, now: Date())
        })
    }
}

struct UndoLearningSection_Previews: PreviewProvider {
    static var previews: some View {
        let filled = UndoLearning.preview(records: [("its", "about"), ("cos", ""), ("cos", ""), ("user", "new")])
        let page = VStack(spacing: 20) {
            UndoLearningSection(model: filled)
            UndoLearningSection(model: .preview())
        }
        .padding(20)
        .frame(width: 500)
        Group {
            page.preferredColorScheme(.light).previewDisplayName("Sáng")
            page.preferredColorScheme(.dark).previewDisplayName("Tối")
        }
    }
}
