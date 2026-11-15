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

    /// nil when nothing blocks Vietnamese typing.
    var warningLine: String? {
        guard blocked else { return nil }
        if let blockingApp { return "⚠︎ \(blockingApp) đang chặn gõ tiếng Việt" }
        return "⚠︎ Một app đang chặn gõ tiếng Việt"
    }
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
                    .foregroundColor(Color(NSColor.secondaryLabelColor))
            }
            if let warningLine = snapshot.warningLine {
                Text(warningLine)
                    .font(.system(size: 11))
                    .foregroundColor(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
