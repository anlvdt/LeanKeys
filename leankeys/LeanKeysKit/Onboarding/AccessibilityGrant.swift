import ApplicationServices
import Combine
import CoreGraphics
import Foundation

/// Accessibility detection and the Settings prompt for the one-click grant (spec §15).
public enum AccessibilityGrant {
    public static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    /// Granted when either signal says so. `tapProbe` runs only when `axTrusted` is false.
    public static func isGranted(axTrusted: () -> Bool, tapProbe: () -> Bool) -> Bool {
        if axTrusted() { return true }
        return tapProbe()
    }

    /// Tries to create a keyboard tap and reports whether that worked.
    ///
    /// The tap is `.defaultTap`, not `.listenOnly` (ruling R2). A listen-only keyboard tap is gated by Input
    /// Monitoring, so creating one while untrusted can raise a second permission dialog every second. An active
    /// tap is gated by Accessibility: it fails (returns nil) while untrusted and raises no extra prompt. The tap
    /// is never added to a run loop and never enabled; it is invalidated at once.
    public static func probeEventTap() -> Bool {
        let keyDownMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: keyDownMask,
            callback: { _, _, event, _ in Unmanaged.passUnretained(event) },
            userInfo: nil
        ) else { return false }
        CFMachPortInvalidate(tap)
        return true
    }

    /// Asks macOS to show its Accessibility prompt.
    public static func requestPrompt() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}

/// Polls `isGranted` every `interval` seconds and calls `onGranted` exactly once, then stops.
public final class GrantWatcher {
    public typealias Schedule = (TimeInterval, @escaping () -> Void) -> AnyCancellable

    private let interval: TimeInterval
    private let isGranted: () -> Bool
    private let onGranted: () -> Void
    private let schedule: Schedule
    private var cancellable: AnyCancellable?
    private var fired = false

    public init(interval: TimeInterval = 1,
                isGranted: @escaping () -> Bool,
                onGranted: @escaping () -> Void,
                schedule: @escaping Schedule = GrantWatcher.mainRunLoopTimer)
    {
        self.interval = interval
        self.isGranted = isGranted
        self.onGranted = onGranted
        self.schedule = schedule
    }

    /// Default scheduler: a repeating timer on the main run loop in `.common` mode, so it keeps firing during menus
    /// and window drags.
    public static func mainRunLoopTimer(_ interval: TimeInterval, _ block: @escaping () -> Void) -> AnyCancellable {
        let timer = Timer(timeInterval: interval, repeats: true) { _ in block() }
        RunLoop.main.add(timer, forMode: .common)
        return AnyCancellable { timer.invalidate() }
    }

    public func start() {
        guard cancellable == nil, !fired else { return }
        cancellable = schedule(interval) { [weak self] in self?.tick() }
    }

    public func stop() {
        cancellable?.cancel()
        cancellable = nil
    }

    /// One poll. Fires `onGranted` on the first grant only.
    public func tick() {
        guard !fired, isGranted() else { return }
        fire()
    }

    /// Fires `onGranted` if granted and not yet fired. Routed through the same once-guard as `tick()`.
    public func fireIfGranted() {
        guard !fired, isGranted() else { return }
        fire()
    }

    private func fire() {
        fired = true
        stop()
        onGranted()
    }
}
