import SwiftUI

/// The centre-button search: finds installed Mac apps, opens websites,
/// and searches Google or YouTube in Orbit's browser.
struct SearchOverlay: View {
    @Binding var isPresented: Bool

    @EnvironmentObject private var catalog: AppCatalog
    @Environment(\.openWindow) private var openWindow

    @State private var query = ""
    @State private var selection = 0
    @FocusState private var fieldFocused: Bool

    enum Result: Identifiable {
        case app(AppInfo)
        case website(URL)
        case webSearch(String)
        case youtubeSearch(String)

        var id: String {
            switch self {
            case .app(let app): return "app:\(app.path)"
            case .website(let url): return "url:\(url.absoluteString)"
            case .webSearch(let q): return "google:\(q)"
            case .youtubeSearch(let q): return "yt:\(q)"
            }
        }
    }

    private var results: [Result] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        var list: [Result] = []
        if let url = URLInput.website(from: q) { list.append(.website(url)) }
        list += catalog.search(q).map { .app($0) }
        list.append(.webSearch(q))
        list.append(.youtubeSearch(q))
        return list
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture { close() }

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Theme.accent)
                    TextField("Search apps, websites or the web", text: $query)
                        .textFieldStyle(.plain)
                        .font(.orbit(18))
                        .focused($fieldFocused)
                        .onSubmit { activateSelection() }
                        .onKeyPress(.downArrow) { move(1); return .handled }
                        .onKeyPress(.upArrow) { move(-1); return .handled }
                        .onExitCommand { close() }
                }
                .padding(.horizontal, 18)
                .frame(height: 58)

                if !results.isEmpty {
                    Divider().overlay(Theme.chipLine)
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                                ResultRow(result: result, selected: index == selection)
                                    .onTapGesture { activate(result) }
                                    .onHover { if $0 { selection = index } }
                            }
                        }
                        .padding(8)
                    }
                    .frame(maxHeight: 420)
                } else if query.isEmpty {
                    Text("Type an app name, a website like youtube.com, or anything to search.")
                        .font(.orbit(13))
                        .foregroundStyle(Theme.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 18)
                        .padding(.bottom, 16)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Theme.chip)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Theme.chipLine, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.5), radius: 30, y: 10)
            .padding(.horizontal, 20)
            .padding(.top, 90)
            .foregroundStyle(Theme.text)
        }
        .onAppear {
            DispatchQueue.main.async { fieldFocused = true }
        }
        .onChange(of: query) { _, _ in selection = 0 }
        .background(
            Button("Close", action: close)
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .accessibilityHidden(true)
        )
    }

    private func move(_ by: Int) {
        guard !results.isEmpty else { return }
        selection = (selection + by + results.count) % results.count
    }

    private func activateSelection() {
        let list = results
        guard !list.isEmpty else { return }
        activate(list[min(selection, list.count - 1)])
    }

    private func activate(_ result: Result) {
        switch result {
        case .app(let app):
            Launcher.openApp(at: app.url)
        case .website(let url):
            openWindow(id: "browser", value: BrowserRequest.fresh(url))
        case .webSearch(let q):
            openWindow(id: "browser", value: BrowserRequest.fresh(URLInput.googleSearch(q)))
        case .youtubeSearch(let q):
            openWindow(id: "browser", value: BrowserRequest.fresh(URLInput.youtubeSearch(q)))
        }
        close()
    }

    private func close() {
        withAnimation(.easeOut(duration: 0.15)) { isPresented = false }
    }
}

private struct ResultRow: View {
    let result: SearchOverlay.Result
    let selected: Bool

    var body: some View {
        HStack(spacing: 12) {
            icon
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.orbit(15, .medium))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.orbit(12))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if selected {
                Image(systemName: "return")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(selected ? Theme.chipHover : .clear)
        )
        .contentShape(Rectangle())
    }

    @ViewBuilder private var icon: some View {
        switch result {
        case .app(let app):
            Image(nsImage: Launcher.icon(forAppAt: app.url))
                .resizable()
                .aspectRatio(contentMode: .fit)
        case .website(let url):
            WebIcon(url: url)
        case .webSearch:
            Image(systemName: "globe")
                .font(.system(size: 18))
                .foregroundStyle(Theme.accent)
        case .youtubeSearch:
            Image(systemName: "play.rectangle.fill")
                .font(.system(size: 18))
                .foregroundStyle(Theme.accent)
        }
    }

    private var title: String {
        switch result {
        case .app(let app): return app.name
        case .website(let url): return url.host ?? url.absoluteString
        case .webSearch(let q): return "Search the web for “\(q)”"
        case .youtubeSearch(let q): return "Search YouTube for “\(q)”"
        }
    }

    private var subtitle: String {
        switch result {
        case .app: return "Application"
        case .website(let url): return url.absoluteString
        case .webSearch: return "Google · opens in Orbit browser"
        case .youtubeSearch: return "YouTube · opens in Orbit browser"
        }
    }
}

/// Turns what the user typed into a URL.
enum URLInput {
    /// Returns an HTTPS URL if the text looks like a website, otherwise nil.
    static func website(from text: String) -> URL? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !t.contains(" ") else { return nil }
        let lower = t.lowercased()
        if lower.hasPrefix("https://") { return URL(string: t) }
        if lower.hasPrefix("http://") {
            // Upgrade to HTTPS.
            return URL(string: "https://" + t.dropFirst("http://".count))
        }
        if lower.hasPrefix("localhost") { return nil }
        // Something like "youtube.com" or "news.bbc.co.uk/sport".
        let host = lower.split(separator: "/").first.map(String.init) ?? lower
        let parts = host.split(separator: ".")
        guard parts.count >= 2, let tld = parts.last, tld.count >= 2,
              tld.allSatisfy({ $0.isLetter }) else { return nil }
        return URL(string: "https://" + t)
    }

    static func googleSearch(_ q: String) -> URL {
        var comps = URLComponents(string: "https://www.google.com/search")!
        comps.queryItems = [URLQueryItem(name: "q", value: q)]
        return comps.url!
    }

    static func youtubeSearch(_ q: String) -> URL {
        var comps = URLComponents(string: "https://www.youtube.com/results")!
        comps.queryItems = [URLQueryItem(name: "search_query", value: q)]
        return comps.url!
    }

    /// Address-bar input: a website, or a Google search.
    static func resolve(_ text: String) -> URL? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        return website(from: t) ?? googleSearch(t)
    }
}
