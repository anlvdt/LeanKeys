import XCTest
@testable import LeanKeysKit

/// Mac virtual key codes, from vendor/vikey/Engine/platforms/mac.h.
private let macKey: [Character: UInt16] = [
    "a": 0, "b": 11, "c": 8, "d": 2, "e": 14, "f": 3, "g": 5, "h": 4, "i": 34, "j": 38, "k": 40, "l": 37, "m": 46,
    "n": 45, "o": 31, "p": 35, "q": 12, "r": 15, "s": 1, "t": 17, "u": 32, "v": 9, "w": 13, "x": 7, "y": 16, "z": 6,
    " ": 49, ",": 43, ".": 47,
]
private let kBackspace: UInt16 = 51
private let kLeftArrow: UInt16 = 123

/// A text field driven by the engine: apply deleteCount then append text; nil lets the key do its own thing.
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

    func testUndoTwoBackspaces() {
        engine.setVietnamese(false)
        engine.resetContext()
        let field = Field(engine)
        XCTAssertEqual(field.type("dduowcj "), "được ")
        XCTAssertEqual(field.backspace(), "được")
        XCTAssertEqual(field.backspace(), "dduowcj")
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

    func testCapsLockXorShiftForLetters() {
        // Ruling R3: for letters Vikey's shift is shift XOR caps. "dd" with Caps Lock is "Đ"; with Caps Lock and Shift, "đ".
        let d = macKey["d"]!
        _ = engine.process(keyCode: d, caps: true, shift: false)
        XCTAssertEqual(engine.process(keyCode: d, caps: true, shift: false)?.text, ["Đ"])
        engine.resetContext()
        _ = engine.process(keyCode: d, caps: true, shift: true)
        XCTAssertEqual(engine.process(keyCode: d, caps: true, shift: true)?.text, ["đ"])
    }
}
