import CryptoKit
import Foundation

/// Everything that touches root: the privileged helper, its openconnect
/// payload, the sudoers rule and the login item.
enum Helper {
    enum Status: Equatable {
        case missing
        case outdated(installed: String)
        case ready
    }

    static let path = "/usr/local/libexec/rwth-vpn-helper"
    static let sudoersPath = "/etc/sudoers.d/rwth-vpn-helper"
    static let payloadPath = "/usr/local/libexec/rwth-vpn"
    static let pidfile = "/var/run/rwth-vpn-helper.pid"

    private static var resourceRoot: URL? {
        if let path = ProcessInfo.processInfo.environment["RWTH_VPN_RESOURCE_ROOT"] {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        if let executable = ProcessInfo.processInfo.arguments.first {
            let sibling = URL(fileURLWithPath: executable).deletingLastPathComponent()
                .appendingPathComponent("resources", isDirectory: true)
            if FileManager.default.fileExists(atPath: sibling.path) {
                return sibling
            }
        }
        return Bundle.main.resourceURL
    }

    enum InstallError: LocalizedError {
        case missingResource(String)
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .missingResource(let name):
                return "The app bundle is incomplete (\(name) is missing). Reinstall the app."
            case .failed(let message):
                return message
            }
        }
    }

    // MARK: - State

    /// Hash of the bundled MANIFEST.sha256; identifies the payload exactly.
    static var bundledManifestHash: String? {
        guard let root = resourceRoot,
              let url = root.appendingPathComponent("openconnect/MANIFEST.sha256") as URL?,
              let data = try? Data(contentsOf: url)
        else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static var status: Status {
        guard FileManager.default.fileExists(atPath: path),
              FileManager.default.fileExists(atPath: sudoersPath)
        else { return .missing }

        let result = run("/usr/bin/sudo", ["-n", path, "version"])
        guard result.status == 0 else { return .missing }

        var helper = ""
        var manifest = ""
        for line in result.output.split(separator: "\n") {
            if line.hasPrefix("helper=") { helper = String(line.dropFirst("helper=".count)) }
            if line.hasPrefix("manifest=") { manifest = String(line.dropFirst("manifest=".count)) }
        }

        guard helper == AppInfo.helperVersion,
              let bundled = bundledManifestHash,
              manifest == bundled
        else {
            return .outdated(installed: helper.isEmpty ? "unknown" : helper)
        }
        return .ready
    }

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: path)
            && FileManager.default.fileExists(atPath: sudoersPath)
    }

    static var isUpToDate: Bool {
        if case .ready = status { return true }
        return false
    }

    static var statusDescription: String {
        switch status {
        case .missing: return "missing"
        case .outdated(let installed): return "outdated (\(installed))"
        case .ready: return "ready"
        }
    }

    /// PID of a session started earlier (e.g. before the app was relaunched).
    static func connectionPID() -> pid_t? {
        guard let text = try? String(contentsOfFile: pidfile, encoding: .utf8),
              let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)),
              kill(pid, 0) == 0
        else { return nil }
        // Guard against a recycled pid from a stale pid file.
        let command = run("/bin/ps", ["-p", "\(pid)", "-o", "command="]).output
        return command.contains("openconnect") ? pid : nil
    }

    // MARK: - Install / uninstall

    static func install() throws {
        guard let helperText = bundledHelper,
              let payloadURL = resourceRoot?.appendingPathComponent("openconnect", isDirectory: true)
        else {
            throw InstallError.missingResource("openconnect payload")
        }

        let appPath = Bundle.main.bundlePath
        let verification = appPath.hasSuffix(".app")
            ? "/usr/bin/codesign --verify --strict '\(appPath)' && "
            : ""
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory.appendingPathComponent("rwth-vpn-install-\(UUID().uuidString)")
        let helperCopy = scratch.appendingPathComponent("helper")
        let sudoersCopy = scratch.appendingPathComponent("sudoers")
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: scratch) }

        try helperText.write(to: helperCopy, atomically: true, encoding: .utf8)
        let rule = "\(NSUserName()) ALL=(root) NOPASSWD: \(path)\n"
        try rule.write(to: sudoersCopy, atomically: true, encoding: .utf8)

        // The app bundle is verified before anything is copied as root, so a
        // modified bundle cannot install a tampered payload.
        let command = """
        \(verification)\
        /bin/rm -rf '\(payloadPath).new' && \
        /bin/mkdir -p '\(payloadPath).new' && \
        /bin/cp -R '\(payloadURL.path)/.' '\(payloadPath).new/' && \
        /usr/sbin/chown -R root:wheel '\(payloadPath).new' && \
        /bin/chmod -R go-w '\(payloadPath).new' && \
        /bin/rm -rf '\(payloadPath)' && \
        /bin/mv '\(payloadPath).new' '\(payloadPath)' && \
        /usr/sbin/visudo -cf '\(sudoersCopy.path)' && \
        /usr/bin/install -o root -g wheel -m 0755 '\(helperCopy.path)' '\(path)' && \
        /usr/bin/install -o root -g wheel -m 0440 '\(sudoersCopy.path)' '\(sudoersPath)'
        """
        let result = try runAdmin(command)
        guard result.status == 0 else {
            throw InstallError.failed(result.error.isEmpty ? "Installation cancelled." : result.error)
        }
    }

    static func uninstall() throws {
        let command = """
        /bin/rm -f '\(sudoersPath)' '\(path)' && \
        /bin/rm -rf '\(payloadPath)'
        """
        let result = try runAdmin(command)
        if result.status != 0 {
            throw InstallError.failed(result.error.isEmpty ? "Uninstall failed." : result.error)
        }
    }

    private static var bundledHelper: String? {
        guard let url = resourceRoot?.appendingPathComponent("rwth-vpn-helper.sh"),
              let text = try? String(contentsOf: url, encoding: .utf8),
              !text.contains("{{HELPER_VERSION}}")
        else { return nil }
        return text
    }

    // MARK: - Process plumbing

    struct Result {
        var status: Int32
        var output: String
        var error: String
    }

    @discardableResult
    static func run(_ launchPath: String, _ arguments: [String], input: String? = nil) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        if let input {
            let stdin = Pipe()
            process.standardInput = stdin
            do {
                try process.run()
                stdin.fileHandleForWriting.write(Data(input.utf8))
                try stdin.fileHandleForWriting.close()
            } catch {
                return Result(status: -1, output: "", error: error.localizedDescription)
            }
            let outData = out.fileHandleForReading.readDataToEndOfFile()
            let errData = err.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return Result(
                status: process.terminationStatus,
                output: String(decoding: outData, as: UTF8.self),
                error: String(decoding: errData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        do {
            try process.run()
        } catch {
            return Result(status: -1, output: "", error: error.localizedDescription)
        }
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Result(
            status: process.terminationStatus,
            output: String(decoding: outData, as: UTF8.self),
            error: String(decoding: errData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    /// Runs a shell command with an administrator prompt through osascript.
    private static func runAdmin(_ shellCommand: String) throws -> Result {
        let escaped = shellCommand
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = "do shell script \"\(escaped)\" with administrator privileges"
        let result = run("/usr/bin/osascript", ["-e", script])
        var message = result.error
        if let range = message.range(of: "execution error: ") {
            message = String(message[range.upperBound...])
        }
        if message.contains("User canceled") || message.contains("(-128)") {
            message = "Cancelled."
        }
        return Result(status: result.status, output: result.output, error: message)
    }
}

/// Starts the app at login through a per-user LaunchAgent.
enum LoginItem {
    static let label = "dev.local.rwth-vpn.loginitem"

    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    static func set(_ enabled: Bool) {
        let fm = FileManager.default
        if enabled {
            guard let executable = Bundle.main.executableURL?.path else { return }
            let plist: [String: Any] = [
                "Label": label,
                "ProgramArguments": [executable],
                "RunAtLoad": true,
                "ProcessType": "Interactive",
            ]
            try? fm.createDirectory(
                at: plistURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) {
                try? data.write(to: plistURL)
            }
            _ = Helper.run("/bin/launchctl", ["bootstrap", "gui/\(getuid())", plistURL.path])
        } else {
            _ = Helper.run("/bin/launchctl", ["bootout", "gui/\(getuid())/\(label)"])
            try? fm.removeItem(at: plistURL)
        }
    }
}
