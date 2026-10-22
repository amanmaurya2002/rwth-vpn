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
        case "remove":
            try Helper.uninstall()
            print("Helper removed.")
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
        """)
    }

    private enum CLIError: LocalizedError {
        case message(String)
        var errorDescription: String? {
            if case .message(let value) = self { return value }
            return nil
        }
    }
}
