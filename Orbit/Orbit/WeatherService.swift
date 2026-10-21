import Foundation
import CoreLocation

/// Live weather from Open-Meteo over HTTPS (free, no API key).
/// Uses your Mac's location when allowed, otherwise the city set in Settings.
@MainActor
final class WeatherService: NSObject, ObservableObject {
    struct Current: Equatable {
        let temperature: Double
        let code: Int
        let place: String
        let outlook: String
        let isDay: Bool

        var summary: String { WeatherService.describe(code) }
        var symbol: String { WeatherService.symbol(code, isDay: isDay) }
    }

    @Published private(set) var current: Current?
    @Published private(set) var hours: [HourForecast] = []
    @Published private(set) var days: [DayForecast] = []
    @Published private(set) var updated: Date?

    struct HourForecast: Identifiable, Equatable {
        var id: Date { time }
        let time: Date
        let temperature: Double
        let code: Int
        let rainChance: Int
    }

    struct DayForecast: Identifiable, Equatable {
        var id: Date { date }
        let date: Date
        let code: Int
        let high: Double
        let low: Double
        let rainChance: Int
    }
    @Published private(set) var errorMessage: String?

    @Published var fallbackCity: String {
        didSet {
            UserDefaults.standard.set(fallbackCity, forKey: Keys.city)
            if !usingDeviceLocation { refresh() }
        }
    }

    @Published var useFahrenheit: Bool {
        didSet {
            UserDefaults.standard.set(useFahrenheit, forKey: Keys.fahrenheit)
            refresh()
        }
    }

    @Published private(set) var usingDeviceLocation = false

    private enum Keys {
        static let city = "orbit.weather.city"
        static let fahrenheit = "orbit.weather.fahrenheit"
    }

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var timer: Timer?
    private var lastLocation: CLLocation?

    override init() {
        fallbackCity = UserDefaults.standard.string(forKey: Keys.city) ?? "London"
        useFahrenheit = UserDefaults.standard.bool(forKey: Keys.fahrenheit)
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        timer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        refresh()
    }

    func refresh() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
            Task { await fetchForFallbackCity() }
        case .denied, .restricted:
            usingDeviceLocation = false
            Task { await fetchForFallbackCity() }
        default:
            usingDeviceLocation = true
            if let lastLocation {
                Task { await fetch(for: lastLocation) }
            }
            manager.requestLocation()
        }
    }

    // MARK: Fetching

    private func fetchForFallbackCity() async {
        let city = fallbackCity.trimmingCharacters(in: .whitespaces)
        guard !city.isEmpty else { return }
        var comps = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        comps.queryItems = [
            URLQueryItem(name: "name", value: city),
            URLQueryItem(name: "count", value: "1"),
        ]
        do {
            let (data, _) = try await URLSession.shared.data(from: comps.url!)
            let response = try JSONDecoder().decode(GeocodeResponse.self, from: data)
            guard let hit = response.results?.first else {
                errorMessage = "Couldn't find “\(city)”"
                return
            }
            await fetchForecast(lat: hit.latitude, lon: hit.longitude, place: hit.name)
        } catch {
            errorMessage = "Weather unavailable"
        }
    }

    private func fetch(for location: CLLocation) async {
        var place = "Here"
        if let mark = try? await geocoder.reverseGeocodeLocation(location).first {
            place = mark.locality ?? mark.subAdministrativeArea ?? mark.administrativeArea ?? place
        }
        await fetchForecast(lat: location.coordinate.latitude, lon: location.coordinate.longitude, place: place)
    }

    private func fetchForecast(lat: Double, lon: Double, place: String) async {
        var comps = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        comps.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.4f", lat)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", lon)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "hourly", value: "temperature_2m,weather_code,precipitation_probability"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max"),
            URLQueryItem(name: "forecast_days", value: "7"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "temperature_unit", value: useFahrenheit ? "fahrenheit" : "celsius"),
        ]
        do {
            let (data, _) = try await URLSession.shared.data(from: comps.url!)
            let r = try JSONDecoder().decode(ForecastResponse.self, from: data)
            current = Current(
                temperature: r.current.temperature_2m,
                code: r.current.weather_code,
                place: place,
                outlook: WeatherService.rainOutlook(r),
                isDay: (r.current.is_day ?? 1) == 1
            )
            (hours, days) = WeatherService.forecast(r)
            updated = Date()
            errorMessage = nil
        } catch {
            errorMessage = "Weather unavailable"
        }
    }

    /// "Rain likely from 18:00" / "No rain expected today".
    private static func rainOutlook(_ r: ForecastResponse) -> String {
        guard let hourly = r.hourly else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        formatter.timeZone = TimeZone(secondsFromGMT: r.utc_offset_seconds ?? 0)

        let now = Date()
        let limit = now.addingTimeInterval(12 * 3600)
        for (index, stamp) in hourly.time.enumerated() {
            guard let date = formatter.date(from: stamp), date > now, date < limit,
                  index < hourly.precipitation_probability.count,
                  let chance = hourly.precipitation_probability[index] else { continue }
            if chance >= 50 {
                let hour = String(stamp.suffix(5))
                return "Rain likely from \(hour)"
            }
        }
        return "No rain expected soon"
    }

    private static func forecast(_ r: ForecastResponse) -> ([HourForecast], [DayForecast]) {
        let zone = TimeZone(secondsFromGMT: r.utc_offset_seconds ?? 0) ?? .current
        let hourFormat = DateFormatter()
        hourFormat.locale = Locale(identifier: "en_US_POSIX")
        hourFormat.dateFormat = "yyyy-MM-dd'T'HH:mm"
        hourFormat.timeZone = zone
        let dayFormat = DateFormatter()
        dayFormat.locale = Locale(identifier: "en_US_POSIX")
        dayFormat.dateFormat = "yyyy-MM-dd"
        dayFormat.timeZone = zone

        var hours: [HourForecast] = []
        if let h = r.hourly {
            let now = Date().addingTimeInterval(-3600)
            for (i, stamp) in h.time.enumerated() {
                guard let time = hourFormat.date(from: stamp), time > now,
                      let temps = h.temperature_2m, i < temps.count, let temp = temps[i] else { continue }
                let code = h.weather_code.flatMap { i < $0.count ? $0[i] : nil } ?? 0
                let rain = i < h.precipitation_probability.count ? (h.precipitation_probability[i] ?? 0) : 0
                hours.append(HourForecast(time: time, temperature: temp, code: code, rainChance: rain))
                if hours.count == 24 { break }
            }
        }

        var days: [DayForecast] = []
        if let d = r.daily {
            for (i, stamp) in d.time.enumerated() {
                guard let date = dayFormat.date(from: stamp),
                      i < d.temperature_2m_max.count, i < d.temperature_2m_min.count,
                      let high = d.temperature_2m_max[i], let low = d.temperature_2m_min[i] else { continue }
                let code = i < d.weather_code.count ? (d.weather_code[i] ?? 0) : 0
                let rain = d.precipitation_probability_max.flatMap { i < $0.count ? $0[i] : nil } ?? 0
                days.append(DayForecast(date: date, code: code, high: high, low: low, rainChance: rain))
            }
        }
        return (hours, days)
    }

    // MARK: Weather codes (WMO)

    nonisolated static func describe(_ code: Int) -> String {
        switch code {
        case 0: return "Clear"
        case 1: return "Mostly clear"
        case 2: return "Partly cloudy"
        case 3: return "Cloudy"
        case 45, 48: return "Fog"
        case 51, 53, 55, 56, 57: return "Drizzle"
        case 61, 63, 65, 66, 67: return "Rain"
        case 71, 73, 75, 77: return "Snow"
        case 80, 81, 82: return "Showers"
        case 85, 86: return "Snow showers"
        case 95, 96, 99: return "Thunderstorm"
        default: return "—"
        }
    }

    nonisolated static func symbol(_ code: Int, isDay: Bool) -> String {
        switch code {
        case 0: return isDay ? "sun.max" : "moon.stars"
        case 1, 2: return isDay ? "cloud.sun" : "cloud.moon"
        case 3: return "cloud"
        case 45, 48: return "cloud.fog"
        case 51, 53, 55, 56, 57: return "cloud.drizzle"
        case 61, 63, 65, 66, 67, 80, 81, 82: return "cloud.rain"
        case 71, 73, 75, 77, 85, 86: return "cloud.snow"
        case 95, 96, 99: return "cloud.bolt.rain"
        default: return "cloud"
        }
    }
}

extension WeatherService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.refresh() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.lastLocation = location
            await self.fetch(for: location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            if self.current == nil { await self.fetchForFallbackCity() }
        }
    }
}

// MARK: - Open-Meteo responses

private struct GeocodeResponse: Decodable {
    struct Hit: Decodable {
        let name: String
        let latitude: Double
        let longitude: Double
    }
    let results: [Hit]?
}

private struct ForecastResponse: Decodable {
    struct CurrentBlock: Decodable {
        let temperature_2m: Double
        let weather_code: Int
        let is_day: Int?
    }
    struct Hourly: Decodable {
        let time: [String]
        let precipitation_probability: [Int?]
        let temperature_2m: [Double?]?
        let weather_code: [Int?]?
    }
    struct Daily: Decodable {
        let time: [String]
        let weather_code: [Int?]
        let temperature_2m_max: [Double?]
        let temperature_2m_min: [Double?]
        let precipitation_probability_max: [Int?]?
    }
    let utc_offset_seconds: Int?
    let current: CurrentBlock
    let hourly: Hourly?
    let daily: Daily?
}
