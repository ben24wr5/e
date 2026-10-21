import SwiftUI

struct OrbitHomeView: View {
    @EnvironmentObject private var ring: RingStore
    @EnvironmentObject private var calendar: CalendarService
    @EnvironmentObject private var weather: WeatherService
    @Environment(\.openWindow) private var openWindow

    @State private var showSearch = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                ClockHeader(nextEvent: calendar.nextEvent)

                Spacer(minLength: 16)

                RingView(
                    items: ring.items,
                    onOpen: open,
                    onCentre: { withAnimation(.easeOut(duration: 0.18)) { showSearch = true } }
                )
                .frame(width: 330, height: 330)
                .frame(maxWidth: .infinity)

                Spacer(minLength: 16)

                VStack(spacing: 14) {
                    HStack(spacing: 10) {
                        NextEventCard()
                        WeatherCard()
                    }
                    .fixedSize(horizontal: false, vertical: true)

                    Text("Scroll or drag to spin · ⌘K to search · ⌥Space anywhere")
                        .font(.orbit(12))
                        .foregroundStyle(Theme.tertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 44)
            .padding(.bottom, 24)
            .foregroundStyle(Theme.text)

            if showSearch {
                SearchOverlay(isPresented: $showSearch)
                    .transition(.opacity)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { WindowRouter.shared.openWindowAction = openWindow }
    }

    private func open(_ item: RingItem) {
        Launcher.open(item) { url in
            openWindow(id: "browser", value: BrowserRequest.reuse(url))
        }
    }
}

// MARK: - Clock

struct ClockHeader: View {
    let nextEvent: CalendarService.NextEvent?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 6) {
                Text(context.date.formatted(.dateTime.weekday(.wide).day().month(.wide)).uppercased())
                    .font(.orbit(13, .medium))
                    .tracking(1.6)
                    .foregroundStyle(Theme.secondary)

                Text(context.date.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 76, weight: .light))
                    .monospacedDigit()
                    .tracking(-2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                HStack(spacing: 8) {
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 8, height: 8)
                    Text(nextEvent?.headline(now: context.date) ?? "Nothing coming up")
                        .font(.orbit(14))
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}
