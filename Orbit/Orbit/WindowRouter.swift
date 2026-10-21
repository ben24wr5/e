import SwiftUI
import AppKit

/// Lets non-SwiftUI code (the global hot key, the menu bar, the Dock)
/// show Orbit's windows.
@MainActor
final class WindowRouter {
    static let shared = WindowRouter()

    /// Captured from a live SwiftUI view so windows can be reopened after closing.
    var openWindowAction: OpenWindowAction?

    private var mainWindow: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue.hasPrefix("main") == true }
    }

    func showMain() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = mainWindow {
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindowAction?(id: "main")
        }
    }

    func toggleMain() {
        if NSApp.isActive, let window = mainWindow, window.isVisible, window.isKeyWindow {
            window.orderOut(nil)
        } else {
            showMain()
        }
    }

    func openWeb(_ url: URL) {
        NSApp.activate(ignoringOtherApps: true)
        openWindowAction?(id: "browser", value: BrowserRequest.reuse(url))
    }
}
