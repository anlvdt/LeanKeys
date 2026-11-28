import XCTest
import VikeyShim
@testable import LeanKeysKit

/// Spec 12.2, C side: the fix filter, undo events and the reverse undo, through the shim and the real engine.

/// Mac virtual key codes, from vendor/vikey/Engine/platforms/mac.h. "⌫" is Backspace.
private let macKey: [Character: UInt16] = [
    "a": 0, "b": 11, "c": 8, "d": 2, "e": 14, "f": 3, "g": 5, "h": 4, "i": 34, "j": 38, "k": 40, "l": 37, "m": 46,
    "n": 45, "o": 31, "p": 35, "q": 12, "r": 15, "s": 1, "t": 17, "u": 32, "v": 9, "w": 13, "x": 7, "y": 16, "z": 6,
    " ": 49, ",": 43, ".": 47, "⌫": 51,
]

private struct Edit: Equatable {
    let deleteCount: Int
    let text: String
    let languageChanged: Bool
}

/// What the filter vetoes (by `before`) and the fixes it was shown. The C callback reads these.
private var vetoed: Set<String> = []
private var shown: [(before: String, after: String, previous: String)] = []

private func string<T>(_ units: T, _ length: Int32) -> String {
    withUnsafeBytes(of: units) { String(decoding: $0.bindMemory(to: UInt16.self).prefix(Int(length)), as: UTF16.self) }
}

private let vetoFilter: lk_fix_filter = { fix in
    guard let fix = fix?.pointee else { return 0 }
    let before = string(fix.before, fix.beforeLength)
    shown.append((before, string(fix.after, fix.afterLength), string(fix.previous, fix.previousLength)))
    return vetoed.contains(before) ? 1 : 0
}

private let neverVeto: lk_fix_filter = { _ in 0 }

/// A line of text driven by lk_vikey_press, keeping every edit it returned.
private final class Line {
    var text: [UInt16] = []
    var edits: [Edit] = []

    var string: String { String(decoding: text, as: UTF16.self) }

    @discardableResult
    func type(_ keys: String) -> String {
        for ch in keys {
            guard let code = macKey[Character(ch.lowercased())] else { XCTFail("no mac key for \(ch)"); continue }
            var raw = lk_edit()
            lk_vikey_press(code, ch.isUppercase ? 1 : 0, 0, &raw)
            let units = withUnsafeBytes(of: &raw.text) { Array($0.bindMemory(to: UInt16.self).prefix(Int(raw.length))) }
            text.removeLast(min(Int(raw.deleteCount), text.count))
            text += units
            edits.append(Edit(deleteCount: Int(raw.deleteCount), text: String(decoding: units, as: UTF16.self),
                              languageChanged: raw.languageChanged != 0))
        }
        return string
    }
}

private func takeUndo() -> (before: String, after: String, previous: String, reverse: Bool)? {
    var undo = lk_undo()
    guard lk_vikey_take_undo(&undo) == 1 else { return nil }
    return (string(undo.fix.before, undo.fix.beforeLength), string(undo.fix.after, undo.fix.afterLength),
            string(undo.fix.previous, undo.fix.previousLength), undo.reverse != 0)
}

final class UndoShimTests: XCTestCase {
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
        vetoed = []
        shown = []
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

    // Probed: in Vietnamese, Telex "cos" types "có" key by key (no fix at the break, nothing to undo). Starting in
    // English, Vikey fixes "cos" to "có" at the space and switches to Vietnamese; ⌫⌫ puts "cos" and English back.
    func testUndoEventCarriesBeforeAfterPrevious() {
        let l = line(0)
        XCTAssertEqual(l.type("toi thich "), "toi thich ")
        XCTAssertEqual(l.type("cos "), "toi thich có ")
        XCTAssertNil(takeUndo(), "a fix alone is not an undo")
        XCTAssertEqual(l.type("⌫⌫"), "toi thich cos")
        let undo = takeUndo()
        XCTAssertEqual(undo?.before, "cos")
        XCTAssertEqual(undo?.after, "có")
        XCTAssertEqual(undo?.previous, "thich")
        XCTAssertEqual(undo?.reverse, false)
        XCTAssertNil(takeUndo(), "one event per undo")
    }

    func testVetoKeepsTypedWordInOneEdit() {
        lk_vikey_set_fix_filter(vetoFilter)
        vetoed = ["cos"]
        let l = line(0)
        l.type("toi thich cos")
        let languageBefore = lk_vikey_language()
        let editsBefore = l.edits.count
        XCTAssertEqual(l.type(" "), "toi thich cos ")
        XCTAssertEqual(l.edits.count, editsBefore + 1, "the space key returns one edit")
        XCTAssertEqual(lk_vikey_language(), languageBefore)
        XCTAssertEqual(shown.count, 1)
        XCTAssertEqual(shown.first?.before, "cos")
        XCTAssertEqual(shown.first?.after, "có")
        XCTAssertEqual(shown.first?.previous, "thich")
        XCTAssertNil(takeUndo(), "the veto is not an undo")
        // Typing on is plain English: the vetoed word is not fixed again by the next word.
        XCTAssertEqual(l.type("nhe "), "toi thich cos nhe ")
    }

    // Ruling P2, probed: with the engine in Vietnamese, "I like its" shows "I like ít" and Vikey puts it back to
    // "its" at the space, switching to English.
    func testVetoOtherDirection() {
        XCTAssertEqual(line(1).type("I like its "), "I like its ", "Vikey's own fix (precondition)")
        XCTAssertEqual(lk_vikey_language(), 0)

        lk_vikey_set_fix_filter(vetoFilter)
        vetoed = ["ít"]
        let l = line(1)
        l.type("I like its")
        XCTAssertEqual(l.string, "I like ít")
        let languageBefore = lk_vikey_language()
        XCTAssertEqual(l.type(" "), "I like ít ")
        XCTAssertEqual(lk_vikey_language(), languageBefore)
        XCTAssertEqual(shown.first?.after, "its")
        XCTAssertEqual(shown.first?.previous, "like")
    }

    func testReverseUndoAfterVeto() {
        lk_vikey_set_fix_filter(vetoFilter)
        vetoed = ["cos"]
        let l = line(0)
        XCTAssertEqual(l.type("toi thich cos "), "toi thich cos ")
        XCTAssertEqual(l.type("⌫"), "toi thich cos")
        XCTAssertNil(takeUndo())
        let editsBefore = l.edits.count
        XCTAssertEqual(l.type("⌫"), "toi thich có")
        XCTAssertEqual(l.edits.last, Edit(deleteCount: 3, text: "có", languageChanged: true))
        XCTAssertEqual(l.edits.count, editsBefore + 1)
        XCTAssertEqual(lk_vikey_language(), 1, "the language after the fix")
        let undo = takeUndo()
        XCTAssertEqual(undo?.before, "cos")
        XCTAssertEqual(undo?.after, "có")
        XCTAssertEqual(undo?.previous, "thich")
        XCTAssertEqual(undo?.reverse, true)
        XCTAssertNil(takeUndo())
        // The engine holds "có" again: a tone key changes its tone.
        XCTAssertEqual(l.type("f"), "toi thich cò")
    }

    func testReverseUndoOtherDirection() {
        lk_vikey_set_fix_filter(vetoFilter)
        vetoed = ["ít"]
        let l = line(1)
        XCTAssertEqual(l.type("I like its ⌫⌫"), "I like its")
        XCTAssertEqual(lk_vikey_language(), 0)
        XCTAssertEqual(takeUndo()?.reverse, true)
    }

    func testOtherKeyClearsVeto() {
        lk_vikey_set_fix_filter(vetoFilter)
        vetoed = ["cos"]
        let l = line(0)
        l.type("toi thich cos ")
        XCTAssertEqual(l.type("a⌫⌫"), "toi thich cos", "plain Backspace once a key came between")
        XCTAssertNil(takeUndo())
    }

    func testNoFilterNoChange() {
        let sentence = "toi thich cos ⌫⌫ nhe, cos lam "
        let vikey = line(0)
        vikey.type(sentence)
        XCTAssertEqual(vikey.string, "toi thich cos nhe, có lam ")
        _ = takeUndo()

        lk_vikey_set_fix_filter(neverVeto)
        let passed = line(0)
        passed.type(sentence)
        XCTAssertEqual(passed.edits, vikey.edits)

        lk_vikey_set_fix_filter(nil)
        let none = line(0)
        none.type(sentence)
        XCTAssertEqual(none.edits, vikey.edits)
    }
    // ⌫⌫ right after the Space that put an English word back ("tét" -> "test", which Vikey lets ⌫⌫ undo) and then a
    // letter is an edit of that word, not an undo: the two Backspaces delete the Space and the last letter.
    func testLetterAfterUndoOfEnglishRestoreEdits() {
        XCTAssertEqual(line(1).type("test "), "test ", "Vikey puts the keys back (precondition)")
        XCTAssertEqual(lk_vikey_language(), 0)
        XCTAssertEqual(line(1).type("test ⌫⌫t"), "test")
        XCTAssertNil(takeUndo(), "an edit is no undo for the learner")
        XCTAssertEqual(line(1).type("test ⌫⌫t xin"), "test xin", "Vikey goes on deciding the next word")
        XCTAssertEqual(line(1).type("test ⌫⌫s "), "tess ")
        XCTAssertEqual(line(1).type("push ⌫⌫h vaf "), "push và ")
        XCTAssertEqual(line(1).type("test ⌫⌫⌫xt "), "text ", "more Backspaces delete more letters")
        XCTAssertEqual(line(1).type("traffic "), "traffic ", "a doubled letter Vikey puts back (precondition)")
        XCTAssertEqual(line(1).type("traffic ⌫⌫c "), "traffic ")
        _ = takeUndo()
    }

    func testBreakAfterUndoOfEnglishRestoreStillUndoes() {
        let l = line(1)
        XCTAssertEqual(l.type("I like its ⌫⌫"), "I like ít")
        XCTAssertNil(takeUndo(), "held until the next key tells an undo from an edit")
        XCTAssertEqual(l.type(" "), "I like ít ")
        let undo = takeUndo()
        XCTAssertEqual(undo?.before, "ít")
        XCTAssertEqual(undo?.after, "its")
        XCTAssertEqual(undo?.previous, "like")
        XCTAssertEqual(undo?.reverse, false)
        // A reset (click, arrow, app switch) also lets the held undo through.
        line(1).type("I like its ⌫⌫")
        lk_vikey_reset_context()
        XCTAssertEqual(takeUndo()?.before, "ít")
    }
}
