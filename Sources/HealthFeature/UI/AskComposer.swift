// Sources/HealthFeature/UI/AskComposer.swift
import Models
import OdyKit
import SwiftUI

/// Ask about the day. The question goes to a new chat with the numbers attached (removable).
struct AskComposer: View {
    let suggestions: [LocalizedStringResource]
    let attachment: () -> String?
    let onSend: (String) -> Void

    @State private var text = ""
    @State private var attach = true
    @FocusState private var focused: Bool

    init(suggestions: [LocalizedStringResource], attachment: @escaping () -> String?, onSend: @escaping (String) -> Void) {
        self.suggestions = suggestions
        self.attachment = attachment
        self.onSend = onSend
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if text.isEmpty && !focused {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(suggestions.enumerated()), id: \.offset) { _, s in
                            Button { send(String(localized: s)) } label: { Text(s).font(.footnote) }
                                .buttonStyle(.glass)
                                .buttonBorderShape(.capsule)
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .scrollClipDisabled()
                .transition(.opacity)
            }
            if attach, focused || !text.isEmpty, attachment() != nil {
                Button { withAnimation(.smooth) { attach = false } } label: {
                    Label("ios:health.ask.attached", systemImage: "xmark.circle.fill").font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .tint(.orange)
                .transition(.opacity)
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField("ios:health.ask.placeholder", text: $text, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($focused)
                    .submitLabel(.send)
                    .onSubmit { send(text) }
                    .padding(.vertical, 6)
                Button { send(text) } label: {
                    Image(systemName: "arrow.up").font(.body.weight(.bold)).frame(width: 30, height: 30)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
                .tint(OdyPalette.marigold)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel(Text("ios:health.ask.send"))
            }
            .padding(.leading, 16)
            .padding(.trailing, 8)
            .padding(.vertical, 6)
            .glassEffect(.regular, in: .capsule)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .animation(.smooth(duration: 0.25), value: focused)
        .animation(.smooth(duration: 0.25), value: text.isEmpty)
    }

    private func send(_ question: String) {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        if attach, let json = attachment() {
            onSend(HealthContext.compose(json: json, question: q))
        } else {
            onSend(q)
        }
        text = ""
        attach = true
        focused = false
    }
}
