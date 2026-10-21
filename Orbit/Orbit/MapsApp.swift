import SwiftUI
import MapKit

/// Orbit Maps: search places and get directions, drawn with Apple's map data
/// directly inside Orbit (the Mac's Maps app is never used).
struct MapsApp: View {
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var selected: MKMapItem?
    @State private var route: MKRoute?
    @State private var transport: MKDirectionsTransportType = .automobile
    @State private var style: MapStyleChoice = .standard
    @State private var isSearching = false
    @State private var message: String?

    enum MapStyleChoice: String, CaseIterable, Identifiable {
        case standard = "Map", satellite = "Satellite", hybrid = "Hybrid"
        var id: String { rawValue }
        var style: MapStyle {
            switch self {
            case .standard: return .standard(elevation: .realistic)
            case .satellite: return .imagery(elevation: .realistic)
            case .hybrid: return .hybrid(elevation: .realistic)
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 320)
                .background(Theme.background)
            Rectangle().fill(Theme.cardLine).frame(width: 1)
            map
        }
        .foregroundStyle(Theme.text)
        .navigationTitle("Maps")
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            AppHeader(kind: .maps) { EmptyView() }
            VStack(alignment: .leading, spacing: 12) {
                OrbitSearchField(prompt: "Search places", text: $query) { Task { await search() } }
                Picker("Map style", selection: $style) {
                    ForEach(MapStyleChoice.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .padding(16)

            if let item = selected {
                placeDetail(item)
            } else if isSearching {
                ProgressView().frame(maxWidth: .infinity).padding(.top, 30)
            } else if results.isEmpty {
                Text(message ?? "Search for a place, an address or something like “coffee”.")
                    .font(.orbit(13))
                    .foregroundStyle(Theme.secondary)
                    .padding(.horizontal, 16)
                Spacer()
            } else {
                List(results, id: \.self) { item in
                    Button {
                        select(item)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name ?? "Place").font(.orbit(14, .semibold))
                            Text(address(of: item))
                                .font(.orbit(12))
                                .foregroundStyle(Theme.secondary)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                }
                .scrollContentBackground(.hidden)
            }
        }
    }

    private func placeDetail(_ item: MKMapItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    selected = nil
                    route = nil
                } label: {
                    Label("Results", systemImage: "chevron.left").font(.orbit(13))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.secondary)

                Text(item.name ?? "Place").font(.orbit(20, .bold))
                Text(address(of: item)).font(.orbit(13)).foregroundStyle(Theme.secondary)
                if let phone = item.phoneNumber, !phone.isEmpty {
                    Label(phone, systemImage: "phone").font(.orbit(13))
                }
                if let category = item.pointOfInterestCategory {
                    Label(categoryName(category), systemImage: "tag").font(.orbit(13))
                }

                Divider().overlay(Theme.cardLine)

                Picker("Travel by", selection: $transport) {
                    Image(systemName: "car.fill").tag(MKDirectionsTransportType.automobile)
                    Image(systemName: "figure.walk").tag(MKDirectionsTransportType.walking)
                    Image(systemName: "tram.fill").tag(MKDirectionsTransportType.transit)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: transport) { _, _ in
                    if route != nil { Task { await directions(to: item) } }
                }

                Button {
                    Task { await directions(to: item) }
                } label: {
                    Label("Directions from my location", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .foregroundStyle(Theme.background)

                if let route {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(travelTime(route.expectedTravelTime)).font(.orbit(22, .bold))
                        Text(distance(route.distance)).font(.orbit(13)).foregroundStyle(Theme.secondary)
                    }
                    ForEach(Array(route.steps.enumerated()), id: \.offset) { _, step in
                        if !step.instructions.isEmpty {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "arrow.turn.up.right").foregroundStyle(Theme.accent)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(step.instructions).font(.orbit(13))
                                    Text(distance(step.distance)).font(.orbit(11)).foregroundStyle(Theme.secondary)
                                }
                            }
                        }
                    }
                } else if let message {
                    Text(message).font(.orbit(12)).foregroundStyle(Theme.secondary)
                }
            }
            .padding(16)
        }
    }

    // MARK: Map

    private var map: some View {
        Map(position: $position, selection: $selected) {
            UserAnnotation()
            ForEach(results, id: \.self) { item in
                Marker(item: item)
                    .tint(Theme.accent)
            }
            if let route {
                MapPolyline(route.polyline)
                    .stroke(Theme.accent, lineWidth: 6)
            }
        }
        .mapStyle(style.style)
        .mapControls {
            MapUserLocationButton()
            MapCompass()
            MapPitchToggle()
            MapZoomStepper()
            MapScaleView()
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            visibleRegion = context.region
        }
        .onChange(of: selected) { _, item in
            route = nil
            if let item { focus(on: item) }
        }
    }

    // MARK: Actions

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        isSearching = true
        selected = nil
        route = nil
        message = nil
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        if let visibleRegion { request.region = visibleRegion }
        do {
            let response = try await MKLocalSearch(request: request).start()
            results = response.mapItems
            position = .region(response.boundingRegion)
            if results.isEmpty { message = "No places found for “\(text)”." }
        } catch {
            results = []
            message = "No places found for “\(text)”."
        }
        isSearching = false
    }

    private func select(_ item: MKMapItem) {
        selected = item
    }

    private func focus(on item: MKMapItem) {
        withAnimation {
            position = .region(MKCoordinateRegion(
                center: item.placemark.coordinate,
                latitudinalMeters: 1200, longitudinalMeters: 1200
            ))
        }
    }

    private func directions(to item: MKMapItem) async {
        message = nil
        let request = MKDirections.Request()
        request.source = MKMapItem.forCurrentLocation()
        request.destination = item
        request.transportType = transport
        do {
            let response = try await MKDirections(request: request).calculate()
            guard let first = response.routes.first else { return }
            route = first
            withAnimation {
                position = .rect(first.polyline.boundingMapRect.insetBy(dx: -2000, dy: -2000))
            }
        } catch {
            route = nil
            message = transport == .transit
                ? "Public transport directions aren't available for this trip."
                : "Couldn't find a route. Make sure Location is allowed for Orbit."
        }
    }

    // MARK: Formatting

    private func address(of item: MKMapItem) -> String {
        let p = item.placemark
        return [p.subThoroughfare, p.thoroughfare, p.locality, p.postalCode, p.country]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    private func categoryName(_ category: MKPointOfInterestCategory) -> String {
        category.rawValue
            .replacingOccurrences(of: "MKPOICategory", with: "")
            .replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
    }

    private func travelTime(_ seconds: TimeInterval) -> String {
        let f = DateComponentsFormatter()
        f.allowedUnits = seconds >= 3600 ? [.hour, .minute] : [.minute]
        f.unitsStyle = .short
        return f.string(from: seconds) ?? ""
    }

    private func distance(_ meters: CLLocationDistance) -> String {
        Measurement(value: meters, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
    }
}
