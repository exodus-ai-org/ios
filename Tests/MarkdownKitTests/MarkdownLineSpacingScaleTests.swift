import Foundation
import Testing
import UIKit

@testable import MarkdownKit

/// The user's bubble draws its message through the answers' pipeline with closer lines
/// (`markdownLineSpacingScale`): its Markdown still styles, and its lines stand as the plain bubble's did.
@Suite("MarkdownTextStyle.lineSpacingScale")
@MainActor
struct MarkdownLineSpacingScaleTests {
    private func run(_ markdown: String, scale: CGFloat) -> NSAttributedString {
        var style = MarkdownTextStyle(spec: .body)
        style.lineSpacingScale = scale
        var builder = MarkdownRunBuilder(
            style: style, citations: [:], underlinesLinks: false, em: MarkdownFontSpec.body.pointSize)
        return builder.build(MarkdownParser.parse(markdown)).text
    }

    @Test("**bold** in the bubble is a bold run")
    func bold() throws {
        let text = run("say **hello** now", scale: 0.6)
        let at = (text.string as NSString).range(of: "hello").location
        let font = try #require(text.attribute(.font, at: at, effectiveRange: nil) as? UIFont)
        #expect(font.fontDescriptor.symbolicTraits.contains(.traitBold))
        let plain = try #require(text.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)
        #expect(!plain.fontDescriptor.symbolicTraits.contains(.traitBold))
    }

    @Test("the room between lines is the plain bubble's: body's, times the scale")
    func spacing() throws {
        let text = run("one line\nand the next", scale: 0.6)
        let paragraph = try #require(text.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
        #expect(abs(paragraph.lineSpacing - MarkdownTypography.bodyLineSpacing * 0.6) < 0.001)
    }
}
