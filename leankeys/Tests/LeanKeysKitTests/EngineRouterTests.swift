import XCTest
@testable import LeanKeysKit

/// Records every call. Models a word buffer: once a key went in since the last reset, the next edit deletes one
/// character (a stale buffer shows up as deleteCount > 0).
private final class FakeEngine: TypingEngine {
    var processCalls = 0
    var resetCalls = 0
    var setVietnameseCalls: [Bool] = []
    var setAutoSwitchCalls: [Bool] = []
    var setModernToneCalls: [Bool] = []
    var isVietnamese = true
    var buffered = 0
    /// When set, returned as is instead of the buffer model.
    var scripted: EngineEdit??

    func process(keyCode: UInt16, caps: Bool, shift: Bool) -> EngineEdit? {
        processCalls += 1
        if let scripted { return scripted }
        let edit = EngineEdit(deleteCount: buffered > 0 ? 1 : 0, text: ["x"], languageChanged: false)
        buffered += 1
        return edit
    }

    func resetContext() {
        resetCalls += 1
        buffered = 0
    }

    func setVietnamese(_ on: Bool) {
        setVietnameseCalls.append(on)
        isVietnamese = on
    }

    func setAutoSwitch(_ on: Bool) {
        setAutoSwitchCalls.append(on)
    }

    func setModernTone(_ on: Bool) {
        setModernToneCalls.append(on)
    }
}

private func isPass(_ result: InterceptResult) -> Bool {
    if case .passToGoNhanh = result { return true }
    return false
}

private func handled(_ result: InterceptResult) -> (Int, [Character], Bool)?? {
    if case .handled(let r) = result { return .some(r) }
    return .none
}

final class EngineRouterTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var fake: FakeEngine!
    private var factoryCalls = 0

    override func setUp() {
        super.setUp()
        suiteName = "EngineRouterTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        fake = FakeEngine()
        factoryCalls = 0
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    /// `stored` writes "LeanKeys.engine" first, as if the user had picked that engine earlier.
    private func makeRouter(failingVikey: Bool = false, stored: EngineKind? = nil) -> EngineRouter {
        if let stored { defaults.set(stored.rawValue, forKey: "LeanKeys.engine") }
        return EngineRouter(defaults: defaults, makeVikey: { [unowned self] in
            self.factoryCalls += 1
            return failingVikey ? nil : self.fake
        })
    }

    private func press(_ router: EngineRouter, ctrl: Bool = false) -> InterceptResult {
        router.intercept(keyCode: 0, caps: false, ctrl: ctrl, shift: false)
    }

    func testDefaultIsVikey() {
        let router = makeRouter()
        XCTAssertEqual(router.selected, .vikey)
        XCTAssertEqual(router.active, .vikey)
        XCTAssertNil(router.fallbackReason)
        XCTAssertEqual(factoryCalls, 1, "the default engine is built at start")
        XCTAssertNil(defaults.string(forKey: "LeanKeys.engine"), "the default is not written back")

        router.setMethod(1)
        XCTAssertEqual(router.active, .gonhanh, "VNI still falls back to Gõ Nhanh")
        XCTAssertEqual(router.fallbackReason, "vni")
        XCTAssertTrue(isPass(press(router)))
    }

    func testStoredGoNhanhIsKept() {
        let router = makeRouter(stored: .gonhanh)
        XCTAssertEqual(router.selected, .gonhanh)
        XCTAssertEqual(router.active, .gonhanh)
        XCTAssertNil(router.fallbackReason)
        XCTAssertTrue(isPass(press(router)))
        XCTAssertTrue(isPass(press(router, ctrl: true)), "Gõ Nhanh handles its own shortcuts")
        XCTAssertEqual(factoryCalls, 0, "Vikey is built only when first needed")
    }

    func testUnknownStoredValueReadsAsVikey() {
        XCTAssertEqual(makeRouter(stored: nil).selected, .vikey)
        defaults.set("bogus", forKey: "LeanKeys.engine")
        XCTAssertEqual(makeRouter().selected, .vikey)
    }

    func testSelectedPersistsUnderLeanKeysEngineKey() {
        let router = makeRouter()
        router.selected = .gonhanh
        XCTAssertEqual(defaults.string(forKey: "LeanKeys.engine"), "gonhanh")
        XCTAssertEqual(makeRouter().selected, .gonhanh)
        router.selected = .vikey
        XCTAssertEqual(defaults.string(forKey: "LeanKeys.engine"), "vikey")
        XCTAssertEqual(makeRouter().selected, .vikey)
    }

    func testVikeySelectedHandles() {
        let router = makeRouter()
        router.selected = .vikey
        XCTAssertEqual(router.active, .vikey)

        fake.scripted = .some(EngineEdit(deleteCount: 2, text: ["á", "b"], languageChanged: false))
        guard let some = handled(press(router)), let r = some else { return XCTFail("expected .handled(edit)") }
        XCTAssertEqual(r.0, 2)
        XCTAssertEqual(r.1, ["á", "b"])
        XCTAssertTrue(r.2)

        fake.scripted = .some(nil)
        guard let none = handled(press(router)) else { return XCTFail("expected .handled(nil)") }
        XCTAssertNil(none)
    }

    func testVNIForcesGoNhanh() {
        let router = makeRouter()
        router.selected = .vikey
        router.setMethod(1)
        XCTAssertEqual(router.active, .gonhanh)
        XCTAssertEqual(router.fallbackReason, "vni")
        XCTAssertTrue(isPass(press(router)))

        router.setMethod(0)
        XCTAssertEqual(router.active, .vikey)
        XCTAssertNil(router.fallbackReason)
    }

    func testVNIBeforeSelectingVikeyNeverBuildsIt() {
        let router = makeRouter(stored: .gonhanh)
        router.setMethod(1)
        router.selected = .vikey
        XCTAssertEqual(router.fallbackReason, "vni")
        XCTAssertTrue(isPass(press(router)))
        XCTAssertEqual(factoryCalls, 0)
    }

    func testVikeyInitFailureFallsBack() {
        let router = makeRouter(failingVikey: true)
        router.selected = .vikey
        XCTAssertEqual(router.active, .gonhanh)
        XCTAssertEqual(router.fallbackReason, "vikey-init-failed")
        XCTAssertTrue(isPass(press(router)))
        router.selected = .gonhanh
        XCTAssertNil(router.fallbackReason)
        router.selected = .vikey
        _ = press(router)
        XCTAssertEqual(router.fallbackReason, "vikey-init-failed")
        XCTAssertEqual(factoryCalls, 1, "a failed init is not retried")
    }

    func testVikeyBuiltOnceAcrossSwitches() {
        let router = makeRouter(stored: .gonhanh)
        for _ in 0..<3 {
            router.selected = .vikey
            _ = press(router)
            router.selected = .gonhanh
        }
        XCTAssertEqual(factoryCalls, 1)
    }

    func testBypassResetsAndPassesThrough() {
        let router = makeRouter()
        router.selected = .vikey
        let resets = fake.resetCalls
        let result = press(router, ctrl: true)
        guard let r = handled(result) else { return XCTFail("expected .handled(nil)") }
        XCTAssertNil(r)
        XCTAssertEqual(fake.resetCalls, resets + 1)
        XCTAssertEqual(fake.processCalls, 0, "a Ctrl chord never reaches Vikey")
    }

    func testSwitchEngineMidWordClearsState() {
        let router = makeRouter()
        router.selected = .vikey
        _ = press(router)
        _ = press(router)
        XCTAssertGreaterThan(fake.buffered, 0)

        var resets = fake.resetCalls
        router.selected = .gonhanh
        XCTAssertGreaterThan(fake.resetCalls, resets, "old engine reset")

        resets = fake.resetCalls
        router.selected = .vikey
        XCTAssertGreaterThan(fake.resetCalls, resets, "new engine reset")
        guard let some = handled(press(router)), let r = some else { return XCTFail("expected .handled(edit)") }
        XCTAssertEqual(r.0, 0, "no stale buffer after the switch")
    }

    func testLeavingVikeyForVNIClearsState() {
        let router = makeRouter()
        router.selected = .vikey
        _ = press(router)
        let resets = fake.resetCalls
        router.setMethod(1)
        XCTAssertGreaterThan(fake.resetCalls, resets)
    }

    func testLanguageChangeNotification() {
        let router = makeRouter()
        router.selected = .vikey
        fake.isVietnamese = false
        fake.scripted = .some(EngineEdit(deleteCount: 0, text: [], languageChanged: true))
        let expected = fake.isVietnamese
        let posted = expectation(forNotification: .leanKeysLanguageChanged, object: nil) { note in
            note.userInfo?["vietnamese"] as? Bool == expected
        }
        guard let some = handled(press(router)), let r = some else { return XCTFail("expected .handled(edit)") }
        XCTAssertEqual(r.0, 0)
        XCTAssertTrue(r.1.isEmpty)
        wait(for: [posted], timeout: 2)
    }

    func testSetEnabledForwardsToVikey() {
        let router = makeRouter()
        router.selected = .vikey
        router.setEnabled(false)
        XCTAssertEqual(fake.setVietnameseCalls.last, false)
    }

    func testSetEnabledBeforeVikeyExistsAppliesOnCreation() {
        let router = makeRouter(stored: .gonhanh)
        router.setEnabled(false)
        XCTAssertEqual(factoryCalls, 0)
        router.selected = .vikey
        XCTAssertEqual(fake.setVietnameseCalls.last, false)
        XCTAssertFalse(fake.isVietnamese)
    }

    func testClearResetsVikey() {
        let router = makeRouter()
        router.selected = .vikey
        _ = press(router)
        let resets = fake.resetCalls
        router.clear()
        XCTAssertEqual(fake.resetCalls, resets + 1)
    }

    func testKeyPassesThroughIsNotConsumed() {
        // Ruling R12: an edit whose key must still be typed reports keyConsumed == false.
        let router = makeRouter()
        router.selected = .vikey
        fake.scripted = .some(EngineEdit(deleteCount: 4, text: Array("test"), languageChanged: false, keyPassesThrough: true))
        let r = handled(press(router))
        XCTAssertEqual(r??.0, 4)
        XCTAssertEqual(r??.1, Array("test"))
        XCTAssertEqual(r??.2, false)

        fake.scripted = .some(EngineEdit(deleteCount: 1, text: ["x"], languageChanged: false))
        XCTAssertEqual(handled(press(router))??.2, true, "an ordinary edit stays consumed")
    }

    // MARK: - Ruling R25: only the user's own off pauses auto switch; on always restores it

    /// Vikey switches to English by itself; the router announces it.
    private func selfSwitchToEnglish(_ router: EngineRouter) {
        fake.isVietnamese = false
        fake.scripted = .some(EngineEdit(deleteCount: 0, text: [], languageChanged: true))
        _ = press(router)
        fake.scripted = nil
    }

    func testExplicitOffPausesAutoSwitch() {
        let router = makeRouter()
        router.setEnabled(false, explicit: true)
        XCTAssertEqual(fake.setAutoSwitchCalls.last, false)
        XCTAssertEqual(fake.setVietnameseCalls.last, false)
    }

    /// The echo of Vikey's switch, and any later replay of that off (input source change, launch), leave auto
    /// switch on.
    func testOffAfterAnAutoSwitchWithoutExplicitKeepsAutoSwitch() {
        let router = makeRouter()
        selfSwitchToEnglish(router)
        router.setEnabled(false) // the app mirroring the switch
        router.setEnabled(false) // e.g. InputSourceManager replaying AppState later
        XCTAssertFalse(fake.setAutoSwitchCalls.contains(false), "auto switch must stay on")
        XCTAssertEqual(fake.setVietnameseCalls.last, false)
    }

    func testOnAlwaysRestoresAutoSwitch() {
        let router = makeRouter()
        router.setEnabled(false, explicit: true)
        router.setEnabled(true) // not explicit: launch, input source, per-app "Bật"
        XCTAssertEqual(fake.setAutoSwitchCalls.last, true)
        XCTAssertEqual(fake.setVietnameseCalls.last, true)
    }

    func testLanguageBeforeAutoSwitchIsTheUsersUntilTheNextExplicitChoice() {
        let router = makeRouter()
        router.setEnabled(true, explicit: true)
        XCTAssertNil(router.languageBeforeAutoSwitch)
        selfSwitchToEnglish(router)
        XCTAssertEqual(router.languageBeforeAutoSwitch, true)
        router.setEnabled(false) // echo: not the user's choice
        fake.isVietnamese = true
        fake.scripted = .some(EngineEdit(deleteCount: 0, text: [], languageChanged: true))
        _ = press(router) // back to Vietnamese, then English again
        selfSwitchToEnglish(router)
        XCTAssertEqual(router.languageBeforeAutoSwitch, true, "the first automatic switch keeps the user's value")
        router.setEnabled(false, explicit: true)
        XCTAssertNil(router.languageBeforeAutoSwitch)
    }

    func testOffAndModernToneApplyWhenVikeyIsBuiltLater() {
        let router = makeRouter(stored: .gonhanh)
        router.setEnabled(false, explicit: true)
        router.setModernTone(false)
        XCTAssertEqual(factoryCalls, 0)
        router.selected = .vikey
        XCTAssertEqual(fake.setAutoSwitchCalls.last, false)
        XCTAssertEqual(fake.setModernToneCalls.last, false)
    }

    func testModernToneForwardsToVikey() {
        let router = makeRouter()
        router.setModernTone(false)
        XCTAssertEqual(fake.setModernToneCalls.last, false)
        router.setModernTone(true)
        XCTAssertEqual(fake.setModernToneCalls.last, true)
    }

    func testRouterAutoSwitchFollowsExplicitOff() {
        let router = makeRouter()
        router.setEnabled(false, explicit: true)
        XCTAssertFalse(router.autoSwitchOn)
        router.setEnabled(true)
        XCTAssertTrue(router.autoSwitchOn)
        router.setEnabled(false)
        XCTAssertTrue(router.autoSwitchOn, "an automatic off must not pause auto switch")
    }

    // MARK: ⌃⌫ convert (design 5.1), real engine

    private func convertRouter(bundle: String = "com.apple.Notes") -> (EngineRouter, VikeyEngine, UndoLearning) {
        let engine = VikeyEngine()!
        engine.resetContext()
        let learning = UndoLearning(book: UndoRuleBook(store: nil), defaults: defaults,
                                    context: { LearnContext(bundleID: bundle, secureInput: false, secureField: false,
                                                            now: Date()) })
        let router = EngineRouter(defaults: defaults, makeVikey: { engine }, undoLearning: { learning },
                                  frontmostBundleID: { bundle })
        return (router, engine, learning)
    }

    private func typeKeys(_ router: EngineRouter, _ keys: [UInt16]) {
        for k in keys { _ = router.intercept(keyCode: k, caps: false, ctrl: false, shift: false) }
    }

    // c o s space
    private let cosKeys: [UInt16] = [8, 31, 1, 49]

    func testConvertLastWord() {
        let (router, _, learning) = convertRouter()
        defer { learning.uninstall() }
        typeKeys(router, cosKeys)
        let result = router.convertLastWord()
        XCTAssertEqual(result?.0, 3)
        XCTAssertEqual(result.map { String($0.1) }, "cos ")
        XCTAssertEqual(result?.2, true)
        XCTAssertEqual(router.mirror.phraseText, "cos ")
    }

    func testConvertLastWordIsNilInCodeApps() {
        let (router, _, learning) = convertRouter(bundle: "com.apple.Terminal")
        defer { learning.uninstall() }
        typeKeys(router, cosKeys)
        XCTAssertNil(router.convertLastWord())
    }

    func testConvertLastWordIsNilWithAutoFixOff() {
        let (router, _, learning) = convertRouter()
        defer { learning.uninstall() }
        router.autoFix = false
        typeKeys(router, cosKeys)
        XCTAssertNil(router.convertLastWord())
    }

    func testConvertLastWordIsNilOnAFreshLineAndDropsTheMirror() {
        let (router, _, learning) = convertRouter()
        defer { learning.uninstall() }
        router.clear()
        XCTAssertNil(router.convertLastWord())
        typeKeys(router, [8, 31])
        XCTAssertFalse(router.mirror.currentWord.isEmpty)
        XCTAssertNil(router.convertLastWord(), "mid-word: nothing to convert yet; the key goes to the app")
        XCTAssertTrue(router.mirror.currentWord.isEmpty, "router and shim both forgot the word")
    }

    func testConvertLastWordIsNilForGoNhanh() {
        let router = makeRouter(stored: .gonhanh)
        XCTAssertNil(router.convertLastWord())
    }
}
