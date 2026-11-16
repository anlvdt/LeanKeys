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
/// Nothing typed is logged.
public final class UndoLearning: ObservableObject {
    public static let doubleKeyFixKey = "LeanKeys.doubleKeyFix", learningKey = "LeanKeys.undoLearning"

    /// The app's instance: rules in `undo-rules.bin`, switches in `UserDefaults.standard`.
    public static let shared = UndoLearning(
        book: UndoRuleBook(store: KeychainEncryptedFileStore(url: storeURL, keychainService: keychainService)),
        defaults: .standard,
        context: LearnContextReader.current)

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

    private let book: UndoRuleBook
    private let defaults: UserDefaults
    private let context: () -> LearnContext
    private let recordQueue = DispatchQueue(label: "io.github.anlvdt.leankeys.undo-learning.record")

    /// The instance the C filter asks. Set by `install()`; read on the key-handling thread, which also installs.
    fileprivate static var installed: UndoLearning?

    /// - Parameter context: where the user is typing; called on the key-handling thread, only when an undo arrives.
    init(book: UndoRuleBook, defaults: UserDefaults, context: @escaping () -> LearnContext) {
        self.book = book
        self.defaults = defaults
        self.context = context
        rules = book.rules
        doubleKeyFix = defaults.object(forKey: Self.doubleKeyFixKey) as? Bool ?? true
        learning = defaults.object(forKey: Self.learningKey) as? Bool ?? true
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

/// The shim's fix filter: 1 keeps the word as typed. Only builds the two words and asks the installed instance.
private let undoFixFilter: lk_fix_filter = { fix in
    guard let fix, let learning = UndoLearning.installed else { return 0 }
    let before = VikeyEngine.string(fix.pointee.before, fix.pointee.beforeLength)
    let previous = VikeyEngine.string(fix.pointee.previous, fix.pointee.previousLength)
    return learning.filterDecision(before: before, previous: previous) ? 1 : 0
}
