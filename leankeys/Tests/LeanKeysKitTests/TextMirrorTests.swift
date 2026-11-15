import XCTest
@testable import LeanKeysKit

/// Collects what a mirror commits.
private final class Recorder {
    var words: [CommittedWord] = []
    var phrases: [String] = []

    init(_ mirror: TextMirror) {
        mirror.onWord = { [unowned self] in words.append($0) }
        mirror.onPhrase = { [unowned self] in phrases.append($0.text) }
    }

    var wordTexts: [String] { words.map(\.text) }
}

private func type(_ text: String, into mirror: TextMirror) {
    for c in text { mirror.typed(c) }
}

/// Minimal engine for router tests: plays back scripted edits, then lets keys through.
private final class ScriptedEngine: TypingEngine {
    var queue: [EngineEdit?] = []
    var isVietnamese = true
    func process(keyCode: UInt16, caps: Bool, shift: Bool) -> EngineEdit? {
        queue.isEmpty ? nil : queue.removeFirst()
    }
    func resetContext() {}
    func setVietnamese(_ on: Bool) { isVietnamese = on }
    func setAutoSwitch(_ on: Bool) {}
    func setModernTone(_ on: Bool) {}
}

final class TextMirrorTests: XCTestCase {
    func testWordsAndPhrasesFromTypedKeys() {
        let mirror = TextMirror()
        let rec = Recorder(mirror)
        type("Số 12 đường Lê Lợi.", into: mirror)
        XCTAssertEqual(rec.phrases, [], "a terminator waits for what follows")
        type(" ", into: mirror)
        XCTAssertEqual(rec.wordTexts, ["Số", "12", "đường", "Lê", "Lợi"])
        XCTAssertEqual(rec.words.map(\.breakChar), [" ", " ", " ", " ", "."])
        XCTAssertEqual(rec.phrases, ["Số 12 đường Lê Lợi"])
        XCTAssertEqual(mirror.currentWord, "")
    }

    func testCurrentWordAndPhraseTerminators() {
        let mirror = TextMirror()
        let rec = Recorder(mirror)
        type("Xin chào, bạn", into: mirror)
        XCTAssertEqual(mirror.currentWord, "bạn")
        type("!\n  Dòng hai\n", into: mirror)
        XCTAssertEqual(rec.wordTexts, ["Xin", "chào", "bạn", "Dòng", "hai"])
        XCTAssertEqual(rec.words.map(\.breakChar), [" ", ",", "!", " ", "\n"])
        // Inner punctuation stays in the phrase, the terminator does not, whitespace is trimmed, empty phrases vanish.
        XCTAssertEqual(rec.phrases, ["Xin chào, bạn", "Dòng hai"])
    }

    func testAppliesEngineEdits() {
        let mirror = TextMirror()
        let rec = Recorder(mirror)
        type("Vie", into: mirror)
        mirror.apply(deleteCount: 1, insert: ["ệ"])
        XCTAssertEqual(mirror.currentWord, "Việ")
        type("t", into: mirror)
        // An engine edit that carries a break (Vikey keeps Space in its text) commits like a typed key.
        mirror.apply(deleteCount: 0, insert: [" "])
        type("Nam. ", into: mirror)
        XCTAssertEqual(rec.wordTexts, ["Việt", "Nam"])
        XCTAssertEqual(rec.phrases, ["Việt Nam"])
    }

    func testDeletingMoreThanMirroredResets() {
        let mirror = TextMirror()
        let rec = Recorder(mirror)
        type("ab", into: mirror)
        mirror.apply(deleteCount: 3, insert: [])
        XCTAssertEqual(mirror.currentWord, "")
        type("c. ", into: mirror)
        // The text left of the cursor is unknown: "c" is not a whole word, and the phrase is dropped.
        XCTAssertEqual(rec.wordTexts, [])
        XCTAssertEqual(rec.phrases, [])
        type("Mới. ", into: mirror)
        XCTAssertEqual(rec.wordTexts, ["Mới"])
        XCTAssertEqual(rec.phrases, ["Mới"])
    }

    private func makeRouter(_ suite: String, engine: EngineKind = .gonhanh) -> EngineRouter {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let router = EngineRouter(defaults: defaults, makeVikey: { ScriptedEngine() })
        router.selected = engine
        return router
    }

    private let dia: [(UInt16, Bool)] = [(2, true), (34, false), (0, false)] // "Dia"

    private func typeKeys(_ keys: [(UInt16, Bool)], _ router: EngineRouter) {
        for (code, shift) in keys { router.observeGoNhanh(keyCode: code, shift: shift, caps: shift, result: nil) }
    }

    /// Ruling R3 (spec 11.1): a phrase also ends where the cursor moves, so those resets emit it.
    func testCursorMovesEmitPhrase() {
        let router = makeRouter("TextMirrorTests.cursor")
        let rec = Recorder(router.mirror)

        // Arrows, Home/End, Page Up/Down, Esc: the phrase is emitted, the word is not (no break key was typed).
        for code: UInt16 in [123, 124, 125, 126, 115, 119, 116, 121, 53] {
            typeKeys(dia, router)
            typeKeys([(code, false)], router)
            XCTAssertEqual(rec.phrases.last, "Dia", "key \(code)")
            XCTAssertEqual(router.mirror.currentWord, "", "key \(code)")
        }
        XCTAssertEqual(rec.phrases.count, 9)
        XCTAssertEqual(rec.wordTexts, [])

        // Tab commits the word (shortcuts expand at Tab), then the phrase.
        typeKeys([(45, true), (0, false), (46, false), (49, false)] + dia + [(48, false)], router) // "Nam Dia\t"
        XCTAssertEqual(rec.words.map(\.text), ["Nam", "Dia"])
        XCTAssertEqual(rec.words.last?.breakChar, "\t")
        XCTAssertEqual(rec.phrases.last, "Nam Dia")

        // A click or app switch reaches the router as clear() (RustBridge.clearBuffer*), terminator pending or not.
        typeKeys(dia, router)
        router.clear()
        XCTAssertEqual(rec.phrases.last, "Dia")
        typeKeys(dia + [(47, false)], router)
        router.clear()
        XCTAssertEqual(rec.phrases.last, "Dia")
        XCTAssertEqual(rec.phrases.count, 12)
        // Nothing pending: nothing emitted.
        router.clear()
        XCTAssertEqual(rec.phrases.count, 12)
    }

    func testBypassAndSecureDiscardPhrase() {
        let router = makeRouter("TextMirrorTests.discard")
        let rec = Recorder(router.mirror)

        // Cmd+key, Control, Option+Backspace, restore shortcut and Secure Input call discardPending() before
        // clearBuffer*, so the clear() that follows has nothing to emit.
        typeKeys(dia, router)
        router.discardPending()
        XCTAssertEqual(router.mirror.currentWord, "")
        router.clear()
        XCTAssertEqual(rec.phrases, [])

        // Forward delete, F1 and other keys without a character change text out of sight: discarded too.
        for code: UInt16 in [117, 122] {
            typeKeys(dia + [(code, false)], router)
            router.clear()
            XCTAssertEqual(rec.phrases, [], "key \(code)")
        }
        XCTAssertEqual(rec.wordTexts, [])

        // A Ctrl chord under Vikey discards as well.
        let vikey = makeRouter("TextMirrorTests.discard.vikey", engine: .vikey)
        let vrec = Recorder(vikey.mirror)
        for code: UInt16 in [0, 11] { _ = vikey.intercept(keyCode: code, caps: false, ctrl: false, shift: false) }
        XCTAssertEqual(vikey.mirror.currentWord, "ab")
        _ = vikey.intercept(keyCode: 8, caps: false, ctrl: true, shift: false) // Ctrl+C
        XCTAssertEqual(vikey.mirror.currentWord, "")
        vikey.clear()
        XCTAssertEqual(vrec.phrases, [])
    }

    /// Ruling R4: `. ! ?` end a phrase only before Space, Return/Enter or a reset.
    func testTerminatorInsideTokensStays() {
        let mirror = TextMirror()
        let rec = Recorder(mirror)
        type("Email an@vidu.vn ", into: mirror)
        XCTAssertEqual(rec.phrases, [])
        mirror.reset()
        XCTAssertEqual(rec.phrases, ["Email an@vidu.vn"])
        XCTAssertEqual(rec.wordTexts, ["Email", "an@vidu", "vn"])

        type("Giá 3.5 triệu\n", into: mirror)
        type("Gọi 0912.345.678\n", into: mirror)
        XCTAssertEqual(rec.phrases.suffix(2), ["Giá 3.5 triệu", "Gọi 0912.345.678"])
    }

    func testSentenceThenNextPhrase() {
        let mirror = TextMirror()
        let rec = Recorder(mirror)
        type("Xong. Mai", into: mirror)
        XCTAssertEqual(rec.phrases, ["Xong"])
        mirror.reset()
        XCTAssertEqual(rec.phrases, ["Xong", "Mai"])
        // Several terminators: only the trailing ones are cut. Deleting a pending terminator resumes the word.
        type("Hả?! Ừ.", into: mirror)
        mirror.apply(deleteCount: 1, insert: [])
        XCTAssertEqual(mirror.currentWord, "Ừ")
        type("m\n", into: mirror)
        XCTAssertEqual(rec.phrases.suffix(2), ["Hả", "Ừm"])
    }

    /// Ruling R5: numbers typed on the keypad stay in the phrase.
    func testKeypadDigitsStayInPhrase() {
        let router = makeRouter("TextMirrorTests.keypad")
        let rec = Recorder(router.mirror)
        typeKeys([(45, true), (49, false)], router) // "N "
        typeKeys([(82, false), (83, false), (84, false), (85, false), (86, false), (87, false), (88, false),
                  (89, false), (91, false), (92, false), (65, false), (83, false)], router) // "0123456789.1"
        XCTAssertEqual(router.mirror.currentWord, "1")
        router.clear()
        XCTAssertEqual(rec.phrases, ["N 0123456789.1"])
        XCTAssertEqual(rec.wordTexts, ["N", "0123456789"])
    }

    func testPhraseCapped() {
        let mirror = TextMirror()
        let rec = Recorder(mirror)
        type(String(repeating: "ab ", count: 200) + "cuối", into: mirror) // 604 characters
        XCTAssertEqual(mirror.currentWord, "cuối")
        type(". ", into: mirror)
        XCTAssertEqual(rec.phrases, [])
        XCTAssertEqual(rec.words.last?.text, "cuối")
        // Exactly 500 is kept, and the next phrase starts clean.
        let exact = String(repeating: "x", count: 499) + "y"
        type(exact + ". ", into: mirror)
        XCTAssertEqual(rec.phrases, [exact])
        type("Ngắn! ", into: mirror)
        XCTAssertEqual(rec.phrases.last, "Ngắn")
    }

    /// Gõ Nhanh (observeGoNhanh) and Vikey (intercept) feed one mirror by one standard.
    func testBothEnginesCommitTheSame() {
        func run(_ engine: EngineKind) -> ([String], [String]) {
            let suite = "TextMirrorTests.both.\(engine)"
            let defaults = UserDefaults(suiteName: suite)!
            defaults.removePersistentDomain(forName: suite)
            let vikey = ScriptedEngine()
            let router = EngineRouter(defaults: defaults, makeVikey: { vikey })
            router.selected = engine
            let rec = Recorder(router.mirror)
            // "Vieejt Nam." in Telex: e, e → ê (edit), j → ệ (edit), Space, Shift+n, a, m, "." passes through.
            typealias Step = (code: UInt16, shift: Bool, edit: (Int, [Character], Bool)?)
            let steps: [Step] = [
                (9, true, nil), (34, false, nil), (14, false, nil),
                (14, false, (1, ["ê"], true)), (38, false, (1, ["ệ"], true)), (17, false, nil),
                (49, false, nil), (45, true, nil), (0, false, nil), (46, false, nil),
                (47, false, (0, [], false)), // an edit with nothing to change; the "." itself still goes through
                (36, false, nil), // Return: nothing left to commit
            ]
            for step in steps {
                if engine == .vikey {
                    vikey.queue = [step.edit.map { EngineEdit(deleteCount: $0.0, text: $0.1, languageChanged: false,
                                                               keyPassesThrough: !$0.2) }]
                    _ = router.intercept(keyCode: step.code, caps: step.shift, ctrl: false, shift: step.shift)
                } else {
                    router.observeGoNhanh(keyCode: step.code, shift: step.shift, caps: step.shift, result: step.edit)
                }
            }
            return (rec.wordTexts, rec.phrases)
        }
        let vikey = run(.vikey), gonhanh = run(.gonhanh)
        XCTAssertEqual(vikey.0, ["Việt", "Nam"])
        XCTAssertEqual(vikey.1, ["Việt Nam"])
        XCTAssertEqual(gonhanh.0, vikey.0)
        XCTAssertEqual(gonhanh.1, vikey.1)
    }

    func testNativeBackspaceDeletes() {
        let defaults = UserDefaults(suiteName: "TextMirrorTests.bs")!
        defaults.removePersistentDomain(forName: "TextMirrorTests.bs")
        let router = EngineRouter(defaults: defaults, makeVikey: { ScriptedEngine() })
        router.selected = .gonhanh
        for code: UInt16 in [0, 11, 8] { router.observeGoNhanh(keyCode: code, shift: false, caps: false, result: nil) }
        router.observeGoNhanh(keyCode: 51, shift: false, caps: false, result: nil)
        XCTAssertEqual(router.mirror.currentWord, "ab")
        // An engine-handled Backspace is swallowed: only its edit counts.
        router.observeGoNhanh(keyCode: 51, shift: false, caps: false, result: (1, [], true))
        XCTAssertEqual(router.mirror.currentWord, "a")
    }
}
