import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            RingSettings()
                .tabItem { Label("Ring", systemImage: "circle.circle") }
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(width: 520, height: 520)
    }
}

// MARK: - Ring

private struct RingSettings: View {
    @EnvironmentObject private var ring: RingStore
    @EnvironmentObject private var catalog: AppCatalog
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
                            .frame(width: 24, height: 24)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.name)
                            Text(item.kind == .app ? "Mac app" : (item.urlString ?? "Website"))
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
            AppPicker().environmentObject(ring).environmentObject(catalog)
        }
        .sheet(isPresented: $showWebsiteForm) {
            WebsiteForm().environmentObject(ring)
        }
    }
}

private struct AppPicker: View {
    @EnvironmentObject private var ring: RingStore
    @EnvironmentObject private var catalog: AppCatalog
    @Environment(\.dismiss) private var dismiss
    @State private var filter = ""

    private var shown: [AppInfo] {
        let q = filter.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? catalog.apps : catalog.apps.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add an app to the ring").font(.headline)
            TextField("Filter", text: $filter)
                .textFieldStyle(.roundedBorder)
            if catalog.isLoading && catalog.apps.isEmpty {
                ProgressView("Finding your apps…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(shown) { app in
                    Button {
                        ring.add(.app(app.name, bundleID: app.bundleID, path: app.path))
                        dismiss()
                    } label: {
                        HStack(spacing: 10) {
                            Image(nsImage: Launcher.icon(forAppAt: app.url))
                                .resizable()
                                .frame(width: 22, height: 22)
                            Text(app.name)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack {
                Button("Rescan") { catalog.reload() }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 420, height: 480)
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
            Text("It opens in Orbit's built-in browser over HTTPS.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Form {
                TextField("Name", text: $name, prompt: Text("YouTube"))
                TextField("Address", text: $address, prompt: Text("youtube.com"))
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
    @EnvironmentObject private var calendar: CalendarService
    @State private var city = ""

    var body: some View {
        Form {
            Section("Shortcut") {
                LabeledContent("Show or hide Orbit", value: "⌥ Space")
                LabeledContent("Search", value: "⌘ K")
                LabeledContent("New browser window", value: "⌘ T")
            }

            Section("Weather") {
                LabeledContent("Location") {
                    Text(weather.usingDeviceLocation ? "Your Mac's location" : "City below")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    TextField("City when location is off", text: $city)
                        .onSubmit { weather.fallbackCity = city }
                    Button("Set") { weather.fallbackCity = city }
                }
                Toggle("Use Fahrenheit", isOn: $weather.useFahrenheit)
            }

            Section("Calendar") {
                LabeledContent("Access") {
                    switch calendar.status {
                    case .ready: Text("Allowed").foregroundStyle(.secondary)
                    case .denied:
                        Button("Open Privacy Settings") { calendar.openPrivacySettings() }
                    case .unknown: Text("Asking…").foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { city = weather.fallbackCity }
    }
}
