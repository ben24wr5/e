import Foundation
import AppKit

struct AppInfo: Identifiable, Hashable {
    var id: String { path }
    let name: String
    let path: String
    let bundleID: String?

    var url: URL { URL(fileURLWithPath: path) }
}

/// Every app installed on this Mac, for search and for adding to the ring.
@MainActor
final class AppCatalog: ObservableObject {
    @Published private(set) var apps: [AppInfo] = []
    @Published private(set) var isLoading = false

    init() {
        reload()
    }

    func reload() {
        isLoading = true
        Task.detached(priority: .utility) { [weak self] in
            let found = AppCatalog.scan()
            await self?.apply(found)
        }
    }

    private func apply(_ found: [AppInfo]) {
        apps = found
        isLoading = false
    }

    func search(_ query: String, limit: Int = 7) -> [AppInfo] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        let matches = apps.filter { $0.name.lowercased().contains(q) }
        let ranked = matches.sorted { a, b in
            let ap = a.name.lowercased().hasPrefix(q)
            let bp = b.name.lowercased().hasPrefix(q)
            if ap != bp { return ap }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
        return Array(ranked.prefix(limit))
    }

    nonisolated static func scan() -> [AppInfo] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        let roots = [
            "/Applications",
            "/System/Applications",
            "/System/Applications/Utilities",
            "/System/Library/CoreServices/Applications",
            "\(home)/Applications",
        ]

        var seenPaths = Set<String>()
        var seenBundles = Set<String>()
        var result: [AppInfo] = []

        func consider(_ path: String) {
            let resolved = (path as NSString).resolvingSymlinksInPath
            guard seenPaths.insert(resolved).inserted else { return }
            let bundle = Bundle(path: path)
            let bundleID = bundle?.bundleIdentifier
            if let bundleID, !seenBundles.insert(bundleID).inserted { return }
            let info = bundle?.localizedInfoDictionary ?? bundle?.infoDictionary
            let name = (info?["CFBundleDisplayName"] as? String)
                ?? (info?["CFBundleName"] as? String)
                ?? ((path as NSString).lastPathComponent as NSString).deletingPathExtension
            result.append(AppInfo(name: name, path: path, bundleID: bundleID))
        }

        for root in roots {
            guard let entries = try? fm.contentsOfDirectory(atPath: root) else { continue }
            for entry in entries where !entry.hasPrefix(".") {
                let path = (root as NSString).appendingPathComponent(entry)
                if entry.hasSuffix(".app") {
                    consider(path)
                } else {
                    // One level deeper, e.g. /Applications/Utilities or vendor folders.
                    var isDir: ObjCBool = false
                    guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue,
                          let inner = try? fm.contentsOfDirectory(atPath: path) else { continue }
                    for sub in inner where sub.hasSuffix(".app") {
                        consider((path as NSString).appendingPathComponent(sub))
                    }
                }
            }
        }

        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
