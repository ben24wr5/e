import SwiftUI
import AppKit

/// One slot on the ring: either a real Mac app or a website that opens
/// in Orbit's built-in browser.
struct RingItem: Identifiable, Codable, Hashable {
    enum Kind: String, Codable { case app, web }

    var id = UUID()
    var kind: Kind
    var name: String
    var bundleID: String?
    var appPath: String?
    var urlString: String?

    var url: URL? { urlString.flatMap(URL.init(string:)) }

    static func app(_ name: String, bundleID: String?, path: String? = nil) -> RingItem {
        RingItem(kind: .app, name: name, bundleID: bundleID, appPath: path)
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

    private let key = "orbit.ringItems.v1"

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
        [
            .web("Browser", "https://www.google.com"),
            .web("YouTube", "https://www.youtube.com"),
            .app("Music", bundleID: "com.apple.Music"),
            .app("Maps", bundleID: "com.apple.Maps"),
            .app("Mail", bundleID: "com.apple.mail"),
            .app("Photos", bundleID: "com.apple.Photos"),
            .app("Calendar", bundleID: "com.apple.iCal"),
            .app("System Settings", bundleID: "com.apple.systempreferences"),
        ]
    }

    var canAdd: Bool { items.count < RingStore.maxItems }
    var canRemove: Bool { items.count > RingStore.minItems }

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

/// Opens real Mac apps and resolves their icons.
@MainActor
enum Launcher {
    private static var iconCache: [String: NSImage] = [:]

    static func appURL(bundleID: String?, path: String?) -> URL? {
        if let bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return url
        }
        if let path, FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    static func appURL(for item: RingItem) -> URL? {
        appURL(bundleID: item.bundleID, path: item.appPath)
    }

    static func icon(forAppAt url: URL) -> NSImage {
        if let cached = iconCache[url.path] { return cached }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        image.size = NSSize(width: 128, height: 128)
        iconCache[url.path] = image
        return image
    }

    /// Launches (or brings forward) the app exactly as the Dock would.
    static func openApp(at url: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            if let error {
                NSLog("Orbit could not open \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }

    static func openApp(bundleID: String) {
        if let url = appURL(bundleID: bundleID, path: nil) { openApp(at: url) }
    }

    /// Opens a ring item: apps launch natively, websites go to Orbit's browser.
    static func open(_ item: RingItem, openWeb: (URL) -> Void) {
        switch item.kind {
        case .app:
            if let url = appURL(for: item) {
                openApp(at: url)
            } else {
                NSSound.beep()
            }
        case .web:
            if let url = item.url { openWeb(url) }
        }
    }
}
