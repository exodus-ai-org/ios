import Foundation
import Models
import NetworkingKit
import SwiftUI
import WebKit

extension EnvironmentValues {
    /// Where the artifact preview reads the computer's sandbox page from; nil outside a chat, where it falls back.
    @Entry var artifactSandbox: ArtifactSandboxSource?
}

/// The computer's artifact sandbox, read through the paired session: its page and assets
/// (`GET /api/v1/artifacts/sandbox/*`, exodus `routes/artifact-sandbox.ts`) and an artifact's code when its row came
/// without it (`GET /api/v1/artifacts/:chatId/:artifactId`). The token and the certificate pin stay in `APIClient`;
/// the page never sees either.
struct ArtifactSandboxSource: Sendable {
    typealias FetchFile = @Sendable (_ path: String, _ query: [URLQueryItem]) async throws -> FetchedFile
    typealias FetchCode = @Sendable (_ chatId: String, _ artifactId: String) async throws -> String

    let file: FetchFile
    let code: FetchCode

    init(file: @escaping FetchFile, code: @escaping FetchCode) {
        self.file = file
        self.code = code
    }

    init(apiClient: APIClient) {
        self.init(
            file: { path, query in try await apiClient.file(path, query: query) },
            code: { chatId, artifactId in
                let stored: StoredArtifact = try await apiClient.get(
                    "/api/v1/artifacts/\(ArtifactSandboxRoute.pathSegment(chatId))/\(ArtifactSandboxRoute.pathSegment(artifactId))")
                return stored.code
            })
    }

    private struct StoredArtifact: Decodable {
        let code: String
    }
}

// MARK: - The scheme

/// The page's own origin, `exodus-artifact://sandbox` — the desktop's iframe uses the same one. Every request to it
/// is one file of the computer's sandbox build: `exodus-artifact://sandbox/<path>` is
/// `/api/v1/artifacts/sandbox/<path>`, so the page's relative asset URLs resolve exactly as they do on the desktop.
enum ArtifactSandboxRoute {
    static let scheme = "exodus-artifact"
    static let host = "sandbox"
    /// The sandbox entry inside the renderer build (exodus `vite.renderer.config.mts`).
    static let page = "src/renderer/sub-apps/artifacts/index.html"
    static let apiPrefix = "/api/v1/artifacts/sandbox/"

    static var pageURL: URL { URL(string: "\(scheme)://\(host)/\(page)")! }
    static var pageAPIPath: String { apiPrefix + page }

    struct Request: Equatable {
        let path: String
        let query: [URLQueryItem]
    }

    /// The API request a sandbox URL stands for, or nil: another scheme or host, an empty path, a character a build
    /// file never has, or a `.` / `..` segment (decoded, so `%2e%2e%2f` is caught too).
    static func apiRequest(for url: URL) -> Request? {
        guard url.scheme?.lowercased() == scheme, url.host()?.lowercased() == host,
            let decoded = url.path(percentEncoded: true).removingPercentEncoding
        else { return nil }
        let path = String(decoded.drop { $0 == "/" })
        guard !path.isEmpty, path.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        let segments = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !segments.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else { return nil }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Request(path: apiPrefix + path, query: query)
    }

    /// A URL the web view may navigate to: the sandbox's own, and the blank documents a page makes for itself.
    static func allowsNavigation(to url: URL?) -> Bool {
        guard let url else { return false }
        if url.absoluteString == "about:blank" || url.absoluteString == "about:srcdoc" { return true }
        return url.scheme?.lowercased() == scheme && url.host()?.lowercased() == host
    }

    /// What the web view is told about a file: the computer's own `Content-Type`, so a module script is run as one.
    static func response(for url: URL, file: FetchedFile) -> HTTPURLResponse {
        let type = file.contentType.flatMap { $0.isEmpty ? nil : $0 } ?? "application/octet-stream"
        return HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": type, "Content-Length": String(file.data.count)])!
    }

    /// An id as one path segment: anything but the characters an id has is escaped, so it cannot add a segment.
    static func pathSegment(_ id: String) -> String {
        id.addingPercentEncoding(withAllowedCharacters: idAllowed) ?? id
    }

    private static let allowed = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~@+/")
    private static let idAllowed = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
}

/// Serves `exodus-artifact://sandbox/…` from the computer, one request per file, through `ArtifactSandboxSource`.
/// A failure of the page itself is reported (before WebKit hears of it), so the preview can say why it fell back.
@MainActor
final class ArtifactSchemeHandler: NSObject, WKURLSchemeHandler {
    private let fetch: ArtifactSandboxSource.FetchFile
    private let onPageFailure: (Error) -> Void
    private var running: [ObjectIdentifier: Task<Void, Never>] = [:]

    init(fetch: @escaping ArtifactSandboxSource.FetchFile, onPageFailure: @escaping (Error) -> Void) {
        self.fetch = fetch
        self.onPageFailure = onPageFailure
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url, let request = ArtifactSandboxRoute.apiRequest(for: url) else {
            urlSchemeTask.didFailWithError(URLError(.unsupportedURL))
            return
        }
        let key = ObjectIdentifier(urlSchemeTask)
        let isPage = request.path == ArtifactSandboxRoute.pageAPIPath
        let fetch = fetch
        running[key] = Task { [weak self] in
            let result: Result<FetchedFile, Error>
            do {
                result = .success(try await fetch(request.path, request.query))
            } catch {
                result = .failure(error)
            }
            // Stopped meanwhile: WebKit raises if a stopped task is answered.
            guard let self, self.running.removeValue(forKey: key) != nil else { return }
            switch result {
            case .success(let file):
                urlSchemeTask.didReceive(ArtifactSandboxRoute.response(for: url, file: file))
                urlSchemeTask.didReceive(file.data)
                urlSchemeTask.didFinish()
            case .failure(let error):
                if isPage { self.onPageFailure(error) }
                urlSchemeTask.didFailWithError(error)
            }
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        running.removeValue(forKey: ObjectIdentifier(urlSchemeTask))?.cancel()
    }
}

// MARK: - What the preview shows

/// Why the preview shows the calm "see it on your computer" state instead of the artifact.
enum ArtifactFallbackReason: Equatable {
    /// The computer has no sandbox route (404): an Exodus from before phones could preview.
    case outdatedComputer
    /// The computer did not answer, or the page did not come up in time.
    case unreachable
    /// The page came up, but the artifact's code did not render (its message, as the sandbox shows it).
    case renderFailed(String?)
}

enum ArtifactPreviewPhase: Equatable {
    case loading
    case rendered
    case fallback(ArtifactFallbackReason)
}

enum ArtifactPreviewEvent: Equatable {
    /// The sandbox page itself could not be fetched; `status` is the computer's HTTP status, when it answered.
    case pageFailed(status: Int?)
    /// The page is up and listening for the code.
    case sandboxReady
    case rendered
    case renderFailed(String?)
    case timedOut
    /// No source to load from (outside a chat), or no code to render.
    case unavailable
}

/// The preview's decisions, apart from the web view so they can be tested. The first fallback is final; an error
/// after a render (the artifact throwing on a tap) still falls back, a late timeout does not.
enum ArtifactPreviewRules {
    /// How long the page has, from the first request, to render the artifact or say it cannot.
    static let timeout: Duration = .seconds(20)

    static func next(_ phase: ArtifactPreviewPhase, on event: ArtifactPreviewEvent) -> ArtifactPreviewPhase {
        if case .fallback = phase { return phase }
        switch event {
        case .renderFailed(let message):
            return .fallback(.renderFailed(message))
        case .rendered:
            return .rendered
        case .sandboxReady:
            return phase
        case .pageFailed(let status):
            guard phase == .loading else { return phase }
            return .fallback(status == 404 ? .outdatedComputer : .unreachable)
        case .timedOut, .unavailable:
            return phase == .loading ? .fallback(.unreachable) : phase
        }
    }

    static func status(of error: Error) -> Int? {
        if let http = error as? HTTPError, http.statusCode > 0 { return http.statusCode }
        return nil
    }

    /// The sandbox's message as the fallback shows it: one paragraph, not a stack.
    static func displayMessage(_ message: String?) -> String? {
        guard let line = message?.split(whereSeparator: \.isNewline).first else { return nil }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.count > 300 ? String(trimmed.prefix(300)) + "…" : trimmed
    }
}

// MARK: - The web view

/// The desktop's own sandbox page in a `WKWebView`, served through `ArtifactSchemeHandler` and handed the code the way
/// the desktop's card hands it to its iframe: on `artifact-sandbox-ready`, a `theme` and a `render` message. The page
/// is its own top-level window here, so its `window.parent` is itself; a script in a world of our own hears what it
/// tells its parent and passes `ready` / `rendered` / `error` on. Nothing leaves but sandbox requests: a navigation
/// elsewhere is cancelled, a new window refused, and a content rule list blocks every other load.
struct ArtifactWebView: UIViewRepresentable {
    let source: ArtifactSandboxSource
    let code: String
    let artifactId: String
    let colorScheme: ColorScheme
    let onEvent: (ArtifactPreviewEvent) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onEvent: onEvent) }

    func makeUIView(context: Context) -> WKWebView {
        let coordinator = context.coordinator
        coordinator.code = code
        coordinator.artifactId = artifactId
        coordinator.theme = Self.theme(colorScheme)

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.setURLSchemeHandler(
            ArtifactSchemeHandler(fetch: source.file) { [weak coordinator] error in
                coordinator?.onEvent(.pageFailed(status: ArtifactPreviewRules.status(of: error)))
            },
            forURLScheme: ArtifactSandboxRoute.scheme)
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        let controller = configuration.userContentController
        controller.add(coordinator, contentWorld: Coordinator.world, name: Coordinator.handlerName)
        controller.addUserScript(
            WKUserScript(
                source: Coordinator.bridgeScript, injectionTime: .atDocumentStart, forMainFrameOnly: true,
                in: Coordinator.world))

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = coordinator
        webView.uiDelegate = coordinator
        // Opaque, with no colour of its own: what shows past the page's end (the room over the home indicator, an
        // overscroll) is then the page's own background, which follows its theme.
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic
        #if DEBUG
        webView.isInspectable = true
        #endif
        coordinator.webView = webView
        coordinator.load()
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onEvent = onEvent
        context.coordinator.setTheme(Self.theme(colorScheme))
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        webView.configuration.userContentController.removeAllScriptMessageHandlers()
        coordinator.loading?.cancel()
    }

    private static func theme(_ scheme: ColorScheme) -> String {
        if scheme == .dark { return "dark" }
        return "light"
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        static let world = WKContentWorld.world(name: "exodus-artifact-bridge")
        static let handlerName = "exodusArtifact"

        /// Listens for what the sandbox posts to its parent (here, itself) and passes on the three messages the
        /// preview acts on: their type, and an error's message as text.
        static let bridgeScript = """
            window.addEventListener('message', function (event) {
              if (event.source !== window) return;
              var data = event.data;
              if (!data || typeof data.type !== 'string') return;
              if (data.type !== 'artifact-sandbox-ready' && data.type !== 'artifact-sandbox-rendered'
                && data.type !== 'artifact-sandbox-error') return;
              window.webkit.messageHandlers.exodusArtifact.postMessage({
                type: data.type,
                message: typeof data.message === 'string' ? data.message.slice(0, 2000) : null
              });
            });
            """

        /// Every load but the sandbox's own (and inline data the page makes) is blocked: the page's CSP already
        /// allows no `connect-src` beyond itself, but it lets images come from anywhere. One rule per scheme: the
        /// rule-list compiler refuses `|` in a pattern.
        static let offlineRules = """
            [
              {"trigger": {"url-filter": ".*"}, "action": {"type": "block"}},
              {"trigger": {"url-filter": "^exodus-artifact://sandbox/"}, "action": {"type": "ignore-previous-rules"}},
              {"trigger": {"url-filter": "^data:"}, "action": {"type": "ignore-previous-rules"}},
              {"trigger": {"url-filter": "^blob:"}, "action": {"type": "ignore-previous-rules"}},
              {"trigger": {"url-filter": "^about:"}, "action": {"type": "ignore-previous-rules"}}
            ]
            """

        var onEvent: (ArtifactPreviewEvent) -> Void
        weak var webView: WKWebView?
        var code = ""
        var artifactId = ""
        var theme = "light"
        var loading: Task<Void, Never>?
        private var isReady = false

        init(onEvent: @escaping (ArtifactPreviewEvent) -> Void) {
            self.onEvent = onEvent
        }

        func load() {
            loading = Task { [weak self] in
                let rules = try? await WKContentRuleListStore.default().compileContentRuleList(
                    forIdentifier: "exodus-artifact-offline", encodedContentRuleList: Self.offlineRules)
                guard let self, !Task.isCancelled, let webView = self.webView else { return }
                // Fail closed: without the rules the page could load from anywhere.
                guard let rules else {
                    self.onEvent(.unavailable)
                    return
                }
                webView.configuration.userContentController.add(rules)
                webView.load(URLRequest(url: ArtifactSandboxRoute.pageURL))
            }
        }

        func setTheme(_ theme: String) {
            guard theme != self.theme else { return }
            self.theme = theme
            if isReady { post(render: false) }
        }

        /// The desktop card's messages (`sendToIframe`) and the page layout, posted from our world to the page's window.
        private func post(render: Bool) {
            var script = "window.postMessage({ type: 'theme', theme }, '*');"
            // A page of its own, not a card in a chat: the sandbox drops the outermost card's frame. A computer
            // without page layout ignores the message.
            if render {
                script += " window.postMessage({ type: 'layout', layout: 'page' }, '*');"
                script += " window.postMessage({ type: 'render', code, artifactId }, '*');"
            }
            webView?.callAsyncJavaScript(
                script, arguments: ["theme": theme, "code": code, "artifactId": artifactId], in: nil,
                in: Self.world, completionHandler: nil)
        }

        // MARK: WKScriptMessageHandler

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
            switch type {
            case "artifact-sandbox-ready":
                isReady = true
                onEvent(.sandboxReady)
                post(render: true)
            case "artifact-sandbox-rendered":
                onEvent(.rendered)
            case "artifact-sandbox-error":
                onEvent(.renderFailed(body["message"] as? String))
            default:
                break
            }
        }

        // MARK: WKNavigationDelegate

        func webView(
            _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            ArtifactSandboxRoute.allowsNavigation(to: navigationAction.request.url) ? .allow : .cancel
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            onEvent(.pageFailed(status: nil))
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            onEvent(.renderFailed(nil))
        }

        // MARK: WKUIDelegate

        func webView(
            _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            nil
        }
    }
}
