import AppKit

/// Crossfades the menu bar icon when its letter changes (V to E, or Telex to a non-ABC character).
public enum MenuBarIconAnimator {
    static let key = "leankeys.icon"

    /// The fade to run before an icon change. nil when Reduce Motion is on, so the icon changes at once.
    public static func transition(reduceMotion: Bool) -> CATransition? {
        guard !reduceMotion else { return nil }
        let transition = CATransition()
        transition.type = .fade
        transition.duration = 0.15
        return transition
    }

    /// Call right before setting `button.image`. Adds the fade to the button's layer for the next change.
    public static func prepare(
        _ button: NSStatusBarButton,
        reduceMotion: Bool = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    ) {
        button.wantsLayer = true
        guard let transition = transition(reduceMotion: reduceMotion) else {
            button.layer?.removeAnimation(forKey: key)
            return
        }
        button.layer?.add(transition, forKey: key)
    }
}
