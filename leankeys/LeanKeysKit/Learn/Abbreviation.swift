import Foundation
import VikeyShim

/// Suggests a trigger name (tên tắt) for a learned phrase.
public enum Abbreviation {
    /// A free trigger for `candidate`. `existing` holds the current gõ tắt triggers, lowercased.
    ///
    /// Every name types as itself in Telex (ruling R15) and has at least two letters (R17).
    /// Phones, tax codes and addresses get fixed names (sdt, mst, dchi; R18) that skip the real-word check.
    /// Emails get "em", or "eml" when "em" is a real word (it is). A phrase gets every word's first letter,
    /// unaccented and lowercase (ruling R1), then those initials without vowels, then the phrase's first two
    /// consonants; a name that is taken, a real word or changed by Telex moves on. Last comes a number on the first
    /// of those that types as itself: sdt2, sdt3, coacdqt2.
    /// Main (key-handling) thread only: replays through the engine's global state.
    public static func suggest(for candidate: Candidate, existing: Set<String>,
                               isRealWord: (String) -> Bool = Abbreviation.isRealWord) -> String {
        let taken = Set(existing.map { $0.lowercased() })
        let (names, avoidWords, bases) = choices(for: candidate)
        var typesCache: [String: Bool] = [:]
        func types(_ name: String) -> Bool {
            if let known = typesCache[name] { return known }
            let result = typesAsIs(name)
            typesCache[name] = result
            return result
        }
        func free(_ name: String) -> Bool {
            name.count >= 2 && types(name) && !taken.contains(name) && !(avoidWords && isRealWord(name))
        }
        if let name = names.first(where: free) { return name }
        let base = bases.first { $0.count >= 2 && types($0) } ?? safeLetters(candidate.text, types) ?? "gt"
        var n = 2
        while taken.contains("\(base)\(n)") || (avoidWords && isRealWord("\(base)\(n)")) { n += 1 }
        return "\(base)\(n)"
    }

    /// True when `s` is a word Vikey's dictionaries see more than once per million words, in English or as
    /// Vietnamese Telex keys. Unaccented letters match the unaccented Vietnamese word: "em", "an", "co", "khong".
    /// Main (key-handling) thread only: replays through the engine's global state.
    public static func isRealWord(_ s: String) -> Bool {
        let word = s.lowercased()
        guard isPlainLetters(word) else { return false }
        return lk_vikey_word_score(0, word) > 0 || lk_vikey_word_score(1, word) > 0
    }

    /// True when typing `s` in Vietnamese Telex shows exactly `s`: "sdt" is, "dd" (đ), "as" (á) and "w" (ư) are not.
    /// Main (key-handling) thread only: replays through the engine's global state, and afterwards resets the
    /// typing context as a click would.
    public static func typesAsIs(_ s: String) -> Bool {
        let word = s.lowercased()
        guard isPlainLetters(word) else { return false }
        return lk_vikey_types_as_is(word) == 1
    }

    private static func isPlainLetters(_ word: String) -> Bool {
        !word.isEmpty && word.unicodeScalars.allSatisfy { ("a"..."z").contains($0) }
    }

    /// The names to try in order, whether real words are to be avoided, and the names a number may go on.
    private static func choices(for candidate: Candidate) -> ([String], Bool, [String]) {
        switch candidate.kind {
        case .phone: return (["sdt"], false, ["sdt"])
        case .taxCode: return (["mst"], false, ["mst"])
        case .address: return (["dchi"], false, ["dchi"])
        case .email: return (["em", "eml"], true, ["eml"])
        case .phrase:
            let first = initials(candidate.text)
            let letters = plainLetters(candidate.text)
            var names: [String] = []
            for name in [first, consonants(first), String(consonants(letters).prefix(2))]
            where name.count >= 2 && !names.contains(name) { names.append(name) }
            return (names, true, names)
        }
    }

    private static func consonants(_ s: String) -> String { s.filter { !"aeiouy".contains($0) } }

    /// Two of the phrase's letters, in order, that type as themselves ("Đi đâu": di), or nil.
    private static func safeLetters(_ text: String, _ types: (String) -> Bool) -> String? {
        var out = ""
        for letter in plainLetters(text) where out.count < 2 && types(out + String(letter)) { out.append(letter) }
        return out.count == 2 ? out : nil
    }

    /// Every letter of `text`, unaccented and lowercase, đ as d.
    private static func plainLetters(_ text: String) -> String {
        String(text.compactMap { $0.isLetter ? plainLetter($0) : nil })
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
