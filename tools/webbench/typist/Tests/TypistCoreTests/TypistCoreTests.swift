import CoreGraphics
import XCTest
@testable import TypistCore

final class TypistCoreTests: XCTestCase {
    private func expectStroke(
        _ c: Character,
        _ code: CGKeyCode,
        _ shift: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let s = KeyMap.stroke(for: c) else {
            return XCTFail("no stroke for \(c)", file: file, line: line)
        }
        XCTAssertEqual(s.keyCode, code, "key code for \(c)", file: file, line: line)
        XCTAssertEqual(s.shift, shift, "shift for \(c)", file: file, line: line)
    }

    func testMapsTelexKeys() {
        expectStroke("a", 0, false)
        expectStroke("A", 0, true)
        expectStroke("`", 51, false)
        expectStroke(" ", 49, false)
        expectStroke("?", 44, true)
    }

    func testRejectsUnmappableCharacters() {
        XCTAssertNil(KeyMap.stroke(for: "ư"))
        XCTAssertNil(KeyMap.stroke(for: "\t"))
        XCTAssertNil(KeyMap.stroke(for: "\n"))
    }

    func testScheduleIsDeterministicAndInRange() {
        let a = Schedule.delays(count: 200, speed: .human, seed: 42)
        let b = Schedule.delays(count: 200, speed: .human, seed: 42)
        XCTAssertEqual(a, b, "same seed must give the same delays")
        XCTAssertEqual(a.count, 200)
        for d in a {
            XCTAssertTrue(d >= 1.0 / 12 && d <= 1.0 / 8, "human delay \(d) out of range")
        }

        let fast = Schedule.delays(count: 50, speed: .fast, seed: 7)
        XCTAssertTrue(fast.allSatisfy { abs($0 - 0.04) < 1e-12 }, "fast must be 0.04 each")

        let burst = Schedule.delays(count: 50, speed: .burst, seed: 7)
        XCTAssertTrue(burst.allSatisfy { $0 == 0 }, "burst must be 0 each")
    }

    func testGuardRefusesWrongAppOrTitle() {
        let ok = { (bundle: String?, title: String?, layout: String) in
            Guard.mayType(
                frontBundle: bundle,
                windowTitle: title,
                expectedBundle: "com.google.Chrome",
                token: "x",
                layoutID: layout
            )
        }
        XCTAssertFalse(ok("com.apple.Safari", "webbench-x-ready", "com.apple.keylayout.US"))
        XCTAssertFalse(ok(nil, "webbench-x-ready", "com.apple.keylayout.US"))
        XCTAssertFalse(ok("com.google.Chrome", "webbench-x-error", "com.apple.keylayout.US"))
        XCTAssertFalse(ok("com.google.Chrome", nil, "com.apple.keylayout.US"))
        XCTAssertFalse(ok("com.google.Chrome", "webbench-x-ready", "com.apple.keylayout.Vietnamese"))
        XCTAssertTrue(ok("com.google.Chrome", "webbench-x-ready - Google Chrome", "com.apple.keylayout.US"))
    }

    func testGuardRefusesEmptyToken() {
        XCTAssertFalse(Guard.mayType(
            frontBundle: "com.google.Chrome",
            windowTitle: "webbench--ready",
            expectedBundle: "com.google.Chrome",
            token: "",
            layoutID: "com.apple.keylayout.US"
        ))
    }
}
