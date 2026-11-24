import XCTest
import VikeyShim
@testable import LeanKeysKit

/// Mac virtual key codes, from vendor/vikey/Engine/platforms/mac.h.
private let macKey: [Character: UInt16] = [
    "a": 0, "b": 11, "c": 8, "d": 2, "e": 14, "f": 3, "g": 5, "h": 4, "i": 34, "j": 38, "k": 40, "l": 37, "m": 46,
    "n": 45, "o": 31, "p": 35, "q": 12, "r": 15, "s": 1, "t": 17, "u": 32, "v": 9, "w": 13, "x": 7, "y": 16, "z": 6,
    " ": 49, ",": 43, ".": 47, "\n": 36,
]
private let kBackspace: UInt16 = 51
private let kLeftArrow: UInt16 = 123
private let kReturn: UInt16 = 36
private let kComma: UInt16 = 43
private let kSpace: UInt16 = 49

/// A text field driven by the engine: apply deleteCount then append text; nil lets the key do its own thing,
/// and so does an edit with keyPassesThrough, after the edit.
private final class Field {
    let engine: TypingEngine
    var text: [Character] = []
    var languageChanges = 0

    init(_ engine: TypingEngine) { self.engine = engine }

    @discardableResult
    func type(_ keys: String) -> String {
        for ch in keys {
            let lower = Character(ch.lowercased())
            guard let code = macKey[lower] else { XCTFail("no mac key for \(ch)"); continue }
            press(code, shift: ch.isUppercase, own: ch)
        }
        return String(text)
    }

    @discardableResult
    func backspace() -> String {
        press(kBackspace, shift: false, own: nil)
        return String(text)
    }

    /// Returns the engine's answer for the key.
    @discardableResult
    func press(_ code: UInt16, shift: Bool, own: Character?) -> EngineEdit? {
        let edit = engine.process(keyCode: code, caps: false, shift: shift)
        if let edit {
            text.removeLast(min(edit.deleteCount, text.count))
            text.append(contentsOf: edit.text)
            if edit.keyPassesThrough, let own { text.append(own) }
            if edit.languageChanged { languageChanges += 1 }
        } else if code == kBackspace {
            if !text.isEmpty { text.removeLast() }
        } else if let own {
            text.append(own)
        }
        return edit
    }
}

final class VikeyEngineTests: XCTestCase {
    private var engine: VikeyEngine!

    override func setUp() {
        super.setUp()
        engine = VikeyEngine()
        XCTAssertNotNil(engine, "lk_vikey_init failed")
        // One Vikey engine per process: every test starts from a known state.
        engine.setVietnamese(true)
        engine.resetContext()
    }

    override func tearDown() {
        // Options are process-wide: put back the defaults for the next test.
        engine?.setAutoSwitch(true)
        engine?.setModernTone(true)
        // A router on the real engine installs its (memory-only) undo learner's fix filter: unregister it.
        lk_vikey_set_fix_filter(nil)
        engine?.setVietnamese(true)
        engine?.resetContext()
        super.tearDown()
    }

    /// Control for the test below: English with auto switch on turns a Vietnamese word back on.
    func testEnglishWithAutoSwitchFlipsBackOnAVietnameseWord() {
        engine.setVietnamese(false)
        engine.resetContext()
        XCTAssertEqual(Field(engine).type("vieejt "), "việt ")
        XCTAssertTrue(engine.isVietnamese)
    }

    /// Ruling R25: an off that is not the user's (the echo of an automatic switch, a replay) keeps auto switch.
    func testNonExplicitOffThroughRouterStillSwitchesBack() {
        let suite = "VikeyEngineTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let engine = self.engine!
        let router = EngineRouter(defaults: defaults, makeVikey: { engine },
                                  undoLearning: { UndoLearning(book: UndoRuleBook(store: nil), defaults: defaults,
                                                               context: { LearnContext(bundleID: nil, secureInput: true, secureField: true, now: Date()) }) })
        router.setEnabled(false)
        engine.resetContext()
        XCTAssertEqual(Field(engine).type("vieejt "), "việt ")
        XCTAssertTrue(engine.isVietnamese)
    }

    /// The router asks the field before Return, only when a word is pending, and passes the answer to the engine.
    private func typeThroughRouter(_ keys: String, fieldAllows: Bool,
                                   app: String? = "com.tinyspeck.slackmacgap") -> (text: String, asked: Int) {
        let suite = "VikeyEngineTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let engine = self.engine!
        var asked = 0
        let router = EngineRouter(defaults: defaults, makeVikey: { engine },
                                  undoLearning: { UndoLearning(book: UndoRuleBook(store: nil), defaults: defaults,
                                                               context: { LearnContext(bundleID: nil, secureInput: true, secureField: true, now: Date()) }) },
                                  frontmostBundleID: { app },
                                  fieldAllowsFixAtReturn: { asked += 1; return fieldAllows })
        router.setEnabled(false)
        engine.resetContext()
        var text: [Character] = []
        for ch in keys {
            guard let code = macKey[ch], case .handled(let r) = router.intercept(keyCode: code, caps: false, ctrl: false,
                                                                                    shift: false) else {
                XCTFail("Vikey must handle \(ch)"); continue
            }
            if let (deleteCount, inserted, consumed) = r {
                text.removeLast(min(deleteCount, text.count))
                text += inserted
                if !consumed { text.append(ch) }
            } else {
                text.append(ch)
            }
        }
        return (String(text), asked)
    }

    func testRouterLetsReturnFixTheWordWhereTheFieldAllows() {
        let r = typeThroughRouter("dduowcj\n", fieldAllows: true)
        XCTAssertEqual(r.text, "được\n")
        XCTAssertEqual(r.asked, 1)
        XCTAssertTrue(engine.isVietnamese)
    }

    func testRouterKeepsD62WhereTheFieldDoesNotAllow() {
        let r = typeThroughRouter("dduowcj\n", fieldAllows: false)
        XCTAssertEqual(r.text, "dduowcj\n")
        XCTAssertFalse(engine.isVietnamese)
    }

    /// Code editors and terminals keep D62: Return there accepts a completion from a popup list (as ruling R12).
    func testRouterKeepsD62InCodeApps() {
        let r = typeThroughRouter("dduowcj\n", fieldAllows: true, app: "com.microsoft.VSCode")
        XCTAssertEqual(r.text, "dduowcj\n")
        XCTAssertEqual(r.asked, 0, "the field is not even asked")
    }

    func testRouterAsksTheFieldOnlyAtReturnAfterAWord() {
        XCTAssertEqual(typeThroughRouter("merge \n", fieldAllows: true).asked, 0, "no word pending at Return")
    }

    /// Ruling R25: the user's explicit off (through the router) stays off.
    func testExplicitOffThroughRouterStaysEnglish() {
        let suite = "VikeyEngineTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let engine = self.engine!
        let router = EngineRouter(defaults: defaults, makeVikey: { engine },
                                  undoLearning: { UndoLearning(book: UndoRuleBook(store: nil), defaults: defaults,
                                                               context: { LearnContext(bundleID: nil, secureInput: true, secureField: true, now: Date()) }) })
        router.setEnabled(false, explicit: true)
        engine.resetContext()
        XCTAssertEqual(Field(engine).type("vieejt "), "vieejt ")
        XCTAssertFalse(engine.isVietnamese)
    }

    func testTelexBasic() {
        XCTAssertEqual(Field(engine).type("vieejt "), "việt ")
        engine.resetContext()
        XCTAssertEqual(Field(engine).type("truowfng "), "trường ")
    }

    func testAutoSwitchToVietnameseFromEnglish() {
        engine.setVietnamese(false)
        engine.resetContext()
        XCTAssertFalse(engine.isVietnamese)
        XCTAssertEqual(Field(engine).type("treen "), "trên ")
        XCTAssertTrue(engine.isVietnamese)
    }

    func testEnglishStaysEnglish() {
        XCTAssertEqual(Field(engine).type("more "), "more ")
    }

    /// Vikey D61: Backspace twice right after a switch back to Vietnamese gives the keys back, when they are an English
    /// word ("cos" is English, "có" Vietnamese).
    func testUndoTwoBackspaces() {
        engine.setVietnamese(false)
        engine.resetContext()
        let field = Field(engine)
        XCTAssertEqual(field.type("cos "), "có ")
        XCTAssertEqual(field.backspace(), "có")
        XCTAssertEqual(field.backspace(), "cos")
        XCTAssertFalse(engine.isVietnamese)
    }

    /// Keys that are no English word ("dduowcj", "vieejt") had only the Vietnamese reading: after the switch back,
    /// Backspace just deletes, and Vietnamese stays (a user fixing the word's last letter is not sent back to English).
    func testBackspaceAfterSwitchBackDeletesWhenKeysAreNoEnglishWord() {
        engine.setVietnamese(false)
        engine.resetContext()
        let field = Field(engine)
        XCTAssertEqual(field.type("vieejt "), "việt ")
        XCTAssertEqual(field.backspace(), "việt")
        XCTAssertEqual(field.backspace(), "việ")
        XCTAssertTrue(engine.isVietnamese)
        XCTAssertEqual(field.type("c "), "việc ")
    }

    func testBackspaceAfterSwitchBackDeletesForAnotherNonEnglishWord() {
        engine.setVietnamese(false)
        engine.resetContext()
        let field = Field(engine)
        XCTAssertEqual(field.type("dduowcj "), "được ")
        XCTAssertEqual(field.backspace(), "được")
        XCTAssertEqual(field.backspace(), "đượ")
        XCTAssertTrue(engine.isVietnamese)
    }

    func testNavigationKeyResetsContext() {
        // What "ej" types as a word of its own.
        let fresh = Field(engine).type("ej")
        engine.resetContext()

        let field = Field(engine)
        XCTAssertEqual(field.type("vie"), "vie")
        XCTAssertNil(field.press(kLeftArrow, shift: false, own: nil))
        XCTAssertEqual(field.type("ej"), "vie" + fresh)
    }

    func testLanguageChangedFlag() {
        engine.setVietnamese(false)
        engine.resetContext()
        let field = Field(engine)
        field.type("treen ")
        XCTAssertEqual(field.languageChanges, 1)
    }

    func testPlainBackspacePassesThrough() {
        // Ruling R9: a Backspace whose edit is just "delete one" is the key's native effect, so it goes through.
        let field = Field(engine)
        XCTAssertEqual(field.type("vieejt"), "việt")
        XCTAssertNil(engine.process(keyCode: kBackspace, caps: false, shift: false), "Vietnamese mode")

        engine.setVietnamese(false)
        engine.resetContext()
        XCTAssertEqual(Field(engine).type("more"), "more")
        XCTAssertNil(engine.process(keyCode: kBackspace, caps: false, shift: false), "English mode")
    }

    func testShiftedCapitalsSurviveTelex() {
        // The macOS key path passes caps = Shift || Caps Lock (RustBridge.swift "let caps = shift || …").
        // Holding Shift for "DDaif Loan" must give "Đài Loan", not "đài Loan".
        func press(_ ch: Character) -> EngineEdit? {
            let upper = ch.isUppercase
            return engine.process(keyCode: macKey[Character(ch.lowercased())]!, caps: upper, shift: upper)
        }
        var text: [Character] = []
        for ch in "DDaif Loan " {
            if let e = press(ch) {
                text.removeLast(min(e.deleteCount, text.count)); text += e.text
                if e.keyPassesThrough { text.append(ch) }
            } else { text.append(ch) }
        }
        XCTAssertEqual(String(text), "Đài Loan ")
    }

    func testCapsLockAloneGivesCapitals() {
        // Caps Lock without Shift: caps = true, shift = false. Letters are upper case.
        let d = macKey["d"]!
        _ = engine.process(keyCode: d, caps: true, shift: false)
        XCTAssertEqual(engine.process(keyCode: d, caps: true, shift: false)?.text, ["Đ"])
    }

    func testCapsLockWithShiftGivesCapitals() {
        // macOS does not invert Caps Lock with Shift: both held still types capitals.
        let d = macKey["d"]!
        _ = engine.process(keyCode: d, caps: true, shift: true)
        XCTAssertEqual(engine.process(keyCode: d, caps: true, shift: true)?.text, ["Đ"])
    }

    // Ruling R12: after Vikey fixes a word, a break key is typed by the key itself, not injected as text.

    /// Vikey D62 (v1.0.34): Return sends what is on screen. It ends the word but never fixes it, so the transformed
    /// word goes out as shown and Return is typed by the key itself.
    func testReturnSendsWhatIsOnScreen() {
        let field = Field(engine)
        let typed = field.type("test")
        XCTAssertNotEqual(typed, "test", "precondition: Telex transforms the word")
        XCTAssertNil(field.press(kReturn, shift: false, own: "\n"), "no fix at Return")
        XCTAssertEqual(String(field.text), typed + "\n")
    }

    // Vikey D19: a doubled tone key switches to English mid-word and shows the Telex result ("lamff" -> "lamf").

    /// A Vietnamese typo with a doubled tone key keeps D19's Telex result, but the word that comes out is no English
    /// word, so Vietnamese comes back at the end of the word: the next words are not typed in English.
    func testDoubledToneKeyInVietnameseWordComesBackAtWordEnd() {
        for (keys, shown) in [("lamff ", "lamf "), ("nguowiff ", "nguowif "), ("bijj ", "bij "), ("dduowcjj ", "dduowcj ")] {
            engine.setVietnamese(true)
            engine.resetContext()
            let field = Field(engine)
            XCTAssertEqual(field.type(keys), shown, keys)
            XCTAssertTrue(engine.isVietnamese, "Vietnamese after \(keys)")
            XCTAssertEqual(field.type("tooi "), shown + "tôi ")
        }
    }

    /// Bringing Vietnamese back leaves Vikey's own Backspace alone: the first ⌫ takes the break and the word goes on.
    func testDoubledKeyComebackLeavesBackspaceAlone() {
        let field = Field(engine)
        field.type("lamff ")
        XCTAssertTrue(engine.isVietnamese)
        XCTAssertEqual(field.backspace(), "lamf")
    }

    /// The app echoes each switch of Vikey's back to it (MenuBar's language-sync → router.setEnabled → setVietnamese,
    /// asynchronously, with the language Vikey already has). That echo must not wipe what the shim tracks about the
    /// word: Vietnamese still comes back at the end of "lamff".
    func testDoubledKeyComebackSurvivesTheAppsEcho() {
        let field = Field(engine)
        field.type("lamff")
        XCTAssertFalse(engine.isVietnamese, "precondition: D19 switched to English mid-word")
        engine.setVietnamese(false)   // the echo
        XCTAssertEqual(field.type(" "), "lamf ")
        XCTAssertTrue(engine.isVietnamese)
    }

    /// A word ended by Return (a one-word message) brings Vietnamese back too, even where Return may not fix the
    /// word (an address bar keeps D62): the newline Return typed is no word of its own.
    func testDoubledToneKeyComesBackAtReturn() {
        let field = Field(engine)
        field.type("lamff")
        XCTAssertFalse(engine.isVietnamese, "precondition: D19 switched to English mid-word")
        field.press(kReturn, shift: false, own: "\n")
        XCTAssertEqual(String(field.text), "lamf\n")
        XCTAssertTrue(engine.isVietnamese)
    }

    /// A word that is English but far more common as Vietnamese ("cos" / "có", "nos" / "nó", "ver" / "vẻ": 30 times
    /// or more in Vikey's dictionaries) brings Vietnamese back too. The screen stays as D19 shows it.
    func testDoubledKeyCollisionWithCommonVietnameseComesBack() {
        for (keys, shown) in [("coss ", "cos "), ("noss ", "nos "), ("verr ", "ver ")] {
            engine.setVietnamese(true)
            engine.resetContext()
            XCTAssertEqual(Field(engine).type(keys), shown, keys)
            XCTAssertTrue(engine.isVietnamese, "Vietnamese after \(keys)")
        }
    }

    /// The language change reaches the app (menu bar icon) at the key that brings Vietnamese back.
    func testDoubledToneKeyComebackReportsLanguageChange() {
        let field = Field(engine)
        field.type("lamff")
        XCTAssertFalse(engine.isVietnamese, "precondition: D19 switched to English mid-word")
        let changesBefore = field.languageChanges
        field.type(" ")
        XCTAssertEqual(field.languageChanges, changesBefore + 1)
    }

    /// An English word made by the doubled key stays English (D19) when it has no Vietnamese reading ("boss") or its
    /// English reading is as common ("its" / "ít", "mix" / "mĩ").
    func testDoubledKeyEnglishWordStaysEnglish() {
        for (keys, shown) in [("boss ", "boss "), ("itss ", "its "), ("mixx ", "mix ")] {
            engine.setVietnamese(true)
            engine.resetContext()
            XCTAssertEqual(Field(engine).type(keys), shown, keys)
            XCTAssertFalse(engine.isVietnamese, "English after \(keys)")
        }
    }

    /// D62 by default in English mode too: a one-word reply is sent as typed and English stays.
    func testReturnInEnglishSendsKeysByDefault() {
        engine.setVietnamese(false)
        engine.resetContext()
        let field = Field(engine)
        field.type("dduowcj")
        field.press(kReturn, shift: false, own: "\n")
        XCTAssertEqual(String(field.text), "dduowcj\n")
        XCTAssertFalse(engine.isVietnamese)
    }

    /// Where the app allows it (a multi-line field without a selection), Return finishes the word as Space does:
    /// "dduowcj" + Return sends "được" and Vietnamese comes back. Return is typed by the key itself.
    func testReturnFixesWordInEnglishWhenAllowed() {
        engine.setVietnamese(false)
        engine.resetContext()
        let field = Field(engine)
        field.type("dduowcj")
        engine.fixWordAtReturn = true
        let edit = field.press(kReturn, shift: false, own: "\n")
        XCTAssertEqual(String(field.text), "được\n")
        XCTAssertEqual(edit?.keyPassesThrough, true, "Return still submits")
        XCTAssertEqual(edit?.languageChanged, true)
        XCTAssertTrue(engine.isVietnamese)
        XCTAssertFalse(engine.fixWordAtReturn, "the permission is for one Return only")
    }

    /// The other direction: an English word typed in Vietnamese mode gets its keys back at Return ("púh" -> "push").
    func testReturnRestoresEnglishWordInVietnameseWhenAllowed() {
        let field = Field(engine)
        XCTAssertNotEqual(field.type("test"), "test", "precondition: Telex transforms the word")
        engine.fixWordAtReturn = true
        field.press(kReturn, shift: false, own: "\n")
        XCTAssertEqual(String(field.text), "test\n")
    }

    /// A word Return has nothing to fix in: exactly the word and Return, no stray space.
    func testReturnWhenAllowedLeavesPlainWordsAlone() {
        let field = Field(engine)
        field.type("vieejt")
        engine.fixWordAtReturn = true
        field.press(kReturn, shift: false, own: "\n")
        XCTAssertEqual(String(field.text), "việt\n")

        engine.setVietnamese(false)
        engine.resetContext()
        let english = Field(engine)
        english.type("merge")
        engine.fixWordAtReturn = true
        english.press(kReturn, shift: false, own: "\n")
        XCTAssertEqual(String(english.text), "merge\n")
        XCTAssertFalse(engine.isVietnamese)
    }

    /// After Return the next message starts fresh: a later Return without permission is D62 again.
    func testReturnPermissionIsForOneReturn() {
        engine.setVietnamese(false)
        engine.resetContext()
        let field = Field(engine)
        field.type("dduowcj")
        engine.fixWordAtReturn = true
        field.press(kReturn, shift: false, own: "\n")
        XCTAssertTrue(engine.isVietnamese, "precondition: the first Return switched back")
        let shown = String(field.type("test").dropFirst("được\n".count))
        XCTAssertNotEqual(shown, "test", "precondition: Telex transforms the word")
        field.press(kReturn, shift: false, own: "\n")
        XCTAssertEqual(String(field.text), "được\n" + shown + "\n", "no fix at this Return")
    }

    /// A Space before Return still lets Vikey restore the word, and Return then goes through as typed.
    func testSpaceThenReturnStillRestores() {
        let field = Field(engine)
        XCTAssertNotEqual(field.type("test"), "test", "precondition: Telex transforms the word")
        _ = field.press(kSpace, shift: false, own: " ")
        XCTAssertNil(field.press(kReturn, shift: false, own: "\n"))
        XCTAssertEqual(String(field.text), "test \n")
    }

    func testCommaAfterRestoreLetsKeyThrough() {
        let field = Field(engine)
        XCTAssertNotEqual(field.type("test"), "test", "precondition: Telex transforms the word")
        let edit = field.press(kComma, shift: false, own: ",")
        XCTAssertNotNil(edit, "Vikey restores the word on a comma")
        XCTAssertEqual(edit?.keyPassesThrough, true)
        XCTAssertFalse(edit?.text.contains(",") ?? true)
        XCTAssertEqual(String(field.text), "test,", "comma appears once")
    }

    func testSpaceKeepsCharacter() {
        let field = Field(engine)
        XCTAssertNotEqual(field.type("test"), "test", "precondition: Telex transforms the word")
        let edit = field.press(kSpace, shift: false, own: " ")
        XCTAssertNotNil(edit, "Vikey restores the word on Space")
        XCTAssertEqual(edit?.keyPassesThrough, false)
        XCTAssertEqual(edit?.text.last, " ")
        XCTAssertEqual(String(field.text), "test ")
    }
}
