import Foundation

/// Laban Key-style optional Advanced Telex initial consonant doubling:
/// typing `cc, gg, kk, nn, pp, qq, tt` at word start expands to `ch, gi, kh, ng, ph, qu, th`.
public enum AdvancedTelex {
    /// Mac virtual key codes for initial consonants -> second key of the digraph (`k -> h`, `c -> h`, etc.).
    private static let doubleInitialMap: [UInt16: (letter: Character, secondKeyCode: UInt16)] = [
        8:  ("c", 4),   // cc -> ch (h = 4)
        5:  ("g", 34),  // gg -> gi (i = 34)
        40: ("k", 4),   // kk -> kh (h = 4)
        45: ("n", 5),   // nn -> ng (g = 5)
        35: ("p", 4),   // pp -> ph (h = 4)
        12: ("q", 32),  // qq -> qu (u = 32)
        17: ("t", 4),   // tt -> th (h = 4)
    ]

    /// When `enabled`, `vietnamese` is active, and `currentWord` consists solely of the single consonant matching
    /// `keyCode`, returns the key code of the second letter of the digraph (`ch, gi, kh, ng, ph, qu, th`).
    public static func translatedKeyCode(keyCode: UInt16, currentWord: String,
                                         vietnamese: Bool, enabled: Bool) -> UInt16 {
        guard enabled, vietnamese,
              currentWord.count == 1,
              let first = currentWord.first,
              let entry = doubleInitialMap[keyCode],
              Character(first.lowercased()) == entry.letter
        else { return keyCode }
        return entry.secondKeyCode
    }
}
