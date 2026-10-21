import SwiftUI

@main
struct OrbitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @StateObject private var ring = RingStore()
    @StateObject private var catalog = AppCatalog()
    @StateObject private var calendar = CalendarService()
    @StateObject private var weather = WeatherService()

    var body: some Scene {
        // The phone-style Orbit home screen.
        WindowGroup("Orbit", id: "main") {
            OrbitHomeView()
                .environmentObject(ring)
                .environmentObject(catalog)
                .environmentObject(calendar)
                .environmentObject(weather)
                .frame(minWidth: 420, idealWidth: 440, minHeight: 760, idealHeight: 820)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 440, height: 820)
        .commands { OrbitCommands() }

        // Built-in web browser (real WebKit, HTTPS, YouTube, fullscreen video).
        WindowGroup("Browser", id: "browser", for: BrowserRequest.self) { $request in
            BrowserWindow(startURL: request?.url ?? Defaults.homePage)
        }
        .defaultSize(width: 1240, height: 820)

        Settings {
            SettingsView()
                .environmentObject(ring)
                .environmentObject(catalog)
                .environmentObject(weather)
                .environmentObject(calendar)
        }

        MenuBarExtra {
            MenuBarContent()
                .environmentObject(ring)
        } label: {
            MenuBarLabel()
        }
    }
}

enum Defaults {
    static let homePage = URL(string: "https://www.google.com")!
}

/// Identifies a browser window. Opening the same request again brings the
/// existing window forward (tapping YouTube twice won't stack windows);
/// a fresh `token` forces a brand-new window.
struct BrowserRequest: Codable, Hashable {
    var url: URL
    var token: UUID?

    static func reuse(_ url: URL) -> BrowserRequest { BrowserRequest(url: url, token: nil) }
    static func fresh(_ url: URL) -> BrowserRequest { BrowserRequest(url: url, token: UUID()) }
}

struct OrbitCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Browser Window") {
                openWindow(id: "browser", value: BrowserRequest.fresh(Defaults.homePage))
            }
            .keyboardShortcut("t", modifiers: .command)

            Button("Show Orbit") {
                WindowRouter.shared.showMain()
            }
            .keyboardShortcut("0", modifiers: .command)
        }
    }
}
