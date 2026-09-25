import MarkdownKit
import Models
import NetworkingKit
import SwiftUI
import UIKit

extension EnvironmentValues {
    @Entry var placePhotoLoader: PlacePhotoLoader?
}

/// Places photos through the computer's proxy (`GET /api/v1/maps/photo?name=&maxWidth=`, exodus `routes/maps.ts`): the
/// computer adds the user's Google key, so the key never reaches the phone. Fetched through the paired session (device
/// token, pinned TLS), downsampled off the main actor, kept in memory only.
final class PlacePhotoLoader: Sendable {
    typealias Fetch = @Sendable (_ name: String, _ maxWidth: Int) async throws -> Data

    /// What the phone asks for: the desktop's detail-card size (`buildPlacePhotoUrl(name, 800)`).
    static let requestWidth = 800

    private let fetch: Fetch
    private let cache: GeneratedImageCache

    init(fetch: @escaping Fetch, cache: GeneratedImageCache = GeneratedImageCache(totalCostLimit: 48 * 1024 * 1024)) {
        self.fetch = fetch
        self.cache = cache
    }

    convenience init(apiClient: APIClient) {
        self.init { name, maxWidth in
            try await apiClient.data(
                "/api/v1/maps/photo",
                query: [URLQueryItem(name: "name", value: name), URLQueryItem(name: "maxWidth", value: String(maxWidth))])
        }
    }

    /// The route's own check (`isPlacePhotoName`): a name that is not a Places photo resource never leaves the phone.
    static func isPhotoName(_ name: String) -> Bool {
        name.wholeMatch(of: /places\/[\w-]{1,256}\/photos\/[\w-]{1,2048}/.asciiOnlyWordCharacters()) != nil
    }

    func cached(_ name: String, pixelWidth: Int) -> UIImage? {
        cache.image(for: Self.cacheKey(name, pixelWidth))
    }

    /// The photo, at most `pixelWidth` wide. Throws for a bad name, a failed fetch or bytes that are no image.
    func load(_ name: String, pixelWidth: Int) async throws -> UIImage {
        guard Self.isPhotoName(name) else { throw PlacePhotoError.badName }
        let key = Self.cacheKey(name, pixelWidth)
        if let hit = cache.image(for: key) { return hit }
        let data = try await fetch(name, Self.requestWidth)
        try Task.checkCancellation()
        let image = try await Self.decode(data, pixelWidth: pixelWidth)
        cache.insert(image, for: key)
        return image
    }

    @concurrent
    private static func decode(_ data: Data, pixelWidth: Int) async throws -> UIImage {
        let loaded = try MarkdownImageLoader.downsample(data, maxPixelWidth: max(1, pixelWidth))
        return UIImage(cgImage: loaded.cgImage)
    }

    private static func cacheKey(_ name: String, _ width: Int) -> GeneratedImageSource {
        .media(path: "maps-photo/\(width)/\(name)")
    }
}

enum PlacePhotoError: Error {
    case badName
}

/// The place detail's hero: its photos, paged when there are several, over the tinted placeholder that stays when a
/// photo cannot be loaded.
struct PlacePhotoHero: View {
    let names: [String]
    let ink: MapDayInk
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var photos: [String] { names.filter(PlacePhotoLoader.isPhotoName).prefix(10).map { $0 } }

    var body: some View {
        Group {
            if photos.count > 1 {
                TabView {
                    ForEach(photos, id: \.self) { name in
                        PlacePhotoView(name: name, ink: ink)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
            } else if let name = photos.first {
                PlacePhotoView(name: name, ink: ink)
            } else {
                PlacePhotoPlaceholder(ink: ink, hasPhotos: false)
            }
        }
        .frame(height: height)
        .clipShape(.rect(cornerRadius: 14))
        .accessibilityHidden(true)
    }

    private var height: CGFloat {
        if photos.isEmpty { return dynamicTypeSize.isAccessibilitySize ? 64 : 88 }
        return dynamicTypeSize.isAccessibilitySize ? 120 : 170
    }
}

private struct PlacePhotoView: View {
    let name: String
    let ink: MapDayInk
    @Environment(\.placePhotoLoader) private var loader
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    var body: some View {
        GeometryReader { proxy in
            let pixelWidth = Int((proxy.size.width * displayScale).rounded(.up))
            ZStack {
                PlacePhotoPlaceholder(ink: ink, hasPhotos: true)
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                        .transition(.opacity)
                }
            }
            .task(id: "\(name)@\(pixelWidth)") {
                guard let loader, pixelWidth > 0 else { return }
                if let hit = loader.cached(name, pixelWidth: pixelWidth) {
                    image = hit
                    return
                }
                guard let loaded = try? await loader.load(name, pixelWidth: pixelWidth) else { return }
                withAnimation(.easeOut(duration: 0.2)) { image = loaded }
            }
        }
    }
}

private struct PlacePhotoPlaceholder: View {
    let ink: MapDayInk
    let hasPhotos: Bool

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [ink.fill.opacity(0.28), ink.fill.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: hasPhotos ? "photo" : "mappin.and.ellipse")  // l10n:ignore: SF Symbol names
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(ink.fill)
        }
    }
}
