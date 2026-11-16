import Foundation

/// Spec 17.2: a key next to Enter (`\` `]` `'`, with Shift `|` `}` `"`) hit together with Enter. Pressed just before
/// Enter, its character is deleted and Enter follows; pressed just after Enter, the key is dropped.
///
/// `decide` sees every key on the Vikey path (it remembers the previous one) and answers for this key. It never acts
/// on a key or an Enter with ⌘, ⌥ or ⌃, in a terminal or code editor, or on a character that closes a pair still
/// open on its line. The router skips it while the switch is off. Nothing typed is stored beyond the previous key's
/// code and time.
public struct StrayEnterFilter {
    /// The longest gap between the two key presses, inclusive.
    public static let window: TimeInterval = 0.100

    /// Terminals and code editors, where `\` before Enter is meant (spec 17.2). JetBrains IDEs match by prefix.
    public static let excludedBundleIDs: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "dev.warp.Warp-Preview",
        "com.mitchellh.ghostty", "org.alacritty", "io.alacritty", "net.kovidgoyal.kitty", "com.github.wez.wezterm",
        "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.todesktop.230313mzl4w4u92", "com.todesktop.cursor",
        "com.exafunction.windsurf", "dev.zed.Zed", "dev.zed.Zed-Preview", "com.apple.dt.Xcode", "com.sublimetext.4",
        "com.sublimetext.3", "com.panic.Nova", "com.barebones.bbedit", "com.google.android.studio",
    ]
    static let excludedBundlePrefix = "com.jetbrains."

    public enum Decision: Equatable { case none, deleteBeforeEnter, dropKey }

    /// Keys next to Enter: (character, character with Shift).
    static let adjacentKeys: [UInt16: (plain: Character, shifted: Character)] = [
        42: ("\\", "|"), 30: ("]", "}"), 39: ("'", "\""),
    ]
    static let enterKeys: Set<UInt16> = [36, 76]

    private struct Press {
        let keyCode: UInt16
        let shift: Bool
        let modified: Bool
        let time: TimeInterval
    }

    private var previous: Press?

    public init() {}

    /// - Parameters:
    ///   - otherModifiers: ⌘, ⌥ or ⌃ is held.
    ///   - time: when the key was pressed, in seconds on a monotonic clock.
    ///   - lineBeforeCursor: the text from the line start to the cursor, as on screen after the previous key; empty
    ///     when unknown, which deletes nothing.
    public mutating func decide(keyCode: UInt16, shift: Bool, otherModifiers: Bool, time: TimeInterval,
                                lineBeforeCursor: String, bundleID: String?) -> Decision {
        let before = previous
        previous = Press(keyCode: keyCode, shift: shift, modified: otherModifiers, time: time)
        guard !otherModifiers, let before, !before.modified, Self.isWithinWindow(time - before.time),
              !Self.isExcluded(bundleID) else { return .none }
        if Self.enterKeys.contains(keyCode) {
            guard let pair = Self.adjacentKeys[before.keyCode] else { return .none }
            let stray = before.shift ? pair.shifted : pair.plain
            guard lineBeforeCursor.last == stray,
                  !Self.closesOpenPair(stray, after: lineBeforeCursor.dropLast()) else { return .none }
            return .deleteBeforeEnter
        }
        if Self.adjacentKeys[keyCode] != nil, Self.enterKeys.contains(before.keyCode) { return .dropKey }
        return .none
    }

    static func isExcluded(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return excludedBundleIDs.contains(bundleID) || bundleID.hasPrefix(excludedBundlePrefix)
    }

    /// Within `window`, allowing for floating-point error in the subtraction (1000.8 - 1000.7 is not 0.1).
    private static func isWithinWindow(_ gap: TimeInterval) -> Bool {
        gap >= 0 && gap <= window + 1e-6
    }

    /// `'` or `"` after an odd number of the same on the line; `]` or `}` while a `[` or `{` is still open.
    private static func closesOpenPair(_ c: Character, after text: Substring) -> Bool {
        switch c {
        case "'", "\"":
            return text.filter { $0 == c }.count % 2 == 1
        case "]", "}":
            let opener: Character = c == "]" ? "[" : "{"
            var depth = 0
            for ch in text {
                if ch == opener { depth += 1 } else if ch == c { depth = max(0, depth - 1) }
            }
            return depth > 0
        default:
            return false
        }
    }
}
