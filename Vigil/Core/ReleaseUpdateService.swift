import Foundation

/// Checks GitHub Releases for a newer build of Vigil.
///
/// The only network call Vigil ever makes. It talks to one host, sends no
/// identifying information beyond a User-Agent, and is never contacted unless
/// the user asks for a check or opts into automatic ones.
struct ReleaseUpdateService {

    private let owner = "mchigangawa"
    private let repository = "Vigil"

    /// Hosts this service is willing to talk to. A release asset must live on
    /// one of them, so a tampered or redirected response cannot point the
    /// downloader at an arbitrary server.
    static let allowedHosts: Set<String> = [
        "api.github.com", "github.com", "objects.githubusercontent.com",
        "release-assets.githubusercontent.com",
    ]

    func checkForUpdates(currentVersion: String) async throws -> UpdateCheckResult {
        let release = try await fetchLatestRelease()
        let latest = Self.normalizedVersion(from: release.tagName)
        let current = Self.normalizedVersion(from: currentVersion)
        let hasUpdate = Self.compareVersion(current, latest) == .orderedAscending

        // Prefer a macOS zip; fall back to the first asset.
        let asset = release.assets.first { candidate in
            let name = candidate.name.lowercased()
            return name.hasSuffix(".zip") && (name.contains("vigil") || name.contains("mac"))
        } ?? release.assets.first { $0.name.lowercased().hasSuffix(".zip") }

        var downloadURL = asset?.browserDownloadURL
        if let url = downloadURL, !Self.isAllowed(url) {
            // Refuse to surface a download that isn't hosted by GitHub.
            downloadURL = nil
        }

        return UpdateCheckResult(
            currentVersion: current,
            latestVersion: latest,
            releaseName: release.name,
            releaseNotes: release.body,
            releaseNotesURL: release.htmlURL,
            downloadURL: downloadURL,
            hasUpdate: hasUpdate
        )
    }

    static func isAllowed(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }
        return allowedHosts.contains(host)
    }

    private func fetchLatestRelease() async throws -> GitHubRelease {
        let endpoint = "https://api.github.com/repos/\(owner)/\(repository)/releases/latest"
        guard let url = URL(string: endpoint), Self.isAllowed(url) else {
            throw UpdateError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Vigil", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UpdateError.invalidResponse }

        switch http.statusCode {
        case 200...299: break
        case 404: throw UpdateError.noReleases
        case 403, 429: throw UpdateError.rateLimited
        default: throw UpdateError.invalidResponse
        }

        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    // MARK: - Version comparison

    /// Strips a leading "v" and any `-beta` / `+build` suffix.
    static func normalizedVersion(from versionText: String) -> String {
        let cleaned = versionText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "^[vV]", with: "", options: .regularExpression)

        if let metadataStart = cleaned.firstIndex(where: { $0 == "-" || $0 == "+" }) {
            return String(cleaned[..<metadataStart])
        }
        return cleaned
    }

    /// Numeric, component-wise comparison, so 1.10.0 correctly beats 1.9.0.
    static func compareVersion(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = versionComponents(lhs)
        let right = versionComponents(rhs)

        for index in 0..<max(left.count, right.count) {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l < r { return .orderedAscending }
            if l > r { return .orderedDescending }
        }
        return .orderedSame
    }

    private static func versionComponents(_ version: String) -> [Int] {
        normalizedVersion(from: version)
            .split(separator: ".")
            .map { Int($0.prefix { $0.isNumber }) ?? 0 }
    }
}

struct UpdateCheckResult: Equatable {
    let currentVersion: String
    let latestVersion: String
    let releaseName: String?
    let releaseNotes: String?
    let releaseNotesURL: URL
    let downloadURL: URL?
    let hasUpdate: Bool
}

enum UpdateError: LocalizedError, Equatable {
    case invalidResponse
    case noReleases
    case rateLimited
    case noDownloadableAsset
    case archiveHadNoApp
    case identityMismatch(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Couldn't check for updates right now. Try again shortly."
        case .noReleases:
            return "No releases have been published yet."
        case .rateLimited:
            return "GitHub is rate-limiting update checks. Try again in a few minutes."
        case .noDownloadableAsset:
            return "That release has no downloadable macOS build."
        case .archiveHadNoApp:
            return "The download didn't contain a Vigil app."
        case .identityMismatch(let found):
            return "The download identifies itself as \u{201C}\(found)\u{201D}, not Vigil. Update cancelled."
        }
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let name: String?
    let body: String?
    let htmlURL: URL
    let assets: [GitHubReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name, body
        case htmlURL = "html_url"
        case assets
    }
}

private struct GitHubReleaseAsset: Decodable {
    let name: String
    let browserDownloadURL: URL

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}
