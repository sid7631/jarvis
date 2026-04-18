import SwiftUI
import AppKit

/// Configures the hosting NSWindow for a transparent, borderless, floating appearance.
/// Place as a hidden `.background(WindowAccessor())` in the root view.
struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = WatcherView()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - Watcher View

/// Custom NSView that reliably configures the window once added to the hierarchy.
private class WatcherView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        configureWindow(window)
    }

    private func configureWindow(_ window: NSWindow) {
        // Transparent background
        window.isOpaque = false
        window.backgroundColor = .clear

        // Hide title bar visually but keep .titled so the window can become key
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)

        // Remove standard window buttons
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        // Float above other windows
        window.level = .floating

        // Draggable by clicking anywhere on the window
        window.isMovableByWindowBackground = true

        // Available on all Spaces
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // No shadow for a clean floating orb look
        window.hasShadow = false
    }
}
