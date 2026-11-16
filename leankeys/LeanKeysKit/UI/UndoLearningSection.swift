import AppKit
import SwiftUI

/// 4C settings card on Nâng cao (spec 12.3), with 4D's additions (spec 17.3): the four switches, the learned words
/// (capitalisation undos shown as the phrase + " (viết hoa)") and the learned names. Copies the look of
/// `LearnSettingsSection`'s advanced card.
public struct UndoLearningSection: View {
    static let title = "Tự sửa và tự học"
    static let doubleKeyFixTitle = "⌫ sửa phím gõ đúp"
    static let learningTitle = "Tự học từ hoàn tác"
    static let autoCapitalizeTitle = "Tự viết hoa tên riêng"
    static let strayEnterTitle = "Bỏ ký tự gõ dính khi Enter"
    static let listTitle = "Từ đã học"
    static let emptyText = "Chưa có từ nào"
    static let namesTitle = "Tên đã học"
    static let namesEmptyText = "Chưa có tên nào"
    static let capitalizationSuffix = " (viết hoa)"
    static let removeAllLabel = "Xoá tất cả"
    static let removeAllConfirmTitle = "Xoá mọi từ và tên đã học?"
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
            toggleRow(Self.autoCapitalizeTitle, isOn: $model.autoCapitalize)
            Divider().padding(.leading, 12)
            toggleRow(Self.strayEnterTitle, isOn: $model.strayEnter)
            Divider().padding(.leading, 12)

            list(Self.listTitle, empty: Self.emptyText, items: model.rules, row: ruleRow)
            Divider().padding(.leading, 12)
            list(Self.namesTitle, empty: Self.namesEmptyText, items: model.names, row: nameRow)
            Divider().padding(.leading, 12)

            HStack {
                Button(Self.removeAllLabel) { confirmRemoveAll = true }
                    .controlSize(.small)
                    .disabled(model.rules.isEmpty && model.names.isEmpty)
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

    /// How a rule reads in the list: a capitalisation undo ("cap:hà nội") as "hà nội (viết hoa)", others as typed.
    static func displayText(_ rule: UndoRule) -> String {
        guard rule.text.hasPrefix(AutoCapitalizer.rulePrefix) else { return rule.text }
        return String(rule.text.dropFirst(AutoCapitalizer.rulePrefix.count)) + capitalizationSuffix
    }

    /// A titled list of fixed-height rows, lazy, scrolling past `maxListHeight`; `empty` when there are none.
    private func list<Item: Identifiable, Row: View>(_ title: String, empty: String, items: [Item],
                                                     row: @escaping (Item) -> Row) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 13))
            if items.isEmpty {
                Text(empty)
                    .font(.system(size: 12))
                    .foregroundColor(Color(NSColor.secondaryLabelColor))
                    .padding(.leading, 8)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(items) { item in
                            row(item).frame(height: Self.rowHeight)
                        }
                    }
                }
                .frame(height: min(CGFloat(items.count) * Self.rowHeight, Self.maxListHeight))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func ruleRow(_ rule: UndoRule) -> some View {
        let text = Self.displayText(rule)
        return HStack(spacing: 6) {
            Text(text).font(.system(size: 12)).lineLimit(1)
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
            .accessibilityLabel(Text("Xoá \(text)"))
        }
        .padding(.leading, 8)
    }

    private func nameRow(_ name: LearnedName) -> some View {
        HStack(spacing: 6) {
            Text(name.form).font(.system(size: 12)).lineLimit(1)
            Spacer()
            Text("\(name.count) lần")
                .font(.system(size: 11))
                .foregroundColor(Color(NSColor.secondaryLabelColor))
                .monospacedDigit()
            Button { model.remove(name) } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("Xoá \(name.form)"))
        }
        .padding(.leading, 8)
    }
}

extension UndoLearning {
    /// Fake data for previews and review images: a memory-only book and a throwaway defaults suite, never the real
    /// store or `UserDefaults.standard`. Each record is one ⌫⌫ undo of `text` typed after `previous`; each name is one
    /// observation of a word the user capitalised (learned at the second), in a memory-only `LearnedNames`.
    static func preview(records: [(text: String, previous: String)] = [],
                        names: [(word: String, previous: String?)] = []) -> UndoLearning {
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
        let learnedNames = LearnedNames(store: nil, hmacKey: nil, titles: Set(ProperNounData.bundled.titles),
                                        isDictionaryWord: { _ in false }, now: {
            tick += 60
            return tick
        })
        for name in names {
            learnedNames.observe(word: name.word, previous: name.previous)
        }
        return UndoLearning(book: book, defaults: defaults, probe: {
            LearnContextProbe(bundleID: nil, pid: nil, secureInput: false, now: Date())
        }, secureField: { _ in false }, names: learnedNames)
    }
}

struct UndoLearningSection_Previews: PreviewProvider {
    static var previews: some View {
        let filled = UndoLearning.preview(
            records: [("its", "about"), ("cos", ""), ("cos", ""), ("cap:hà nội", "ở"), ("user", "new")],
            names: [("Hùng", "anh"), ("Hùng", "anh"), ("Thảo", nil), ("Thảo", nil)])
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
