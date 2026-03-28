import AppKit
import SwiftUI
import AVFoundation

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
                accessibilityDescription: "Claude Code Handsfree Voice"
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

        // Voice selection submenu
        let voiceItem = NSMenuItem(title: "Voice", action: nil, keyEquivalent: "")
        let voiceMenu = NSMenu()
        // System default option — follows System Settings > Spoken Content
        let systemItem = NSMenuItem(title: "System Default", action: #selector(selectVoice(_:)), keyEquivalent: "")
        systemItem.representedObject = "system"
        voiceMenu.addItem(systemItem)
        voiceMenu.addItem(NSMenuItem.separator())

        let voices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") && ($0.quality == .enhanced || $0.quality == .premium || $0.identifier.contains("siri")) }
            .sorted { $0.quality.rawValue > $1.quality.rawValue || ($0.quality == $1.quality && $0.name < $1.name) }
        for voice in voices {
            let quality = voice.quality == .premium ? "Premium" : voice.quality == .enhanced ? "Enhanced" : "Siri"
            let item = NSMenuItem(title: "\(voice.name) (\(quality))", action: #selector(selectVoice(_:)), keyEquivalent: "")
            item.representedObject = voice.identifier
            voiceMenu.addItem(item)
        }
        voiceItem.submenu = voiceMenu
        menu.addItem(voiceItem)

        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(title: "Voice Settings...", action: #selector(openSpokenContent), keyEquivalent: ","))

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Claude Code Handsfree Voice", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

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
            print("[HandsFree] Panel visible: \(panel.isVisible), frame: \(panel.frame)")
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

    @objc private func selectVoice(_ sender: NSMenuItem) {
        if let identifier = sender.representedObject as? String {
            AppState.shared.setVoice(identifier)
        }
    }

    @objc private func openSpokenContent() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.universalaccess?SpokenContent")!)
    }

    @objc private func testTTS() {
        AppState.shared.handleHookMessage(
            "Hello! This is Claude Code Handsfree Voice. I just finished a task. The tests are passing and the code has been committed."
        )
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        let mode = AppState.shared.responseMode
        let selectedVoice = AppState.shared.selectedVoiceId
        let panelVisible = floatingPanel?.isVisible ?? false
        for item in menu.items {
            if item.action == #selector(togglePanel) {
                item.title = panelVisible ? "Hide Panel" : "Show Panel"
            }
            if let sub = item.submenu {
                for subItem in sub.items {
                    // Response mode checkmarks
                    switch subItem.title {
                    case "Full Response": subItem.state = mode == .full ? .on : .off
                    case "Summary (First Sentence)": subItem.state = mode == .summary ? .on : .off
                    case "Notify Only": subItem.state = mode == .notify ? .on : .off
                    default: break
                    }
                    // Voice selection checkmarks
                    if subItem.action == #selector(selectVoice(_:)),
                       let id = subItem.representedObject as? String {
                        subItem.state = id == selectedVoice ? .on : .off
                    }
                }
            }
        }
    }
}
