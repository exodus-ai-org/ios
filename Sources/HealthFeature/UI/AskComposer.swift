// Sources/HealthFeature/UI/AskComposer.swift
import Models
import OdyKit
import SwiftUI

/// Ask about the day. The question goes to a new chat with the numbers attached; the chip says so before anything
/// is typed, and removes them. Numbers are attached by default only when the user has agreed to send the day's
/// summary. A suggestion fills the box rather than sending, so it can be read and changed first.
struct AskComposer: View {
    let suggestions: [LocalizedStringResource]
    /// Whether there is anything to attach; the block itself is only built when sending.
    let canAttach: Bool
    let attachedLabel: LocalizedStringResource
    let attachByDefault: Bool
    let attachment: () -> String?
    let onSend: (String) -> Void

    @State private var text = ""
    @State private var attach: Bool
    @FocusState private var focused: Bool
    /// The send button as the system draws it: a bordered circle is padded past its 30 pt label.
    @State private var buttonHeight: CGFloat = 0

    init(
        suggestions: [LocalizedStringResource], canAttach: Bool, attachedLabel: LocalizedStringResource,
        attachByDefault: Bool, attachment: @escaping () -> String?, onSend: @escaping (String) -> Void
    ) {
        self.suggestions = suggestions
        self.canAttach = canAttach
        self.attachedLabel = attachedLabel
        self.attachByDefault = attachByDefault
        self.attachment = attachment
        self.onSend = onSend
        _attach = State(initialValue: attachByDefault)
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
            if attach, canAttach {
                Button { withAnimation(.smooth) { attach = false } } label: {
                    Label(attachedLabel, systemImage: "xmark.circle.fill").font(.caption.weight(.semibold))
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
        // Consent given or taken back from the menu while the box is empty.
        .onChange(of: attachByDefault) { if text.isEmpty { attach = attachByDefault } }
    }

    private func send(_ question: String) {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        if attach, canAttach, let json = attachment() {
            onSend(HealthContext.compose(json: json, question: q))
        } else {
            onSend(q)
        }
        text = ""
        attach = attachByDefault
        focused = false
    }
}
