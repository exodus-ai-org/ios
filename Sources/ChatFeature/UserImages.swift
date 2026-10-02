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

    /// Wide enough for the full-screen viewer on any phone; the strip draws the same image smaller.
    static let maxPixelWidth = 2048

    /// Decoded pictures, by message and position: a data URL is decoded once, not on every scroll past it.
    @MainActor static let cache = NSCache<NSString, UIImage>()

    static func key(_ messageId: String, _ index: Int) -> NSString { "\(messageId)#\(index)" as NSString }
}

/// The pictures above a question's bubble, right-aligned as the bubble is: one shown at a moderate size, several as
/// a row of squares. A tap opens them full screen, where a swipe goes from one to the next.
struct UserImageStrip: View {
    let messageId: String
    let dataURLs: [String]

    @State private var images: [Int: UIImage] = [:]
    @State private var viewer: ImageViewerPage?
    @ScaledMetric(relativeTo: .body) private var single: CGFloat = 170
    @ScaledMetric(relativeTo: .body) private var square: CGFloat = 96

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(dataURLs.indices, id: \.self) { index in
                    tile(index)
                }
            }
        }
        // Right-aligned like the bubble: a row narrower than the screen hugs the trailing edge.
        .defaultScrollAnchor(.trailing)
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: dataURLs.count == 1 ? single : square)
        .task(id: messageId) { await decode() }
        .fullScreenCover(item: $viewer) { page in
            ImageViewer(
                pages: dataURLs.indices.compactMap { index in
                    images[index].map { ImageViewerPage.Content(id: index, image: $0, caption: nil) }
                },
                start: page.id)
        }
    }

    @ViewBuilder
    private func tile(_ index: Int) -> some View {
        let side = dataURLs.count == 1 ? single : square
        Button {
            if images[index] != nil { viewer = ImageViewerPage(id: index) }
        } label: {
            Group {
                if let image = images[index] {
                    if dataURLs.count == 1 {
                        // One picture keeps its shape, as tall as the strip, no wider than it would be square.
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: min(side * image.size.width / max(image.size.height, 1), side * 1.5), height: side)
                    } else {
                        Image(uiImage: image).resizable().scaledToFill().frame(width: side, height: side)
                    }
                } else {
                    Rectangle().fill(.fill.tertiary).frame(width: side, height: side)
                }
            }
            .clipShape(.rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color(.separator), lineWidth: 0.5))
            .contentShape(.rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("ios:chat.markdown.image"))
        .accessibilityValue(dataURLs.count > 1 ? Text(verbatim: "\(index + 1) / \(dataURLs.count)") : Text(verbatim: ""))
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
