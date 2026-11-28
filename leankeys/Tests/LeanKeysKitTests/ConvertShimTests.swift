import XCTest
import VikeyShim
@testable import LeanKeysKit

/// Spec 5.1 of the convert-last-word design, C side: lk_vikey_convert_last_word (the ⌃⌫ key) through the shim and the
/// real engine. "⌃" in a typed string stands for that call, applied to the line like a key.

/// Mac virtual key codes, from vendor/vikey/Engine/platforms/mac.h. "⌫" is Backspace, "\n" Return.
private let macKey: [Character: UInt16] = [
    "a": 0, "b": 11, "c": 8, "d": 2, "e": 14, "f": 3, "g": 5, "h": 4, "i": 34, "j": 38, "k": 40, "l": 37, "m": 46,
    "n": 45, "o": 31, "p": 35, "q": 12, "r": 15, "s": 1, "t": 17, "u": 32, "v": 9, "w": 13, "x": 7, "y": 16, "z": 6,
    " ": 49, ",": 43, ".": 47, "'": 39, "\n": 36, "⌫": 51,
]

private struct Edit: Equatable {
    let deleteCount: Int
    let text: String
    let languageChanged: Bool
}

/// A line of text driven by lk_vikey_press, keeping every edit it returned.
private final class Line {
    var text: [UInt16] = []
    var edits: [Edit] = []
    /// What the last ⌃ returned: 1 (an edit was made) or 0 (the key goes through to the app).
    var lastConvertResult: Int32 = -1
    /// Caps Lock on for every letter, as VikeyEngine reports it: capitals arrive without Shift.
    var capsLock = false

    var string: String { String(decoding: text, as: UTF16.self) }

    private func apply(_ raw: inout lk_edit) {
        let units = withUnsafeBytes(of: &raw.text) { Array($0.bindMemory(to: UInt16.self).prefix(Int(raw.length))) }
        text.removeLast(min(Int(raw.deleteCount), text.count))
        text += units
        edits.append(Edit(deleteCount: Int(raw.deleteCount), text: String(decoding: units, as: UTF16.self),
                          languageChanged: raw.languageChanged != 0))
    }

    @discardableResult
    func type(_ keys: String) -> String {
        for ch in keys {
            if ch == "⌃" {
                var raw = lk_edit()
                lastConvertResult = lk_vikey_convert_last_word(0, &raw)
                apply(&raw)
                continue
            }
            guard let code = macKey[Character(ch.lowercased())] else { XCTFail("no mac key for \(ch)"); continue }
            var raw = lk_edit()
            if capsLock && ch.isLetter { lk_vikey_set_caps_lock(1) }
            lk_vikey_press(code, ch.isUppercase ? 1 : 0, 0, &raw)
            lk_vikey_set_caps_lock(0)
            apply(&raw)
        }
        return string
    }
}

final class ConvertShimTests: XCTestCase {
    override func setUp() {
        super.setUp()
        XCTAssertEqual(lk_vikey_init(), 1)
        clean()
    }

    override func tearDown() {
        clean()
        super.tearDown()
    }

    private func clean() {
        lk_vikey_set_fix_filter(nil)
        var undo = lk_undo()
        while lk_vikey_take_undo(&undo) == 1 {}
        VikeyEngine.setDoubleKeyFix(true)
        lk_vikey_set_language(1)
        lk_vikey_reset_context()
    }

    /// A fresh line, starting in `vietnamese` (1) or English (0).
    private func line(_ vietnamese: Int32) -> Line {
        lk_vikey_set_language(vietnamese)
        lk_vikey_reset_context()
        return Line()
    }

    private func assertNothingToConvert(_ l: Line, file: StaticString = #filePath, line: UInt = #line) {
        var raw = lk_edit()
        raw.deleteCount = 9; raw.length = 9; raw.languageChanged = 1
        XCTAssertEqual(lk_vikey_convert_last_word(0, &raw), 0, file: file, line: line)
        XCTAssertEqual(raw.deleteCount, 0, file: file, line: line)
        XCTAssertEqual(raw.length, 0, file: file, line: line)
        XCTAssertEqual(raw.languageChanged, 0, file: file, line: line)
    }

    func testConvertsTelexWordAfterSpace() {
        let l = line(1)
        XCTAssertEqual(l.type("cos "), "có ")
        XCTAssertEqual(l.type("⌃"), "cos ")
        XCTAssertEqual(l.lastConvertResult, 1)
        XCTAssertEqual(lk_vikey_language(), 0)
        XCTAssertEqual(l.edits.last?.languageChanged, true)
    }

    func testConvertsCollisionWords() {
        var l = line(1)
        XCTAssertEqual(l.type("toi uong beer "), "toi uong bể ")
        XCTAssertEqual(l.type("⌃"), "toi uong beer ")
        l = line(1)
        XCTAssertEqual(l.type("mix "), "mĩ ")
        XCTAssertEqual(l.type("⌃"), "mix ")
        l = line(1)
        XCTAssertEqual(l.type("lats "), "lát ")
        XCTAssertEqual(l.type("⌃"), "lats ")
    }

    func testConvertsRawWordToTelex() {
        let l = line(0)
        XCTAssertEqual(l.type("pus"), "pus")
        XCTAssertEqual(l.type("⌃"), "pú")
        XCTAssertEqual(lk_vikey_language(), 1)
        XCTAssertEqual(l.edits.last?.languageChanged, true)
    }

    func testConvertsWordBeingTyped() {
        let l = line(1)
        XCTAssertEqual(l.type("pus"), "pú")
        XCTAssertEqual(l.type("⌃"), "pus")
        XCTAssertEqual(lk_vikey_language(), 0)
        XCTAssertEqual(l.type("h "), "push ")
    }

    func testKeepsBreakCharacters() {
        var l = line(1)
        XCTAssertEqual(l.type("cos, "), "có, ")
        XCTAssertEqual(l.type("⌃"), "cos, ")
        l = line(1)
        XCTAssertEqual(l.type("cos."), "có.")
        XCTAssertEqual(l.type("⌃"), "cos.")
    }

    func testToggleBack() {
        let l = line(1)
        XCTAssertEqual(l.type("cos "), "có ")
        XCTAssertEqual(l.type("⌃"), "cos ")
        XCTAssertEqual(lk_vikey_language(), 0)
        XCTAssertEqual(l.type("⌃"), "có ")
        XCTAssertEqual(lk_vikey_language(), 1)
        XCTAssertEqual(l.edits.last?.languageChanged, true)
    }

    func testToggleBackWhileTyping() {
        let l = line(1)
        XCTAssertEqual(l.type("pus"), "pú")
        XCTAssertEqual(l.type("⌃⌃"), "pú")
        XCTAssertEqual(lk_vikey_language(), 1)
        // The engine holds "pú" again: a tone key goes on from it ("pú" + r -> "pủ").
        XCTAssertEqual(l.type("r"), "pủ")
    }

    func testAnyKeyEndsTheToggle() {
        let l = line(1)
        XCTAssertEqual(l.type("cos "), "có ")
        XCTAssertEqual(l.type("⌃"), "cos ")
        // A key between: the next ⌃ is no toggle back to "có" (it acts on "a", which Telex does not change).
        XCTAssertEqual(l.type("a"), "cos a")
        XCTAssertEqual(l.type("⌃"), "cos a")
        XCTAssertEqual(l.lastConvertResult, 0)
    }

    func testNothingToConvertReturnsZero() {
        var l = line(1)
        assertNothingToConvert(l)
        XCTAssertEqual(l.type("ok "), "ok ")
        assertNothingToConvert(l)
        l = line(1)
        XCTAssertEqual(l.type("sdt "), "sdt ")
        assertNothingToConvert(l)
        l = line(1)
        XCTAssertEqual(l.type("cos "), "có ")
        lk_vikey_reset_context()
        assertNothingToConvert(l)
        l = line(1)
        l.type("cos")
        l.type("\n")
        assertNothingToConvert(l)
    }

    func testKeepsCase() {
        var l = line(1)
        XCTAssertEqual(l.type("Cos "), "Có ")
        XCTAssertEqual(l.type("⌃"), "Cos ")
        l = line(1)
        l.type("COS ")
        XCTAssertEqual(l.type("⌃"), "COS ")
    }

    func testWordAfterApostrophe() {
        let l = line(1)
        XCTAssertEqual(l.type("don't "), "don't ")
        var raw = lk_edit()
        XCTAssertEqual(lk_vikey_convert_last_word(0, &raw), 0)
        XCTAssertEqual(raw.deleteCount, 0)
        XCTAssertEqual(raw.length, 0)
        XCTAssertEqual(l.string, "don't ")
    }

    // ⌃⌫ with nothing to change leaves every bit of state alone: the keys after it give the same edits as without it.
    func testNoOpLeavesStateAlone() {
        func run(_ noOp: Bool) -> [Edit] {
            let l = line(1)
            l.type("ok ")
            if noOp { assertNothingToConvert(l); l.type("sdt "); assertNothingToConvert(l) } else { l.type("sdt ") }
            let start = l.edits.count
            l.type("toi cos thich lats  ⌫⌫⌫")
            return Array(l.edits[start...])
        }
        XCTAssertEqual(run(true), run(false))
    }

    func testCapsLockWordKeepsCase() {
        var l = line(1)
        l.capsLock = true
        XCTAssertEqual(l.type("COS "), "CÓ ")
        XCTAssertEqual(l.type("⌃"), "COS ")
        l = line(0)
        l.capsLock = true
        XCTAssertEqual(l.type("PUS"), "PUS")
        XCTAssertEqual(l.type("⌃"), "PÚ")
        XCTAssertEqual(lk_vikey_language(), 1)
    }
}
