import Foundation
import VikeyShim

/// Suggests a trigger name (tên tắt) for a learned phrase.
public enum Abbreviation {
    /// A free trigger for `candidate`. `existing` holds the current gõ tắt triggers, lowercased.
    ///
    /// Phones, tax codes and addresses get the spec's fixed names (sdt, mst, dc). Emails get "em", or "eml" when
    /// "em" is a real word (it is). A phrase gets every word's first letter, unaccented and lowercase (ruling R1).
    /// A name that is taken, or for emails and phrases a real word, gets a number: sdt2, sdt3, coacdqt2.
    public static func suggest(for candidate: Candidate, existing: Set<String>,
                               isRealWord: (String) -> Bool = Abbreviation.isRealWord) -> String {
        let taken = Set(existing.map { $0.lowercased() })
        let (names, avoidWords) = choices(for: candidate)
        func free(_ name: String) -> Bool { !taken.contains(name) && !(avoidWords && isRealWord(name)) }
        if let name = names.first(where: free) { return name }
        let base = names[names.count - 1]
        var n = 2
        while !free("\(base)\(n)") { n += 1 }
        return "\(base)\(n)"
    }

    /// True when `s` is a word Vikey's dictionaries see more than once per million words, in English or as
    /// Vietnamese Telex keys. Unaccented letters match the unaccented Vietnamese word: "em", "an", "co", "khong".
    /// Runs the engine for the Vietnamese side, so call it on the key-handling (main) thread.
    public static func isRealWord(_ s: String) -> Bool {
        let word = s.lowercased()
        guard !word.isEmpty, word.unicodeScalars.allSatisfy({ ("a"..."z").contains($0) }) else { return false }
        return lk_vikey_word_score(0, word) > 0 || lk_vikey_word_score(1, word) > 0
    }

    /// The names to try in order, and whether real words are to be avoided. The fixed names are kept even when
    /// they read as a word ("dc" is an English word to Vikey).
    private static func choices(for candidate: Candidate) -> ([String], Bool) {
        switch candidate.kind {
        case .phone: return (["sdt"], false)
        case .taxCode: return (["mst"], false)
        case .address: return (["dc"], false)
        case .email: return (["em", "eml"], true)
        case .phrase:
            let letters = initials(candidate.text)
            return ([letters.isEmpty ? "gt" : letters], true)
        }
    }

    /// Every word's first letter, unaccented and lowercase, with đ as d: "Cảm ơn anh chị đã quan tâm" is coacdqt.
    /// Leading punctuation is skipped; a word that starts with a digit or a symbol adds nothing.
    static func initials(_ text: String) -> String {
        var out = ""
        for word in text.split(whereSeparator: { $0.isWhitespace }) {
            guard let first = word.first(where: { $0.isLetter || $0.isNumber }), first.isLetter,
                  let letter = plainLetter(first) else { continue }
            out.append(letter)
        }
        return out
    }

    private static func plainLetter(_ c: Character) -> Character? {
        let folded = String(c).replacingOccurrences(of: "đ", with: "d").replacingOccurrences(of: "Đ", with: "D")
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX")).lowercased()
        guard let first = folded.first, first.isASCII, first.isLetter else { return nil }
        return first
    }
}
