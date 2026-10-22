import Foundation

@main
enum RWTHVPNCLI {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        do {
            try run(arguments)
        } catch {
            fputs("rwth-vpn: \(error.localizedDescription)\n", stderr)
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
            try Helper.install()
            print("Helper installed. You can now run: rwth-vpn connect")
        case "remove", "uninstall":
            try uninstall(arguments.dropFirst())
        case "status":
            print("helper: \(Helper.statusDescription)")
            if let pid = Helper.connectionPID() {
                print("connection: active (pid \(pid))")
            } else {
                print("connection: inactive")
            }
        case "disconnect":
            let result = Helper.run("/usr/bin/sudo", ["-n", Helper.path, "stop"])
            guard result.status == 0 else {
                throw CLIError.message(result.error.isEmpty ? "Could not disconnect." : result.error)
            }
            print("Disconnected.")
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
        print(result.output)
    }

    private static func printUsage() {
        print("""
        Usage: rwth-vpn <command>

        Commands:
          setup       Install or update the privileged helper
          remove      Remove the helper and bundled payload
          status      Show helper and tunnel status
          connect     Connect using credentials shared with the app
          disconnect  Disconnect the active tunnel
          uninstall   Remove the CLI and helper (use --purge to delete credentials)
        """)
    }

    private static func uninstall(_ arguments: ArraySlice<String>) throws {
        let values = Array(arguments)
        let purge = values.contains("--purge")
        let unknown = values.filter { $0 != "--purge" }
        guard unknown.isEmpty else {
            throw CLIError.message("Usage: rwth-vpn uninstall [--purge]")
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
            print(purge ? "Helper removed and credentials purged." : "Helper removed.")
            return
        }

        let command = "/bin/rm -rf \(shellQuote(root))"
        let script = "/bin/sh -c 'sleep 1; \(command)'"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        try process.run()
        print(purge ? "Helper removed, credentials purged, and CLI uninstall started."
                    : "Helper removed and CLI uninstall started. Credentials were kept.")
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
}
