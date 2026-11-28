import Foundation

/// A learned "keep as typed" rule (spec 12.2): after the user undid Vikey's switch of `text` with ⌫⌫, leave it alone.
public enum UndoRuleKind: String, Codable {
    /// Leave `text` as typed after Vikey would switch it (spec 12.2).
    case keep
    /// Turn the raw keys `text` into the other form on the break key (convert-last-word design 5.3).
    case convert
}

public struct UndoRule: Codable, Equatable, Identifiable {
    public var id: String {
        // A keep rule's id is as before (existing callers); a convert rule's carries the kind and direction.
        guard kind == .convert else { return previous + "\u{1F}" + text }
        return "convert" + ((toRaw ?? false) ? "1" : "0") + "\u{1F}" + previous + "\u{1F}" + text
    }
    /// The word before the switch, lowercase.
    public let text: String
    /// The word before it on the line, lowercase; "" for a rule that holds in any context.
    public let previous: String
    /// Undos counted.
    public var count: Int
    public var lastUsed: Date
    /// `.keep` for a rule learned from ⌫⌫; absent in files from before convert rules.
    public var kind: UndoRuleKind = .keep
    /// Convert rules only (nil for `.keep`): true turns a Telex form into its raw keys, false turns raw keys into
    /// their Telex form. `text` is then the raw keys, lowercase.
    public var toRaw: Bool? = nil
}

extension UndoRule {
    private enum CodingKeys: String, CodingKey { case text, previous, count, lastUsed, kind, toRaw }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = try c.decode(String.self, forKey: .text)
        previous = try c.decode(String.self, forKey: .previous)
        count = try c.decode(Int.self, forKey: .count)
        lastUsed = try c.decode(Date.self, forKey: .lastUsed)
        kind = try c.decodeIfPresent(UndoRuleKind.self, forKey: .kind) ?? .keep
        toRaw = try c.decodeIfPresent(Bool.self, forKey: .toRaw)
    }
}

/// The learned "keep as typed" rules (spec 12.2–12.3).
///
/// - A context rule `(previous, text)` keeps `text` after `previous` from its first undo.
/// - The contextless count of `text` keeps it anywhere from its second undo.
/// - A reverse undo (the user undid a keep) drops every rule for `text` and blocks it. The next undos count as usual,
///   but nothing keeps `text` until two of them clear the block (spec 12.2: "thêm 2 lần hoàn tác cùng chiều mới tạo
///   lại luật"); from then its rules apply, the contextless one with the count those two undos made.
/// - At most `capacity` entries (context rules and contextless counts together); the least recently used goes first.
///
/// Thread-safe behind one lock, held only for dictionary work: `shouldKeep` runs on the key-handling thread and does
/// no I/O. Every change is saved through `store` on a private serial queue (JSON of the rules and blocks; the store
/// encrypts it) and announced through `onChange` on the main queue. Nothing is logged.
public final class UndoRuleBook {
    public static let capacity = 5_000

    private struct Key: Hashable {
        let previous: String
        let text: String
    }

    private struct ConvertKey: Hashable {
        let previous: String
        let keys: String
        let toRaw: Bool
    }

    /// File version 2 adds the optional keys; `rules` stays the keep rules only, so a version 1 reader still works.
    private struct Snapshot: Codable {
        var v = 2
        var rules: [UndoRule]
        var blocked: [String: Int]
        var convert: [UndoRule]?
        var convertBlocked: [String: Int]?
        var pinned: [String]?
    }

    static let pinCapacity = 500

    private let store: LearnStore?
    private let now: () -> Date
    private let lock = NSLock()
    private let saveQueue = DispatchQueue(label: "io.github.anlvdt.leankeys.undo-rules.save")

    // Guarded by `lock`.
    private var entries: [Key: UndoRule] = [:]
    /// Text → same-direction undos still needed before its rules apply again.
    private var blocked: [String: Int] = [:]
    private var convertEntries: [ConvertKey: UndoRule] = [:]
    /// "1"/"0" (toRaw) + US + keys → same-direction manual converts still needed.
    private var convertBlocked: [String: Int] = [:]
    /// Lowercase word → the word as pasted.
    private var pins: [String: String] = [:]
    private var savePending = false
    /// The store could not be read or decoded at launch: nothing is saved this session, so its file is never
    /// overwritten, until "Xoá tất cả" erases it (`removeAll`; ruling R16).
    private var persistent: Bool
    private var _onChange: (() -> Void)?

    /// Loads the saved rules synchronously. `store == nil` keeps them in memory only.
    public init(store: LearnStore?, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.now = now
        persistent = store != nil
        guard let store else { return }
        do {
            if let data = try store.load() {
                // A file that cannot be decoded (corrupt, or from a later version) is never overwritten (R16).
                guard let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else {
                    persistent = false
                    return
                }
                var purged = false
                for rule in snapshot.rules where !rule.text.isEmpty && rule.count > 0 {
                    // Saved before the secret check (security audit MEDIUM-4): dropped, and the file rewritten below.
                    if Self.isSecretShaped(rule.text) || Exclusions.looksLikeSecret(rule.previous) {
                        purged = true
                        continue
                    }
                    entries[Key(previous: rule.previous, text: rule.text)] = rule
                }
                blocked = snapshot.blocked.filter { $0.value > 0 && !Self.isSecretShaped($0.key) }
                purged = purged || blocked.count != snapshot.blocked.filter { $0.value > 0 }.count
                for rule in snapshot.convert ?? [] where rule.kind == .convert && !rule.text.isEmpty && rule.count > 0 {
                    if Self.isSecretShaped(rule.text) || Exclusions.looksLikeSecret(rule.previous) {
                        purged = true
                        continue
                    }
                    guard let toRaw = rule.toRaw else { continue }
                    convertEntries[ConvertKey(previous: rule.previous, keys: rule.text, toRaw: toRaw)] = rule
                }
                convertBlocked = (snapshot.convertBlocked ?? [:]).filter { $0.value > 0 }
                for word in snapshot.pinned ?? [] {
                    guard Self.pinnable(word), pins.count < Self.pinCapacity else { purged = true; continue }
                    pins[word.lowercased()] = word
                }
                evictOverCapacity()
                if purged { scheduleSave() }
            }
        } catch {
            persistent = false
        }
    }

    /// A rule text shaped like a password or key (`Exclusions.looksLikeSecret`). A capitalisation rule ("cap:" +
    /// phrase) is judged word by word, since the space between its words would read as a symbol.
    static func isSecretShaped(_ text: String) -> Bool {
        guard text.hasPrefix("cap:") else { return Exclusions.looksLikeSecret(text) }
        return text.dropFirst(4).split(separator: " ").contains { Exclusions.looksLikeSecret(String($0)) }
    }

    private static func pinnable(_ word: String) -> Bool {
        (2...38).contains(word.count) && word.unicodeScalars.allSatisfy { $0.isASCII && $0.properties.isAlphabetic }
            && !isSecretShaped(word)
    }

    private static func blockKey(_ keys: String, _ toRaw: Bool) -> String { (toRaw ? "1" : "0") + "\u{1F}" + keys }

    /// Called on the main queue after a change.
    public var onChange: (() -> Void)? {
        get { lock.withLock { _onChange } }
        set { lock.withLock { _onChange = newValue } }
    }

    /// One ⌫⌫ undo of Vikey switching `before`, typed after `previous` ("" when none). `reverse` marks the undo of a
    /// keep this book made. A secret-shaped `before` is never recorded, nor a secret-shaped `previous` kept as its
    /// context (security audit MEDIUM-4: an undo inside a password typed in plain text).
    public func record(before: String, previous: String, reverse: Bool) {
        let text = before.lowercased()
        guard !text.isEmpty, !Self.isSecretShaped(text) else { return }
        let previous = Exclusions.looksLikeSecret(previous) ? "" : previous.lowercased()
        lock.withLock {
            if reverse {
                entries = entries.filter { $0.key.text != text }
                blocked[text] = 2
            } else {
                let date = now()
                if !previous.isEmpty {
                    bump(Key(previous: previous, text: text), at: date)
                    eraseConvert(previous: previous, keys: text)
                }
                bump(Key(previous: "", text: text), at: date)
                eraseConvert(previous: "", keys: text)
                evictOverCapacity()
                if let left = blocked[text] { blocked[text] = left > 1 ? left - 1 : nil }
            }
        }
        didChange()
    }

    /// Whether to leave `before` (typed after `previous`) as typed. A hit marks the deciding rule used.
    public func shouldKeep(before: String, previous: String) -> Bool {
        let text = before.lowercased()
        let previous = previous.lowercased()
        let hit: Bool = lock.withLock {
            guard blocked[text] == nil else { return false }
            if !previous.isEmpty, markUsed(Key(previous: previous, text: text)) { return true }
            guard let rule = entries[Key(previous: "", text: text)], rule.count >= 2 else {
                return false
            }
            return markUsed(Key(previous: "", text: text))
        }
        // The new `lastUsed` is saved, but the UI is not told: only the order of `rules` moved.
        if hit { scheduleSave() }
        return hit
    }

    /// One manual ⌃⌫ convert of the raw keys `keys` (typed after `previous`), in direction `toRaw`. `reverse` marks the
    /// undo of a convert this book applied: it drops that text's convert rules of that direction and blocks them.
    public func recordConvert(keys: String, previous: String, toRaw: Bool, reverse: Bool) {
        let text = keys.lowercased()
        guard !text.isEmpty, !Self.isSecretShaped(text) else { return }
        let previous = Exclusions.looksLikeSecret(previous) ? "" : previous.lowercased()
        let blockKey = Self.blockKey(text, toRaw)
        lock.withLock {
            if reverse {
                convertEntries = convertEntries.filter { !($0.key.keys == text && $0.key.toRaw == toRaw) }
                convertBlocked[blockKey] = 2
            } else {
                let date = now()
                if !previous.isEmpty {
                    bumpConvert(ConvertKey(previous: previous, keys: text, toRaw: toRaw), at: date)
                    eraseKeep(previous: previous, text: text)
                }
                bumpConvert(ConvertKey(previous: "", keys: text, toRaw: toRaw), at: date)
                eraseKeep(previous: "", text: text)
                evictOverCapacity()
                if let left = convertBlocked[blockKey] { convertBlocked[blockKey] = left > 1 ? left - 1 : nil }
            }
        }
        didChange()
    }

    /// Whether to convert the raw keys `keys` (typed after `previous`) in direction `toRaw`. A hit marks the rule used.
    public func shouldConvert(keys: String, previous: String, toRaw: Bool) -> Bool {
        let text = keys.lowercased()
        let previous = previous.lowercased()
        let hit: Bool = lock.withLock {
            guard convertBlocked[Self.blockKey(text, toRaw)] == nil else { return false }
            if !previous.isEmpty, markConvertUsed(ConvertKey(previous: previous, keys: text, toRaw: toRaw)) { return true }
            let any = ConvertKey(previous: "", keys: text, toRaw: toRaw)
            guard let rule = convertEntries[any], rule.count >= 2 else { return false }
            return markConvertUsed(any)
        }
        if hit { scheduleSave() }
        return hit
    }

    /// Adds pasted words (one per line) to "Từ của tôi": ASCII letters only, 2–38 of them, at most 500 words, no
    /// duplicates (compared in lowercase). They apply anywhere, are never evicted and replace learned rules for the
    /// same text. Returns how many lines were added and skipped.
    public func pin(_ lines: [String]) -> (added: Int, skipped: Int) {
        var added = 0, skipped = 0
        lock.withLock {
            for line in lines {
                let word = line.trimmingCharacters(in: .whitespacesAndNewlines)
                let lower = word.lowercased()
                guard Self.pinnable(word), pins[lower] == nil, pins.count < Self.pinCapacity else {
                    skipped += 1
                    continue
                }
                pins[lower] = word
                entries = entries.filter { $0.key.text != lower }
                convertEntries = convertEntries.filter { $0.key.keys != lower }
                added += 1
            }
        }
        if added > 0 { didChange() }
        return (added, skipped)
    }

    public func unpin(_ word: String) {
        let removed = lock.withLock { pins.removeValue(forKey: word.lowercased()) != nil }
        if removed { didChange() }
    }

    /// The pinned words as pasted, sorted.
    public var pinnedWords: [String] {
        lock.withLock { Array(pins.values) }.sorted { $0.lowercased() < $1.lowercased() }
    }

    /// Whether `keys` (matched in lowercase) is a pinned word.
    public func isPinned(_ keys: String) -> Bool {
        let lower = keys.lowercased()
        return lock.withLock { pins[lower] != nil }
    }

    /// The rules worth showing: every context rule, and contextless counts of 2 or more, except for blocked texts
    /// (they apply nowhere yet). Most recently used first.
    public var rules: [UndoRule] {
        let (all, blocks, converts, convertBlocks) = lock.withLock { (entries, blocked, convertEntries, convertBlocked) }
        let keeps = all.values.filter { blocks[$0.text] == nil && (!$0.previous.isEmpty || $0.count >= 2) }
        let convs = converts.values.filter {
            convertBlocks[Self.blockKey($0.text, $0.toRaw ?? false)] == nil && (!$0.previous.isEmpty || $0.count >= 2)
        }
        return (keeps + convs)
            .sorted { $0.lastUsed != $1.lastUsed ? $0.lastUsed > $1.lastUsed : $0.id < $1.id }
    }

    public func remove(_ rule: UndoRule) {
        let removed = lock.withLock {
            if rule.kind == .convert {
                return convertEntries.removeValue(
                    forKey: ConvertKey(previous: rule.previous, keys: rule.text, toRaw: rule.toRaw ?? false)) != nil
            }
            return entries.removeValue(forKey: Key(previous: rule.previous, text: rule.text)) != nil
        }
        if removed { didChange() }
    }

    /// Forgets every rule, hidden count and block. A file this session could not read is erased, so its rules do
    /// not come back at the next launch; from then on changes are saved (ruling R16).
    public func removeAll() {
        let eraseUnreadable: Bool = lock.withLock {
            entries = [:]
            blocked = [:]
            convertEntries = [:]
            convertBlocked = [:]
            pins = [:]
            return !persistent && store != nil
        }
        if eraseUnreadable {
            saveQueue.async { [self] in
                guard (try? store?.erase()) != nil else { return }
                lock.withLock { persistent = true }
            }
        }
        didChange()
    }

    /// Waits for queued saves, for tests.
    func flush() { saveQueue.sync {} }

    // MARK: Under the lock

    private func bump(_ key: Key, at date: Date) {
        if var rule = entries[key] {
            rule.count += 1
            rule.lastUsed = date
            entries[key] = rule
        } else {
            entries[key] = UndoRule(text: key.text, previous: key.previous, count: 1, lastUsed: date)
        }
    }

    private func markUsed(_ key: Key) -> Bool {
        guard var rule = entries[key], rule.count >= 1 else { return false }
        rule.lastUsed = now()
        entries[key] = rule
        return true
    }

    private func bumpConvert(_ key: ConvertKey, at date: Date) {
        if var rule = convertEntries[key] {
            rule.count += 1
            rule.lastUsed = date
            convertEntries[key] = rule
        } else {
            convertEntries[key] = UndoRule(text: key.keys, previous: key.previous, count: 1, lastUsed: date,
                                           kind: .convert, toRaw: key.toRaw)
        }
    }

    private func markConvertUsed(_ key: ConvertKey) -> Bool {
        guard var rule = convertEntries[key], rule.count >= 1 else { return false }
        rule.lastUsed = now()
        convertEntries[key] = rule
        return true
    }

    /// Recording a convert for `(previous, text)` replaces the keep rule for it.
    private func eraseKeep(previous: String, text: String) {
        entries[Key(previous: previous, text: text)] = nil
    }

    /// Recording a keep for `(previous, keys)` replaces the convert rules for it, in both directions.
    private func eraseConvert(previous: String, keys: String) {
        convertEntries[ConvertKey(previous: previous, keys: keys, toRaw: true)] = nil
        convertEntries[ConvertKey(previous: previous, keys: keys, toRaw: false)] = nil
    }

    /// The least recently used entry goes first, whichever kind it is. Pins are not entries.
    private func evictOverCapacity() {
        while entries.count + convertEntries.count > Self.capacity {
            let oldKeep = entries.min(by: { $0.value.lastUsed < $1.value.lastUsed })
            let oldConvert = convertEntries.min(by: { $0.value.lastUsed < $1.value.lastUsed })
            if let k = oldKeep, oldConvert == nil || k.value.lastUsed <= oldConvert!.value.lastUsed {
                entries[k.key] = nil
            } else if let c = oldConvert {
                convertEntries[c.key] = nil
            } else {
                return
            }
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
            let (saved, savedBlocks, savedConverts, savedConvertBlocks, savedPins) = lock.withLock {
                savePending = false
                return (entries, blocked, convertEntries, convertBlocked, Array(pins.values))
            }
            let snapshot = Snapshot(rules: Array(saved.values), blocked: savedBlocks,
                                    convert: Array(savedConverts.values), convertBlocked: savedConvertBlocks,
                                    pinned: savedPins)
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? store?.save(data)
        }
    }
}
