import XCTest
@testable import LeanKeysKit

final class AdvancedTelexTests: XCTestCase {
    private static let keyCodes: [Character: UInt16] = [
        "a": 0, "b": 11, "c": 8, "d": 2, "e": 14, "f": 3, "g": 5, "h": 4, "i": 34, "j": 38, "k": 40, "l": 37,
        "m": 46, "n": 45, "o": 31, "p": 35, "q": 12, "r": 15, "s": 1, "t": 17, "u": 32, "v": 9, "w": 13, "x": 7,
        "y": 16, "z": 6, " ": 49,
    ]

    private func type(_ keys: String, using router: EngineRouter) -> String {
        var screen = ""
        for ch in keys {
            guard let code = Self.keyCodes[ch] else { continue }
            guard case .handled(let res) = router.intercept(keyCode: code, caps: false, ctrl: false, shift: false) else {
                continue
            }
            if let (bs, chars, consumed) = res {
                if bs > 0 { screen.removeLast(min(bs, screen.count)) }
                screen += String(chars)
                if !consumed { screen.append(ch) }
            } else {
                screen.append(ch)
            }
        }
        return screen
    }

    func testOffByDefaultAndExpandsWhenEnabled() {
        let suite = "AdvancedTelexTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let router = EngineRouter(defaults: defaults)
        router.setEnabled(true, explicit: true)
        XCTAssertFalse(router.advancedTelex)

        // Off: "kko " stays ASCII/Vikey default
        XCTAssertEqual(type("kko ", using: router), "kko ")
        router.clear()

        // On: initial consonant doubles expand cleanly
        router.advancedTelex = true
        XCTAssertEqual(type("ccao ", using: router), "chao ")
        router.clear()
        XCTAssertEqual(type("kkoong ", using: router), "không ")
        router.clear()
        XCTAssertEqual(type("nnayf ", using: router), "ngày ")
        router.clear()
        XCTAssertEqual(type("ttanhf ", using: router), "thành ")
        router.clear()
        XCTAssertEqual(type("qqa ", using: router), "qua ")
        router.clear()
        XCTAssertEqual(type("ppowr ", using: router), "phở ")
        router.clear()
        XCTAssertEqual(type("ggs ", using: router), "gí ")
    }
}
