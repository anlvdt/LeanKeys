import Combine
import Foundation
import VikeyShim

/// Spec 12.2–12.3 on the Vikey path: the "keep as typed" filter the shim asks before Vikey fixes a word, learning
/// from the user's ⌫⌫ undos, and the two switches ("⌫ sửa phím gõ đúp", "Tự học từ hoàn tác"), both on by default.
///
/// Threading: `install()`, the C filter and `afterPress` run on the key-handling (event-tap, main) thread, like the
/// engine; the switches and `rules` live on main too. The key path does no I/O: the filter is one `shouldKeep`
/// lookup, and `afterPress` hands records to a serial background queue (`UndoRuleBook.record` may be O(n) under its
/// lock). Learned rules apply everywhere; only learning skips Secure Input, password fields and excluded apps.
///
/// Spec 17.1 for the router: the "Tự viết hoa tên riêng" switch, the learned names, and capitalisation undos, which
/// go into the same rule book as "cap:" rules. Learning a name runs on the key-handling thread (ruling R4: its
/// dictionary check replays the engine) and reads the context only for a word the user capitalised.
/// Nothing typed is logged.
public final class UndoLearning: ObservableObject {
    public static let doubleKeyFixKey = "LeanKeys.doubleKeyFix", learningKey = "LeanKeys.undoLearning"
    /// Spec 17.3: "Tự viết hoa tên riêng".
    public static let autoCapitalizeKey = "LeanKeys.autoCapitalize"

    /// The app's instance: rules in `undo-rules.bin`, learned names in `learned-names.bin`, switches in
    /// `UserDefaults.standard`.
    public static let shared = UndoLearning(
        book: UndoRuleBook(store: KeychainEncryptedFileStore(url: storeURL, keychainService: keychainService)),
        defaults: .standard,
        context: LearnContextReader.current,
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

    /// Names learned from the user's own capitals (spec 17.1.3).
    public let learnedNames: LearnedNames

    private let book: UndoRuleBook
    private let defaults: UserDefaults
    private let context: () -> LearnContext
    private let recordQueue = DispatchQueue(label: "io.github.anlvdt.leankeys.undo-learning.record")

    /// The instance the C filter asks. Set by `install()`; read on the key-handling thread, which also installs.
    fileprivate static var installed: UndoLearning?

    /// - Parameters:
    ///   - context: where the user is typing; called on the key-handling thread, only when an undo arrives or a
    ///     word the user capitalised could be learned.
    ///   - names: memory only unless given (only `shared` opens `learned-names.bin`).
    init(book: UndoRuleBook, defaults: UserDefaults, context: @escaping () -> LearnContext,
         names: LearnedNames = UndoLearning.memoryNames()) {
        self.book = book
        self.defaults = defaults
        self.context = context
        learnedNames = names
        rules = book.rules
        doubleKeyFix = defaults.object(forKey: Self.doubleKeyFixKey) as? Bool ?? true
        learning = defaults.object(forKey: Self.learningKey) as? Bool ?? true
        autoCapitalize = defaults.object(forKey: Self.autoCapitalizeKey) as? Bool ?? true
        book.onChange = { [weak self] in
            guard let self else { return }
            rules = self.book.rules
        }
    }

    /// Registers the C filter (answered by this instance) and applies the double-key switch to the shim. Idempotent.
    public func install() {
        Self.installed = self
        lk_vikey_set_fix_filter(undoFixFilter)
        VikeyEngine.setDoubleKeyFix(doubleKeyFix)
    }

    /// Unregisters the filter if this instance holds it. For tests.
    func uninstall() {
        guard Self.installed === self else { return }
        Self.installed = nil
        lk_vikey_set_fix_filter(nil)
    }

    /// What the C filter answers: keep `before` (typed after `previous`) as typed.
    func filterDecision(before: String, previous: String) -> Bool {
        learning && book.shouldKeep(before: before, previous: previous)
    }

    /// After each key Vikey handled: takes the shim's undo event, if any, and records it unless learning is off or
    /// the user is typing somewhere excluded. The event is always taken, so a skipped one never lingers.
    func afterPress(engine: VikeyEngine) {
        guard let undo = engine.takeUndo(), learning else { return }
        // Reading the context costs up to 2 × 25 ms of AX IPC (LearnContextReader). It happens only when an undo
        // event exists, never per key: the same rule 4B uses once per phrase.
        guard !isExcluded(context()) else { return }
        recordQueue.async { [book] in
            book.record(before: undo.before, previous: undo.previous, reverse: undo.reverse)
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
        if let learnedName { learnedNames.undone(word: learnedName) }
        guard learning, !isExcluded(context()) else { return }
        recordQueue.async { [book] in
            book.record(before: text, previous: previous, reverse: false)
        }
    }

    /// A word the user typed with a capital mid-phrase, as the router saw it: learned unless capitalisation is off
    /// or the user is typing somewhere excluded. Key-handling thread (ruling R4: the dictionary check replays the
    /// engine); the context is read only here, once per such word.
    func userCapitalized(_ word: String, previous: String?) {
        guard autoCapitalize, !isExcluded(context()) else { return }
        learnedNames.observe(word: word, previous: previous)
    }

    /// Learned names kept in memory only, with the real dictionary check and the bundled titles.
    static func memoryNames() -> LearnedNames {
        LearnedNames(store: nil, hmacKey: nil, titles: Set(ProperNounData.bundled.titles),
                     isDictionaryWord: LearnedNames.isDictionaryWord)
    }

    public func remove(_ rule: UndoRule) { book.remove(rule) }

    public func removeAll() { book.removeAll() }

    /// Waits for queued records and the saves they started, for tests.
    func flush() {
        recordQueue.sync {}
        book.flush()
    }

    private func isExcluded(_ context: LearnContext) -> Bool {
        if context.secureInput || context.secureField { return true }
        guard let bundleID = context.bundleID else { return false }
        return Exclusions.defaultBundleIDs.contains(bundleID)
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
