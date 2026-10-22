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
          remove      Remove the helper; keep the CLI
          status      Show helper and tunnel status
          connect     Connect using credentials shared with the app
          disconnect  Disconnect the active tunnel
          uninstall   Remove the CLI and helper

        Examples:
          rwth-vpn setup
          rwth-vpn connect
          rwth-vpn status
          rwth-vpn uninstall
        """)
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
