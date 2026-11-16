import CryptoKit
import Foundation
import VikeyShim

/// A proper name the user typed with a capital often enough to learn (spec 17.1.3).
public struct LearnedName: Codable, Equatable, Identifiable {
    public var id: String { form.lowercased() }
    /// The cased form as typed, NFC.
    public let form: String
    /// True for a dictionary word: only written with this form right after a title ("anh Hùng").
    public var afterTitleOnly: Bool
    /// Observations counted.
    public var count: Int
    public var lastUsed: Date
}

/// The names learned from words the user types with a capital mid-sentence (spec 17.1.3).
///
/// - A word typed right after a title (`titles`) counts toward "after title".
/// - A word whose ASCII-folded letters are no dictionary word (`isDictionaryWord` false) counts toward "anywhere".
/// - At `threshold` observations the word is learned with its cased form; `afterTitleOnly` is false only for
///   non-dictionary words. Below the threshold only `HMAC-SHA256(lowercased word) → (count, afterTitleSeen,
///   lastUsed)` is kept, never the word.
/// - At most `capacity` learned names, and as many hidden counts; the least recently used goes first.
/// - The second undo of a learned name (anywhere) removes it.
///
/// Thread-safe behind one lock, held only for dictionary work: `name(after:word:)` runs on the key-handling thread
/// and does no I/O. Every change is saved through `store` on a private serial queue (JSON; the store encrypts it)
/// and announced through `onChange` on the main queue. Nothing is logged.
public final class LearnedNames: LearnedNameLookup {
    public static let capacity = 2_000, threshold = 2

    private struct Pending: Codable {
        var count: Int
        var afterTitleSeen: Bool
        var lastUsed: Date
    }

    private struct Snapshot: Codable {
        var v = 1
        var names: [LearnedName]
        /// HMAC hex → hidden count.
        var pending: [String: Pending]
        /// Learned name id → undos so far.
        var undos: [String: Int]
    }

    private let store: LearnStore?
    private let key: SymmetricKey
    private let titles: Set<String>
    private let isDictionaryWord: (String) -> Bool
    private let now: () -> Date
    private let lock = NSLock()
    private let saveQueue = DispatchQueue(label: "io.github.anlvdt.leankeys.learned-names.save")

    // Guarded by `lock`.
    private var learned: [String: LearnedName] = [:]
    private var pending: [String: Pending] = [:]
    private var undos: [String: Int] = [:]
    private var savePending = false
    /// The store could not be read at launch: nothing is saved this session, so its file is never overwritten.
    private var persistent: Bool
    private var _onChange: (() -> Void)?

    /// Loads the saved names synchronously. `store == nil` keeps them in memory only. `hmacKey` must be 32 bytes
    /// (from `LearnKeyProvider.hmacKey()`); otherwise a random key is used for this instance's lifetime, so saved
    /// hidden counts match nothing after a restart. `isDictionaryWord` receives the word's ASCII-folded lowercase
    /// letters ("Đường" → "duong"); `LearnedNames.isDictionaryWord(_:)` is the real check.
    public init(store: LearnStore?, hmacKey: Data?, titles: Set<String>, isDictionaryWord: @escaping (String) -> Bool,
                now: @escaping () -> Date = Date.init) {
        self.store = store
        if let hmacKey, hmacKey.count == 32 {
            key = SymmetricKey(data: hmacKey)
        } else {
            key = SymmetricKey(size: .bits256)
        }
        self.titles = Set(titles.map(Self.normalized))
        self.isDictionaryWord = isDictionaryWord
        self.now = now
        persistent = store != nil
        guard let store else { return }
        do {
            if let data = try store.load(), let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
                for name in snapshot.names where !name.form.isEmpty && name.count > 0 {
                    learned[Self.normalized(name.form)] = name
                }
                pending = snapshot.pending.filter { $0.value.count > 0 && $0.value.count < Self.threshold }
                undos = snapshot.undos.filter { learned[$0.key] != nil && $0.value > 0 }
                evictOverCapacity()
            }
        } catch {
            persistent = false
        }
    }

    /// Called on the main queue after a change to `names`.
    public var onChange: (() -> Void)? {
        get { lock.withLock { _onChange } }
        set { lock.withLock { _onChange = newValue } }
    }

    /// A word the user typed with a capital (Shift or Caps Lock), mid-sentence, not all caps, at least 2 letters,
    /// not capitalised by LeanKeys. `previous` = the word before it (lowercased) or nil.
    ///
    /// The caller decides "typed by the user, mid-sentence, not by LeanKeys, not in Secure Input or an excluded
    /// app"; this drops words without a capital, all caps, or with fewer than 2 letters.
    public func observe(word: String, previous: String?) {
        let form = word.precomposedStringWithCanonicalMapping
        guard Self.looksLikeTypedName(form) else { return }
        let id = form.lowercased()
        let afterTitle = previous.map { titles.contains(Self.normalized($0)) } ?? false
        let anywhere = !isDictionaryWord(Self.asciiFolded(id))
        guard afterTitle || anywhere else { return }
        let digest = Self.digest(id, key: key)

        let namesChanged: Bool = lock.withLock {
            let date = now()
            if var name = learned[id] {
                name.count += 1
                name.lastUsed = date
                learned[id] = name
                return true
            }
            var hidden = pending[digest] ?? Pending(count: 0, afterTitleSeen: false, lastUsed: date)
            hidden.count += 1
            hidden.afterTitleSeen = hidden.afterTitleSeen || afterTitle
            hidden.lastUsed = date
            if hidden.count >= Self.threshold {
                pending[digest] = nil
                learned[id] = LearnedName(form: form, afterTitleOnly: !anywhere, count: hidden.count, lastUsed: date)
                evictOverCapacity()
                return true
            }
            pending[digest] = hidden
            evictOverCapacity()
            return false
        }
        if namesChanged { didChange() } else { scheduleSave() }
    }

    /// The learned form of `word` when it is learned and either holds anywhere or `previous` is a title. A hit marks
    /// the name used. Key-handling thread: one short lock, no I/O.
    public func name(after previous: String?, word: String) -> String? {
        let id = Self.normalized(word)
        let isTitle = previous.map { titles.contains(Self.normalized($0)) } ?? false
        let form: String? = lock.withLock {
            guard var name = learned[id], !name.afterTitleOnly || isTitle else { return nil }
            name.lastUsed = now()
            learned[id] = name
            return name.form
        }
        // The new `lastUsed` is saved, but the UI is not told: only the order of `names` moved.
        if form != nil { scheduleSave() }
        return form
    }

    /// The user undid a capitalisation of `word`; the second undo of a learned name (anywhere) removes it.
    public func undone(word: String) {
        let id = Self.normalized(word)
        let outcome: (counted: Bool, removed: Bool) = lock.withLock {
            guard learned[id] != nil else { return (false, false) }
            let count = (undos[id] ?? 0) + 1
            if count >= 2 {
                learned[id] = nil
                undos[id] = nil
                return (true, true)
            }
            undos[id] = count
            return (true, false)
        }
        if outcome.removed { didChange() } else if outcome.counted { scheduleSave() }
    }

    /// Learned names (at or above the threshold) only, most recently used first.
    public var names: [LearnedName] {
        let all = lock.withLock { learned }
        return all.values.sorted { $0.lastUsed != $1.lastUsed ? $0.lastUsed > $1.lastUsed : $0.id < $1.id }
    }

    public func remove(_ name: LearnedName) {
        let id = Self.normalized(name.form)
        let removed: Bool = lock.withLock {
            undos[id] = nil
            return learned.removeValue(forKey: id) != nil
        }
        if removed { didChange() }
    }

    /// Forgets every name, hidden count and undo count.
    public func removeAll() {
        lock.withLock {
            learned = [:]
            pending = [:]
            undos = [:]
        }
        didChange()
    }

    /// Waits for queued saves, for tests.
    func flush() { saveQueue.sync {} }

    // MARK: Words

    /// The real dictionary check for `isDictionaryWord`: `letters` (ASCII, lowercase) is a word in Vikey's English
    /// or Vietnamese dictionary, however rare (any score but `LK_VIKEY_NOT_A_WORD`). Key-handling thread only: the
    /// Vietnamese lookup replays through the engine's global state.
    public static func isDictionaryWord(_ letters: String) -> Bool {
        lk_vikey_word_score(0, letters) != LK_VIKEY_NOT_A_WORD || lk_vikey_word_score(1, letters) != LK_VIKEY_NOT_A_WORD
    }

    /// Lowercase without Vietnamese marks, đ as d: "Đường" → "duong".
    static func asciiFolded(_ word: String) -> String {
        let lower = word.lowercased().replacingOccurrences(of: "đ", with: "d")
        let scalars = lower.decomposedStringWithCanonicalMapping.unicodeScalars
            .filter { !(0x0300...0x036F).contains($0.value) }
        return String(String.UnicodeScalarView(scalars))
    }

    /// At least 2 letters, at least one capital, not every letter a capital. Letters only, save `-` `'` `’` between
    /// two letters ("Ê-đê"): a word with a digit or another symbol ("Matkhau2024", "Abc@xyz"), or one shaped like a
    /// secret, is never counted, not even as a digest.
    private static func looksLikeTypedName(_ word: String) -> Bool {
        let chars = Array(word)
        for (i, c) in chars.enumerated() where !c.isLetter {
            guard Self.joiners.contains(c), i > 0, i < chars.count - 1,
                  chars[i - 1].isLetter, chars[i + 1].isLetter else { return false }
        }
        guard !Exclusions.looksLikeSecret(word) else { return false }
        let letters = chars.filter(\.isLetter)
        guard letters.count >= 2 else { return false }
        return letters.contains(where: \.isUppercase) && !letters.allSatisfy(\.isUppercase)
    }

    private static let joiners: Set<Character> = ["-", "'", "’"]

    private static func normalized(_ word: String) -> String {
        word.precomposedStringWithCanonicalMapping.lowercased()
    }

    private static func digest(_ text: String, key: SymmetricKey) -> String {
        HMAC<SHA256>.authenticationCode(for: Data(text.utf8), using: key).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Under the lock

    private func evictOverCapacity() {
        while learned.count > Self.capacity {
            guard let oldest = learned.min(by: { $0.value.lastUsed < $1.value.lastUsed })?.key else { return }
            learned[oldest] = nil
            undos[oldest] = nil
        }
        while pending.count > Self.capacity {
            guard let oldest = pending.min(by: { $0.value.lastUsed < $1.value.lastUsed })?.key else { return }
            pending[oldest] = nil
        }
    }

    // MARK: Saving

    private func didChange() {
        scheduleSave()
        DispatchQueue.main.async { [weak self] in self?.onChange?() }
    }

    /// Queues one save; changes made before it runs ride along.
    private func scheduleSave() {
        guard store != nil else { return }
        let schedule: Bool = lock.withLock {
            guard persistent, !savePending else { return false }
            savePending = true
            return true
        }
        guard schedule else { return }
        saveQueue.async { [self] in
            // Copy-on-write copies: the lock is held for no real work.
            let (names, hidden, undone) = lock.withLock {
                savePending = false
                return (learned, pending, undos)
            }
            let snapshot = Snapshot(names: Array(names.values), pending: hidden, undos: undone)
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? store?.save(data)
        }
    }
}
