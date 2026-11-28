import Foundation

/// Display rules from the research report "Gợi ý từ tiếng Việt trên máy" (2026-11-28): a fast typist pays a glance
/// (~760 ms to pick on touch, Li & Feit) for every list shown, so show only rows likely to pay that back.
///
/// 1. At a word start, and for "word + next word" look-ahead rows, only the user's own learned phrases: guesses
///    there are right ~10 % of the time, for QuickType too, and their scores do not tell right from wrong.
/// 2. A completion shows from `minTypedLetters` letters on.
/// 3. Every row must save at least `minKeysSaved` Telex keystrokes over typing it out (Tab counts as one key).
/// 4. At most `maxRows` rows.
///
/// Bench `testGatedPolicyVersusUngated` (2026-11-28, ±3 points run to run): ungated the list showed on 96 % of
/// keystrokes and 70 % were wasted glances; with 2 letters / 2 keys it shows on 38 %, wasted 28 %, row 1 right
/// 26 % when shown (28 % ungated), and Tab on an exact row 1 saves 17 % of Telex keys (30 % ungated). A 3-key bar
/// cut glances to 22 % but row 1 accuracy to 20 % and savings to 13.5 %.
public enum SuggestionGate {
    public static var minKeysSaved = 2
    public static let maxRows = 2
    /// Letters typed before a completion shows (learned phrases and Gõ Tắt excepted): row 1 is right ~53 % after two
    /// letters on the bench, far less after one.
    public static var minTypedLetters = 2

    /// Telex keystrokes to type `text`: one per letter, plus one per modified vowel or đ (aa, aw, ee, oo, ow, uw,
    /// dd) and one per tone mark (s f r x j); "ươ" takes a single w (`dduowjc` = "được"). An approximation: it
    /// ignores other Telex shortcuts (w → ư) and typos.
    public static func telexKeys(_ text: String) -> Int {
        var keys = 0
        let lower = text.precomposedStringWithCanonicalMapping.lowercased()
        // ư followed by ơ (any tone): the w is shared.
        var prevWasHornU = false
        for ch in lower {
            let base = String(ch).decomposedStringWithCanonicalMapping.unicodeScalars
            let hasHorn = base.contains { $0.value == 0x031B }
            let isO = base.first == "o"
            if prevWasHornU && hasHorn && isO { keys -= 1 }
            prevWasHornU = hasHorn && base.first == "u"
        }
        for ch in lower {
            guard ch.isLetter || ch.isNumber else { keys += 1; continue }
            keys += 1
            let decomposed = String(ch).decomposedStringWithCanonicalMapping.unicodeScalars
            for s in decomposed.dropFirst() {
                switch s.value {
                case 0x0302, 0x0306, 0x031B: keys += 1 // circumflex, breve, horn: aa/aw/ow...
                case 0x0300, 0x0301, 0x0303, 0x0309, 0x0323: keys += 1 // tone marks
                default: break
                }
            }
            if ch == "đ" { keys += 1 }
        }
        return keys
    }

    /// Keys a row saves: what is left to type (its insertion, trailing space included) minus the one Tab press.
    public static func keysSaved(_ c: PredictionCandidate, typed: String) -> Int {
        let typedKeys = c.deleteCount > 0 ? telexKeys(String(c.display.prefix(c.deleteCount))) : 0
        return telexKeys(c.insertion) - typedKeys - 1
    }

    static func isLearnedPhrase(_ c: PredictionCandidate) -> Bool {
        c.isPersonal && c.kind != .word && c.kind != .shortcut
    }

    public static func apply(_ rows: [PredictionCandidate], phase: PredictionPhase, query: PredictionQuery) -> [PredictionCandidate] {
        let typed = query.currentWord.precomposedStringWithCanonicalMapping.lowercased()
        let kept = rows.filter { c in
            if c.kind == .shortcut { return true } // the user's own Gõ Tắt: always worth showing
            switch phase {
            case .next:
                guard isLearnedPhrase(c) else { return false }
            case .ahead, .mid:
                if typed.count < minTypedLetters && !isLearnedPhrase(c) { return false }
                let parts = c.display.lowercased().split(whereSeparator: \.isWhitespace)
                let isLookAhead = parts.count >= 2 && parts[0] == typed
                if isLookAhead && !isLearnedPhrase(c) { return false }
            }
            return keysSaved(c, typed: typed) >= minKeysSaved
        }
        return Array(kept.prefix(maxRows))
    }
}
