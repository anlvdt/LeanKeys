import Foundation

/// Decides whether typist may post keys right now.
public enum Guard {
    /// The layout typist types on. ABC is macOS's default English layout; it has the same key
    /// codes as US for every key typist sends, so both are accepted.
    public static let requiredLayoutID = "com.apple.keylayout.US"
    public static let acceptedLayoutIDs: Set<String> = [requiredLayoutID, "com.apple.keylayout.ABC"]

    public static func layoutAccepted(_ layoutID: String) -> Bool {
        acceptedLayoutIDs.contains(layoutID)
    }

    public static func mayType(
        frontBundle: String?,
        windowTitle: String?,
        expectedBundle: String,
        token: String,
        layoutID: String
    ) -> Bool {
        guard !token.isEmpty else { return false }
        guard let bundle = frontBundle, bundle == expectedBundle else { return false }
        guard let title = windowTitle, title.contains("webbench-\(token)-ready") else { return false }
        return layoutAccepted(layoutID)
    }
}
