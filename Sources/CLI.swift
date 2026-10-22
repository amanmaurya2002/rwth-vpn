import Foundation
import Darwin

@main
enum RWTHVPNCLI {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        do {
            try run(arguments)
        } catch {
            Terminal.error(error.localizedDescription)
            exit(1)
        }
    }

    private static func run(_ arguments: [String]) throws {
        guard let command = arguments.first else {
            printUsage()
            return
        }

        switch command {
        case "setup":
            guard arguments.dropFirst().isEmpty else {
                throw CLIError.message("Usage: rwth-vpn setup")
            }
            try Helper.install()
            Terminal.success("Helper installed.")
            Terminal.muted("You can now run: rwth-vpn connect")
        case "configure":
            guard arguments.dropFirst().isEmpty else {
                throw CLIError.message("Usage: rwth-vpn configure")
            }
            try configure()
        case "remove":
            guard arguments.dropFirst().isEmpty else {
                throw CLIError.message("Usage: rwth-vpn remove")
            }
            try removeHelper()
        case "uninstall":
            try uninstall(arguments.dropFirst())
        case "status":
            guard arguments.dropFirst().isEmpty else {
                throw CLIError.message("Usage: rwth-vpn status")
            }
            Terminal.header("RWTH VPN")
            Terminal.row("Helper", Helper.statusDescription, tone: Helper.status == .ready ? .success : .warning)
            if let pid = Helper.connectionPID() {
                Terminal.row("Tunnel", "active (pid \(pid))", tone: .success)
            } else {
                Terminal.row("Tunnel", "inactive", tone: .muted)
            }
        case "disconnect":
            guard arguments.dropFirst().isEmpty else {
                throw CLIError.message("Usage: rwth-vpn disconnect")
            }
            let result = Helper.run("/usr/bin/sudo", ["-n", Helper.path, "stop"])
            guard result.status == 0 else {
                throw CLIError.message(result.error.isEmpty ? "Could not disconnect." : result.error)
            }
            Terminal.success("Disconnected.")
        case "connect":
            try connect(arguments.dropFirst())
        case "update":
            try update(arguments.dropFirst())
        case "help", "--help", "-h":
            printUsage()
        default:
            throw CLIError.message("Unknown command '\(command)'. Use 'rwth-vpn help'.")
        }
    }

    private static func connect(_ arguments: ArraySlice<String>) throws {
        let values = Array(arguments)
        guard values.count <= 1 else {
            throw CLIError.message("Usage: rwth-vpn connect [split|full]")
        }
        let group = values.first ?? "split"
        guard group == "split" || group == "full" else {
            throw CLIError.message("Tunnel must be 'split' or 'full'.")
        }
        guard Helper.status == .ready else {
            throw CLIError.message("Helper is not ready. Run 'rwth-vpn setup'.")
        }

        let username = VPNCore.loadUsername()
        guard let user = VPNCore.validateUsername(username) else {
            throw CLIError.message("No valid username found. Configure it in the app first.")
        }
        let password = VPNCore.loadPassword()
        guard !password.isEmpty else {
            throw CLIError.message("No VPN password found. Configure it in the app first.")
        }
        guard let code = VPNCore.currentCode(secret: VPNCore.loadTOTPSecret()) else {
            throw CLIError.message("No TOTP code available. Configure a token secret in the app first.")
        }

        let result = Helper.run("/usr/bin/sudo", ["-n", Helper.path, "connect", group, user],
                                input: "\(password)\n\(code)\n")
        if result.status != 0 {
            throw CLIError.message(result.error.isEmpty ? result.output : result.error)
        }
        Terminal.success("Connected.")
        if !result.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            print(result.output)
        }
    }

    private static func removeHelper() throws {
        if Helper.connectionPID() != nil {
            let result = Helper.run("/usr/bin/sudo", ["-n", Helper.path, "stop"])
            guard result.status == 0 else {
                throw CLIError.message(result.error.isEmpty ? "Could not disconnect." : result.error)
            }
        }
        try Helper.uninstall()
        Terminal.success("Helper removed.")
        Terminal.muted("The CLI remains installed.")
    }

    private static func printUsage() {
        print("""
        \(Terminal.bold("rwth-vpn")) — a small RWTH VPN client

        \(Terminal.bold("Usage:")) rwth-vpn <command>

        Commands:
          setup       Install or update the privileged helper
          configure   Save username, VPN password, and optional TOTP secret
          remove      Remove the helper; keep the CLI
          status      Show helper and tunnel status
          connect     Connect using credentials shared with the app
          disconnect  Disconnect the active tunnel
          update      Check for and install the latest CLI release
          uninstall   Remove the CLI and helper

        Examples:
          rwth-vpn setup
          rwth-vpn connect
          rwth-vpn status
          rwth-vpn uninstall
        """)
    }

    private static func configure() throws {
        guard Terminal.isInteractive else {
            throw CLIError.message("Configuration requires an interactive terminal.")
        }
        print("Configure RWTH VPN")
        print(Terminal.dim("----------------------------------------"))
        print("Username: ", terminator: "")
        guard let rawUsername = readLine(),
              let username = VPNCore.validateUsername(rawUsername)
        else {
            throw CLIError.message("Username must look like ab123456.")
        }
        guard let password = readSecret("VPN password: "), !password.isEmpty else {
            throw CLIError.message("VPN password cannot be empty.")
        }
        print("TOTP secret (optional, Base32 or otpauth://): ", terminator: "")
        let secret = readLine() ?? ""
        if !secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           VPNCore.currentCode(secret: secret) == nil {
            throw CLIError.message("The TOTP secret is not valid.")
        }
        VPNCore.saveCredentials(username: username, password: password, secret: secret)
        Terminal.success("Credentials saved to the login Keychain.")
    }

    private static func readSecret(_ prompt: String) -> String? {
        var buffer = [CChar](repeating: 0, count: 1024)
        return buffer.withUnsafeMutableBufferPointer { pointer in
            prompt.withCString { promptPointer in
                guard let result = readpassphrase(promptPointer, pointer.baseAddress, pointer.count, 0) else {
                    return nil
                }
                return String(cString: result)
            }
        }
    }

    private static func update(_ arguments: ArraySlice<String>) throws {
        let values = Array(arguments)
        let check = values.contains("--check")
        let yes = values.contains("--yes")
        let unknown = values.filter { $0 != "--check" && $0 != "--yes" }
        guard unknown.isEmpty,
              values.filter({ $0 == "--check" }).count <= 1,
              values.filter({ $0 == "--yes" }).count <= 1
        else {
            throw CLIError.message("Usage: rwth-vpn update [--check] [--yes]")
        }

        let release = try CLIUpdater.latestRelease()
        if let current = ProcessInfo.processInfo.environment["RWTH_VPN_VERSION"],
           current == release.version {
            Terminal.success("Already up to date (\(current)).")
            return
        }
        Terminal.success("Latest release: \(release.version)")
        if check {
            return
        }
        guard let root = ProcessInfo.processInfo.environment["RWTH_VPN_INSTALL_ROOT"],
              !root.isEmpty
        else {
            throw CLIError.message("This CLI was not installed by the direct installer. Reinstall it before using 'rwth-vpn update'.")
        }
        if !yes {
            guard confirm("Install rwth-vpn \(release.version)?") else {
                Terminal.muted("Cancelled.")
                return
            }
        }
        try CLIUpdater.install(release, root: root)
        Terminal.success("Updated to \(release.version).")
    }

    private enum CLIUpdater {
            struct Release {
            let version: String
            let tag: String
            let archive: String
            let baseURL: URL
    }

        static let apiURL = URL(string: "https://api.github.com/repos/amanmaurya2002/rwth-vpn/releases/latest")!
        static let downloadRoot = "https://github.com/amanmaurya2002/rwth-vpn/releases/download"

        static func latestRelease() throws -> Release {
            let result = run("/usr/bin/curl", ["-fsSL", "-H", "Accept: application/vnd.github+json",
                                               "-A", "rwth-vpn-cli", apiURL.absoluteString])
            guard result.status == 0 else {
                throw CLIError.message(result.error.isEmpty ? "Could not check for updates." : result.error)
            }
            let text = result.output
            guard let tag = match(#""tag_name"\s*:\s*"([^"]+)""#, in: text),
                  tag.range(of: #"^v[0-9]+\.[0-9]+\.[0-9]+$"#, options: .regularExpression) != nil,
                  let version = tag.split(separator: "v").last.map(String.init)
            else {
                throw CLIError.message("The latest release response was invalid.")
            }
            let archive = "rwth-vpn-cli-\(version).tar.gz"
            guard let baseURL = URL(string: "\(downloadRoot)/\(tag)") else {
                throw CLIError.message("The latest release URL was invalid.")
            }
            return Release(version: version, tag: tag, archive: archive, baseURL: baseURL)
        }

        static func install(_ release: Release, root: String) throws {
            let fm = FileManager.default
            let temp = fm.temporaryDirectory.appendingPathComponent("rwth-vpn-update-\(UUID().uuidString)")
            let archiveURL = temp.appendingPathComponent(release.archive)
            let checksumsURL = temp.appendingPathComponent("SHA256SUMS.txt")
            let extracted = temp.appendingPathComponent("extracted")
            try fm.createDirectory(at: extracted, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: temp) }

            for (url, destination) in [
                (release.baseURL.appendingPathComponent(release.archive), archiveURL),
                (release.baseURL.appendingPathComponent("SHA256SUMS.txt"), checksumsURL),
            ] {
                let result = run("/usr/bin/curl", ["-fsSL", "-o", destination.path, url.absoluteString])
                guard result.status == 0 else {
                    throw CLIError.message(result.error.isEmpty ? "Could not download the update." : result.error)
                }
            }

            let checksum = run("/usr/bin/awk", ["-v", "name=\(release.archive)",
                                                 "$0 ~ name { print $1; exit }", checksumsURL.path])
            let actual = run("/usr/bin/shasum", ["-a", "256", archiveURL.path])
            let expected = checksum.output.trimmingCharacters(in: .whitespacesAndNewlines)
            let digest = actual.output.split(separator: " ").first.map(String.init) ?? ""
            guard checksum.status == 0, actual.status == 0, !expected.isEmpty, expected == digest else {
                throw CLIError.message("Update checksum verification failed.")
            }

            let extractResult = run("/usr/bin/tar", ["-xzf", archiveURL.path, "-C", extracted.path])
            guard extractResult.status == 0 else {
                throw CLIError.message("Could not unpack the update.")
            }
            let newBinary = extracted.appendingPathComponent("rwth-vpn-cli")
            let newResources = extracted.appendingPathComponent("resources")
            let installRoot = URL(fileURLWithPath: root, isDirectory: true)
            let libexec = installRoot.appendingPathComponent("libexec/rwth-vpn", isDirectory: true)
            let binary = libexec.appendingPathComponent("rwth-vpn-cli")
            let resources = libexec.appendingPathComponent("resources", isDirectory: true)
            guard fm.fileExists(atPath: newBinary.path), fm.fileExists(atPath: newResources.path) else {
                throw CLIError.message("The update archive is incomplete.")
            }
            try fm.createDirectory(at: libexec, withIntermediateDirectories: true)
            let stagedBinary = libexec.appendingPathComponent(".rwth-vpn-cli.new")
            let stagedResources = libexec.appendingPathComponent(".resources.new", isDirectory: true)
            try? fm.removeItem(at: stagedBinary)
            try? fm.removeItem(at: stagedResources)
            try fm.copyItem(at: newBinary, to: stagedBinary)
            try fm.copyItem(at: newResources, to: stagedResources)
            try? fm.removeItem(at: binary)
            try? fm.removeItem(at: resources)
            try fm.moveItem(at: stagedBinary, to: binary)
            try fm.moveItem(at: stagedResources, to: resources)
        }

    private static func match(_ pattern: String, in text: String) -> String? {
            guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
            let range = NSRange(text.startIndex..., in: text)
            guard let result = expression.firstMatch(in: text, range: range),
                  result.numberOfRanges > 1,
                  let valueRange = Range(result.range(at: 1), in: text)
            else { return nil }
            return String(text[valueRange])
        }

    private static func run(_ path: String, _ arguments: [String]) -> (status: Int32, output: String, error: String) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            let output = Pipe()
            let error = Pipe()
            process.standardOutput = output
            process.standardError = error
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                return (-1, "", error.localizedDescription)
            }
            return (
                process.terminationStatus,
                String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
                String(decoding: error.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            )
    }
    }

    private static func uninstall(_ arguments: ArraySlice<String>) throws {
        let values = Array(arguments)
        let purge = values.contains("--purge")
        let yes = values.contains("--yes")
        let unknown = values.filter { $0 != "--purge" && $0 != "--yes" }
        guard unknown.isEmpty else {
            throw CLIError.message("Usage: rwth-vpn uninstall [--purge] [--yes]")
        }

        guard values.filter({ $0 == "--purge" }).count <= 1,
              values.filter({ $0 == "--yes" }).count <= 1 else {
            throw CLIError.message("Usage: rwth-vpn uninstall [--purge] [--yes]")
        }

        if !yes {
            let scope = purge
                ? "the CLI, VPN helper, and saved credentials"
                : "the CLI and VPN helper (credentials will be kept)"
            guard confirm("Uninstall \(scope)?") else {
                Terminal.muted("Cancelled.")
                return
            }
        }

        if Helper.connectionPID() != nil {
            let result = Helper.run("/usr/bin/sudo", ["-n", Helper.path, "stop"])
            guard result.status == 0 else {
                throw CLIError.message(result.error.isEmpty ? "Could not disconnect." : result.error)
            }
        }
        try Helper.uninstall()
        if purge {
            Keychain.delete("username")
            Keychain.delete("password")
            Keychain.delete("totp")
            UserDefaults.standard.removePersistentDomain(forName: "dev.local.rwth-vpn")
        }

        guard let root = ProcessInfo.processInfo.environment["RWTH_VPN_INSTALL_ROOT"] else {
            Terminal.success(purge ? "Helper removed and credentials purged."
                                    : "Helper removed. Credentials were kept.")
            return
        }

        let bin = "\(root)/bin/rwth-vpn"
        let libexec = "\(root)/libexec/rwth-vpn"
        let command = "/bin/rm -f \(shellQuote(bin)); /bin/rm -rf \(shellQuote(libexec))"
        let script = "/bin/sh -c 'sleep 1; \(command)'"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        try process.run()
        Terminal.success("Uninstall scheduled.")
        Terminal.muted(purge ? "CLI, helper, and credentials will be removed."
                              : "CLI and helper will be removed. Credentials were kept.")
    }

    private static func confirm(_ prompt: String) -> Bool {
        guard Terminal.isInteractive else {
            Terminal.muted("Non-interactive mode: rerun with --yes to confirm.")
            return false
        }
        print("\(Terminal.warningSymbol) \(prompt) \(Terminal.dim("[y/N]")) ", terminator: "")
        return ["y", "yes"].contains((readLine() ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private enum CLIError: LocalizedError {
        case message(String)
        var errorDescription: String? {
            if case .message(let value) = self { return value }
            return nil
        }
    }

    private enum Terminal {
        enum Tone { case success, warning, muted }
        static let isInteractive = isatty(STDIN_FILENO) != 0 && isatty(STDOUT_FILENO) != 0
        private static let colors = isInteractive && ProcessInfo.processInfo.environment["NO_COLOR"] == nil
        static let warningSymbol = "!"

        static func header(_ text: String) {
            print("\n\(bold(text))")
            print(dim("----------------------------------------"))
        }

        static func row(_ label: String, _ value: String, tone: Tone) {
            let padded = label.padding(toLength: 10, withPad: " ", startingAt: 0)
            print("  \(bold(padded)) \(paint(value, tone))")
        }

        static func success(_ text: String) { print("\(green("OK")) \(text)") }
        static func error(_ text: String) { fputs("\(red("ERR")) rwth-vpn: \(text)\n", stderr) }
        static func muted(_ text: String) { print(dim(text)) }
        static func paint(_ text: String, _ tone: Tone) -> String {
            switch tone {
            case .success: return green(text)
            case .warning: return yellow(text)
            case .muted: return dim(text)
            }
        }
        static func bold(_ text: String) -> String { color(text, "1") }
        static func dim(_ text: String) -> String { color(text, "2") }
        static func green(_ text: String) -> String { color(text, "32") }
        static func yellow(_ text: String) -> String { color(text, "33") }
        static func red(_ text: String) -> String { color(text, "31") }
        private static func color(_ text: String, _ code: String) -> String {
            colors ? "\u{001B}[\(code)m\(text)\u{001B}[0m" : text
        }
    }
}
