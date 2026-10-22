import AppKit
import CryptoKit
import Foundation

@MainActor
final class UpdateController {
    static let shared = UpdateController()

    private var isChecking = false

    private struct Release: Decodable {
        let tagName: String
        let name: String?
        let body: String?
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case name, body, assets
        }
    }

    private struct Asset: Decodable {
        let name: String
        let browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    private enum UpdateError: LocalizedError {
        case unavailable
        case invalidVersion
        case missingAsset
        case checksumMismatch
        case installationFailed

        var errorDescription: String? {
            switch self {
            case .unavailable: return "Could not check for updates."
            case .invalidVersion: return "The release version is invalid."
            case .missingAsset: return "The release does not contain a compatible update."
            case .checksumMismatch: return "The downloaded update failed its checksum verification."
            case .installationFailed: return "The update could not be installed."
            }
        }
    }

    func checkForUpdates() {
        guard !isChecking else { return }
        isChecking = true
        Task {
            defer { isChecking = false }
            do {
                let release = try await fetchRelease()
                guard let version = normalizedVersion(release.tagName),
                      version > normalizedVersion(AppInfo.version)! else {
                    showNotice(title: "RWTH VPN is up to date",
                               message: "You are running version \(AppInfo.version).")
                    return
                }
                try await offer(release, version: version)
            } catch is CancellationError {
            } catch {
                showNotice(title: "Update check failed",
                           message: error.localizedDescription)
            }
        }
    }

    private func fetchRelease() async throws -> Release {
        guard let url = URL(string: AppInfo.latestReleaseAPI) else {
            throw UpdateError.unavailable
        }
        var request = URLRequest(url: url)
        request.setValue("RWTH-VPN/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw UpdateError.unavailable
        }
        return try JSONDecoder().decode(Release.self, from: data)
    }

    private func offer(_ release: Release, version: Version) async throws {
        guard let zip = release.assets.first(where: { $0.name.hasSuffix(".zip") }),
              let sums = release.assets.first(where: { $0.name == "SHA256SUMS.txt" })
        else { throw UpdateError.missingAsset }

        let alert = NSAlert()
        alert.messageText = "\(release.name ?? "RWTH VPN update") is available"
        alert.informativeText = "Version \(version.description) is ready to install."
        if let notes = release.body, !notes.isEmpty {
            alert.informativeText += "\n\n" + notes
        }
        alert.addButton(withTitle: "Install Update")
        alert.addButton(withTitle: "Later")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let panel = NSProgressIndicator(frame: NSRect(x: 0, y: 0, width: 260, height: 18))
        panel.isIndeterminate = true
        panel.style = .bar
        let progressAlert = NSAlert()
        progressAlert.messageText = "Installing RWTH VPN \(version.description)…"
        progressAlert.accessoryView = panel
        progressAlert.addButton(withTitle: "Cancel")

        let task = Task {
            let temporary = FileManager.default.temporaryDirectory
                .appendingPathComponent("rwth-vpn-update-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: temporary) }

            let zipURL = temporary.appendingPathComponent(zip.name)
            let sumsURL = temporary.appendingPathComponent(sums.name)
            try await download(zip.browserDownloadURL, to: zipURL)
            try await download(sums.browserDownloadURL, to: sumsURL)
            try verify(zipURL: zipURL, sumsURL: sumsURL, assetName: zip.name)
            try install(zipURL: zipURL, version: version)
        }

        progressAlert.beginSheetModal(for: NSApp.keyWindow ?? NSApp.mainWindow ?? NSWindow()) { _ in
            task.cancel()
        }

        do {
            try await task.value
        } catch is CancellationError {
        } catch {
            showNotice(title: "Update failed", message: error.localizedDescription)
        }
    }

    private func download(_ url: URL, to destination: URL) async throws {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw UpdateError.unavailable
        }
        try data.write(to: destination, options: .atomic)
    }

    private func verify(zipURL: URL, sumsURL: URL, assetName: String) throws {
        let digest = SHA256.hash(data: try Data(contentsOf: zipURL))
            .map { String(format: "%02x", $0) }
            .joined()
        let sums = try String(contentsOf: sumsURL, encoding: .utf8)
        let matches = sums.split(whereSeparator: \.isNewline).contains {
            let fields = $0.split(maxSplits: 1, whereSeparator: \.isWhitespace)
            guard fields.count == 2, fields[0] == digest else { return false }
            let checksumName = fields[1].replacingOccurrences(of: "dist/", with: "")
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: ".", with: "")
            let downloadedName = assetName
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: ".", with: "")
            return checksumName == downloadedName
        }
        guard matches else { throw UpdateError.checksumMismatch }
    }

    private func install(zipURL: URL, version: Version) throws {
        let directory = zipURL.deletingLastPathComponent()
        let extracted = directory.appendingPathComponent("extracted", isDirectory: true)
        try FileManager.default.createDirectory(at: extracted, withIntermediateDirectories: true)

        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unzip.arguments = ["-x", "-k", zipURL.path, extracted.path]
        try unzip.run()
        unzip.waitUntilExit()
        guard unzip.terminationStatus == 0 else { throw UpdateError.installationFailed }

        let source = extracted.appendingPathComponent("RWTH VPN.app")
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw UpdateError.installationFailed
        }

        let script = directory.appendingPathComponent("install.sh")
        let target = Bundle.main.bundlePath
        let contents = """
        #!/bin/sh
        set -eu
        sleep 1
        /usr/bin/ditto --rsrc --extattr --acl "\(source.path)" "\(target)"
        /usr/bin/open "\(target)"
        """
        try contents.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)

        let updater = Process()
        updater.executableURL = URL(fileURLWithPath: "/bin/sh")
        updater.arguments = [script.path]
        try updater.run()
        NSApp.terminate(nil)
    }

    private func normalizedVersion(_ value: String) -> Version? {
        Version(value.trimmingCharacters(in: CharacterSet(charactersIn: "v")))
    }

    private func showNotice(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

private struct Version: Comparable, CustomStringConvertible {
    let components: [Int]

    init?(_ value: String) {
        let parts = value.split(separator: ".")
        guard !parts.isEmpty, parts.allSatisfy({ Int($0) != nil }) else { return nil }
        components = parts.map { Int($0)! }
    }

    var description: String { components.map(String.init).joined(separator: ".") }

    static func < (lhs: Version, rhs: Version) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }
}
