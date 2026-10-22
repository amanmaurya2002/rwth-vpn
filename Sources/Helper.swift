import Foundation

/// Everything that touches root: the privileged helper, its sudoers rule and
/// the login item.
enum Helper {
    static let path = "/usr/local/libexec/rwth-vpn-helper"
    static let sudoersPath = "/etc/sudoers.d/rwth-vpn-helper"
    static let pidfile = "/var/run/rwth-vpn-helper.pid"

    enum InstallError: LocalizedError {
        case missingResource
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .missingResource:
                return "The helper script is missing from the app bundle."
            case .failed(let message):
                return message
            }
        }
    }

    /// The helper script shipped inside the .app.
    static var source: String? {
        guard let url = Bundle.main.url(forResource: "rwth-vpn-helper", withExtension: "sh"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return nil }
        return text
    }

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: path)
            && FileManager.default.fileExists(atPath: sudoersPath)
    }

    /// True when the installed helper is byte-identical to the bundled one.
    static var isUpToDate: Bool {
        guard let expected = source,
              let installed = try? String(contentsOfFile: path, encoding: .utf8)
        else { return false }
        return expected == installed
    }

    /// Proves the NOPASSWD rule really works: the helper rejects its
    /// arguments with exit code 64, which sudo can only report when it ran
    /// the helper without asking for a password.
    static var isPasswordless: Bool {
        run("/usr/bin/sudo", ["-n", path, "__check__"]).status == 64
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

    static func install() throws {
        guard let source else { throw InstallError.missingResource }
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory.appendingPathComponent("rwth-vpn-helper-\(UUID().uuidString)")
        let helperCopy = scratch.appendingPathComponent("helper")
        let sudoersCopy = scratch.appendingPathComponent("sudoers")
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: scratch) }

        try source.write(to: helperCopy, atomically: true, encoding: .utf8)
        let rule = "\(NSUserName()) ALL=(root) NOPASSWD: \(path)\n"
        try rule.write(to: sudoersCopy, atomically: true, encoding: .utf8)

        let command = """
        /bin/mkdir -p /usr/local/libexec && \
        /usr/sbin/visudo -cf '\(sudoersCopy.path)' && \
        /usr/bin/install -o root -g wheel -m 0755 '\(helperCopy.path)' '\(path)' && \
        /usr/bin/install -o root -g wheel -m 0440 '\(sudoersCopy.path)' '\(sudoersPath)'
        """
        let result = try runAdmin(command)
        guard result.status == 0 else {
            throw InstallError.failed(result.error.isEmpty ? "Installation cancelled." : result.error)
        }

        guard let installed = try? String(contentsOfFile: path, encoding: .utf8), installed == source else {
            throw InstallError.failed("The helper was installed but its contents do not match. Aborting.")
        }
    }

    static func uninstall() throws {
        let command = "/bin/rm -f '\(sudoersPath)' '\(path)'"
        let result = try runAdmin(command)
        if result.status != 0 {
            throw InstallError.failed(result.error.isEmpty ? "Uninstall failed." : result.error)
        }
    }

    // MARK: - Process plumbing

    struct Result {
        var status: Int32
        var output: String
        var error: String
    }

    @discardableResult
    static func run(_ launchPath: String, _ arguments: [String]) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
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
        // osascript reports failures on stderr with an "execution error:" prefix.
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
