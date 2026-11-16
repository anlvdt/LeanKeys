import AppKit
import XCTest
import VikeyShim
@testable import LeanKeysKit

/// Spec 12.2–12.3, Swift side: undo events drained after each key, exclusions, the two switches, and the C filter
/// backed by an `UndoRuleBook`, with the real engine.

/// Mac virtual key codes, from vendor/vikey/Engine/platforms/mac.h. "⌫" is Backspace.
private let macKey: [Character: UInt16] = [
    "a": 0, "b": 11, "c": 8, "d": 2, "e": 14, "f": 3, "g": 5, "h": 4, "i": 34, "j": 38, "k": 40, "l": 37, "m": 46,
    "n": 45, "o": 31, "p": 35, "q": 12, "r": 15, "s": 1, "t": 17, "u": 32, "v": 9, "w": 13, "x": 7, "y": 16, "z": 6,
    " ": 49, ",": 43, ".": 47, "⌫": 51,
]

/// A text field driven by the engine as the router drives it: each key, then `afterPress` when `learning` is set.
private final class Field {
    let engine: VikeyEngine
    let learning: UndoLearning?
    var text: [Character] = []

    init(_ engine: VikeyEngine, _ learning: UndoLearning? = nil) {
        self.engine = engine
        self.learning = learning
    }

    @discardableResult
    func type(_ keys: String) -> String {
        for ch in keys {
            guard let code = macKey[Character(ch.lowercased())] else { XCTFail("no mac key for \(ch)"); continue }
            let own: Character? = ch == "⌫" ? nil : ch
            if let edit = engine.process(keyCode: code, caps: ch.isUppercase, shift: ch.isUppercase) {
                text.removeLast(min(edit.deleteCount, text.count))
                text.append(contentsOf: edit.text)
                if edit.keyPassesThrough, let own { text.append(own) }
            } else if own == nil {
                if !text.isEmpty { text.removeLast() }
            } else if let own {
                text.append(own)
            }
            learning?.afterPress(engine: engine)
        }
        return String(text)
    }
}

final class UndoLearningTests: XCTestCase {
    private var engine: VikeyEngine!
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var context = LearnContext(bundleID: "com.apple.TextEdit", secureInput: false, secureField: false,
                                       now: Date())
    private var learning: UndoLearning?

    override func setUp() {
        super.setUp()
        engine = VikeyEngine()
        XCTAssertNotNil(engine, "lk_vikey_init failed")
        suiteName = "UndoLearningTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        cleanEngine()
    }

    override func tearDown() {
        learning?.uninstall()
        learning = nil
        cleanEngine()
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func cleanEngine() {
        lk_vikey_set_fix_filter(nil)
        while engine.takeUndo() != nil {}
        VikeyEngine.setDoubleKeyFix(true)
        engine.setVietnamese(true)
        engine.resetContext()
    }

    private func makeLearning(_ book: UndoRuleBook = UndoRuleBook(store: nil)) -> UndoLearning {
        let made = UndoLearning(book: book, defaults: defaults, context: { [unowned self] in self.context })
        learning = made
        return made
    }

    /// A fresh line in English: Vikey fixes "cos " to "có " there (in Vietnamese, Telex types "có" key by key).
    private func englishLine(_ learning: UndoLearning?) -> Field {
        engine.setVietnamese(false)
        engine.resetContext()
        return Field(engine, learning)
    }

    /// Types "toi thich cos " and undoes Vikey's fix with ⌫⌫, draining after every key; returns the screen.
    @discardableResult
    private func undoCos(_ learning: UndoLearning) -> String {
        let field = englishLine(learning)
        XCTAssertEqual(field.type("toi thich cos "), "toi thich có ", "Vikey's own fix (precondition)")
        return field.type("⌫⌫")
    }

    /// Waits until queued records are in the book and its `onChange` has reached `rules` on main.
    private func settle(_ learning: UndoLearning) {
        learning.flush()
        let published = expectation(description: "main queue")
        DispatchQueue.main.async { published.fulfill() }
        wait(for: [published], timeout: 2)
    }

    func testRecordsUndoOutsideExclusions() {
        let book = UndoRuleBook(store: nil)
        let learning = makeLearning(book)
        XCTAssertEqual(undoCos(learning), "toi thich cos")
        XCTAssertNil(engine.takeUndo(), "afterPress drained the undo")
        settle(learning)
        XCTAssertEqual(learning.rules.map { [$0.previous, $0.text] }, [["thich", "cos"]])
        XCTAssertTrue(book.shouldKeep(before: "cos", previous: "thich"))
    }

    func testSkipsSecureFieldAndExcludedApp() {
        defaults.set(["com.example.private"], forKey: ShortcutSuggestionsModel.excludedAppsKey)
        let contexts = [
            LearnContext(bundleID: "com.apple.TextEdit", secureInput: false, secureField: true, now: Date()),
            LearnContext(bundleID: "com.apple.TextEdit", secureInput: true, secureField: true, now: Date()),
            LearnContext(bundleID: "com.1password.1password", secureInput: false, secureField: false, now: Date()),
            LearnContext(bundleID: "com.example.private", secureInput: false, secureField: false, now: Date()),
        ]
        let book = UndoRuleBook(store: nil)
        let learning = makeLearning(book)
        for context in contexts {
            self.context = context
            XCTAssertEqual(undoCos(learning), "toi thich cos")
            XCTAssertNil(engine.takeUndo(), "the undo is drained even when it is not learned")
        }
        settle(learning)
        XCTAssertTrue(learning.rules.isEmpty)
        XCTAssertTrue(book.rules.isEmpty)
        XCTAssertFalse(book.shouldKeep(before: "cos", previous: "thich"))
    }

    func testLearningOffKeepsNothingRecordsNothing() {
        let book = UndoRuleBook(store: nil)
        book.record(before: "cos", previous: "thich", reverse: false)
        let learning = makeLearning(book)
        learning.install()
        XCTAssertTrue(learning.filterDecision(before: "cos", previous: "thich"))

        learning.learning = false
        XCTAssertEqual(defaults.object(forKey: UndoLearning.learningKey) as? Bool, false)
        XCTAssertFalse(learning.filterDecision(before: "cos", previous: "thich"))
        // Through the C filter: Vikey's fix stands, and its undo is not recorded.
        XCTAssertEqual(undoCos(learning), "toi thich cos")
        let other = englishLine(learning)
        XCTAssertEqual(other.type("ban cos "), "ban có ")
        other.type("⌫⌫")
        settle(learning)
        XCTAssertEqual(book.rules.map { [$0.previous, $0.text, String($0.count)] }, [["thich", "cos", "1"]])

        learning.learning = true
        XCTAssertTrue(learning.filterDecision(before: "cos", previous: "thich"))
    }

    func testDoubleKeyFixToggleReachesShim() {
        let learning = makeLearning()
        learning.doubleKeyFix = false
        XCTAssertEqual(defaults.object(forKey: UndoLearning.doubleKeyFixKey) as? Bool, false)
        engine.setVietnamese(true)
        engine.resetContext()
        XCTAssertEqual(Field(engine).type("hocjj⌫"), "hoc")

        learning.doubleKeyFix = true
        XCTAssertEqual(defaults.object(forKey: UndoLearning.doubleKeyFixKey) as? Bool, true)
        engine.setVietnamese(true)
        engine.resetContext()
        XCTAssertEqual(Field(engine).type("hocjj⌫"), "học")
    }

    func testEndToEndContextRule() {
        let learning = makeLearning(UndoRuleBook(store: nil))
        learning.install()
        XCTAssertEqual(undoCos(learning), "toi thich cos")
        settle(learning)
        // One undo after "thich": the next "cos " after "thich " stays as typed, in one edit, still English.
        let again = englishLine(learning)
        XCTAssertEqual(again.type("toi thich cos "), "toi thich cos ")
        XCTAssertFalse(engine.isVietnamese)
        // Other contexts still get Vikey's fix: a context rule needs only one undo, a contextless one two.
        XCTAssertEqual(englishLine(learning).type("ban cos "), "ban có ")
    }

    /// The router installs the learner it was given when it builds the real engine, and drains undos after each key.
    func testRouterInstallsLearnerAndDrainsUndo() {
        let book = UndoRuleBook(store: nil)
        let learning = makeLearning(book)
        let engine = self.engine!
        let router = EngineRouter(defaults: defaults, makeVikey: { engine }, undoLearning: { learning })
        router.setEnabled(false)
        XCTAssertEqual(type("toi thich cos ", through: router), "toi thich có ", "Vikey's own fix (precondition)")
        XCTAssertEqual(type("toi thich cos ⌫⌫", through: router), "toi thich cos")
        XCTAssertNil(engine.takeUndo(), "the router drained the undo")
        settle(learning)
        XCTAssertEqual(book.rules.map { [$0.previous, $0.text] }, [["thich", "cos"]])
        // The installed filter now keeps the word.
        XCTAssertEqual(type("toi thich cos ", through: router), "toi thich cos ")
    }

    /// Types `keys` on a fresh English line through `router.intercept`, applying each result the way the macOS key
    /// handler does; returns the screen.
    private func type(_ keys: String, through router: EngineRouter) -> String {
        router.setEnabled(false)
        router.clear()
        var text: [Character] = []
        for ch in keys {
            guard let code = macKey[ch] else { XCTFail("no mac key for \(ch)"); continue }
            let own: Character? = ch == "⌫" ? nil : ch
            switch router.intercept(keyCode: code, caps: false, ctrl: false, shift: false) {
            case .passToGoNhanh:
                XCTFail("Vikey is the active engine")
            case .handled(let result):
                if let (deleteCount, inserted, consumed) = result {
                    text.removeLast(min(deleteCount, text.count))
                    text.append(contentsOf: inserted)
                    if consumed { continue }
                }
                if let own { text.append(own) } else if !text.isEmpty { text.removeLast() }
            }
        }
        return String(text)
    }

    // MARK: Settings card (spec 17.3)

    /// Fake learned names, memory only: every word counts as a name anywhere.
    private func fakeNames() -> LearnedNames {
        LearnedNames(store: nil, hmacKey: nil, titles: [], isDictionaryWord: { _ in false })
    }

    func testNamesArePublishedAndRemovable() {
        let names = fakeNames()
        let learning = UndoLearning(book: UndoRuleBook(store: nil), defaults: defaults,
                                    context: { [unowned self] in self.context }, names: names)
        self.learning = learning
        XCTAssertEqual(learning.names, [])
        names.observe(word: "Lan", previous: "chị")
        names.observe(word: "Lan", previous: "chị")
        settle(learning)
        XCTAssertEqual(learning.names.map(\.form), ["Lan"])
        learning.remove(learning.names[0])
        settle(learning)
        XCTAssertEqual(learning.names, [])
        XCTAssertNil(names.name(after: nil, word: "lan"))
    }

    func testRemoveAllEmptiesRulesAndNames() {
        let names = fakeNames()
        let book = UndoRuleBook(store: nil)
        let learning = UndoLearning(book: book, defaults: defaults, context: { [unowned self] in self.context },
                                    names: names)
        self.learning = learning
        book.record(before: "cap:hà nội", previous: "ở", reverse: false)
        names.observe(word: "Lan", previous: nil)
        names.observe(word: "Lan", previous: nil)
        settle(learning)
        XCTAssertEqual(learning.rules.count, 1)
        XCTAssertEqual(learning.names.count, 1)
        learning.removeAll()
        settle(learning)
        XCTAssertEqual(learning.rules, [])
        XCTAssertEqual(learning.names, [])
        XCTAssertEqual(book.rules, [])
        XCTAssertEqual(names.names, [])
    }

    /// Ruling R14 (M2): a capitalisation undone after a secret-shaped word records no context, so the word is never
    /// kept; the contextless count still goes up.
    func testCapitalizationUndoSkipsSecretContext() {
        let book = UndoRuleBook(store: nil)
        let learning = makeLearning(book)
        learning.capitalizationUndone("cap:hà nội", previous: "matkhau2024", learnedName: nil)
        learning.capitalizationUndone("cap:hà nội", previous: "matkhau2024", learnedName: nil)
        settle(learning)
        XCTAssertEqual(book.rules.map(\.previous), [""], "contextless only")
        // Control: an ordinary previous word is kept as the context.
        learning.capitalizationUndone("cap:huế", previous: "ở", learnedName: nil)
        settle(learning)
        XCTAssertTrue(book.rules.contains { $0.text == "cap:huế" && $0.previous == "ở" })
    }

    /// Ruling R14 (M5): words that can never be learned are dropped before the context (AX) is read.
    func testUserCapitalizedReadsContextOnlyForNameShapedWords() {
        var reads = 0
        let learning = UndoLearning(book: UndoRuleBook(store: nil), defaults: defaults,
                                    context: { [unowned self] in reads += 1; return self.context }, names: fakeNames())
        self.learning = learning
        for word in ["FOMO", "A", "Matkhau2024", "tiki", "Abc@xyz"] {
            learning.userCapitalized(word, previous: "mua")
        }
        XCTAssertEqual(reads, 0)
        learning.userCapitalized("Tiki", previous: "mua")
        XCTAssertEqual(reads, 1)
    }

    // MARK: The AX secure-field read stays off the key thread (audit item 4)

    /// A record queue that holds its work until `drain()`, and a secure-field (AX) check that counts its reads.
    private final class Deferred {
        var work: [() -> Void] = []
        var axReads = 0
        var secure = false
        func drain() {
            let pending = work
            work = []
            pending.forEach { $0() }
        }
    }

    private func deferredLearning(_ deferred: Deferred, book: UndoRuleBook = UndoRuleBook(store: nil),
                                  names: LearnedNames? = nil) -> UndoLearning {
        let made = UndoLearning(book: book, defaults: defaults, probe: { [unowned self] in context.probe },
                                secureField: { _ in
                                    deferred.axReads += 1
                                    return deferred.secure
                                },
                                names: names ?? fakeNames(), onRecordQueue: { deferred.work.append($0) })
        learning = made
        return made
    }

    func testKeyThreadNeverReadsSecureField() {
        let deferred = Deferred()
        let book = UndoRuleBook(store: nil)
        let names = fakeNames()
        let learning = deferredLearning(deferred, book: book, names: names)
        XCTAssertEqual(undoCos(learning), "toi thich cos")
        learning.capitalizationUndone("cap:hà nội", previous: "ở", learnedName: nil)
        learning.userCapitalized("Tiki", previous: "mua")
        learning.userCapitalized("Tiki", previous: "mua")
        XCTAssertEqual(deferred.axReads, 0, "the key path reads no AX")
        XCTAssertEqual(deferred.work.count, 4, "every observation is queued")
        XCTAssertTrue(book.rules.isEmpty)
        XCTAssertTrue(names.names.isEmpty)

        deferred.drain()
        XCTAssertEqual(deferred.axReads, 4, "the queue checks the field once per observation")
        XCTAssertEqual(Set(book.rules.map(\.text)), ["cos", "cap:hà nội"])
        XCTAssertEqual(names.names.map(\.form), ["Tiki"])
    }

    func testSecureFieldOnTheQueueDropsTheRecord() {
        let deferred = Deferred()
        deferred.secure = true
        let book = UndoRuleBook(store: nil)
        let names = fakeNames()
        let learning = deferredLearning(deferred, book: book, names: names)
        undoCos(learning)
        learning.capitalizationUndone("cap:hà nội", previous: "ở", learnedName: nil)
        learning.userCapitalized("Tiki", previous: "mua")
        learning.userCapitalized("Tiki", previous: "mua")
        deferred.drain()
        XCTAssertEqual(deferred.axReads, 4)
        XCTAssertTrue(book.rules.isEmpty, "a secure field drops the undo records")
        XCTAssertTrue(names.names.isEmpty, "and the name sightings")
    }

    /// Secure Input and excluded apps are decided on the key thread: nothing reaches the queue.
    func testExclusionsDecidedBeforeQueueing() {
        defaults.set(["com.example.private"], forKey: ShortcutSuggestionsModel.excludedAppsKey)
        let deferred = Deferred()
        let learning = deferredLearning(deferred)
        for context in [
            LearnContext(bundleID: "com.apple.TextEdit", secureInput: true, secureField: false, now: Date()),
            LearnContext(bundleID: "com.1password.1password", secureInput: false, secureField: false, now: Date()),
            LearnContext(bundleID: "com.example.private", secureInput: false, secureField: false, now: Date()),
        ] {
            self.context = context
            undoCos(learning)
            learning.capitalizationUndone("cap:hà nội", previous: "ở", learnedName: nil)
            learning.userCapitalized("Tiki", previous: "mua")
        }
        XCTAssertTrue(deferred.work.isEmpty)
        XCTAssertEqual(deferred.axReads, 0)
    }

    /// A store that keeps what it is handed, for checking what reached disk: the current data and every save ever
    /// made (review re-review Minor 3). Saves arrive on a private queue.
    private final class KeptStore: LearnStore {
        private let lock = NSLock()
        private var data: Data?
        private var saves: [Data] = []
        var saved: Data? { lock.withLock { data } }
        var everySave: [Data] { lock.withLock { saves } }
        func load() throws -> Data? { lock.withLock { data } }
        func save(_ data: Data) throws { lock.withLock { self.data = data; saves.append(data) } }
        func erase() throws { lock.withLock { data = nil } }

        /// Whether any save ever held `text`, composed or decomposed.
        func everSaved(_ text: String) -> Bool {
            everySave.contains { save in
                [text.precomposedStringWithCanonicalMapping, text.decomposedStringWithCanonicalMapping]
                    .contains { save.range(of: Data($0.utf8)) != nil }
            }
        }
    }

    /// Ruling R17 (review I1): records queued before "Xoá tất cả" never bring a rule or a hidden count back, in
    /// memory or on disk.
    func testRemoveAllDropsQueuedRecords() {
        let deferred = Deferred()
        let bookStore = KeptStore(), namesStore = KeptStore()
        let book = UndoRuleBook(store: bookStore)
        let names = LearnedNames(store: namesStore, hmacKey: Data(repeating: 7, count: 32), titles: [],
                                 isDictionaryWord: { _ in false })
        let learning = deferredLearning(deferred, book: book, names: names)
        undoCos(learning)
        learning.capitalizationUndone("cap:hà nội", previous: "ở", learnedName: nil)
        learning.userCapitalized("Tiki", previous: "mua")
        learning.userCapitalized("Tiki", previous: "mua")
        learning.removeAll()
        // The queued records run and their saves finish before the queued clear (review re-review Minor 3): a
        // record that ignored the generation would reach a save here, even though the clear wipes it later.
        let queuedClear = deferred.work.removeLast()
        deferred.drain()
        book.flush()
        names.flush()
        XCTAssertFalse(bookStore.everSaved("cos"), "no save ever held the queued rule")
        XCTAssertFalse(bookStore.everSaved("cap:hà nội"), "nor the queued capitalisation rule")
        XCTAssertFalse(namesStore.everSaved("Tiki"), "nor the queued name")
        queuedClear()
        book.flush()
        names.flush()
        XCTAssertTrue(book.rules.isEmpty)
        XCTAssertFalse(book.shouldKeep(before: "cos", previous: "thich"))
        XCTAssertTrue(names.names.isEmpty)
        names.observe(word: "Tiki", previous: "mua")
        XCTAssertTrue(names.names.isEmpty, "no hidden count survived: one more sighting is still below the threshold")
        names.flush()
        let reloadedBook = UndoRuleBook(store: bookStore)
        XCTAssertTrue(reloadedBook.rules.isEmpty, "nothing queued reached the saved rules")
        XCTAssertNil(bookStore.saved?.range(of: Data("cos".utf8)))
        // Control: work queued after the clear is recorded as usual.
        learning.userCapitalized("Lazada", previous: "mua")
        learning.userCapitalized("Lazada", previous: "mua")
        deferred.drain()
        XCTAssertEqual(names.names.map(\.form), ["Lazada"])
    }

    /// Review M1: the undo of a learned name goes through the same queue as its sightings, so a sighting queued
    /// before the second undo cannot re-create a hidden count for a name the user just rejected.
    func testNameUndoIsOrderedWithItsSightings() {
        let deferred = Deferred()
        let names = fakeNames()
        let learning = deferredLearning(deferred, names: names)
        names.observe(word: "Tiki", previous: nil)
        names.observe(word: "Tiki", previous: nil)
        XCTAssertEqual(names.names.map(\.form), ["Tiki"])
        learning.userCapitalized("Tiki", previous: "mua")
        learning.capitalizationUndone("cap:tiki", previous: "", learnedName: "tiki")
        learning.capitalizationUndone("cap:tiki", previous: "", learnedName: "tiki")
        deferred.drain()
        XCTAssertTrue(names.names.isEmpty, "removed by the second undo")
        names.observe(word: "Tiki", previous: nil)
        XCTAssertTrue(names.names.isEmpty, "the queued sighting left no hidden count behind")
    }

    /// Final re-review: identifiers typed in a terminal or code editor (`Config`, `Router`) are never learned as
    /// names; 4B and 4C keep their own exclusions.
    func testNoNameLearningInCodeApps() {
        let deferred = Deferred()
        let names = fakeNames()
        let learning = deferredLearning(deferred, names: names)
        for app in ["com.microsoft.VSCode", "com.jetbrains.intellij", "dev.warp.Warp-Preview"] {
            context = LearnContext(bundleID: app, secureInput: false, secureField: false, now: Date())
            learning.userCapitalized("Tiki", previous: "mua")
            learning.userCapitalized("Tiki", previous: "mua")
        }
        deferred.drain()
        XCTAssertTrue(names.names.isEmpty)
    }

    /// Task 4 minor 8: one terminal list. Every terminal the stray-key filter and capitalisation skip is also
    /// excluded from learning; editors are not (4B and 4C keep learning there).
    func testOneTerminalList() {
        XCTAssertTrue(Exclusions.defaultBundleIDs.isSuperset(of: CodeApps.terminals))
        XCTAssertTrue(CodeApps.bundleIDs.isSuperset(of: CodeApps.terminals))
        XCTAssertFalse(Exclusions.defaultBundleIDs.contains("com.microsoft.VSCode"))
    }

    /// The live reader's key-thread half reads no AX: it only fills in what NSWorkspace and the Secure Input flag say.
    func testLiveProbeIsCheap() {
        // The bundle ID and pid belong to the same app (review M7: no second frontmost read to race with).
        let probe = LearnContextReader.probe()
        if let pid = probe.pid {
            XCTAssertEqual(NSRunningApplication(processIdentifier: pid)?.bundleIdentifier, probe.bundleID)
        }
        // No pid: the queue half fails closed.
        XCTAssertTrue(LearnContextReader.isSecureField(LearnContextProbe(bundleID: nil, pid: nil, secureInput: false,
                                                                         now: Date())))
        XCTAssertTrue(LearnContextReader.isSecureField(LearnContextProbe(bundleID: nil, pid: 1, secureInput: true,
                                                                         now: Date())))
    }

    func testCapitalizationRuleDisplayText() {
        let date = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(UndoLearningSection.displayText(UndoRule(text: "cap:hà nội", previous: "", count: 1,
                                                                lastUsed: date)), "hà nội (viết hoa)")
        XCTAssertEqual(UndoLearningSection.displayText(UndoRule(text: "its", previous: "about", count: 1,
                                                                lastUsed: date)), "its")
    }

    func testCapitalizeAndStrayEnterDefaultOnAndPersist() {
        let learning = makeLearning()
        XCTAssertTrue(learning.autoCapitalize)
        XCTAssertTrue(learning.strayEnter)
        learning.autoCapitalize = false
        learning.strayEnter = false
        XCTAssertEqual(defaults.object(forKey: "LeanKeys.autoCapitalize") as? Bool, false)
        XCTAssertEqual(defaults.object(forKey: "LeanKeys.strayEnter") as? Bool, false)
        let reloaded = UndoLearning(book: UndoRuleBook(store: nil), defaults: defaults,
                                    context: { [unowned self] in self.context })
        XCTAssertFalse(reloaded.autoCapitalize)
        XCTAssertFalse(reloaded.strayEnter)
    }

    func testDefaultsOnWhenUnset() {
        let learning = makeLearning()
        XCTAssertTrue(learning.learning)
        XCTAssertTrue(learning.doubleKeyFix)
        learning.learning = false
        learning.doubleKeyFix = false
        let reloaded = UndoLearning(book: UndoRuleBook(store: nil), defaults: defaults,
                                    context: { [unowned self] in self.context })
        XCTAssertFalse(reloaded.learning)
        XCTAssertFalse(reloaded.doubleKeyFix)
    }
}
