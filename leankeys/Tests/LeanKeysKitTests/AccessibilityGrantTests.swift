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
