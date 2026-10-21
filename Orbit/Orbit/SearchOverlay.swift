import SwiftUI

/// The centre-button screen: every Orbit app at a glance, plus search across
/// apps, websites, the web and YouTube — all inside Orbit.
struct SearchOverlay: View {
    @Binding var isPresented: Bool

    @EnvironmentObject private var youtube: YouTubeModel
    @Environment(\.openWindow) private var openWindow

    @State private var query = ""
    @State private var selection = 0
    @FocusState private var fieldFocused: Bool

    enum Result: Identifiable {
        case app(OrbitAppKind)
        case website(URL)
        case webSearch(String)
        case youtubeSearch(String)

        var id: String {
            switch self {
            case .app(let kind): return "app:\(kind.rawValue)"
            case .website(let url): return "url:\(url.absoluteString)"
            case .webSearch(let q): return "web:\(q)"
            case .youtubeSearch(let q): return "yt:\(q)"
            }
        }
    }

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var results: [Result] {
        let q = trimmed
        guard !q.isEmpty else { return [] }
        var list: [Result] = []
        list += OrbitAppKind.allCases.filter { $0.matches(q) }.map { .app($0) }
        if let url = URLInput.website(from: q) { list.append(.website(url)) }
        list.append(.youtubeSearch(q))
        list.append(.webSearch(q))
        return list
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.65)
                .ignoresSafeArea()
                .onTapGesture { close() }

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Theme.accent)
                    TextField("Search apps, websites or YouTube", text: $query)
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

                Divider().overlay(Theme.chipLine)

                if trimmed.isEmpty {
                    allApps
                } else {
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
                }
            }
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.chip))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.chipLine, lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 30, y: 10)
            .padding(.horizontal, 20)
            .padding(.top, 80)
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

    /// Every Orbit app, like a phone's app library.
    private var allApps: some View {
        VStack(alignment: .leading, spacing: 12) {
            CapsLabel(text: "All apps")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 14) {
                ForEach(OrbitAppKind.allCases) { kind in
                    Button {
                        AppOpener.open(kind, openWindow)
                        close()
                    } label: {
                        VStack(spacing: 6) {
                            OrbitAppGlyph(kind: kind)
                                .frame(width: 26, height: 26)
                                .frame(width: 54, height: 54)
                                .background(Circle().fill(Theme.background))
                                .overlay(Circle().stroke(Theme.chipLine, lineWidth: 1))
                            Text(kind.title)
                                .font(.orbit(11))
                                .foregroundStyle(Theme.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(kind.subtitle)
                }
            }
        }
        .padding(18)
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
        case .app(let kind):
            AppOpener.open(kind, openWindow)
        case .website(let url):
            openWindow(id: "browser", value: BrowserRequest.fresh(url))
        case .webSearch(let q):
            openWindow(id: "browser", value: BrowserRequest.fresh(URLInput.googleSearch(q)))
        case .youtubeSearch(let q):
            youtube.search(q)
            AppOpener.open(.youtube, openWindow)
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
                .frame(width: 22, height: 22)
                .frame(width: 30, height: 30)
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
        case .app(let kind):
            OrbitAppGlyph(kind: kind)
        case .website(let url):
            WebIcon(url: url)
        case .webSearch:
            OrbitAppGlyph(kind: .browser)
        case .youtubeSearch:
            OrbitAppGlyph(kind: .youtube)
        }
    }

    private var title: String {
        switch result {
        case .app(let kind): return kind.title
        case .website(let url): return url.host ?? url.absoluteString
        case .webSearch(let q): return "Search the web for “\(q)”"
        case .youtubeSearch(let q): return "Search YouTube for “\(q)”"
        }
    }

    private var subtitle: String {
        switch result {
        case .app(let kind): return kind.subtitle
        case .website(let url): return "Open in Orbit Browser · \(url.absoluteString)"
        case .webSearch: return "Orbit Browser"
        case .youtubeSearch: return "Orbit YouTube"
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
            return URL(string: "https://" + t.dropFirst("http://".count))
        }
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

    /// Address-bar input: a website, or a Google search.
    static func resolve(_ text: String) -> URL? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        return website(from: t) ?? googleSearch(t)
    }
}
