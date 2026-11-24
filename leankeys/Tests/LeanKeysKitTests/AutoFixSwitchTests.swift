import XCTest
import VikeyShim
@testable import LeanKeysKit

private let keys: [Character: UInt16] = [
    "a": 0, "b": 11, "c": 8, "d": 2, "e": 14, "f": 3, "g": 5, "h": 4, "i": 34, "j": 38, "k": 40, "l": 37, "m": 46,
    "n": 45, "o": 31, "p": 35, "q": 12, "r": 15, "s": 1, "t": 17, "u": 32, "v": 9, "w": 13, "x": 7, "y": 16, "z": 6,
    " ": 49, ".": 47, "\n": 36, "\\": 42,
]

/// The master switch for automatic fixes (spec 2026-11-24), through a router over the real engine.
final class AutoFixSwitchTests: XCTestCase {
    private var engine: VikeyEngine!
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var learning: UndoLearning?
    private var returnQueries = 0
    private var clock: TimeInterval = 500.3

    override func setUp() {
        super.setUp()
        engine = VikeyEngine()
        XCTAssertNotNil(engine, "lk_vikey_init failed")
        suiteName = "AutoFixSwitchTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        returnQueries = 0
        cleanEngine()
    }

    override func tearDown() {
        learning?.uninstall()
        learning = nil
        cleanEngine()
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    /// The engine is process-wide: leave it with every automatic fix on.
    private func cleanEngine() {
        engine.setPureTelex(false)
        lk_vikey_set_fix_filter(nil)
        while engine.takeUndo() != nil {}
        VikeyEngine.setDoubleKeyFix(true)
        engine.setVietnamese(true)
        engine.setAutoSwitch(true)
        engine.resetContext()
    }

    private func makeRouter() -> EngineRouter {
        let made = UndoLearning(book: UndoRuleBook(store: nil), defaults: defaults,
                                context: { LearnContext(bundleID: "com.apple.TextEdit", secureInput: false,
                                                        secureField: false, now: Date()) },
                                names: UndoLearning.memoryNames(), onRecordQueue: { $0() })
        learning = made
        let engine = self.engine!
        return EngineRouter(defaults: defaults, makeVikey: { engine }, undoLearning: { made },
                            now: { [unowned self] in clock }, frontmostBundleID: { "com.apple.TextEdit" },
                            fieldAllowsFixAtReturn: { [unowned self] in returnQueries += 1; return true })
    }

    /// Types `text` on a fresh line, applying results as the macOS key handler does.
    private func type(_ router: EngineRouter, _ text: String, vietnamese: Bool = true) -> String {
        router.setEnabled(vietnamese)
        router.clear()
        var out: [Character] = []
        for ch in text {
            guard let code = keys[Character(ch.lowercased())] ?? keys[ch] else { XCTFail("no key for \(ch)"); continue }
            guard case .handled(let result) = router.intercept(keyCode: code, caps: false, ctrl: false, shift: false)
            else { XCTFail("Vikey is the active engine"); continue }
            if let (deleteCount, inserted, consumed) = result {
                out.removeLast(min(deleteCount, out.count))
                out += inserted
                if consumed { continue }
            }
            out.append(ch)
        }
        return String(out)
    }

    func testAutoFixDefaultsOn() {
        XCTAssertTrue(LeanSettings(defaults: defaults).autoFix)
        XCTAssertTrue(makeRouter().autoFix)
    }

    func testAutoFixPersistsAndAppliesAtLaunch() {
        let router = makeRouter()
        router.autoFix = false
        XCTAssertFalse(defaults.bool(forKey: "LeanKeys.autoFix"))
        XCTAssertNotNil(defaults.object(forKey: "LeanKeys.autoFix"))
        // A relaunch (a new router over the same store) starts pure: English typed with Vietnamese keys stays put.
        cleanEngine()
        let relaunched = makeRouter()
        XCTAssertFalse(relaunched.autoFix)
        XCTAssertEqual(type(relaunched, "treen ", vietnamese: false), "treen ", "no auto switch")
        relaunched.autoFix = true
        XCTAssertEqual(type(relaunched, "treen ", vietnamese: false), "trên ", "auto switch is back")
    }

    func testAutoFixOffSkipsCapitalizeStrayEnterAndReturnFix() {
        let router = makeRouter()
        // Control: with the switch on, a name is capitalised, the stray key is deleted and Return is asked about.
        XCTAssertEqual(type(router, "nguyeenx vawn an "), "Nguyễn Văn An ")
        XCTAssertEqual(type(router, "xong.\\\n"), "xong.\n", "stray backslash dropped before Enter")
        _ = type(router, "dduowcj\n")
        XCTAssertEqual(returnQueries, 1)

        router.autoFix = false
        returnQueries = 0
        XCTAssertEqual(type(router, "nguyeenx vawn an "), "nguyễn văn an ", "no capitals")
        clock += 1
        XCTAssertEqual(type(router, "xong.\\\n"), "xong.\\\n", "the backslash stays")
        _ = type(router, "dduowcj\n")
        XCTAssertEqual(returnQueries, 0, "the field is not even asked")
    }

    func testAutoFixOffKeepsShortcuts() {
        let router = makeRouter()
        router.setShortcuts([("vn", "Việt Nam")])
        router.autoFix = false
        XCTAssertEqual(type(router, "vn "), "Việt Nam ")
    }

    func testAutoFixBackOnKeepsSubSwitches() {
        let router = makeRouter()
        let learning = self.learning!
        learning.autoCapitalize = false
        learning.strayEnter = false
        learning.doubleKeyFix = false
        router.autoFix = false
        router.autoFix = true
        XCTAssertFalse(learning.autoCapitalize)
        XCTAssertFalse(learning.strayEnter)
        XCTAssertFalse(learning.doubleKeyFix)
        XCTAssertTrue(router.autoFix)
        XCTAssertTrue(router.autoSwitchOn)
    }
}
