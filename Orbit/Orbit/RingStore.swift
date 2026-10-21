import SwiftUI

/// One slot on the ring: one of Orbit's built-in apps, or a website shortcut
/// that opens in Orbit's own browser.
struct RingItem: Identifiable, Codable, Hashable {
    enum Kind: String, Codable { case app, web }

    var id = UUID()
    var kind: Kind
    var name: String
    var app: OrbitAppKind?
    var urlString: String?

    var url: URL? { urlString.flatMap(URL.init(string:)) }

    static func app(_ app: OrbitAppKind) -> RingItem {
        RingItem(kind: .app, name: app.title, app: app)
    }

    static func web(_ name: String, _ url: String) -> RingItem {
        RingItem(kind: .web, name: name, urlString: url)
    }
}

@MainActor
final class RingStore: ObservableObject {
    static let minItems = 3
    static let maxItems = 12

    @Published var items: [RingItem] {
        didSet { save() }
    }

    private let key = "orbit.ringItems.v2"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([RingItem].self, from: data),
           !saved.isEmpty {
            items = saved
        } else {
            items = RingStore.defaultItems
        }
    }

    static var defaultItems: [RingItem] {
        [.browser, .youtube, .notes, .music, .maps, .photos, .calendar, .settings].map(RingItem.app)
    }

    var canAdd: Bool { items.count < RingStore.maxItems }
    var canRemove: Bool { items.count > RingStore.minItems }

    func contains(_ app: OrbitAppKind) -> Bool {
        items.contains { $0.app == app }
    }

    func add(_ item: RingItem) {
        guard canAdd else { return }
        items.append(item)
    }

    func remove(_ item: RingItem) {
        guard canRemove else { return }
        items.removeAll { $0.id == item.id }
    }

    func move(from source: IndexSet, to destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
    }

    func resetToDefaults() {
        items = RingStore.defaultItems
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
