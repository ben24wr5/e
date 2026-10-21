import SwiftUI

@main
struct OrbitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @StateObject private var ring = RingStore()
    @StateObject private var calendar = CalendarService()
    @StateObject private var weather = WeatherService()
    @StateObject private var youtube = YouTubeModel()
    @StateObject private var music = MusicPlayer()
    @StateObject private var notes = NotesStore()
    @StateObject private var photos = PhotosLibrary()

    var body: some Scene {
        // The phone-style Orbit home screen.
        WindowGroup("Orbit", id: "main") {
            shared(OrbitHomeView())
                .frame(minWidth: 420, idealWidth: 440, minHeight: 760, idealHeight: 820)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 440, height: 820)
        .commands { OrbitCommands() }

        // Orbit's built-in apps, one window each.
        WindowGroup("Orbit App", id: "app", for: OrbitAppKind.self) { $kind in
            shared(OrbitAppWindow(kind: kind ?? .notes))
        }
        .defaultSize(width: 1000, height: 720)

        // Orbit's browser (real WebKit, HTTPS only).
        WindowGroup("Browser", id: "browser", for: BrowserRequest.self) { $request in
            shared(BrowserWindow(startURL: request?.url ?? Defaults.homePage))
        }
        .defaultSize(width: 1240, height: 820)

        Settings {
            shared(SettingsView())
        }

        MenuBarExtra {
            shared(MenuBarContent())
        } label: {
            MenuBarLabel()
        }
    }

    /// Gives every window the same shared data.
    private func shared<V: View>(_ view: V) -> some View {
        view
            .environmentObject(ring)
            .environmentObject(calendar)
            .environmentObject(weather)
            .environmentObject(youtube)
            .environmentObject(music)
            .environmentObject(notes)
            .environmentObject(photos)
    }
}

enum Defaults {
    static let homePage = URL(string: "https://www.google.com")!
}

/// Identifies a browser window. Opening the same request again brings the
/// existing window forward; a fresh `token` forces a brand-new window.
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
