import CoreGraphics

/// US ANSI key codes for the characters the bench types.
/// Anything outside this table is unmappable and the caller must refuse it.
public enum KeyMap {
    private static let letters: [Character: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "o": 31, "u": 32,
        "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46,
    ]

    private static let digits: [Character: CGKeyCode] = [
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "9": 25, "7": 26, "8": 28, "0": 29,
    ]

    /// Punctuation typed without Shift on US ANSI.
    private static let unshiftedPunctuation: [Character: CGKeyCode] = [
        ",": 43, ".": 47, "'": 39, "-": 27, "/": 44, ";": 41,
    ]

    /// Punctuation that needs Shift on US ANSI.
    private static let shiftedPunctuation: [Character: CGKeyCode] = [
        "!": 18, "?": 44, "(": 25, ")": 29, ":": 41, "\"": 39,
    ]

    private static let backspaceCode: CGKeyCode = 51
    private static let spaceCode: CGKeyCode = 49

    /// Returns the key code and Shift state needed to type `c` on the US layout,
    /// or nil if the character cannot be typed. The backtick is the bench's
    /// stand-in for Backspace (key code 51).
    public static func stroke(for c: Character) -> (keyCode: CGKeyCode, shift: Bool)? {
        if c == "`" { return (backspaceCode, false) }
        if c == " " { return (spaceCode, false) }
        if let code = digits[c] { return (code, false) }
        if let code = letters[c] { return (code, false) }
        // Uppercase ASCII letters: same key as the lowercase letter, with Shift.
        if let ascii = c.asciiValue, (65...90).contains(ascii),
           let code = letters[Character(UnicodeScalar(ascii + 32))] {
            return (code, true)
        }
        if let code = unshiftedPunctuation[c] { return (code, false) }
        if let code = shiftedPunctuation[c] { return (code, true) }
        return nil
    }
}
