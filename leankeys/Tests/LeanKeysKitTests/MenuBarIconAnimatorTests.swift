import AppKit
import XCTest
@testable import LeanKeysKit

final class MenuBarIconAnimatorTests: XCTestCase {
    func testNoTransitionWhenReduceMotion() {
        XCTAssertNil(MenuBarIconAnimator.transition(reduceMotion: true))
    }

    func testFadeTransition() {
        let transition = MenuBarIconAnimator.transition(reduceMotion: false)
        XCTAssertEqual(transition?.type, .fade)
        XCTAssertEqual(transition?.duration, 0.15)
    }
}
