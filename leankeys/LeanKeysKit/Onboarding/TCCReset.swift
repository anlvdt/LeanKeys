import Foundation

/// Resets only LeanKeys' own Accessibility entry (spec §15), so a returning user can re-grant with one click.
public enum TCCReset {
    static let tccutilURL = URL(fileURLWithPath: "/usr/bin/tccutil")

    public static func arguments(bundleID: String) -> [String] {
        ["reset", "Accessibility", bundleID]
    }

    /// Runs `tccutil` and returns true when it exits with status 0.
    public static func run(bundleID: String,
                           runner: (URL, [String]) -> Int32 = defaultRunner) -> Bool
    {
        // An empty ID would make tccutil reset without a bundle filter: refuse, never run it.
        guard !bundleID.isEmpty else { return false }
        return runner(tccutilURL, arguments(bundleID: bundleID)) == 0
    }

    /// Runs the tool and waits for it. `tccutil` returns fast, so the wait is short and acceptable on the main
    /// thread. A missing binary or a launch error returns a non-zero status and never throws.
    public static func defaultRunner(_ url: URL, _ args: [String]) -> Int32 {
        guard FileManager.default.isExecutableFile(atPath: url.path) else { return 127 }
        let process = Process()
        process.executableURL = url
        process.arguments = args
        do {
            try process.run()
        } catch {
            return 1
        }
        process.waitUntilExit()
        return process.terminationStatus
    }
}
