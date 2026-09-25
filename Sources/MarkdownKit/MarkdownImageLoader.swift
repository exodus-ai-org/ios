import CoreGraphics
import Foundation
import ImageIO
import Synchronization

public struct MarkdownLoadedImage: Sendable {
    public let cgImage: CGImage
    /// The source's own width in pixels, shown as points like a browser shows CSS pixels.
    public let sourcePixelWidth: Int
}

enum MarkdownImageLoadError: Error, Equatable {
    case tooLarge
    case notAnImage
    case timedOut
    case badStatus(Int)
    case undecodable
    case failed
}

/// Downloads an image with hard limits (a 15 s budget, 8 MB, `image/*` only) and decodes it downsampled to
/// the width it is shown at, so a 12-megapixel photo is never decoded at full size.
public struct MarkdownImageLoader: Sendable {
    static let timeout: TimeInterval = 15
    public static let byteCap = 8 * 1024 * 1024
    static let maximumPixelDimension = 4096
    public static let shared = MarkdownImageLoader()

    private let session: URLSession
    private let byteCap: Int

    public init(protocolClasses: [AnyClass]? = nil, byteCap: Int = Self.byteCap) {
        session = URLSession(configuration: Self.sessionConfiguration(protocolClasses: protocolClasses))
        self.byteCap = byteCap
    }

    /// A session that remembers nothing and sends nothing of the user's: no cookies, no credentials, no cache, and
    /// never the paired session (a third-party host must not see the device token).
    public static func sessionConfiguration(protocolClasses: [AnyClass]? = nil) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = Self.timeout
        configuration.timeoutIntervalForResource = Self.timeout
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        if let protocolClasses { configuration.protocolClasses = protocolClasses }
        return configuration
    }

    func load(_ url: URL, maxPixelWidth: Int) async throws -> MarkdownLoadedImage {
        let data = try await download(url)
        try Task.checkCancellation()
        return try Self.downsample(data, maxPixelWidth: maxPixelWidth)
    }

    /// The same limits for any remote image the chat shows (a legacy generated-image link too).
    public func download(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = Self.timeout
        let task = session.dataTask(with: request)
        let receiver = CappedReceiver(cap: byteCap)
        task.delegate = receiver
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                receiver.start(continuation)
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
    }

    public static func downsample(_ data: Data, maxPixelWidth: Int) throws -> MarkdownLoadedImage {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            var width = properties[kCGImagePropertyPixelWidth] as? Int,
            var height = properties[kCGImagePropertyPixelHeight] as? Int, width > 0, height > 0
        else { throw MarkdownImageLoadError.undecodable }
        if let orientation = properties[kCGImagePropertyOrientation] as? Int, (5...8).contains(orientation) {
            swap(&width, &height)
        }
        let targetWidth = max(1, min(width, maxPixelWidth))
        let longestSide = Double(max(width, height)) * Double(targetWidth) / Double(width)
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: min(Int(longestSide.rounded(.up)), maximumPixelDimension),
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
            throw MarkdownImageLoadError.undecodable
        }
        return MarkdownLoadedImage(cgImage: image, sourcePixelWidth: width)
    }

    static func map(_ error: any Error) -> any Error {
        if error is MarkdownImageLoadError || error is CancellationError { return error }
        guard let urlError = error as? URLError else { return MarkdownImageLoadError.failed }
        switch urlError.code {
        case .timedOut: return MarkdownImageLoadError.timedOut
        case .cancelled: return CancellationError()
        default: return MarkdownImageLoadError.failed
        }
    }
}

/// Collects a response body and gives up as soon as it breaks a limit, before the rest is downloaded.
private final class CappedReceiver: NSObject, URLSessionDataDelegate, Sendable {
    private struct State {
        var data = Data()
        var failure: MarkdownImageLoadError?
        var continuation: CheckedContinuation<Data, any Error>?
    }

    private let cap: Int
    private let state = Mutex(State())

    init(cap: Int) {
        self.cap = cap
    }

    func start(_ continuation: CheckedContinuation<Data, any Error>) {
        state.withLock { $0.continuation = continuation }
    }

    func urlSession(
        _ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
    ) {
        let failure: MarkdownImageLoadError?
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            failure = .badStatus(http.statusCode)
        } else if response.mimeType?.lowercased().hasPrefix("image/") != true {
            failure = .notAnImage
        } else if response.expectedContentLength > Int64(cap) {
            failure = .tooLarge
        } else {
            failure = nil
        }
        state.withLock { $0.failure = failure }
        completionHandler(failure == nil ? .allow : .cancel)
    }

    /// An https image may not continue over plain http.
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        let downgrades = task.originalRequest?.url?.scheme?.lowercased() == "https" && request.url?.scheme?.lowercased() != "https"
        if downgrades { state.withLock { $0.failure = .failed } }
        completionHandler(downgrades ? nil : request)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let overCap = state.withLock { state in
            state.data.append(data)
            if state.data.count > cap { state.failure = .tooLarge }
            return state.failure != nil
        }
        if overCap { dataTask.cancel() }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        let (continuation, result): (CheckedContinuation<Data, any Error>?, Result<Data, any Error>) = state.withLock {
            state in
            defer { state.continuation = nil }
            if let failure = state.failure { return (state.continuation, .failure(failure)) }
            if let error { return (state.continuation, .failure(MarkdownImageLoader.map(error))) }
            return (state.continuation, .success(state.data))
        }
        continuation?.resume(with: result)
    }
}
