import Foundation

/// Terminals and code editors: apps where typed text is code or a command. There `\` before Enter is meant
/// (spec 17.2), and case matters (a branch, a path, an identifier), so nothing is capitalised (spec 17.1, ruling R12).
/// The one list both features read. JetBrains IDEs match by prefix.
public enum CodeApps {
    /// Terminals. `Exclusions.defaultBundleIDs` reads this list too (passwords are typed there without a secure
    /// field), so the two never drift apart.
    public static let terminals: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "dev.warp.Warp-Preview",
        "com.mitchellh.ghostty", "org.alacritty", "io.alacritty", "net.kovidgoyal.kitty", "com.github.wez.wezterm",
        "co.zeit.hyper", "org.tabby",
    ]
    public static let bundleIDs: Set<String> = terminals.union([
        // Code editors.
        "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.todesktop.230313mzl4w4u92", "com.todesktop.cursor",
        "com.exafunction.windsurf", "dev.zed.Zed", "dev.zed.Zed-Preview", "com.apple.dt.Xcode", "com.sublimetext.4",
        "com.sublimetext.3", "com.panic.Nova", "com.barebones.bbedit", "com.google.android.studio",
    ])
    static let bundlePrefix = "com.jetbrains."

    public static func contains(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return bundleIDs.contains(bundleID) || bundleID.hasPrefix(bundlePrefix)
    }
}
