#if DEBUG
import Foundation

/// The gallery's runs for the user's bubble: a message written in Markdown, and one long enough to be cut short.
extension MessageGalleryFixtures {
    static let bubbleRuns: [Run] = [
        Run(
            title: "The user's message in Markdown",
            json: bubbleRun(
                id: "ub1",
                question: """
                    ### Release checklist
                    - bump `CFBundleVersion`
                    - run the **full** suite
                    ```sh
                    xcodebuild test -scheme App
                    ```
                    Anything [missing](https://example.com)?
                    """,
                answer: "Add a smoke test on a real device before you tag it.")),
        Run(
            title: "A long message: cut short with Show more",
            json: bubbleRun(
                id: "ub2",
                question: (1...34).map { "Line \($0) of the meeting notes I pasted, with enough words to read as prose." }
                    .joined(separator: "\n"),
                answer: "Here is the gist of those notes.")),
    ]

    private static func bubbleRun(id: String, question: String, answer: String) -> String {
        let messages: [[String: Any]] = [
            ["id": id, "runId": id, "role": "user", "content": question, "timestamp": 1000],
            [
                "id": "\(id)a", "runId": id, "role": "assistant", "content": [["type": "text", "text": answer]],
                "stopReason": "stop", "timestamp": 1200,
            ],
        ]
        let data = (try? JSONSerialization.data(withJSONObject: messages)) ?? Data("[]".utf8)
        return String(decoding: data, as: UTF8.self)
    }
}
#endif
