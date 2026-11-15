import Foundation
import VikeyShim

/// Vikey's engine (vendor/vikey) as a `TypingEngine`. Vikey keeps its state in process-wide globals,
/// so every instance drives the same engine.
public final class VikeyEngine: TypingEngine {
    /// nil when lk_vikey_init() fails.
    public init?() {
        guard lk_vikey_init() == 1 else { return nil }
    }

    public func process(keyCode: UInt16, caps: Bool, shift: Bool) -> EngineEdit? {
        let letter = Self.letterKeys.contains(keyCode)
        // Ruling R3: for letters Caps Lock flips Shift; other keys take Shift as it is.
        let vikeyShift = letter ? (shift != caps) : shift

        if Self.navigationKeys.contains(keyCode) {
            resetContext()
            return nil
        }

        var raw = lk_edit()
        lk_vikey_press(keyCode, vikeyShift ? 1 : 0, ProcessInfo.processInfo.systemUptime, &raw)
        let edit = Self.edit(from: &raw)
        // Return finishes the word (Vikey may fix it), then the next word starts fresh.
        if Self.returnKeys.contains(keyCode) { resetContext() }

        if edit.deleteCount == 0 && edit.text.isEmpty && !edit.languageChanged { return nil }
        // Ruling R9: a plain Backspace (delete one, nothing typed) is the key's native effect.
        if keyCode == 51 && edit.deleteCount == 1 && edit.text.isEmpty && !edit.languageChanged { return nil }
        if edit.deleteCount == 0 && !edit.languageChanged,
           let own = Self.ownCharacter(keyCode: keyCode, shift: vikeyShift), edit.text == [own] {
            return nil
        }
        return edit
    }

    public func resetContext() {
        lk_vikey_reset_context()
    }

    public func setVietnamese(_ on: Bool) {
        lk_vikey_set_language(on ? 1 : 0)
    }

    public var isVietnamese: Bool { lk_vikey_language() == 1 }

    // MARK: - Mac virtual key codes (vendor/vikey/Engine/platforms/mac.h)

    private static let returnKeys: Set<UInt16> = [36, 76]
    /// Arrows, Tab and Esc: the cursor or the field changes, nothing to look back on.
    private static let navigationKeys: Set<UInt16> = [123, 124, 125, 126, 48, 53]

    private static let letters: [UInt16: Character] = [
        0: "a", 11: "b", 8: "c", 2: "d", 14: "e", 3: "f", 5: "g", 4: "h", 34: "i", 38: "j", 40: "k", 37: "l", 46: "m",
        45: "n", 31: "o", 35: "p", 12: "q", 15: "r", 1: "s", 17: "t", 32: "u", 9: "v", 13: "w", 7: "x", 16: "y", 6: "z",
    ]
    private static let letterKeys = Set(letters.keys)

    /// Non-letter keys on a US layout: (plain, with Shift).
    private static let symbols: [UInt16: (Character, Character)] = [
        18: ("1", "!"), 19: ("2", "@"), 20: ("3", "#"), 21: ("4", "$"), 23: ("5", "%"),
        22: ("6", "^"), 26: ("7", "&"), 28: ("8", "*"), 25: ("9", "("), 29: ("0", ")"),
        33: ("[", "{"), 30: ("]", "}"), 47: (".", ">"), 43: (",", "<"), 50: ("`", "~"), 27: ("-", "_"),
        24: ("=", "+"), 42: ("\\", "|"), 41: (";", ":"), 39: ("'", "\""), 44: ("/", "?"),
        49: (" ", " "), 36: ("\n", "\n"), 76: ("\n", "\n"),
    ]

    /// What the key types by itself.
    private static func ownCharacter(keyCode: UInt16, shift: Bool) -> Character? {
        if let c = letters[keyCode] { return shift ? Character(c.uppercased()) : c }
        if let (plain, shifted) = symbols[keyCode] { return shift ? shifted : plain }
        return nil
    }

    private static func edit(from raw: inout lk_edit) -> EngineEdit {
        let count = max(0, min(Int(raw.length), 256))
        let units: [UInt16] = withUnsafeBytes(of: &raw.text) { Array($0.bindMemory(to: UInt16.self).prefix(count)) }
        return EngineEdit(deleteCount: Int(raw.deleteCount),
                          text: Array(String(decoding: units, as: UTF16.self)),
                          languageChanged: raw.languageChanged != 0)
    }
}
