import SwiftUI
import AppKit

/// Orbit Clock: world clock, stopwatch and timer.
struct ClockApp: View {
    enum Tab: String, CaseIterable, Identifiable {
        case world = "World Clock", stopwatch = "Stopwatch", timer = "Timer"
        var id: String { rawValue }
    }

    @State private var tab: Tab = .world

    var body: some View {
        VStack(spacing: 0) {
            AppHeader(kind: .clock) { EmptyView() }
            Picker("View", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(16)

            switch tab {
            case .world: WorldClockView()
            case .stopwatch: StopwatchView()
            case .timer: CountdownView()
            }
        }
        .background(Theme.background)
        .foregroundStyle(Theme.text)
        .navigationTitle("Clock")
    }
}

// MARK: - World clock

private struct WorldClockView: View {
    @AppStorage("orbit.clock.zones") private var zonesRaw = "Europe/London,America/New_York,Asia/Tokyo,Australia/Sydney"
    @State private var adding = false

    private var zones: [String] { zonesRaw.split(separator: ",").map(String.init).filter { !$0.isEmpty } }

    var body: some View {
        VStack(spacing: 0) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                List {
                    ForEach(zones, id: \.self) { id in
                        if let zone = TimeZone(identifier: id) {
                            ZoneRow(zone: zone, now: context.date)
                                .listRowBackground(Color.clear)
                                .contextMenu {
                                    Button("Remove", role: .destructive) { remove(id) }
                                }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            HStack {
                Spacer()
                Button {
                    adding = true
                } label: {
                    Label("Add City", systemImage: "plus")
                }
            }
            .padding(16)
        }
        .sheet(isPresented: $adding) {
            ZonePicker { id in
                if !zones.contains(id) { zonesRaw = (zones + [id]).joined(separator: ",") }
            }
        }
    }

    private func remove(_ id: String) {
        zonesRaw = zones.filter { $0 != id }.joined(separator: ",")
    }
}

private struct ZoneRow: View {
    let zone: TimeZone
    let now: Date

    private var city: String {
        zone.identifier.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? zone.identifier
    }

    private var offsetText: String {
        let diff = zone.secondsFromGMT(for: now) - TimeZone.current.secondsFromGMT(for: now)
        if diff == 0 { return "Same time as here" }
        let hours = Double(diff) / 3600
        let formatted = hours == hours.rounded() ? String(Int(hours)) : String(format: "%.1f", hours)
        return hours > 0 ? "\(formatted) h ahead" : "\(formatted.replacingOccurrences(of: "-", with: "")) h behind"
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(city).font(.orbit(17, .semibold))
                Text(offsetText).font(.orbit(12)).foregroundStyle(Theme.secondary)
            }
            Spacer()
            Text(now.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: zone)))
                .font(.system(size: 34, weight: .light))
                .monospacedDigit()
        }
        .padding(.vertical, 6)
    }
}

private struct ZonePicker: View {
    let onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var filter = ""

    private var matches: [String] {
        let all = TimeZone.knownTimeZoneIdentifiers.filter { $0.contains("/") }
        let q = filter.replacingOccurrences(of: " ", with: "_")
        return q.isEmpty ? all : all.filter { $0.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add a city").font(.headline)
            TextField("Search cities", text: $filter).textFieldStyle(.roundedBorder)
            List(matches, id: \.self) { id in
                Button {
                    onPick(id)
                    dismiss()
                } label: {
                    Text(id.replacingOccurrences(of: "_", with: " "))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 360, height: 440)
    }
}

// MARK: - Stopwatch

private struct StopwatchView: View {
    @State private var startedAt: Date?
    @State private var accumulated: TimeInterval = 0
    @State private var laps: [TimeInterval] = []

    private func elapsed(at date: Date) -> TimeInterval {
        accumulated + (startedAt.map { date.timeIntervalSince($0) } ?? 0)
    }

    var body: some View {
        VStack(spacing: 20) {
            TimelineView(.animation(minimumInterval: 0.03, paused: startedAt == nil)) { context in
                Text(stopwatchText(elapsed(at: context.date)))
                    .font(.system(size: 56, weight: .light))
                    .monospacedDigit()
            }
            .padding(.top, 20)

            HStack(spacing: 24) {
                RoundButton(title: startedAt == nil ? (accumulated > 0 ? "Reset" : "Lap") : "Lap",
                            color: Theme.chip, textColor: Theme.text) {
                    if startedAt != nil {
                        laps.insert(elapsed(at: Date()), at: 0)
                    } else {
                        accumulated = 0
                        laps = []
                    }
                }
                .disabled(startedAt == nil && accumulated == 0)

                RoundButton(title: startedAt == nil ? "Start" : "Stop",
                            color: startedAt == nil ? Color(hex: 0x14532D) : Color(hex: 0x7F1D1D),
                            textColor: startedAt == nil ? Color(hex: 0x86EFAC) : Color(hex: 0xFCA5A5)) {
                    if let start = startedAt {
                        accumulated += Date().timeIntervalSince(start)
                        startedAt = nil
                    } else {
                        startedAt = Date()
                    }
                }
                .keyboardShortcut(.space, modifiers: [])
            }

            List {
                ForEach(Array(laps.enumerated()), id: \.offset) { index, lap in
                    let previous = index + 1 < laps.count ? laps[index + 1] : 0
                    HStack {
                        Text("Lap \(laps.count - index)")
                        Spacer()
                        Text(stopwatchText(lap - previous)).monospacedDigit()
                    }
                    .font(.orbit(14))
                    .listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
        }
    }
}

// MARK: - Timer

private struct CountdownView: View {
    @State private var minutes = 5
    @State private var seconds = 0
    @State private var endsAt: Date?
    @State private var pausedRemaining: TimeInterval?
    @State private var runID = UUID()
    @State private var finished = false

    private var total: TimeInterval { TimeInterval(minutes * 60 + seconds) }
    private var isRunning: Bool { endsAt != nil }
    private var isActive: Bool { endsAt != nil || pausedRemaining != nil }

    var body: some View {
        VStack(spacing: 22) {
            if isActive {
                TimelineView(.periodic(from: .now, by: 0.25)) { context in
                    let remaining = endsAt.map { max(0, $0.timeIntervalSince(context.date)) } ?? (pausedRemaining ?? 0)
                    Text(countdownText(remaining))
                        .font(.system(size: 64, weight: .light))
                        .monospacedDigit()
                }
                .padding(.top, 30)
            } else {
                HStack(spacing: 18) {
                    Stepper(value: $minutes, in: 0...599) {
                        Text("\(minutes) min").font(.orbit(22, .medium)).monospacedDigit()
                    }
                    Stepper(value: $seconds, in: 0...59, step: 5) {
                        Text("\(seconds) s").font(.orbit(22, .medium)).monospacedDigit()
                    }
                }
                .padding(.top, 30)
                HStack(spacing: 8) {
                    ForEach([1, 3, 5, 10, 15, 30], id: \.self) { m in
                        Button("\(m)m") { minutes = m; seconds = 0 }
                            .buttonStyle(.bordered)
                    }
                }
            }

            if finished {
                Label("Time's up", systemImage: "bell.fill")
                    .font(.orbit(16, .semibold))
                    .foregroundStyle(Theme.accent)
            }

            HStack(spacing: 24) {
                RoundButton(title: "Cancel", color: Theme.chip, textColor: Theme.text) {
                    endsAt = nil
                    pausedRemaining = nil
                    runID = UUID()
                }
                .disabled(!isActive)

                RoundButton(title: isRunning ? "Pause" : (pausedRemaining != nil ? "Resume" : "Start"),
                            color: isRunning ? Color(hex: 0x78350F) : Color(hex: 0x14532D),
                            textColor: isRunning ? Color(hex: 0xFCD34D) : Color(hex: 0x86EFAC)) {
                    if let end = endsAt {
                        pausedRemaining = max(0, end.timeIntervalSinceNow)
                        endsAt = nil
                        runID = UUID()
                    } else {
                        let length = pausedRemaining ?? total
                        guard length > 0 else { return }
                        pausedRemaining = nil
                        finished = false
                        start(length)
                    }
                }
                .keyboardShortcut(.space, modifiers: [])
            }
            Spacer()
        }
    }

    private func start(_ length: TimeInterval) {
        let id = UUID()
        runID = id
        endsAt = Date().addingTimeInterval(length)
        Task {
            try? await Task.sleep(for: .seconds(length))
            guard runID == id else { return }
            endsAt = nil
            finished = true
            NSSound(named: "Glass")?.play()
        }
    }
}

// MARK: - Shared

private struct RoundButton: View {
    let title: String
    let color: Color
    let textColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.orbit(15, .semibold))
                .foregroundStyle(textColor)
                .frame(width: 84, height: 84)
                .background(Circle().fill(color))
        }
        .buttonStyle(.plain)
    }
}

private func stopwatchText(_ t: TimeInterval) -> String {
    let centi = Int((t * 100).rounded(.down))
    let m = centi / 6000, s = (centi / 100) % 60, c = centi % 100
    return m >= 60
        ? String(format: "%d:%02d:%02d.%02d", m / 60, m % 60, s, c)
        : String(format: "%02d:%02d.%02d", m, s, c)
}

private func countdownText(_ t: TimeInterval) -> String {
    let total = Int(t.rounded(.up))
    let h = total / 3600, m = (total % 3600) / 60, s = total % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
}
