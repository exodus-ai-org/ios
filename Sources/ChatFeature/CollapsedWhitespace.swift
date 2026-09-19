extension String {
    /// Every run of whitespace and newlines collapsed to one space, the ends trimmed. Real chat
    /// titles can be long and multi-line; every place that shows one goes through this.
    var collapsedWhitespace: String {
        split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
