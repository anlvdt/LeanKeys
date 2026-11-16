import Foundation

/// A learned "keep as typed" rule (spec 12.2): after the user undid Vikey's switch of `text` with ⌫⌫, leave it alone.
public struct UndoRule: Codable, Equatable, Identifiable {
    public var id: String { previous + "\u{1F}" + text }
    /// The word before the switch, lowercase.
    public let text: String
    /// The word before it on the line, lowercase; "" for a rule that holds in any context.
    public let previous: String
    /// Undos counted.
    public var count: Int
    public var lastUsed: Date
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

    private struct Snapshot: Codable {
        var v = 1
        var rules: [UndoRule]
        var blocked: [String: Int]
    }

    private let store: LearnStore?
    private let now: () -> Date
    private let lock = NSLock()
    private let saveQueue = DispatchQueue(label: "io.github.anlvdt.leankeys.undo-rules.save")

    // Guarded by `lock`.
    private var entries: [Key: UndoRule] = [:]
    /// Text → same-direction undos still needed before its rules apply again.
    private var blocked: [String: Int] = [:]
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
                if !previous.isEmpty { bump(Key(previous: previous, text: text), at: date) }
                bump(Key(previous: "", text: text), at: date)
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

    /// The rules worth showing: every context rule, and contextless counts of 2 or more, except for blocked texts
    /// (they apply nowhere yet). Most recently used first.
    public var rules: [UndoRule] {
        let (all, blocks) = lock.withLock { (entries, blocked) }
        return all.values.filter { blocks[$0.text] == nil && (!$0.previous.isEmpty || $0.count >= 2) }
            .sorted { $0.lastUsed != $1.lastUsed ? $0.lastUsed > $1.lastUsed : $0.id < $1.id }
    }

    public func remove(_ rule: UndoRule) {
        let removed = lock.withLock {
            entries.removeValue(forKey: Key(previous: rule.previous, text: rule.text)) != nil
        }
        if removed { didChange() }
    }

    /// Forgets every rule, hidden count and block. A file this session could not read is erased, so its rules do
    /// not come back at the next launch; from then on changes are saved (ruling R16).
    public func removeAll() {
        let eraseUnreadable: Bool = lock.withLock {
            entries = [:]
            blocked = [:]
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

    private func evictOverCapacity() {
        while entries.count > Self.capacity {
            guard let oldest = entries.min(by: { $0.value.lastUsed < $1.value.lastUsed })?.key else { return }
            entries[oldest] = nil
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
            let (saved, savedBlocks) = lock.withLock {
                savePending = false
                return (entries, blocked)
            }
            let snapshot = Snapshot(rules: Array(saved.values), blocked: savedBlocks)
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? store?.save(data)
        }
    }
}
