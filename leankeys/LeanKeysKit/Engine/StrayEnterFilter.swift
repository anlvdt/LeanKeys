import Foundation

/// Spec 17.2: a key next to Enter (`\` `]` `'`, with Shift `|` `}` `"`) hit together with Enter. Pressed just before
/// Enter, its character is deleted and Enter follows; pressed just after Enter, the key is dropped.
///
/// `decide` sees every key on the Vikey path (it remembers the previous one) and answers for this key. It never acts
/// on a key or an Enter with ⌘, ⌥ or ⌃, in a terminal or code editor (`CodeApps`), or on a character that closes a pair still
/// open on its line. The router skips it while the switch is off. Nothing typed is stored beyond the previous key's
/// code and time.
public struct StrayEnterFilter {
    /// The longest gap between the two key presses, inclusive.
    public static let window: TimeInterval = 0.100

    public enum Decision: Equatable { case none, deleteBeforeEnter, dropKey }

    /// Keys next to Enter: (character, character with Shift).
    static let adjacentKeys: [UInt16: (plain: Character, shifted: Character)] = [
        42: ("\\", "|"), 30: ("]", "}"), 39: ("'", "\""),
    ]
    static let enterKeys: Set<UInt16> = [36, 76]
    /// `]`, with Shift `}`.
    private static let bracketKey: UInt16 = 30
    /// Stray characters that never close a pair: deleted even when the line's start is unknown.
    private static let pairless: Set<Character> = ["\\", "|"]

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
    ///   - lineBeforeCursor: the text before the cursor on its line, as on screen after the previous key: the whole
    ///     line when `lineStartKnown`, else only what was typed since the cursor last moved (possibly empty).
    ///   - lineStartKnown: `lineBeforeCursor` starts at the line's start. Without it the pair rule cannot be
    ///     checked, so only `\` and `|`, which close no pair, are deleted.
    ///   - bracketTypesLetter: `]` and `}` type a letter (ư, Ư in Vietnamese Telex), so after Enter they begin the
    ///     next line and are never dropped (ruling R14).
    public mutating func decide(keyCode: UInt16, shift: Bool, otherModifiers: Bool, time: TimeInterval,
                                lineBeforeCursor: String, lineStartKnown: Bool, bundleID: String?,
                                bracketTypesLetter: Bool = false) -> Decision {
        let before = previous
        previous = Press(keyCode: keyCode, shift: shift, modified: otherModifiers, time: time)
        guard !otherModifiers, let before, !before.modified, Self.isWithinWindow(time - before.time),
              !CodeApps.contains(bundleID) else { return .none }
        if Self.enterKeys.contains(keyCode) {
            guard let pair = Self.adjacentKeys[before.keyCode] else { return .none }
            let stray = before.shift ? pair.shifted : pair.plain
            guard lineBeforeCursor.last == stray else { return .none }
            if lineStartKnown {
                guard !Self.closesOpenPair(stray, after: lineBeforeCursor.dropLast()) else { return .none }
            } else {
                guard Self.pairless.contains(stray) else { return .none }
            }
            return .deleteBeforeEnter
        }
        if Self.adjacentKeys[keyCode] != nil, Self.enterKeys.contains(before.keyCode),
           !(bracketTypesLetter && keyCode == Self.bracketKey) { return .dropKey }
        return .none
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
