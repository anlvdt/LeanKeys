import XCTest
@testable import LeanKeysKit

final class ConvertKeyDefaultTests: XCTestCase {
    private struct Shortcut: Codable { let keyCode: UInt16; let modifiers: UInt64 }
    private var suite = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suite = "ConvertKeyDefaultTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testWritesOnce() throws {
        XCTAssertTrue(ConvertKeyDefault.apply(defaults, shortcutKey: "s", enabledKey: "e"))
        let data = try XCTUnwrap(defaults.data(forKey: "s"))
        let decoded = try JSONDecoder().decode(Shortcut.self, from: data)
        XCTAssertEqual(decoded.keyCode, 51)
        XCTAssertEqual(decoded.modifiers, 262144)
        XCTAssertTrue(defaults.bool(forKey: "e"))
        XCTAssertFalse(ConvertKeyDefault.apply(defaults, shortcutKey: "s", enabledKey: "e"))
    }

    func testDoesNotReapplyAfterTheUserTurnedItOff() {
        XCTAssertTrue(ConvertKeyDefault.apply(defaults, shortcutKey: "s", enabledKey: "e"))
        defaults.set(false, forKey: "e")
        defaults.removeObject(forKey: "s")
        XCTAssertFalse(ConvertKeyDefault.apply(defaults, shortcutKey: "s", enabledKey: "e"))
        XCTAssertNil(defaults.data(forKey: "s"))
    }

    func testExistingShortcutIsKept() {
        let mine = Data("mine".utf8)
        defaults.set(mine, forKey: "s")
        XCTAssertFalse(ConvertKeyDefault.apply(defaults, shortcutKey: "s", enabledKey: "e"))
        XCTAssertEqual(defaults.data(forKey: "s"), mine)
        XCTAssertFalse(defaults.bool(forKey: "e"))
    }
}
