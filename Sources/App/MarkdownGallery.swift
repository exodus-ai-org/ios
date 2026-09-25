#if DEBUG
import MarkdownKit
import SwiftUI
import UIKit

/// DEBUG-only visual check of `MarkdownView`: `-MarkdownGallery` shows it, `-MarkdownGallerySection N`
/// scrolls to section N, `-MarkdownGalleryStream` shows only the streaming section, looping it.
enum MarkdownGalleryLaunch {
    static var isEnabled: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("-MarkdownGallery") || streams
    }

    static var streams: Bool { ProcessInfo.processInfo.arguments.contains("-MarkdownGalleryStream") }

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
        MarkdownCitation(number: 1, title: "Swift.org", host: "www.swift.org"),
        MarkdownCitation(number: 2, title: "Apple Developer Documentation", host: "developer.apple.com"),
        MarkdownCitation(number: 3, title: "A very long article title that must be truncated in the chip", host: nil),
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
    ]

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
