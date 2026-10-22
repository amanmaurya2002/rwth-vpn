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
        ScrollView {
            VStack(spacing: 20) {
                hero
                connectionCard
                tunnelSection
                codeSection
                logSection
            }
            .padding(24)
        }
        .scrollIndicators(.hidden)
        .frame(width: 460, height: 680)
        .background(.regularMaterial)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    model.showSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("Settings")
            }
        }
        .sheet(isPresented: $model.showSettings) {
            SettingsView(model: model)
        }
    }

    private var hero: some View {
        VStack(spacing: 12) {
            Image(systemName: model.isConnected ? "lock.shield.fill" : "lock.shield")
                .font(.system(size: 54, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(accent)
                .symbolEffect(.pulse, isActive: model.isBusy)
                .accessibilityHidden(true)

            VStack(spacing: 4) {
                Text(model.isConnected ? "Connected" : "RWTH VPN")
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                Text(model.statusText)
                    .font(.subheadline)
                    .foregroundStyle(hasError ? .red : .secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var connectionCard: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.isConnected
                         ? (model.group == "full" ? "Full tunnel" : "Split tunnel")
                         : "No active tunnel")
                        .font(.headline)
                    Text(detailText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                statusBadge
            }

            Button {
                model.toggle()
            } label: {
                Label(model.buttonTitle,
                      systemImage: model.isConnected ? "xmark.circle.fill" : "lock.open.fill")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .tint(model.isConnected ? .red : Brand.blue)
            .disabled(model.isBusy)
            .keyboardShortcut(.return, modifiers: [.command])
        }
        .padding(18)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        }
    }

    private var statusBadge: some View {
        Label(model.isConnected ? "Active" : (hasError ? "Error" : "Offline"),
              systemImage: model.isConnected ? "checkmark.circle.fill" : "circle")
            .font(.caption.weight(.semibold))
            .foregroundStyle(accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(accent.opacity(0.12), in: Capsule())
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

    private var tunnelSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Tunnel mode", systemImage: "arrow.triangle.branch")
                .font(.headline)
            Picker("Tunnel mode", selection: $model.group) {
                Text("Split tunnel").tag("split")
                Text("Full tunnel").tag("full")
            }
            .pickerStyle(.segmented)
            .disabled(model.isConnected || model.isBusy)
            Text(model.group == "full"
                 ? "All traffic goes through RWTH."
                 : "Only RWTH addresses go through the tunnel.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private var codeSection: some View {
        if model.usesAutomaticCode {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = TOTP.secondsRemaining(at: context.date)
                let code = TOTP.code(secret: TOTP.normalize(model.secretDraft), at: context.date)
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("One-time code", systemImage: "key.fill")
                            .font(.headline)
                        Text(code ?? "------")
                            .font(.system(.title2, design: .monospaced, weight: .semibold))
                        if code == nil {
                            Text("Check the token secret in Settings.")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    Spacer()
                    ProgressView(value: Double(remaining), total: 30)
                        .progressViewStyle(.circular)
                        .tint(Brand.blue)
                        .overlay {
                            Text("\(remaining)")
                                .font(.caption.weight(.semibold))
                                .monospacedDigit()
                        }
                        .frame(width: 42, height: 42)
                }
                .padding(16)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Label("One-time code", systemImage: "key.fill")
                    .font(.headline)
                TextField("123456", text: $model.manualCode)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.title3, design: .monospaced, weight: .medium))
                    .onChange(of: model.manualCode) { _, newValue in
                        let digits = String(newValue.filter(\.isNumber).prefix(6))
                        if digits != newValue { model.manualCode = digits }
                    }
                Text("Add a token secret in Settings to generate codes automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var logSection: some View {
        DisclosureGroup(isExpanded: $model.showLog) {
            VStack(alignment: .leading, spacing: 4) {
                if model.logLines.isEmpty {
                    Text("No output yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(model.logLines.suffix(6).enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(.caption2, design: .monospaced))
                        .lineLimit(1)
                }
                if !model.logLines.isEmpty {
                    Button("Copy log") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(model.logLines.joined(separator: "\n"), forType: .string)
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
        } label: {
            Label("Connection log", systemImage: "text.append")
                .font(.headline)
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Settings sheet

struct SettingsView: View {
    @ObservedObject var model: VPNModel

    var body: some View {
        Form {
            HStack {
                Text("Settings")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Done") {
                    model.saveCredentials()
                    model.showSettings = false
                }
                .keyboardShortcut(.defaultAction)
            }

            Section("Credentials") {
                field("Username", hint: "Your RWTH account, e.g. ab123456") {
                TextField("ab123456", text: $model.username)
                }

                field("VPN password", hint: "The VPN password from IdM SelfService — not your SSO password.") {
                    SecureField("VPN password", text: $model.passwordDraft)
                }

                field(
                    "Token secret",
                    hint: "Base32 secret or the full otpauth:// link. The app then generates the code for you."
                ) {
                    TextField("JBSWY3DPEHPK3PXP", text: $model.secretDraft)
                        .font(.system(.body, design: .monospaced))
                }
            }

            Section("Privileged helper") {
                helperCard
            }

            Section("Behavior") {
                rowToggle("Connect when the app opens", isOn: $model.autoConnect)
                rowToggle("Launch at login", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
            }

            HStack(spacing: 8) {
                Button("Save") { model.saveCredentials() }
                    .buttonStyle(.borderedProminent)
                Button("Forget password") { model.forgetPassword() }
                    .buttonStyle(.bordered)
                Button("Check for updates") {
                    if let url = URL(string: AppInfo.releases) { NSWorkspace.shared.open(url) }
                }
                .buttonStyle(.bordered)
                Spacer()
                Text("v\(AppInfo.version)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            if let problem = model.helperProblem {
                Text(problem)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("vpn.rwth-aachen.de · v\(AppInfo.version) · credentials in your Keychain")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 620)
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
                Text(model.helperInstalled
                     ? "Helper installed"
                     : (model.helperOutdated ? "Helper update available" : "Helper needs setup"))
                    .font(.system(size: 11, weight: .medium))
                Spacer()
            }
            Text(model.helperInstalled
                 ? "Connects without asking for your admin password."
                 : (model.helperOutdated
                    ? "The bundled VPN client changed. Update the helper once to match this version."
                    : "One-time setup so the app can bring the tunnel up without an admin prompt every time."))
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button(model.helperInstalled
                       ? "Reinstall…"
                       : (model.helperOutdated ? "Update…" : "Install…")) {
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
