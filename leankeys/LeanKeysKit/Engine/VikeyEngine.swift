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
        // The macOS key path passes caps = Shift || Caps Lock, and macOS types capitals when either is held
        // (Shift does not invert Caps Lock). So a letter is upper case exactly when `caps` is set; other keys
        // take Shift as it is. (Phase-1 ruling R3 used Shift XOR caps, which turned "DD" + Shift into "đ".)
        let vikeyShift = letter ? caps : shift

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
        // Ruling R12: a break key (Return/Enter, punctuation) that Vikey appends after fixing the word is typed by
        // the key itself, so Return still submits and the host sees the real key. Space stays in the text: the
        // key handler does not let Space through after an edit.
        if let own = Self.ownCharacter(keyCode: keyCode, shift: vikeyShift), Self.isBreakCharacter(own),
           edit.text.last == own {
            let text = Array(edit.text.dropLast())
            if edit.deleteCount == 0 && text.isEmpty && !edit.languageChanged { return nil }
            return EngineEdit(deleteCount: edit.deleteCount, text: text, languageChanged: edit.languageChanged,
                              keyPassesThrough: true)
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

    /// Spec 12.1: Backspace right after a doubled key ("hocjj") gives back the Vietnamese word ("học").
    /// On by default; process-wide, like the engine.
    public static func setDoubleKeyFix(_ on: Bool) {
        lk_vikey_set_double_key_fix(on ? 1 : 0)
    }

    public func setAutoSwitch(_ on: Bool) {
        Self.options.autoSwitch = on
        Self.applyOptions()
    }

    public func setModernTone(_ on: Bool) {
        Self.options.modernTone = on
        Self.applyOptions()
    }

    /// lk_vikey_set_options sets all three at once, so the current values live here (process-wide, like the
    /// engine). Defaults match the shim's: modern orthography, auto switch on, plain Telex.
    private static var options = (modernTone: true, autoSwitch: true, telexStyle: Int32(0))

    private static func applyOptions() {
        lk_vikey_set_options(options.modernTone ? 1 : 0, options.autoSwitch ? 1 : 0, options.telexStyle)
    }

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

    /// Characters whose key the macOS key handler lets through after an edit: Return/Enter and the punctuation
    /// it counts as break keys. Not Space, letters or digits.
    private static func isBreakCharacter(_ c: Character) -> Bool {
        c == "\n" || !(c == " " || c.isLetter || c.isNumber)
    }

    /// What the key types when the app gets it untouched: `caps` (Shift or Caps Lock) cases letters, Shift picks
    /// the symbol. nil for keys without a character (arrows, Esc, Backspace, function keys).
    static func typedCharacter(keyCode: UInt16, shift: Bool, caps: Bool) -> Character? {
        keypad[keyCode] ?? ownCharacter(keyCode: keyCode, shift: letterKeys.contains(keyCode) ? caps : shift)
    }

    /// Keypad digits and decimal point (Carbon kVK_ANSI_Keypad0…9, kVK_ANSI_KeypadDecimal). Only for `typedCharacter`.
    private static let keypad: [UInt16: Character] = [
        82: "0", 83: "1", 84: "2", 85: "3", 86: "4", 87: "5", 88: "6", 89: "7", 91: "8", 92: "9", 65: ".",
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
