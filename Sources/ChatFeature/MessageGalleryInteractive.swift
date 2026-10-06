#if DEBUG
import Foundation

/// The gallery's runs for the interactive blocks: a questionnaire waiting for its answer, a confirmation waiting for
/// its, and a questionnaire answered — frozen with its picks, the answer under it as a card, and the reply after it.
/// `-MessageGallerySection ask|confirm|answered` scrolls to one.
extension MessageGalleryFixtures {
    static let askSource =
        #"{"title":"A few details first","questions":[{"id":"where","text":"Where does it itch most?","type":"single","options":["Lower legs","Arms","All over"],"other":true},{"id":"when","text":"When is it worst?","type":"multi","options":["After a shower","At night","All day"]}],"note":"Anything else I should know?","submit":"Send"}"#
    static let confirmSource =
        #"{"title":"Add this trip to your calendar?","details":"**Oct 21–25**, five days, 17 stops; calendar *Travel*.","approve":"Add it","reject":"Not now","note":"Anything to change?"}"#

    static let interactiveRuns: [Run] = [
        Run(
            title: "A questionnaire in the answer",
            json: interactiveRun(
                id: "ib1", question: "My legs itch after every shower. What can I do?",
                reply: "That's common when the air is dry. A few details first, so I can be specific:\n\n```exodus-ask\n\(askSource)\n```")),
        Run(
            title: "A confirmation before an action",
            json: interactiveRun(
                id: "ib2", question: "Put the Kyoto trip in my calendar.",
                reply: "Here's what I'd add:\n\n```exodus-confirm\n\(confirmSource)\n```")),
        Run(title: "Answered: the block frozen, the answer as a card", json: answeredRun()),
    ]

    /// The run index a `-MessageGallerySection` name stands for.
    static func namedSection(_ name: String) -> Int? {
        let offset: Int? =
            switch name {
            case "ask": 0
            case "confirm": 1
            case "answered": 2
            default: nil
            }
        return offset.map { runs.count - interactiveRuns.count + $0 }
    }

    private static func interactiveRun(
        id: String, question: String, reply: String, then rest: [[String: Any]] = []
    ) -> String {
        let messages: [[String: Any]] =
            [
                ["id": id, "runId": id, "role": "user", "content": question, "timestamp": 1000],
                [
                    "id": "\(id)a", "runId": id, "role": "assistant", "content": [["type": "text", "text": reply]],
                    "stopReason": "stop", "timestamp": 1200,
                ],
            ] + rest
        let data = (try? JSONSerialization.data(withJSONObject: messages)) ?? Data("[]".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    private static func answeredRun() -> String {
        guard case .ask(let ask)? = InteractiveBlock.parse(.ask, source: askSource) else { return "[]" }
        let answer = InteractiveAnswer.composeAsk(
            ask, ref: "ib3",
            responses: ["where": .init(options: ["Lower legs"]), "when": .init(options: ["After a shower", "At night"])],
            note: "I use an unscented lotion.", labels: .current)
        let rest: [[String: Any]] = [
            ["id": "ib4", "runId": "ib4", "role": "user", "content": answer, "timestamp": 1400],
            [
                "id": "ib4a", "runId": "ib4", "role": "assistant",
                "content": [
                    [
                        "type": "text",
                        "text":
                            "Then it's most likely dry skin from hot showers. Keep them short and lukewarm, and put the lotion on within three minutes, while your skin is still damp.",
                    ]
                ],
                "stopReason": "stop", "timestamp": 1600,
            ],
        ]
        return interactiveRun(
            id: "ib3", question: "My legs itch after every shower. What can I do?",
            reply: "A few details first, so I can be specific:\n\n```exodus-ask\n\(askSource)\n```", then: rest)
    }
}
#endif
