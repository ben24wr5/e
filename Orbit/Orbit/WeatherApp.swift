import SwiftUI

/// Orbit Weather: current conditions, the next 24 hours and 7 days.
struct WeatherApp: View {
    @EnvironmentObject private var weather: WeatherService
    @State private var city = ""

    var body: some View {
        VStack(spacing: 0) {
            AppHeader(kind: .weather) {
                Button {
                    weather.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: .command)
                .help("Refresh")
            }

            if let now = weather.current {
                ScrollView {
                    VStack(spacing: 18) {
                        currentBlock(now)
                        if !weather.hours.isEmpty { hourly }
                        if !weather.days.isEmpty { daily }
                        cityBox
                        if let updated = weather.updated {
                            Text("Updated \(updated.formatted(date: .omitted, time: .shortened)) · Open-Meteo")
                                .font(.orbit(11))
                                .foregroundStyle(Theme.tertiary)
                        }
                    }
                    .padding(18)
                }
            } else if let message = weather.errorMessage {
                AppMessage(symbol: "cloud.slash", title: "Weather unavailable", detail: message,
                           buttonTitle: "Try Again", action: { weather.refresh() })
            } else {
                ProgressView().controlSize(.large).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.background)
        .foregroundStyle(Theme.text)
        .navigationTitle("Weather")
        .onAppear { city = weather.fallbackCity }
    }

    private func currentBlock(_ now: WeatherService.Current) -> some View {
        VStack(spacing: 6) {
            Text(now.place).font(.orbit(26, .semibold))
            Text("\(Int(now.temperature.rounded()))°")
                .font(.system(size: 92, weight: .thin))
            Label(now.summary, systemImage: now.symbol)
                .font(.orbit(17))
                .foregroundStyle(Theme.secondary)
            if let today = weather.days.first {
                Text("H: \(Int(today.high.rounded()))°   L: \(Int(today.low.rounded()))°")
                    .font(.orbit(15, .medium))
            }
            Text(now.outlook)
                .font(.orbit(13))
                .foregroundStyle(Theme.secondary)
        }
        .padding(.vertical, 10)
    }

    private var hourly: some View {
        VStack(alignment: .leading, spacing: 10) {
            CapsLabel(text: "Next 24 hours")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 18) {
                    ForEach(Array(weather.hours.enumerated()), id: \.element.id) { index, hour in
                        VStack(spacing: 8) {
                            Text(index == 0 ? "Now" : hour.time.formatted(.dateTime.hour()))
                                .font(.orbit(12, .medium))
                            Image(systemName: WeatherService.symbol(hour.code, isDay: isDaytime(hour.time)))
                                .font(.system(size: 18))
                                .frame(height: 22)
                            Text("\(Int(hour.temperature.rounded()))°").font(.orbit(15, .semibold))
                            Text(hour.rainChance >= 20 ? "\(hour.rainChance)%" : " ")
                                .font(.orbit(11))
                                .foregroundStyle(OrbitAppKind.weather.tint)
                        }
                        .frame(minWidth: 40)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.cardLine, lineWidth: 1))
    }

    private var daily: some View {
        let lows = weather.days.map(\.low)
        let highs = weather.days.map(\.high)
        let minT = lows.min() ?? 0
        let maxT = highs.max() ?? 1
        return VStack(alignment: .leading, spacing: 10) {
            CapsLabel(text: "7-day forecast")
            ForEach(Array(weather.days.enumerated()), id: \.element.id) { index, day in
                HStack(spacing: 12) {
                    Text(index == 0 ? "Today" : day.date.formatted(.dateTime.weekday(.abbreviated)))
                        .font(.orbit(15, .medium))
                        .frame(width: 56, alignment: .leading)
                    Image(systemName: WeatherService.symbol(day.code, isDay: true))
                        .frame(width: 26)
                    Text(day.rainChance >= 20 ? "\(day.rainChance)%" : "")
                        .font(.orbit(11))
                        .foregroundStyle(OrbitAppKind.weather.tint)
                        .frame(width: 34, alignment: .leading)
                    Text("\(Int(day.low.rounded()))°").font(.orbit(14)).foregroundStyle(Theme.secondary)
                        .frame(width: 34, alignment: .trailing)
                    TemperatureBar(low: day.low, high: day.high, minT: minT, maxT: maxT)
                        .frame(height: 6)
                    Text("\(Int(day.high.rounded()))°").font(.orbit(14, .semibold))
                        .frame(width: 34, alignment: .leading)
                }
                if index < weather.days.count - 1 {
                    Divider().overlay(Theme.cardLine)
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.cardLine, lineWidth: 1))
    }

    private var cityBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            CapsLabel(text: "Location")
            Text(weather.usingDeviceLocation
                 ? "Using your current location. The city below is used if location is off."
                 : "Showing the city below.")
                .font(.orbit(12))
                .foregroundStyle(Theme.secondary)
            HStack {
                OrbitSearchField(prompt: "City", text: $city) { weather.fallbackCity = city }
                Button("Set") { weather.fallbackCity = city }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.cardLine, lineWidth: 1))
    }

    private func isDaytime(_ date: Date) -> Bool {
        let hour = Calendar.current.component(.hour, from: date)
        return hour >= 7 && hour < 19
    }
}

private struct TemperatureBar: View {
    let low: Double
    let high: Double
    let minT: Double
    let maxT: Double

    var body: some View {
        GeometryReader { geo in
            let span = max(maxT - minT, 1)
            let start = (low - minT) / span * geo.size.width
            let width = max((high - low) / span * geo.size.width, 6)
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.chipLine)
                Capsule()
                    .fill(LinearGradient(colors: [OrbitAppKind.weather.tint, Theme.accent],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: width)
                    .offset(x: start)
            }
        }
    }
}
