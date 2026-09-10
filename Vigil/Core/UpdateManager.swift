import AppKit
import Foundation
import Combine
import os

/// Checks for, downloads, and installs new releases of Vigil.
///
/// The install works the way a self-updating app has to: the running bundle
/// cannot replace itself while it is executing, so a small detached script
/// waits for this process to exit, swaps the bundle, and relaunches.
@MainActor
final class UpdateManager: ObservableObject {

    private static let log = Logger(subsystem: "zw.co.munyaradzichigangawa.Vigil", category: "Updates")

    @Published private(set) var isChecking = false
    @Published private(set) var isInstalling = false
    /// Human-readable phase while installing, e.g. "Downloading…".
    @Published private(set) var stage: String?
    @Published private(set) var result: UpdateCheckResult?
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastCheckedAt: Date?

    private let service = ReleaseUpdateService()

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// True when an update exists and can actually be installed in place.
    var canInstall: Bool {
        guard let result, result.hasUpdate, result.downloadURL != nil else { return false }
        return !isInstalling
    }

    /// Running from Xcode's DerivedData means an in-place swap would replace a
    /// build product that the next \u{2318}R overwrites anyway.
    var isRunningFromDerivedData: Bool {
        Bundle.main.bundleURL.path.contains("/DerivedData/")
    }

    // MARK: - Checking

    func check(userInitiated: Bool) async {
        guard !isChecking else { return }
        isChecking = true
        errorMessage = nil
        defer { isChecking = false }

        do {
            let outcome = try await service.checkForUpdates(currentVersion: currentVersion)
            result = outcome
            lastCheckedAt = Date()
            Preferences.shared.lastUpdateCheck = lastCheckedAt
            Self.log.info("Update check: current \(outcome.currentVersion, privacy: .public), latest \(outcome.latestVersion, privacy: .public)")
        } catch {
            result = nil
            // A silent background check shouldn't nag about a flaky network.
            if userInitiated { errorMessage = error.localizedDescription }
            Self.log.error("Update check failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Installing

    func install() async {
        guard let result, let downloadURL = result.downloadURL else {
            errorMessage = UpdateError.noDownloadableAsset.errorDescription
            return
        }
        guard ReleaseUpdateService.isAllowed(downloadURL) else {
            errorMessage = UpdateError.invalidResponse.errorDescription
            return
        }

        isInstalling = true
        errorMessage = nil
        stage = "Downloading\u{2026}"

        do {
            let fileManager = FileManager.default
            let (downloaded, response) = try await URLSession.shared.download(from: downloadURL)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw UpdateError.invalidResponse
            }

            stage = "Extracting\u{2026}"
            let extractDir = fileManager.temporaryDirectory
                .appendingPathComponent("vigil-update-\(UUID().uuidString)")
            try fileManager.createDirectory(at: extractDir, withIntermediateDirectories: true)

            try Self.run("/usr/bin/ditto", ["-x", "-k", downloaded.path, extractDir.path])

            guard let newApp = try fileManager
                .contentsOfDirectory(at: extractDir, includingPropertiesForKeys: nil)
                .first(where: { $0.pathExtension == "app" })
            else { throw UpdateError.archiveHadNoApp }

            // Refuse to overwrite ourselves with something that isn't Vigil.
            // Without this, a compromised or mistaken release asset could swap
            // an arbitrary app into our bundle path.
            stage = "Verifying\u{2026}"
            let expectedID = Bundle.main.bundleIdentifier ?? "zw.co.munyaradzichigangawa.Vigil"
            guard let incoming = Bundle(url: newApp)?.bundleIdentifier else {
                throw UpdateError.archiveHadNoApp
            }
            guard incoming == expectedID else {
                throw UpdateError.identityMismatch(incoming)
            }

            stage = "Installing\u{2026}"
            try Self.writeAndLaunchSwapScript(from: newApp,
                                              to: Bundle.main.bundleURL,
                                              scratch: extractDir)

            // Give the user a beat to read the stage, then get out of the way
            // so the script can replace the bundle.
            try? await Task.sleep(nanoseconds: 500_000_000)
            NSApp.terminate(nil)

        } catch {
            isInstalling = false
            stage = nil
            errorMessage = error.localizedDescription
            Self.log.error("Update install failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Helpers

    private static func run(_ launchPath: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw UpdateError.invalidResponse }
    }

    /// Writes the detached swap script and starts it.
    ///
    /// Paths are passed to the script as positional arguments rather than
    /// interpolated into its body, so a bundle path containing quotes or other
    /// shell metacharacters cannot break out of the quoting.
    private static func writeAndLaunchSwapScript(from newApp: URL,
                                                 to currentBundle: URL,
                                                 scratch: URL) throws {
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = """
        #!/bin/bash
        # Vigil in-place updater. Args: <pid> <new app> <current bundle> <scratch dir>
        set -e
        target_pid="$1"; new_app="$2"; current="$3"; scratch="$4"

        # Wait for Vigil to exit; give up after 30s rather than hang forever.
        for _ in $(seq 1 300); do
            kill -0 "$target_pid" 2>/dev/null || break
            sleep 0.1
        done

        /usr/bin/rsync -a --delete "$new_app/" "$current/"
        # A freshly swapped bundle keeps any quarantine flag from the download;
        # clearing it avoids Gatekeeper refusing to launch the replacement.
        /usr/bin/xattr -dr com.apple.quarantine "$current" 2>/dev/null || true
        /bin/rm -rf "$scratch"
        /usr/bin/open "$current"
        """

        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vigil-update-\(pid).sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700],
                                              ofItemAtPath: scriptURL.path)

        let launcher = Process()
        launcher.executableURL = URL(fileURLWithPath: "/bin/bash")
        launcher.arguments = [scriptURL.path,
                              String(pid),
                              newApp.path,
                              currentBundle.path,
                              scratch.path]
        launcher.standardOutput = FileHandle.nullDevice
        launcher.standardError = FileHandle.nullDevice
        try launcher.run()
    }
}
