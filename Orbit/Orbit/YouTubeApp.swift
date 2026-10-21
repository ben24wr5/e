import SwiftUI
import WebKit

struct YouTubeVideo: Identifiable, Hashable {
    let id: String
    var title: String
    var channel: String
    var duration: String
    var views: String
    var published: String

    var thumbnail: URL? { URL(string: "https://i.ytimg.com/vi/\(id)/hqdefault.jpg") }
    var watchURL: URL { URL(string: "https://www.youtube.com/watch?v=\(id)")! }
    var isLive: Bool { duration.isEmpty && views.lowercased().contains("watching") }
}

/// Orbit's YouTube app: native search and results, with YouTube's own player.
@MainActor
final class YouTubeModel: ObservableObject {
    @Published var query = ""
    @Published private(set) var results: [YouTubeVideo] = []
    @Published private(set) var heading = "Trending"
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published var playing: YouTubeVideo?

    static let categories = ["Trending", "Music", "Gaming", "News", "Sport", "Comedy", "Learning", "Tech", "Cooking", "Film"]

    private var task: Task<Void, Never>?

    func loadHomeIfNeeded() {
        if results.isEmpty && !isLoading && errorMessage == nil {
            browse("Trending")
        }
    }

    /// A category chip: searches without filling the search box.
    func browse(_ category: String) {
        let q = category == "Trending" ? "trending videos this week" : "\(category.lowercased()) videos"
        run(q, heading: category)
    }

    /// A typed search, or a pasted YouTube link which plays directly.
    func search(_ text: String) {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        if let id = YouTubeSearch.videoID(from: q) {
            playing = YouTubeVideo(id: id, title: "YouTube video", channel: "", duration: "", views: "", published: "")
            return
        }
        query = q
        run(q, heading: "Results for “\(q)”")
    }

    private func run(_ q: String, heading: String) {
        playing = nil
        self.heading = heading
        task?.cancel()
        isLoading = true
        errorMessage = nil
        task = Task { [weak self] in
            do {
                let videos = try await YouTubeSearch.fetch(q)
                guard !Task.isCancelled, let self else { return }
                self.results = videos
                self.isLoading = false
                if videos.isEmpty { self.errorMessage = "No videos found." }
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.isLoading = false
                self.errorMessage = "Couldn't reach YouTube. Check your internet connection and try again."
            }
        }
    }

    func retry() {
        if heading.hasPrefix("Results"), !query.isEmpty { search(query) } else { browse(heading) }
    }
}

/// Reads YouTube's own search page over HTTPS (no account or API key needed).
enum YouTubeSearch {
    static func fetch(_ q: String) async throws -> [YouTubeVideo] {
        var comps = URLComponents(string: "https://www.youtube.com/results")!
        comps.queryItems = [
            URLQueryItem(name: "search_query", value: q),
            URLQueryItem(name: "hl", value: "en"),
            URLQueryItem(name: "gl", value: "GB"),
        ]
        var request = URLRequest(url: comps.url!)
        request.setValue(BrowserModel.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("en-GB,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("SOCS=CAI; CONSENT=YES+1", forHTTPHeaderField: "Cookie")
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let html = String(data: data, encoding: .utf8),
              let json = initialData(in: html) else {
            throw URLError(.cannotParseResponse)
        }
        var renderers: [[String: Any]] = []
        collect(json, into: &renderers)
        var seen = Set<String>()
        return renderers.compactMap(parse).filter { seen.insert($0.id).inserted }
    }

    static func videoID(from text: String) -> String? {
        guard let url = URL(string: text), let host = url.host?.lowercased() else { return nil }
        if host.hasSuffix("youtu.be") {
            let id = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return id.isEmpty ? nil : id
        }
        guard host.contains("youtube.com") else { return nil }
        if let v = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "v" })?.value, !v.isEmpty {
            return v
        }
        let parts = url.path.split(separator: "/").map(String.init)
        if parts.count >= 2, ["shorts", "embed", "live"].contains(parts[0]) { return parts[1] }
        return nil
    }

    private static func initialData(in html: String) -> Any? {
        for marker in ["var ytInitialData = ", "window[\"ytInitialData\"] = ", "ytInitialData = "] {
            guard let start = html.range(of: marker) else { continue }
            let rest = html[start.upperBound...]
            guard let end = rest.range(of: ";</script>") else { continue }
            let jsonText = String(rest[..<end.lowerBound])
            if let data = jsonText.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data) {
                return object
            }
        }
        return nil
    }

    private static func collect(_ node: Any, into list: inout [[String: Any]]) {
        if let dict = node as? [String: Any] {
            if let renderer = dict["videoRenderer"] as? [String: Any] {
                list.append(renderer)
            }
            for value in dict.values { collect(value, into: &list) }
        } else if let array = node as? [Any] {
            for value in array { collect(value, into: &list) }
        }
    }

    private static func text(_ any: Any?) -> String {
        guard let dict = any as? [String: Any] else { return "" }
        if let simple = dict["simpleText"] as? String { return simple }
        if let runs = dict["runs"] as? [[String: Any]] {
            return runs.compactMap { $0["text"] as? String }.joined()
        }
        return ""
    }

    private static func parse(_ r: [String: Any]) -> YouTubeVideo? {
        guard let id = r["videoId"] as? String else { return nil }
        let title = text(r["title"])
        guard !title.isEmpty else { return nil }
        let owner = text(r["ownerText"])
        let channel = owner.isEmpty ? text(r["longBylineText"]) : owner
        let short = text(r["shortViewCountText"])
        let views = short.isEmpty ? text(r["viewCountText"]) : short
        return YouTubeVideo(
            id: id,
            title: title,
            channel: channel,
            duration: text(r["lengthText"]),
            views: views,
            published: text(r["publishedTimeText"])
        )
    }
}

// MARK: - App UI

struct YouTubeApp: View {
    @EnvironmentObject private var yt: YouTubeModel
    @State private var field = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            if let video = yt.playing {
                YouTubePlayerView(videoID: video.id)
            } else {
                categoryBar
                content
            }
        }
        .background(Theme.background)
        .foregroundStyle(Theme.text)
        .navigationTitle(yt.playing?.title ?? "YouTube")
        .onAppear {
            field = yt.query
            yt.loadHomeIfNeeded()
        }
        .onChange(of: yt.query) { _, newValue in field = newValue }
    }

    private var header: some View {
        HStack(spacing: 12) {
            if yt.playing != nil {
                Button {
                    yt.playing = nil
                } label: {
                    Label("Videos", systemImage: "chevron.left")
                        .font(.orbit(13, .medium))
                }
                .buttonStyle(.plain)
                .keyboardShortcut("[", modifiers: .command)
            }
            HStack(spacing: 6) {
                OrbitAppGlyph(kind: .youtube).frame(width: 24, height: 18)
                Text("YouTube").font(.orbit(17, .bold))
            }
            Spacer(minLength: 16)
            OrbitSearchField(prompt: "Search YouTube or paste a link", text: $field) {
                yt.search(field)
            }
            .frame(maxWidth: 460)
            Spacer(minLength: 16)
        }
        .padding(.horizontal, 18)
        .frame(height: 56)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.cardLine).frame(height: 1) }
    }

    private var categoryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(YouTubeModel.categories, id: \.self) { category in
                    let selected = yt.heading == category
                    Button(category) { yt.browse(category) }
                        .buttonStyle(.plain)
                        .font(.orbit(13, .medium))
                        .padding(.horizontal, 14)
                        .frame(height: 30)
                        .background(Capsule().fill(selected ? Theme.text : Theme.chip))
                        .foregroundStyle(selected ? Theme.background : Theme.text)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
    }

    @ViewBuilder private var content: some View {
        if yt.isLoading && yt.results.isEmpty {
            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let message = yt.errorMessage, yt.results.isEmpty {
            AppMessage(symbol: "wifi.exclamationmark", title: "Nothing to show", detail: message,
                       buttonTitle: "Try Again", action: { yt.retry() })
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text(yt.heading).font(.orbit(20, .bold))
                        if yt.isLoading { ProgressView().controlSize(.small) }
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 250, maximum: 380), spacing: 18)],
                              alignment: .leading, spacing: 24) {
                        ForEach(yt.results) { video in
                            VideoCard(video: video) { yt.playing = video }
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 24)
            }
        }
    }
}

private struct VideoCard: View {
    let video: YouTubeVideo
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Color(hex: 0x1D1F25)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .overlay {
                        AsyncImage(url: video.thumbnail) { phase in
                            if let image = phase.image {
                                image.resizable().scaledToFill()
                            } else {
                                Color(hex: 0x1D1F25)
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(alignment: .bottomTrailing) {
                        if video.isLive || !video.duration.isEmpty {
                            Text(video.isLive ? "LIVE" : video.duration)
                                .font(.orbit(11, .semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(RoundedRectangle(cornerRadius: 5)
                                    .fill(video.isLive ? Color(hex: 0xCC0000) : Color.black.opacity(0.8)))
                                .foregroundStyle(.white)
                                .padding(8)
                        }
                    }
                    .scaleEffect(hovering ? 1.02 : 1)
                    .animation(.easeOut(duration: 0.15), value: hovering)

                Text(video.title)
                    .font(.orbit(14, .semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if !video.channel.isEmpty {
                    Text(video.channel)
                        .font(.orbit(12))
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                }
                let meta = [video.views, video.published].filter { !$0.isEmpty }.joined(separator: " · ")
                if !meta.isEmpty {
                    Text(meta)
                        .font(.orbit(12))
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(video.title)
    }
}

// MARK: - Player

/// YouTube's own player and watch page, with the site's top bar hidden so it
/// sits inside Orbit. Full screen, captions, quality and sign-in all work.
struct YouTubePlayerView: NSViewRepresentable {
    let videoID: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.preferences.isElementFullscreenEnabled = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.allowsAirPlayForMediaPlayback = true

        let css = """
        #masthead-container, ytd-masthead, tp-yt-app-drawer#guide, ytd-mini-guide-renderer,
        #guide, ytd-popup-container tp-yt-iron-dropdown[hidden] { display: none !important; }
        ytd-app { --ytd-masthead-height: 0px !important; }
        #page-manager.ytd-app { margin-top: 0 !important; }
        html, body, ytd-app { background: #0E0F12 !important; }
        """
        let js = """
        (function(){
          var s = document.createElement('style');
          s.textContent = \(String(reflecting: css));
          (document.head || document.documentElement).appendChild(s);
        })();
        """
        configuration.userContentController.addUserScript(
            WKUserScript(source: js, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        )

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = BrowserModel.userAgent
        webView.allowsBackForwardNavigationGestures = true
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        load(videoID, into: webView, coordinator: context.coordinator)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if context.coordinator.currentID != videoID {
            load(videoID, into: webView, coordinator: context.coordinator)
        }
    }

    private func load(_ id: String, into webView: WKWebView, coordinator: Coordinator) {
        coordinator.currentID = id
        // Dark theme, English.
        let cookie = HTTPCookie(properties: [
            .domain: ".youtube.com", .path: "/", .name: "PREF",
            .value: "f6=400&hl=en", .secure: "TRUE",
            .expires: Date().addingTimeInterval(60 * 60 * 24 * 365),
        ])
        let url = URL(string: "https://www.youtube.com/watch?v=\(id)")!
        if let cookie {
            webView.configuration.websiteDataStore.httpCookieStore.setCookie(cookie) {
                webView.load(URLRequest(url: url))
            }
        } else {
            webView.load(URLRequest(url: url))
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var currentID: String?

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let scheme = navigationAction.request.url?.scheme?.lowercased() else {
                decisionHandler(.allow); return
            }
            decisionHandler(["https", "about", "blob", "data"].contains(scheme) ? .allow : .cancel)
        }

        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }
    }
}
