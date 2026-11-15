import Foundation

/// One-time setup on the first launch (spec §13.2): launch at login, on without asking.
public enum FirstRun {
    public static let doneKey = "LeanKeys.firstRunDone"

    /// Calls `enableLaunchAtLogin` and sets "LeanKeys.firstRunDone", once. If it throws, the flag stays unset so
    /// the next launch tries again; the error is not surfaced (no dialog on first run).
    public static func performIfNeeded(defaults: UserDefaults = .standard, enableLaunchAtLogin: () throws -> Void) {
        guard !defaults.bool(forKey: doneKey) else { return }
        do {
            try enableLaunchAtLogin()
            defaults.set(true, forKey: doneKey)
        } catch {
            NSLog("[LeanKeys] launch at login not enabled, will retry next launch: \(error)")
        }
    }
}
