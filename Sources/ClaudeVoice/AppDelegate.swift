import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var floatingPanel: FloatingPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        setupFloatingPanel()
        HookServer.shared.start()
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = NSImage(
                systemSymbolName: "waveform.circle.fill",
                accessibilityDescription: "Claude Voice"
            )
        }

        let menu = NSMenu()
        menu.delegate = self

        let showItem = NSMenuItem(title: "Show Panel", action: #selector(togglePanel), keyEquivalent: "s")
        showItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(showItem)

        menu.addItem(NSMenuItem.separator())

        // Response mode submenu
        let responseModeItem = NSMenuItem(title: "Response Mode", action: nil, keyEquivalent: "")
        let responseModeMenu = NSMenu()
        responseModeMenu.addItem(NSMenuItem(title: "Full Response", action: #selector(setModeFull), keyEquivalent: ""))
        responseModeMenu.addItem(NSMenuItem(title: "Summary (First Sentence)", action: #selector(setModeSummary), keyEquivalent: ""))
        responseModeMenu.addItem(NSMenuItem(title: "Notify Only", action: #selector(setModeNotify), keyEquivalent: ""))
        responseModeItem.submenu = responseModeMenu
        menu.addItem(responseModeItem)

        menu.addItem(NSMenuItem.separator())

        let testItem = NSMenuItem(title: "Test TTS", action: #selector(testTTS), keyEquivalent: "t")
        testItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(testItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Claude Voice", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    private func setupFloatingPanel() {
        let panel = FloatingPanel()
        panel.isReleasedWhenClosed = false
        panel.orderFrontRegardless()
        self.floatingPanel = panel

        // Ensure it's visible after a short delay (workaround for launch timing)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if !(panel.isVisible) {
                panel.setIsVisible(true)
                panel.orderFrontRegardless()
            }
            print("[ClaudeVoice] Panel visible: \(panel.isVisible), frame: \(panel.frame)")
        }
    }

    // MARK: - Actions

    @objc private func togglePanel() {
        if let panel = floatingPanel, panel.isVisible {
            panel.orderOut(nil)
        } else {
            floatingPanel?.orderFrontRegardless()
        }
    }

    @objc private func setModeFull() { AppState.shared.setResponseMode(.full) }
    @objc private func setModeSummary() { AppState.shared.setResponseMode(.summary) }
    @objc private func setModeNotify() { AppState.shared.setResponseMode(.notify) }

    @objc private func testTTS() {
        AppState.shared.handleHookMessage(
            "Hello! This is Claude Voice. I just finished a task. The tests are passing and the code has been committed."
        )
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        let mode = AppState.shared.responseMode
        for item in menu.items {
            if let sub = item.submenu {
                for subItem in sub.items {
                    switch subItem.title {
                    case "Full Response": subItem.state = mode == .full ? .on : .off
                    case "Summary (First Sentence)": subItem.state = mode == .summary ? .on : .off
                    case "Notify Only": subItem.state = mode == .notify ? .on : .off
                    default: break
                    }
                }
            }
        }
    }
}
