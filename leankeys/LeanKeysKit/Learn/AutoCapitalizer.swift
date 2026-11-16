import Foundation

/// Spec 17.1 for `EngineRouter` on the Vikey path: which just-typed words to capitalise when a word is committed,
/// as an edit of the text on screen, and the last such edit, for ⌫ to undo (17.1.4).
///
/// Single-threaded, like the router (the key-handling thread). Nothing typed is logged or kept beyond `last`.
final class AutoCapitalizer {
    /// Marks a capitalisation undo in the 4C rule book: `rulePrefix` + the lowercased phrase.
    static let rulePrefix = "cap:"

    /// A capitalisation to make: replace `original` (the last characters before the cursor) with `capitalized`.
    struct Replacement: Equatable {
        /// The affected words with what separates them, as on screen.
        let original: String
        let capitalized: String
        /// The rule-book text for undoing it: "cap:" + the affected words as typed, lowercased, one space apart.
        let rule: String
        /// The word before the affected ones, lowercased; "" at the start of the run.
        let previous: String
        /// What the rules were asked, and what they answered.
        let words: [String]
        let capitalization: Capitalization
    }

    /// The capitalisation just made, with how many characters the break key added after it.
    struct Made {
        let replacement: Replacement
        let breakLength: Int
    }

    private let rules: ProperNounRules
    /// The rules without learned names: a difference from `rules` means a learned name made the capitalisation.
    private let fixedRules: ProperNounRules

    /// Set right after a capitalisation; the router takes it at the next key.
    var last: Made?

    init(data: ProperNounData = .bundled, learned: LearnedNameLookup?) {
        rules = ProperNounRules(data: data, learned: learned)
        fixedRules = ProperNounRules(data: data, learned: nil)
    }

    /// What to capitalise now that the word ending `phraseText` (the current phrase before the cursor, as on
    /// screen) is committed; nil for nothing or when `keepsLowercase(rule, previous)` says the user undid it here.
    ///
    /// The rules see only the words no punctuation separates from the last one (spec 17.1: not across punctuation),
    /// so the replaced span holds words and spaces only.
    func replacement(phraseText: String, keepsLowercase: (String, String) -> Bool) -> Replacement? {
        guard let lastCharacter = phraseText.last, TextMirror.isWordCharacter(lastCharacter) else { return nil }
        let runStart = phraseText.lastIndex(where: { !TextMirror.isWordCharacter($0) && $0 != " " })
            .map { phraseText.index(after: $0) } ?? phraseText.startIndex
        let run = phraseText[runStart...]
        let ranges = Self.wordRanges(in: run)
        let words = ranges.map { String(run[$0]) }
        guard let capitalization = rules.capitalization(for: words),
              capitalization.wordCount > 0, capitalization.wordCount <= words.count,
              capitalization.words.count == capitalization.wordCount else { return nil }

        let first = words.count - capitalization.wordCount
        let affected = Array(words[first...])
        let rule = Self.rulePrefix + affected.joined(separator: " ").lowercased()
        let previous = first > 0 ? words[first - 1].lowercased() : ""
        guard !keepsLowercase(rule, previous) else { return nil }

        var capitalized = ""
        var cursor = ranges[first].lowerBound
        for (range, word) in zip(ranges[first...], capitalization.words) {
            capitalized += run[cursor..<range.lowerBound]
            capitalized += word
            cursor = range.upperBound
        }
        let original = String(run[ranges[first].lowerBound...])
        guard capitalized != original else { return nil }
        return Replacement(original: original, capitalized: capitalized, rule: rule, previous: previous,
                           words: words, capitalization: capitalization)
    }

    /// The learned name that made `replacement`, lowercased, or nil when the fixed rules alone made it.
    func learnedName(in replacement: Replacement) -> String? {
        guard fixedRules.capitalization(for: replacement.words) != replacement.capitalization else { return nil }
        return replacement.words.last?.lowercased()
    }

    /// The ranges of the letter/digit runs in `text`, in order.
    private static func wordRanges(in text: Substring) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var start: String.Index?
        var i = text.startIndex
        while i < text.endIndex {
            if TextMirror.isWordCharacter(text[i]) {
                if start == nil { start = i }
            } else if let s = start {
                ranges.append(s..<i)
                start = nil
            }
            i = text.index(after: i)
        }
        if let s = start { ranges.append(s..<text.endIndex) }
        return ranges
    }
}
