import SwiftUI
import WebKit
import AppKit
import UniformTypeIdentifiers

/// A real WebKit browser (the same engine as Safari): HTTPS, logins and cookies
/// that persist, YouTube playback, full-screen video, picture-in-picture,
/// pop-ups, file uploads and downloads.
@MainActor
final class BrowserModel: NSObject, ObservableObject {
    let webView: WKWebView

    @Published private(set) var currentURL: URL?
    @Published private(set) var title = ""
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var isLoading = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var isSecure = true
    @Published var lastDownload: String?

    private var observations: [NSKeyValueObservation] = []

    init(startURL: URL) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()            // cookies & logins persist
        configuration.preferences.isElementFullscreenEnabled = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()

        // Present as Safari so sites (YouTube included) serve their full desktop experience.
        webView.customUserAgent =
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        webView.navigationDelegate = self
        webView.uiDelegate = self

        observations = [
            webView.observe(\.url, options: [.initial, .new]) { [weak self] webView, _ in
                Task { @MainActor in self?.currentURL = webView.url }
            },
            webView.observe(\.title, options: [.initial, .new]) { [weak self] webView, _ in
                Task { @MainActor in self?.title = webView.title ?? "" }
            },
            webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] webView, _ in
                Task { @MainActor in self?.canGoBack = webView.canGoBack }
            },
            webView.observe(\.canGoForward, options: [.initial, .new]) { [weak self] webView, _ in
                Task { @MainActor in self?.canGoForward = webView.canGoForward }
            },
            webView.observe(\.isLoading, options: [.initial, .new]) { [weak self] webView, _ in
                Task { @MainActor in self?.isLoading = webView.isLoading }
            },
            webView.observe(\.estimatedProgress, options: [.initial, .new]) { [weak self] webView, _ in
                Task { @MainActor in self?.progress = webView.estimatedProgress }
            },
            webView.observe(\.hasOnlySecureContent, options: [.initial, .new]) { [weak self] webView, _ in
                Task { @MainActor in self?.isSecure = webView.hasOnlySecureContent }
            },
        ]

        webView.load(URLRequest(url: startURL))
    }

    func go(_ text: String) {
        guard let url = URLInput.resolve(text) else { return }
        webView.load(URLRequest(url: url))
    }

    func back() { webView.goBack() }
    func forward() { webView.goForward() }
    func reloadOrStop() { isLoading ? webView.stopLoading() : webView.reload() }
    func home() { webView.load(URLRequest(url: Defaults.homePage)) }

    func openInDefaultBrowser() {
        if let url = webView.url { NSWorkspace.shared.open(url) }
    }

    func zoom(_ delta: CGFloat) {
        webView.pageZoom = max(0.5, min(3, webView.pageZoom + delta))
    }

    func resetZoom() { webView.pageZoom = 1 }
}

// MARK: - Navigation

extension BrowserModel: WKNavigationDelegate {
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url, let scheme = url.scheme?.lowercased() else {
            decisionHandler(.allow); return
        }
        switch scheme {
        case "https", "about", "blob", "data", "javascript":
            if navigationAction.shouldPerformDownload {
                decisionHandler(.download)
            } else {
                decisionHandler(.allow)
            }
        case "http":
            // Keep everything on HTTPS.
            var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
            comps?.scheme = "https"
            decisionHandler(.cancel)
            if let secure = comps?.url { webView.load(URLRequest(url: secure)) }
        default:
            // mailto:, facetime:, maps:, zoommtg: … hand off to the right Mac app.
            decisionHandler(.cancel)
            NSWorkspace.shared.open(url)
        }
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if navigationResponse.canShowMIMEType {
            decisionHandler(.allow)
        } else {
            decisionHandler(.download)
        }
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }
}

// MARK: - Pop-ups, alerts, uploads

extension BrowserModel: WKUIDelegate {
    /// target="_blank" links and window.open(): open in this window.
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil || navigationAction.targetFrame?.isMainFrame == false {
            webView.load(navigationAction.request)
        }
        return nil
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = frame.request.url?.host ?? "This page says"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
        completionHandler()
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = frame.request.url?.host ?? "This page says"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        completionHandler(alert.runModal() == .alertFirstButtonReturn)
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        let alert = NSAlert()
        alert.messageText = frame.request.url?.host ?? "This page asks"
        alert.informativeText = prompt
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = defaultText ?? ""
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        completionHandler(alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil)
    }

    func webView(_ webView: WKWebView,
                 runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.canChooseFiles = true
        completionHandler(panel.runModal() == .OK ? panel.urls : nil)
    }

    /// Camera / microphone for video calls (Meet, Zoom web, etc.).
    func webView(_ webView: WKWebView,
                 requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo,
                 type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(.prompt)
    }
}

// MARK: - Downloads (saved to ~/Downloads)

extension BrowserModel: WKDownloadDelegate {
    func download(_ download: WKDownload,
                  decideDestinationUsing response: URLResponse,
                  suggestedFilename: String,
                  completionHandler: @escaping (URL?) -> Void) {
        let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        var destination = folder.appendingPathComponent(suggestedFilename)
        let base = destination.deletingPathExtension().lastPathComponent
        let ext = destination.pathExtension
        var counter = 2
        while FileManager.default.fileExists(atPath: destination.path) {
            let name = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
            destination = folder.appendingPathComponent(name)
            counter += 1
        }
        lastDownload = destination.lastPathComponent
        completionHandler(destination)
    }

    func downloadDidFinish(_ download: WKDownload) {
        if let name = lastDownload {
            let url = (FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first)?
                .appendingPathComponent(name)
            if let url { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        lastDownload = nil
        NSSound.beep()
    }
}

// MARK: - SwiftUI

struct WebViewHost: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

struct BrowserWindow: View {
    @StateObject private var model: BrowserModel
    @State private var address = ""
    @FocusState private var addressFocused: Bool

    init(startURL: URL) {
        _model = StateObject(wrappedValue: BrowserModel(startURL: startURL))
    }

    var body: some View {
        WebViewHost(webView: model.webView)
            .overlay(alignment: .top) {
                if model.isLoading {
                    ProgressView(value: model.progress)
                        .progressViewStyle(.linear)
                        .tint(Theme.accent)
                        .frame(height: 2)
                }
            }
            .navigationTitle(model.title.isEmpty ? "Orbit Browser" : model.title)
            .toolbar {
                ToolbarItemGroup(placement: .navigation) {
                    Button(action: model.back) { Image(systemName: "chevron.left") }
                        .disabled(!model.canGoBack)
                        .keyboardShortcut("[", modifiers: .command)
                        .help("Back")
                    Button(action: model.forward) { Image(systemName: "chevron.right") }
                        .disabled(!model.canGoForward)
                        .keyboardShortcut("]", modifiers: .command)
                        .help("Forward")
                }

                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        Image(systemName: model.isSecure ? "lock.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(model.isSecure ? Color.secondary : Color.orange)
                            .help(model.isSecure ? "Secure HTTPS connection" : "Some content on this page isn't secure")
                        TextField("Search or enter website", text: $address)
                            .textFieldStyle(.plain)
                            .focused($addressFocused)
                            .onSubmit {
                                model.go(address)
                                addressFocused = false
                            }
                    }
                    .padding(.horizontal, 10)
                    .frame(minWidth: 360, idealWidth: 560, maxWidth: 720, minHeight: 28)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
                }

                ToolbarItemGroup(placement: .primaryAction) {
                    Button(action: model.reloadOrStop) {
                        Image(systemName: model.isLoading ? "xmark" : "arrow.clockwise")
                    }
                    .keyboardShortcut("r", modifiers: .command)
                    .help(model.isLoading ? "Stop" : "Reload")

                    Button(action: model.openInDefaultBrowser) { Image(systemName: "safari") }
                        .help("Open in your default browser")

                    Button {
                        WindowRouter.shared.showMain()
                    } label: {
                        Image(systemName: "circle.circle")
                    }
                    .help("Back to Orbit")
                }
            }
            .background(
                // Keyboard shortcuts without visible buttons.
                Group {
                    Button("Focus address bar") { addressFocused = true }
                        .keyboardShortcut("l", modifiers: .command)
                    Button("Zoom in") { model.zoom(0.1) }
                        .keyboardShortcut("+", modifiers: .command)
                    Button("Zoom out") { model.zoom(-0.1) }
                        .keyboardShortcut("-", modifiers: .command)
                    Button("Actual size") { model.resetZoom() }
                        .keyboardShortcut("0", modifiers: [.command, .option])
                }
                .opacity(0)
                .accessibilityHidden(true)
            )
            .onAppear { address = model.currentURL?.absoluteString ?? "" }
            .onChange(of: model.currentURL) { _, newURL in
                if !addressFocused { address = newURL?.absoluteString ?? "" }
            }
            .onChange(of: addressFocused) { _, focused in
                if !focused { address = model.currentURL?.absoluteString ?? "" }
            }
            .frame(minWidth: 640, minHeight: 420)
    }
}
