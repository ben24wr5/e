import SwiftUI

/// Orbit Calendar: a month view and day agenda over Orbit's own events.
struct CalendarApp: View {
    @EnvironmentObject private var calendar: CalendarService
    @State private var month = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
    @State private var selectedDay = Calendar.current.startOfDay(for: Date())
    @State private var editing: OrbitEvent?

    private let cal = Calendar.current

    var body: some View {
        HStack(spacing: 0) {
            monthView
                .frame(minWidth: 460)
            Rectangle().fill(Theme.cardLine).frame(width: 1)
            dayView
                .frame(width: 340)
        }
        .background(Theme.background)
        .foregroundStyle(Theme.text)
        .navigationTitle("Calendar")
        .sheet(item: $editing) { event in
            EventEditor(event: event) { saved in
                calendar.save(saved)
                selectedDay = cal.startOfDay(for: saved.start)
            } onDelete: { removed in
                calendar.delete(removed)
            }
            .environmentObject(calendar)
        }
    }

    // MARK: Month

    private var monthView: some View {
        VStack(spacing: 0) {
            AppHeader(kind: .calendar, title: month.formatted(.dateTime.month(.wide).year())) {
                Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                    .keyboardShortcut(.leftArrow, modifiers: .command)
                    .accessibilityLabel("Previous month")
                Button("Today") {
                    month = cal.dateInterval(of: .month, for: Date())?.start ?? Date()
                    selectedDay = cal.startOfDay(for: Date())
                }
                Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
                    .keyboardShortcut(.rightArrow, modifiers: .command)
                    .accessibilityLabel("Next month")
            }

            let symbols = weekdaySymbols
            HStack(spacing: 0) {
                ForEach(symbols, id: \.self) { symbol in
                    Text(symbol.uppercased())
                        .font(.orbit(11, .medium))
                        .tracking(1)
                        .foregroundStyle(Theme.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 10)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(gridDays, id: \.self) { day in
                    DayCell(
                        day: day,
                        inMonth: cal.isDate(day, equalTo: month, toGranularity: .month),
                        isToday: cal.isDateInToday(day),
                        isSelected: cal.isDate(day, inSameDayAs: selectedDay),
                        events: calendar.events(on: day)
                    )
                    .onTapGesture { selectedDay = day }
                    .onTapGesture(count: 2) { newEvent(on: day) }
                }
            }
            .padding(.horizontal, 12)
            Spacer(minLength: 12)
        }
    }

    private var weekdaySymbols: [String] {
        let symbols = cal.shortWeekdaySymbols
        let first = cal.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    private var gridDays: [Date] {
        guard let monthInterval = cal.dateInterval(of: .month, for: month) else { return [] }
        let firstWeekday = cal.component(.weekday, from: monthInterval.start)
        let leading = (firstWeekday - cal.firstWeekday + 7) % 7
        guard let start = cal.date(byAdding: .day, value: -leading, to: monthInterval.start) else { return [] }
        return (0..<42).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    private func shiftMonth(_ delta: Int) {
        if let next = cal.date(byAdding: .month, value: delta, to: month) { month = next }
    }

    // MARK: Day

    private var dayView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedDay.formatted(.dateTime.weekday(.wide)).uppercased())
                        .font(.orbit(11, .medium)).tracking(1.2).foregroundStyle(Theme.secondary)
                    Text(selectedDay.formatted(.dateTime.day().month(.wide)))
                        .font(.orbit(22, .bold))
                }
                Spacer()
                Button {
                    newEvent(on: selectedDay)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Theme.accent))
                        .foregroundStyle(Theme.background)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("n", modifiers: .command)
                .accessibilityLabel("New event")
            }
            .padding(18)

            let dayEvents = calendar.events(on: selectedDay)
            if dayEvents.isEmpty {
                Text("No events. Press + or double-click a day to add one.")
                    .font(.orbit(13))
                    .foregroundStyle(Theme.secondary)
                    .padding(.horizontal, 18)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(dayEvents) { event in
                            Button { editing = event } label: { EventRow(event: event) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
                }
            }
        }
        .background(Theme.card.opacity(0.5))
    }

    private func newEvent(on day: Date) {
        let now = Date()
        var start = cal.startOfDay(for: day)
        if cal.isDateInToday(day) {
            let hour = cal.component(.hour, from: now) + 1
            start = cal.date(bySettingHour: min(hour, 23), minute: 0, second: 0, of: day) ?? start
        } else {
            start = cal.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? start
        }
        editing = OrbitEvent(title: "", start: start, end: start.addingTimeInterval(3600),
                             isAllDay: false, location: "", notes: "", colorIndex: 0)
    }
}

private struct DayCell: View {
    let day: Date
    let inMonth: Bool
    let isToday: Bool
    let isSelected: Bool
    let events: [OrbitEvent]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(day.formatted(.dateTime.day()))
                .font(.orbit(13, isToday ? .bold : .regular))
                .foregroundStyle(isToday ? Theme.background : (inMonth ? Theme.text : Theme.tertiary))
                .frame(width: 24, height: 24)
                .background(Circle().fill(isToday ? Theme.accent : .clear))
            ForEach(events.prefix(2)) { event in
                Text(event.title.isEmpty ? "Event" : event.title)
                    .font(.orbit(10, .medium))
                    .lineLimit(1)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 4)
                        .fill(Color(hex: OrbitEvent.palette[event.colorIndex % OrbitEvent.palette.count]).opacity(0.25)))
            }
            if events.count > 2 {
                Text("+\(events.count - 2) more").font(.orbit(10)).foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(5)
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10).fill(isSelected ? Theme.chipHover : Theme.card.opacity(inMonth ? 1 : 0.4)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(isSelected ? Theme.accent.opacity(0.7) : Theme.cardLine, lineWidth: 1))
        .contentShape(Rectangle())
    }
}

private struct EventRow: View {
    let event: OrbitEvent

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(hex: OrbitEvent.palette[event.colorIndex % OrbitEvent.palette.count]))
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 3) {
                Text(event.title.isEmpty ? "Untitled event" : event.title).font(.orbit(14, .semibold))
                Text(event.isAllDay ? "All day"
                     : "\(event.start.formatted(date: .omitted, time: .shortened)) – \(event.end.formatted(date: .omitted, time: .shortened))")
                    .font(.orbit(12)).foregroundStyle(Theme.secondary)
                if !event.location.isEmpty {
                    Label(event.location, systemImage: "mappin").font(.orbit(12)).foregroundStyle(Theme.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.cardLine, lineWidth: 1))
        .contentShape(Rectangle())
    }
}

private struct EventEditor: View {
    @EnvironmentObject private var calendar: CalendarService
    @Environment(\.dismiss) private var dismiss
    @State var event: OrbitEvent
    let onSave: (OrbitEvent) -> Void
    let onDelete: (OrbitEvent) -> Void

    init(event: OrbitEvent, onSave: @escaping (OrbitEvent) -> Void, onDelete: @escaping (OrbitEvent) -> Void) {
        _event = State(initialValue: event)
        self.onSave = onSave
        self.onDelete = onDelete
    }

    private var isExisting: Bool { calendar.events.contains { $0.id == event.id } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isExisting ? "Edit Event" : "New Event").font(.headline)
            Form {
                TextField("Title", text: $event.title, prompt: Text("Design review"))
                Toggle("All day", isOn: $event.isAllDay)
                DatePicker("Starts", selection: $event.start,
                           displayedComponents: event.isAllDay ? [.date] : [.date, .hourAndMinute])
                DatePicker("Ends", selection: $event.end, in: event.start...,
                           displayedComponents: event.isAllDay ? [.date] : [.date, .hourAndMinute])
                TextField("Location", text: $event.location)
                TextField("Notes", text: $event.notes, axis: .vertical)
                    .lineLimit(2...5)
                Picker("Colour", selection: $event.colorIndex) {
                    ForEach(OrbitEvent.palette.indices, id: \.self) { index in
                        Text(["Amber", "Sky", "Red", "Green", "Lilac", "Pink"][index]).tag(index)
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                if isExisting {
                    Button("Delete Event", role: .destructive) {
                        onDelete(event)
                        dismiss()
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    var saved = event
                    if saved.isAllDay {
                        let cal = Calendar.current
                        saved.start = cal.startOfDay(for: saved.start)
                        let endDay = cal.startOfDay(for: max(saved.end, saved.start))
                        saved.end = cal.date(byAdding: .day, value: 1, to: endDay) ?? saved.start.addingTimeInterval(86400)
                    }
                    onSave(saved)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
        .onChange(of: event.start) { old, new in
            // Keep the event's length when the start moves.
            let length = event.end.timeIntervalSince(old)
            event.end = new.addingTimeInterval(max(length, 0))
        }
    }
}
