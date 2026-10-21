import SwiftUI
import AppKit

/// Orbit's menu bar icon. Its label view stays alive for the whole session,
/// so it's where the window router gets a working `openWindow`.
struct MenuBarLabel: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: "circle.circle")
            .onAppear { WindowRouter.shared.openWindowAction = openWindow }
    }
}

struct MenuBarContent: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Show Orbit") { WindowRouter.shared.showMain() }

        Divider()

        ForEach(OrbitAppKind.allCases) { kind in
            Button(kind.title) { AppOpener.open(kind, openWindow) }
        }

        Divider()

        Button("New Browser Window") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "browser", value: BrowserRequest.fresh(Defaults.homePage))
        }

        Button("Quit Orbit") { NSApp.terminate(nil) }
            .keyboardShortcut("q", modifiers: .command)
    }
}
