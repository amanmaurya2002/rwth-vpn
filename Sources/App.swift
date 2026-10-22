import AppKit
import SwiftUI

@main
enum RWTHVPN {
    @MainActor private static var delegate: AppDelegate?

    @MainActor
    static func main() {
        if CommandLine.arguments.contains("--selftest") {
            exit(SelfTest.run())
        }

        if CommandLine.arguments.contains("--render-icon") {
            IconRenderer.render(to: CommandLine.arguments.last ?? "/tmp/icon.png")
            exit(0)
        }

        if CommandLine.arguments.contains("--debug-connect") {
            runDebugConnect()
            exit(0)
        }

        if CommandLine.arguments.contains("--render-preview") {
            PreviewRenderer.render()
            exit(0)
        }

        let application = NSApplication.shared
        let appDelegate = AppDelegate()
        delegate = appDelegate
        application.delegate = appDelegate
        application.setActivationPolicy(.regular)
        application.run()
    }

    /// Dev: drive the real state machine against a real server, printing the
    /// log and final status. Credentials come from the environment.
    @MainActor
    private static func runDebugConnect() {
        let env = ProcessInfo.processInfo.environment
        let model = VPNModel()
        model.username = env["RWTHVPN_USER"] ?? ""
        model.passwordDraft = env["RWTHVPN_PASS"] ?? ""
        model.secretDraft = env["RWTHVPN_TOTP"] ?? ""
        model.group = env["RWTHVPN_GROUP"] ?? "split"
        model.connect()

        let deadline = Date().addingTimeInterval(45)
        while model.isBusy && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        print("---- LOG ----")
        for line in model.logLines { print(line) }
        print("---- STATUS: \(model.status) ip=\(model.tunnelIP ?? "nil") ----")
    }
}
