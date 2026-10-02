#if DEBUG
import ChatFeature
import MarkdownKit
import SwiftUI
import UIKit

/// DEBUG-only visual check of `MarkdownView`: `-MarkdownGallery` shows it, `-MarkdownGallerySection N`
/// scrolls to section N, `-MarkdownGalleryStream` shows only the streaming section, looping it.
/// `-MarkdownGalleryArriving` draws every block as one still being written — by `Text`, not in a text view: two
/// screenshots, with and without it, show whether a block's text moves when the block settles.
enum MarkdownGalleryLaunch {
    static var isEnabled: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("-MarkdownGallery") || streams
    }

    static var streams: Bool { ProcessInfo.processInfo.arguments.contains("-MarkdownGalleryStream") }
    static var arriving: Bool { ProcessInfo.processInfo.arguments.contains("-MarkdownGalleryArriving") }

    static var section: Int? {
        guard let index = ProcessInfo.processInfo.arguments.firstIndex(of: "-MarkdownGallerySection"),
            index + 1 < ProcessInfo.processInfo.arguments.count
        else { return nil }
        return Int(ProcessInfo.processInfo.arguments[index + 1])
    }
}

struct MarkdownGalleryView: View {
    private let sections = MarkdownGalleryDocuments.sections.enumerated().filter {
        !MarkdownGalleryLaunch.streams || $0.offset == MarkdownGalleryDocuments.streamSection
    }
    @State private var tapped: Int?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    ForEach(sections, id: \.offset) { index, section in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(verbatim: "\(index) · \(section.title)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tint)
                            if index == MarkdownGalleryDocuments.streamSection {
                                MarkdownGalleryStream(text: section.text)
                            } else {
                                MarkdownView(
                                    text: section.text, citations: MarkdownGalleryDocuments.citations,
                                    isStreaming: false
                                ) { tapped = $0 }
                            }
                        }
                        .id(index)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .overlay(alignment: .bottom) {
                if let tapped {
                    Text(verbatim: "Tapped citation \(tapped)")
                        .font(.footnote)
                        .padding(8)
                        .background(.regularMaterial, in: .capsule)
                }
            }
            .task {
                guard let section = MarkdownGalleryLaunch.section else { return }
                try? await Task.sleep(for: .milliseconds(300))
                proxy.scrollTo(section, anchor: .top)
            }
        }
        .environment(\.markdownCitationIcons, GalleryIcons.markdown)
        .environment(\.markdownDrawsAsArriving, MarkdownGalleryLaunch.arriving)
    }
}

private struct MarkdownGalleryStream: View {
    let text: String
    @State private var shown = ""
    @State private var isStreaming = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MarkdownView(text: shown, citations: MarkdownGalleryDocuments.citations, isStreaming: isStreaming)
            Button {
                Task { await stream() }
            } label: {
                Text(verbatim: "Replay stream")
            }
            .font(.footnote)
            .disabled(isStreaming)
        }
        .task {
            guard MarkdownGalleryLaunch.streams else {
                shown = text
                return
            }
            while !Task.isCancelled {
                await stream()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    private func stream() async {
        isStreaming = true
        shown = ""
        let characters = Array(text)
        var index = 0
        while index < characters.count, !Task.isCancelled {
            let next = min(index + 1, characters.count)
            shown += String(characters[index..<next])
            index = next
            try? await Task.sleep(for: .milliseconds(30))
        }
        isStreaming = false
    }
}

enum MarkdownGalleryDocuments {
    static let citations = [
        MarkdownCitation(number: 1, title: "Swift.org", host: "www.swift.org", iconURL: GalleryIcons.url("swift.org")),
        MarkdownCitation(
            number: 2, title: "Apple Developer Documentation", host: "Apple Developer",
            iconURL: GalleryIcons.url("developer.apple.com")),
        MarkdownCitation(number: 3, title: "A very long article title that must be truncated in the chip", host: nil),
        MarkdownCitation(number: 4, title: "Storms cross East Texas", host: "Lufkin Daily News"),
    ]

    private static let open = "\u{3010}"
    private static let close = "\u{3011}"

    private static func cite(_ numbers: String) -> String { "\(open)\(numbers)-source\(close)" }

    static let smallImage = dataURL(width: 120, height: 80, colors: [.systemTeal, .systemBlue])
    static let wideImage = dataURL(width: 900, height: 300, colors: [.systemOrange, .systemPink, .systemPurple])

    private static func dataURL(width: CGFloat, height: CGFloat, colors: [UIColor]) -> String {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: width, height: height)
        let data = UIGraphicsImageRenderer(size: size, format: format).pngData { context in
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors.map(\.cgColor) as CFArray, locations: nil)!
            context.cgContext.drawLinearGradient(
                gradient, start: .zero, end: CGPoint(x: width, y: height), options: [])
        }
        return "data:image/png;base64,\(data.base64EncodedString())"
    }

    static var streamSection: Int { sections.firstIndex { $0.title == streamTitle }! }
    private static let streamTitle = "Streaming: an unclosed fence"

    static let sections: [(title: String, text: String)] = [
        (
            "Headings h1–h6",
            """
            # Heading one
            A paragraph under the first heading, long enough to wrap onto a second line on a phone.

            ## Heading two
            Text under heading two.

            ### Heading three
            Text under heading three.

            #### Heading four
            Text under heading four.

            ##### Heading five
            Text under heading five.

            ###### Heading six
            Text under heading six.
            """
        ),
        (
            "Emphasis, links, tilde and money",
            """
            Plain, **bold**, *italic*, ***bold italic***, `inline code`, **bold with `code`** and ~~struck through~~.

            Tonight 19~32°C, tomorrow 5~10°C: a lone tilde never strikes. Only ~~this~~ does.

            Hotels cost $200 - $300 per night, and $5 - $10 for breakfast. Money is not math.

            A [markdown link](https://www.swift.org), a bare https://developer.apple.com/documentation autolink \
            and snake_case_names stay literal.
            A hard break follows\\
            this line.
            """
        ),
        (
            "Lists",
            """
            - First level
              - Second level with a longer item that wraps onto the next line to check the hanging indent
                - Third level
                - Another third
              - Back to second
            - First again

            3. Starts at three
            4. Four
            5. Five

            8) eight
            9) nine
            10) ten, wider number
            11) eleven

            - [x] Done task
            - [ ] Open task with a longer description that wraps to a second line
            - [ ] Another open one
            """
        ),
        (
            "Blockquotes",
            """
            > A quote with **bold** text that runs long enough to wrap onto a second line on a phone screen.
            >
            > > A nested quote inside it.
            >
            > - a quoted list item
            > - another one

            After the quote.
            """
        ),
        (
            "Code",
            """
            A fenced block with a language:

            ```swift
            struct Greeting {
                let name: String
                func render() -> String { "Hello, \\(name)! This line is deliberately long so that it must scroll sideways." }
            }
            ```

            Without a language:

            ```
            plain text code
            second line
            ```

            And the text after it.
            """
        ),
        (
            "Tables",
            """
            | Left | Center | Right |
            | :--- | :----: | ----: |
            | apples | **12** | 1.20 |
            | pears with a longer name | 3 | 13.75 |
            | `code` | ~~old~~ | 0.5 |

            | Region | Q1 | Q2 | Q3 | Q4 | Notes |
            | --- | --: | --: | --: | --: | --- |
            | North America | 1,204 | 1,388 | 1,502 | 1,640 | A long note that should wrap inside its cell instead of making the column enormous |
            | Europe | 998 | 1,020 | 1,115 | 1,203 | Short |
            """
        ),
        (
            "Images",
            """
            A small image stays its own size:

            ![A small teal gradient](\(smallImage))

            A wide image is capped to the content width:

            ![A wide orange gradient](\(wideImage))

            A remote image waits for a tap (MarkdownImagePolicy.current):

            ![The Swift logo](https://www.swift.org/assets/images/swift~dark.svg)

            A broken image shows its alt text:

            ![Diagram that failed to load](diagrams/missing.png)

            An image with no alt text that cannot load:

            ![](diagrams/missing.png)
            """
        ),
        (
            "Citations",
            """
            Swift 6 turns on strict concurrency checking by default \(cite("1")). The documentation covers \
            `Sendable` in depth\(cite("2")). Two at once \(cite("1,3")). An unresolved marker \(cite("9")) is \
            stripped, like the desktop does.

            - In a list item too \(cite("2"))
            """
        ),
        (
            "HTML and a thematic break",
            """
            Before the rule.

            ---

            <div>raw html block</div>

            &copy; 2026 &mdash; <span>inline html</span>
            """
        ),
        (
            "Desktop samples",
            """
            # Title

            First paragraph with **bold** and `code`.

            Steps:

            1. First item

               Its continuation paragraph, indented.

            2. Second item
               - nested a

               - nested b (loose)

            3. Third

            Look:

                indented code

                second chunk of the same block

            Back to text.

            | Name | Value |
            | ---- | ----: |
            | a    |     1 |
            | b    |     2 |

            The identity:

            $$
            a^2 + b^2

            = c^2
            $$

            holds. Inline $$x^2$$ too, but $5 - $10 stays text.

            > Quote line one
            lazy continuation

            1) paren one

            2) paren two

            10. ten
            11. eleven

            Tail.
            """
        ),
        (
            streamTitle,
            """
            Here is the **plan** for the migration \(cite("1")):

            1. Parse the input
            2. Render each block

            | Step | Time |
            | --- | --: |
            | parse | 2 ms |

            ```python
            def render(blocks):
                for block in blocks:
                    print(block)  # a long comment so the line has to scroll sideways on a phone
            """
        ),
        ("Long document (~2 000 tokens)", longDocument(minimumLength: 8_000)),
        ("Chinese, with citations", chineseSample),
        (
            "A chip at the end of a line goes to the next line whole",
            """
            Storms crossed East Texas late on Sunday \(cite("4,1,2")) and the power was out by morning.

            Storms crossed East Texas late on Sunday night \(cite("4,1,2")) and the power was out by morning.

            Storms crossed East Texas late on a Sunday night \(cite("4,1,2")) and the power was out by morning.

            Storms crossed all of East Texas late on a Sunday night \(cite("4,1,2")) and the power was out.
            """
        ),
        (
            "An HTML line break is a line break",
            """
            Day one: the old town<br>Day two: the coast<BR/>Day three: the hills

            <br>

            The paragraph above this one was nothing but a break, and is not drawn. In code, `<br>` is text.
            """
        ),
        ("Bold beside CJK punctuation", cjkEmphasisSample),
    ]

    /// Han text sets differently from Latin (no spaces, full-width punctuation), and chips must sit well in both.
    private static let chineseSample = [
        "早上好。要给你一份贴合持仓的简报，我先拉几组最新数据：美股大盘走势、日元汇率与美联储利率路径，以及半导体供应链的最新动态。",  // l10n:ignore: gallery fixture
        "",
        "## 大盘：波动周，周五收复失地",  // l10n:ignore: gallery fixture
        "本周美股经历了一波债券收益率驱动的抛售，10 年期美债收益率一度触及 2007 年以来最高水平\(cite("1"))\(cite("2"))。但周五三大指数收高，道指涨 0.93%，标普 500 涨 0.51%\(cite("1,2"))。芯片股在周五普涨提振了市场情绪\(cite("3"))。",  // l10n:ignore: gallery fixture
        "",
        "- **美联储**：10 月再次加息的概率一度接近 70%\(cite("2"))。",  // l10n:ignore: gallery fixture
        "- **日元**：美元兑日元在 150 附近反复。",  // l10n:ignore: gallery fixture
    ].joined(separator: "\n")

    /// CommonMark leaves these `**` literal; the CJK-friendly rule bolds them. The last line stays literal, as in
    /// English it should.
    private static let cjkEmphasisSample = [
        "关键不在点位，而是**\"卖与不卖都没有依据\"**——赢家靠的是纪律。",  // l10n:ignore: gallery fixture
        "",
        "这是**「重点」**的说法，**粗体。**后面接着写，中文**粗体**中文，还有*斜体*。",  // l10n:ignore: gallery fixture
        "",
        "Code keeps its asterisks: `而是**\"引号\"**`, and a**\"quoted\"**b stays literal.",  // l10n:ignore: gallery fixture
    ].joined(separator: "\n")

    private static func longDocument(minimumLength: Int) -> String {
        let pieces = [
            "## Section heading\n\n",
            "A paragraph with **bold**, *emphasis*, `code` and a [link](https://example.com) \(cite("1")).\n\n",
            "- first item\n- second item with ~~old~~ text\n- third 19~32°C\n\n",
            "```swift\nlet answer = 42\nprint(answer)\n```\n\n",
            "| a | b |\n|:--|--:|\n| 1 | 2 |\n\n",
            "> A quote that runs\n> over two lines.\n\n",
            "Costs $200 - $300 per night, snake_case_names stay literal.\n\n",
        ]
        var text = ""
        var index = 0
        while text.count < minimumLength {
            text += pieces[index % pieces.count]
            index += 1
        }
        return text
    }
}
#endif
