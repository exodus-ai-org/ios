import Foundation

/// `widget.json` in a directory: the App Group container in the app and the extension, a scratch one in tests.
public struct SnapshotStore: Sendable {
    let directory: URL

    public init(directory: URL) { self.directory = directory }

    /// The shared container; nil when the App Group entitlement is missing (a misconfigured build).
    public static func appGroup() -> SnapshotStore? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetGroup.identifier)
            .map(SnapshotStore.init(directory:))
    }

    public var fileURL: URL { directory.appending(path: "widget.json") }

    /// Missing, unreadable, half-written or from a newer app: the empty snapshot.
    public func load() -> WidgetSnapshot {
        guard let data = try? Data(contentsOf: fileURL),
            let snapshot = try? Self.decoder.decode(WidgetSnapshot.self, from: data),
            snapshot.version <= WidgetSnapshot.currentVersion
        else { return .empty }
        return snapshot
    }

    /// Readable once the phone has been unlocked after a restart: the Lock Screen draws it too.
    public func save(_ snapshot: WidgetSnapshot) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.encoder.encode(snapshot)
            .write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()
}
