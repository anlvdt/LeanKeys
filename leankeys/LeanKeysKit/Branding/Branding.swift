import Foundation

/// LeanKeys' own name and links. The app's AppMetadata, UpdateChecker and UpdateManager read these through the
/// `branding` hook, so Gõ Nhanh's sources keep their own values everywhere else.
public enum LeanBranding {
    public static let name = "LeanKeys"
    public static let repository = "https://github.com/anlvdt/LeanKeys"
    /// GitHub's list endpoint, not /latest, so UpdateChecker can pick the highest version.
    public static let releasesAPI = "https://api.github.com/repos/anlvdt/LeanKeys/releases"
    public static let issuesURL = repository + "/issues"
}

/// LeanKeys' own version and the upstream tags it is built from, read from Resources/Versions.json.
public enum LeanVersions {
    private struct File: Decodable {
        let leankeys: String
        let gonhanh: String
        let vikey: String
    }

    /// Falls back to "?" for each field if Versions.json cannot be read or decoded, so the About screen still renders.
    public static func load() -> (leankeys: String, gonhanh: String, vikey: String) {
        guard let url = Bundle.module.url(forResource: "Versions", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data)
        else { return ("?", "?", "?") }
        return (file.leankeys, file.gonhanh, file.vikey)
    }

    /// "Gõ Nhanh v1.0.165 · Vikey v1.0.33"
    public static var engineLine: String {
        let v = load()
        return "Gõ Nhanh \(v.gonhanh) · Vikey \(v.vikey)"
    }
}

/// The projects LeanKeys is built from, shown on the About screen and in ACKNOWLEDGEMENTS.md.
public enum LeanAcknowledgements {
    public struct Credit: Identifiable {
        public let name: String
        public let authors: String
        public let role: String
        public let repository: String
        public let license: String
        public var id: String { name }
    }

    public static let credits: [Credit] = [
        Credit(name: "Gõ Nhanh", authors: "khaphanspace và cộng đồng Gõ Nhanh",
               role: "nền tảng của LeanKeys: ứng dụng, giao diện và engine mặc định",
               repository: "https://github.com/khaphanspace/gonhanh.org", license: "BSD-3-Clause"),
        Credit(name: "Vikey", authors: "Tony Dinh",
               role: "engine Vikey, tự chuyển Việt/Anh theo ngữ cảnh",
               repository: "https://github.com/tonyminibot/Vikey", license: "GPL-3.0"),
        Credit(name: "OpenKey", authors: "Mai Vũ Tuyên",
               role: "nguồn gốc engine của Vikey",
               repository: "https://github.com/tuyenvm/OpenKey", license: "GPL-3.0"),
    ]

    /// LeanKeys' own licence.
    public static let leanKeysLicense = "GPL-3.0"

    public static var text: String {
        let lines = credits.map { "\($0.name) — \($0.authors) (\($0.license)): \($0.role). \($0.repository)" }
        return (lines + ["\(LeanBranding.name) phát hành theo giấy phép \(leanKeysLicense)."]).joined(separator: "\n")
    }
}
