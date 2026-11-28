import XCTest
@testable import LeanKeysKit

final class KeyPathBenchTests: XCTestCase {
    func testEngineReplay() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["LEANKEYS_PREDICT_BENCH"] == "1")
        let start = DispatchTime.now().uptimeNanoseconds
        let engine = try XCTUnwrap(VikeyEngine())
        let initMS = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6
        engine.setVietnamese(true)
        engine.setPureTelex(true)
        engine.resetContext()
        defer {
            engine.setPureTelex(false)
            engine.resetContext()
        }
        // "chaof banj " in macOS virtual key codes.
        let keys: [UInt16] = [8, 4, 0, 31, 3, 49, 11, 0, 45, 38, 49]
        var samples: [UInt64] = []
        var edits = 0
        var output = ""
        for _ in 0..<1000 {
            for key in keys {
                let t = DispatchTime.now().uptimeNanoseconds
                let edit = engine.process(keyCode: key, caps: false, shift: false)
                samples.append(DispatchTime.now().uptimeNanoseconds - t)
                if let edit {
                    edits += 1
                    output.removeLast(min(edit.deleteCount, output.count))
                    output.append(contentsOf: edit.text)
                    if edit.keyPassesThrough, let character = VikeyEngine.typedCharacter(keyCode: key, shift: false, caps: false) { output.append(character) }
                } else if let character = VikeyEngine.typedCharacter(keyCode: key, shift: false, caps: false) {
                    output.append(character)
                }
            }
        }
        XCTAssertGreaterThan(edits, 0)
        XCTAssertEqual(output, String(repeating: "chào bạn ", count: 1000))
        samples.sort()
        print("[bench] engine init ms", initMS, "key p50/p95/p99 ns",
              [50, 95, 99].map { samples[samples.count * $0 / 100] })
    }
}
