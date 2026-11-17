import Foundation

/// Decides whether typist may post keys right now.
public enum Guard {
    public static let requiredLayoutID = "com.apple.keylayout.US"

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
        return layoutID == requiredLayoutID
    }
}
