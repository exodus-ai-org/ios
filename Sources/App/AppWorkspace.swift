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
                "Chat", comment: "Name of the chat workspace, and the title of an open conversation that has no name yet.")
        case .philharmonic:
            LocalizedStringResource("Philharmonic")
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
