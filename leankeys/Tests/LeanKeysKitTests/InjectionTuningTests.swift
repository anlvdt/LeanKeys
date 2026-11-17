import Foundation
import XCTest
@testable import LeanKeysKit

final class InjectionTuningTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "InjectionTuningTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - Settle policy

    func testDefaults() {
        XCTAssertEqual(InjectionTuning.settleMicros(.fast, defaults: defaults), 1000)
        XCTAssertEqual(InjectionTuning.settleMicros(.slow, defaults: defaults), 8000)
        XCTAssertEqual(InjectionTuning.settleMicros(.other, defaults: defaults), 5000, "other methods keep Gõ Nhanh's 5 ms")
    }

    func testUpstreamValues() {
        XCTAssertEqual(InjectionTuning.upstreamSettleMicros(.fast), 5000)
        XCTAssertEqual(InjectionTuning.upstreamSettleMicros(.slow), 20000)
        XCTAssertEqual(InjectionTuning.upstreamSettleMicros(.other), 5000)
    }

    func testOverrides() {
        defaults.set(2500, forKey: "LeanKeys.settleMicros.fast")
        XCTAssertEqual(InjectionTuning.settleMicros(.fast, defaults: defaults), 2500)
        XCTAssertEqual(InjectionTuning.settleMicros(.slow, defaults: defaults), 8000, "the fast override leaves slow alone")

        defaults.set(12000, forKey: "LeanKeys.settleMicros.slow")
        XCTAssertEqual(InjectionTuning.settleMicros(.slow, defaults: defaults), 12000)
        XCTAssertEqual(InjectionTuning.settleMicros(.fast, defaults: defaults), 2500)
        XCTAssertEqual(InjectionTuning.settleMicros(.other, defaults: defaults), 5000, "other ignores both overrides")
    }

    func testZeroOverrideIsHonoured() {
        defaults.set(0, forKey: "LeanKeys.settleMicros.fast")
        XCTAssertEqual(InjectionTuning.settleMicros(.fast, defaults: defaults), 0)
    }

    func testClamping() {
        defaults.set(-5, forKey: "LeanKeys.settleMicros.fast")
        XCTAssertEqual(InjectionTuning.settleMicros(.fast, defaults: defaults), 0)
        defaults.set(99999, forKey: "LeanKeys.settleMicros.slow")
        XCTAssertEqual(InjectionTuning.settleMicros(.slow, defaults: defaults), 30000)
        defaults.set(30000, forKey: "LeanKeys.settleMicros.fast")
        XCTAssertEqual(InjectionTuning.settleMicros(.fast, defaults: defaults), 30000)
    }

    func testNonNumericOverrideIsIgnored() {
        defaults.set("fast please", forKey: "LeanKeys.settleMicros.fast")
        XCTAssertEqual(InjectionTuning.settleMicros(.fast, defaults: defaults), 1000)
        defaults.removeObject(forKey: "LeanKeys.settleMicros.fast")
        XCTAssertEqual(InjectionTuning.settleMicros(.fast, defaults: defaults), 1000)
    }

    // MARK: - Latency harness

    func testBlockingModel() {
        let d: (UInt32, UInt32, UInt32) = (200, 800, 500)
        // 3 backspaces, one wait, one chunk, settle.
        XCTAssertEqual(InjectionTuning.blockingMicros(bs: 3, textUTF16: 5, delays: d, settle: 5000), 600 + 800 + 500 + 5000)
        // No backspaces: no wait.
        XCTAssertEqual(InjectionTuning.blockingMicros(bs: 0, textUTF16: 1, delays: d, settle: 1000), 500 + 1000)
        // 21 UTF-16 units: two chunks; charByChar: one chunk per unit.
        XCTAssertEqual(InjectionTuning.blockingMicros(bs: 0, textUTF16: 21, delays: d, settle: 0), 1000)
        XCTAssertEqual(InjectionTuning.blockingMicros(bs: 0, textUTF16: 3, delays: d, settle: 0, charByChar: true), 1500)
        // emptyCharPrefix: one prefix sleep and one extra backspace.
        XCTAssertEqual(InjectionTuning.blockingMicros(bs: 1, textUTF16: 3, delays: d, settle: 0, emptyCharPrefix: true),
                       200 + 2 * 200 + 800 + 500)
    }

    private struct Profile {
        let name: String
        let delays: (UInt32, UInt32, UInt32)
        let settleClass: InjectionTuning.SettleClass
        var emptyCharPrefix = false
    }

    /// The delay tuples detectMethod() really returns for the common apps.
    private let profiles = [
        Profile(name: "fast, no bundle id (200,800,500)", delays: (200, 800, 500), settleClass: .fast),
        Profile(name: "fast, default app (1000,3000,1500)", delays: (1000, 3000, 1500), settleClass: .fast),
        Profile(name: "slow, Office (3000,8000,3000)", delays: (3000, 8000, 3000), settleClass: .slow),
        Profile(name: "slow, Terminal/VS Code (8000,25000,8000)", delays: (8000, 25000, 8000), settleClass: .slow),
        Profile(name: "emptyChar, browsers (3000,8000,3000)", delays: (3000, 8000, 3000), settleClass: .other, emptyCharPrefix: true),
    ]
    private let edits = [(bs: 1, chars: 3), (bs: 3, chars: 5)]

    /// Replays injectViaBackspace's sleep sequence with a no-op event sink and times it on the wall clock.
    private func replay(bs: Int, chars: Int, delays: (UInt32, UInt32, UInt32), settle: UInt32, emptyCharPrefix: Bool,
                        post: () -> Void) -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        var bs = bs
        if emptyCharPrefix {
            post(); usleep(delays.0 > 0 ? delays.0 : 1000); bs += 1
        }
        for _ in 0 ..< bs { post(); usleep(delays.0) }
        if bs > 0 { usleep(delays.1) }
        var offset = 0
        while offset < chars { post(); if delays.2 > 0 { usleep(delays.2) }; offset += 20 }
        usleep(settle)
        return Double(DispatchTime.now().uptimeNanoseconds - start) / 1000
    }

    /// Prints the before/after table (Gõ Nhanh's settle vs LeanKeys' defaults). Asserts only what the clock can
    /// promise: a replay never takes less than the model says.
    func testLatencyTable() {
        var posts = 0
        let iterations = 5
        var lines = ["", "profile | edit | model before→after ms | measured before→after ms"]
        for p in profiles {
            for e in edits {
                let before = InjectionTuning.upstreamSettleMicros(p.settleClass)
                let after = InjectionTuning.defaultSettleMicros(p.settleClass)
                let mBefore = InjectionTuning.blockingMicros(bs: e.bs, textUTF16: e.chars, delays: p.delays, settle: before,
                                                             emptyCharPrefix: p.emptyCharPrefix)
                let mAfter = InjectionTuning.blockingMicros(bs: e.bs, textUTF16: e.chars, delays: p.delays, settle: after,
                                                            emptyCharPrefix: p.emptyCharPrefix)
                var tBefore = [Double](), tAfter = [Double]()
                for _ in 0 ..< iterations {
                    tBefore.append(replay(bs: e.bs, chars: e.chars, delays: p.delays, settle: before,
                                          emptyCharPrefix: p.emptyCharPrefix) { posts += 1 })
                    tAfter.append(replay(bs: e.bs, chars: e.chars, delays: p.delays, settle: after,
                                         emptyCharPrefix: p.emptyCharPrefix) { posts += 1 })
                }
                let medBefore = tBefore.sorted()[iterations / 2], medAfter = tAfter.sorted()[iterations / 2]
                XCTAssertGreaterThanOrEqual(medBefore, Double(mBefore))
                XCTAssertGreaterThanOrEqual(medAfter, Double(mAfter))
                lines.append(String(format: "%@ | bs=%d, %d chars | %.1f → %.1f | %.1f → %.1f",
                                    p.name, e.bs, e.chars, Double(mBefore) / 1000, Double(mAfter) / 1000,
                                    medBefore / 1000, medAfter / 1000))
            }
        }
        XCTAssertGreaterThan(posts, 0)
        print(lines.joined(separator: "\n"))
    }
}

/// Editors inside a browser page (ProseMirror, Lexical, Quill, contenteditable: AXTextArea or AXWebArea) do not get the
/// address-bar method: its leading U+202F made ProseMirror drop the Backspaces after it ("Hoom" gave "Ho\u{202F}ôm").
final class BrowserEditorInjectionTests: XCTestCase {
    private func defaults() -> UserDefaults {
        let d = UserDefaults(suiteName: "BrowserEditorInjectionTests-\(UUID().uuidString)")!
        return d
    }

    func testOnlyEditorRolesAreEditors() {
        XCTAssertTrue(BrowserEditorInjection.isEditor(role: "AXTextArea"))
        XCTAssertTrue(BrowserEditorInjection.isEditor(role: "AXWebArea"))
        XCTAssertFalse(BrowserEditorInjection.isEditor(role: "AXTextField"))
        XCTAssertFalse(BrowserEditorInjection.isEditor(role: "AXComboBox"))
        XCTAssertFalse(BrowserEditorInjection.isEditor(role: nil))
    }

    func testDefaultIsNotTheAddressBarMethod() {
        XCTAssertNotEqual(BrowserEditorInjection.method(defaults: defaults()), .emptyCharPrefix)
    }

    func testHiddenOverride() {
        let d = defaults()
        for (value, method) in [("fast", BrowserEditorInjection.Method.fast), ("slow", .slow),
                                ("charByChar", .charByChar), ("emptyCharPrefix", .emptyCharPrefix)] {
            d.set(value, forKey: BrowserEditorInjection.overrideKey)
            XCTAssertEqual(BrowserEditorInjection.method(defaults: d), method, value)
        }
        d.set("nonsense", forKey: BrowserEditorInjection.overrideKey)
        XCTAssertEqual(BrowserEditorInjection.method(defaults: d), BrowserEditorInjection.defaultMethod)
    }
}
