import XCTest
import VikeyShim
@testable import LeanKeysKit

final class PredictionEngineTests: XCTestCase {
    private var corpus: BuiltInPredictionCorpus!

    override func setUp() {
        super.setUp()
        corpus = BuiltInPredictionCorpus(data: .bundled)
    }

    func testNextWordVietnameseBigrams() {
        let engine = PredictionEngine(corpus: corpus, personal: nil, dictionary: nil)
        let q = PredictionQuery(
            previousWords: ["cảm"],
            currentWord: "",
            followsNonSpaceBreak: false,
            atWordStartAfterSpace: true,
            isVietnamese: true
        )
        let candidates = engine.predict(q)
        XCTAssertFalse(candidates.isEmpty)
        XCTAssertEqual(candidates.first?.display, "ơn")
        XCTAssertEqual(candidates.first?.insertion, "ơn ")
        XCTAssertEqual(candidates.first?.deleteCount, 0)
    }

    func testPhraseAndSentenceContinuations() {
        let engine = PredictionEngine(corpus: corpus, personal: nil, dictionary: nil)

        let q1 = PredictionQuery(
            previousWords: ["cảm", "ơn"],
            currentWord: "",
            followsNonSpaceBreak: false,
            atWordStartAfterSpace: true,
            isVietnamese: true
        )
        let c1 = engine.predict(q1)
        XCTAssertTrue(c1.contains(where: { $0.display == "bạn nhiều" && $0.kind == .phrase }))

        let q2 = PredictionQuery(
            previousWords: ["để", "em"],
            currentWord: "",
            followsNonSpaceBreak: false,
            atWordStartAfterSpace: true,
            isVietnamese: true
        )
        let c2 = engine.predict(q2)
        XCTAssertEqual(c2.first?.kind, .sentence)
        XCTAssertEqual(c2.first?.display, "kiểm tra lại rồi báo anh sau")
    }

    func testContextAwareMidWordPrefixCompletionAndCase() {
        let engine = PredictionEngine(corpus: corpus, personal: nil, dictionary: nil)

        // "chúc bạn m" / "mộ" -> matches "một ngày tốt lành" from context
        let q1 = PredictionQuery(
            previousWords: ["chúc", "bạn"],
            currentWord: "mộ",
            followsNonSpaceBreak: false,
            atWordStartAfterSpace: false,
            isVietnamese: true
        )
        let c1 = engine.predict(q1)
        XCTAssertEqual(c1.first?.display, "một ngày tốt lành")
        XCTAssertEqual(c1.first?.deleteCount, 2)

        // Preserves Title Case / UPPERCASE on mid-word completion
        let q2 = PredictionQuery(
            previousWords: [],
            currentWord: "Chươ",
            followsNonSpaceBreak: false,
            atWordStartAfterSpace: false,
            isVietnamese: true
        )
        let c2 = engine.predict(q2)
        XCTAssertTrue(c2.contains(where: { $0.display.hasPrefix("Chương") && $0.deleteCount == 4 }))

        let q3 = PredictionQuery(
            previousWords: [],
            currentWord: "CHƯƠ",
            followsNonSpaceBreak: false,
            atWordStartAfterSpace: false,
            isVietnamese: true
        )
        let c3 = engine.predict(q3)
        XCTAssertTrue(c3.contains(where: { $0.display.hasPrefix("CHƯƠNG") }))
    }

    func testShortcutPrefixMatches() {
        let engine = PredictionEngine(corpus: corpus, personal: nil, dictionary: nil)
        let q = PredictionQuery(
            previousWords: [],
            currentWord: "dc",
            followsNonSpaceBreak: false,
            atWordStartAfterSpace: false,
            isVietnamese: true,
            shortcuts: [("dchi", "số 12 đường Lê Lợi"), ("dc", "được")]
        )
        let c = engine.predict(q)
        XCTAssertEqual(c.first?.kind, .shortcut)
        XCTAssertEqual(c.first?.insertion, "được ")
        XCTAssertTrue(c.contains(where: { $0.insertion == "số 12 đường Lê Lợi " }))
    }

    func testSkipsNonSpaceBreakAndSingleCharPrefix() {
        let engine = PredictionEngine(corpus: corpus, personal: nil, dictionary: nil)
        let shortQ = PredictionQuery(
            previousWords: [],
            currentWord: "c",
            followsNonSpaceBreak: false,
            atWordStartAfterSpace: false,
            isVietnamese: true
        )
        XCTAssertTrue(engine.predict(shortQ).isEmpty)

        let urlQ = PredictionQuery(
            previousWords: ["example"],
            currentWord: "com",
            followsNonSpaceBreak: true,
            atWordStartAfterSpace: false,
            isVietnamese: false
        )
        XCTAssertTrue(engine.predict(urlQ).isEmpty)
    }

    func testChainedPredictionAfterTabAccept() {
        let defaultsSuite = "PredictionChainTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsSuite)!
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }

        let router = EngineRouter(defaults: defaults, makeVikey: { nil })
        let controller = PredictionController(
            defaults: defaults,
            personal: PersonalPredictionModel(store: nil),
            corpus: corpus,
            dictionary: nil,
            onLearnerQueue: { $0() },
            onMain: { $0() }
        )
        controller.setEnabled(true)

        // Simulate "cảm " typed into mirror
        for ch in Array("cảm ") { router.mirror.typed(ch) }
        let anchor = CaretLocator.CaretAnchor(rect: CGRect(x: 200, y: 400, width: 2, height: 18), isFieldFallback: false)
        // Drive prediction engine directly for deterministic unit check, and acceptCandidate flow via mirror
        let first = PredictionEngine(corpus: corpus, personal: nil, dictionary: nil).predict(
            PredictionQuery(previousWords: router.mirror.recentWordsBeforeCurrent,
                            currentWord: router.mirror.currentWord,
                            followsNonSpaceBreak: false,
                            atWordStartAfterSpace: true,
                            isVietnamese: true)
        )
        XCTAssertEqual(first.first?.display, "ơn")

        // Simulate accepting "ơn " -> mirror should have "cảm ơn "
        router.resetWordAfterPrediction(deleteCount: first[0].deleteCount, inserted: Array(first[0].insertion))
        XCTAssertEqual(router.mirror.recentWordsBeforeCurrent, ["cảm", "ơn"])
        XCTAssertEqual(router.mirror.currentWord, "")

        let chained = PredictionEngine(corpus: corpus, personal: nil, dictionary: nil).predict(
            PredictionQuery(previousWords: router.mirror.recentWordsBeforeCurrent,
                            currentWord: router.mirror.currentWord,
                            followsNonSpaceBreak: false,
                            atWordStartAfterSpace: true,
                            isVietnamese: true)
        )
        XCTAssertTrue(chained.contains(where: { $0.display == "bạn nhiều" }))
        _ = anchor
    }

    func testVikeyShimCompletionsAndBounds() {
        var buf = [CChar](repeating: 0, count: 16 * 32)
        var scores = [Int32](repeating: 0, count: 16)

        // Null / empty / invalid prefix returns 0 safely
        let emptyCount = "".withCString { p in
            buf.withUnsafeMutableBufferPointer { b in
                scores.withUnsafeMutableBufferPointer { s in
                    b.baseAddress!.withMemoryRebound(to: (CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
                                                         CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
                                                         CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
                                                         CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar).self,
                                                    capacity: 16) { tp in
                        lk_vikey_completions(0, p, tp, s.baseAddress, 5)
                    }
                }
            }
        }
        XCTAssertEqual(emptyCount, 0)
        XCTAssertEqual(lk_vikey_completions(0, nil, nil, nil, 5), 0)

        // English prefix completion via VikeyDictionaryCompleter
        let en = VikeyDictionaryCompleter.shared.completions(vietnamese: false, asciiPrefix: "improv", maxOut: 5)
        XCTAssertTrue(en.contains(where: { $0.text == "improve" || $0.text == "improved" || $0.text == "improvement" }))

        // Telex rendering via lk_vikey_render_telex
        var u16 = [UInt16](repeating: 0, count: 64)
        let len = "dduowcj".withCString { ptr in
            u16.withUnsafeMutableBufferPointer { lk_vikey_render_telex(ptr, $0.baseAddress, 64) }
        }
        XCTAssertGreaterThan(len, 0)
        XCTAssertEqual(String(decoding: u16.prefix(Int(len)), as: UTF16.self), "được")
        XCTAssertEqual(lk_vikey_render_telex(nil, nil, 0), 0)
    }

    func testCaretLocatorCocoaRectConversionAndPanelClamping() {
        let converted = CaretLocator.cocoaRect(fromQuartz: CGRect(x: 100, y: 200, width: 2, height: 20),
                                               primaryScreenHeight: 1000)
        XCTAssertEqual(converted, CGRect(x: 100, y: 780, width: 2, height: 20))

        let screen = CGRect(x: 0, y: 25, width: 1440, height: 875)
        // Normal case: places below caret
        let normal = CandidatePanelController.panelOrigin(panelSize: CGSize(width: 260, height: 34),
                                                          caretRect: CGRect(x: 300, y: 500, width: 2, height: 18),
                                                          screens: [screen])
        XCTAssertEqual(normal.y, 460)

        // Near bottom edge: flips above caret
        let flipped = CandidatePanelController.panelOrigin(panelSize: CGSize(width: 260, height: 34),
                                                           caretRect: CGRect(x: 300, y: 40, width: 2, height: 18),
                                                           screens: [screen])
        XCTAssertEqual(flipped.y, 64)

        // Near right edge: clamps inside screen
        let clampedRight = CandidatePanelController.panelOrigin(panelSize: CGSize(width: 260, height: 34),
                                                                caretRect: CGRect(x: 1380, y: 500, width: 2, height: 18),
                                                                screens: [screen])
        XCTAssertEqual(clampedRight.x, 1440 - 260 - 8)
    }

    func testPredictionLatencyUnderBudget() {
        let engine = PredictionEngine(corpus: corpus, personal: nil, dictionary: VikeyDictionaryCompleter.shared)
        let queries = [
            PredictionQuery(previousWords: ["cảm", "ơn"], currentWord: "", followsNonSpaceBreak: false, atWordStartAfterSpace: true, isVietnamese: true),
            PredictionQuery(previousWords: ["chúc", "bạn"], currentWord: "mộ", followsNonSpaceBreak: false, atWordStartAfterSpace: false, isVietnamese: true),
            PredictionQuery(previousWords: [], currentWord: "chươ", followsNonSpaceBreak: false, atWordStartAfterSpace: false, isVietnamese: true),
            PredictionQuery(previousWords: [], currentWord: "impr", followsNonSpaceBreak: false, atWordStartAfterSpace: false, isVietnamese: false),
        ]
        for q in queries { _ = engine.predict(q) }
        let iterations = 50
        let t0 = CFAbsoluteTimeGetCurrent()
        for _ in 0..<iterations { for q in queries { _ = engine.predict(q) } }
        let avgMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000.0 / Double(iterations * queries.count)
        print("PredictionEngine avg latency: \(String(format: "%.4f", avgMs)) ms/query")
        XCTAssertLessThan(avgMs, 0.5, "Prediction runs on the event-tap thread: keep each query under 0.5 ms")
    }

    func testWordRowGrowsIntoPhraseTheUserTypedBefore() {
        let personal = PersonalPredictionModel(store: nil)
        personal.enabled = true
        let ctx = LearnContext(bundleID: "com.apple.TextEdit", secureInput: false, secureField: false, now: Date())
        for _ in 0..<2 { personal.observe(CommittedPhrase(text: "Em gửi báo cáo tiến độ Q4 nhé"), context: ctx) }
        let engine = PredictionEngine(corpus: corpus, personal: personal, dictionary: nil,
                                      phraseExtension: .replace, minExtensionContext: 2)
        let rows = engine.predict(PredictionQuery(previousWords: ["Em", "gửi"], currentWord: "bá",
                                                  followsNonSpaceBreak: false, atWordStartAfterSpace: false, isVietnamese: true))
        XCTAssertEqual(rows.first?.display, "báo cáo tiến độ Q4 nhé")
        XCTAssertEqual(rows.first?.deleteCount, 2)
        XCTAssertEqual(rows.first?.insertion, "báo cáo tiến độ Q4 nhé ")

        personal.enabled = false // learning off: learned phrases must not surface, rows stay words
        let off = engine.predict(PredictionQuery(previousWords: ["Em", "gửi"], currentWord: "bá",
                                                 followsNonSpaceBreak: false, atWordStartAfterSpace: false, isVietnamese: true))
        XCTAssertFalse(off.contains { $0.display.contains("tiến độ") })
    }

    func testBuiltInPhraseTableIsNotGluedOntoWordRows() {
        let engine = PredictionEngine(corpus: corpus, personal: nil, dictionary: nil, phraseExtension: .replace)
        let off = PredictionEngine(corpus: corpus, personal: nil, dictionary: nil)
        let q = PredictionQuery(previousWords: ["cảm"], currentWord: "", followsNonSpaceBreak: false,
                                atWordStartAfterSpace: true, isVietnamese: true)
        XCTAssertEqual(engine.predict(q).map(\.display), off.predict(q).map(\.display))
    }
}
