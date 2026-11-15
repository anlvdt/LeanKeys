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
        type("Nam.", into: mirror)
        XCTAssertEqual(rec.wordTexts, ["Việt", "Nam"])
        XCTAssertEqual(rec.phrases, ["Việt Nam"])
    }

    func testDeletingMoreThanMirroredResets() {
        let mirror = TextMirror()
        let rec = Recorder(mirror)
        type("ab", into: mirror)
        mirror.apply(deleteCount: 3, insert: [])
        XCTAssertEqual(mirror.currentWord, "")
        type("c.", into: mirror)
        // The text left of the cursor is unknown: "c" is not a whole word, and the phrase is dropped.
        XCTAssertEqual(rec.wordTexts, [])
        XCTAssertEqual(rec.phrases, [])
        type("Mới.", into: mirror)
        XCTAssertEqual(rec.wordTexts, ["Mới"])
        XCTAssertEqual(rec.phrases, ["Mới"])
    }

    func testMirrorResetsOnNavigationAndBypass() {
        let defaults = UserDefaults(suiteName: "TextMirrorTests.reset")!
        defaults.removePersistentDomain(forName: "TextMirrorTests.reset")
        let router = EngineRouter(defaults: defaults, makeVikey: { ScriptedEngine() })
        router.selected = .gonhanh
        let rec = Recorder(router.mirror)

        func typeKeys(_ keys: [(UInt16, Bool)]) {
            for (code, shift) in keys { router.observeGoNhanh(keyCode: code, shift: shift, caps: shift, result: nil) }
        }
        let dia: [(UInt16, Bool)] = [(2, true), (34, false), (0, false)] // "Dia"

        // Arrow: word and phrase gone, no partial phrase.
        typeKeys(dia + [(123, false)])
        XCTAssertEqual(router.mirror.currentWord, "")
        typeKeys([(47, false)]) // "."
        XCTAssertEqual(rec.wordTexts, [])
        XCTAssertEqual(rec.phrases, [])

        // Tab: commits the word (shortcuts expand at Tab) but drops the phrase.
        typeKeys(dia + [(48, false)])
        XCTAssertEqual(rec.words.last?.text, "Dia")
        XCTAssertEqual(rec.words.last?.breakChar, "\t")
        XCTAssertEqual(router.mirror.currentWord, "")
        typeKeys([(47, false)])
        XCTAssertEqual(rec.phrases, [])

        // Ctrl/Cmd chords, mouse clicks and app switches reach the router as clear() (RustBridge.clearBuffer*).
        rec.words.removeAll()
        typeKeys(dia)
        router.clear()
        XCTAssertEqual(router.mirror.currentWord, "")
        typeKeys([(47, false)])
        XCTAssertEqual(rec.wordTexts, [])
        XCTAssertEqual(rec.phrases, [])

        // Esc and unmapped keys (F-keys, forward delete) reset too.
        for code: UInt16 in [53, 117, 122] {
            typeKeys(dia + [(code, false), (47, false)])
            XCTAssertEqual(rec.wordTexts, [], "key \(code)")
            XCTAssertEqual(rec.phrases, [], "key \(code)")
        }
    }

    func testVikeyCtrlChordResetsMirror() {
        let defaults = UserDefaults(suiteName: "TextMirrorTests.ctrl")!
        defaults.removePersistentDomain(forName: "TextMirrorTests.ctrl")
        let router = EngineRouter(defaults: defaults, makeVikey: { ScriptedEngine() })
        router.selected = .vikey
        let rec = Recorder(router.mirror)
        for code: UInt16 in [0, 11] { _ = router.intercept(keyCode: code, caps: false, ctrl: false, shift: false) }
        XCTAssertEqual(router.mirror.currentWord, "ab")
        _ = router.intercept(keyCode: 8, caps: false, ctrl: true, shift: false) // Ctrl+C
        XCTAssertEqual(router.mirror.currentWord, "")
        _ = router.intercept(keyCode: 47, caps: false, ctrl: false, shift: false)
        XCTAssertEqual(rec.phrases, [])
    }

    func testPhraseCapped() {
        let mirror = TextMirror()
        let rec = Recorder(mirror)
        type(String(repeating: "ab ", count: 200) + "cuối", into: mirror) // 604 characters
        XCTAssertEqual(mirror.currentWord, "cuối")
        type(".", into: mirror)
        XCTAssertEqual(rec.phrases, [])
        XCTAssertEqual(rec.words.last?.text, "cuối")
        // Exactly 500 is kept, and the next phrase starts clean.
        let exact = String(repeating: "x", count: 499) + "y"
        type(exact + ".", into: mirror)
        XCTAssertEqual(rec.phrases, [exact])
        type("Ngắn!", into: mirror)
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
