import Foundation
import EventKit
import AppKit

/// Reads the next event from the Mac's own Calendar (iCloud, Google, Exchange —
/// whatever accounts are set up in Calendar.app).
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

    @Published private(set) var status: Status = .unknown
    @Published private(set) var nextEvent: NextEvent?

    private let store = EKEventStore()
    private var timer: Timer?
    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        Task { await requestAccess() }
    }

    func requestAccess() async {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            status = .ready
            refresh()
            return
        case .denied, .restricted, .writeOnly:
            status = .denied
            return
        default:
            break
        }
        do {
            let granted = try await store.requestFullAccessToEvents()
            status = granted ? .ready : .denied
            if granted { refresh() }
        } catch {
            status = .denied
        }
    }

    func refresh() {
        guard status == .ready else { return }
        let now = Date()
        guard let end = Calendar.current.date(byAdding: .day, value: 7, to: now) else { return }
        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: nil)
        let events = store.events(matching: predicate)
            .filter { $0.endDate > now }
            .sorted { $0.startDate < $1.startDate }
        let pick = events.first(where: { !$0.isAllDay }) ?? events.first
        nextEvent = pick.map {
            NextEvent(
                title: ($0.title?.isEmpty == false ? $0.title! : "Untitled event"),
                start: $0.startDate,
                end: $0.endDate,
                location: $0.location?.isEmpty == false ? $0.location : nil,
                isAllDay: $0.isAllDay
            )
        }
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }
}

extension CalendarService.NextEvent {
    /// "Design review in 16 min", "Design review now", "Tomorrow: Dentist".
    func headline(now: Date = Date()) -> String {
        if isAllDay {
            return Calendar.current.isDateInToday(start) ? "Today: \(title)" : "\(dayWord(now: now)): \(title)"
        }
        if start <= now { return "\(title) — now" }
        let minutes = Int(start.timeIntervalSince(now) / 60)
        if minutes < 1 { return "\(title) starting now" }
        if minutes < 60 { return "\(title) in \(minutes) min" }
        if Calendar.current.isDateInToday(start) {
            let hours = minutes / 60
            return "\(title) in \(hours) h \(minutes % 60) min"
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
