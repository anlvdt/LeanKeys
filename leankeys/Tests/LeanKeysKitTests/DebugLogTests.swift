@testable import LeanKeysKit
import XCTest

final class DebugLogTests: XCTestCase {
    func testLogLivesInTheUsersOwnFolder() {
        XCTAssertFalse(DebugLog.path.hasPrefix("/tmp"))
        XCTAssertFalse(DebugLog.path.hasPrefix("/private/tmp"))
        XCTAssertTrue(DebugLog.path.hasSuffix("/Library/Logs/LeanKeys/debug.log"))
        XCTAssertTrue(DebugLog.path.hasPrefix(FileManager.default.homeDirectoryForCurrentUser.path))
    }

    func testCharacterKeysNeverShowTheirCode() {
        // Letters, digits and punctuation on a US layout: every code that is not a control key.
        for code in UInt16(0)...UInt16(127) where !DebugLog.controlKeyCodes.contains(code) {
            XCTAssertEqual(DebugLog.keyLabel(code), "char", "key code \(code)")
        }
        for letter: UInt16 in [0, 1, 2, 12, 13, 14, 15, 16, 17, 31, 32, 34, 35, 37, 38, 40, 45, 46] {
            XCTAssertEqual(DebugLog.keyLabel(letter), "char")
        }
        for digit: UInt16 in [18, 19, 20, 21, 23, 22, 26, 28, 25, 29] {
            XCTAssertEqual(DebugLog.keyLabel(digit), "char")
        }
    }

    func testControlKeysKeepTheirCode() {
        XCTAssertEqual(DebugLog.keyLabel(51), "51")  // ⌫
        XCTAssertEqual(DebugLog.keyLabel(36), "36")  // Return
        XCTAssertEqual(DebugLog.keyLabel(49), "49")  // Space
        XCTAssertEqual(DebugLog.keyLabel(123), "123") // ←
    }

    func testTextIsWrittenAsItsLengthOnly() {
        XCTAssertEqual(DebugLog.redact(Array("mật khẩu")), "<8>")
        XCTAssertEqual(DebugLog.redact("hunter2"), "<7>")
        XCTAssertEqual(DebugLog.redact([Character]()), "<0>")
        XCTAssertFalse(DebugLog.redact("secret").contains("secret"))
    }
}
