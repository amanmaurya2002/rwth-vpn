import Foundation

/// Shared credential and helper operations used by the app and CLI adapters.
enum VPNCore {
    static let usernameAccount = "username"

    static func loadUsername() -> String {
        UserDefaults.standard.string(forKey: "username")
            ?? Keychain.get(usernameAccount)
            ?? ""
    }

    static func saveUsername(_ username: String) {
        UserDefaults.standard.set(username, forKey: "username")
        Keychain.set(username, for: usernameAccount)
    }

    static func loadPassword() -> String { Keychain.get("password") ?? "" }
    static func loadTOTPSecret() -> String { Keychain.get("totp") ?? "" }

    static func saveCredentials(username: String, password: String, secret: String) {
        saveUsername(username)
        Keychain.set(password, for: "password")
        Keychain.set(TOTP.normalize(secret), for: "totp")
    }

    static func currentCode(secret: String, manualCode: String? = nil) -> String? {
        let normalized = TOTP.normalize(secret)
        if !normalized.isEmpty, let code = TOTP.code(secret: normalized) { return code }
        let manual = manualCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return manual.count == 6 && manual.allSatisfy(\.isNumber) ? manual : nil
    }

    static func validateUsername(_ username: String) -> String? {
        let value = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard value.range(of: "^[a-z]{2}[0-9]{6}$", options: .regularExpression) != nil else {
            return nil
        }
        return value
    }
}
