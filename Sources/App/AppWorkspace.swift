enum AppWorkspace: String, CaseIterable, Identifiable {
    case chat = "Chat"
    case philharmonic = "Philharmonic"

    var id: String { rawValue }
    var isAvailable: Bool { self == .chat }
}
