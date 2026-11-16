import AppKit
import SwiftUI

/// What the status card shows: the language LeanKeys is typing in right now, plus the two lines under it.
public struct StatusSnapshot: Equatable {
    public var vietnamese: Bool
    /// True only while Vikey is the active engine: Gõ Nhanh has no automatic switching.
    public var autoSwitchApplies: Bool
    public var autoSwitchOn: Bool
    /// True while a Secure Input holder stops Vietnamese typing.
    public var blocked: Bool
    /// The app holding Secure Input; nil when it is not known.
    public var blockingApp: String?

    public init(vietnamese: Bool, autoSwitchApplies: Bool, autoSwitchOn: Bool, blocked: Bool, blockingApp: String?) {
        self.vietnamese = vietnamese
        self.autoSwitchApplies = autoSwitchApplies
        self.autoSwitchOn = autoSwitchOn
        self.blocked = blocked
        self.blockingApp = blockingApp
    }
}

public extension StatusSnapshot {
    var languageTitle: String { vietnamese ? "Tiếng Việt" : "English" }

    /// nil when automatic switching does not apply.
    var autoSwitchLine: String? {
        guard autoSwitchApplies else { return nil }
        return autoSwitchOn ? "Tự chuyển Việt/Anh: Bật" : "Tự chuyển Việt/Anh: Tạm dừng"
    }

    /// Tooltip of the auto-switch line: why it is paused and how to resume (`EngineRouter.setEnabled(explicit:)`).
    var autoSwitchHelp: String {
        autoSwitchOn
            ? "LeanKeys tự chuyển Việt/Anh theo từ bạn gõ."
            : "Bạn đã tự chọn English nên LeanKeys tạm không tự chuyển. Chọn Tiếng Việt để bật lại."
    }

    /// nil when nothing blocks Vietnamese typing.
    var warningLine: String? {
        guard blocked else { return nil }
        if let blockingApp { return "⚠︎ \(blockingApp) đang chặn gõ tiếng Việt" }
        return "⚠︎ Một ứng dụng đang chặn gõ tiếng Việt"
    }

    /// Tooltip of the warning line: what blocks typing and what to do about it.
    static let warningHelp = "Một ô mật khẩu đang bật Secure Input. Rời ô đó hoặc thoát ứng dụng đang giữ nó; LeanKeys sẽ tự gõ lại được."
}

/// Language title, then the auto-switch line, then the warning line in orange when present.
public struct StatusCard: View {
    private let snapshot: StatusSnapshot

    public init(snapshot: StatusSnapshot) {
        self.snapshot = snapshot
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(snapshot.languageTitle)
                .font(.system(size: 15, weight: .semibold))
            if let autoSwitchLine = snapshot.autoSwitchLine {
                Text(autoSwitchLine)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(NSColor.secondaryLabelColor))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(snapshot.autoSwitchHelp)
            }
            if let warningLine = snapshot.warningLine {
                WarningLine(warningLine, help: StatusSnapshot.warningHelp)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One-line warning: an orange triangle, then the text in label color (contrast 4.5:1 or better on window backgrounds).
/// The `⚠︎ ` glyph in the string is dropped at render time, because the symbol replaces it; the copy itself is unchanged.
/// VoiceOver reads it as one element, "Cảnh báo: …", since the triangle itself is hidden.
struct WarningLine: View {
    static let glyphPrefix = "⚠︎ "

    private let line: String
    private let help: String

    /// `help` is the tooltip; it defaults to the line itself.
    init(_ line: String, help: String? = nil) {
        self.line = line
        self.help = help ?? line
    }

    /// The text drawn next to the triangle symbol.
    static func displayText(for line: String) -> String {
        line.hasPrefix(glyphPrefix) ? String(line.dropFirst(glyphPrefix.count)) : line
    }

    /// What VoiceOver reads for the line.
    static func accessibilityText(for line: String) -> String {
        "Cảnh báo: " + displayText(for: line)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(Self.displayText(for: line))
                .font(.system(size: 11))
                .foregroundStyle(Color(NSColor.labelColor))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .help(help)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(Self.accessibilityText(for: line)))
    }
}
