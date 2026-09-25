import Foundation

/// The top-level areas of the app. Philharmonic is listed but not available yet.
enum AppWorkspace: CaseIterable, Identifiable {
    case chat
    case philharmonic

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .chat:
            LocalizedStringResource(
                "ios:app.workspace.chat", comment: "Name of the chat workspace in the sidebar.")
        case .philharmonic:
            LocalizedStringResource("ios:app.workspace.philharmonic")
        }
    }

    var systemImage: String {
        switch self {
        case .chat: "bubble.left.and.bubble.right"
        case .philharmonic: "music.note.list"
        }
    }

    var isAvailable: Bool { self == .chat }
}
