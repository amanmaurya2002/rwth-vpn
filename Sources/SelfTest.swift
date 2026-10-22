import AppKit
import CoreGraphics
import Foundation
import SwiftUI

/// `--selftest` exercises everything that can be checked without real RWTH
/// credentials: TOTP, Base32, Keychain, menu bar plumbing, helper/payload
/// integrity and the full connect state machine against a fake openconnect.
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

        // From here on the tests must not touch the login keychain.
        Keychain.isEnabled = false

        check("Helper version resource", AppInfo.helperVersion != "0", AppInfo.helperVersion)
        check("Bundled openconnect payload", Helper.bundledManifestHash != nil)
        check("Bundled helper script", Bundle.main.url(forResource: "rwth-vpn-helper", withExtension: "sh") != nil)
        check("Auto-connect defaults on", VPNModel.preview(connected: false).autoConnect)
        print("INFO  helper status: \(Helper.status)")

        if CGSessionCopyCurrentDictionary() != nil {
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
        } else {
            print("SKIP  UI checks (no window server)")
        }

        testConnectFlow()
        testPromptVariants()
        testAuthFailure()
        testRedaction()

        print(failures == 0 ? "SELFTEST OK" : "SELFTEST FAILED (\(failures))")
        return failures == 0 ? 0 : 1
    }

    // MARK: - Fake gateway

    /// Writes an executable fake openconnect that asks for a password and then
    /// for `prompt`, accepting one line each, and reports a tunnel address.
    private static func fakeClient(prompt: String, address: String = "10.0.0.42",
                                   failFirstPassword: Bool = false) -> URL {
        let script = FileManager.default.temporaryDirectory
            .appendingPathComponent("fake-openconnect-\(UUID().uuidString).sh")
        var lines = [
            "#!/bin/bash",
            "printf 'Password:'",
            "read -r password",
            "printf '\\n'",
        ]
        if failFirstPassword {
            lines += [
                "printf 'Login failed.\\n'",
                "printf 'Password:'",
                "read -r again",
                "printf '\\n'",
                "sleep 1",
            ]
        } else {
            lines += [
                "printf '\(prompt)'",
                "read -r answer",
                "printf '\\n'",
                "printf 'Configured as \(address) + 2001:db8::1/64, with SSL connected\\n'",
                "printf 'Session authentication will expire at Thu, 05 Nov 2026 09:50:39 CET\\n'",
                "sleep 2",
            ]
        }
        let body = lines.joined(separator: "\n") + "\n"
        try? body.write(to: script, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script
    }

    private static func connect(using script: URL, password: String = "pw",
                                secret: String = "JBSWY3DPEHPK3PXP",
                                manualCode: String = "") -> VPNModel {
        setenv("RWTHVPN_DEBUG_COMMAND", script.path, 1)
        let model = VPNModel()
        model.username = "ab123456"
        model.passwordDraft = password
        model.secretDraft = secret
        model.manualCode = manualCode
        model.connect()
        let deadline = Date().addingTimeInterval(6)
        while model.isBusy && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        unsetenv("RWTHVPN_DEBUG_COMMAND")
        return model
    }

    private static func testConnectFlow() {
        let script = fakeClient(prompt: "Answer:")
        defer { try? FileManager.default.removeItem(at: script) }

        let model = connect(using: script)
        check("Connect state machine", model.isConnected, "status=\(model.status) log=\(model.logLines.suffix(3).joined(separator: " | "))")
        check("Tunnel address parsed", model.tunnelIP == "10.0.0.42", model.tunnelIP ?? "nil")
        check("Session expiry parsed", model.sessionExpiry?.contains("05 Nov 2026") == true, model.sessionExpiry ?? "nil")
    }

    /// RWTH's gateway says "Response:"; other gateways say "Challenge:" or a
    /// free-form label. All of them must be answered with the token code.
    private static func testPromptVariants() {
        for prompt in ["Response:", "Challenge:", "Verification code:"] {
            let script = fakeClient(prompt: prompt)
            defer { try? FileManager.default.removeItem(at: script) }
            let model = connect(using: script)
            check("Prompt variant \"\(prompt)\"", model.isConnected, "status=\(model.status)")
        }
    }

    /// A rejected password must surface a clear error instead of hanging or
    /// feeding the token code in as a second password attempt.
    private static func testAuthFailure() {
        let script = fakeClient(prompt: "Answer:", failFirstPassword: true)
        defer { try? FileManager.default.removeItem(at: script) }

        let model = connect(using: script, password: "wrong")
        var message = ""
        if case .failed(let text) = model.status { message = text }
        check("Rejected password fails fast", !message.isEmpty, "status=\(model.status)")
        check("Failure message is specific", message.contains("rejected"), message)
    }

    /// Credentials must never reach the log the user can copy.
    private static func testRedaction() {
        let script = fakeClient(prompt: "Response:")
        defer { try? FileManager.default.removeItem(at: script) }

        let password = "sup3rSecretPassword"
        let model = connect(using: script, password: password, secret: "", manualCode: "654321")
        let log = model.logLines.joined(separator: "\n")
        check("Password not logged", !log.contains(password), "log contains the password")
        check("Token code not logged", !log.contains("654321"), "log contains the token")
    }
}
