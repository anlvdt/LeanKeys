import XCTest
import VikeyShim
@testable import LeanKeysKit

/// The first all-caps word of a line (Caps Lock on) converts like the words after it: "BUIF " gives "BÙI ".
/// Vikey alone keeps a lone all-caps word as typed unless it doubles a vowel or uses w (its rules D23/D41), so a
/// heading or a form that starts with a family name ("BÙI", "NGUYỄN") came out raw. LeanKeys knows Caps Lock is on
/// and treats the word as part of a run of capitals. Acronyms with an English reading (USA, IRS) stay; so does a
/// word typed with Shift held, which Vikey already decides.
final class CapsLockWordTests: XCTestCase {
    private let keyCodes: [Character: UInt16] = [
        "a": 0, "b": 11, "c": 8, "d": 2, "e": 14, "f": 3, "g": 5, "h": 4, "i": 34, "j": 38, "k": 40, "l": 37,
        "m": 46, "n": 45, "o": 31, "p": 35, "q": 12, "r": 15, "s": 1, "t": 17, "u": 32, "v": 9, "w": 13, "x": 7,
        "y": 16, "z": 6, " ": 49, "3": 20, "4": 21, "5": 23, ".": 47, ",": 43,
    ]

    override func tearDown() {
        lk_vikey_set_fix_filter(nil)
        super.tearDown()
    }

    /// Types `keys` with Caps Lock on (letters are capitals, Shift not held) or with Shift held, and returns the
    /// field's text.
    private func type(_ keys: String, capsLock: Bool, thenBackspaces: Int = 0) -> String {
        guard let engine = VikeyEngine() else { XCTFail("no engine"); return "" }
        engine.setAutoSwitch(true)
        engine.setVietnamese(true)
        engine.resetContext()
        var text: [Character] = []
        for ch in keys {
            guard let code = keyCodes[Character(ch.lowercased())] else { XCTFail("no key for \(ch)"); continue }
            let letter = ch.isLetter
            let caps = letter && ch.isUppercase
            let shift = capsLock ? false : caps
            if let edit = engine.process(keyCode: code, caps: caps, shift: shift) {
                text.removeLast(min(edit.deleteCount, text.count))
                text.append(contentsOf: edit.text)
                if edit.keyPassesThrough { text.append(ch) }
            } else {
                text.append(ch)
            }
        }
        for _ in 0..<thenBackspaces {
            if let edit = engine.process(keyCode: 51, caps: false, shift: false) {
                text.removeLast(min(edit.deleteCount, text.count))
                text.append(contentsOf: edit.text)
            } else if !text.isEmpty {
                text.removeLast()
            }
        }
        return String(text)
    }

    func testFirstAllCapsWordConvertsWithCapsLock() {
        XCTAssertEqual(type("BUIF ", capsLock: true), "BÙI ")
        XCTAssertEqual(type("NGUYEENX ", capsLock: true), "NGUYỄN ")
        XCTAssertEqual(type("BUIF THIJ XUAAN ", capsLock: true), "BÙI THỊ XUÂN ")
        XCTAssertEqual(type("453 BUIF MIF ", capsLock: true), "453 BÙI MÌ ")
    }

    func testAcronymsStayWithCapsLock() {
        XCTAssertEqual(type("USA ", capsLock: true), "USA ")
        XCTAssertEqual(type("IRS ", capsLock: true), "IRS ")
        XCTAssertEqual(type("HTML ", capsLock: true), "HTML ")
    }

    func testShiftHeldIsLeftToVikey() {
        XCTAssertEqual(type("BUIF ", capsLock: false), "BUIF ")
    }

    func testLowerCaseIsUnchanged() {
        XCTAssertEqual(type("buif ", capsLock: false), "bùi ")
        XCTAssertEqual(type("Buif ", capsLock: false), "Bùi ")
    }

    func testCommonWordWithOnlyAToneKeyConverts() {
        XCTAssertEqual(type("BAFN ", capsLock: true), "BÀN ")
    }

    func testBackspaceTwiceGivesTheKeysBack() {
        XCTAssertEqual(type("BUIF ", capsLock: true, thenBackspaces: 2), "BUIF")
        XCTAssertNil(VikeyEngine()?.takeUndo(), "the undo learner never saw the Caps Lock veto")
    }

    /// The Caps Lock rule never keeps a word whose keys are English: Vikey puts "BÚ" back to "BUS" and so does LeanKeys.
    func testEnglishKeysStay() {
        XCTAssertEqual(type("BUS ", capsLock: true), "BUS ")
    }

    /// The word is kept at any break, and an acronym after it stays.
    func testInALineAndBeforePunctuation() {
        XCTAssertEqual(type("BUIF IRS ", capsLock: true), "BÙI IRS ")
        XCTAssertEqual(type("BUIF. ", capsLock: true), "BÙI. ")
        XCTAssertEqual(type("BUIF, ", capsLock: true), "BÙI, ")
    }
}
