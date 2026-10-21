import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

struct Track: Identifiable, Codable, Hashable {
    var id = UUID()
    var fileName: String
    var title: String
    var artist: String
    var album: String
    var duration: Double

    var url: URL { MusicPlayer.libraryFolder.appendingPathComponent(fileName) }
}

/// Orbit Music: its own library (songs are copied into Orbit) and its own player.
@MainActor
final class MusicPlayer: ObservableObject {
    nonisolated static var libraryFolder: URL { OrbitStorage.subfolder("Music") }
    nonisolated static let audioTypes: [UTType] = [.mp3, .mpeg4Audio, .wav, .aiff, .audio]

    @Published private(set) var tracks: [Track] = [] {
        didSet { OrbitStorage.save(tracks, to: "music.json") }
    }
    @Published private(set) var current: Track?
    @Published private(set) var isPlaying = false
    @Published private(set) var isImporting = false
    @Published private(set) var artwork: NSImage?
    @Published var position: Double = 0
    @Published var shuffle = false
    @Published var repeatAll = true
    @Published var volume: Float = 0.8 {
        didSet { player.volume = volume }
    }

    private let player = AVPlayer()
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var isScrubbing = false

    init() {
        tracks = (OrbitStorage.load([Track].self, from: "music.json") ?? [])
            .filter { FileManager.default.fileExists(atPath: $0.url.path) }
        player.volume = volume
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                guard let self, !self.isScrubbing else { return }
                self.position = time.seconds.isFinite ? time.seconds : 0
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.next(auto: true) }
        }
    }

    // MARK: Library

    /// Copies the chosen songs into Orbit's own library.
    func importSongs(from urls: [URL]) {
        isImporting = true
        Task {
            var added: [Track] = []
            for url in expand(urls) {
                if let track = await copyIn(url) { added.append(track) }
            }
            tracks.append(contentsOf: added)
            tracks.sort { ($0.artist, $0.album, $0.title) < ($1.artist, $1.album, $1.title) }
            isImporting = false
        }
    }

    func remove(_ track: Track) {
        if current?.id == track.id { stop() }
        try? FileManager.default.removeItem(at: track.url)
        tracks.removeAll { $0.id == track.id }
    }

    private func expand(_ urls: [URL]) -> [URL] {
        var files: [URL] = []
        for url in urls {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            if isDir.boolValue {
                let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil,
                                                            options: [.skipsHiddenFiles])
                while let file = walker?.nextObject() as? URL {
                    if Self.isAudio(file: file) { files.append(file) }
                }
            } else if Self.isAudio(file: url) {
                files.append(url)
            }
        }
        return files
    }

    private static func isAudio(file url: URL) -> Bool {
        ["mp3", "m4a", "aac", "wav", "aiff", "aif", "caf", "flac", "alac"].contains(url.pathExtension.lowercased())
    }

    private func copyIn(_ source: URL) async -> Track? {
        let fileName = "\(UUID().uuidString).\(source.pathExtension.lowercased())"
        let destination = Self.libraryFolder.appendingPathComponent(fileName)
        do {
            try FileManager.default.copyItem(at: source, to: destination)
        } catch {
            return nil
        }
        let asset = AVURLAsset(url: destination)
        let metadata = (try? await asset.load(.commonMetadata)) ?? []
        func value(_ id: AVMetadataIdentifier) async -> String? {
            guard let item = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: id).first else { return nil }
            return try? await item.load(.stringValue)
        }
        let duration = (try? await asset.load(.duration)).map { $0.seconds } ?? 0
        let fallback = source.deletingPathExtension().lastPathComponent
        return Track(
            fileName: fileName,
            title: await value(.commonIdentifierTitle) ?? fallback,
            artist: await value(.commonIdentifierArtist) ?? "Unknown Artist",
            album: await value(.commonIdentifierAlbumName) ?? "",
            duration: duration.isFinite ? duration : 0
        )
    }

    // MARK: Playback

    func play(_ track: Track) {
        current = track
        position = 0
        player.replaceCurrentItem(with: AVPlayerItem(url: track.url))
        player.play()
        isPlaying = true
        loadArtwork(for: track)
    }

    func togglePlay() {
        guard current != nil else {
            if let first = tracks.first { play(first) }
            return
        }
        if isPlaying { player.pause() } else { player.play() }
        isPlaying.toggle()
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        current = nil
        isPlaying = false
        artwork = nil
        position = 0
    }

    func next(auto: Bool = false) {
        guard !tracks.isEmpty else { return }
        guard let current, let index = tracks.firstIndex(of: current) else {
            play(tracks[0]); return
        }
        if shuffle, tracks.count > 1 {
            var pick = index
            while pick == index { pick = Int.random(in: 0..<tracks.count) }
            play(tracks[pick])
        } else if index + 1 < tracks.count {
            play(tracks[index + 1])
        } else if repeatAll || !auto {
            play(tracks[0])
        } else {
            isPlaying = false
        }
    }

    func previous() {
        guard !tracks.isEmpty else { return }
        if position > 3 { seek(to: 0); return }
        guard let current, let index = tracks.firstIndex(of: current) else { return }
        play(tracks[index > 0 ? index - 1 : tracks.count - 1])
    }

    func beginScrub() { isScrubbing = true }

    func seek(to seconds: Double) {
        position = seconds
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600)) { [weak self] _ in
            Task { @MainActor in self?.isScrubbing = false }
        }
    }

    private func loadArtwork(for track: Track) {
        artwork = nil
        Task {
            let asset = AVURLAsset(url: track.url)
            let metadata = (try? await asset.load(.commonMetadata)) ?? []
            guard let item = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .commonIdentifierArtwork).first,
                  let data = try? await item.load(.dataValue),
                  let image = NSImage(data: data),
                  self.current?.id == track.id else { return }
            self.artwork = image
        }
    }
}

// MARK: - UI

struct MusicApp: View {
    @EnvironmentObject private var music: MusicPlayer
    @State private var filter = ""
    @State private var importing = false

    private var shown: [Track] {
        let q = filter.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return music.tracks }
        return music.tracks.filter {
            $0.title.localizedCaseInsensitiveContains(q)
                || $0.artist.localizedCaseInsensitiveContains(q)
                || $0.album.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            AppHeader(kind: .music) {
                OrbitSearchField(prompt: "Search songs", text: $filter)
                    .frame(width: 240)
                Button {
                    importing = true
                } label: {
                    Label("Add Songs", systemImage: "plus")
                }
                .disabled(music.isImporting)
            }

            if music.tracks.isEmpty {
                AppMessage(symbol: "music.note.list",
                           title: music.isImporting ? "Adding songs…" : "Your Orbit music library is empty",
                           detail: "Add songs or a whole folder of music files (MP3, M4A, WAV, AIFF, FLAC). Orbit keeps its own copy, so it never touches the Mac's Music app.",
                           buttonTitle: music.isImporting ? nil : "Add Songs…",
                           action: { importing = true })
            } else {
                List {
                    ForEach(shown) { track in
                        TrackRow(track: track, isCurrent: music.current?.id == track.id, isPlaying: music.isPlaying)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) { music.play(track) }
                            .contextMenu {
                                Button("Play") { music.play(track) }
                                Button("Remove from Orbit Music", role: .destructive) { music.remove(track) }
                            }
                            .listRowBackground(music.current?.id == track.id ? Theme.chipHover : Color.clear)
                    }
                }
                .scrollContentBackground(.hidden)
                .overlay(alignment: .top) {
                    if music.isImporting { ProgressView("Adding songs…").padding(8) }
                }
            }

            NowPlayingBar()
        }
        .background(Theme.background)
        .foregroundStyle(Theme.text)
        .navigationTitle("Music")
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: MusicPlayer.audioTypes + [.folder],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { music.importSongs(from: urls) }
        }
    }
}

private struct TrackRow: View {
    let track: Track
    let isCurrent: Bool
    let isPlaying: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isCurrent ? (isPlaying ? "speaker.wave.2.fill" : "pause.fill") : "music.note")
                .foregroundStyle(isCurrent ? OrbitAppKind.music.tint : Theme.tertiary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title).font(.orbit(14, isCurrent ? .semibold : .regular)).lineLimit(1)
                Text([track.artist, track.album].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.orbit(12)).foregroundStyle(Theme.secondary).lineLimit(1)
            }
            Spacer()
            Text(formatTime(track.duration))
                .font(.orbit(12)).monospacedDigit().foregroundStyle(Theme.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct NowPlayingBar: View {
    @EnvironmentObject private var music: MusicPlayer

    var body: some View {
        HStack(spacing: 16) {
            Group {
                if let art = music.artwork {
                    Image(nsImage: art).resizable().scaledToFill()
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 20))
                        .foregroundStyle(OrbitAppKind.music.tint)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Theme.chip)
                }
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(music.current?.title ?? "Not playing").font(.orbit(14, .semibold)).lineLimit(1)
                Text(music.current?.artist ?? "Double-click a song to play it")
                    .font(.orbit(12)).foregroundStyle(Theme.secondary).lineLimit(1)
            }
            .frame(width: 200, alignment: .leading)

            VStack(spacing: 6) {
                HStack(spacing: 20) {
                    control("shuffle", active: music.shuffle, label: "Shuffle") { music.shuffle.toggle() }
                    control("backward.fill", label: "Previous") { music.previous() }
                    Button(action: music.togglePlay) {
                        Image(systemName: music.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(Theme.text)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(music.isPlaying ? "Pause" : "Play")
                    control("forward.fill", label: "Next") { music.next() }
                    control("repeat", active: music.repeatAll, label: "Repeat") { music.repeatAll.toggle() }
                }
                HStack(spacing: 8) {
                    Text(formatTime(music.position)).font(.orbit(11)).monospacedDigit()
                    Slider(value: Binding(
                        get: { music.position },
                        set: { music.position = $0 }
                    ), in: 0...max(music.current?.duration ?? 1, 1)) { editing in
                        if editing { music.beginScrub() } else { music.seek(to: music.position) }
                    }
                    .tint(OrbitAppKind.music.tint)
                    .disabled(music.current == nil)
                    Text(formatTime(music.current?.duration ?? 0)).font(.orbit(11)).monospacedDigit()
                }
                .foregroundStyle(Theme.secondary)
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 6) {
                Image(systemName: "speaker.fill").foregroundStyle(Theme.secondary)
                Slider(value: $music.volume, in: 0...1).frame(width: 100).tint(Theme.secondary)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Theme.card)
        .overlay(alignment: .top) { Rectangle().fill(Theme.cardLine).frame(height: 1) }
    }

    private func control(_ symbol: String, active: Bool = false, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(active ? OrbitAppKind.music.tint : Theme.text)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

func formatTime(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds > 0 else { return "0:00" }
    let s = Int(seconds.rounded())
    return s >= 3600
        ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
        : String(format: "%d:%02d", s / 60, s % 60)
}
