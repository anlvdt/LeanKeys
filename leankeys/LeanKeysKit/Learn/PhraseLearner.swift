import CryptoKit
import Foundation

/// Where a phrase was typed.
public struct LearnContext {
    public let bundleID: String?
    public let secureInput: Bool
    public let secureField: Bool
    public let now: Date

    public init(bundleID: String?, secureInput: Bool, secureField: Bool, now: Date) {
        self.bundleID = bundleID
        self.secureInput = secureInput
        self.secureField = secureField
        self.now = now
    }
}

public enum PhraseKind: String, Codable {
    case phone, taxCode, address, email, phrase
}

/// A phrase seen often enough to suggest a gõ tắt for.
public struct Candidate: Identifiable, Equatable {
    /// HMAC-SHA256 of the item, hex.
    public let id: String
    public let text: String
    public let kind: PhraseKind
    /// Sightings in the window.
    public let count: Int
    /// Days in the window with at least one sighting.
    public let days: Int

    public init(id: String, text: String, kind: PhraseKind, count: Int, days: Int = 1) {
        self.id = id
        self.text = text
        self.kind = kind
        self.count = count
        self.days = days
    }
}

/// Counts the phrases the user types again and again, so the app can suggest a gõ tắt for them.
///
/// Privacy: below the threshold only an HMAC-SHA256 digest of each item is kept, with its count per day. The text
/// itself is kept from the moment the item reaches the threshold until the user accepts or dismisses it, or its
/// sightings leave the window. Nothing is learned while disabled (the default), under Secure Input, in a secure text
/// field, in an excluded app or an unknown one (no bundle ID), or from a phrase holding a card number or an OTP.
/// Nothing is logged. Single-threaded, like `TextMirror`.
public final class PhraseLearner {
    /// Off until the user turns it on. Turning it off also wipes every stored text (the digests and day counts stay),
    /// so nothing readable is kept while learning is off.
    public var enabled = false {
        didSet { if !enabled { wipePlaintext() } }
    }
    public var excludedBundleIDs: Set<String> = Exclusions.defaultBundleIDs

    private let store: LearnStore
    private let threshold: Int
    private let windowDays: Int
    private let minLength: Int

    private var key: SymmetricKey?
    /// The saved state was read. Until then nothing is counted or saved, so an unreadable store is never overwritten.
    private var loaded = false
    private var entries: [String: Entry] = [:]
    /// Accepted or dismissed, by digest: never suggested again.
    private var handled: Set<String> = []

    public init(store: LearnStore, threshold: Int = 3, windowDays: Int = 30, minLength: Int = 8) {
        self.store = store
        self.threshold = max(1, threshold)
        self.windowDays = max(1, windowDays)
        self.minLength = minLength
        _ = loadIfNeeded(now: Date())
    }

    public func observe(_ phrase: CommittedPhrase, context: LearnContext) {
        guard enabled, !context.secureInput, !context.secureField,
              let bundleID = context.bundleID, !excludedBundleIDs.contains(bundleID),
              !Exclusions.isExcludedByDefault(bundleID) else { return }
        let text = PhraseDetector.normalizedDisplay(phrase.text)
        guard !text.isEmpty, !Exclusions.containsSensitiveNumber(text), loadIfNeeded(now: context.now),
              let key = hmacKeyIfNeeded() else { return }

        let today = Self.day(context.now)
        prune(today: today)
        var seen: Set<String> = []
        for item in PhraseDetector.items(in: text) where item.display.count >= minLength {
            let id = Self.digest(item.key, key: key)
            guard seen.insert(id).inserted, !handled.contains(id) else { continue }
            var entry = entries[id] ?? Entry()
            entry.days[String(today), default: 0] += 1
            if entry.count >= threshold {
                entry.text = item.display
                entry.kind = item.kind
            }
            entries[id] = entry
        }
        save()
    }

    /// At the threshold, with their text, not yet accepted or dismissed. Most seen first.
    public var ready: [Candidate] {
        entries.compactMap { id, entry -> Candidate? in
            guard !handled.contains(id), let text = entry.text, let kind = entry.kind, entry.count >= threshold
            else { return nil }
            return Candidate(id: id, text: text, kind: kind, count: entry.count, days: entry.days.count)
        }
        .sorted { $0.count != $1.count ? $0.count > $1.count : $0.text < $1.text }
    }

    /// Never suggest it again (remembered by digest); its text and counts go.
    public func dismiss(_ c: Candidate) { handle(c) }

    /// The user added the gõ tắt: its text and counts go, and it is never suggested again.
    public func accept(_ c: Candidate) { handle(c) }

    /// Forget everything: counts, texts, dismissals, the file and its keys.
    public func eraseAll() {
        entries = [:]
        handled = []
        key = nil
        loaded = true
        do { try store.erase() } catch { save() }
    }

    /// Items currently counted, for tests.
    var trackedCount: Int { entries.count }

    // MARK: State

    private struct Entry: Codable {
        /// Day number (UTC days since 1970) → sightings that day.
        var days: [String: Int] = [:]
        var text: String?
        var kind: PhraseKind?

        var count: Int { days.values.reduce(0, +) }

        enum CodingKeys: String, CodingKey { case days = "d", text = "t", kind = "k" }
    }

    private struct Snapshot: Codable {
        var v = 1
        var entries: [String: Entry]
        var handled: [String]
    }

    /// Drops kept texts that today's rules would never have learned: a whole-line phrase with one word or a
    /// password-shaped word, or a text holding a card number or OTP. Before this rule a password typed in a terminal
    /// could reach the review list.
    private func purgeSecretShapedTexts() {
        var changed = false
        for (id, entry) in entries {
            guard let text = entry.text else { continue }
            let bad = Exclusions.containsSensitiveNumber(text)
                || (entry.kind == .phrase && !PhraseDetector.isLearnablePhrase(text))
            if bad { entries[id] = nil; changed = true }
        }
        if changed { save() }
    }

    private func wipePlaintext() {
        guard loaded, entries.values.contains(where: { $0.text != nil || $0.kind != nil }) else { return }
        for (id, var entry) in entries where entry.text != nil || entry.kind != nil {
            entry.text = nil
            entry.kind = nil
            entries[id] = entry
        }
        save()
    }

    private func handle(_ c: Candidate) {
        guard loadIfNeeded(now: Date()) else { return }
        handled.insert(c.id)
        entries[c.id] = nil
        save()
    }

    /// Reads the saved state once; false while it cannot be read (try again later). Never touches the HMAC key, so
    /// a learner that stays disabled creates no Keychain item.
    private func loadIfNeeded(now: Date) -> Bool {
        guard !loaded else { return true }
        do {
            if let data = try store.load(),
               let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
                entries = snapshot.entries
                handled = Set(snapshot.handled)
            }
        } catch {
            return false
        }
        loaded = true
        purgeSecretShapedTexts()
        prune(today: Self.day(now))
        return true
    }

    /// The HMAC key, fetched (and on first use created) only when something is about to be counted.
    private func hmacKeyIfNeeded() -> SymmetricKey? {
        if key == nil {
            if let provider = store as? LearnKeyProvider {
                guard let data = try? provider.hmacKey(), data.count == 32 else { return nil }
                key = SymmetricKey(data: data)
            } else {
                key = SymmetricKey(size: .bits256)
            }
        }
        return key
    }

    /// Drops sightings older than the window, items with none left, and the text of items now below the threshold.
    private func prune(today: Int) {
        let oldest = today - windowDays + 1
        for (id, var entry) in entries {
            entry.days = entry.days.filter { (Int($0.key) ?? .min) >= oldest }
            if entry.days.isEmpty {
                entries[id] = nil
                continue
            }
            if entry.count < threshold {
                entry.text = nil
                entry.kind = nil
            }
            entries[id] = entry
        }
    }

    private func save() {
        guard loaded else { return }
        let snapshot = Snapshot(entries: entries, handled: handled.sorted())
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? store.save(data)
    }

    private static func day(_ date: Date) -> Int { Int((date.timeIntervalSince1970 / 86_400).rounded(.down)) }

    private static func digest(_ text: String, key: SymmetricKey) -> String {
        HMAC<SHA256>.authenticationCode(for: Data(text.utf8), using: key).map { String(format: "%02x", $0) }.joined()
    }
}

/// Finds what to count in a phrase: the phrase itself, plus any phone number, tax code, email or address in it.
enum PhraseDetector {
    struct Item: Equatable {
        let kind: PhraseKind
        /// What is digested: the kind, then the normalised text (digits only for numbers).
        let key: String
        /// What is shown once the item reaches the threshold.
        let display: String
    }

    /// NFC, trimmed, whitespace runs as one space. Case is kept for display.
    static func normalizedDisplay(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// NFC, lowercased, whitespace runs as one space.
    static func normalizedKey(_ text: String) -> String {
        normalizedDisplay(text).lowercased()
    }

    // A number never starts or ends inside a longer one: no digit (or digit and separator) right before or after.
    private static let before = #"(?<![\d+])(?<!\d[ .\-])"#
    private static let after = #"(?![ .\-]?\d)"#
    /// `0` or `+84`, then 9 digits; spaces, dots or dashes allowed between digits.
    private static let phone = try! NSRegularExpression(pattern: before + #"(?:\+84|0)(?:[ .\-]?\d){9}"# + after)
    /// 10 digits, or 10 digits, `-` and 3 digits.
    private static let taxCode = try! NSRegularExpression(pattern: before + #"\d{10}(?:-\d{3})?"# + after)
    private static let email = try! NSRegularExpression(
        pattern: #"(?<![A-Za-z0-9._%+\-])[A-Za-z0-9._%+\-]+@[A-Za-z0-9\-]+(?:\.[A-Za-z0-9\-]+)*\.[A-Za-z]{2,}(?![A-Za-z0-9\-])"#)
    /// Address words, as whole words, any case. "thị xã" comes before "xã" so it counts once.
    private static let addressWord = try! NSRegularExpression(
        pattern: #"(?<![\p{L}\p{N}])(?:số|đường|phố|phường|thị xã|xã|quận|huyện|tp|tỉnh)(?![\p{L}\p{N}])"#,
        options: [.caseInsensitive])

    /// "số" before a number or "nhà" ("số 12", "số nhà 5"), not "số lượng" or "con số này".
    private static let soAddress = try! NSRegularExpression(pattern: #"^\s*(?:\d|nhà(?![\p{L}\p{N}]))"#,
                                                            options: [.caseInsensitive])
    /// "xã hội" (society) is no "xã".
    private static let xaHoi = try! NSRegularExpression(pattern: #"^\s+hội(?![\p{L}\p{N}])"#, options: [.caseInsensitive])
    /// One word of a place name after an address word, and the punctuation right after it.
    private static let nameToken = try! NSRegularExpression(pattern: #"(?:\s+|\.)([^\s,;:!?.]+)([,;:!?.]?)"#)
    /// Words that end a place name typed in lowercase: particles, pronouns and the like ("quận đống đa giúp em").
    private static let addressStopWords: Set<String> = [
        "nhé", "nha", "nhá", "nhe", "ạ", "à", "ha", "nhỉ", "ơi", "giúp", "với", "đi", "luôn", "thì", "mà", "là", "và",
        "em", "anh", "chị", "mình", "tôi", "bạn", "mai", "nay", "hôm", "cho", "của", "để", "nhưng", "rồi",
    ]
    /// Longest place name taken after the last address word: "tỉnh Bà Rịa Vũng Tàu".
    private static let maxNameWords = 4

    private static func isSo(_ range: NSRange, in ns: NSString) -> Bool {
        ns.substring(with: range).lowercased() == "số"
    }

    private static func isAddressWord(_ range: NSRange, in ns: NSString) -> Bool {
        let word = ns.substring(with: range).lowercased()
        let after = NSRange(location: range.location + range.length, length: ns.length - range.location - range.length)
        let rest = ns as String
        if word == "số" { return soAddress.firstMatch(in: rest, options: [.anchored], range: after) != nil }
        if word == "xã" { return xaHoi.firstMatch(in: rest, options: [.anchored], range: after) == nil }
        return true
    }

    /// Where the place name after the address word at `last` ends: a number ("quận 1"), or up to four words, ending
    /// before a stop word or at a comma or other punctuation.
    private static func addressEnd(after last: NSRange, in ns: NSString) -> Int {
        let text = ns as String
        var end = last.location + last.length
        var pos = end
        for i in 0..<maxNameWords {
            guard let m = nameToken.firstMatch(in: text, options: [.anchored],
                                               range: NSRange(location: pos, length: ns.length - pos)) else { break }
            let token = ns.substring(with: m.range(at: 1))
            if addressStopWords.contains(token.lowercased()) { break }
            let number = token.first?.isNumber == true
            if i > 0, number { break }
            end = m.range(at: 1).location + m.range(at: 1).length
            pos = m.range.location + m.range.length
            if number || m.range(at: 2).length > 0 { break }
        }
        return end
    }

    /// "mst", "thuế" (which covers "mã số thuế") or plain "thue" as a word, ignoring case but not diacritics, so
    /// "thuê" (to rent) never matches. `text` is already NFC.
    static func mentionsTax(_ text: String) -> Bool {
        text.lowercased().range(of: #"(?<![\p{L}\p{N}])(?:mst|thuế|thue)(?![\p{L}\p{N}])"#,
                                options: .regularExpression) != nil
    }

    /// A whole line counts as a phrase only when it has at least two words and no word outside the recognised pieces
    /// (phones, tax codes, emails, addresses) looks like a password. A password typed where macOS does not flag a
    /// password field (a terminal prompt, an app's own login box) ends with Return like any line: one word, or a
    /// password-shaped word in a line, never becomes a suggestion.
    private static let wordPattern = try! NSRegularExpression(pattern: #"\S+"#)

    static func isLearnablePhrase(_ text: String, outside pieces: [NSRange]? = nil) -> Bool {
        let ns = text as NSString
        let ranges = pieces ?? Self.pieces(in: text).map(\.0)
        var words = 0
        let wordRegex = try! NSRegularExpression(pattern: #"\S+"#)
        for m in wordRegex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            words += 1
            // The word without the punctuation around it ("an@vidu.vn." ends a sentence): covered by a recognised
            // piece (email, phone, tax code, address), it is that piece, not a password.
            let word = ns.substring(with: m.range)
            let core = Exclusions.trimmedWord(word)
            let coreStart = (word as NSString).range(of: core).location
            let coreRange = core.isEmpty || coreStart == NSNotFound ? m.range
                : NSRange(location: m.range.location + coreStart, length: (core as NSString).length)
            if ranges.contains(where: { NSIntersectionRange($0, coreRange).length == coreRange.length }) { continue }
            if Exclusions.looksLikeSecret(word) { return false }
        }
        return words >= 2
    }

    /// `text` must be `normalizedDisplay` output. The whole phrase comes first, as `.phrase` unless one piece
    /// covers all of it (then only that piece).
    static func items(in text: String) -> [Item] {
        let all = NSRange(location: 0, length: (text as NSString).length)
        let pieces = Self.pieces(in: text)
        var items: [Item] = []
        if !pieces.contains(where: { $0.0 == all }), isLearnablePhrase(text, outside: pieces.map(\.0)) {
            items.append(Item(kind: .phrase, key: "phrase:" + normalizedKey(text), display: text))
        }
        items += pieces.sorted { $0.0.location < $1.0.location }.map(\.1)
        return items
    }

    /// The recognised pieces of `text` (emails, phones, tax codes, an address) with their ranges.
    static func pieces(in text: String) -> [(NSRange, Item)] {
        let ns = text as NSString
        let all = NSRange(location: 0, length: ns.length)
        var pieces: [(NSRange, Item)] = []
        func overlaps(_ r: NSRange) -> Bool { pieces.contains { NSIntersectionRange($0.0, r).length > 0 } }

        for m in email.matches(in: text, range: all) {
            let s = ns.substring(with: m.range)
            pieces.append((m.range, Item(kind: .email, key: "email:" + s.lowercased(), display: s)))
        }
        let taxContext = mentionsTax(text)
        for m in phone.matches(in: text, range: all) where !overlaps(m.range) {
            let s = ns.substring(with: m.range)
            // A bare 0xxxxxxxxx next to "MST", "mã số thuế" or "thuế" is a tax code.
            if taxContext, s.range(of: #"^0\d{9}$"#, options: .regularExpression) != nil {
                pieces.append((m.range, Item(kind: .taxCode, key: "taxCode:" + s, display: s)))
                continue
            }
            var digits = s.filter(\.isNumber)
            if s.hasPrefix("+84") { digits = "0" + digits.dropFirst(2) }
            pieces.append((m.range, Item(kind: .phone, key: "phone:" + digits, display: s)))
        }
        for m in taxCode.matches(in: text, range: all) where !overlaps(m.range) {
            let s = ns.substring(with: m.range)
            pieces.append((m.range, Item(kind: .taxCode, key: "taxCode:" + s, display: s)))
        }
        // An address runs from its first address word to the name after its last one (design 2026-11-24, N5).
        let words = addressWord.matches(in: text, range: all).filter { isAddressWord($0.range, in: ns) }
        if words.count >= 2, words.contains(where: { !isSo($0.range, in: ns) }),
           let first = words.first, let last = words.last {
            let end = addressEnd(after: last.range, in: ns)
            let raw = ns.substring(with: NSRange(location: first.range.location, length: end - first.range.location))
            let s = raw.trimmingCharacters(in: CharacterSet(charactersIn: " .,;:"))
            let range = NSRange(location: first.range.location, length: (s as NSString).length)
            pieces.append((range, Item(kind: .address, key: "address:" + normalizedKey(s), display: s)))
        }

        return pieces
    }
}
