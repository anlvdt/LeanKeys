import AppKit
import XCTest
@testable import LeanKeysKit

final class StatusPopoverTests: XCTestCase {
    /// Records every call the popover model makes, and serves a snapshot the test can change.
    private final class Stub {
        var vietnamese = true
        var method = 0
        var updateReady = false
        var setVietnameseCalls: [Bool] = []
        var setMethodCalls: [Int] = []

        var actions: StatusPopoverActions {
            StatusPopoverActions(
                snapshot: { StatusSnapshot(vietnamese: self.vietnamese, autoSwitchApplies: false, autoSwitchOn: false, blocked: false, blockingApp: nil) },
                method: { self.method },
                updateReady: { self.updateReady },
                setVietnamese: { self.setVietnameseCalls.append($0) },
                setMethod: { self.setMethodCalls.append($0) },
                installUpdate: {},
                openSettings: {},
                quit: {}
            )
        }
    }

    func testDoesNotReopenRightAfterTransientClose() {
        let now = Date()
        XCTAssertTrue(StatusPopoverController.shouldOpen(lastClose: nil, now: now))
        XCTAssertFalse(StatusPopoverController.shouldOpen(lastClose: now.addingTimeInterval(-0.1), now: now))
        XCTAssertTrue(StatusPopoverController.shouldOpen(lastClose: now.addingTimeInterval(-0.5), now: now))
    }

    func testRouteLeftClickOpensPopover() {
        XCTAssertEqual(StatusClickRoute.route(type: .leftMouseUp, modifiers: []), .popover)
    }

    func testRouteRightOrOptionClickOpensLegacyMenu() {
        XCTAssertEqual(StatusClickRoute.route(type: .rightMouseUp, modifiers: []), .legacyMenu)
        XCTAssertEqual(StatusClickRoute.route(type: .leftMouseUp, modifiers: .option), .legacyMenu)
    }

    func testRouteControlClickOpensLegacyMenu() {
        XCTAssertEqual(StatusClickRoute.route(type: .leftMouseUp, modifiers: .control), .legacyMenu)
    }

    func testChooseVietnameseOnlyCallsWhenDifferent() {
        let stub = Stub()
        stub.vietnamese = true
        let model = StatusPopoverModel(actions: stub.actions)

        model.choose(vietnamese: true)
        XCTAssertTrue(stub.setVietnameseCalls.isEmpty)

        model.choose(vietnamese: false)
        XCTAssertEqual(stub.setVietnameseCalls, [false])
    }

    func testReloadPicksUpAutomaticSwitch() {
        let stub = Stub()
        stub.vietnamese = true
        let model = StatusPopoverModel(actions: stub.actions)
        XCTAssertTrue(model.snapshot.vietnamese)

        stub.vietnamese = false
        model.reload()
        XCTAssertFalse(model.snapshot.vietnamese)
    }

    func testUpdateButtonOnlyWhenReady() {
        let stub = Stub()
        let model = StatusPopoverModel(actions: stub.actions)
        XCTAssertFalse(model.updateReady)

        stub.updateReady = true
        model.reload()
        XCTAssertTrue(model.updateReady)
    }
}
