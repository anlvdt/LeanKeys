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

    // MARK: Security audit LOW-2: the log switches itself off after a day

    func testStaleLogIsRemoved() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("debug.log").path
        let created = Date(timeIntervalSince1970: 1_800_000_000)
        FileManager.default.createFile(atPath: file, contents: Data("I: x".utf8),
                                       attributes: [.creationDate: created])

        XCTAssertTrue(DebugLog.isOnAfterExpiry(path: file, keepPath: file + ".keep", now: created.addingTimeInterval(23 * 3600)))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file))
        XCTAssertFalse(DebugLog.isOnAfterExpiry(path: file, keepPath: file + ".keep", now: created.addingTimeInterval(25 * 3600)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file), "a log older than a day is deleted")
        XCTAssertFalse(DebugLog.isOnAfterExpiry(path: file, keepPath: file + ".keep", now: created))
    }

    /// Spec 2026-11-28-privacy-opt-in §4: on the developer's Mac a `debug.keep` file keeps the log past a day.
    func testKeepFileKeepsLogOn() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("debug.log").path
        let keep = dir.appendingPathComponent("debug.keep").path
        let created = Date(timeIntervalSince1970: 1_800_000_000)
        FileManager.default.createFile(atPath: file, contents: Data(), attributes: [.creationDate: created])
        FileManager.default.createFile(atPath: keep, contents: Data())
        XCTAssertTrue(DebugLog.isOnAfterExpiry(path: file, keepPath: keep, now: created.addingTimeInterval(30 * 24 * 3600)))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file))
        XCTAssertEqual(DebugLog.keepPath, (DebugLog.path as NSString).deletingLastPathComponent + "/debug.keep")
    }
}
