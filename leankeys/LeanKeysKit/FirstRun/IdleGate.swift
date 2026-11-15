import CoreGraphics
import Foundation

/// True once no key has been pressed for `threshold` seconds. Gates the silent update install so it never lands
/// mid-typing (spec §13.2).
public struct IdleGate {
    private let threshold: TimeInterval
    private let secondsSinceLastKey: () -> TimeInterval

    /// `secondsSinceLastKey` defaults to the system-wide time since the last key down.
    public init(
        threshold: TimeInterval = 30,
        secondsSinceLastKey: @escaping () -> TimeInterval = {
            CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown)
        }
    ) {
        self.threshold = threshold
        self.secondsSinceLastKey = secondsSinceLastKey
    }

    /// Read fresh on every access.
    public var isIdle: Bool {
        secondsSinceLastKey() >= threshold
    }
}
