import Foundation

/// The proper-noun lists of spec §17.1.1–17.1.2, read from Resources/ProperNouns.json.
/// Places and single words keep their canonical casing; every other list is lowercase.
public struct ProperNounData: Decodable {
    public let places: [String]
    /// Places that are also ordinary phrases ("hòa bình"): capitalised only right after a place cue.
    public let ambiguousPlaces: [String]
    public let placeCues: [String]
    /// Places that are not capitalised right after one of these words, which make them an ordinary phrase
    /// ("cập nhật bản" is "update the version", "xã hội an toàn" a safe society). Keys are lowercase places.
    public let placeNotAfter: [String: [String]]
    public let surnames: [String]
    /// Surnames that are never ordinary words, so they are capitalised on their own.
    public let sureSurnames: [String]
    public let middleNames: [String]
    public let givenNames: [String]
    /// Given names that are not capitalised right after one of these words, which make them a common noun
    /// ("vương quốc", a kingdom). Keys are lowercase given names.
    public let givenNameNotAfter: [String: [String]]
    /// Forms of address; learned names (§17.1.3) may be tied to them.
    public let titles: [String]
    public let singleWords: [String]

    public init(places: [String] = [], ambiguousPlaces: [String] = [], placeCues: [String] = [],
                placeNotAfter: [String: [String]] = [:], surnames: [String] = [], sureSurnames: [String] = [], middleNames: [String] = [],
                givenNames: [String] = [], givenNameNotAfter: [String: [String]] = [:], titles: [String] = [],
                singleWords: [String] = []) {
        self.places = places
        self.ambiguousPlaces = ambiguousPlaces
        self.placeCues = placeCues
        self.placeNotAfter = placeNotAfter
        self.surnames = surnames
        self.sureSurnames = sureSurnames
        self.middleNames = middleNames
        self.givenNames = givenNames
        self.givenNameNotAfter = givenNameNotAfter
        self.titles = titles
        self.singleWords = singleWords
    }

    /// Empty if the resource cannot be read, so typing goes on without capitalisation instead of crashing.
    public static let bundled: ProperNounData = {
        guard let url = Bundle.module.url(forResource: "ProperNouns", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(ProperNounData.self, from: data)
        else { return ProperNounData() }
        return file
    }()
}

/// Names the user taught by typing them capitalised (§17.1.3).
public protocol LearnedNameLookup {
    /// The learned cased form of `word` (lowercased) after `previous` (lowercased, nil at phrase start), or nil.
    func name(after previous: String?, word: String) -> String?
}

/// Replace the last `wordCount` words of the phrase with `words`.
public struct Capitalization: Equatable {
    public let wordCount: Int
    public let words: [String]

    public init(wordCount: Int, words: [String]) {
        self.wordCount = wordCount
        self.words = words
    }
}

/// Decides which just-typed words to capitalise (spec §17.1.1–17.1.2, then learned names).
/// A port of the measured prototype (tools/capbench): wrong capitals are worse than missing ones.
public struct ProperNounRules {
    private let places: Set<[String]>
    private let longestPlace: Int
    private let ambiguous: Set<String>
    private let cues: Set<String>
    private let notAfter: [String: Set<String>]
    private let surnames: Set<String>
    private let sureSurnames: Set<String>
    private let middleNames: Set<String>
    private let givenNames: Set<String>
    private let givenNotAfter: [String: Set<String>]
    private let learned: LearnedNameLookup?

    public init(data: ProperNounData = .bundled, learned: LearnedNameLookup? = nil) {
        let phrases = (data.places + data.singleWords).map { $0.split(separator: " ").map { Self.key(String($0)) } }
        places = Set(phrases)
        longestPlace = phrases.map(\.count).max() ?? 0
        ambiguous = Set(data.ambiguousPlaces.map(Self.phraseKey))
        cues = Set(data.placeCues.map(Self.phraseKey))
        notAfter = Dictionary(data.placeNotAfter.map { (Self.phraseKey($0.key), Set($0.value.map(Self.key))) },
                              uniquingKeysWith: { $0.union($1) })
        surnames = Set(data.surnames.map(Self.key))
        sureSurnames = Set(data.sureSurnames.map(Self.key))
        middleNames = Set(data.middleNames.map(Self.key))
        givenNames = Set(data.givenNames.map(Self.key))
        givenNotAfter = Dictionary(data.givenNameNotAfter.map { (Self.key($0.key), Set($0.value.map(Self.key))) },
                                   uniquingKeysWith: { $0.union($1) })
        self.learned = learned
    }

    /// The lookup form of a word: lowercase, with the tone mark moved to the end, so tone placement does not matter
    /// ("hoá" and "hóa", "thuỷ" and "thủy" share a key). Letter marks (â ă ê ô ơ ư đ) stay where they are.
    static func key(_ word: String) -> String {
        var scalars = String.UnicodeScalarView()
        var tone: Unicode.Scalar?
        for s in word.lowercased().decomposedStringWithCanonicalMapping.unicodeScalars {
            if toneMarks.contains(s.value) { tone = tone ?? s } else { scalars.append(s) }
        }
        if let tone { scalars.append(tone) }
        return String(scalars)
    }

    private static func phraseKey(_ phrase: String) -> String {
        phrase.split(separator: " ").map { key(String($0)) }.joined(separator: " ")
    }

    /// Combining grave, acute, tilde, hook above, dot below.
    private static let toneMarks: Set<UInt32> = [0x300, 0x301, 0x303, 0x309, 0x323]

    /// `words`: the words no punctuation separates from the word just committed, as on screen, oldest first, ending
    /// with that word. `firstWordStartsPhrase`: `words[0]` is the phrase's first word (after . ! ?, a newline, or
    /// as far as the caller knows), so its capital is sentence case, not a name (ruling R11). nil = nothing to change.
    public func capitalization(for words: [String], firstWordStartsPhrase: Bool = true) -> Capitalization? {
        // The rules read at most a place and the two cue words before it (ruling R14: a long run costs no more).
        let reach = max(longestPlace + 2, 3)
        if words.count > reach {
            return capitalization(for: Array(words.suffix(reach)), firstWordStartsPhrase: false)
        }
        guard let last = words.last, Self.isTouchable(last) else { return nil }
        let keys = words.map(Self.key)  // case is all `out` changes, so these stay valid for `out` too
        let i = words.count - 1
        var out = words
        var first = words.count  // leftmost word a rule covered

        // Place phrases ending at the last word, longest first. An ambiguous one without a cue ends the search.
        for length in stride(from: min(longestPlace, words.count), through: 1, by: -1) {
            let start = words.count - length
            let phrase = Array(keys[start...])
            guard places.contains(phrase) else { continue }
            if ambiguous.contains(phrase.joined(separator: " ")) {
                let before = keys[max(0, start - 2)..<start]
                let cued = before.last.map { cues.contains($0) } == true
                    || (!before.isEmpty && cues.contains(before.joined(separator: " ")))
                if !cued { break }
            }
            // An ordinary phrase after this word ("cập nhật bản", "xã hội an"): ends the search like a missing cue.
            if start > 0, notAfter[phrase.joined(separator: " ")]?.contains(keys[start - 1]) == true { break }
            for k in start...i { out[k] = Self.capitalized(out[k]) }
            first = start
            break
        }

        // Names, on the words as they now stand.
        let word = keys[i]
        let p1 = i >= 1 ? out[i - 1] : nil
        let p1Key = i >= 1 ? keys[i - 1] : nil
        let p2Key = i >= 2 ? keys[i - 2] : nil
        // Not a given name where the word before makes a common noun of it ("vương quốc", a kingdom).
        let isGivenName = givenNames.contains(word) && givenNotAfter[word]?.contains(p1Key ?? "") != true
        // A capital on screen that marks a name: not the phrase's first word's, which is sentence case ("Mai anh đi
        // đâu"), unless that word is a sure surname.
        func marked(_ k: Int) -> Bool {
            Self.startsUpper(out[k]) && (k > 0 || !firstWordStartsPhrase || sureSurnames.contains(keys[k]))
        }
        if sureSurnames.contains(word) {
            out[i] = Self.capitalized(out[i]); first = min(first, i)
        } else if middleNames.contains(word), let p1Key, surnames.contains(p1Key),
                  sureSurnames.contains(p1Key) || marked(i - 1) {
            out[i - 1] = Self.capitalized(out[i - 1]); out[i] = Self.capitalized(out[i]); first = min(first, i - 1)
        } else if let p1Key, let p2Key, marked(i - 1), middleNames.contains(p1Key), surnames.contains(p2Key) {
            out[i] = Self.capitalized(out[i]); first = min(first, i)
        } else if isGivenName, let p1Key, surnames.contains(p1Key),
                  sureSurnames.contains(p1Key) || marked(i - 1) {
            out[i - 1] = Self.capitalized(out[i - 1]); out[i] = Self.capitalized(out[i]); first = min(first, i - 1)
        } else if isGivenName, let p2Key, marked(i - 1), marked(i - 2),
                  surnames.contains(p2Key) || middleNames.contains(p2Key) {
            out[i] = Self.capitalized(out[i]); first = min(first, i)
        } else if words[i] == words[i].lowercased(),
                  let form = learned?.name(after: p1?.lowercased(), word: words[i]), form.lowercased() == words[i] {
            out[i] = form; first = min(first, i)
        }

        guard out != words else { return nil }
        return Capitalization(wordCount: words.count - first, words: Array(out[first...]))
    }

    /// All lowercase or capitalised. Others (`iPhone`, `FOMO`) are the user's own spelling and never touched.
    private static func isTouchable(_ word: String) -> Bool {
        word == word.lowercased() || (startsUpper(word) && word.dropFirst() == word.dropFirst().lowercased())
    }

    private static func startsUpper(_ word: String) -> Bool {
        word.first?.isUppercase == true
    }

    /// First letter upper; anything not all lowercase is left exactly as typed.
    private static func capitalized(_ word: String) -> String {
        guard word == word.lowercased(), let head = word.first else { return word }
        return head.uppercased() + word.dropFirst()
    }
}
