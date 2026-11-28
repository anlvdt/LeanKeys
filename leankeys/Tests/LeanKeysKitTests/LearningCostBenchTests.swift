import XCTest
@testable import LeanKeysKit

final class LearningCostBenchTests: XCTestCase {
    func testCorpusLearningCost() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["LEANKEYS_PREDICT_BENCH"] == "1")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let corpus = try String(contentsOfFile: "vendor/vikey/Tools/autoswitch/sim/corpus/chat_messages.txt", encoding: .utf8)
        let lines = corpus.split(separator: "\n").map(String.init)
        for disk in [false, true] {
            let store = disk ? KeychainEncryptedFileStore(url: folder.appendingPathComponent("model.bin")) : nil
            let model = PersonalPredictionModel(store: store, saveDelay: disk ? 2 : 0)
            model.enabled = true
            var times: [Double] = []
            for line in lines {
                let context = LearnContext(bundleID: "com.apple.TextEdit", secureInput: false, secureField: false, now: Date())
                let start = DispatchTime.now().uptimeNanoseconds
                model.observe(CommittedPhrase(text: line), context: context)
                times.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6)
            }
            model.flush()
            times.sort()
            print("[audit] learning disk=\(disk) n=\(times.count) p50=\(times[times.count/2]) p95=\(times[times.count*95/100]) p99=\(times[times.count*99/100]) max=\(times.last!) ms stats=\(model.stats)")
            XCTAssertGreaterThan(model.stats.vocabCount, 0)
        }
    }
    func testConcurrentLearningAndReadCost() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["LEANKEYS_PREDICT_BENCH"] == "1")
        let corpus = try String(contentsOfFile: "vendor/vikey/Tools/autoswitch/sim/corpus/chat_messages.txt", encoding: .utf8)
        let lines = corpus.split(separator: "\n").map(String.init)
        let model = PersonalPredictionModel(store: nil)
        model.enabled = true
        let context = LearnContext(bundleID: "com.apple.TextEdit", secureInput: false, secureField: false, now: Date())
        for line in lines { model.observe(CommittedPhrase(text: line), context: context) }
        for concurrent in [false, true] {
            let group = DispatchGroup()
            if concurrent {
                group.enter()
                DispatchQueue.global().async {
                    for line in lines { model.observe(CommittedPhrase(text: line), context: context) }
                    group.leave()
                }
            }
            var times: [Double] = []
            for _ in 0..<2000 {
                let start = DispatchTime.now().uptimeNanoseconds
                _ = model.wordCompletions(matching: "c")
                times.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6)
                Thread.sleep(forTimeInterval: 0.001)
            }
            group.wait()
            times.sort()
            print("[audit] concurrent=\(concurrent) read p50=\(times[1000]) p95=\(times[1900]) p99=\(times[1980]) max=\(times.last!) ms")
        }
    }

}
