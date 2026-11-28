import Foundation

/// Which events count as the user's own input. Typist and LeanKeys tag the events they post
/// with these markers in eventSourceUserData; anything else is real keyboard or mouse input.
public enum InputSource {
    public static let ownMarker: Int64 = 0x5745_4242       // "WEBB": typist's own events
    public static let leanKeysMarker: Int64 = 0x474E_4820  // "GNH ": LeanKeys' reposted events

    public static func isForeign(marker: Int64) -> Bool {
        marker != ownMarker && marker != leanKeysMarker
    }
}
