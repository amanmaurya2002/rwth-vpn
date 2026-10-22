import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = VPNModel()

    private var window: NSWindow?
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMainMenu()
        showWindow()

        model.$status
            .receive(on: RunLoop.main)
            .sink { [weak self] status in self?.syncStatusItem(status) }
            .store(in: &cancellables)

        syncStatusItem(model.status)
        model.loadStoredSecrets()

        // Migration aid: an outdated helper would fail silently, so surface
        // the one-click reinstall straight away.
        if Helper.isInstalled, !Helper.isUpToDate {
            model.showSettings = true
        }

        // Connect automatically when credentials are already saved.
        if model.autoConnect, model.hasCredentials, !model.isConnected {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.model.connect()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    // MARK: - Window

    private func showWindow() {
        if window == nil {
            let hosting = NSHostingController(rootView: MainView(model: model))
            let newWindow = NSWindow(contentViewController: hosting)
            newWindow.title = "RWTH VPN"
            newWindow.styleMask = [.titled, .closable, .miniaturizable]
            newWindow.isReleasedWhenClosed = false
            newWindow.setContentSize(NSSize(width: 420, height: 580))
            newWindow.center()
            window = newWindow
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Menu bar status (only while a session exists)

    private func syncStatusItem(_ status: VPNModel.Status) {
        let shouldShow: Bool
        switch status {
        case .connecting, .connected, .disconnecting: shouldShow = true
        case .disconnected, .failed: shouldShow = false
        }

        if shouldShow, statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.target = self
            item.button?.action = #selector(statusItemClicked)
            item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
            item.button?.toolTip = "RWTH VPN"
            statusItem = item
        } else if !shouldShow, let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }

        guard let button = statusItem?.button else { return }
        let symbol: String
        switch status {
        case .connected: symbol = "lock.shield.fill"
        case .connecting, .disconnecting: symbol = "arrow.triangle.2.circlepath"
        default: symbol = "lock.shield"
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "RWTH VPN")
        image?.isTemplate = true
        button.image = image
        switch status {
        case .connected: button.contentTintColor = .systemGreen
        case .connecting, .disconnecting: button.contentTintColor = .systemOrange
        default: button.contentTintColor = nil
        }
    }

    @objc private func statusItemClicked() {
        if let event = NSApp.currentEvent, event.type == .rightMouseUp {
            showStatusMenu()
        } else {
            showWindow()
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func showStatusMenu() {
        guard let item = statusItem else { return }
        let menu = NSMenu()
        menu.addItem(withTitle: "Show RWTH VPN", action: #selector(menuShow), keyEquivalent: "")
        menu.addItem(withTitle: model.isConnected ? "Disconnect" : "Connect",
                     action: #selector(menuToggle), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit RWTH VPN", action: #selector(menuQuit), keyEquivalent: "q")
        for entry in menu.items { entry.target = self }

        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    @objc private func menuShow() { showWindow() }
    @objc private func menuToggle() { model.toggle() }
    @objc private func menuQuit() { NSApp.terminate(nil) }

    // MARK: - Menu

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        let aboutItem = appMenu.addItem(withTitle: "About RWTH VPN", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        let licencesItem = appMenu.addItem(withTitle: "Licences", action: #selector(openLicences), keyEquivalent: "")
        licencesItem.target = self
        appMenu.addItem(.separator())
        let updatesItem = appMenu.addItem(withTitle: "Check for Updates…", action: #selector(openReleases), keyEquivalent: "")
        updatesItem.target = self
        let issuesItem = appMenu.addItem(withTitle: "Report an Issue…", action: #selector(openIssues), keyEquivalent: "")
        issuesItem.target = self
        appMenu.addItem(.separator())
        let settingsItem = appMenu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide RWTH VPN", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit RWTH VPN", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu

        NSApp.mainMenu = mainMenu
    }

    @objc private func showAbout() {
        let credits = NSMutableAttributedString(
            string: AppInfo.disclaimer + "\n\n",
            attributes: [.font: NSFont.systemFont(ofSize: 11)]
        )
        credits.append(NSAttributedString(
            string: AppInfo.repository,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .link: URL(string: AppInfo.repository)!,
            ]
        ))
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: AppInfo.name,
            .applicationVersion: AppInfo.version,
            .version: "build \(AppInfo.build)",
            .credits: credits,
        ])
    }

    @objc private func openLicences() {
        if let url = Bundle.main.url(forResource: "THIRD-PARTY-NOTICES", withExtension: "md") {
            NSWorkspace.shared.open(url)
        } else if let url = URL(string: AppInfo.repository) {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openReleases() {
        if let url = URL(string: AppInfo.releases) { NSWorkspace.shared.open(url) }
    }

    @objc private func openIssues() {
        if let url = URL(string: AppInfo.issues) { NSWorkspace.shared.open(url) }
    }

    @objc private func openSettings() {
        showWindow()
        model.showSettings = true
    }
}
