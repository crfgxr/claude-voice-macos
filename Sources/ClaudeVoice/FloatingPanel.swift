import AppKit
import SwiftUI

/// NSHostingView subclass that accepts clicks even when the window is inactive
final class ClickThroughHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
}

final class FloatingPanel: NSPanel {
    init() {
        let panelRect = NSRect(x: 0, y: 0, width: 300, height: 76)

        super.init(
            contentRect: panelRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .floating
        isFloatingPanel = true
        hasShadow = true
        backgroundColor = .clear
        isOpaque = false
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        animationBehavior = .utilityWindow
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        acceptsMouseMovedEvents = true

        // Position at top-center
        if let screen = NSScreen.main {
            let sf = screen.visibleFrame
            let x = sf.midX - panelRect.width / 2
            let y = sf.maxY - panelRect.height - 20
            setFrameOrigin(NSPoint(x: x, y: y))
        }

        let hostingView = ClickThroughHostingView(
            rootView: ContentView()
                .environmentObject(AppState.shared)
        )
        hostingView.frame = NSRect(origin: .zero, size: panelRect.size)
        contentView = hostingView

        print("[ClaudeVoice] Panel created at \(frame)")
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
