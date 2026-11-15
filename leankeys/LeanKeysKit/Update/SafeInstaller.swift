import Foundation

/// The unattended update install (spec §13.2, §8 "never silently stop working"). Unlike Gõ Nhanh's
/// restartToUpdate it checks the update before quitting, and its swap script always relaunches an app.
///
/// Order: `prepare` mounts the DMG read-only and `verify`s it (LeanKeys.app at the root, same bundle ID as the
/// running app, `codesign --verify --deep --strict` passes; for a silent install also the running app's designated
/// requirement); on failure it detaches and reports why, and the caller keeps running. `launchSwap` then starts
/// swap-update.sh; the caller quits only if that process started.
public enum SafeInstaller {
    public enum Verdict: Equatable {
        case valid(URL)
        case missingApp
        case wrongBundleID(found: String?)
        case codesignFailed
        /// Silent install only: the candidate is signed with a different identity than the running app.
        case differentIdentity
    }

    /// Outcome of `prepare`. `rejected` and `unmounted` have already detached the image.
    public enum Preparation {
        case prepared(Prepared)
        case rejected(Verdict)
        case unmounted
    }

    /// The checks `verify` runs, injectable for tests.
    public struct Checks {
        public var appExists: (URL) -> Bool
        public var bundleIdentifier: (URL) -> String?
        public var codesignValid: (URL) -> Bool
        /// True when the app satisfies the running app's designated requirement (UpdateInstallPolicy).
        public var sameIdentity: (URL) -> Bool

        public init(appExists: @escaping (URL) -> Bool, bundleIdentifier: @escaping (URL) -> String?,
                    codesignValid: @escaping (URL) -> Bool, sameIdentity: @escaping (URL) -> Bool)
        {
            self.appExists = appExists
            self.bundleIdentifier = bundleIdentifier
            self.codesignValid = codesignValid
            self.sameIdentity = sameIdentity
        }

        public static let live = Checks(
            appExists: { url in
                var isDir: ObjCBool = false
                return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
            },
            bundleIdentifier: { url in
                NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist"))?["CFBundleIdentifier"] as? String
            },
            codesignValid: { url in
                SafeInstaller.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", url.path]).status == 0
            },
            sameIdentity: { url in UpdateInstallPolicy.candidateMatchesRunningIdentity(url) }
        )
    }

    /// A mounted, verified update.
    public struct Prepared {
        public let mountPoint: URL
        public let app: URL
    }

    /// Decides whether `<mountPoint>/<appName>.app` may replace the running app. Stops at the first failed check.
    /// A nil `expectedBundleID` (nothing to compare against) is a rejection. `requireSameIdentity` (silent installs)
    /// adds the designated-requirement check, run last.
    public static func verify(mountPoint: URL, appName: String, expectedBundleID: String?, checks: Checks,
                              requireSameIdentity: Bool = false) -> Verdict
    {
        let app = mountPoint.appendingPathComponent("\(appName).app")
        guard checks.appExists(app) else { return .missingApp }
        let found = checks.bundleIdentifier(app)
        guard let expectedBundleID, found == expectedBundleID else { return .wrongBundleID(found: found) }
        guard checks.codesignValid(app) else { return .codesignFailed }
        if requireSameIdentity, !checks.sameIdentity(app) { return .differentIdentity }
        return .valid(app)
    }

    /// A 2xx HTTP response, or a non-HTTP one (nothing to reject). An error page saved as the DMG fails here.
    public static func isSuccessfulDownload(_ response: URLResponse?) -> Bool {
        guard let response else { return false }
        guard let http = response as? HTTPURLResponse else { return true }
        return (200 ..< 300).contains(http.statusCode)
    }

    /// The swap script shipped in the kit's resources.
    public static var swapScriptURL: URL? {
        Bundle.module.url(forResource: "swap-update", withExtension: "sh")
    }

    /// Mounts `dmg` read-only and verifies it. Blocking (hdiutil, codesign): call off the main thread.
    /// On any failure the image is detached, the reason is logged, and the outcome says which check failed.
    public static func prepare(dmg: URL, appName: String, expectedBundleID: String?, requireSameIdentity: Bool = false,
                               checks: Checks = .live) -> Preparation
    {
        guard let mount = mount(dmg) else {
            log("could not mount \(dmg.path)")
            return .unmounted
        }
        let verdict = verify(mountPoint: mount, appName: appName, expectedBundleID: expectedBundleID, checks: checks,
                             requireSameIdentity: requireSameIdentity)
        guard case let .valid(app) = verdict else {
            log("rejected update \(dmg.path): \(verdict)")
            detach(mount)
            return .rejected(verdict)
        }
        return .prepared(Prepared(mountPoint: mount, app: app))
    }

    /// Starts the swap script for `prepared` (it waits for `pid` to exit). Returns false, with the image detached,
    /// if the script could not be started; the caller must then keep running.
    public static func launchSwap(_ prepared: Prepared, dmg: URL, installedApp: URL,
                                  pid: Int32 = ProcessInfo.processInfo.processIdentifier) -> Bool
    {
        // Run a copy: the bundle holding the original is about to be replaced.
        let script = FileManager.default.temporaryDirectory.appendingPathComponent("leankeys-swap-update.sh")
        do {
            guard let source = swapScriptURL else { throw CocoaError(.fileNoSuchFile) }
            try? FileManager.default.removeItem(at: script)
            try FileManager.default.copyItem(at: source, to: script)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [script.path, prepared.app.path, installedApp.path, prepared.mountPoint.path, dmg.path, String(pid)]
            try process.run()
            return true
        } catch {
            log("could not start the swap script: \(error)")
            detach(prepared.mountPoint)
            return false
        }
    }

    public static func detach(_ mountPoint: URL) {
        _ = run("/usr/bin/hdiutil", ["detach", mountPoint.path, "-quiet"])
    }

    // MARK: - Private

    private static func mount(_ dmg: URL) -> URL? {
        let result = run("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-readonly", "-noautoopen", "-plist"])
        guard result.status == 0,
              let plist = try? PropertyListSerialization.propertyList(from: result.output, format: nil) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]],
              let path = entities.compactMap({ $0["mount-point"] as? String }).first
        else { return nil }
        return URL(fileURLWithPath: path)
    }

    static func run(_ tool: String, _ arguments: [String]) -> (status: Int32, output: Data) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return (-1, Data()) }
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, output)
    }

    private static func log(_ message: String) {
        NSLog("[LeanKeys] update: \(message)")
    }
}
