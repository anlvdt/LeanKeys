import XCTest
@testable import LeanKeysKit

final class IdleGateTests: XCTestCase {
    func testDefaultThresholdIsThirtySeconds() {
        XCTAssertFalse(IdleGate(secondsSinceLastKey: { 29.9 }).isIdle, "a key 29.9 s ago is still typing")
        XCTAssertTrue(IdleGate(secondsSinceLastKey: { 30 }).isIdle)
    }

    func testJustTypedIsNotIdle() {
        XCTAssertFalse(IdleGate(secondsSinceLastKey: { 0 }).isIdle)
    }

    func testReadsTheClockEachTime() {
        var seconds: TimeInterval = 5
        let gate = IdleGate(threshold: 10, secondsSinceLastKey: { seconds })
        XCTAssertFalse(gate.isIdle)
        seconds = 10
        XCTAssertTrue(gate.isIdle)
        seconds = 1
        XCTAssertFalse(gate.isIdle, "a new key press ends the idle spell")
    }
}
