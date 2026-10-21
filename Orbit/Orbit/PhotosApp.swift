import SwiftUI
import AVKit
import ImageIO
import UniformTypeIdentifiers

struct PhotoItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var fileName: String
    var originalName: String
    var isVideo: Bool
    var added: Date
    var isFavorite = false

    var url: URL { PhotosLibrary.folder.appendingPathComponent(fileName) }
}

/// Orbit Photos: its own photo and video library, kept inside Orbit.
@MainActor
final class PhotosLibrary: ObservableObject {
    nonisolated static var folder: URL { OrbitStorage.subfolder("Photos") }

    @Published private(set) var items: [PhotoItem] = [] {
        didSet { OrbitStorage.save(items, to: "photos.json") }
    }
    @Published private(set) var isImporting = false

    private let thumbnails = NSCache<NSString, NSImage>()

    init() {
        items = (OrbitStorage.load([PhotoItem].self, from: "photos.json") ?? [])
            .filter { FileManager.default.fileExists(atPath: $0.url.path) }
    }

    func importFiles(_ urls: [URL]) {
        isImporting = true
        Task.detached(priority: .userInitiated) { [weak self] in
            var added: [PhotoItem] = []
            for url in PhotosLibrary.expand(urls) {
                let ext = url.pathExtension.lowercased()
                let fileName = "\(UUID().uuidString).\(ext)"
                let destination = PhotosLibrary.folder.appendingPathComponent(fileName)
                guard (try? FileManager.default.copyItem(at: url, to: destination)) != nil else { continue }
                added.append(PhotoItem(fileName: fileName,
                                       originalName: url.lastPathComponent,
                                       isVideo: PhotosLibrary.videoExtensions.contains(ext),
                                       added: Date()))
            }
            let newItems = added
            await self?.finishImport(newItems)
        }
    }

    private func finishImport(_ added: [PhotoItem]) {
        items.insert(contentsOf: added.reversed(), at: 0)
        isImporting = false
    }

    func toggleFavorite(_ item: PhotoItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].isFavorite.toggle()
    }

    func delete(_ item: PhotoItem) {
        try? FileManager.default.removeItem(at: item.url)
        items.removeAll { $0.id == item.id }
        thumbnails.removeAllObjects()
    }

    func thumbnail(for item: PhotoItem, size: CGFloat) async -> NSImage? {
        let key = "\(item.fileName)-\(Int(size))" as NSString
        if let cached = thumbnails.object(forKey: key) { return cached }
        let url = item.url
        let isVideo = item.isVideo
        let image: NSImage? = await Task.detached(priority: .utility) {
            isVideo ? PhotosLibrary.videoFrame(url, size: size) : PhotosLibrary.downsample(url, size: size)
        }.value
        if let image { thumbnails.setObject(image, forKey: key) }
        return image
    }

    // MARK: Helpers (run off the main thread)

    nonisolated static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "gif", "tiff", "tif", "bmp", "webp"]
    nonisolated static let videoExtensions: Set<String> = ["mov", "mp4", "m4v"]

    nonisolated static func expand(_ urls: [URL]) -> [URL] {
        var files: [URL] = []
        for url in urls {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            if isDir.boolValue {
                let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil,
                                                            options: [.skipsHiddenFiles, .skipsPackageDescendants])
                while let file = walker?.nextObject() as? URL {
                    if isMedia(file) { files.append(file) }
                }
            } else if isMedia(url) {
                files.append(url)
            }
        }
        return files
    }

    nonisolated static func isMedia(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return imageExtensions.contains(ext) || videoExtensions.contains(ext)
    }

    nonisolated static func downsample(_ url: URL, size: CGFloat) -> NSImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: size,
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    nonisolated static func videoFrame(_ url: URL, size: CGFloat) -> NSImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: size, height: size)
        guard let cg = try? generator.copyCGImage(at: CMTime(seconds: 0.5, preferredTimescale: 600), actualTime: nil)
        else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}

// MARK: - UI

struct PhotosApp: View {
    @EnvironmentObject private var library: PhotosLibrary
    @State private var importing = false
    @State private var showFavorites = false
    @State private var viewing: PhotoItem?
    @State private var tileSize: CGFloat = 170

    private var shown: [PhotoItem] {
        showFavorites ? library.items.filter(\.isFavorite) : library.items
    }

    var body: some View {
        VStack(spacing: 0) {
            AppHeader(kind: .photos, title: showFavorites ? "Favourites" : "Photos") {
                Picker("Show", selection: $showFavorites) {
                    Text("All").tag(false)
                    Text("Favourites").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 180)
                Slider(value: $tileSize, in: 110...300)
                    .frame(width: 110)
                    .help("Thumbnail size")
                Button {
                    importing = true
                } label: {
                    Label("Add Photos", systemImage: "plus")
                }
                .disabled(library.isImporting)
            }

            if library.items.isEmpty {
                AppMessage(symbol: "photo.on.rectangle.angled",
                           title: library.isImporting ? "Adding photos…" : "Your Orbit photo library is empty",
                           detail: "Add pictures and videos, or a whole folder of them. Orbit keeps its own copy, separate from the Mac's Photos app.",
                           buttonTitle: library.isImporting ? nil : "Add Photos…",
                           action: { importing = true })
            } else if shown.isEmpty {
                AppMessage(symbol: "heart", title: "No favourites yet",
                           detail: "Open a photo and press the heart to add it here.")
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: tileSize, maximum: tileSize * 1.6), spacing: 4)],
                              spacing: 4) {
                        ForEach(shown) { item in
                            PhotoTile(item: item, size: tileSize)
                                .onTapGesture { viewing = item }
                                .contextMenu {
                                    Button(item.isFavorite ? "Remove from Favourites" : "Add to Favourites") {
                                        library.toggleFavorite(item)
                                    }
                                    Button("Delete from Orbit Photos", role: .destructive) { library.delete(item) }
                                }
                        }
                    }
                    .padding(4)
                }
            }
        }
        .background(Theme.background)
        .foregroundStyle(Theme.text)
        .navigationTitle("Photos")
        .overlay {
            if let item = viewing {
                PhotoViewer(item: item, items: shown, viewing: $viewing)
            }
        }
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [.image, .movie, .folder],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { library.importFiles(urls) }
        }
    }
}

private struct PhotoTile: View {
    @EnvironmentObject private var library: PhotosLibrary
    let item: PhotoItem
    let size: CGFloat
    @State private var image: NSImage?

    var body: some View {
        Color(hex: 0x1D1F25)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(nsImage: image).resizable().scaledToFill()
                }
            }
            .clipped()
            .overlay(alignment: .bottomLeading) {
                if item.isVideo {
                    Image(systemName: "video.fill")
                        .font(.system(size: 11))
                        .padding(6)
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if item.isFavorite {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 11))
                        .padding(6)
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                }
            }
            .contentShape(Rectangle())
            .task(id: item.id) {
                image = await library.thumbnail(for: item, size: 420)
            }
    }
}

private struct PhotoViewer: View {
    @EnvironmentObject private var library: PhotosLibrary
    let item: PhotoItem
    let items: [PhotoItem]
    @Binding var viewing: PhotoItem?
    @State private var full: NSImage?
    @State private var player: AVPlayer?

    private var current: PhotoItem {
        library.items.first(where: { $0.id == item.id }) ?? item
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.96).ignoresSafeArea()

            Group {
                if item.isVideo {
                    VideoPlayer(player: player)
                } else if let full {
                    Image(nsImage: full).resizable().scaledToFit()
                } else {
                    ProgressView()
                }
            }
            .padding(.vertical, 56)
            .padding(.horizontal, 60)

            VStack {
                HStack(spacing: 14) {
                    Text(current.originalName).font(.orbit(13)).foregroundStyle(Theme.secondary).lineLimit(1)
                    Spacer()
                    Button { library.toggleFavorite(current) } label: {
                        Image(systemName: current.isFavorite ? "heart.fill" : "heart")
                    }
                    .accessibilityLabel("Favourite")
                    Button { viewing = nil } label: { Image(systemName: "xmark") }
                        .keyboardShortcut(.cancelAction)
                        .accessibilityLabel("Close")
                }
                .buttonStyle(.plain)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.text)
                .padding(16)
                Spacer()
            }

            HStack {
                arrow("chevron.left", offset: -1)
                Spacer()
                arrow("chevron.right", offset: 1)
            }
            .padding(.horizontal, 12)
        }
        .task(id: item.id) {
            full = nil
            player?.pause()
            player = nil
            if item.isVideo {
                let newPlayer = AVPlayer(url: item.url)
                player = newPlayer
                newPlayer.play()
            } else {
                full = await library.thumbnail(for: item, size: 2600)
            }
        }
        .onDisappear { player?.pause() }
    }

    private func arrow(_ symbol: String, offset: Int) -> some View {
        Button {
            guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
            let target = index + offset
            if items.indices.contains(target) { viewing = items[target] }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .semibold))
                .frame(width: 44, height: 44)
                .background(Circle().fill(Theme.chip.opacity(0.8)))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.text)
        .keyboardShortcut(offset < 0 ? .leftArrow : .rightArrow, modifiers: [])
        .accessibilityLabel(offset < 0 ? "Previous" : "Next")
    }
}
