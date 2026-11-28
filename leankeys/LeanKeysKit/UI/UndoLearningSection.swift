import AppKit
import SwiftUI

/// 4C settings card on Nâng cao (spec 12.3), with 4D's additions (spec 17.3): the four switches, the words kept as
/// typed (capitalisation undos shown as the phrase + " (giữ chữ thường)") and the learned names. Copies the look of
/// `LearnSettingsSection`'s advanced card.
public struct UndoLearningSection: View {
    static let title = "Tự sửa và tự học"
    static let doubleKeyFixTitle = "Sửa lỗi bấm đúp phím dấu"
    static let doubleKeyFixSubtitle = "Bấm ⌫ ngay sau khi lỡ bấm đúp: hocjj⌫ → học"
    static let learningTitle = "Nhớ từ bạn sửa"
    static let learningSubtitle = "Bấm ⌫⌫ hoặc ⌃⌫ ngay sau một từ sai: lần sau nhớ"
    static let autoCapitalizeTitle = "Tự viết hoa tên riêng"
    static let autoCapitalizeSubtitle = "Tên người, địa danh: Hà Nội, Nguyễn Văn An"
    static let strayEnterTitle = "Bỏ phím \\ ] ' lỡ bấm cùng Enter"
    static let strayEnterSubtitle = "Không áp dụng trong Terminal và trình soạn code"
    /// Shown under each of the four switches while the master switch "Tự sửa khi gõ" is off.
    static let autoFixOffNote = "Đang tắt bởi Tự sửa khi gõ"
    static let listTitle = "Từ đã học"
    static let emptyText = "Chưa có. Bấm ⌫⌫ hoặc ⌃⌫ ngay sau một từ sai để thêm."
    static let pinButtonTitle = "Thêm từ giữ nguyên…"
    static let pinSheetTitle = "Thêm từ giữ nguyên"
    static let pinSheetHint = "Mỗi dòng một từ, chỉ chữ cái a–z (2–38 ký tự)."
    static let pinSheetAdd = "Thêm"
    static let pinSheetCancel = "Huỷ"
    static let unpinHelp = "Bỏ ghim"
    static let namesTitle = "Tên đã học"
    static let namesEmptyText = "Chưa có. Tên bạn tự viết hoa từ hai lần trở lên sẽ hiện ở đây."
    /// A `cap:` rule records that the user undid a capital: LeanKeys keeps that phrase lowercase.
    static let capitalizationSuffix = " (giữ chữ thường)"
    static let removeAllLabel = "Xoá tất cả"
    static let removeAllConfirmTitle = "Xoá mọi từ đã học, từ ghim và tên đã học?"
    static let removeAllConfirmMessage = "Mọi từ đã học, từ ghim và tên đã học sẽ bị xoá. Không hoàn tác được."
    static let removeAllConfirm = "Xoá"
    static let removeAllCancel = "Huỷ"

    /// Rows are a fixed height so the list can be lazy and still size itself; past `maxListHeight` it scrolls.
    private static let rowHeight: CGFloat = 24
    private static let maxListHeight: CGFloat = 240

    @ObservedObject private var model: UndoLearning
    @State private var confirmRemoveAll = false
    /// True while the master switch is off: the four switches are greyed out; their stored values stay.
    private let autoFixOff: Bool
    @State private var showPinSheet = false
    @State private var pinText = ""
    @State private var pinResult: String?

    public init(model: UndoLearning, autoFixOff: Bool = false) {
        self.model = model
        self.autoFixOff = autoFixOff
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(Self.title)
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 4)

            toggleRow(Self.doubleKeyFixTitle, subtitle: Self.doubleKeyFixSubtitle, isOn: $model.doubleKeyFix)
            Divider().padding(.leading, 12)
            toggleRow(Self.learningTitle, subtitle: Self.learningSubtitle, isOn: $model.learning)
            Divider().padding(.leading, 12)
            toggleRow(Self.autoCapitalizeTitle, subtitle: Self.autoCapitalizeSubtitle, isOn: $model.autoCapitalize)
            Divider().padding(.leading, 12)
            toggleRow(Self.strayEnterTitle, subtitle: Self.strayEnterSubtitle, isOn: $model.strayEnter)
            Divider().padding(.leading, 12)

            list(Self.listTitle, empty: Self.emptyText, items: listItems, row: listRow)
            HStack(spacing: 8) {
                Button(Self.pinButtonTitle) { pinText = ""; showPinSheet = true }
                    .controlSize(.small)
                if let pinResult {
                    Text(pinResult)
                        .font(.system(size: 11))
                        .foregroundColor(Color(NSColor.secondaryLabelColor))
                        .lineLimit(1)
                        .help(pinResult)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
            Divider().padding(.leading, 12)
            list(Self.namesTitle, empty: Self.namesEmptyText, items: model.names, row: nameRow)
            Divider().padding(.leading, 12)

            HStack {
                Button(Self.removeAllLabel) { confirmRemoveAll = true }
                    .controlSize(.small)
                    .disabled(!Self.canRemoveAll(model))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.controlBackgroundColor).opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5))
        .sheet(isPresented: $showPinSheet) { pinSheet }
        .alert(Self.removeAllConfirmTitle, isPresented: $confirmRemoveAll) {
            Button(Self.removeAllConfirm, role: .destructive) { model.removeAll(); pinResult = nil }
            Button(Self.removeAllCancel, role: .cancel) {}
        } message: {
            Text(Self.removeAllConfirmMessage)
        }
    }

    /// Looks like Gõ Nhanh's `SettingsToggleRow`: the subtitle is one 11 pt line, in full in its tooltip.
    private func toggleRow(_ title: String, subtitle: String? = nil, isOn: Binding<Bool>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(Color(NSColor.secondaryLabelColor))
                        .lineLimit(1)
                        .help(subtitle)
                }
                if autoFixOff {
                    Text(Self.autoFixOffNote)
                        .font(.system(size: 11))
                        .foregroundColor(Color(NSColor.secondaryLabelColor))
                        .lineLimit(1)
                }
            }
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .accessibilityLabel(Text(title))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .disabled(autoFixOff)
    }

    /// How a rule reads in the list: a capitalisation undo ("cap:hà nội") as "hà nội (giữ chữ thường)", others as typed.
    static func displayText(_ rule: UndoRule) -> String {
        guard rule.text.hasPrefix(AutoCapitalizer.rulePrefix) else { return rule.text }
        return String(rule.text.dropFirst(AutoCapitalizer.rulePrefix.count)) + capitalizationSuffix
    }

    /// "Xoá tất cả" works whenever there is anything to clear: rules, names or pinned words.
    static func canRemoveAll(_ model: UndoLearning) -> Bool {
        !(model.rules.isEmpty && model.names.isEmpty && model.pinnedWords.isEmpty)
    }

    /// The kind word shown on each row.
    static func kindLabel(_ kind: UndoRuleKind) -> String { kind == .keep ? "giữ như gõ" : "đổi" }

    /// A convert rule's direction, for its tooltip; nil for a keep rule.
    static func convertHelp(_ rule: UndoRule) -> String? {
        guard rule.kind == .convert else { return nil }
        return rule.text + ((rule.toRaw ?? false) ? " → kiểu gõ thô" : " → Telex")
    }

    /// "Đã thêm N từ, bỏ M dòng."
    static func pinResultLine(added: Int, skipped: Int) -> String { "Đã thêm \(added) từ, bỏ \(skipped) dòng." }

    private enum ListItem: Identifiable {
        case pinned(String)
        case rule(UndoRule)
        var id: String {
            switch self {
            case .pinned(let word): return "pin\u{1F}" + word
            case .rule(let rule): return rule.id
            }
        }
    }

    /// Pinned words first, then the learned rules.
    private var listItems: [ListItem] { model.pinnedWords.map(ListItem.pinned) + model.rules.map(ListItem.rule) }

    @ViewBuilder
    private func listRow(_ item: ListItem) -> some View {
        switch item {
        case .pinned(let word): pinnedRow(word)
        case .rule(let rule): ruleRow(rule)
        }
    }

    private func pinnedRow(_ word: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "pin.fill")
                .font(.system(size: 10))
                .foregroundColor(Color(NSColor.secondaryLabelColor))
            Text(word).font(.system(size: 12)).lineLimit(1)
            Spacer()
            Text(Self.kindLabel(.keep))
                .font(.system(size: 11))
                .foregroundColor(Color(NSColor.secondaryLabelColor))
            Button { model.unpin(word); pinResult = nil } label: {
                Image(systemName: "pin.slash")
            }
            .buttonStyle(.borderless)
            .help(Self.unpinHelp)
            .accessibilityLabel(Text("\(Self.unpinHelp) \(word)"))
        }
        .padding(.leading, 8)
    }

    private var pinSheet: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Self.pinSheetTitle).font(.system(size: 13, weight: .medium))
            Text(Self.pinSheetHint)
                .font(.system(size: 11))
                .foregroundColor(Color(NSColor.secondaryLabelColor))
                .lineLimit(1)
                .help(Self.pinSheetHint)
            TextEditor(text: $pinText)
                .font(.system(size: 12, design: .monospaced))
                .frame(width: 300, height: 140)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(NSColor.separatorColor)))
            HStack {
                Spacer()
                Button(Self.pinSheetCancel) { showPinSheet = false }
                    .keyboardShortcut(.cancelAction)
                Button(Self.pinSheetAdd) {
                    let lines = pinText.split(whereSeparator: \.isNewline).map(String.init)
                    let result = model.pin(lines)
                    pinResult = Self.pinResultLine(added: result.added, skipped: result.skipped)
                    showPinSheet = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(pinText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
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
                .help(Self.convertHelp(rule) ?? text)
            if !rule.previous.isEmpty {
                Text("sau “\(rule.previous)”")
                    .font(.system(size: 11))
                    .foregroundColor(Color(NSColor.secondaryLabelColor))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Text(Self.kindLabel(rule.kind))
                .font(.system(size: 11))
                .foregroundColor(Color(NSColor.secondaryLabelColor))
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
                        converts: [(keys: String, toRaw: Bool)] = [], pinned: [String] = [],
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
        for convert in converts {
            book.recordConvert(keys: convert.keys, previous: "", toRaw: convert.toRaw, reverse: false)
            book.recordConvert(keys: convert.keys, previous: "", toRaw: convert.toRaw, reverse: false)
        }
        _ = book.pin(pinned)
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
            converts: [("beer", true), ("cos", false)], pinned: ["Beer", "github"],
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
