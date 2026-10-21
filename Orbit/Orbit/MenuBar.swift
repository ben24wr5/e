import SwiftUI

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
    @EnvironmentObject private var ring: RingStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Show Orbit") { WindowRouter.shared.showMain() }
            .keyboardShortcut(" ", modifiers: .option)

        Button("New Browser Window") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "browser", value: BrowserRequest.fresh(Defaults.homePage))
        }

        Divider()

        ForEach(ring.items) { item in
            Button(item.name) {
                NSApp.activate(ignoringOtherApps: true)
                Launcher.open(item) { url in
                    openWindow(id: "browser", value: BrowserRequest.reuse(url))
                }
            }
        }

        Divider()

        SettingsLink { Text("Settings…") }
            .keyboardShortcut(",", modifiers: .command)

        Button("Quit Orbit") { NSApp.terminate(nil) }
            .keyboardShortcut("q", modifiers: .command)
    }
}
