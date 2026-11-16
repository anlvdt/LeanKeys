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

    private final class UpdateStub {
        var phase: PopoverUpdateRow.Phase = .idle
        var checks = 0
        var installs = 0
        var closes = 0

        var actions: StatusPopoverActions {
            StatusPopoverActions(
                snapshot: { StatusSnapshot(vietnamese: true, autoSwitchApplies: false, autoSwitchOn: false, blocked: false, blockingApp: nil) },
                method: { 0 },
                updateReady: { false },
                setVietnamese: { _ in },
                setMethod: { _ in },
                installUpdate: { self.installs += 1 },
                openSettings: {},
                quit: {},
                updatePhase: { self.phase },
                checkForUpdates: { self.checks += 1; self.phase = .checking },
                popoverClosed: { self.closes += 1 }
            )
        }
    }

    func testUpdateRowTapChecksThenShowsProgress() {
        let stub = UpdateStub()
        let model = StatusPopoverModel(actions: stub.actions)
        model.tapUpdateRow()
        XCTAssertEqual(stub.checks, 1)
        XCTAssertEqual(model.updatePhase, .checking, "the row changes at once")

        model.tapUpdateRow()
        XCTAssertEqual(stub.checks, 1, "a click while checking does nothing")

        stub.phase = .downloading(progress: 0.3)
        model.reload()
        XCTAssertEqual(model.updatePhase, .downloading(progress: 0.3))
        model.tapUpdateRow()
        XCTAssertEqual(stub.checks, 1)
        XCTAssertEqual(stub.installs, 0)
    }

    func testUpdateRowReadyInstallsAndFailureRetries() {
        let stub = UpdateStub()
        stub.phase = .ready
        let model = StatusPopoverModel(actions: stub.actions)
        model.tapUpdateRow()
        XCTAssertEqual(stub.installs, 1)

        stub.phase = .failed(.network)
        model.reload()
        model.tapUpdateRow()
        XCTAssertEqual(stub.checks, 1)
    }

    func testClosingThePopoverIsReported() {
        let stub = UpdateStub()
        let model = StatusPopoverModel(actions: stub.actions)
        model.popoverDidClose()
        XCTAssertEqual(stub.closes, 1)
    }

    func testWithoutUpdatePhaseFallsBackToUpdateReady() {
        let stub = Stub()
        let model = StatusPopoverModel(actions: stub.actions)
        XCTAssertEqual(model.updatePhase, .idle)
        stub.updateReady = true
        model.reload()
        XCTAssertEqual(model.updatePhase, .ready)
    }
}
