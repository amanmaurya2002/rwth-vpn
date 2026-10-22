import Combine
import Foundation

/// Drives one openconnect session and owns everything the UI shows.
@MainActor
final class VPNModel: ObservableObject {
    enum Status: Equatable {
        case disconnected
        case connecting
        case connected
        case disconnecting
        case failed(String)
    }

    // MARK: Published state

    @Published var status: Status = .disconnected
    @Published var logLines: [String] = []
    @Published var tunnelIP: String?
    @Published var sessionExpiry: String?
    @Published var showLog = false
    @Published var showSettings = false
    @Published var helperInstalled = false
    @Published var helperOutdated = false
    @Published var helperProblem: String?

    @Published var username: String = UserDefaults.standard.string(forKey: "username") ?? "" {
        didSet { if !suppressPersistence { UserDefaults.standard.set(username, forKey: "username") } }
    }

    @Published var group: String = UserDefaults.standard.string(forKey: "group") ?? "split" {
        didSet { if !suppressPersistence { UserDefaults.standard.set(group, forKey: "group") } }
    }

    @Published var passwordDraft: String = ""
    @Published var secretDraft: String = ""
    @Published var manualCode: String = ""

    @Published var launchAtLogin: Bool = LoginItem.isEnabled
    @Published var autoConnect: Bool = UserDefaults.standard.object(forKey: "autoConnect") as? Bool ?? true

    // MARK: Private state

    private var process: Process?
    private var stdinPipe: Pipe?
    private var outputPipe: Pipe?
    private var buffer = ""
    private var sentPassword = false
    private var sentAnswer = false
    private var lastFailure: String?
    private var watchdog: DispatchWorkItem?
    private var syncTimer: Timer?
    /// Preview rendering must not write to the real preferences.
    private var suppressPersistence = false

    init() {
        startStateSync()
        refreshHelperState()
    }

    deinit {
        syncTimer?.invalidate()
    }

    // MARK: Derived state

    var isBusy: Bool {
        switch status {
        case .connecting, .disconnecting: return true
        default: return false
        }
    }

    var isConnected: Bool {
        if case .connected = status { return true }
        return false
    }

    var hasCredentials: Bool {
        !username.trimmingCharacters(in: .whitespaces).isEmpty && !passwordDraft.isEmpty
    }

    var statusText: String {
        switch status {
        case .disconnected: return "Not connected"
        case .connecting: return "Connecting…"
        case .connected: return group == "full" ? "Full tunnel" : "Split tunnel"
        case .disconnecting: return "Disconnecting…"
        case .failed(let message): return message
        }
    }

    var buttonTitle: String {
        switch status {
        case .connected: return "Disconnect"
        case .connecting: return "Connecting…"
        case .disconnecting: return "Disconnecting…"
        default: return "Connect"
        }
    }

    var currentCode: String? {
        let secret = TOTP.normalize(secretDraft)
        if !secret.isEmpty, let code = TOTP.code(secret: secret) { return code }
        let manual = manualCode.trimmingCharacters(in: .whitespacesAndNewlines)
        return manual.count == 6 ? manual : nil
    }

    var usesAutomaticCode: Bool {
        !TOTP.normalize(secretDraft).isEmpty
    }

    // MARK: Actions

    func connect() {
        guard !isBusy, !isConnected else { return }

        let user = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard user.range(of: "^[a-z]{2}[0-9]{6}$", options: .regularExpression) != nil else {
            status = .failed("Enter your RWTH username (ab123456).")
            showSettings = true
            return
        }
        guard !passwordDraft.isEmpty else {
            status = .failed("Enter your VPN password.")
            showSettings = true
            return
        }
        guard currentCode != nil else {
            status = .failed("Enter the 6-digit code from your token.")
            return
        }

        let launch: (path: String, arguments: [String])
        if let debug = DebugCommand.current {
            launch = debug
        } else {
            switch Helper.status {
            case .ready:
                break
            case .outdated:
                status = .failed("Update the helper to finish setup.")
                showSettings = true
                return
            case .missing:
                status = .failed("Set up the helper first.")
                showSettings = true
                return
            }
            launch = ("/usr/bin/sudo", ["-n", Helper.path, "connect", group, user])
        }

        username = user
        Keychain.set(passwordDraft, for: "password")
        Keychain.set(TOTP.normalize(secretDraft), for: "totp")

        logLines = []
        tunnelIP = nil
        sessionExpiry = nil
        lastFailure = nil
        sentPassword = false
        sentAnswer = false
        buffer = ""
        status = .connecting
        appendLog("Starting \(group == "full" ? "full" : "split") tunnel for \(user)…")

        let task = Process()
        let input = Pipe()
        let output = Pipe()
        task.executableURL = URL(fileURLWithPath: launch.path)
        task.arguments = launch.arguments
        task.standardInput = input
        task.standardOutput = output
        task.standardError = output

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            let text = String(decoding: data, as: UTF8.self)
            Task { @MainActor [weak self] in self?.ingest(text) }
        }

        task.terminationHandler = { [weak self] finished in
            Task { @MainActor [weak self] in self?.handleTermination(finished) }
        }

        // Publish the pipes before starting: the client can print its first
        // prompt immediately, and the handler needs stdin to answer it.
        process = task
        stdinPipe = input
        outputPipe = output
        scheduleWatchdog()

        do {
            try task.run()
        } catch {
            process = nil
            stdinPipe = nil
            outputPipe = nil
            stopWatchdog()
            status = .failed("Could not start openconnect.")
            appendLog("error: \(error.localizedDescription)")
            return
        }
    }

    func disconnect() {
        guard process != nil || isConnected else { return }
        status = .disconnecting
        appendLog("Disconnecting…")

        DispatchQueue.global(qos: .userInitiated).async {
            _ = Helper.run("/usr/bin/sudo", ["-n", Helper.path, "stop"])
        }

        // openconnect exits on its own; this is just a safety net.
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard let self else { return }
            if case .disconnecting = self.status {
                self.finishSession()
            }
        }
    }

    func toggle() {
        if isConnected || isBusy {
            disconnect()
        } else {
            connect()
        }
    }

    /// Reads the Keychain lazily so launching the app never blocks on a
    /// keychain prompt before the window exists.
    func loadStoredSecrets() {
        if passwordDraft.isEmpty { passwordDraft = Keychain.get("password") ?? "" }
        if secretDraft.isEmpty { secretDraft = Keychain.get("totp") ?? "" }
    }

    func saveCredentials() {
        Keychain.set(passwordDraft, for: "password")
        Keychain.set(TOTP.normalize(secretDraft), for: "totp")
    }

    func forgetPassword() {
        passwordDraft = ""
        Keychain.delete("password")
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLogin = enabled
        LoginItem.set(enabled)
    }

    func installHelper() {
        helperProblem = nil
        do {
            try Helper.install()
            // sudo picks up the new sudoers rule asynchronously.
            for delay in [0.3, 0.8, 1.6] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self else { return }
                    self.refreshHelperState()
                    // After a successful (re)install, finish the job and connect.
                    if delay == 1.6, self.helperInstalled, self.autoConnect,
                       self.hasCredentials, !self.isConnected, !self.isBusy {
                        self.connect()
                    }
                }
            }
        } catch {
            helperProblem = error.localizedDescription
        }
    }

    func removeHelper() {
        do {
            try Helper.uninstall()
            refreshHelperState()
        } catch {
            helperProblem = error.localizedDescription
        }
    }

    func refreshHelperState() {
        switch Helper.status {
        case .ready:
            helperInstalled = true
            helperOutdated = false
            helperProblem = nil
        case .outdated(let installed):
            helperInstalled = false
            helperOutdated = true
            helperProblem = "Helper \(installed) is out of date — update it to match the app."
        case .missing:
            helperInstalled = false
            helperOutdated = false
        }
    }

    func clearError() {
        if case .failed = status { status = .disconnected }
    }

    // MARK: Output handling

    private func ingest(_ chunk: String) {
        buffer += chunk.replacingOccurrences(of: "\r", with: "\n")
        while let newline = buffer.firstIndex(of: "\n") {
            let line = String(buffer[buffer.startIndex..<newline])
            buffer = String(buffer[buffer.index(after: newline)...])
            handleLine(line)
        }

        let pending = buffer.trimmingCharacters(in: .whitespaces)
        if pending.hasSuffix("Password:") {
            buffer = ""
            handlePasswordPrompt()
        } else if pending.hasSuffix("Answer:") || pending.hasSuffix("Challenge:") || pending.hasSuffix("Response:") {
            buffer = ""
            handleAnswerPrompt()
        } else if pending.hasSuffix(":"), sentPassword, !sentAnswer {
            // Some gateways label the token field differently; after the
            // password, any remaining prompt is the one-time code.
            buffer = ""
            handleAnswerPrompt()
        }
    }

    private func handleLine(_ rawLine: String) {
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        if line.isEmpty { return }
        if line.hasPrefix("POST ") || line.hasPrefix("GET ") { return }
        if line.contains("SSL negotiation") || line.contains("XML POST enabled") { return }

        // openconnect 9.x: "Configured as 172.21.0.142 + 2a00:..., with SSL connected"
        // older versions:  "Connected as 134.61.x.x, using SSL"
        if let range = line.range(of: "Configured as ") ?? line.range(of: "Connected as ") {
            let rest = line[range.upperBound...]
            let address = (rest.split(separator: " ").first.map(String.init) ?? "")
                .trimmingCharacters(in: CharacterSet(charactersIn: ",;"))
            if !address.isEmpty { tunnelIP = address }
            lastFailure = nil
            status = .connected
            appendLog("Connected\(address.isEmpty ? "" : " — \(address)").")
            return
        }

        if let range = line.range(of: "Session authentication will expire at ") {
            sessionExpiry = String(line[range.upperBound...])
        }

        if line.contains("Login failed") {
            lastFailure = "Login failed — check your password."
        } else if line.contains("a password is required") {
            helperInstalled = false
            helperOutdated = false
            helperProblem = "The sudo rule is not active — reinstall the helper in Settings."
            lastFailure = "Helper not authorised."
        } else if line.contains("Failed to") || line.contains("Unrecoverable") || line.contains("error") {
            lastFailure = line
        } else if line.contains("Session terminated") || line.contains("Tunnel timeout") {
            lastFailure = line
        }

        appendLog(line)
    }

    private func handlePasswordPrompt() {
        guard !sentPassword else {
            fail(sentAnswer
                 ? "Login failed — wrong code or password."
                 : "The server rejected the password.")
            abortSession()
            return
        }
        sentPassword = true
        appendLog("Sending password…")
        send(passwordDraft)
    }

    private func handleAnswerPrompt() {
        guard !sentAnswer else {
            fail("The server asked for the code twice.")
            abortSession()
            return
        }
        guard let code = currentCode else {
            fail("No token code available.")
            abortSession()
            return
        }
        sentAnswer = true
        appendLog("Sending one-time code…")
        send(code)
    }

    private func send(_ line: String) {
        guard let handle = stdinPipe?.fileHandleForWriting else { return }
        try? handle.write(contentsOf: Data((line + "\n").utf8))
    }

    /// Closing stdin makes openconnect give up on its next prompt (EOF) and
    /// unwind its routes — the only signal a non-root app can send it.
    private func abortSession() {
        try? stdinPipe?.fileHandleForWriting.close()
    }

    private func handleTermination(_ finished: Process) {
        let code = finished.terminationStatus
        stopWatchdog()
        if case .failed = status {
            finishSession()
            return
        }
        switch status {
        case .connected, .disconnecting:
            status = .disconnected
            appendLog("Disconnected.")
        case .connecting:
            let reason = lastFailure ?? (code == 0 ? "Connection closed." : "openconnect exited (\(code)).")
            status = .failed(reason)
            appendLog(reason)
        case .disconnected, .failed:
            break
        }
        finishSession()
    }

    private func finishSession() {
        stopWatchdog()
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        try? stdinPipe?.fileHandleForWriting.close()
        process = nil
        stdinPipe = nil
        outputPipe = nil
        sentPassword = false
        sentAnswer = false
        buffer = ""
        tunnelIP = nil
        if case .disconnecting = status { status = .disconnected }
        if case .connected = status { status = .disconnected }
        if case .connecting = status { status = .failed(lastFailure ?? "Connection failed.") }
        refreshHelperState()
    }

    private func fail(_ message: String) {
        lastFailure = message
        status = .failed(message)
        appendLog(message)
    }

    private func appendLog(_ line: String) {
        logLines.append(line)
        if logLines.count > 400 { logLines.removeFirst(logLines.count - 400) }
    }

    // MARK: Watchdog & adoption

    private func scheduleWatchdog() {
        stopWatchdog()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if case .connecting = self.status {
                self.fail("Timed out while connecting.")
                self.abortSession()
            }
        }
        watchdog = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 90, execute: item)
    }

    private func stopWatchdog() {
        watchdog?.cancel()
        watchdog = nil
    }

    /// Picks up sessions that were already running when the app launched and
    /// notices when one of them disappears.
    private func startStateSync() {
        syncTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.process == nil else { return }
                let external = Helper.connectionPID() != nil
                if external, !self.isConnected, !self.isBusy {
                    self.status = .connected
                    self.appendLog("Re-attached to a running session.")
                } else if !external, self.isConnected {
                    self.status = .disconnected
                    self.tunnelIP = nil
                    self.sessionExpiry = nil
                }
            }
        }
    }

    // MARK: Previews

    static func preview(connected: Bool = true) -> VPNModel {
        let model = VPNModel()
        model.suppressPersistence = true
        model.username = "ab123456"
        model.passwordDraft = "secret"
        model.secretDraft = "JBSWY3DPEHPK3PXP"
        model.status = connected ? .connected : .disconnected
        model.tunnelIP = connected ? "172.21.0.142" : nil
        model.sessionExpiry = connected ? "Thu, 05 Nov 2026 09:50:39 CET" : nil
        model.logLines = [
            "Starting split tunnel for ab123456…",
            "Sending password…",
            "Sending one-time code…",
            "Connected — 172.21.0.142",
        ]
        return model
    }
}

/// Test hook: `RWTHVPN_DEBUG_COMMAND="path arg arg"` replaces the privileged
/// helper so the connect state machine can be exercised without sudo.
enum DebugCommand {
    static var current: (path: String, arguments: [String])? {
        guard let raw = ProcessInfo.processInfo.environment["RWTHVPN_DEBUG_COMMAND"],
              !raw.isEmpty
        else { return nil }
        var parts = raw.split(separator: " ").map(String.init)
        guard let executable = parts.first else { return nil }
        parts.removeFirst()
        return (executable, parts)
    }
}
