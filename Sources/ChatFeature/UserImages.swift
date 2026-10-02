import Models
import SwiftUI
import UIKit

/// The pictures a question was asked with: the image blocks of a user message, in order, as the desktop stores them
/// (a data URL in `data`).
enum UserImages {
    static func dataURLs(of message: ChatMessage) -> [String] {
        message.contentBlocks.compactMap { block in
            if case .image(_, let dataURL) = block { dataURL } else { nil }
        }
    }

    /// Wide enough for the full-screen viewer on any phone; the strip draws the same image as a small square.
    static let maxPixelWidth = 2048

    /// Decoded pictures, by message and position: a data URL is decoded once, not on every scroll past it.
    @MainActor static let cache = NSCache<NSString, UIImage>()

    static func key(_ messageId: String, _ index: Int) -> NSString { "\(messageId)#\(index)" as NSString }
}

/// The pictures above a question's bubble, right-aligned as the bubble is: rounded squares whatever their shape, as
/// the desktop's composer and transcript show them, so several sit in an even row. Past `shown` the last square reads
/// "+N"; a tap on any opens them all full screen, where a swipe goes from one to the next.
struct UserImageStrip: View {
    let messageId: String
    let dataURLs: [String]

    /// The desktop's `USER_IMAGES_SHOWN`.
    static let shown = 4

    @State private var images: [Int: UIImage] = [:]
    @State private var viewer: ImageViewerPage?
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 80

    /// The squares drawn: every picture while they fit, else the first three and a fourth that reads "+N".
    static func layout(count: Int) -> (tiles: Int, more: Int) {
        count > shown ? (shown, count - (shown - 1)) : (count, 0)
    }

    var body: some View {
        let layout = Self.layout(count: dataURLs.count)
        HStack(spacing: 8) {
            ForEach(0..<layout.tiles, id: \.self) { index in
                tile(index, more: index == layout.tiles - 1 ? layout.more : 0)
            }
        }
        .task(id: messageId) { await decode() }
        .fullScreenCover(item: $viewer) { page in
            ImageViewer(
                pages: dataURLs.indices.compactMap { index in
                    images[index].map { ImageViewerPage.Content(id: index, image: $0, caption: nil) }
                },
                start: page.id)
        }
    }

    static func moreText(_ count: Int) -> LocalizedStringResource {
        LocalizedStringResource(
            "ios:chat.images.more", defaultValue: "Show \(count) more",
            comment: "A question's pictures: the last square past four, which opens the rest. %lld is how many more there are.")
    }

    private func tile(_ index: Int, more: Int) -> some View {
        Button {
            if images[index] != nil { viewer = ImageViewerPage(id: index) }
        } label: {
            ZStack {
                if let image = images[index] {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Rectangle().fill(.fill.tertiary)
                }
                if more > 0 {
                    Rectangle().fill(.black.opacity(0.5))
                    Text(verbatim: "+\(more)")
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
            }
            .frame(width: side, height: side)
            .clipShape(.rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color(.separator), lineWidth: 0.5))
            .contentShape(.rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(more > 0 ? Text(Self.moreText(more)) : Text("ios:chat.markdown.image"))
        .accessibilityValue(dataURLs.count > 1 && more == 0 ? Text(verbatim: "\(index + 1) / \(dataURLs.count)") : Text(verbatim: ""))
    }

    private func decode() async {
        for (index, dataURL) in dataURLs.enumerated() {
            let key = UserImages.key(messageId, index)
            if let cached = UserImages.cache.object(forKey: key) {
                images[index] = cached
                continue
            }
            guard
                let image = await ComputerUseFrameStore.decodeScreenshot(dataURL, maxPixelWidth: UserImages.maxPixelWidth)
            else { continue }
            UserImages.cache.setObject(image, forKey: key)
            images[index] = image
        }
    }
}
