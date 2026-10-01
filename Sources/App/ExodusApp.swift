import ChatFeature
import MarkdownKit
import NetworkingKit
import SettingsFeature
import SwiftUI

@main
struct ExodusApp: App {
    private let connection: ServerConnection
    private let serverConfig: ServerConfigStore
    private let apiClient: APIClient
    private let streamManager: ChatStreamManager
    private let reporter: LogReporter
    @State private var toneModel = ColorToneModel()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // One connection, and one URLSession — its own, which trusts only the
        // certificate this device was paired with — shared by everything that
        // talks to the computer. Unpaired (the Simulator), both are inert and
        // requests go to the plain manual address.
        let connection = ServerConnection(store: KeychainCredentialStore())
        connection.onComputerChange { Task { @MainActor in ChatCaches.clearAll() } }
        let config = ServerConfigStore()
        config.connection = connection
        self.connection = connection
        serverConfig = config
        // Reports wait while Face ID still holds the token (the UnlockGate's own condition), then go to the computer.
        let reporter = LogReporter(
            session: connection.session, serverConfig: config,
            isReady: { [connection] in !connection.isPaired || connection.isUnlocked })
        self.reporter = reporter
        apiClient = APIClient(session: connection.session, serverConfig: config, reporter: reporter)
        streamManager = ChatStreamManager(sseClient: SSEClient(session: connection.session, reporter: reporter))
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-EmitTestLogReport") {
            reporter.report(.warn, scope: "debug", message: "Test report from the -EmitTestLogReport launch argument")
        }
        SettingsDebugHooks.cardPrototypes = { AnyView(CardPrototypesView()) }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            Group {
                #if DEBUG
                // The galleries of chat content are painted as a chat is.
                if MarkdownGalleryLaunch.isEnabled {
                    MarkdownGalleryView().chatTone(toneModel)
                } else if MessageGalleryLaunch.isEnabled {
                    MessageGalleryView().chatTone(toneModel)
                } else if SettingsGalleryLaunch.isEnabled {
                    SettingsGalleryView()
                } else if OdyGalleryLaunch.isEnabled {
                    OdyGalleryView()
                } else if HealthGalleryLaunch.isEnabled {
                    HealthGalleryView()
                } else if CardPrototypesLaunch.isEnabled {
                    CardPrototypesView(embedded: false).chatTone(toneModel)
                } else {
                    shell
                }
                #else
                shell
                #endif
            }
            // The tone is the chat's: `ChatDetailView` paints itself in it. Everything around a chat — the
            // drawer, Settings — keeps the system's own look, so the tone reads as the conversation's colour
            // and not as the app's.
            .environment(\.accentGlyph, toneModel.tone.glyphColor)
            .environment(\.colorTone, toneModel.tone)
            .environment(\.toneAccent, toneModel.tone.color)
            .environment(\.toneInk, toneModel.tone.inkColor)
            .environment(toneModel)
            .environment(\.renderDiagnostics, Self.diagnostics(reporter))
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { reporter.flushSoon() }
            }
        }
    }

    private static func diagnostics(_ reporter: LogReporter) -> RenderDiagnostics {
        RenderDiagnostics { scope, message, attributes in
            reporter.report(.warn, scope: scope, message: message, attributes: attributes.mapValues { .string($0) })
        }
    }

    private var shell: some View {
        UnlockGate(connection: connection) {
            AppShell(apiClient: apiClient, streamManager: streamManager, serverConfig: serverConfig)
        }
        .launchSplash()
    }
}

#if DEBUG
extension View {
    /// A gallery of chat content, painted as a chat is (`ChatDetailView`): the tone's ink as the tint, and links
    /// underlined where that ink is the text's own colour.
    fileprivate func chatTone(_ model: ColorToneModel) -> some View {
        colorTone(model.tone).environment(\.markdownUnderlinesLinks, model.tone == .neutral)
    }
}
#endif
