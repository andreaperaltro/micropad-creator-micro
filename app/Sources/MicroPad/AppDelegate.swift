import AppKit
import ApplicationServices
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = AppController()
    private var statusItem: NSStatusItem!
    private var editorWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.write("LAUNCH MicroPad · Accessibility=\(AXIsProcessTrusted())")
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        controller.onStatusChange = { [weak self] in self?.refreshStatus() }
        refreshStatus()

        if !controller.accessibilityOK { controller.requestAccessibility() }

        // First launch: open the editor and enable launch at login.
        if !UserDefaults.standard.bool(forKey: "launchedBefore") {
            UserDefaults.standard.set(true, forKey: "launchedBefore")
            controller.launchAtLogin = true
            openEditor()
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach { controller.handleURL($0) }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openEditor()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.pad.release()
    }

    // MARK: Menu bar

    private func refreshStatus() {
        guard let button = statusItem?.button else { return }
        let symbol = controller.connected ? "square.grid.3x3.fill" : "square.grid.3x3"
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "MicroPad")
        button.appearsDisabled = !controller.connected

        let menu = NSMenu()
        let status = controller.connected
            ? "Pad connected · \(controller.activeProfile.name)"
            : "Pad not connected"
        menu.addItem(withTitle: status, action: nil, keyEquivalent: "").isEnabled = false
        if !controller.frontAppName.isEmpty {
            menu.addItem(withTitle: "Active app: \(controller.frontAppName)", action: nil, keyEquivalent: "").isEnabled = false
        }
        menu.addItem(.separator())
        menu.addItem(item("Open editor…", #selector(openEditorAction), "e"))
        menu.addItem(item("Test flash", #selector(testFlash), ""))
        let keys = item("Key LEDs", #selector(toggleKeyLEDs), "")
        keys.state = controller.keyLEDs ? .on : .off
        menu.addItem(keys)
        let edge = item("Edge LEDs", #selector(toggleEdgeLEDs), "")
        edge.state = controller.edgeLEDs ? .on : .off
        menu.addItem(edge)
        menu.addItem(.separator())
        let login = item("Launch at login", #selector(toggleLogin), "")
        login.state = controller.launchAtLogin ? .on : .off
        menu.addItem(login)
        if !controller.accessibilityOK {
            menu.addItem(.separator())
            menu.addItem(item("⚠︎ Grant Accessibility permission…", #selector(openAccessibility), ""))
        }
        menu.addItem(.separator())
        menu.addItem(item("Quit MicroPad", #selector(quit), "q"))
        statusItem.menu = menu
    }

    private func item(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        return i
    }

    @objc private func openEditorAction() { openEditor() }
    @objc private func testFlash() { controller.testFlash() }
    @objc private func toggleKeyLEDs() { controller.keyLEDs.toggle() }
    @objc private func toggleEdgeLEDs() { controller.edgeLEDs.toggle() }
    @objc private func toggleLogin() { controller.launchAtLogin.toggle() }
    @objc private func openAccessibility() { controller.requestAccessibility(); controller.openAccessibilitySettings() }
    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: Editor

    func openEditor() {
        if editorWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1080, height: 680),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false)
            window.title = "MicroPad"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(
                rootView: EditorView()
                    .environmentObject(controller)
                    .environmentObject(controller.store))
            window.center()
            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: window, queue: .main
            ) { _ in
                // Give focus back to the previous app so the pad goes back to work.
                NSApp.hide(nil)
            }
            editorWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        editorWindow?.makeKeyAndOrderFront(nil)
    }
}
