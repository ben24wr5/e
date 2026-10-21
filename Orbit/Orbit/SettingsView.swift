import SwiftUI

/// Orbit's own Settings app.
struct SettingsView: View {
    var body: some View {
        TabView {
            RingSettings()
                .tabItem { Label("Home Screen", systemImage: "circle.circle") }
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            StorageSettings()
                .tabItem { Label("Storage", systemImage: "internaldrive") }
        }
        .frame(minWidth: 520, minHeight: 520)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Ring

private struct RingSettings: View {
    @EnvironmentObject private var ring: RingStore
    @State private var showAppPicker = false
    @State private var showWebsiteForm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Apps on your ring")
                .font(.headline)
            Text("Drag to reorder. The first item sits at 12 o'clock. \(RingStore.minItems)–\(RingStore.maxItems) items.")
                .font(.callout)
                .foregroundStyle(.secondary)

            List {
                ForEach(ring.items) { item in
                    HStack(spacing: 10) {
                        RingIcon(item: item)
                            .frame(width: 20, height: 20)
                            .frame(width: 26, height: 26)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.name)
                            Text(item.kind == .app ? "Orbit app" : "Website · \(item.urlString ?? "")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button {
                            ring.remove(item)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .disabled(!ring.canRemove)
                        .help("Remove from ring")
                    }
                    .padding(.vertical, 2)
                }
                .onMove { ring.move(from: $0, to: $1) }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))

            HStack {
                Button("Add App…") { showAppPicker = true }
                    .disabled(!ring.canAdd)
                Button("Add Website…") { showWebsiteForm = true }
                    .disabled(!ring.canAdd)
                Spacer()
                Button("Reset to Defaults") { ring.resetToDefaults() }
            }
        }
        .padding(20)
        .sheet(isPresented: $showAppPicker) {
            AppPicker().environmentObject(ring)
        }
        .sheet(isPresented: $showWebsiteForm) {
            WebsiteForm().environmentObject(ring)
        }
    }
}

private struct AppPicker: View {
    @EnvironmentObject private var ring: RingStore
    @Environment(\.dismiss) private var dismiss

    private var available: [OrbitAppKind] {
        OrbitAppKind.allCases.filter { !ring.contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add an Orbit app to the ring").font(.headline)
            if available.isEmpty {
                Text("Every Orbit app is already on your ring.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(available) { kind in
                    Button {
                        ring.add(.app(kind))
                        dismiss()
                    } label: {
                        HStack(spacing: 10) {
                            OrbitAppGlyph(kind: kind)
                                .frame(width: 20, height: 20)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(kind.title)
                                Text(kind.subtitle).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 400, height: 440)
    }
}

private struct WebsiteForm: View {
    @EnvironmentObject private var ring: RingStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var address = ""

    private var url: URL? { URLInput.website(from: address) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add a website").font(.headline)
            Text("It opens in Orbit Browser over HTTPS.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Form {
                TextField("Name", text: $name, prompt: Text("BBC News"))
                TextField("Address", text: $address, prompt: Text("bbc.co.uk/news"))
            }
            if !address.isEmpty && url == nil {
                Text("That doesn't look like a website address.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") {
                    guard let url else { return }
                    let title = name.trimmingCharacters(in: .whitespaces)
                    ring.add(.web(title.isEmpty ? (url.host ?? "Website") : title, url.absoluteString))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(url == nil)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @EnvironmentObject private var weather: WeatherService
    @State private var city = ""

    var body: some View {
        Form {
            Section("Shortcuts") {
                LabeledContent("Show or hide Orbit", value: "⌥ Space")
                LabeledContent("All apps and search", value: "⌘ K")
                LabeledContent("New browser window", value: "⌘ T")
            }

            Section("Weather") {
                LabeledContent("Location") {
                    Text(weather.usingDeviceLocation ? "Your current location" : "The city below")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    TextField("City", text: $city)
                        .onSubmit { weather.fallbackCity = city }
                    Button("Set") { weather.fallbackCity = city }
                }
                Toggle("Use Fahrenheit", isOn: $weather.useFahrenheit)
            }
        }
        .formStyle(.grouped)
        .onAppear { city = weather.fallbackCity }
    }
}

// MARK: - Storage

private struct StorageSettings: View {
    @EnvironmentObject private var notes: NotesStore
    @EnvironmentObject private var calendar: CalendarService
    @EnvironmentObject private var music: MusicPlayer
    @EnvironmentObject private var photos: PhotosLibrary

    var body: some View {
        Form {
            Section("Orbit keeps its own data") {
                LabeledContent("Notes", value: "\(notes.notes.count)")
                LabeledContent("Calendar events", value: "\(calendar.events.count)")
                LabeledContent("Songs", value: "\(music.tracks.count)")
                LabeledContent("Photos and videos", value: "\(photos.items.count)")
            }
            Section {
                Text("Everything is stored in Orbit's own folder on this Mac and never in the Mac's Notes, Calendar, Music or Photos apps.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
