import Testing

@testable import ChatFeature

@Suite("InteractiveText: the words an answer is written with")
struct InteractiveTextTests {
    @Test("the phone's labels, in English")
    func labels() {
        #expect(
            InteractiveAnswer.Labels.current
                == .init(other: "Other", addition: "Also", note: "Note", approved: "Approved", rejected: "Rejected"))
        #expect(InteractiveText.other == "Other…")
        #expect(InteractiveText.sent == "Sent")
    }
}
