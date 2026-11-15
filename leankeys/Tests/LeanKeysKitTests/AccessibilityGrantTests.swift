import Combine
import XCTest
@testable import LeanKeysKit

final class AccessibilityGrantTests: XCTestCase {
    /// Stores the scheduled block so a test can tick it by hand; records whether the cancellable ran.
    private final class FakeSchedule {
        var block: (() -> Void)?
        var scheduleCount = 0
        var cancelled = false

        func schedule(_: TimeInterval, _ block: @escaping () -> Void) -> AnyCancellable {
            scheduleCount += 1
            self.block = block
            return AnyCancellable { [weak self] in self?.cancelled = true }
        }

        func tick() { block?() }
    }

    func testGrantedWhenEitherSignal() {
        XCTAssertTrue(AccessibilityGrant.isGranted(axTrusted: { true }, tapProbe: { false }))
        XCTAssertTrue(AccessibilityGrant.isGranted(axTrusted: { false }, tapProbe: { true }))
        XCTAssertFalse(AccessibilityGrant.isGranted(axTrusted: { false }, tapProbe: { false }))
    }

    func testProbeNotCalledWhenAXTrusted() {
        var probeCalls = 0
        let granted = AccessibilityGrant.isGranted(axTrusted: { true }, tapProbe: {
            probeCalls += 1
            return false
        })
        XCTAssertTrue(granted)
        XCTAssertEqual(probeCalls, 0)
    }

    func testWatcherFiresOnce() {
        var answers = [false, false, true, true]
        var grantedCalls = 0
        let schedule = FakeSchedule()
        let watcher = GrantWatcher(
            interval: 1,
            isGranted: { answers.isEmpty ? true : answers.removeFirst() },
            onGranted: { grantedCalls += 1 },
            schedule: schedule.schedule
        )
        watcher.start()
        watcher.tick()
        watcher.tick()
        watcher.tick()
        watcher.tick()
        watcher.fireIfGranted()
        XCTAssertEqual(grantedCalls, 1)
    }

    func testWatcherStopsAfterFiring() {
        let schedule = FakeSchedule()
        var grantedCalls = 0
        let watcher = GrantWatcher(
            interval: 1,
            isGranted: { true },
            onGranted: { grantedCalls += 1 },
            schedule: schedule.schedule
        )
        watcher.start()
        XCTAssertFalse(schedule.cancelled)
        watcher.tick()
        XCTAssertTrue(schedule.cancelled)
        XCTAssertEqual(grantedCalls, 1)
    }

    func testStartSchedulesOnlyOnce() {
        let schedule = FakeSchedule()
        let watcher = GrantWatcher(interval: 1, isGranted: { false }, onGranted: {}, schedule: schedule.schedule)
        watcher.start()
        watcher.start()
        XCTAssertEqual(schedule.scheduleCount, 1)
        watcher.stop()
        watcher.stop()
        XCTAssertTrue(schedule.cancelled)
    }
}

/// I1: the relaunch after a grant may happen at most once per 60 s, so a bad state cannot loop the app.
final class GrantRelaunchGuardTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testFirstRelaunchIsAllowed() {
        XCTAssertTrue(GrantWatcher.shouldRelaunch(last: nil, now: now))
    }

    func testRelaunchWithinSixtySecondsIsRefused() {
        XCTAssertFalse(GrantWatcher.shouldRelaunch(last: now.addingTimeInterval(-1), now: now))
        XCTAssertFalse(GrantWatcher.shouldRelaunch(last: now.addingTimeInterval(-59.9), now: now))
    }

    func testRelaunchAtOrAfterSixtySecondsIsAllowed() {
        XCTAssertTrue(GrantWatcher.shouldRelaunch(last: now.addingTimeInterval(-60), now: now))
        XCTAssertTrue(GrantWatcher.shouldRelaunch(last: now.addingTimeInterval(-600), now: now))
    }
}
