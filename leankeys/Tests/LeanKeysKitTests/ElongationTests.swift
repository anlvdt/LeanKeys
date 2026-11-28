import XCTest
@testable import LeanKeysKit

final class ElongationTests: XCTestCase {
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

    func testChatElongationCases() {
        let suite = "ElongationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let router = EngineRouter(defaults: defaults)
        router.setEnabled(true, explicit: true)
        router.resetWordAfterPrediction(deleteCount: 0, inserted: [])

        // Toned vowel repeated twice -> keeps tone and elongates, stays Vietnamese after Space
        XCTAssertEqual(type("nhesee ", using: router), "nhéee ")
        XCTAssertTrue(router.currentVietnamese)

        router.clear()
        XCTAssertEqual(type("haraa ", using: router), "hảaa ")

        router.clear()
        XCTAssertEqual(type("asaaa ", using: router), "áaaa ")

        router.clear()
        XCTAssertEqual(type("asaaaa ", using: router), "áaaaa ")

        // Vietnamese word with non-ASCII letter + 3 trailing vowels -> ôiii, ơiii
        router.clear()
        XCTAssertEqual(type("ooiii ", using: router), "ôiii ")

        router.clear()
        XCTAssertEqual(type("owiii ", using: router), "ơiii ")
    }

    func testEnglishWordsWithDoubleVowelsUntouched() {
        let suite = "ElongationEnTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let router = EngineRouter(defaults: defaults)
        router.setEnabled(true, explicit: true)

        XCTAssertEqual(type("see ", using: router), "see ")
        router.clear()
        XCTAssertEqual(type("tree ", using: router), "tree ")
        router.clear()
        XCTAssertEqual(type("good ", using: router), "good ")
    }
}
