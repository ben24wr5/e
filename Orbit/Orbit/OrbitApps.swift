import SwiftUI
import AppKit

/// Orbit's own built-in apps. None of these open or use the Mac's system apps.
enum OrbitAppKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case browser, youtube, music, maps, photos, calendar, notes, weather, clock, calculator, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .browser: return "Browser"
        case .youtube: return "YouTube"
        case .music: return "Music"
        case .maps: return "Maps"
        case .photos: return "Photos"
        case .calendar: return "Calendar"
        case .notes: return "Notes"
        case .weather: return "Weather"
        case .clock: return "Clock"
        case .calculator: return "Calculator"
        case .settings: return "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .browser: return "globe"
        case .youtube: return "play.rectangle.fill"
        case .music: return "music.note"
        case .maps: return "map.fill"
        case .photos: return "photo.on.rectangle.angled"
        case .calendar: return "calendar"
        case .notes: return "note.text"
        case .weather: return "cloud.sun.fill"
        case .clock: return "clock.fill"
        case .calculator: return "plus.forwardslash.minus"
        case .settings: return "gearshape.fill"
        }
    }

    var tint: Color {
        switch self {
        case .browser: return Theme.accent
        case .youtube: return Color(hex: 0xFF4E45)
        case .music: return Color(hex: 0xFF6B9A)
        case .maps: return Color(hex: 0x4ADE80)
        case .photos: return Color(hex: 0xFACC15)
        case .calendar: return Color(hex: 0xF87171)
        case .notes: return Color(hex: 0xFDE68A)
        case .weather: return Color(hex: 0x7DD3FC)
        case .clock: return Color(hex: 0xE5E7EB)
        case .calculator: return Color(hex: 0xFDBA74)
        case .settings: return Color(hex: 0xA7A9B0)
        }
    }

    var subtitle: String {
        switch self {
        case .browser: return "Browse the web over HTTPS"
        case .youtube: return "Search and watch videos"
        case .music: return "Your Orbit music library"
        case .maps: return "Search places and get directions"
        case .photos: return "Your Orbit photo library"
        case .calendar: return "Events and appointments"
        case .notes: return "Quick notes"
        case .weather: return "Forecast for the next 7 days"
        case .clock: return "World clock, stopwatch, timer"
        case .calculator: return "Calculator"
        case .settings: return "Orbit settings"
        }
    }

    /// Window size the app opens at, and the smallest it can shrink to.
    var windowSize: CGSize {
        switch self {
        case .calculator: return CGSize(width: 340, height: 540)
        case .clock: return CGSize(width: 460, height: 600)
        case .weather: return CGSize(width: 520, height: 720)
        case .settings: return CGSize(width: 560, height: 600)
        case .notes: return CGSize(width: 860, height: 600)
        default: return CGSize(width: 1120, height: 760)
        }
    }

    var minimumSize: CGSize {
        switch self {
        case .calculator: return CGSize(width: 300, height: 480)
        case .clock: return CGSize(width: 400, height: 500)
        case .weather: return CGSize(width: 420, height: 560)
        case .settings: return CGSize(width: 520, height: 520)
        default: return CGSize(width: 640, height: 460)
        }
    }

    func matches(_ query: String) -> Bool {
        let q = query.lowercased()
        return title.lowercased().contains(q) || rawValue.contains(q) || subtitle.lowercased().contains(q)
    }
}

/// The glyph used for an Orbit app on the ring, in search and in menus.
struct OrbitAppGlyph: View {
    let kind: OrbitAppKind

    var body: some View {
        Image(systemName: kind.symbol)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .fontWeight(.semibold)
            .foregroundStyle(kind.tint)
    }
}

/// Opens Orbit's apps in their own windows.
@MainActor
enum AppOpener {
    static func open(_ kind: OrbitAppKind, _ openWindow: OpenWindowAction) {
        NSApp.activate(ignoringOtherApps: true)
        if kind == .browser {
            openWindow(id: "browser", value: BrowserRequest.reuse(Defaults.homePage))
        } else {
            openWindow(id: "app", value: kind)
        }
    }

    static func open(_ item: RingItem, _ openWindow: OpenWindowAction) {
        switch item.kind {
        case .app:
            if let kind = item.app { open(kind, openWindow) }
        case .web:
            if let url = item.url {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "browser", value: BrowserRequest.reuse(url))
            }
        }
    }
}

/// The window content for each built-in app.
struct OrbitAppWindow: View {
    let kind: OrbitAppKind

    var body: some View {
        content
            .preferredColorScheme(.dark)
            .background(WindowConfigurator(size: kind.windowSize, minSize: kind.minimumSize))
    }

    @ViewBuilder private var content: some View {
        switch kind {
        case .browser: BrowserWindow(startURL: Defaults.homePage)
        case .youtube: YouTubeApp()
        case .music: MusicApp()
        case .maps: MapsApp()
        case .photos: PhotosApp()
        case .calendar: CalendarApp()
        case .notes: NotesApp()
        case .weather: WeatherApp()
        case .clock: ClockApp()
        case .calculator: CalculatorApp()
        case .settings:
            SettingsView()
                .navigationTitle("Settings")
        }
    }
}

/// Sets a window's starting size once, when it first appears.
struct WindowConfigurator: NSViewRepresentable {
    let size: CGSize
    let minSize: CGSize

    func makeNSView(context: Context) -> ConfiguratorView {
        let view = ConfiguratorView()
        view.size = size
        view.minSize = minSize
        return view
    }

    func updateNSView(_ nsView: ConfiguratorView, context: Context) {}

    final class ConfiguratorView: NSView {
        var size: CGSize = .zero
        var minSize: CGSize = .zero
        private var configured = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, !configured else { return }
            configured = true
            window.contentMinSize = minSize
            window.setContentSize(size)
            window.center()
        }
    }
}

/// Shared look for the top bar of Orbit's apps.
struct AppHeader<Trailing: View>: View {
    let kind: OrbitAppKind
    var title: String? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 10) {
            OrbitAppGlyph(kind: kind)
                .frame(width: 20, height: 20)
            Text(title ?? kind.title)
                .font(.orbit(17, .semibold))
                .lineLimit(1)
            Spacer(minLength: 12)
            trailing
        }
        .padding(.horizontal, 18)
        .frame(height: 52)
        .foregroundStyle(Theme.text)
        .background(Theme.background)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.cardLine).frame(height: 1)
        }
    }
}

/// A rounded search field in Orbit's style.
struct OrbitSearchField: View {
    let prompt: String
    @Binding var text: String
    var onSubmit: () -> Void = {}

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.secondary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .onSubmit(onSubmit)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear")
            }
        }
        .font(.orbit(14))
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(Capsule().fill(Theme.chip))
        .overlay(Capsule().stroke(Theme.chipLine, lineWidth: 1))
        .foregroundStyle(Theme.text)
    }
}

/// Centered message used for empty and permission states.
struct AppMessage: View {
    let symbol: String
    let title: String
    let detail: String
    var buttonTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(Theme.secondary)
            Text(title)
                .font(.orbit(18, .semibold))
            Text(detail)
                .font(.orbit(13))
                .foregroundStyle(Theme.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            if let buttonTitle, let action {
                Button(buttonTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .foregroundStyle(Theme.background)
                    .padding(.top, 4)
            }
        }
        .foregroundStyle(Theme.text)
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
