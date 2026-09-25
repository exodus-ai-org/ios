import Foundation

@testable import MarkdownKit

// Ported from the desktop's tests/unit/renderer/lib/markdown-blocks.test.ts SAMPLES.
enum MarkdownFixtures {
    static let samples: [(name: String, text: String)] = [
        (
            "paragraphs and headings",
            """
            # Title

            First paragraph with **bold** and `code`.

            Second paragraph,
            still the second paragraph.

            ## Setext-looking text
            Heading two
            -----------

            Done.
            """
        ),
        (
            "a loose list with nested items and a continuation paragraph",
            """
            Steps:

            1. First item

               Its continuation paragraph, indented.

            2. Second item
               - nested a

               - nested b (loose)

            3. Third

            After the list.
            """
        ),
        (
            "a fenced code block with blank lines and markdown-looking content",
            """
            Here is code:

            ```ts
            function a() {

              // # not a heading

              return "- not a list"
            }
            ```

            And after.
            """
        ),
        (
            "an indented code block after a paragraph",
            """
            Look:

                indented code

                second chunk of the same block

            Back to text.
            """
        ),
        (
            "a GFM table and a task list",
            """
            | Name | Value |
            | ---- | ----: |
            | a    |     1 |
            | b    |     2 |

            - [x] done
            - [ ] todo

            ~~struck~~ and https://example.com autolink.
            """
        ),
        (
            "display math containing blank lines",
            """
            The identity:

            $$
            a^2 + b^2

            = c^2
            $$

            holds. Inline $$x^2$$ too, but $5 - $10 stays text.
            """
        ),
        (
            "a block quote with a lazy continuation and a nested list",
            """
            > Quote line one
            lazy continuation

            > - quoted item
            >
            >   quoted continuation

            ---

            Text after a thematic break.
            """
        ),
        (
            "html and entities",
            """
            <div>

            inside?

            </div>

            &copy; 2026 &mdash; <span>inline</span>
            """
        ),
        (
            "list markers that arrive a character at a time",
            """
            Intro

            - dash one

            - dash two

            * star list

            + plus list

            1) paren one

            2) paren two

            10. ten
            11. eleven

            Tail.
            """
        ),
        (
            "a table right after a paragraph, then a list of fences",
            """
            Summary below.

            | a | b |
            |---|---|
            | 1 | 2 |

            1. Run this:

               ```sh
               echo one

               echo two
               ```

            2. Then this:

               ```sh
               echo three
               ```

            Done.
            """
        ),
        ("leading and trailing blank lines", "\n\nText after blank lines.\n\n"),
    ]

    static func sample(_ name: String) -> String {
        samples.first { $0.name == name }!.text
    }

    static func prefixes(of text: String) -> [String] {
        var result: [String] = []
        var index = text.startIndex
        while index < text.endIndex {
            index = text.index(after: index)
            result.append(String(text[..<index]))
        }
        return result
    }

    static func kinds(_ blocks: [MarkdownBlock]) -> [MarkdownBlock.Kind] {
        blocks.map(\.kind)
    }

    static func plain(_ string: AttributedString) -> String {
        String(string.characters)
    }

    static func runs(_ string: AttributedString) -> [(text: String, intent: InlinePresentationIntent, link: URL?)] {
        string.runs.map { run in
            (String(string[run.range].characters), run.inlinePresentationIntent ?? [], run.link)
        }
    }

    static func paragraphText(_ blocks: [MarkdownBlock]) -> [String] {
        blocks.compactMap {
            if case .paragraph(let content) = $0.kind { return plain(content) }
            return nil
        }
    }

    static func longDocument(minimumLength: Int) -> String {
        let pieces = [
            "## Section heading\n\n",
            "A paragraph with **bold**, *emphasis*, `code` and a [link](https://example.com) 【1-source】.\n\n",
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
