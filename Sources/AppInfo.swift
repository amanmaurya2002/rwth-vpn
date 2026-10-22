import Foundation

/// Single place for versions, links and product strings.
enum AppInfo {
    static let cliVersion = "1.2.6"
    static let name = "RWTH VPN"
    static let repository = "https://github.com/amanmaurya2002/rwth-vpn"
    static let releases = repository + "/releases/latest"
    static let latestReleaseAPI = "https://api.github.com/repos/amanmaurya2002/rwth-vpn/releases/latest"
    static let issues = repository + "/issues/new/choose"

    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
    }

    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }

    /// Contract version between app and privileged helper; bump
    /// Resources/helper-version.txt when the helper or payload changes.
    static var helperVersion: String {
        let url: URL?
        if let root = ProcessInfo.processInfo.environment["RWTH_VPN_RESOURCE_ROOT"] {
            url = URL(fileURLWithPath: root, isDirectory: true)
                .appendingPathComponent("helper-version.txt")
        } else if let executable = ProcessInfo.processInfo.arguments.first {
            url = URL(fileURLWithPath: executable).deletingLastPathComponent()
                .appendingPathComponent("resources/helper-version.txt")
        } else {
            url = Bundle.main.url(forResource: "helper-version", withExtension: "txt")
        }
        guard let url,
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return "0" }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static let disclaimer = """
    Unofficial student project. Not affiliated with RWTH Aachen University or \
    its IT Center. Use at your own risk; the official client is Cisco Secure \
    Client.
    """
}
