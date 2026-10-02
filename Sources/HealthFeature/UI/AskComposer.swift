// Sources/HealthFeature/UI/AskComposer.swift
import Models
import OdyKit
import SwiftUI

/// Ask about the day. The question goes to a new chat with the numbers always attached (Chat shows them as its health
/// card), so there is nothing to confirm here. A suggestion fills the box rather than sending, so it can be read and
/// changed first.
struct AskComposer: View {
    let suggestions: [LocalizedStringResource]
    /// The numbers that go with the question, built only when sending; nil sends the question alone.
    let attachment: () -> String?
    let onSend: (String) -> Void
    /// A question handed over from a widget: in the box, focused, waiting to be read and sent.
    let initialText: String?

    @State private var text = ""
    @FocusState private var focused: Bool
    /// The send button as the system draws it: a bordered circle is padded past its 30 pt label.
    @State private var buttonHeight: CGFloat = 0

    init(
        suggestions: [LocalizedStringResource], attachment: @escaping () -> String?, initialText: String? = nil,
        onSend: @escaping (String) -> Void
    ) {
        self.suggestions = suggestions
        self.attachment = attachment
        self.onSend = onSend
        self.initialText = initialText
        _text = State(initialValue: initialText ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if text.isEmpty && !focused {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(suggestions.enumerated()), id: \.offset) { _, s in
                            Button {
                                text = String(localized: s)
                                focused = true
                            } label: { Text(s).font(.footnote) }
                                .buttonStyle(.glass)
                                .buttonBorderShape(.capsule)
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .scrollClipDisabled()
                .transition(.opacity)
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField("ios:health.ask.placeholder", text: $text, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($focused)
                    .submitLabel(.send)
                    .onSubmit { send(text) }
                    // As tall as the send button as drawn, so one line (and the placeholder) centres on it; more
                    // lines grow the field upward while the button stays at the bottom.
                    .frame(minHeight: max(buttonHeight, 30), alignment: .center)
                Button { send(text) } label: {
                    Image(systemName: "arrow.up").font(.body.weight(.bold)).frame(width: 30, height: 30)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
                .tint(OdyPalette.marigold)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel(Text("ios:health.ask.send"))
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { buttonHeight = $0 }
            }
            .padding(.leading, 16)
            .padding(.trailing, 8)
            .padding(.vertical, 6)
            .glassEffect(.regular, in: .capsule)
        }
        .padding(.horizontal, 12)
        .padding(.top, 14)
        .padding(.bottom, 8)
        // One frosted panel behind the whole stack, fading in at its top edge, so what scrolls under it stays
        // legible without a hard line.
        .background {
            Rectangle()
                .fill(.bar)
                .mask {
                    VStack(spacing: 0) {
                        LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: 18)
                        Color.black
                    }
                }
                .ignoresSafeArea(edges: .bottom)
        }
        .animation(.smooth(duration: 0.25), value: focused)
        .animation(.smooth(duration: 0.25), value: text.isEmpty)
        .onAppear { if initialText != nil { focused = true } }
        // A second link while Health is already on screen: the box is already there, so it takes the new question.
        .onChange(of: initialText) {
            if let initialText {
                text = initialText
                focused = true
            }
        }
    }

    private func send(_ question: String) {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        if let json = attachment() {
            onSend(HealthContext.compose(json: json, question: q))
        } else {
            onSend(q)
        }
        text = ""
        focused = false
    }
}
