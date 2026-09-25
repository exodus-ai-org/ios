import Foundation
import Models
import NetworkingKit
import Observation
import SwiftUI

/// `GET /api/v1/settings/secrets-status`, read when Settings opens and when a page that edits keys comes back. A
/// computer without the route (older than masking) answers 404: no notice, nothing reported to the user.
@MainActor
@Observable
public final class SecretsStatusModel {
    public private(set) var status: SecretsStatus?
    private let apiClient: APIClient

    public init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    public func load() async {
        do {
            status = try await apiClient.get("/api/v1/settings/secrets-status")
        } catch {
            if (error as? HTTPError)?.statusCode == 404 { status = nil }
        }
    }
}

/// One secret the notice names: the desktop's words for it, and the page that edits it on the phone, when there is one.
struct SecretNoticeItem: Identifiable, Equatable {
    let id: String
    let title: String
    let page: SettingsPage?

    /// The desktop's `secretName` (`secrets-notices.tsx`) and, for a provider key, the Providers page.
    static func items(for names: [String]) -> [SecretNoticeItem] {
        names.map { name in
            switch SecretReentryName(name) {
            case .setting(let secret):
                SecretNoticeItem(id: name, title: title(of: secret), page: secret.provider == nil ? nil : .providers)
            case .mcp(let server, let field):
                SecretNoticeItem(
                    id: name,
                    title: String(
                        localized: "settings:secrets.fields.mcp", defaultValue: "MCP server “\(server)”: \(field)",
                        comment: "A secret of an MCP server to enter again. The first %@ is the server's name, the second the field."),
                    page: nil)
            case .unknown(let raw):
                SecretNoticeItem(id: name, title: raw, page: nil)
            }
        }
    }

    private static func title(of secret: SecretReentryName.SettingSecret) -> String {
        switch secret {
        case .openaiApiKey:
            String(localized: "settings:secrets.fields.openaiApiKey", defaultValue: "OpenAI API key", comment: "A key to enter again.")
        case .azureOpenaiApiKey:
            String(localized: "settings:secrets.fields.azureOpenaiApiKey", defaultValue: "Azure OpenAI API key", comment: "A key to enter again.")
        case .anthropicApiKey:
            String(localized: "settings:secrets.fields.anthropicApiKey", defaultValue: "Anthropic API key", comment: "A key to enter again.")
        case .googleGeminiApiKey:
            String(localized: "settings:secrets.fields.googleGeminiApiKey", defaultValue: "Gemini API key", comment: "A key to enter again.")
        case .xAiApiKey:
            String(localized: "settings:secrets.fields.xAiApiKey", defaultValue: "xAI API key", comment: "A key to enter again.")
        case .googleApiKey:
            String(localized: "settings:secrets.fields.googleApiKey", defaultValue: "Google Maps API key", comment: "A key to enter again.")
        case .braveApiKey:
            String(localized: "settings:secrets.fields.braveApiKey", defaultValue: "Brave Search API key", comment: "A key to enter again.")
        case .elasticsearchPassword:
            String(localized: "settings:secrets.fields.elasticsearchPassword", defaultValue: "Elasticsearch password", comment: "A key to enter again.")
        case .knowledgeBaseApiKey:
            String(localized: "settings:secrets.fields.knowledgeBaseApiKey", defaultValue: "LightRAG API key", comment: "A key to enter again.")
        case .s3AccessKeyId:
            String(localized: "settings:secrets.fields.s3AccessKeyId", defaultValue: "Amazon S3 access key ID", comment: "A key to enter again.")
        case .s3SecretAccessKey:
            String(localized: "settings:secrets.fields.s3SecretAccessKey", defaultValue: "Amazon S3 secret access key", comment: "A key to enter again.")
        case .legacyMcpServers:
            String(localized: "settings:secrets.fields.legacyMcpServers", defaultValue: "Legacy MCP configuration", comment: "A key to enter again.")
        }
    }
}

/// What tapping a notice line does: pushes the page that edits the secret, and nothing more. It never selects a
/// provider on `settings` (the Providers page's model): that page shows the computer's active provider, and a Save
/// after the jump must not switch the desktop's chats to another one. The line names the provider instead.
enum SecretNoticeJump {
    @MainActor
    static func open(_ item: SecretNoticeItem, path: inout [SettingsPage], settings: SettingsViewModel) {
        guard let page = item.page else { return }
        path.append(page)
    }
}

/// The top of Settings, like the desktop's Settings → General: keys stored without encryption, and each key to enter
/// again, by name — a provider key opens the Providers page; the rest are edited on the computer.
struct SecretsNoticeSections: View {
    let status: SecretsStatus?
    let open: (SecretNoticeItem) -> Void

    var body: some View {
        if let status {
            if status.encryption == .unavailable {
                Section {
                    Label {
                        Text("ios:settings.secrets.encryptionUnavailable")
                    } icon: {
                        Image(systemName: "exclamationmark.shield")
                            .foregroundStyle(.orange)
                    }
                    .font(.subheadline)
                }
            }
            if !status.needsReentry.isEmpty {
                let items = SecretNoticeItem.items(for: status.needsReentry)
                Section {
                    Label {
                        Text("settings:secrets.notice.needsReentry")
                    } icon: {
                        Image(systemName: "key")
                            .foregroundStyle(.orange)
                    }
                    .font(.subheadline)
                    ForEach(items) { item in
                        if item.page != nil {
                            Button {
                                open(item)
                            } label: {
                                HStack {
                                    Text(verbatim: item.title).foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                        .accessibilityHidden(true)
                                }
                            }
                        } else {
                            Text(verbatim: item.title)
                        }
                    }
                } footer: {
                    if items.contains(where: { $0.page == nil }) {
                        Text("ios:settings.secrets.onComputerOnly")
                    }
                }
            }
        }
    }
}
