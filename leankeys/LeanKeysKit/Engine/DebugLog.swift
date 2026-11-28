import Foundation

/// Where Gõ Nhanh's debug key log lives, and what it may say (spec §18.2).
///
/// Upstream writes the log to `/tmp/gonhanh_debug.log` whenever that file exists. `/tmp` is shared by every user and
/// process, so anything on the Mac could switch the log on and read each key typed, with its character. LeanKeys keeps
/// the log in the user's own `~/Library/Logs/LeanKeys` (folder 0700, file 0600) and never writes a typed character or
/// the key code of a character key into it: only control keys keep their code, and text is written as its length.
/// What remains visible is typing rhythm and word lengths, which the log needs to be of any use.
public enum DebugLog {
    /// `~/Library/Logs/LeanKeys/debug.log`.
    public static let path: String = {
        let logs = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/LeanKeys", isDirectory: true)
        return logs.appendingPathComponent("debug.log").path
    }()

    /// Key codes that name no character: Return, Enter, Tab, Space, ⌫, Esc, forward delete, arrows, Home, End,
    /// Page Up, Page Down.
    static let controlKeyCodes: Set<UInt16> = [36, 76, 48, 49, 51, 53, 117, 123, 124, 125, 126, 115, 119, 116, 121]

    /// The key as the log may show it: control keys by code, every other key as `char`.
    public static func keyLabel(_ code: UInt16) -> String {
        controlKeyCodes.contains(code) ? String(code) : "char"
    }

    /// Text as the log may show it: its length only.
    public static func redact<S: Collection>(_ text: S) -> String where S.Element == Character {
        "<\(text.count)>"
    }

    /// Whether the log is on (the file exists).
    public static var isOn: Bool { FileManager.default.fileExists(atPath: path) }

    /// How long the log stays on once switched on (security audit LOW-2): any process of the same user can create
    /// the file, so a log nobody remembers switching on must not keep recording typing rhythm.
    public static let maxAge: TimeInterval = 24 * 3600

    /// `~/Library/Logs/LeanKeys/debug.keep`: on the developer's own Mac only, this file keeps the log on past `maxAge`
    /// (spec 2026-11-28-privacy-opt-in §4). The app never creates it and a release never ships it; like the log file it
    /// sits in the user's 0700 folder, so only the user's own processes can create it.
    public static let keepPath: String = ((path as NSString).deletingLastPathComponent as NSString)
        .appendingPathComponent("debug.keep")

    /// The switch's subtitle in Nâng cao (one line; the full path is in its tooltip).
    public static let settingsSubtitle = "Chỉ ghi trên máy này, không chứa chữ bạn gõ, không gửi đi đâu"

    /// Whether the log is on, after deleting a log file created more than `maxAge` ago (unless `keepPath` exists).
    /// Read once at launch and on each refresh of the log switch.
    public static func isOnAfterExpiry(path: String = path, keepPath: String = keepPath, now: Date = Date()) -> Bool {
        let fm = FileManager.default
        guard let attributes = try? fm.attributesOfItem(atPath: path) else { return false }
        if !fm.fileExists(atPath: keepPath), let created = attributes[.creationDate] as? Date,
           now.timeIntervalSince(created) > maxAge {
            try? fm.removeItem(atPath: path)
            return false
        }
        return true
    }

    /// Switches the log on (creates the folder 0700 and an empty file 0600) or off (removes the file).
    public static func setOn(_ on: Bool) {
        let fm = FileManager.default
        if on {
            let folder = (path as NSString).deletingLastPathComponent
            try? fm.createDirectory(atPath: folder, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
            try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder)
            if !fm.fileExists(atPath: path) {
                fm.createFile(atPath: path, contents: nil, attributes: [.posixPermissions: 0o600])
            }
        } else {
            try? fm.removeItem(atPath: path)
        }
    }

    /// Maximum log size on disk (10 MB) before truncating so a long-lived debug.keep log cannot fill the disk.
    public static let maxBytes: UInt64 = 10 * 1024 * 1024

    /// Appends `line` using throwing FileHandle APIs (safe against Obj-C exceptions on disk-full) and truncates
    /// if the file reached `maxBytes`.
    public static func appendLine(_ line: String, path: String = path, maxBytes: UInt64 = maxBytes) {
        guard let data = line.data(using: .utf8),
              let handle = FileHandle(forWritingAtPath: path) else { return }
        defer { try? handle.close() }
        if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
           let size = attrs[.size] as? UInt64, size >= maxBytes {
            try? handle.truncate(atOffset: 0)
        }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }

    /// Empties the log, keeping it on.
    public static func clear() {
        guard isOn, let handle = FileHandle(forWritingAtPath: path) else { return }
        try? handle.truncate(atOffset: 0)
        try? handle.close()
    }
}
