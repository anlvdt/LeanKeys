import Combine
import Foundation
import VikeyShim

/// Spec 12.2–12.3 on the Vikey path: the "keep as typed" filter the shim asks before Vikey fixes a word, learning
/// from the user's ⌫⌫ undos, and the two switches ("Sửa lỗi bấm đúp phím dấu", "Nhớ từ bạn giữ nguyên"), both on by default.
///
/// Threading: `install()`, the C filter and `afterPress` run on the key-handling (event-tap, main) thread, like the
/// engine; the switches and `rules` live on main too. The key path does no I/O: the filter is one `shouldKeep`
/// lookup, and `afterPress` hands records to a serial background queue (`UndoRuleBook.record` may be O(n) under its
/// lock). Learned rules apply everywhere; only learning skips Secure Input, password fields and excluded apps.
/// The key thread reads only the cheap context (`LearnContextReader.probe`: app, Secure Input, time) and decides
/// Secure Input and excluded apps from it; the secure-field check (AX IPC) runs on that background queue, which drops
/// the observation when the field is secure or the check fails (audit item 4). Typed text handed to the queue stays
/// in memory.
///
/// Spec 17.1 for the router: the "Tự viết hoa tên riêng" switch, the learned names, and capitalisation undos, which
/// go into the same rule book as "cap:" rules. Learning a name runs on the key-handling thread (ruling R4: its
/// dictionary check replays the engine); the count itself is recorded on the background queue, after the
/// secure-field check. Names are not learned in terminals and code editors (`CodeApps`: identifiers, commands).
/// Nothing typed is logged.
public final class UndoLearning: ObservableObject {
    public static let doubleKeyFixKey = "LeanKeys.doubleKeyFix", learningKey = "LeanKeys.undoLearning"
    /// Spec 17.3: "Tự viết hoa tên riêng".
    public static let autoCapitalizeKey = "LeanKeys.autoCapitalize"
    /// Spec 17.3: "Bỏ phím \ ] ' lỡ bấm cùng Enter".
    public static let strayEnterKey = "LeanKeys.strayEnter"

    /// The app's instance: rules in `undo-rules.bin`, learned names in `learned-names.bin`, switches in
    /// `UserDefaults.standard`.
    public static let shared = UndoLearning(
        book: UndoRuleBook(store: KeychainEncryptedFileStore(url: storeURL, keychainService: keychainService)),
        defaults: .standard,
        probe: LearnContextReader.probe,
        secureField: LearnContextReader.isSecureField,
        names: .shared)

    static let keychainService = "io.github.anlvdt.leankeys.undo"
    static var storeURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/LeanKeys/undo-rules.bin")
    }

    /// The rules worth showing (`UndoRuleBook.rules`), most recently used first.
    @Published public private(set) var rules: [UndoRule]

    /// Spec 12.1: ⌫ right after a doubled key gives the Vietnamese word back.
    @Published public var doubleKeyFix: Bool {
        didSet {
            defaults.set(doubleKeyFix, forKey: Self.doubleKeyFixKey)
            VikeyEngine.setDoubleKeyFix(doubleKeyFix)
        }
    }

    /// Spec 12.2. Off: the filter keeps nothing and no undo is recorded; the rules stay.
    @Published public var learning: Bool {
        didSet { defaults.set(learning, forKey: Self.learningKey) }
    }

    /// Spec 17.1. Off: nothing is capitalised and no name is learned; learned names and rules stay.
    @Published public var autoCapitalize: Bool {
        didSet { defaults.set(autoCapitalize, forKey: Self.autoCapitalizeKey) }
    }

    /// Spec 17.2, read by the router on the key-handling thread. Off: no key next to Enter is deleted or dropped.
    @Published public var strayEnter: Bool {
        didSet { defaults.set(strayEnter, forKey: Self.strayEnterKey) }
    }

    /// Names learned from the user's own capitals (spec 17.1.3).
    public let learnedNames: LearnedNames

    /// `learnedNames.names` for the settings card (spec 17.3), most recently used first; updated on main.
    @Published public private(set) var names: [LearnedName]

    private let book: UndoRuleBook
    private let defaults: UserDefaults
    private let probe: () -> LearnContextProbe
    private let secureField: (LearnContextProbe) -> Bool
    private let recordQueue = DispatchQueue(label: "io.github.anlvdt.leankeys.undo-learning.record")
    private let onRecordQueue: (@escaping () -> Void) -> Void
    /// Bumped by "Xoá tất cả": a record queued under an older generation drops itself (ruling R17).
    private var generation = 0
    /// Guards `generation`, and is held while work is queued with it (re-review Minor 1). Recursive: an inline
    /// record queue (tests) runs the work, which reads the generation, while it is held.
    private let generationLock = NSRecursiveLock()

    /// The instance the C filter asks. Set by `install()`; read on the key-handling thread, which also installs.
    fileprivate static var installed: UndoLearning?

    /// - Parameters:
    ///   - probe: where the user is typing, without IPC; called on the key-handling thread, only when an undo
    ///     arrives or a word the user capitalised could be learned.
    ///   - secureField: whether the focused field of the probed app is a password field, or cannot be told; called
    ///     on the record queue only, once per observation that passed the key-thread checks.
    ///   - names: memory only unless given (only `shared` opens `learned-names.bin`).
    ///   - onRecordQueue: runs work on the serial record queue; nil for this instance's own background queue.
    init(book: UndoRuleBook, defaults: UserDefaults, probe: @escaping () -> LearnContextProbe,
         secureField: @escaping (LearnContextProbe) -> Bool, names: LearnedNames = UndoLearning.memoryNames(),
         onRecordQueue: ((@escaping () -> Void) -> Void)? = nil) {
        self.book = book
        self.defaults = defaults
        self.probe = probe
        self.secureField = secureField
        self.onRecordQueue = onRecordQueue ?? { [recordQueue] in recordQueue.async(execute: $0) }
        learnedNames = names
        self.names = names.names
        rules = book.rules
        doubleKeyFix = defaults.object(forKey: Self.doubleKeyFixKey) as? Bool ?? true
        learning = defaults.object(forKey: Self.learningKey) as? Bool ?? true
        autoCapitalize = defaults.object(forKey: Self.autoCapitalizeKey) as? Bool ?? true
        strayEnter = defaults.object(forKey: Self.strayEnterKey) as? Bool ?? true
        book.onChange = { [weak self] in
            guard let self else { return }
            rules = self.book.rules
        }
        names.onChange = { [weak self] in
            guard let self else { return }
            self.names = self.learnedNames.names
        }
    }

    /// Registers the C filter (answered by this instance) and applies the double-key switch to the shim. Idempotent.
    public func install() {
        Self.installed = self
        lk_vikey_set_fix_filter(undoFixFilter)
        lk_vikey_set_convert_filter(undoConvertFilter)
        VikeyEngine.setDoubleKeyFix(doubleKeyFix)
    }

    /// Unregisters the filter if this instance holds it. For tests.
    func uninstall() {
        guard Self.installed === self else { return }
        Self.installed = nil
        lk_vikey_set_fix_filter(nil)
        lk_vikey_set_convert_filter(nil)
    }

    /// What the C filter answers: keep `before` (typed after `previous`) as typed.
    /// A pinned word ("Từ của tôi") is kept as typed too; with the learning switch off pins stop applying (spec 8.8).
    func filterDecision(before: String, previous: String) -> Bool {
        guard learning else { return false }
        return book.shouldKeep(before: before, previous: previous)
            || (before.allSatisfy(\.isASCII) && book.isPinned(before.lowercased()))
    }

    /// What the C convert filter answers: convert the raw keys `keys`, shown as `shown` (typed after `previous`), at
    /// the break key. A word shown as its raw keys can only go to Telex, so only a rule of the direction fits; a
    /// pinned word converts to Telex only. Learning off: nothing applies, pins included.
    func convertDecision(keys: String, shown: String, previous: String) -> Bool {
        guard learning else { return false }
        let toRaw = shown.lowercased() != keys
        return book.shouldConvert(keys: keys, previous: previous, toRaw: toRaw) || (toRaw && book.isPinned(keys))
    }

    /// After each key Vikey handled: takes the shim's undo event, if any, and records it unless learning is off or
    /// the user is typing somewhere excluded. The event is always taken, so a skipped one never lingers.
    func afterPress(engine: VikeyEngine) {
        guard let undo = engine.takeUndo(), learning, let probe = includedProbe() else { return }
        switch undo.kind {
        case 0:
            record(probe) { [book] in book.record(before: undo.before, previous: undo.previous, reverse: undo.reverse) }
        case 1, 2:
            // Kind 1: a ⌃⌫ convert of `before` into `after`. Kind 2: the undo of a rule's convert of `before` into
            // `after` (the shim queues the rule's own fix), so both say the direction the same way.
            guard !undo.keys.isEmpty else { return }
            let toRaw = undo.after.lowercased() == undo.keys
            record(probe) { [book] in
                book.recordConvert(keys: undo.keys, previous: undo.previous, toRaw: toRaw, reverse: undo.kind == 2)
            }
        default:
            return
        }
    }

    // MARK: Capitalisation (spec 17.1)

    /// Whether to leave the capitalisation rule text `text` ("cap:" + lowercased phrase) alone after `previous`:
    /// the 4C rule book, under the 4C switch, as `filterDecision`.
    func keepsLowercase(_ text: String, previous: String) -> Bool {
        learning && book.shouldKeep(before: text, previous: previous)
    }

    /// The user undid a capitalisation with ⌫: one undo of `text` after `previous` in the rule book (unless
    /// learning is off or the user is typing somewhere excluded), and one undo of `learnedName` when a learned
    /// name made it. Key-handling thread; the record runs on the background queue, as in `afterPress`.
    func capitalizationUndone(_ text: String, previous: String, learnedName: String?) {
        // On the queue, after any sighting of the name already there (review M1). It only removes data: no
        // secure-field check.
        if let learnedName {
            onRecordQueueUnlessCleared { [learnedNames] in learnedNames.undone(word: learnedName) }
        }
        guard learning, let probe = includedProbe() else { return }
        // A secret-shaped word before the phrase is never kept as its context (ruling R14).
        let previous = Exclusions.looksLikeSecret(previous) ? "" : previous
        record(probe) { [book] in book.record(before: text, previous: previous, reverse: false) }
    }

    /// A word the user typed with a capital mid-phrase, as the router saw it: learned unless capitalisation is off,
    /// the user is typing somewhere excluded, or in a terminal or code editor. Key-handling thread: the dictionary
    /// check stays here (ruling R4: it replays the engine), and the context is probed only for a word `LearnedNames`
    /// could count (ruling R14); the count is recorded on the queue.
    func userCapitalized(_ word: String, previous: String?) {
        guard autoCapitalize, LearnedNames.looksLikeTypedName(word.precomposedStringWithCanonicalMapping),
              let probe = includedProbe(), !CodeApps.contains(probe.bundleID),
              let sighting = learnedNames.sighting(word: word, previous: previous) else { return }
        record(probe) { [learnedNames] in learnedNames.record(sighting) }
    }

    /// The context without IPC, or nil under Secure Input or in an excluded app. Key-handling thread.
    private func includedProbe() -> LearnContextProbe? {
        let probe = probe()
        return isExcluded(probe) ? nil : probe
    }

    /// Runs `work` on the record queue unless the probed app's focused field is a password field or cannot be told,
    /// or "Xoá tất cả" came after it was queued.
    private func record(_ probe: LearnContextProbe, _ work: @escaping () -> Void) {
        let secureField = secureField
        onRecordQueueUnlessCleared {
            guard !secureField(probe) else { return }
            work()
        }
    }

    /// Runs `work` on the record queue unless "Xoá tất cả" came after it was queued. The generation is read and the
    /// work queued in one critical section, as `removeAll` bumps it and queues its clear: work that holds the new
    /// generation is always queued behind that clear, so the clear never wipes it (re-review Minor 1).
    private func onRecordQueueUnlessCleared(_ work: @escaping () -> Void) {
        generationLock.withLock {
            let generation = generation
            onRecordQueue { [weak self] in
                guard self?.currentGeneration() == generation else { return }
                work()
            }
        }
    }

    private func currentGeneration() -> Int { generationLock.withLock { generation } }

    /// Learned names kept in memory only, with the real dictionary check and the bundled titles.
    static func memoryNames() -> LearnedNames {
        LearnedNames(store: nil, hmacKey: nil, titles: Set(ProperNounData.bundled.titles),
                     isDictionaryWord: LearnedNames.isDictionaryWord)
    }

    public func remove(_ rule: UndoRule) { book.remove(rule) }

    public func remove(_ name: LearnedName) { learnedNames.remove(name) }

    /// "Xoá tất cả" (spec 17.3): every rule, capitalisation rules included, and every learned name. Cleared now,
    /// so the list empties at once, and again on the record queue behind any work already there; that work drops
    /// itself as well (ruling R17), so nothing queued before brings a rule or a hidden count back. The bump and the
    /// queued clear happen together, after the clear here, so work queued after the bump is never cleared
    /// (re-review Minor 1).
    public func removeAll() {
        book.removeAll()
        learnedNames.removeAll()
        generationLock.withLock {
            generation += 1
            onRecordQueue { [book, learnedNames] in
                book.removeAll()
                learnedNames.removeAll()
            }
        }
    }

    /// Waits for queued records and the saves they started, for tests.
    func flush() {
        recordQueue.sync {}
        book.flush()
        learnedNames.flush()
    }

    /// Secure Input or an excluded app, from the key-thread probe; the password-field check comes on the queue.
    private func isExcluded(_ context: LearnContextProbe) -> Bool {
        if context.secureInput { return true }
        guard let bundleID = context.bundleID else { return false }
        return Exclusions.isExcludedByDefault(bundleID)
            || (defaults.stringArray(forKey: ShortcutSuggestionsModel.excludedAppsKey) ?? []).contains(bundleID)
    }
}

public extension LearnedNames {
    /// The app's learned names, in `learned-names.bin` with their own Keychain item (spec 17.1.3).
    static let shared: LearnedNames = {
        let store = KeychainEncryptedFileStore(url: namesURL, keychainService: "io.github.anlvdt.leankeys.names")
        return LearnedNames(store: store, hmacKey: try? store.hmacKey(), titles: Set(ProperNounData.bundled.titles),
                            isDictionaryWord: LearnedNames.isDictionaryWord)
    }()

    private static var namesURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/LeanKeys/learned-names.bin")
    }
}

/// The shim's fix filter: 1 keeps the word as typed. Only builds the two words and asks the installed instance.
private let undoFixFilter: lk_fix_filter = { fix in
    guard let fix, let learning = UndoLearning.installed else { return 0 }
    let before = VikeyEngine.string(fix.pointee.before, fix.pointee.beforeLength)
    let previous = VikeyEngine.string(fix.pointee.previous, fix.pointee.previousLength)
    return learning.filterDecision(before: before, previous: previous) ? 1 : 0
}

/// The shim's convert filter, asked at a break key when Vikey made no fix: 1 converts the word. `after` is empty
/// when the conversion is the Telex form, which only renders once this says 1.
private let undoConvertFilter: lk_convert_filter = { fix in
    guard let fix, let learning = UndoLearning.installed else { return 0 }
    let keys = VikeyEngine.string(fix.pointee.keys, fix.pointee.keysLength)
    let shown = VikeyEngine.string(fix.pointee.before, fix.pointee.beforeLength)
    let previous = VikeyEngine.string(fix.pointee.previous, fix.pointee.previousLength)
    return learning.convertDecision(keys: keys, shown: shown, previous: previous) ? 1 : 0
}
