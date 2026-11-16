import XCTest
import VikeyShim
@testable import LeanKeysKit

/// Spec 17.1 on the Vikey path: capitalisation when a word is committed, ⌫ undo, and learning names, through
/// `EngineRouter.intercept` with the real engine and memory-only rules and names.

/// Mac virtual key codes, from vendor/vikey/Engine/platforms/mac.h. "⌫" is Backspace, "\n" Return.
private let macKey: [Character: UInt16] = [
    "a": 0, "b": 11, "c": 8, "d": 2, "e": 14, "f": 3, "g": 5, "h": 4, "i": 34, "j": 38, "k": 40, "l": 37, "m": 46,
    "n": 45, "o": 31, "p": 35, "q": 12, "r": 15, "s": 1, "t": 17, "u": 32, "v": 9, "w": 13, "x": 7, "y": 16, "z": 6,
    " ": 49, ",": 43, ".": 47, "⌫": 51, "\n": 36, "/": 44, "-": 27,
]
/// Symbols typed with Shift: Shift+2, Shift+3, Shift+` (US layout).
private let shiftedMacKey: [Character: UInt16] = ["@": 19, "#": 20, "~": 50]

/// A text field fed by `router.intercept`, applying each result the way the macOS key handler does: the key itself
/// is typed when the result is nil, or when it is not consumed (Return and punctuation after an edit).
private final class Field {
    let router: EngineRouter
    var text: [Character] = []

    init(_ router: EngineRouter) { self.router = router }

    /// Types `keys`; an uppercase letter is sent with Shift (caps and shift set, as the macOS key path does).
    @discardableResult
    func type(_ keys: String) -> String {
        for ch in keys {
            guard let code = shiftedMacKey[ch] ?? macKey[Character(ch.lowercased())] else {
                XCTFail("no mac key for \(ch)"); continue
            }
            let upper = ch.isUppercase || shiftedMacKey[ch] != nil
            switch router.intercept(keyCode: code, caps: upper, ctrl: false, shift: upper) {
            case .passToGoNhanh:
                XCTFail("Vikey is the active engine")
            case .handled(let result):
                if let (deleteCount, inserted, consumed) = result {
                    text.removeLast(min(deleteCount, text.count))
                    text.append(contentsOf: inserted)
                    if consumed { continue }
                }
                if ch == "⌫" {
                    if !text.isEmpty { text.removeLast() }
                } else {
                    text.append(ch)
                }
            }
        }
        return String(text)
    }
}

final class AutoCapitalizerTests: XCTestCase {
    private var engine: VikeyEngine!
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var context = LearnContext(bundleID: "com.apple.TextEdit", secureInput: false, secureField: false,
                                       now: Date())
    private var learning: UndoLearning?
    /// The frontmost app the router sees: an ordinary text app unless a test says otherwise (never the real one,
    /// which is the terminal or editor running the tests).
    private var frontmost: String? = "com.apple.TextEdit"

    override func setUp() {
        super.setUp()
        engine = VikeyEngine()
        XCTAssertNotNil(engine, "lk_vikey_init failed")
        suiteName = "AutoCapitalizerTests.\(UUID().uuidString)"
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

    /// A router over the real engine with a memory-only rule book and `names` (memory-only real names by default).
    private func makeRouter(book: UndoRuleBook = UndoRuleBook(store: nil),
                            names: LearnedNames? = nil) -> EngineRouter {
        let made = UndoLearning(book: book, defaults: defaults, context: { [unowned self] in self.context },
                                names: names ?? UndoLearning.memoryNames())
        learning = made
        let engine = self.engine!
        return EngineRouter(defaults: defaults, makeVikey: { engine }, undoLearning: { made },
                            frontmostBundleID: { [unowned self] in self.frontmost })
    }

    /// Names in memory whose dictionary check says no word is a dictionary word: every capital the router hands
    /// over would count "anywhere", so a negative case shows the router held it back.
    private func permissiveNames() -> LearnedNames {
        LearnedNames(store: nil, hmacKey: nil, titles: Set(ProperNounData.bundled.titles), isDictionaryWord: { _ in false })
    }

    /// A fresh line (a click: the router clears) in Vietnamese.
    private func line(_ router: EngineRouter, vietnamese: Bool = true) -> Field {
        router.setEnabled(vietnamese)
        router.clear()
        return Field(router)
    }

    private func settle() {
        learning?.flush()
    }

    func testCapitalisesPlaceAtSpace() {
        let router = makeRouter()
        XCTAssertEqual(line(router).type("tooi owr haf nooij "), "tôi ở Hà Nội ")
    }

    /// Review Focus 2: the replacement lands before the ".", which the key still types.
    func testPunctuationBreak() {
        let router = makeRouter()
        XCTAssertEqual(line(router).type("tooi owr haf nooij."), "tôi ở Hà Nội.")
        XCTAssertEqual(line(router).type("tooi owr haf nooij, "), "tôi ở Hà Nội, ")
        // The edit carries no "." and is not consumed: the key follows it.
        line(router).type("tooi owr haf nooij")
        guard case .handled(let edit?) = router.intercept(keyCode: 47, caps: false, ctrl: false, shift: false) else {
            return XCTFail("expected a capitalisation edit at '.'")
        }
        XCTAssertEqual(edit.0, "hà nội".count)
        XCTAssertEqual(String(edit.1), "Hà Nội")
        XCTAssertFalse(edit.2, "punctuation is typed by the key itself")
    }

    /// Review Focus 1: when Vikey fixes the word at the break key, LeanKeys does not capitalise at that key, so
    /// Vikey's own ⌫⌫ undo still finds its word.
    func testNoCapitaliseAfterVikeyFix() {
        let router = makeRouter()
        // Control: in Vietnamese, Telex types "nguyễn" key by key and the sure surname is capitalised.
        XCTAssertEqual(line(router).type("nguyeenx "), "Nguyễn ")
        // In English, Vikey switches the word itself at Space (deleteCount > 0): no capital at that key.
        let field = line(router, vietnamese: false)
        XCTAssertEqual(field.type("nguyeenx"), "nguyeenx")
        guard case .handled(let fix?) = router.intercept(keyCode: 49, caps: false, ctrl: false, shift: false) else {
            return XCTFail("expected Vikey's fix at Space")
        }
        XCTAssertGreaterThan(fix.0, 0, "Vikey fixed the word (precondition)")
        XCTAssertEqual(String(fix.1), "nguyễn ")
        XCTAssertEqual(line(router, vietnamese: false).type("nguyeenx "), "nguyễn ")
        XCTAssertEqual(line(router, vietnamese: false).type("nguyeenx ⌫⌫"), "nguyeenx", "Vikey's ⌫⌫ undo")
    }

    func testBackspaceUndoes() {
        let book = UndoRuleBook(store: nil)
        let router = makeRouter(book: book)
        XCTAssertEqual(line(router).type("tooi owr haf nooij ⌫"), "tôi ở hà nội")
        settle()
        XCTAssertEqual(book.rules.map { [$0.previous, $0.text] }, [["ở", "cap:hà nội"]])
        // The context rule holds after one undo; elsewhere a contextless rule needs two.
        XCTAssertEqual(line(router).type("tooi owr haf nooij "), "tôi ở hà nội ")
        XCTAssertEqual(line(router).type("ddeens haf nooij "), "đến Hà Nội ")
        // Undo at punctuation: the "." goes, the words come back.
        XCTAssertEqual(line(router).type("ddeens haf nooij.⌫"), "đến hà nội")
        // The text after the undo stays in step with Vikey: a tone key edits the restored word.
        XCTAssertEqual(line(router).type("chuyeens bay ra haf nooij ⌫s"), "chuyến bay ra hà nối")
    }

    /// The words ⌫ gave back stay as typed when finished unchanged, with or without a word before them, even
    /// where the rule book would not keep them yet; editing them, or the next occurrence, is judged normally.
    func testUndoneWordsStayAtNextBreak() {
        let book = UndoRuleBook(store: nil)
        let router = makeRouter(book: book)
        XCTAssertEqual(line(router).type("nguyeenx ⌫ "), "nguyễn ", "no previous word: no rule after one undo")
        XCTAssertEqual(line(router).type("nguyeenx ⌫."), "nguyễn.")
        XCTAssertEqual(line(router).type("tooi o haf nooij ⌫ "), "tôi o hà nội ")
        XCTAssertEqual(line(router).type("tooi o haf nooij ⌫ ddi "), "tôi o hà nội đi ", "the break ends it")
        // Edited after the undo: judged again (no rule keeps "huỳnh" after one contextless undo).
        XCTAssertEqual(line(router).type("huyfnh ⌫a⌫ "), "Huỳnh ")
        // The next occurrence after one contextless undo (a rule needs two) is capitalised again.
        let fresh = makeRouter()
        XCTAssertEqual(line(fresh).type("nguyeenx ⌫ "), "nguyễn ")
        settle()
        XCTAssertEqual(line(fresh).type("nguyeenx "), "Nguyễn ")
    }

    /// Only the very next key undoes, and not after the cursor moved or after Return.
    func testOnlyTheNextBackspaceUndoes() {
        let router = makeRouter()
        XCTAssertEqual(line(router).type("tooi owr haf nooij a⌫"), "tôi ở Hà Nội ")
        let field = line(router)
        field.type("tooi owr haf nooij ")
        router.clear()  // a click
        guard case .handled(let afterClick) = router.intercept(keyCode: 51, caps: false, ctrl: false, shift: false)
        else { return XCTFail("Vikey is the active engine") }
        XCTAssertNil(afterClick, "a plain ⌫ after a click")
        XCTAssertEqual(line(router).type("tooi owr haf nooij\n"), "tôi ở Hà Nội\n", "capitalised before Return")
        XCTAssertEqual(line(router).type("tooi owr haf nooij\n⌫"), "tôi ở Hà Nội", "⌫ after Return is a plain ⌫")
    }

    func testNameChain() {
        let router = makeRouter()
        XCTAssertEqual(line(router).type("nguyeenx vawn an "), "Nguyễn Văn An ")
        XCTAssertEqual(line(router).type("nguyeenx ddi chowj "), "Nguyễn đi chợ ")
    }

    /// Review Focus 4, spec 17.1.3: only words the user typed with a capital, mid-phrase, are learned.
    func testLearnsFromUserCapitalsOnly() {
        // The real dictionary: "Hùng" is a word, so it is learned after a title only.
        let names = UndoLearning.memoryNames()
        let router = makeRouter(names: names)
        XCTAssertEqual(line(router).type("anh hufng "), "anh hùng ", "not learned yet")
        XCTAssertEqual(line(router).type("anh Hufng "), "anh Hùng ")
        XCTAssertEqual(line(router).type("anh Hufng "), "anh Hùng ")
        XCTAssertEqual(names.names.map(\.form), ["Hùng"])
        XCTAssertEqual(line(router).type("anh hufng "), "anh Hùng ")
        XCTAssertEqual(line(router).type("ddi hufng "), "đi hùng ", "after a title only")

        // A dictionary that knows no word: any capital handed to the names would be learned, so these negatives
        // show the router held it back.
        let open = permissiveNames()
        let strict = makeRouter(names: open)
        strict.setShortcuts([("hnn", "Hà Nội")])
        XCTAssertEqual(line(strict).type("tooi owr haf nooij "), "tôi ở Hà Nội ")
        XCTAssertEqual(line(strict).type("tooi owr haf nooij "), "tôi ở Hà Nội ")
        XCTAssertEqual(line(strict).type("ddi hnn "), "đi Hà Nội ")
        XCTAssertEqual(line(strict).type("ddi hnn "), "đi Hà Nội ")
        // A word LeanKeys capitalised, committed again after ⌫ moved back into it.
        XCTAssertEqual(line(strict).type("tooi owr haf nooij a⌫⌫ "), "tôi ở Hà Nội ")
        XCTAssertEqual(line(strict).type("tooi owr haf nooij a⌫⌫ "), "tôi ở Hà Nội ")
        // Each negative has its own word, typed twice (the threshold), so one slip would show.
        XCTAssertEqual(line(strict).type("Tiki "), "Tiki ")
        XCTAssertEqual(line(strict).type("xong. Tiki "), "xong. Tiki ", "phrase start after '. '")
        XCTAssertEqual(line(strict).type("xong.Lazada "), "xong.Lazada ", "glued to punctuation")
        XCTAssertEqual(line(strict).type("xong.Lazada "), "xong.Lazada ")
        XCTAssertTrue(open.names.isEmpty, "LeanKeys' capitals, gõ tắt, phrase start, glued: nothing learned")
        // Excluded: a password field.
        context = LearnContext(bundleID: "com.apple.TextEdit", secureInput: false, secureField: true, now: Date())
        line(strict).type("mua Kiki ")
        line(strict).type("mua Kiki ")
        XCTAssertTrue(open.names.isEmpty, "nothing learned in a password field")
        // Control: the same word mid-phrase in an ordinary field is learned.
        context = LearnContext(bundleID: "com.apple.TextEdit", secureInput: false, secureField: false, now: Date())
        line(strict).type("mua Tiki ")
        line(strict).type("mua Tiki ")
        XCTAssertEqual(open.names.map(\.form), ["Tiki"])
        XCTAssertEqual(line(strict).type("ddi tiki "), "đi Tiki ")
    }

    /// Spec 17.1.4: a learned name undone twice anywhere is removed.
    func testUndoingLearnedNameTwiceRemovesIt() {
        let names = permissiveNames()
        let router = makeRouter(names: names)
        line(router).type("mua Tiki ")
        line(router).type("mua Tiki ")
        XCTAssertEqual(line(router).type("mua tiki ⌫"), "mua tiki")
        XCTAssertEqual(names.names.map(\.form), ["Tiki"])
        XCTAssertEqual(line(router).type("ddi tiki ⌫"), "đi tiki")
        XCTAssertTrue(names.names.isEmpty)
        XCTAssertEqual(line(router).type("veef tiki "), "về tiki ")
    }

    /// Ruling R12: terminals and code editors get no capitals (a command or identifier is case-sensitive).
    func testNoCapitalisationInCodeApps() {
        let names = permissiveNames()
        let router = makeRouter(names: names)
        line(router).type("mua Tiki ")
        line(router).type("mua Tiki ")
        for app in ["com.apple.Terminal", "com.microsoft.VSCode", "co.zeit.hyper", "com.jetbrains.intellij"] {
            frontmost = app
            XCTAssertEqual(line(router).type("tooi owr haf nooij "), "tôi ở hà nội ", app)
            XCTAssertEqual(line(router).type("mua tiki\n"), "mua tiki\n", app)
        }
        frontmost = "com.apple.TextEdit"
        XCTAssertEqual(line(router).type("tooi owr haf nooij "), "tôi ở Hà Nội ")
        XCTAssertEqual(line(router).type("mua tiki "), "mua Tiki ")
    }

    /// Ruling R13: a word glued to a symbol (an address, a path, a tag) is never capitalised, not even a learned name.
    func testGluedWordsStayAsTyped() {
        let router = makeRouter(names: permissiveNames())
        line(router).type("mua Tiki ")
        line(router).type("mua Tiki ")
        XCTAssertEqual(line(router).type("mua tiki "), "mua Tiki ", "control: the name is learned")
        XCTAssertEqual(line(router).type("an@tiki.vn "), "an@tiki.vn ")
        XCTAssertEqual(line(router).type("cd ~/tiki/ "), "cd ~/tiki/ ")
        XCTAssertEqual(line(router).type("xem #tiki "), "xem #tiki ")
        XCTAssertEqual(line(router).type("xem @tiki "), "xem @tiki ")
        XCTAssertEqual(line(router).type("ten-tiki "), "ten-tiki ")
    }

    func testSwitchOff() {
        let names = permissiveNames()
        let router = makeRouter(names: names)
        learning?.autoCapitalize = false
        XCTAssertEqual(defaults.object(forKey: UndoLearning.autoCapitalizeKey) as? Bool, false)
        XCTAssertEqual(line(router).type("tooi owr haf nooij "), "tôi ở hà nội ")
        line(router).type("mua Tiki ")
        line(router).type("mua Tiki ")
        XCTAssertTrue(names.names.isEmpty, "off: no learning either")
        learning?.autoCapitalize = true
        XCTAssertEqual(line(router).type("tooi owr haf nooij "), "tôi ở Hà Nội ")
    }

    func testSwitchDefaultsOn() {
        _ = makeRouter()
        XCTAssertNil(defaults.object(forKey: UndoLearning.autoCapitalizeKey))
        XCTAssertEqual(learning?.autoCapitalize, true)
    }

    func testGoNhanhUnaffected() {
        let router = makeRouter()
        router.selected = .gonhanh
        for key: UInt16 in [4, 0, 3, 49, 51] {
            guard case .passToGoNhanh = router.intercept(keyCode: key, caps: false, ctrl: false, shift: false) else {
                return XCTFail("Gõ Nhanh decides every key")
            }
        }
    }
}
