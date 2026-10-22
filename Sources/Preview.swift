import AppKit
import SwiftUI

/// Development helper: renders the real AppKit-backed controls by hosting the
/// views in an off-screen window and capturing the view hierarchy.
/// Triggered by `--render-preview <directory>`; never used in normal runs.
@MainActor
enum PreviewRenderer {
    static func render() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        Keychain.isEnabled = false

        let directory = CommandLine.arguments.last.flatMap { $0.hasPrefix("/") ? $0 : nil } ?? "/tmp"
        let base = URL(fileURLWithPath: directory)

        let connected = VPNModel.preview(connected: true)
        capture(MainView(model: connected), size: NSSize(width: 420, height: 580),
                to: base.appendingPathComponent("preview-main.png"))

        let logModel = VPNModel.preview(connected: true)
        logModel.showLog = true
        capture(MainView(model: logModel), size: NSSize(width: 420, height: 580),
                to: base.appendingPathComponent("preview-log.png"))

        let idle = VPNModel.preview(connected: false)
        idle.secretDraft = ""
        idle.manualCode = "123456"
        capture(MainView(model: idle), size: NSSize(width: 420, height: 580),
                to: base.appendingPathComponent("preview-idle.png"))

        let settings = VPNModel.preview(connected: false)
        capture(SettingsView(model: settings), size: NSSize(width: 440, height: 560),
                to: base.appendingPathComponent("preview-settings.png"))
    }

    private static func capture(_ view: some View, size: NSSize, to url: URL) {
        let window = NSWindow(
            contentRect: NSRect(origin: NSPoint(x: 40, y: 40), size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
        window.ignoresMouseEvents = true

        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: size)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        RunLoop.current.run(until: Date().addingTimeInterval(0.6))

        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            print("capture failed: \(url.lastPathComponent)")
            window.orderOut(nil)
            return
        }
        host.cacheDisplay(in: host.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: url)
            print("wrote \(url.path)")
        }
        window.orderOut(nil)
    }
}
