import Foundation

/// The interactive blocks' words in the user's language. An answer is written with the answering phone's words
/// (`InteractiveAnswer.Labels.current`); the model reads them as they are.
enum InteractiveText {
    static var other: String {
        String(
            localized: "ios:chat.block.other", defaultValue: "Other…",
            comment: "Questionnaire in an answer: the choice that lets the user type an answer of their own.")
    }
    static var approved: String {
        String(
            localized: "ios:chat.block.approved", defaultValue: "Approved",
            comment: "A confirmation the user approved; also the word written in the answer sent to the assistant.")
    }
    static var rejected: String {
        String(
            localized: "ios:chat.block.rejected", defaultValue: "Rejected",
            comment: "A confirmation the user rejected; also the word written in the answer sent to the assistant.")
    }
    static var sent: String {
        String(
            localized: "ios:chat.block.sent", defaultValue: "Sent",
            comment: "VoiceOver announcement after the user sent a questionnaire's or confirmation's answer.")
    }
    static var answerOther: String {
        String(
            localized: "ios:chat.block.answer.other", defaultValue: "Other",
            comment:
                "Written in the answer sent to the assistant, before what the user typed under Other…: e.g. Other: ankles.")
    }
    static var answerAddition: String {
        String(
            localized: "ios:chat.block.answer.addition", defaultValue: "Also",
            comment:
                "Written in the answer sent to the assistant, before what the user typed in a questionnaire's closing field.")
    }
    static var answerNote: String {
        String(
            localized: "ios:chat.block.answer.note", defaultValue: "Note",
            comment: "Written in the answer sent to the assistant, before the note typed under a confirmation.")
    }
}

extension InteractiveAnswer.Labels {
    /// The words this phone writes an answer with.
    static var current: Self {
        Self(
            other: InteractiveText.answerOther, addition: InteractiveText.answerAddition,
            note: InteractiveText.answerNote, approved: InteractiveText.approved, rejected: InteractiveText.rejected)
    }
}
