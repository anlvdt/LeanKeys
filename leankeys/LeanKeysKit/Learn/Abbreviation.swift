import Foundation
import VikeyShim

/// Suggests a trigger name (tên tắt) for a learned phrase.
public enum Abbreviation {
    /// A free trigger for `candidate`. `existing` holds the current gõ tắt triggers, lowercased.
    ///
    /// Every name types as itself in Telex (ruling R15), is not in the blocklist of chat words and rude words, and
    /// has at least two letters, three for a phrase (R17, amended 2026-11-24). Phones, tax codes and addresses get
    /// fixed names (sdt, mst, dchi; R18) that skip the real-word check. Emails get "em", or "eml" when "em" is a real
    /// word (it is). A phrase tries `phraseNames` in order, skipping real words. Only when every name is taken or a
    /// real word comes a number, on the first name that types as itself: sdt2, coacd2.
    /// Main (key-handling) thread only: replays through the engine's global state.
    public static func suggest(for candidate: Candidate, existing: Set<String>,
                               isRealWord: (String) -> Bool = Abbreviation.isRealWord) -> String {
        let taken = Set(existing.map { $0.lowercased() })
        let (names, avoidWords, bases) = choices(for: candidate)
        let minLetters = candidate.kind == .phrase ? 3 : 2
        var typesCache: [String: Bool] = [:]
        func types(_ name: String) -> Bool {
            if let known = typesCache[name] { return known }
            let result = typesAsIs(name)
            typesCache[name] = result
            return result
        }
        // No "w": it is Telex's ư key, in both engines, whatever Vikey's English restore makes of it ("xiwn").
        func usable(_ name: String) -> Bool {
            name.count >= minLetters && !name.contains("w") && !isBlocked(name) && types(name)
        }
        func free(_ name: String) -> Bool {
            usable(name) && !taken.contains(name) && !(avoidWords && isRealWord(name))
        }
        if let name = names.first(where: free) { return name }
        let vowelless = consonants(initials(candidate.text))
        let base = bases.first(where: usable)
            ?? (candidate.kind == .phrase && vowelless.count >= 2 && types(vowelless) ? vowelless : nil)
            ?? "gt"
        var n = 2
        while taken.contains("\(base)\(n)") || isBlocked("\(base)\(n)") || (avoidWords && isRealWord("\(base)\(n)")) {
            n += 1
        }
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

    /// True for chat words and rude words people type themselves (`TriggerBlocklist.txt`): as a trigger they would
    /// expand every time. Vikey's dictionaries do not hold them.
    public static func isBlocked(_ s: String) -> Bool { blocklist.contains(s.lowercased()) }

    private static let blocklist: Set<String> = {
        guard let url = Bundle.module.url(forResource: "TriggerBlocklist", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else {
            // A debug build stops here, so a broken resource never ships as a silently empty list.
            assertionFailure("TriggerBlocklist.txt is missing or unreadable")
            return []
        }
        return Set(text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") })
    }()

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
            let names = phraseNames(candidate.text)
            return (names, true, names)
        }
    }

    /// Names for a phrase, best first, each made of the phrase's own letters, 3 to 5 of them (design 2026-11-24):
    /// - the first letters of its first five, four, three words ("Cảm ơn anh chị đã quan tâm": coacd, coac, coa),
    ///   filler words (dạ, ạ, nhé, thì…) left out first, then kept ("Dạ em cảm ơn anh": ecoa, then decoa);
    /// - the same starting one or two words later, for initials Telex would change ("anh xem giúp em với": axgev
    ///   types ãgev, so xgev);
    /// - the first word's first two or three letters, then the next words' initials ("em cảm ơn": emco);
    /// - the first word's first four or three letters ("Shopee": shop, sho).
    /// Never letters that start no word, like the old "first two consonants" (which gave "cl").
    /// Not filtered: `suggest` drops the ones taken, real, blocked or changed by Telex.
    static func phraseNames(_ text: String) -> [String] {
        let all = initials(text)
        let content = initials(text, skipping: fillers)
        let firstWord = text.split(whereSeparator: \.isWhitespace).lazy
            .map { plainLetters(String($0)) }.first { !$0.isEmpty } ?? ""
        let rest = all.dropFirst()
        var names: [String] = []
        for length in [5, 4, 3] {
            names.append(String(content.prefix(length)))
            names.append(String(all.prefix(length)))
        }
        for start in [1, 2] where start < all.count {
            let tail = all.dropFirst(start)
            for length in [5, 4, 3] { names.append(String(tail.prefix(length))) }
        }
        names.append(String(firstWord.prefix(2)) + rest.prefix(3))
        names.append(String(firstWord.prefix(3)) + rest.prefix(2))
        names.append(String(firstWord.prefix(4)))
        names.append(String(firstWord.prefix(3)))
        var seen: Set<String> = []
        return names.filter { (3...5).contains($0.count) && seen.insert($0).inserted }
    }

    /// Words that add little to a phrase's meaning, skipped for the second set of initials.
    static let fillers: Set<String> = ["dạ", "ạ", "nhé", "nha", "nhá", "à", "ừ", "ơi", "thì", "là", "mà", "nhỉ",
                                       "vâng", "hả", "ha"]

    private static func consonants(_ s: String) -> String { s.filter { !"aeiouy".contains($0) } }

    /// Every letter of `text`, unaccented and lowercase, đ as d.
    private static func plainLetters(_ text: String) -> String {
        String(text.compactMap { $0.isLetter ? plainLetter($0) : nil })
    }

    /// Every word's first letter, unaccented and lowercase, with đ as d: "Cảm ơn anh chị đã quan tâm" is coacdqt.
    /// Leading punctuation is skipped; a word that starts with a digit or a symbol adds nothing; so does a word in
    /// `skipping` (lowercased, punctuation around it ignored).
    static func initials(_ text: String, skipping: Set<String> = []) -> String {
        var out = ""
        for word in text.split(whereSeparator: { $0.isWhitespace }) {
            if !skipping.isEmpty, skipping.contains(Exclusions.trimmedWord(String(word)).lowercased()) { continue }
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
