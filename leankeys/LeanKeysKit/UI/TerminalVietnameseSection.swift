import AppKit
import SwiftUI

/// Nâng cao card: the terminals the user types Vietnamese in (spec 2026-11-24-terminal-vietnamese). Every terminal
/// passes keys straight through by default (ruling R22); a terminal switched on here types like any app, but stays in
/// `CodeApps`, so nothing typed there is learned or capitalised. Looks like `UndoLearningSection`'s card.
public struct TerminalVietnameseSection: View {
    static let title = "Gõ tiếng Việt trong terminal"
    static let note = "Chuyển sang English trước khi gõ mật khẩu (sudo, ssh): LeanKeys không biết lúc nào terminal hỏi mật khẩu. Thứ gõ trong terminal không bao giờ được học."

    /// The terminals in `CodeApps.terminals` that `appURL` finds installed, with their names, sorted by name.
    static func installedTerminals(appURL: (String) -> URL?) -> [(bundleID: String, name: String)] {
        CodeApps.terminals.compactMap { id -> (bundleID: String, name: String)? in
            guard let url = appURL(id) else { return nil }
            let info = Bundle(url: url)?.infoDictionary
            let name = (info?["CFBundleDisplayName"] as? String) ?? (info?["CFBundleName"] as? String)
                ?? url.deletingPathExtension().lastPathComponent
            return (id, name)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private let onChange: () -> Void
    private let terminals: [(bundleID: String, name: String)]
    @State private var chosen: Set<String>

    /// `onChange` runs after each switch: the app drops its cached pass-through decision so the change applies now.
    public init(onChange: @escaping () -> Void) {
        self.onChange = onChange
        terminals = Self.installedTerminals { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
        _chosen = State(initialValue: KeyPassthrough.vietnameseTerminals())
    }

    public var body: some View {
        if !terminals.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text(Self.title)
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 4)
                ForEach(terminals, id: \.bundleID) { terminal in
                    row(terminal)
                    Divider().padding(.leading, 12)
                }
                Text(Self.note)
                    .font(.system(size: 11))
                    .foregroundColor(Color(NSColor.secondaryLabelColor))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.controlBackgroundColor).opacity(0.5)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5))
        }
    }

    private func row(_ terminal: (bundleID: String, name: String)) -> some View {
        HStack {
            Text(terminal.name).font(.system(size: 13))
            Spacer()
            Toggle("", isOn: Binding(
                get: { chosen.contains(terminal.bundleID) },
                set: { on in
                    KeyPassthrough.setVietnamese(on, terminal: terminal.bundleID)
                    chosen = KeyPassthrough.vietnameseTerminals()
                    onChange()
                }))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .accessibilityLabel(Text("\(Self.title): \(terminal.name)"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
