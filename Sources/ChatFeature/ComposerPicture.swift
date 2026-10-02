import Foundation
import ImageIO
import Models
import UniformTypeIdentifiers

/// A picture waiting in the composer, ready for the wire: decoded, turned upright, downscaled on the phone (longest side
/// at most `maxPixelSize`) and re-encoded — JPEG, or PNG when it has an alpha channel — so a 12 MP photo is a few
/// hundred KB of base64, not 5 MB. Encoding from a thumbnail also leaves the photo's metadata (its location among it)
/// behind.
public struct ComposerPicture: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let mimeType: String
    /// `data:<mimeType>;base64,…`: the desktop stores an attachment's data URL in the image block's `data`.
    public let dataURL: String
    public let pixelWidth: Int
    public let pixelHeight: Int

    /// Hands over one picked picture's original (nil: it could not be), when its turn to be prepared comes.
    public typealias Loader = @Sendable () async -> Data?

    static let maxPixelSize = 2048
    static let jpegQuality = 0.85

    enum PrepareError: Error {
        case undecodable, unencodable
    }

    init(id: UUID = UUID(), mimeType: String, dataURL: String, pixelWidth: Int, pixelHeight: Int) {
        self.id = id
        self.mimeType = mimeType
        self.dataURL = dataURL
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }

    /// Anything ImageIO reads (HEIC from Photos, JPEG from the camera, PNG screenshots), prepared for sending.
    static func prepare(_ data: Data) throws -> ComposerPicture {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int, width > 0, height > 0
        else { throw PrepareError.undecodable }
        // The thumbnail applies the EXIF orientation, so the size asked for is the longest side either way.
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: min(max(width, height), maxPixelSize),
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
            throw PrepareError.undecodable
        }
        let keepsAlpha = (properties[kCGImagePropertyHasAlpha] as? Bool) == true
        let type = keepsAlpha ? UTType.png : UTType.jpeg
        let encoded = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(encoded, type.identifier as CFString, 1, nil) else {
            throw PrepareError.unencodable
        }
        let quality = keepsAlpha ? nil : [kCGImageDestinationLossyCompressionQuality: jpegQuality] as CFDictionary
        CGImageDestinationAddImage(destination, image, quality)
        guard CGImageDestinationFinalize(destination) else { throw PrepareError.unencodable }
        let mimeType = type.preferredMIMEType ?? "application/octet-stream"
        return ComposerPicture(
            mimeType: mimeType, dataURL: "data:\(mimeType);base64,\((encoded as Data).base64EncodedString())",
            pixelWidth: image.width, pixelHeight: image.height)
    }

    /// Off the main actor: a 48 MP photo takes a moment to decode.
    @concurrent
    static func prepared(_ data: Data) async throws -> ComposerPicture {
        try prepare(data)
    }
}

/// The pictures the next message carries, in pick order, at most `limit` (the menu's photo entries are off at the
/// limit, and the photo picker is told the room left).
public struct ComposerAttachments: Equatable, Sendable {
    public static let limit = 10

    public private(set) var pictures: [ComposerPicture] = []

    public init() {}

    public var isEmpty: Bool { pictures.isEmpty }
    public var isFull: Bool { pictures.count >= Self.limit }
    /// How many more fit: the photo picker's selection limit.
    public var room: Int { max(0, Self.limit - pictures.count) }

    /// Adds in order as many as fit; returns how many did not.
    @discardableResult
    public mutating func append(_ more: [ComposerPicture]) -> Int {
        let fitting = more.prefix(room)
        pictures += fitting
        return more.count - fitting.count
    }

    public mutating func remove(_ id: ComposerPicture.ID) {
        pictures.removeAll { $0.id == id }
    }

    public mutating func removeAll() {
        pictures.removeAll()
    }
}

/// A user message's `content` as the desktop's `send` builds it (`use-chat.ts`): text alone is a plain string; with
/// pictures it is an array — the text block when there is text, then one image block per picture, in order.
enum ComposerContent {
    static func content(text: String, pictures: [ComposerPicture]) -> JSONValue {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pictures.isEmpty else { return .string(text) }
        var blocks: [JSONValue] = []
        if !text.isEmpty {
            blocks.append(.object(["type": .string("text"), "text": .string(text)]))
        }
        for picture in pictures {
            blocks.append(
                .object([
                    "type": .string("image"), "mimeType": .string(picture.mimeType), "data": .string(picture.dataURL),
                ]))
        }
        return .array(blocks)
    }
}
