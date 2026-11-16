import XCTest
import VikeyShim
@testable import LeanKeysKit

/// Spec 17.2: a key next to Enter hit together with Enter is dropped, before Enter (deleted) or right after (never
/// typed). Unit tests on `StrayEnterFilter`, the mirror's line, and the router path with the real engine.

private let backslash: UInt16 = 42, bracket: UInt16 = 30, quote: UInt16 = 39, enter: UInt16 = 36, letterA: UInt16 = 0

final class StrayEnterFilterTests: XCTestCase {
    /// A non-zero base time, so the window's boundary is checked on real floating-point sums.
    private let t0: TimeInterval = 1_000.7

    private func decide(_ filter: inout StrayEnterFilter, _ keyCode: UInt16, shift: Bool = false,
                        modifiers: Bool = false, at time: TimeInterval, line: String, known: Bool = true,
                        bundle: String? = "com.apple.Notes", telex: Bool = false) -> StrayEnterFilter.Decision {
        filter.decide(keyCode: keyCode, shift: shift, otherModifiers: modifiers, time: time, lineBeforeCursor: line,
                      lineStartKnown: known, bundleID: bundle, bracketTypesLetter: telex)
    }

    /// `key` typed at t0 onto `line` (its character is already the line's last), then Enter after `gap`.
    private func enterAfter(_ key: UInt16, shift: Bool = false, gap: TimeInterval, line: String,
                            enterModifiers: Bool = false, known: Bool = true,
                            bundle: String? = "com.apple.Notes") -> StrayEnterFilter.Decision {
        var filter = StrayEnterFilter()
        XCTAssertEqual(decide(&filter, key, shift: shift, at: t0, line: String(line.dropLast()), known: known,
                              bundle: bundle), .none)
        return decide(&filter, enter, modifiers: enterModifiers, at: t0 + gap, line: line, known: known,
                      bundle: bundle)
    }

    func testDeletesStrayBackslashBeforeEnter() {
        XCTAssertEqual(enterAfter(backslash, gap: 0.040, line: "xong.\\"), .deleteBeforeEnter)
        XCTAssertEqual(enterAfter(backslash, shift: true, gap: 0.040, line: "xong.|"), .deleteBeforeEnter)
        XCTAssertEqual(enterAfter(bracket, gap: 0.040, line: "xong]"), .deleteBeforeEnter)
        XCTAssertEqual(enterAfter(bracket, shift: true, gap: 0.040, line: "xong}"), .deleteBeforeEnter)
        XCTAssertEqual(enterAfter(quote, gap: 0.040, line: "xong'"), .deleteBeforeEnter)
        XCTAssertEqual(enterAfter(quote, shift: true, gap: 0.040, line: "xong\""), .deleteBeforeEnter)
        // Numpad Enter too.
        var filter = StrayEnterFilter()
        _ = decide(&filter, backslash, at: t0, line: "ok")
        XCTAssertEqual(decide(&filter, 76, at: t0 + 0.040, line: "ok\\"), .deleteBeforeEnter)
    }

    /// Only a character the key put at the end of the line is deleted: not when the line ends otherwise (the
    /// engine turned the key into something else, or the line is unknown: empty), and not with the other shift.
    func testDeletesOnlyTheKeysOwnCharacter() {
        XCTAssertEqual(enterAfter(bracket, gap: 0.040, line: "xongư"), .none)
        XCTAssertEqual(enterAfter(backslash, gap: 0.040, line: ""), .none)
        var filter = StrayEnterFilter()
        _ = decide(&filter, backslash, shift: true, at: t0, line: "ok")
        XCTAssertEqual(decide(&filter, enter, at: t0 + 0.040, line: "ok\\"), .none, "| was typed, the line ends in \\")
    }

    /// Spec 17.4: exactly 100 ms is within the window, 101 ms is not.
    func testKeepsWhenSlow() {
        XCTAssertEqual(enterAfter(backslash, gap: 0.101, line: "xong.\\"), .none)
        XCTAssertEqual(enterAfter(backslash, gap: 0.100, line: "xong.\\"), .deleteBeforeEnter)
        XCTAssertEqual(StrayEnterFilter.window, 0.100)
        // After Enter as well.
        var filter = StrayEnterFilter()
        _ = decide(&filter, enter, at: t0, line: "xong")
        XCTAssertEqual(decide(&filter, backslash, at: t0 + 0.101, line: ""), .none)
        _ = decide(&filter, enter, at: t0 + 1, line: "")
        XCTAssertEqual(decide(&filter, backslash, at: t0 + 1 + 0.100, line: ""), .dropKey)
    }

    func testDropsStrayAfterEnter() {
        for (key, shift) in [(backslash, false), (backslash, true), (bracket, false), (bracket, true),
                             (quote, false), (quote, true)] {
            var filter = StrayEnterFilter()
            _ = decide(&filter, letterA, at: t0, line: "")
            XCTAssertEqual(decide(&filter, enter, at: t0 + 0.5, line: "xong"), .none)
            XCTAssertEqual(decide(&filter, key, shift: shift, at: t0 + 0.530, line: ""), .dropKey, "\(key) \(shift)")
            // Only the key right after Enter.
            XCTAssertEqual(decide(&filter, key, shift: shift, at: t0 + 0.540, line: ""), .none)
        }
        // Not a key that is not next to Enter.
        var filter = StrayEnterFilter()
        _ = decide(&filter, enter, at: t0, line: "xong")
        XCTAssertEqual(decide(&filter, letterA, at: t0 + 0.010, line: ""), .none)
        // Not when another key came between: "\" "a" Enter keeps the "\" (it is not the line's end anyway).
        filter = StrayEnterFilter()
        _ = decide(&filter, backslash, at: t0, line: "x")
        _ = decide(&filter, letterA, at: t0 + 0.010, line: "x\\")
        XCTAssertEqual(decide(&filter, enter, at: t0 + 0.020, line: "x\\a"), .none)
    }

    /// Fix round 1 (R8): with the line's start unknown (after a click, app switch, Tab, launch), `\` and `|` are
    /// still deleted from the typed tail; `'` `"` `]` `}` need the whole line for the pair rule, so they stay.
    func testUnknownLineStartDeletesOnlyPairless() {
        XCTAssertEqual(enterAfter(backslash, gap: 0.040, line: "xong.\\", known: false), .deleteBeforeEnter)
        XCTAssertEqual(enterAfter(backslash, shift: true, gap: 0.040, line: "xong|", known: false), .deleteBeforeEnter)
        XCTAssertEqual(enterAfter(backslash, gap: 0.100, line: "xong\\", known: false), .deleteBeforeEnter)
        XCTAssertEqual(enterAfter(backslash, gap: 0.101, line: "xong\\", known: false), .none)
        XCTAssertEqual(enterAfter(backslash, gap: 0.040, line: "xong\\", enterModifiers: true, known: false), .none)
        XCTAssertEqual(enterAfter(backslash, gap: 0.040, line: "xong\\", known: false, bundle: "com.apple.Terminal"),
                       .none)
        for (key, shift, line) in [(quote, false, "xong'"), (quote, true, "xong\""), (bracket, false, "xong]"),
                                   (bracket, true, "xong}")] {
            XCTAssertEqual(enterAfter(key, shift: shift, gap: 0.040, line: line, known: false), .none, line)
        }
        XCTAssertEqual(enterAfter(backslash, gap: 0.040, line: "", known: false), .none, "empty tail")
        XCTAssertEqual(enterAfter(backslash, gap: 0.040, line: "xong", known: false), .none, "tail without it")
        XCTAssertEqual(enterAfter(backslash, shift: true, gap: 0.040, line: "xong\\", known: false), .none)
    }

    func testOpenPairKept() {
        // An odd number of quotes before it: the quote closes "'xin chào", so it stays.
        XCTAssertEqual(enterAfter(quote, gap: 0.040, line: "nói 'xin chào'"), .none)
        XCTAssertEqual(enterAfter(quote, shift: true, gap: 0.040, line: "nói \"xin chào\""), .none)
        XCTAssertEqual(enterAfter(bracket, gap: 0.040, line: "[ghi chú]"), .none)
        XCTAssertEqual(enterAfter(bracket, shift: true, gap: 0.040, line: "{ghi chú}"), .none)
        // A pair already closed earlier on the line does not keep a stray after it.
        XCTAssertEqual(enterAfter(quote, gap: 0.040, line: "nói 'xin chào' xong'"), .deleteBeforeEnter)
        XCTAssertEqual(enterAfter(bracket, gap: 0.040, line: "[ghi chú] xong]"), .deleteBeforeEnter)
        XCTAssertEqual(enterAfter(bracket, gap: 0.040, line: "[a [b] c]"), .none, "nested: still one open")
    }

    /// Ruling R14 (M3): in Vietnamese Telex `]` and `}` type ư and Ư, so after Enter they start the next line and
    /// are never dropped. `\` and `'` still are.
    func testBracketKeptAfterEnterWhenItTypesALetter() {
        for (key, shift, dropped) in [(bracket, false, false), (bracket, true, false), (backslash, false, true),
                                      (quote, true, true)] {
            var filter = StrayEnterFilter()
            _ = decide(&filter, enter, at: t0, line: "xong", telex: true)
            XCTAssertEqual(decide(&filter, key, shift: shift, at: t0 + 0.030, line: "", telex: true),
                           dropped ? .dropKey : .none, "\(key) \(shift)")
        }
    }

    func testExcludedApps() {
        for bundle in ["com.apple.Terminal", "com.jetbrains.intellij", "com.jetbrains.pycharm", "com.googlecode.iterm2",
                       "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92", "com.apple.dt.Xcode",
                       "com.google.android.studio"] {
            XCTAssertEqual(enterAfter(backslash, gap: 0.040, line: "x\\", bundle: bundle), .none, bundle)
            var filter = StrayEnterFilter()
            _ = decide(&filter, enter, at: t0, line: "x", bundle: bundle)
            XCTAssertEqual(decide(&filter, backslash, at: t0 + 0.010, line: "", bundle: bundle), .none, bundle)
        }
        XCTAssertTrue(CodeApps.contains("com.apple.Terminal"))
        // Ruling R12: one list of terminals and code editors, the learning exclusions' terminals included.
        for terminal in ["co.zeit.hyper", "org.tabby"] {
            XCTAssertEqual(enterAfter(backslash, gap: 0.040, line: "x\\", bundle: terminal), .none, terminal)
        }
        XCTAssertEqual(enterAfter(backslash, gap: 0.040, line: "x\\", bundle: nil), .deleteBeforeEnter)
    }

    /// Review Focus 5: a key or an Enter with ⌘, ⌥ or ⌃ is never dropped and never deletes.
    func testModifiersNeverDropped() {
        // ⌥+Enter after a stray-looking "\".
        XCTAssertEqual(enterAfter(backslash, gap: 0.040, line: "xong\\", enterModifiers: true), .none)
        // ⌥\ or ⌘\ right after Enter.
        var filter = StrayEnterFilter()
        _ = decide(&filter, enter, at: t0, line: "xong")
        XCTAssertEqual(decide(&filter, backslash, modifiers: true, at: t0 + 0.010, line: ""), .none)
        // A modified "\" before Enter is not a stray either.
        filter = StrayEnterFilter()
        _ = decide(&filter, backslash, modifiers: true, at: t0, line: "xong")
        XCTAssertEqual(decide(&filter, enter, at: t0 + 0.010, line: "xong\\"), .none)
        // Nor a "\" right after a modified Enter (⌘↩ sends in many apps).
        filter = StrayEnterFilter()
        _ = decide(&filter, enter, modifiers: true, at: t0, line: "xong")
        XCTAssertEqual(decide(&filter, backslash, at: t0 + 0.010, line: ""), .none)
    }

    // MARK: Mirror line

    func testMirrorLineBeforeCursor() {
        let mirror = TextMirror()
        XCTAssertNil(mirror.lineBeforeCursor, "unknown until a newline")
        XCTAssertEqual(mirror.typedTail, "")
        for c in "abc" { mirror.typed(c) }
        XCTAssertNil(mirror.lineBeforeCursor)
        XCTAssertEqual(mirror.typedTail, "abc", "what was typed is still known")
        mirror.apply(deleteCount: 1, insert: ["\\"])
        XCTAssertEqual(mirror.typedTail, "ab\\")
        mirror.apply(deleteCount: 5, insert: ["x"])
        XCTAssertEqual(mirror.typedTail, "x", "deleted past what is held: only the new text")
        mirror.typed("\n")
        XCTAssertEqual(mirror.lineBeforeCursor, "")
        // Sentence ends clear the phrase, not the line.
        for c in "Xong. Nói 'xin chào'" { mirror.typed(c) }
        XCTAssertEqual(mirror.lineBeforeCursor, "Xong. Nói 'xin chào'")
        mirror.apply(deleteCount: 2, insert: ["!"])
        XCTAssertEqual(mirror.lineBeforeCursor, "Xong. Nói 'xin chà!")
        // Deleting past the line start, a click (reset) or a bypass (discard): unknown.
        mirror.apply(deleteCount: 30, insert: ["x"])
        XCTAssertNil(mirror.lineBeforeCursor)
        XCTAssertEqual(mirror.typedTail, "x")
        mirror.typed("\r")
        XCTAssertEqual(mirror.lineBeforeCursor, "")
        mirror.typed("a")
        mirror.reset()
        XCTAssertNil(mirror.lineBeforeCursor)
        XCTAssertEqual(mirror.typedTail, "", "a click: nothing typed since")
        mirror.typed("\n")
        mirror.discard()
        XCTAssertNil(mirror.lineBeforeCursor)
        mirror.typed("\n")
        mirror.typed("\t")
        XCTAssertNil(mirror.lineBeforeCursor, "Tab moves the cursor like a click")
    }

    // MARK: Router (spec 17.2 through `EngineRouter.intercept`, real engine)

    private var engine: VikeyEngine!
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var learning: UndoLearning?
    private var clock: TimeInterval = 500.3
    private var bundle: String? = "com.apple.Notes"

    override func setUp() {
        super.setUp()
        engine = VikeyEngine()
        XCTAssertNotNil(engine, "lk_vikey_init failed")
        suiteName = "StrayEnterFilterTests.\(UUID().uuidString)"
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
        engine.setAutoSwitch(true)
        engine.resetContext()
    }

    private func makeRouter() -> EngineRouter {
        let made = UndoLearning(book: UndoRuleBook(store: nil), defaults: defaults,
                                context: { LearnContext(bundleID: "com.apple.Notes", secureInput: false,
                                                        secureField: false, now: Date()) })
        learning = made
        let engine = self.engine!
        return EngineRouter(defaults: defaults, makeVikey: { engine }, undoLearning: { made },
                            now: { [unowned self] in clock }, frontmostBundleID: { [unowned self] in bundle })
    }

    /// A fresh line the router knows: a click, then a newline typed in the field.
    private func freshLine(_ router: EngineRouter) -> RouterField {
        router.clear()
        let field = RouterField(router)
        field.press(enter)
        field.text.removeAll()
        clock += 1
        return field
    }

    func testRouterDeletesBeforeEnter() {
        let router = makeRouter()
        let field = freshLine(router)
        field.type("xong.")
        field.press(backslash)
        XCTAssertEqual(String(field.text), "xong.\\")
        clock += 0.040
        guard case .handled(let edit?) = field.press(enter) else { return XCTFail("expected the stray deleted") }
        XCTAssertEqual(edit.0, 1)
        XCTAssertTrue(edit.1.isEmpty)
        XCTAssertFalse(edit.2, "Enter follows the edit")
        XCTAssertEqual(String(field.text), "xong.\n")
        XCTAssertEqual(router.mirror.lineBeforeCursor, "", "the mirror saw the delete and the newline")
    }

    func testRouterKeepsSlowBackslash() {
        let router = makeRouter()
        let field = freshLine(router)
        field.type("xong")
        field.press(backslash)
        clock += 0.101
        field.press(enter)
        XCTAssertEqual(String(field.text), "xong\\\n")
    }

    func testRouterDropsAfterEnter() {
        let router = makeRouter()
        router.setEnabled(false)  // English: in Vietnamese Telex `]` types ư (see the next test)
        let field = freshLine(router)
        field.type("xong")
        field.press(enter)
        clock += 0.030
        guard case .handled(let edit?) = field.press(bracket) else { return XCTFail("expected the key dropped") }
        XCTAssertEqual(edit.0, 0)
        XCTAssertTrue(edit.1.isEmpty)
        XCTAssertTrue(edit.2, "consumed: the key never reaches the app")
        XCTAssertEqual(String(field.text), "xong\n")
        XCTAssertEqual(router.mirror.lineBeforeCursor, "")
        // The next line types normally.
        clock += 1
        field.type("ok")
        XCTAssertEqual(String(field.text), "xong\nok")
    }

    /// Ruling R14 (M3): in Vietnamese `]` right after Enter types ư, the start of the next line: it is kept.
    func testRouterKeepsBracketAfterEnterInVietnamese() {
        let router = makeRouter()
        router.setEnabled(true)
        let field = freshLine(router)
        field.type("xong")
        field.press(enter)
        clock += 0.030
        field.press(bracket)
        XCTAssertEqual(String(field.text), "xong\nư")
        // `\` is still dropped.
        let next = freshLine(router)
        next.type("xong")
        next.press(enter)
        clock += 0.030
        next.press(backslash)
        XCTAssertEqual(String(next.text), "xong\n")
    }

    /// The first line after a click (line start unknown): a stray `\` typed since is still deleted (R8); a `]`
    /// is kept, since the pair rule needs the whole line.
    func testRouterUnknownLineStart() {
        let router = makeRouter()
        router.clear()
        var field = RouterField(router)
        field.type("xong.")
        field.press(backslash)
        clock += 0.040
        field.press(enter)
        XCTAssertEqual(String(field.text), "xong.\n")

        clock += 1
        router.clear()
        field = RouterField(router)
        field.type("xong ")
        field.press(bracket)
        let typed = String(field.text)
        clock += 0.040
        field.press(enter)
        XCTAssertEqual(String(field.text), typed + "\n", "kept")

        clock += 1
        router.clear()
        field = RouterField(router)
        field.press(backslash)
        clock += 0.040
        field.press(enter)
        XCTAssertEqual(String(field.text), "\n", "the tail is just the stray")
    }

    func testRouterModifiersNeverDropped() {
        let router = makeRouter()
        let field = freshLine(router)
        field.type("xong")
        field.press(enter)
        clock += 0.010
        // ⌥\ (and ⌃\) reach the router as Ctrl chords: the key goes through untouched.
        guard case .handled(nil) = router.intercept(keyCode: backslash, caps: false, ctrl: true, shift: false) else {
            return XCTFail("a modified key goes through")
        }
        // ⌥+Return after a stray-looking "\".
        let next = freshLine(router)
        next.type("xong")
        next.press(backslash)
        clock += 0.010
        guard case .handled(let result) = router.intercept(keyCode: enter, caps: false, ctrl: false, shift: false,
                                                           option: true) else { return XCTFail("Vikey decides") }
        XCTAssertNotEqual(result?.0, 1, "⌥+Return deletes nothing")
    }

    func testRouterSwitchAndExcludedApp() {
        let router = makeRouter()
        XCTAssertNil(defaults.object(forKey: UndoLearning.strayEnterKey))
        XCTAssertEqual(learning?.strayEnter, true)
        learning?.strayEnter = false
        XCTAssertEqual(defaults.object(forKey: UndoLearning.strayEnterKey) as? Bool, false)
        var field = freshLine(router)
        field.type("xong")
        field.press(backslash)
        clock += 0.040
        field.press(enter)
        XCTAssertEqual(String(field.text), "xong\\\n", "off")
        learning?.strayEnter = true
        bundle = "com.apple.Terminal"
        field = freshLine(router)
        field.type("xong")
        field.press(backslash)
        clock += 0.040
        field.press(enter)
        XCTAssertEqual(String(field.text), "xong\\\n", "Terminal")
    }

    func testGoNhanhUnaffected() {
        let router = makeRouter()
        router.selected = .gonhanh
        for key in [backslash, enter, bracket] {
            guard case .passToGoNhanh = router.intercept(keyCode: key, caps: false, ctrl: false, shift: false) else {
                return XCTFail("Gõ Nhanh decides every key")
            }
        }
    }
}

/// Mac key codes for the letters and punctuation these tests type.
private let routerKeys: [Character: UInt16] = [
    "a": 0, "g": 5, "k": 40, "n": 45, "o": 31, "x": 7, ".": 47, " ": 49,
]

/// A text field fed by `router.intercept`, applying results the way the macOS key handler does: the key itself is
/// typed when the result is nil, or when it is not consumed.
private final class RouterField {
    let router: EngineRouter
    var text: [Character] = []

    init(_ router: EngineRouter) { self.router = router }

    func type(_ keys: String) {
        for ch in keys {
            guard let code = routerKeys[ch] else { XCTFail("no mac key for \(ch)"); continue }
            press(code)
        }
    }

    @discardableResult
    func press(_ keyCode: UInt16, shift: Bool = false) -> InterceptResult {
        let result = router.intercept(keyCode: keyCode, caps: shift, ctrl: false, shift: shift)
        guard case .handled(let edit) = result else { XCTFail("Vikey is the active engine"); return result }
        if let (deleteCount, inserted, consumed) = edit {
            text.removeLast(min(deleteCount, text.count))
            text.append(contentsOf: inserted)
            if consumed { return result }
        }
        if let c = VikeyEngine.typedCharacter(keyCode: keyCode, shift: shift, caps: shift) { text.append(c) }
        return result
    }
}
