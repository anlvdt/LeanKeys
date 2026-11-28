import AppKit
import XCTest
@testable import LeanKeysKit

/// 4A+ latency & quality bench (2026-11-28 review). Skipped unless `LEANKEYS_PREDICT_BENCH=1`.
/// Replays made-up chat text (Vikey's `chat_messages.txt`), never the user's data, and does no synthetic typing.
/// `LEANKEYS_BENCH_CORPUS` points at the corpus, `LEANKEYS_BENCH_OUT` at a folder for the JSON samples.
final class PredictionLatencyBenchTests: XCTestCase {
    private var enabled: Bool { ProcessInfo.processInfo.environment["LEANKEYS_PREDICT_BENCH"] == "1" }
    private var outDir: URL? {
        ProcessInfo.processInfo.environment["LEANKEYS_BENCH_OUT"].map { URL(fileURLWithPath: $0) }
    }

    private static func stats(_ ms: [Double]) -> String {
        guard !ms.isEmpty else { return "n=0" }
        let s = ms.sorted()
        func p(_ q: Double) -> Double { s[min(s.count - 1, Int(Double(s.count) * q))] }
        let mean = s.reduce(0, +) / Double(s.count)
        return String(format: "n=%d mean=%.3f p50=%.3f p95=%.3f p99=%.3f max=%.3f ms", s.count, mean, p(0.5), p(0.95), p(0.99), s.last!)
    }

    private func dump(_ name: String, _ obj: Any) {
        guard let outDir else { return }
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: obj) {
            try? data.write(to: outDir.appendingPathComponent(name))
        }
    }

    private func corpusLines() throws -> [String] {
        let path = ProcessInfo.processInfo.environment["LEANKEYS_BENCH_CORPUS"]
            ?? "vendor/vikey/Tools/autoswitch/sim/corpus/chat_messages.txt"
        let text = try String(contentsOfFile: path, encoding: .utf8)
        return text.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    private static func words(_ line: String) -> [String] {
        line.split(whereSeparator: { $0.isWhitespace }).map {
            String($0).trimmingCharacters(in: CharacterSet.punctuationCharacters)
        }.filter { !$0.isEmpty }
    }

    // MARK: - 1. engine.predict on every keystroke of real text + quality

    func testPredictReplayLatencyAndQuality() throws {
        try XCTSkipUnless(enabled)
        let lines = try corpusLines()
        let split = lines.count * 2 / 3
        let ctx = LearnContext(bundleID: "com.apple.TextEdit", secureInput: false, secureField: false,
                               now: Date())
        let personal = PersonalPredictionModel(store: nil)
        personal.enabled = true
        for l in lines[..<split] { personal.observe(CommittedPhrase(text: l), context: ctx) }

        for (label, model, sticky) in [("personal", Optional(personal), false), ("builtin-only", nil, false), ("personal+sticky", Optional(personal), true), ("personal+filter-only", Optional(personal), true), ("personal+filter-then-3", Optional(personal), true)] {
            let engine = PredictionEngine(corpus: .shared, personal: model, dictionary: VikeyDictionaryCompleter.shared)
            var afterSpace: [Double] = [], midWord: [Double] = []
            var keys = 0, shown = 0, listChanged = 0, slot0Changed = 0, hideShowFlips = 0
            var words = 0, next1 = 0, next3 = 0, wordsCompletedEarly = 0, savedChars = 0, totalChars = 0
            var firstSlot0Pos: [Int] = []
            var runs: [Int] = []          // keystrokes a shown list stays identical
            var curRun = 0
            var examples: [String] = []
            for line in lines[split...] {
                let ws = Self.words(line)
                var prevList: [String] = []
                var prevShown = false
                for (wi, w) in ws.enumerated() {
                    let prev = Array(ws[..<wi])
                    let target = w.lowercased()
                    words += 1
                    totalChars += w.count
                    var hitAt: Int?
                    let chars = Array(w)
                    for k in 0...chars.count - 1 {
                        // State at this keystroke: k == 0 is "right after the space before w".
                        let cur = String(chars[..<k])
                        keys += 1
                        let q = PredictionQuery(previousWords: prev, currentWord: cur, followsNonSpaceBreak: false,
                                                atWordStartAfterSpace: k == 0, isVietnamese: true)
                        let willRun = !(cur.isEmpty && prev.isEmpty) && !(cur.count == 1)  // app: refreshNow hides at 1 letter
                        var list: [PredictionCandidate] = []
                        if willRun {
                            let t0 = CFAbsoluteTimeGetCurrent()
                            list = engine.predict(q)
                            let dt = (CFAbsoluteTimeGetCurrent() - t0) * 1000
                            if k == 0 { afterSpace.append(dt) } else { midWord.append(dt) }
                        }
                        var texts = list.map(\.display)
                        if sticky {
                            // Proposed policy: on each key keep the shown words that still match the typed prefix in
                            // their slots (1-letter words included), fill only the freed slots with new results.
                            let f = BuiltInPredictionCorpus.foldDiacritics(cur)
                            let keep = prevList.map { t -> String? in
                                (cur.isEmpty || (BuiltInPredictionCorpus.foldDiacritics(t).hasPrefix(f) && t.lowercased() != cur.lowercased())) ? t : nil
                            }
                            if k == 0 { texts = Array(texts.prefix(3)) }
                            else if label.hasSuffix("filter-only") || (label.hasSuffix("filter-then-3") && (cur.count < 3 || keep.contains { $0 != nil })) {
                                texts = keep.compactMap { $0 }
                            } else {
                                var slots = keep
                                var fresh = texts.filter { !keep.contains($0) }.makeIterator()
                                for i in 0..<3 {
                                    if i < slots.count, slots[i] != nil { continue }
                                    if let n = fresh.next() { if i < slots.count { slots[i] = n } else { slots.append(n) } }
                                }
                                texts = slots.compactMap { $0 }
                            }
                        }
                        let isShown = !texts.isEmpty
                        if isShown { shown += 1 }
                        if isShown != prevShown { hideShowFlips += 1 }
                        if isShown && prevShown && texts != prevList { listChanged += 1 }
                        if isShown && prevShown && texts == prevList { curRun += 1 } else {
                            if curRun > 0 { runs.append(curRun) }
                            curRun = isShown ? 1 : 0
                        }
                        if examples.count < 40, line.hasPrefix("Mình") || line.hasPrefix("Em ") {
                            examples.append("\(prev.suffix(2).joined(separator: " "))|\(cur)| → \(texts.joined(separator: " · "))")
                        }
                        if isShown && prevShown && texts.first != prevList.first { slot0Changed += 1 }
                        prevShown = isShown
                        prevList = texts
                        if k == 0 {
                            let firstWords = texts.map { $0.split(separator: " ").first.map { String($0).lowercased() } ?? "" }
                            if firstWords.first == target { next1 += 1 }
                            if firstWords.contains(target) { next3 += 1 }
                        }
                        if hitAt == nil, let top = texts.first,
                           top.split(separator: " ").first.map({ String($0).lowercased() }) == target {
                            hitAt = k
                        }
                    }
                    if let hitAt {
                        wordsCompletedEarly += 1
                        savedChars += chars.count - hitAt
                        firstSlot0Pos.append(hitAt)
                    }
                }
            }
            print("[bench] predict(\(label)) after-space: \(Self.stats(afterSpace))")
            print("[bench] predict(\(label)) mid-word:    \(Self.stats(midWord))")
            print(String(format: "[bench] quality(%@) keys=%d shown=%.1f%% list-changed-while-shown=%.1f%% slot0-changed=%.1f%% hide/show flips per word=%.2f",
                         label, keys, 100.0 * Double(shown) / Double(keys), 100.0 * Double(listChanged) / Double(max(1, shown)),
                         100.0 * Double(slot0Changed) / Double(max(1, shown)), Double(hideShowFlips) / Double(words)))
            print(String(format: "[bench] quality(%@) words=%d next-word top1=%.1f%% top3=%.1f%%; target in slot0 before finished=%.1f%% of words; max keystroke saving if Tab at first slot0 hit=%.1f%% of chars",
                         label, words, 100.0 * Double(next1) / Double(words), 100.0 * Double(next3) / Double(words),
                         100.0 * Double(wordsCompletedEarly) / Double(words), 100.0 * Double(savedChars) / Double(totalChars)))
            if curRun > 0 { runs.append(curRun) }
            let meanRun = Double(runs.reduce(0, +)) / Double(max(1, runs.count))
            let ge3 = 100.0 * Double(runs.filter { $0 >= 3 }.count) / Double(max(1, runs.count))
            print(String(format: "[bench] stability(%@) a shown list stays for %.2f keystrokes on average; %.1f%% of lists last >= 3 keystrokes", label, meanRun, ge3))
            if label == "personal" { for e in examples { print("[example] \(e)") } }
            dump("predict-\(label).json", ["afterSpace": afterSpace, "midWord": midWord, "runs": runs])
        }
    }

    // MARK: - 2. CandidatePanelController.show (SwiftUI) cost on the main thread

    func testPanelShowCost() throws {
        try XCTSkipUnless(enabled)
        _ = NSApplication.shared
        let panel = CandidatePanelController()
        let anchor = CaretLocator.CaretAnchor(rect: CGRect(x: 400, y: 500, width: 2, height: 18), isFieldFallback: false)
        func cands(_ seed: Int) -> [PredictionCandidate] {
            (0..<3).map { i in
                PredictionCandidate(id: "c\(seed)-\(i)", display: ["cảm ơn bạn", "kiểm tra lại", "được không"][i] + " \(seed)",
                                    insertion: "x ", deleteCount: 0, kind: .word, score: 1)
            }
        }
        var first: [Double] = [], changed: [Double] = [], same: [Double] = [], moved: [Double] = []
        var commitChanged: [Double] = []
        func spin() -> Double {
            let t = CFAbsoluteTimeGetCurrent()
            CATransaction.flush()
            RunLoop.current.run(mode: .default, before: Date())
            return (CFAbsoluteTimeGetCurrent() - t) * 1000
        }
        for round in 0..<40 {
            panel.hide(); _ = spin()
            var t = CFAbsoluteTimeGetCurrent()
            panel.show(candidates: cands(round), anchor: anchor) { _ in }
            first.append((CFAbsoluteTimeGetCurrent() - t) * 1000); _ = spin()
            for i in 1...10 {
                t = CFAbsoluteTimeGetCurrent()
                panel.show(candidates: cands(round * 100 + i), anchor: anchor) { _ in }
                changed.append((CFAbsoluteTimeGetCurrent() - t) * 1000)
                commitChanged.append(spin())
                t = CFAbsoluteTimeGetCurrent()
                panel.show(candidates: cands(round * 100 + i), anchor: anchor) { _ in }
                same.append((CFAbsoluteTimeGetCurrent() - t) * 1000); _ = spin()
                let a2 = CaretLocator.CaretAnchor(rect: anchor.rect.offsetBy(dx: CGFloat(i * 7), dy: 0), isFieldFallback: false)
                t = CFAbsoluteTimeGetCurrent()
                panel.show(candidates: cands(round * 100 + i), anchor: a2) { _ in }
                moved.append((CFAbsoluteTimeGetCurrent() - t) * 1000); _ = spin()
            }
        }
        panel.hide()
        print("[bench] panel.show first:          \(Self.stats(first))")
        print("[bench] panel.show texts changed:  \(Self.stats(changed))")
        print("[bench]   + CA commit/render:      \(Self.stats(commitChanged))")
        print("[bench] panel.show same texts:     \(Self.stats(same))")
        print("[bench] panel.show moved only:     \(Self.stats(moved))")
        dump("panel.json", ["first": first, "changed": changed, "commit": commitChanged, "same": same, "moved": moved])
    }

    // MARK: - 3. CaretLocator (AX) against running apps

    func testCaretLocatorAgainstRunningApps() throws {
        try XCTSkipUnless(enabled)
        try XCTSkipUnless(AXIsProcessTrusted(), "needs Accessibility for the test runner")
        let ids = ["com.apple.TextEdit", "com.apple.Notes", "com.google.Chrome", "com.apple.Safari",
                   "com.microsoft.Word", "com.apple.Terminal", "com.anthropic.claudefordesktop"]
        var out: [String: Any] = [:]
        for id in ids {
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first else { continue }
            var ms: [Double] = []
            var nils = 0, fallback = 0
            for _ in 0..<150 {
                let t = CFAbsoluteTimeGetCurrent()
                let a = CaretLocator.currentAnchor(pid: app.processIdentifier)
                ms.append((CFAbsoluteTimeGetCurrent() - t) * 1000)
                if a == nil { nils += 1 } else if a!.isFieldFallback { fallback += 1 }
            }
            print("[bench] AX \(id): \(Self.stats(ms)) nil=\(nils) fieldFallback=\(fallback)")
            out[id] = ["ms": ms, "nil": nils, "fallback": fallback]
        }
        dump("ax.json", out)
    }

    /// AX while the target app is busy taking keys, as in real typing. Keys go to TextEdit with `postToPid`, which
    /// skips the HID/session taps, so LeanKeys never sees them. Needs `LEANKEYS_BENCH_LIVE=1` and a front TextEdit
    /// document (the runner script opens and closes one).
    func testCaretLocatorWhileTyping() throws {
        try XCTSkipUnless(enabled && ProcessInfo.processInfo.environment["LEANKEYS_BENCH_LIVE"] == "1")
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.TextEdit").first,
              app.isActive else { throw XCTSkip("TextEdit must be frontmost") }
        let pid = app.processIdentifier
        let src = CGEventSource(stateID: .privateState)
        let letters: [CGKeyCode] = [0x00, 0x0B, 0x08, 0x02, 0x0E, 0x31] // a b c d e space
        var out: [String: Any] = [:]
        for interval in [50, 80, 120] {
            var ms: [Double] = []
            var nils = 0
            for i in 0..<120 {
                let code = letters[i % letters.count]
                CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: true)?.postToPid(pid)
                CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: false)?.postToPid(pid)
                let t = CFAbsoluteTimeGetCurrent()
                let a = CaretLocator.currentAnchor(pid: pid)
                let dt = (CFAbsoluteTimeGetCurrent() - t) * 1000
                ms.append(dt)
                if a == nil { nils += 1 }
                let rest = Double(interval) / 1000 - dt / 1000
                if rest > 0 { Thread.sleep(forTimeInterval: rest) }
            }
            print("[bench] AX TextEdit while typing every \(interval) ms: \(Self.stats(ms)) nil=\(nils)")
            out["\(interval)"] = ["ms": ms, "nil": nils]
        }
        dump("ax-live.json", out)
    }
}
