import SwiftUI

/// Fades the trailing edge of a horizontal scroll view while more content lies to the right, the only
/// hint that a wide table or a long code line scrolls.
struct MarkdownTrailingFade: ViewModifier {
    static let width: CGFloat = 28

    @State private var moreToRight = false

    nonisolated static func hasMoreToRight(contentWidth: CGFloat, offset: CGFloat, containerWidth: CGFloat) -> Bool {
        contentWidth - offset - containerWidth > 1
    }

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: Bool.self) { geometry in
                Self.hasMoreToRight(
                    contentWidth: geometry.contentSize.width, offset: geometry.contentOffset.x,
                    containerWidth: geometry.containerSize.width)
            } action: { _, more in
                moreToRight = more
            }
            .mask {
                HStack(spacing: 0) {
                    Rectangle()
                    LinearGradient(colors: [.black, moreToRight ? .clear : .black], startPoint: .leading, endPoint: .trailing)
                        .frame(width: Self.width)
                }
            }
    }
}

extension View {
    func markdownTrailingFade() -> some View { modifier(MarkdownTrailingFade()) }
}
