import AppKit
import Foundation
import SwiftUI

/// `--selftest` exercises everything that can be checked without real RWTH
/// credentials: TOTP, Base32, Keychain, menu bar plumbing, and the full
/// connect state machine against a fake openconnect.
@MainActor
enum SelfTest {
    private static var failures = 0

    private static func check(_ name: String, _ condition: Bool, _ detail: String = "") {
        if condition {
            print("PASS  \(name)")
        } else {
            failures += 1
            print("FAIL  \(name)\(detail.isEmpty ? "" : " — \(detail)")")
        }
    }

    static func run() -> Int32 {
        failures = 0

        // RFC 6238 vector: secret "12345678901234567890", T = 59 s, 6 digits.
        let vectorSecret = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"
        let vectorCode = TOTP.code(secret: vectorSecret, at: Date(timeIntervalSince1970: 59))
        check("TOTP RFC 6238 vector", vectorCode == "287082", "got \(vectorCode ?? "nil")")

        let live = TOTP.code(secret: "JBSWY3DPEHPK3PXP")
        check("TOTP current code", live?.count == 6 && live?.allSatisfy(\.isNumber) == true, "got \(live ?? "nil")")

        let uri = "otpauth://totp/RWTH:ab123456?secret=JBSWY3DPEHPK3PXP&issuer=RWTH"
        check("otpauth URI parsing", TOTP.normalize(uri) == "JBSWY3DPEHPK3PXP", TOTP.normalize(uri))

        let decoded = TOTP.base32Decode("JBSWY3DPEHPK3PXP").map { String(decoding: $0.prefix(6), as: UTF8.self) }
        check("Base32 decoding", decoded == "Hello!", decoded ?? "nil")

        let account = "selftest-\(UUID().uuidString)"
        Keychain.set("hello-keychain", for: account)
        check("Keychain write/read", Keychain.get(account) == "hello-keychain")
        Keychain.delete(account)
        check("Keychain delete", Keychain.get(account) == nil)

        check("Helper script bundled", Helper.source != nil)
        check("Auto-connect defaults on", VPNModel.preview(connected: false).autoConnect)

        // The same status item and hosting plumbing the app uses.
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        check("Status item has a button", item.button != nil)
        let symbol = NSImage(systemSymbolName: "lock.shield", accessibilityDescription: nil)
        check("Menu bar symbol available", symbol != nil)
        NSStatusBar.system.removeStatusItem(item)

        let preview = VPNModel.preview(connected: true)
        let hosting = NSHostingController(rootView: MainView(model: preview))
        hosting.view.frame = NSRect(x: 0, y: 0, width: 420, height: 580)
        hosting.view.layoutSubtreeIfNeeded()
        check("Main view lays out", hosting.view.fittingSize.height > 400, "\(hosting.view.fittingSize)")

        let settingsHost = NSHostingController(rootView: SettingsView(model: preview))
        settingsHost.view.frame = NSRect(x: 0, y: 0, width: 440, height: 560)
        settingsHost.view.layoutSubtreeIfNeeded()
        check("Settings view lays out", settingsHost.view.fittingSize.height > 400, "\(settingsHost.view.fittingSize)")

        testConnectFlow()
        testAuthFailure()

        print("INFO  helper installed: \(Helper.isInstalled), passwordless: \(Helper.isPasswordless)")
        print(failures == 0 ? "SELFTEST OK" : "SELFTEST FAILED (\(failures))")
        return failures == 0 ? 0 : 1
    }

    /// Drives the real connect state machine against a fake openconnect that
    /// asks for a password and a code, then reports a tunnel address.
    private static func testConnectFlow() {
        let script = FileManager.default.temporaryDirectory
            .appendingPathComponent("fake-openconnect-\(UUID().uuidString).sh")
        let body = """
        #!/bin/bash
        printf 'Password:'
        read -r password
        printf '\\n'
        printf 'Answer:'
        read -r answer
        printf '\\n'
        printf 'Connected as 134.61.96.5, using SSL\\n'
        sleep 2
        """
        try? body.write(to: script, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        setenv("RWTHVPN_DEBUG_COMMAND", script.path, 1)
        defer {
            unsetenv("RWTHVPN_DEBUG_COMMAND")
            try? FileManager.default.removeItem(at: script)
        }

        let model = VPNModel()
        model.username = "ab123456"
        model.passwordDraft = "pw"
        model.secretDraft = "JBSWY3DPEHPK3PXP"
        model.connect()

        let deadline = Date().addingTimeInterval(6)
        while !model.isConnected && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        check("Connect state machine", model.isConnected, "status=\(model.status)")
        check("Tunnel address parsed", model.tunnelIP == "134.61.96.5", model.tunnelIP ?? "nil")
    }

    /// A rejected password must surface a clear error instead of hanging or
    /// feeding the token code in as a second password attempt.
    private static func testAuthFailure() {
        let script = FileManager.default.temporaryDirectory
            .appendingPathComponent("fake-reject-\(UUID().uuidString).sh")
        let body = """
        #!/bin/bash
        printf 'Password:'
        read -r password
        printf '\\nLogin failed.\\n'
        printf 'Password:'
        read -r again
        printf '\\n'
        sleep 1
        """
        try? body.write(to: script, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        setenv("RWTHVPN_DEBUG_COMMAND", script.path, 1)
        defer {
            unsetenv("RWTHVPN_DEBUG_COMMAND")
            try? FileManager.default.removeItem(at: script)
        }

        let model = VPNModel()
        model.username = "ab123456"
        model.passwordDraft = "wrong"
        model.secretDraft = "JBSWY3DPEHPK3PXP"
        model.connect()

        let deadline = Date().addingTimeInterval(6)
        while model.isBusy && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        var message = ""
        if case .failed(let text) = model.status { message = text }
        check("Rejected password fails fast", !message.isEmpty, "status=\(model.status)")
        check("Failure message is specific", message.contains("rejected"), message)
    }
}
