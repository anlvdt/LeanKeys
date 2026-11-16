import Foundation
import LeanKeysKit // LEANKEYS-HOOK: branding

// MARK: - FFI for Version Comparison

@_silgen_name("version_compare")
func version_compare(_ v1: UnsafePointer<CChar>?, _ v2: UnsafePointer<CChar>?) -> Int32

@_silgen_name("version_has_update")
func version_has_update(_ current: UnsafePointer<CChar>?, _ latest: UnsafePointer<CChar>?) -> Int32

// MARK: - Update Info

struct UpdateInfo {
    let version: String
    let downloadURL: URL
    let releaseNotes: String
    let publishedAt: Date?
}

// MARK: - Update Check Result

enum UpdateCheckResult {
    case available(UpdateInfo)
    case upToDate
    case error(String)
}

// MARK: - Update Checker

class UpdateChecker {
    static let shared = UpdateChecker()

    /// Use /releases instead of /releases/latest to get highest version, not most recent publish
    private let githubAPIURL = LeanBranding.releasesAPI // LEANKEYS-HOOK: branding

    private init() {}

    /// Check for updates asynchronously
    func checkForUpdates(completion: @escaping (UpdateCheckResult) -> Void) {
        guard let url = URL(string: githubAPIURL) else {
            completion(.error("Không đọc được phản hồi của máy chủ cập nhật. Thử lại sau.")) // LEANKEYS-HOOK: copy
            return
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error {
                DispatchQueue.main.async {
                    completion(.error("Không kết nối được máy chủ cập nhật. Kiểm tra mạng rồi thử lại.")) // LEANKEYS-HOOK: copy
                }
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                DispatchQueue.main.async {
                    completion(.error("Không đọc được phản hồi của máy chủ cập nhật. Thử lại sau.")) // LEANKEYS-HOOK: copy
                }
                return
            }

            guard httpResponse.statusCode == 200 else {
                DispatchQueue.main.async {
                    completion(.error("Máy chủ cập nhật đang bận (mã \(httpResponse.statusCode)). Thử lại sau ít phút.")) // LEANKEYS-HOOK: copy
                }
                return
            }

            guard let data else {
                DispatchQueue.main.async {
                    completion(.error("Không đọc được phản hồi của máy chủ cập nhật. Thử lại sau.")) // LEANKEYS-HOOK: copy
                }
                return
            }

            self?.parseResponse(data: data, completion: completion)
        }

        task.resume()
    }

    private func parseResponse(data: Data, completion: @escaping (UpdateCheckResult) -> Void) {
        do {
            guard let releases = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                DispatchQueue.main.async { completion(.error("Không đọc được phản hồi của máy chủ cập nhật. Thử lại sau.")) } // LEANKEYS-HOOK: copy
                return
            }

            let currentVersion = AppMetadata.version
            let includePrerelease = currentVersion.contains("pre")

            // Find the highest version release
            // Pre-release builds check pre-releases too; stable builds only check stable
            var bestRelease: [String: Any]?
            var bestVersion = ""

            for release in releases {
                guard let tagName = release["tag_name"] as? String,
                      release["draft"] as? Bool != true else { continue }
                if !includePrerelease, release["prerelease"] as? Bool == true {
                    continue
                }

                let version = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName

                if bestVersion.isEmpty {
                    bestVersion = version
                    bestRelease = release
                } else {
                    let cmp = bestVersion.withCString { bestPtr in
                        version.withCString { verPtr in
                            version_compare(bestPtr, verPtr)
                        }
                    }
                    if cmp < 0 {
                        bestVersion = version
                        bestRelease = release
                    }
                }
            }

            guard let release = bestRelease, !bestVersion.isEmpty else {
                DispatchQueue.main.async { completion(.upToDate) }
                return
            }

            // Check if update available
            let hasUpdate = currentVersion.withCString { currentPtr in
                bestVersion.withCString { latestPtr in
                    version_has_update(currentPtr, latestPtr)
                }
            }

            guard hasUpdate == 1 else {
                DispatchQueue.main.async { completion(.upToDate) }
                return
            }

            // Find DMG download URL
            var downloadURL: URL?
            if let assets = release["assets"] as? [[String: Any]] {
                for asset in assets {
                    if let name = asset["name"] as? String,
                       name.lowercased().hasSuffix(".dmg"),
                       let urlString = asset["browser_download_url"] as? String,
                       let url = URL(string: urlString), // LEANKEYS-HOOK: branding
                       SafeInstaller.isTrustedDownloadURL(url) // LEANKEYS-HOOK: branding
                    {
                        downloadURL = url
                        break
                    }
                }
            }

            guard let finalDownloadURL = downloadURL else {
                DispatchQueue.main.async { completion(.error("Bản mới chưa có tệp cài đặt. Thử lại sau.")) } // LEANKEYS-HOOK: copy
                return
            }

            let releaseNotes = release["body"] as? String ?? ""
            var publishedAt: Date?
            if let publishedString = release["published_at"] as? String {
                publishedAt = ISO8601DateFormatter().date(from: publishedString)
            }

            let updateInfo = UpdateInfo(
                version: bestVersion,
                downloadURL: finalDownloadURL,
                releaseNotes: releaseNotes,
                publishedAt: publishedAt
            )

            DispatchQueue.main.async { completion(.available(updateInfo)) }

        } catch {
            DispatchQueue.main.async {
                completion(.error("Không đọc được phản hồi của máy chủ cập nhật. Thử lại sau.")) // LEANKEYS-HOOK: copy
            }
        }
    }
}
