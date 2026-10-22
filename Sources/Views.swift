import AppKit
import SwiftUI

enum Brand {
    static let blue = Color(red: 0.00, green: 0.38, blue: 0.70)
    static let cyan = Color(red: 0.00, green: 0.58, blue: 0.78)
    static let red = Color(red: 0.80, green: 0.18, blue: 0.18)

    static var gradient: LinearGradient {
        LinearGradient(colors: [blue, cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// A prominent button that looks the same whether or not the window is key
/// (the stock bordered style turns grey in inactive windows).
struct ProminentButtonStyle: ButtonStyle {
    var color: Color
    var enabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(color.opacity(!enabled ? 0.55 : (configuration.isPressed ? 0.82 : 1)))
            )
            .scaleEffect(configuration.isPressed ? 0.995 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Main window

struct MainView: View {
    @ObservedObject var model: VPNModel

    private var accent: Color {
        switch model.status {
        case .connected: return .green
        case .connecting, .disconnecting: return .orange
        case .failed: return .red
        case .disconnected: return Color.secondary
        }
    }

    private var hasError: Bool {
        if case .failed = model.status { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            statusCard
            connectButton
            tunnelSection
            codeSection
            logSection
            Spacer(minLength: 0)
            footer
        }
        .padding(24)
        .frame(width: 420, height: 580, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $model.showSettings) {
            SettingsView(model: model)
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Brand.gradient)
                .frame(width: 52, height: 52)
                .overlay(
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text("RWTH VPN")
                    .font(.system(size: 20, weight: .bold))
                HStack(spacing: 6) {
                    Circle().fill(accent).frame(width: 7, height: 7)
                    Text(model.statusText)
                        .font(.system(size: 12))
                        .foregroundStyle(hasError ? Color.red : Color.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            Button {
                model.showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Settings")
        }
    }

    private var statusCard: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.isConnected
                     ? (model.group == "full" ? "Full tunnel" : "Split tunnel")
                     : "No active tunnel")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(model.isConnected ? Color.primary : Color.secondary)
                Text(detailText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Spacer(minLength: 0)
            Text(model.isConnected ? "Connected" : (hasError ? "Error" : "Offline"))
                .font(.system(size: 10, weight: .semibold))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(accent.opacity(0.14)))
                .foregroundStyle(accent)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }

    private var detailText: String {
        if model.isConnected {
            var parts: [String] = []
            if let ip = model.tunnelIP { parts.append(ip) }
            if let expiry = model.sessionExpiry { parts.append("until \(expiry)") }
            return parts.isEmpty ? "Tunnel is up" : parts.joined(separator: " · ")
        }
        return "Nothing is routed through RWTH."
    }

    private var connectButton: some View {
        Button {
            model.toggle()
        } label: {
            HStack(spacing: 8) {
                if model.isBusy {
                    ProgressView().controlSize(.small).tint(.white)
                } else {
                    Image(systemName: model.isConnected ? "xmark" : "lock.open.fill")
                        .font(.system(size: 13, weight: .bold))
                }
                Text(model.buttonTitle)
                    .font(.system(size: 14, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
        }
        .buttonStyle(ProminentButtonStyle(color: model.isConnected ? Brand.red : Brand.blue,
                                          enabled: !model.isBusy))
        .disabled(model.isBusy)
        .keyboardShortcut(.return, modifiers: [.command])
    }

    private var tunnelSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tunnel")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 2) {
                segment("Split", value: "split", detail: "RWTH only")
                segment("Full", value: "full", detail: "Everything")
            }
            .padding(2)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
            .opacity(model.isConnected || model.isBusy ? 0.55 : 1)

            Text(model.group == "full"
                 ? "All traffic goes through RWTH."
                 : "Only RWTH addresses go through the tunnel.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }

    private func segment(_ title: String, value: String, detail: String) -> some View {
        let selected = model.group == value
        return Button {
            guard !model.isConnected, !model.isBusy else { return }
            model.group = value
        } label: {
            HStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 12, weight: selected ? .semibold : .regular))
                Text(detail)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(selected ? Color.primary : Color.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                    .fill(selected ? Color(nsColor: .controlBackgroundColor) : Color.clear)
                    .shadow(color: .black.opacity(selected ? 0.12 : 0), radius: 1, y: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var codeSection: some View {
        if model.usesAutomaticCode {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = TOTP.secondsRemaining(at: context.date)
                let code = TOTP.code(secret: TOTP.normalize(model.secretDraft), at: context.date)
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("One-time code")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(code ?? "------")
                            .font(.system(size: 20, weight: .semibold, design: .monospaced))
                        if code == nil {
                            Text("Token secret not recognised — check Settings.")
                                .font(.system(size: 9))
                                .foregroundStyle(.red)
                        }
                    }
                    Spacer(minLength: 0)
                    ZStack {
                        Circle().stroke(Color.primary.opacity(0.08), lineWidth: 3)
                        Circle()
                            .trim(from: 0, to: CGFloat(remaining) / 30)
                            .stroke(Brand.blue, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text("\(remaining)")
                            .font(.system(size: 10, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 34, height: 34)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("One-time code")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("123456", text: $model.manualCode)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 15, weight: .medium, design: .monospaced))
                    .onChange(of: model.manualCode) { _, newValue in
                        let digits = String(newValue.filter(\.isNumber).prefix(6))
                        if digits != newValue { model.manualCode = digits }
                    }
                Text("Add your token secret in Settings to generate codes automatically.")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
        }
    }

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) { model.showLog.toggle() }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                            .rotationEffect(.degrees(model.showLog ? 90 : 0))
                        Text("Log")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer()

                if model.showLog, !model.logLines.isEmpty {
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(model.logLines.joined(separator: "\n"), forType: .string)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                }
            }

            if model.showLog {
                logBox
            } else {
                detailsCard
            }
        }
    }

    private var logBox: some View {
        let lines = model.logLines.suffix(6)
        return VStack(alignment: .leading, spacing: 2) {
            if lines.isEmpty {
                Text("No output yet.")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: 90, alignment: .topLeading)
        .clipped()
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }

    private var detailsCard: some View {
        VStack(spacing: 7) {
            detailRow("Server", "vpn.rwth-aachen.de")
            detailRow("Group", model.group == "full" ? "RWTH-VPN (Full Tunnel)" : "RWTH-VPN (Split Tunnel)")
            detailRow("Token", model.usesAutomaticCode ? "Automatic, every 30 s" : "Entered manually")
        }
        .padding(12)
        .frame(height: 90, alignment: .center)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Button {
                model.showSettings = true
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            Spacer()
            Button {
                NSApp.terminate(nil)
            } label: {
                Text("Quit")
            }
        }
        .buttonStyle(.plain)
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
    }
}

// MARK: - Settings sheet

struct SettingsView: View {
    @ObservedObject var model: VPNModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Settings")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Button("Done") {
                    model.saveCredentials()
                    model.showSettings = false
                }
                .keyboardShortcut(.defaultAction)
            }

            field("Username", hint: "Your RWTH account, e.g. ab123456") {
                TextField("ab123456", text: $model.username)
                    .textFieldStyle(.roundedBorder)
            }

            field("VPN password", hint: "The VPN password from IdM SelfService — not your SSO password.") {
                SecureField("VPN password", text: $model.passwordDraft)
                    .textFieldStyle(.roundedBorder)
            }

            field(
                "Token secret",
                hint: "Base32 secret or the full otpauth:// link. The app then generates the code for you."
            ) {
                TextField("JBSWY3DPEHPK3PXP", text: $model.secretDraft)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
            }

            helperCard

            VStack(spacing: 8) {
                rowToggle("Connect when the app opens", isOn: $model.autoConnect)
                rowToggle("Launch at login", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
            }

            HStack(spacing: 8) {
                Button("Save") { model.saveCredentials() }
                    .controlSize(.small)
                Button("Forget password") { model.forgetPassword() }
                    .controlSize(.small)
                Spacer()
                Text("v2.0")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }

            if let problem = model.helperProblem {
                Text(problem)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
            Text("vpn.rwth-aachen.de · openconnect · credentials in your Keychain")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
        .padding(24)
        .frame(width: 440, height: 560, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func field<Content: View>(
        _ title: String,
        hint: String?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            content()
            if let hint {
                Text(hint)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func rowToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title).font(.system(size: 11))
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
    }

    private var helperCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: model.helperInstalled ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(model.helperInstalled ? Color.green : Color.orange)
                Text(model.helperInstalled ? "Helper installed" : "Helper needs setup")
                    .font(.system(size: 11, weight: .medium))
                Spacer()
            }
            Text(model.helperInstalled
                 ? "Connects without asking for your admin password."
                 : "One-time setup so the app can bring the tunnel up without an admin prompt every time.")
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button(model.helperInstalled ? "Reinstall…" : "Install…") {
                    model.installHelper()
                }
                .controlSize(.small)
                if model.helperInstalled {
                    Button("Remove") { model.removeHelper() }
                        .controlSize(.small)
                }
                Spacer()
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }
}
