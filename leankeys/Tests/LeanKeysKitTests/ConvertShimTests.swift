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

/// What the convert filter converts (by `keys`) and the words it was shown. The C callback reads these.
private var converting: Set<String> = []
private var convertShown: [(before: String, after: String, previous: String, keys: String)] = []

private func units<T>(_ u: T, _ length: Int32) -> String {
    withUnsafeBytes(of: u) { String(decoding: $0.bindMemory(to: UInt16.self).prefix(Int(length)), as: UTF16.self) }
}

private let convertFilter: lk_convert_filter = { fix in
    guard let fix = fix?.pointee else { return 0 }
    let keys = units(fix.keys, fix.keysLength)
    convertShown.append((units(fix.before, fix.beforeLength), units(fix.after, fix.afterLength),
                         units(fix.previous, fix.previousLength), keys))
    return converting.contains(keys) ? 1 : 0
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
        lk_vikey_set_convert_filter(nil)
        converting = []
        convertShown = []
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

    // ⌃⌫ with nothing to change goes through to the app, and the typing context starts over, as after a reset: the keys
    // after it give the same edits as after lk_vikey_reset_context.
    func testNoOpResetsTheContext() {
        func run(_ noOp: Bool) -> [Edit] {
            let l = line(1)
            l.type("ok ")
            if noOp { assertNothingToConvert(l) } else { lk_vikey_reset_context() }
            l.type("sdt ")
            if noOp { assertNothingToConvert(l) } else { lk_vikey_reset_context() }
            let start = l.edits.count
            l.type("toi cos thich lats  ⌫⌫⌫")
            return Array(l.edits[start...])
        }
        XCTAssertEqual(run(true), run(false))
    }

    // A filter that converts nothing changes nothing: Backspace over a break, a tone key after it, all as with no filter.
    func testZeroFilterEqualsNilFilter() {
        for typed in ["toi ⌫s", "can ⌫s", "toi ⌫⌫s", "toi ⌫as ", "toi thich cos ⌫⌫ nhe, beer ⌫r va test ⌫⌫t ",
                      "toi uong beer ⌫⌫ mix lats ⌫⌫⌫s "] {
            func run(_ filter: Bool) -> [Edit] {
                lk_vikey_set_convert_filter(filter ? convertFilter : nil)
                converting = []
                return line(1).edits + { let l = line(1); l.type(typed); return l.edits }()
            }
            XCTAssertEqual(run(true), run(false), typed)
            lk_vikey_set_convert_filter(nil)
        }
    }

    func testFilterAfterIsEmptyForTelexConversion() {
        lk_vikey_set_convert_filter(convertFilter)
        converting = []
        let l = line(0)
        l.type("pus ")
        let seen = convertShown.last
        XCTAssertEqual(seen?.before, "pus")
        XCTAssertEqual(seen?.after, "")
        XCTAssertEqual(seen?.keys, "pus")
    }

    func testTelexConversionAtBreakWhenFilterSaysOne() {
        lk_vikey_set_convert_filter(convertFilter)
        converting = ["pus"]
        let l = line(0)
        XCTAssertEqual(l.type("pus "), "pú ")
        XCTAssertEqual(lk_vikey_language(), 1)
        XCTAssertEqual(l.type("⌃"), "pus ")
        XCTAssertEqual(takeEvent()?.kind, 2)
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

    // MARK: Learning events (spec 5.3, 8.4)

    private func takeEvent() -> (before: String, after: String, previous: String, keys: String, reverse: Bool, kind: Int32)? {
        var undo = lk_undo()
        guard lk_vikey_take_undo(&undo) == 1 else { return nil }
        let f = undo.fix
        return (VikeyEngine.string(f.before, f.beforeLength), VikeyEngine.string(f.after, f.afterLength),
                VikeyEngine.string(f.previous, f.previousLength), VikeyEngine.string(f.keys, f.keysLength),
                undo.reverse != 0, undo.kind)
    }

    func testConvertEventHeldUntilNextKey() {
        let l = line(1)
        XCTAssertEqual(l.type("toi uong beer ⌃"), "toi uong beer ")
        XCTAssertNil(takeEvent(), "held until the next key")
        l.type("n")
        let e = takeEvent()
        XCTAssertEqual(e?.kind, 1)
        XCTAssertEqual(e?.before, "bể")
        XCTAssertEqual(e?.after, "beer")
        XCTAssertEqual(e?.keys, "beer")
        XCTAssertEqual(e?.previous, "uong")
        XCTAssertEqual(e?.reverse, false)
        XCTAssertNil(takeEvent(), "one event per conversion")
    }

    func testToggleBackRecordsNothing() {
        let l = line(1)
        l.type("toi uong beer ⌃⌃n")
        XCTAssertNil(takeEvent())
    }

    func testResetReleasesEvent() {
        let l = line(1)
        l.type("toi uong beer ⌃")
        XCTAssertNil(takeEvent())
        lk_vikey_reset_context()
        XCTAssertEqual(takeEvent()?.kind, 1)
        XCTAssertNil(takeEvent())
    }

    func testConvertOfJustFixedWordIsUndo() {
        let l = line(0)
        XCTAssertEqual(l.type("toi thich cos "), "toi thich có ", "precondition: Vikey fixes it")
        XCTAssertEqual(l.type("⌃"), "toi thich cos ")
        XCTAssertEqual(l.lastConvertResult, 1)
        XCTAssertEqual(lk_vikey_language(), 0)
        XCTAssertNil(takeEvent(), "held until the next key")
        l.type(" ")
        let e = takeEvent()
        XCTAssertEqual(e?.kind, 0)
        XCTAssertEqual(e?.before, "cos")
        XCTAssertEqual(e?.after, "có")
        XCTAssertEqual(e?.keys, "cos")
        XCTAssertEqual(e?.reverse, false)
    }

    func testConvertWhileHeldUndo() {
        let l = line(1)
        XCTAssertEqual(l.type("test ⌫⌫"), "tét")
        XCTAssertEqual(l.type("⌃"), "test")
        XCTAssertEqual(l.lastConvertResult, 1)
        l.type(" ")
        XCTAssertNil(takeEvent(), "the held undo was dropped and nothing is held")
    }

    func testToggleBackOfJustFixedWordRecordsNothing() {
        let l = line(0)
        XCTAssertEqual(l.type("toi thich cos "), "toi thich có ")
        XCTAssertEqual(l.type("⌃⌃"), "toi thich có ")
        l.type("x")
        XCTAssertNil(takeEvent())
    }

    // MARK: Convert filter at a break key (spec 5.2, 5.3)

    func testConvertFilterAppliesAtBreak() {
        lk_vikey_set_convert_filter(convertFilter)
        converting = ["beer"]
        let l = line(1)
        XCTAssertEqual(l.type("toi uong beer"), "toi uong bể")
        let start = l.edits.count
        XCTAssertEqual(l.type(" "), "toi uong beer ")
        XCTAssertEqual(l.edits.count, start + 1)
        XCTAssertEqual(l.edits[start].deleteCount, 2)
        XCTAssertEqual(l.edits[start].text, "beer ")
        XCTAssertEqual(lk_vikey_language(), 0)
        XCTAssertEqual(l.edits[start].languageChanged, true)
        let seen = convertShown.last
        XCTAssertEqual(seen?.before, "bể")
        XCTAssertEqual(seen?.after, "beer")
        XCTAssertEqual(seen?.previous, "uong")
        XCTAssertEqual(seen?.keys, "beer")
        XCTAssertNil(takeEvent(), "a rule's conversion is no event")
    }

    func testFilterNotCalledWhenVikeyFixes() {
        lk_vikey_set_convert_filter(convertFilter)
        converting = ["cos"]
        let l = line(0)
        XCTAssertEqual(l.type("toi thich cos "), "toi thich có ")
        XCTAssertFalse(convertShown.contains { $0.keys == "cos" }, "the word Vikey fixed never reaches the filter")
    }

    func testFilterNotCalledWithoutKeysOrWord() {
        lk_vikey_set_convert_filter(convertFilter)
        converting = ["beer", "mix", "mi"]
        let l = line(1)
        // A Backspace in the word: the keys are unknown.
        l.type("beers⌫ ")
        XCTAssertTrue(convertShown.isEmpty)
        // Two breaks: the second has no word before it.
        l.type("mix  ")
        XCTAssertTrue(l.string.hasSuffix(" mix  "), l.string)
        XCTAssertEqual(convertShown.map { $0.keys }, ["mix"])
    }

    func testNilFilterChangesNothing() {
        func run(_ filter: Bool) -> [Edit] {
            lk_vikey_set_convert_filter(filter ? convertFilter : nil)
            converting = []
            let l = line(1)
            l.type("toi uong beer mix cos, lats  ")
            return l.edits
        }
        XCTAssertEqual(run(true), run(false))
        lk_vikey_set_convert_filter(nil)
        XCTAssertEqual(line(1).type("toi uong beer "), "toi uong bể ")
    }

    func testCtrlBackspaceAfterRuleConvertReverses() {
        lk_vikey_set_convert_filter(convertFilter)
        converting = ["beer"]
        let l = line(1)
        XCTAssertEqual(l.type("toi uong beer ⌃"), "toi uong bể ")
        XCTAssertEqual(l.lastConvertResult, 1)
        XCTAssertEqual(lk_vikey_language(), 1)
        let e = takeEvent()
        XCTAssertEqual(e?.kind, 2, "queued at once, not held")
        XCTAssertEqual(e?.keys, "beer")
        XCTAssertEqual(e?.before, "bể")
        XCTAssertEqual(e?.after, "beer")
        XCTAssertEqual(e?.previous, "uong")
        XCTAssertNil(takeEvent())
        l.type("n")
        XCTAssertNil(takeEvent(), "nothing more after the next key")
    }

    func testCtrlBackspaceReverseEventAfterNextKey() {
        lk_vikey_set_convert_filter(convertFilter)
        converting = ["beer"]
        let l = line(1)
        l.type("toi uong beer ⌃n")
        XCTAssertEqual(takeEvent()?.kind, 2)
        XCTAssertNil(takeEvent())
    }

    func testDoubleBackspaceAfterRuleConvertReverses() {
        lk_vikey_set_convert_filter(convertFilter)
        converting = ["beer"]
        let l = line(1)
        XCTAssertEqual(l.type("toi uong beer ⌫⌫"), "toi uong bể")
        let e = takeEvent()
        XCTAssertEqual(e?.kind, 2, "available right after the second Backspace")
        XCTAssertEqual(e?.keys, "beer")
        XCTAssertEqual(e?.before, "bể")
        XCTAssertEqual(e?.after, "beer")
        XCTAssertEqual(e?.previous, "uong")
        XCTAssertNil(takeEvent(), "exactly one event")
        XCTAssertEqual(lk_vikey_language(), 1)
        // The word is back as Vikey had it: a tone key goes on from it.
        XCTAssertEqual(l.type("s"), "toi uong bế")
    }

    func testOneBackspaceAfterRuleConvertIsPlain() {
        lk_vikey_set_convert_filter(convertFilter)
        converting = ["beer"]
        let l = line(1)
        XCTAssertEqual(l.type("toi uong beer ⌫"), "toi uong beer")
        XCTAssertNil(takeEvent())
        l.type("x")
        XCTAssertNil(takeEvent())
    }

    func testRuleConvertThenAnotherKeyKeepsNoReverse() {
        lk_vikey_set_convert_filter(convertFilter)
        converting = ["beer"]
        let l = line(1)
        l.type("toi uong beer a⌫⌫")
        XCTAssertNil(takeEvent())
    }

    // A held ⌃⌫ event released by the very key that queues another: neither is lost nor replaced silently.
    func testHeldConvertThenRuleConvertKeepsBoth() {
        lk_vikey_set_convert_filter(convertFilter)
        converting = ["beer"]
        let l = line(1)
        l.type("cos ⌃")                       // held kind 1 event for "cos"
        XCTAssertNil(takeEvent())
        l.type("beer ")                        // the first key releases it; the break converts "beer" by the rule
        XCTAssertEqual(takeEvent()?.kind, 1)
        l.type("⌫⌫")
        XCTAssertEqual(takeEvent()?.kind, 2)
        XCTAssertNil(takeEvent())
    }
}
