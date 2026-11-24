import Foundation

/// Which learned phrases are worth a gõ tắt, and in what order (design 2026-11-24, tiers 1–2).
///
/// A suggestion is worth what it saves: sightings × (Telex keys of the text − keys of the trigger and its Space).
/// Short chat replies ("dạ vâng ạ", "ok em nhé") save a few keys a use and are left out; so is a phrase seen on one
/// day only. Of candidates that overlap (one holds all the other's words, in order) only one shows: a recognised
/// piece (phone, tax code, email, address) before a phrase, else the best. The others stay counted in the learner
/// and can come back. Pure: no engine, no I/O.
public enum SuggestionRanking {
    /// A phrase must save at least this many keys each time it is used. 15 (user asked to drop these, 2026-11-24) leaves out
    /// "đúng rồi anh", "haha đúng rồi" and "để em check lại", which save 12, 13 and 14.
    public static let minPhraseSaving = 15
    /// A phrase must have been seen on at least this many days.
    public static let minPhraseDays = 2

    /// Shown order: best first, overlaps hidden; a phrase loses a capital that only starts its sentence.
    public static func rank(_ ready: [Candidate]) -> [Candidate] {
        let scored = ready.compactMap { c -> (Candidate, Int, [String])? in
            let saving = savingPerUse(c)
            if c.kind == .phrase {
                guard c.days >= minPhraseDays, saving >= minPhraseSaving else { return nil }
            } else {
                guard saving > 0 else { return nil }
            }
            return (c, c.count * saving, words(c.text))
        }
        .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.text < $1.0.text }

        // Phones, tax codes, emails and addresses are chosen first: one is reused more widely than a sentence holding
        // it ("Email của em là an@vidu.vn" hides behind the email). The shown order stays by score.
        var chosen: [(Candidate, Int, [String])] = []
        for pass in [false, true] {
            for (c, score, w) in scored where (c.kind == .phrase) == pass && !chosen.contains(where: { overlaps($0.2, w) }) {
                chosen.append((c, score, w))
            }
        }
        return chosen.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.text < $1.0.text }.map { c, _, _ in
            let text = c.kind == .phrase ? sentenceCaseStripped(c.text) : c.text
            return Candidate(id: c.id, text: text, kind: c.kind, count: c.count, days: c.days)
        }
    }

    /// Keys saved each time the gõ tắt is used instead of typing the text, with the trigger the candidate will
    /// likely get: sdt, mst, eml (3), dchi (4), a phrase's initials (3 to 5).
    static func savingPerUse(_ c: Candidate) -> Int {
        let trigger: Int
        switch c.kind {
        case .phone, .taxCode, .email: trigger = 3
        case .address: trigger = 4
        case .phrase: trigger = min(5, max(3, Abbreviation.initials(c.text).count))
        }
        return telexKeys(c.text) - trigger - 1
    }

    /// Keys to type `text` in Telex: one per character, one more for đ (dd), for â ê ô (aa), for ă ơ ư (w) and
    /// for a tone mark. "ầ" is 3.
    public static func telexKeys(_ text: String) -> Int {
        text.reduce(0) { total, ch in
            let lower = String(ch).lowercased()
            if lower == "đ" { return total + 2 }
            let marks = lower.decomposedStringWithCanonicalMapping.unicodeScalars.filter { telexMarks.contains($0.value) }
            return total + 1 + marks.count
        }
    }

    /// Circumflex, breve, horn; grave, acute, hook, tilde, dot below.
    private static let telexMarks: Set<UInt32> = [0x302, 0x306, 0x31B, 0x300, 0x301, 0x309, 0x303, 0x323]

    /// Drops a capital that only starts the sentence: the first word is capitalised (not all capitals) and the
    /// second is not, so "Em gửi anh" is "em gửi anh" while "Nguyễn Văn An" keeps its capital. Both engines
    /// capitalise the result after a capitalised trigger, so the start of a sentence still comes out right.
    public static func sentenceCaseStripped(_ text: String) -> String {
        let parts = text.split(separator: " ", maxSplits: 1)
        guard parts.count == 2, let first = parts[0].first, first.isUppercase,
              !parts[0].filter(\.isLetter).allSatisfy(\.isUppercase),
              let second = parts[1].first(where: \.isLetter), !second.isUppercase
        else { return text }
        return first.lowercased() + text.dropFirst()
    }

    /// Lowercased runs of letters and digits.
    private static func words(_ text: String) -> [String] {
        TextMirror.words(in: PhraseDetector.normalizedKey(text))
    }

    /// One word list holds the other as a run of whole words.
    private static func overlaps(_ a: [String], _ b: [String]) -> Bool {
        contains(a, b) || contains(b, a)
    }

    private static func contains(_ haystack: [String], _ needle: [String]) -> Bool {
        guard !needle.isEmpty, needle.count <= haystack.count else { return false }
        return (0...(haystack.count - needle.count)).contains { Array(haystack[$0..<($0 + needle.count)]) == needle }
    }
}
