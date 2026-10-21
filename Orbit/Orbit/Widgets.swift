import SwiftUI

/// Rounded card used by the glance widgets.
struct GlanceCard<Content: View>: View {
    var action: (() -> Void)?
    @ViewBuilder var content: Content
    @State private var hovering = false

    var body: some View {
        let card = VStack(alignment: .leading, spacing: 6) { content }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(hovering && action != nil ? Theme.chipHover : Theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Theme.cardLine, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .onHover { hovering = $0 }

        if let action {
            Button(action: action) { card }
                .buttonStyle(.plain)
        } else {
            card
        }
    }
}

struct NextEventCard: View {
    @EnvironmentObject private var calendar: CalendarService

    var body: some View {
        GlanceCard(action: tap) {
            CapsLabel(text: "Next")
            switch calendar.status {
            case .unknown:
                ProgressView().controlSize(.small)
            case .denied:
                Text("Calendar off")
                    .font(.orbit(16, .semibold))
                Text("Click to allow access")
                    .font(.orbit(13))
                    .foregroundStyle(Theme.secondary)
            case .ready:
                if let event = calendar.nextEvent {
                    Text(event.title)
                        .font(.orbit(16, .semibold))
                        .lineLimit(1)
                    Text(event.detail)
                        .font(.orbit(13))
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                } else {
                    Text("All clear")
                        .font(.orbit(16, .semibold))
                    Text("Nothing in the next 7 days")
                        .font(.orbit(13))
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                }
            }
        }
        .help("Open Calendar")
    }

    private func tap() {
        if calendar.status == .denied {
            calendar.openPrivacySettings()
        } else {
            Launcher.openApp(bundleID: "com.apple.iCal")
        }
    }
}

struct WeatherCard: View {
    @EnvironmentObject private var weather: WeatherService

    var body: some View {
        GlanceCard(action: { weather.refresh() }) {
            if let now = weather.current {
                CapsLabel(text: now.place)
                HStack(spacing: 6) {
                    Text("\(Int(now.temperature.rounded()))° \(now.summary)")
                        .font(.orbit(16, .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    Image(systemName: now.symbol)
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.secondary)
                }
                Text(now.outlook)
                    .font(.orbit(13))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            } else if let message = weather.errorMessage {
                CapsLabel(text: "Weather")
                Text(message)
                    .font(.orbit(14, .semibold))
                Text("Click to retry")
                    .font(.orbit(13))
                    .foregroundStyle(Theme.secondary)
            } else {
                CapsLabel(text: "Weather")
                ProgressView().controlSize(.small)
            }
        }
        .help("Refresh weather")
    }
}
