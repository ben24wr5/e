import Foundation

/// Where Orbit keeps its own data: ~/Library/Application Support/Orbit
enum OrbitStorage {
    static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let url = base.appendingPathComponent("Orbit", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func subfolder(_ name: String) -> URL {
        let url = folder.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func load<T: Decodable>(_ type: T.Type, from file: String) -> T? {
        let url = folder.appendingPathComponent(file)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(type, from: data)
    }

    static func save<T: Encodable>(_ value: T, to file: String) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: folder.appendingPathComponent(file), options: .atomic)
    }
}

/// An event in Orbit's own calendar.
struct OrbitEvent: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var location: String
    var notes: String
    var colorIndex: Int

    static let palette: [UInt32] = [0xF5A524, 0x7DD3FC, 0xF87171, 0x4ADE80, 0xC4B5FD, 0xFF6B9A]

    /// Does this event happen on the given day?
    func occurs(on day: Date, calendar: Calendar = .current) -> Bool {
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return false }
        return start < dayEnd && end > dayStart || (isAllDay && calendar.isDate(start, inSameDayAs: day))
    }
}

/// Orbit's own calendar. Events are stored inside Orbit, not in the Mac's Calendar.
@MainActor
final class CalendarService: ObservableObject {
    enum Status { case unknown, denied, ready }

    struct NextEvent: Equatable {
        let title: String
        let start: Date
        let end: Date
        let location: String?
        let isAllDay: Bool
    }

    @Published private(set) var events: [OrbitEvent] = [] {
        didSet { OrbitStorage.save(events, to: "calendar.json") }
    }
    @Published private(set) var nextEvent: NextEvent?
    let status: Status = .ready

    private var timer: Timer?

    init() {
        events = OrbitStorage.load([OrbitEvent].self, from: "calendar.json") ?? []
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func events(on day: Date) -> [OrbitEvent] {
        events.filter { $0.occurs(on: day) }
            .sorted { a, b in
                if a.isAllDay != b.isAllDay { return a.isAllDay }
                return a.start < b.start
            }
    }

    func hasEvents(on day: Date) -> Bool {
        events.contains { $0.occurs(on: day) }
    }

    func save(_ event: OrbitEvent) {
        var fixed = event
        if fixed.end < fixed.start { fixed.end = fixed.start.addingTimeInterval(3600) }
        if let index = events.firstIndex(where: { $0.id == fixed.id }) {
            events[index] = fixed
        } else {
            events.append(fixed)
        }
        refresh()
    }

    func delete(_ event: OrbitEvent) {
        events.removeAll { $0.id == event.id }
        refresh()
    }

    func refresh() {
        let now = Date()
        guard let horizon = Calendar.current.date(byAdding: .day, value: 7, to: now) else { return }
        let upcoming = events
            .filter { $0.end > now && $0.start < horizon }
            .sorted { $0.start < $1.start }
        let pick = upcoming.first(where: { !$0.isAllDay }) ?? upcoming.first
        let next = pick.map {
            NextEvent(title: $0.title.isEmpty ? "Untitled event" : $0.title,
                      start: $0.start, end: $0.end,
                      location: $0.location.isEmpty ? nil : $0.location,
                      isAllDay: $0.isAllDay)
        }
        if next != nextEvent { nextEvent = next }
    }
}

extension CalendarService.NextEvent {
    /// "Design review in 16 min", "Design review — now", "Tomorrow: Dentist".
    func headline(now: Date = Date()) -> String {
        if isAllDay {
            return Calendar.current.isDateInToday(start) ? "Today: \(title)" : "\(dayWord(now: now)): \(title)"
        }
        if start <= now { return "\(title) — now" }
        let minutes = Int(start.timeIntervalSince(now) / 60)
        if minutes < 1 { return "\(title) starting now" }
        if minutes < 60 { return "\(title) in \(minutes) min" }
        if Calendar.current.isDateInToday(start) {
            return "\(title) in \(minutes / 60) h \(minutes % 60) min"
        }
        return "\(dayWord(now: now)): \(title)"
    }

    /// "15:00 · Room 4B"
    var detail: String {
        let time = isAllDay ? "All day" : start.formatted(date: .omitted, time: .shortened)
        let day = Calendar.current.isDateInToday(start) ? "" : start.formatted(.dateTime.weekday(.abbreviated)) + " "
        if let location { return "\(day)\(time) · \(location)" }
        return "\(day)\(time)"
    }

    private func dayWord(now: Date) -> String {
        if Calendar.current.isDateInTomorrow(start) { return "Tomorrow" }
        return start.formatted(.dateTime.weekday(.wide))
    }
}
