import XCTest
@testable import LeanKeysKit

/// Lets every key through (as Vikey does for plain letters) and counts calls.
private final class PassEngine: TypingEngine {
    var processCalls = 0
    var resetCalls = 0
    var isVietnamese = true
    func process(keyCode: UInt16, caps: Bool, shift: Bool) -> EngineEdit? {
        processCalls += 1
        return nil
    }
    func resetContext() { resetCalls += 1 }
    func setVietnamese(_ on: Bool) { isVietnamese = on }
    func setAutoSwitch(_ on: Bool) {}
    func setModernTone(_ on: Bool) {}
}

private func handled(_ result: InterceptResult) -> (Int, [Character], Bool)?? {
    if case .handled(let r) = result { return .some(r) }
    return .none
}

private func isPass(_ result: InterceptResult) -> Bool {
    if case .passToGoNhanh = result { return true }
    return false
}

/// US-layout key codes used here.
private enum Key {
    static let letters: [Character: UInt16] = [
        "a": 0, "c": 8, "d": 2, "e": 14, "g": 5, "h": 4, "i": 34, "k": 40, "n": 45, "o": 31, "p": 35, "r": 15, "s": 1,
        "u": 32, "v": 9, "x": 7,
    ]
    static let space: UInt16 = 49
    static let dot: UInt16 = 47
    /// Keys that are not letters, typed by `type` as they are.
    static let others: [Character: (key: UInt16, shift: Bool)] = [
        " ": (49, false), ".": (47, false), ",": (43, false), "@": (19, true), "1": (18, false), "4": (21, false),
        "9": (25, false),
    ]
    static let comma: UInt16 = 43
    static let returnKey: UInt16 = 36
    static let tab: UInt16 = 48
    static let one: UInt16 = 18
}

final class ShortcutExpanderTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var engine: PassEngine!

    override func setUp() {
        super.setUp()
        suiteName = "ShortcutExpanderTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        engine = PassEngine()
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeRouter(stored: EngineKind? = nil) -> EngineRouter {
        if let stored { defaults.set(stored.rawValue, forKey: "LeanKeys.engine") }
        let router = EngineRouter(defaults: defaults, makeVikey: { [unowned self] in self.engine })
        router.setShortcuts([("vn", "Việt Nam"), ("ko", "không")])
        return router
    }

    /// Types `word` through the router, letter by letter; uppercase letters are sent with caps.
    private func type(_ word: String, into router: EngineRouter) {
        for c in word {
            if let (key, shift) = Key.others[c] {
                _ = router.intercept(keyCode: key, caps: false, ctrl: false, shift: shift)
                continue
            }
            let key = Key.letters[Character(c.lowercased())]!
            _ = router.intercept(keyCode: key, caps: c.isUppercase, ctrl: false, shift: c.isUppercase)
        }
    }

    func testExpandsOnSpaceWithVikey() {
        let router = makeRouter()
        var phrases: [String] = []
        router.mirror.onPhrase = { phrases.append($0.text) }
        type("vn", into: router)
        let resetsBefore = engine.resetCalls

        let r = handled(router.intercept(keyCode: Key.space, caps: false, ctrl: false, shift: false))
        // Space is not posted after an edit (RustBridge's break path excludes it), so it rides in the text.
        XCTAssertEqual(r??.0, 2)
        XCTAssertEqual(r??.1, Array("Việt Nam "))
        XCTAssertEqual(r??.2, true, "Space is consumed: its character is in the text")
        XCTAssertEqual(engine.processCalls, 2, "Vikey never sees the break key that expanded")
        XCTAssertGreaterThan(engine.resetCalls, resetsBefore, "Vikey forgets the trigger it still holds")

        // The mirror holds what is on screen.
        XCTAssertEqual(router.mirror.currentWord, "")
        router.mirror.reset()
        XCTAssertEqual(phrases, ["Việt Nam"])
    }

    func testPunctuationAndReturnPassThrough() {
        let router = makeRouter()
        var phrases: [String] = []
        router.mirror.onPhrase = { phrases.append($0.text) }

        type("vn", into: router)
        var r = handled(router.intercept(keyCode: Key.comma, caps: false, ctrl: false, shift: false))
        XCTAssertEqual(r??.0, 2)
        XCTAssertEqual(r??.1, Array("Việt Nam"))
        XCTAssertEqual(r??.2, false, "the comma is typed by the key itself")
        router.mirror.reset()
        XCTAssertEqual(phrases, ["Việt Nam,"])

        type("ko", into: router)
        r = handled(router.intercept(keyCode: Key.one, caps: false, ctrl: false, shift: true))
        XCTAssertEqual(r??.1, Array("không"))
        XCTAssertEqual(r??.2, false, "Shift+1 (!) is typed by the key itself")
        router.clear()
        XCTAssertEqual(phrases.last, "không")

        type("vn", into: router)
        r = handled(router.intercept(keyCode: Key.returnKey, caps: false, ctrl: false, shift: false))
        XCTAssertEqual(r??.0, 2)
        XCTAssertEqual(r??.1, Array("Việt Nam"))
        XCTAssertEqual(r??.2, false, "Return is posted for real so it still submits")
        XCTAssertEqual(phrases.last, "Việt Nam")
    }

    func testCaseRules() {
        let expander = ShortcutExpander([("vn", "Việt Nam"), ("ko", "không")])
        XCTAssertEqual(expander.expand(word: "vn"), "Việt Nam")
        XCTAssertEqual(expander.expand(word: "Vn"), "Việt Nam")
        XCTAssertEqual(expander.expand(word: "VN"), "VIỆT NAM")
        XCTAssertEqual(expander.expand(word: "vN"), "Việt Nam", "lowercase first letter: replacement as is")
        XCTAssertEqual(expander.expand(word: "Ko"), "Không")
        XCTAssertEqual(expander.expand(word: "KO"), "KHÔNG")

        let router = makeRouter()
        type("VN", into: router)
        let r = handled(router.intercept(keyCode: Key.space, caps: false, ctrl: false, shift: false))
        XCTAssertEqual(r??.1, Array("VIỆT NAM "))
    }

    func testNoExpansionMidWord() {
        let expander = ShortcutExpander([("vn", "Việt Nam")])
        XCTAssertNil(expander.expand(word: "vnexpress"))
        XCTAssertNil(expander.expand(word: "avn"))
        XCTAssertNil(expander.expand(word: ""))

        let router = makeRouter()
        type("vnexpress", into: router)
        let r = handled(router.intercept(keyCode: Key.space, caps: false, ctrl: false, shift: false))
        XCTAssertEqual(r.map { $0 == nil }, true, "Vikey decides (here: lets Space through)")
        XCTAssertEqual(engine.processCalls, 10)
    }

    func testTabAndClearedTableDoNotExpand() {
        let router = makeRouter()
        type("vn", into: router)
        let r = handled(router.intercept(keyCode: Key.tab, caps: false, ctrl: false, shift: false))
        XCTAssertEqual(r.map { $0 == nil }, true, "Tab is no trigger, as in Gõ Nhanh")

        router.setShortcuts([])
        type("vn", into: router)
        let r2 = handled(router.intercept(keyCode: Key.space, caps: false, ctrl: false, shift: false))
        XCTAssertEqual(r2.map { $0 == nil }, true)
    }

    func testNoDoubleExpansionOnGoNhanh() {
        // Gõ Nhanh's own engine expands shortcuts; the router must leave the key to it.
        let router = makeRouter(stored: .gonhanh)
        XCTAssertEqual(router.active, .gonhanh)
        for key: UInt16 in [9, 45] { router.observeGoNhanh(keyCode: key, shift: false, caps: false, result: nil) }
        XCTAssertEqual(router.mirror.currentWord, "vn")
        XCTAssertTrue(isPass(router.intercept(keyCode: Key.space, caps: false, ctrl: false, shift: false)))

        // VNI forces Gõ Nhanh too.
        let vni = makeRouter()
        vni.selected = .vikey
        vni.setMethod(1)
        XCTAssertEqual(vni.active, .gonhanh)
        for key: UInt16 in [9, 45] { vni.observeGoNhanh(keyCode: key, shift: false, caps: false, result: nil) }
        XCTAssertTrue(isPass(vni.intercept(keyCode: Key.space, caps: false, ctrl: false, shift: false)))
    }

    func testNoExpansionAfterInWordPunctuation() {
        // Gõ Nhanh matches ".vn" here (its shortcut_prefix), never "vn".
        for text in ["gov.vn", "a,vn", "an@vidu.vn"] {
            let router = makeRouter()
            type(text, into: router)
            XCTAssertEqual(router.mirror.currentWord, "vn", text)
            let r = handled(router.intercept(keyCode: Key.space, caps: false, ctrl: false, shift: false))
            XCTAssertEqual(r.map { $0 == nil }, true, "\(text) + Space must not expand")
        }
        let router = makeRouter()
        type("xin chao vn", into: router)
        let r = handled(router.intercept(keyCode: Key.space, caps: false, ctrl: false, shift: false))
        XCTAssertEqual(r??.1, Array("Việt Nam "))
    }

    func testExpandsWithVietnameseOff() {
        // Gõ Nhanh expands with the IME off too.
        let router = makeRouter()
        router.setEnabled(false, explicit: true)
        type("vn", into: router)
        let r = handled(router.intercept(keyCode: Key.space, caps: false, ctrl: false, shift: false))
        XCTAssertEqual(r??.1, Array("Việt Nam "))
    }

    func testNoExpansionWhenMirrorLostTrack() {
        let router = makeRouter()
        // An edit that deletes more than the mirror holds: the text left of the cursor is unknown.
        router.mirror.apply(deleteCount: 3, insert: [])
        type("vn", into: router)
        let r = handled(router.intercept(keyCode: Key.space, caps: false, ctrl: false, shift: false))
        XCTAssertEqual(r.map { $0 == nil }, true)
    }

    func testNoExpansionInsideNumberWord() {
        let router = makeRouter()
        router.setShortcuts([("k", "nghìn")])
        type("149k", into: router)
        let r = handled(router.intercept(keyCode: Key.space, caps: false, ctrl: false, shift: false))
        XCTAssertEqual(r.map { $0 == nil }, true, "149k is no trigger k")
    }
}
