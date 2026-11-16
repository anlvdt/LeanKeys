import XCTest
@testable import LeanKeysKit

/// Mac virtual key codes, from vendor/vikey/Engine/platforms/mac.h.
private let macKey: [Character: UInt16] = [
    "a": 0, "b": 11, "c": 8, "d": 2, "e": 14, "f": 3, "g": 5, "h": 4, "i": 34, "j": 38, "k": 40, "l": 37, "m": 46,
    "n": 45, "o": 31, "p": 35, "q": 12, "r": 15, "s": 1, "t": 17, "u": 32, "v": 9, "w": 13, "x": 7, "y": 16, "z": 6,
    " ": 49, ",": 43, ".": 47,
]
private let kBackspace: UInt16 = 51

/// A text field driven by the engine, like the one in VikeyEngineTests. "⌫" is Backspace. Letters pass
/// caps = shift, as the macOS key path does (caps = Shift or Caps Lock).
private final class Field {
    let engine: TypingEngine
    var text: [Character] = []

    init(_ engine: TypingEngine) { self.engine = engine }

    @discardableResult
    func type(_ keys: String) -> String {
        for ch in keys {
            if ch == "⌫" {
                press(kBackspace, shift: false, own: nil)
                continue
            }
            guard let code = macKey[Character(ch.lowercased())] else { XCTFail("no mac key for \(ch)"); continue }
            press(code, shift: ch.isUppercase, own: ch)
        }
        return String(text)
    }

    private func press(_ code: UInt16, shift: Bool, own: Character?) {
        if let edit = engine.process(keyCode: code, caps: shift, shift: shift) {
            text.removeLast(min(edit.deleteCount, text.count))
            text.append(contentsOf: edit.text)
            if edit.keyPassesThrough, let own { text.append(own) }
        } else if code == kBackspace {
            if !text.isEmpty { text.removeLast() }
        } else if let own {
            text.append(own)
        }
    }
}

final class DoubleKeyFixTests: XCTestCase {
    private var engine: VikeyEngine!

    override func setUp() {
        super.setUp()
        engine = VikeyEngine()
        XCTAssertNotNil(engine, "lk_vikey_init failed")
        VikeyEngine.setDoubleKeyFix(true)
        engine.setVietnamese(true)
        engine.resetContext()
    }

    override func tearDown() {
        VikeyEngine.setDoubleKeyFix(true)
        engine?.setVietnamese(true)
        engine?.resetContext()
        super.tearDown()
    }

    /// Types `keys` into a fresh field, starting in Vietnamese.
    private func typed(_ keys: String) -> String {
        engine.setVietnamese(true)
        engine.resetContext()
        return Field(engine).type(keys)
    }

    func testToneDoubledThenBackspace() {
        XCTAssertEqual(typed("hocjj⌫"), "học")
        XCTAssertEqual(typed("tieengss⌫"), "tiếng")
        XCTAssertEqual(typed("ddaxx⌫"), "đã")
    }

    func testPlainLettersDoubled() {
        XCTAssertEqual(typed("quaa⌫"), "qua")
    }

    func testLanguageStaysVietnamese() {
        engine.setVietnamese(true)
        engine.resetContext()
        let field = Field(engine)
        XCTAssertEqual(field.type("hocjj⌫"), "học")
        XCTAssertTrue(engine.isVietnamese)
        XCTAssertEqual(field.type(" ddi"), "học đi")
    }

    func testEnglishWordWins() {
        XCTAssertEqual(typed("userr⌫"), "use")
        XCTAssertEqual(typed("coss⌫"), "có")
        XCTAssertEqual(typed("carr⌫"), "cả")
    }

    func testCapitals() {
        XCTAssertEqual(typed("Hocjj⌫"), "Học")
        XCTAssertEqual(typed("HOCJJ⌫"), "HỌC")
    }

    /// The engine is rebuilt in capitals too: a tone key after the repair keeps the word all caps, as when the word
    /// is typed straight ("HÕC" is not a word, so S: "HỌC" + S = "HÓC").
    func testCapitalsStayAfterRepair() {
        XCTAssertEqual(typed("HOCJS"), "HÓC")
        XCTAssertEqual(typed("HOCJJ⌫S"), "HÓC")
        XCTAssertEqual(typed("TIEENGSS⌫F"), typed("TIEENGSF"))
    }

    func testSecondBackspaceIsPlain() {
        XCTAssertEqual(typed("hocjj⌫⌫"), "họ")
    }

    func testNotDoubledUnchanged() {
        VikeyEngine.setDoubleKeyFix(false)
        let vikey = typed("rofif⌫")
        VikeyEngine.setDoubleKeyFix(true)
        XCTAssertEqual(typed("rofif⌫"), vikey)
    }

    func testResetBetweenCancels() {
        VikeyEngine.setDoubleKeyFix(false)
        engine.setVietnamese(true)
        engine.resetContext()
        let off = Field(engine)
        off.type("hocjj")
        engine.resetContext()
        let vikey = off.type("⌫")

        VikeyEngine.setDoubleKeyFix(true)
        engine.setVietnamese(true)
        engine.resetContext()
        let on = Field(engine)
        on.type("hocjj")
        engine.resetContext()
        XCTAssertEqual(on.type("⌫"), vikey)
    }

    func testSwitchOff() {
        VikeyEngine.setDoubleKeyFix(false)
        XCTAssertEqual(typed("hocjj⌫"), "hoc")
    }
}
