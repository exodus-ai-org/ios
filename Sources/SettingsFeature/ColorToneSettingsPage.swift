import Models
import SwiftUI

/// Settings → General → Color tone: the desktop's seven swatches as a checkmark list, each drawn in the tone itself.
struct ColorToneSettingsPage: View {
    @Bindable var viewModel: ColorToneViewModel

    var body: some View {
        Form {
            Section {
                ForEach(ColorTone.allCases) { tone in
                    Button {
                        Task { await viewModel.select(tone) }
                    } label: {
                        ColorToneRow(tone: tone, isSelected: tone == viewModel.selected)
                    }
                    .buttonStyle(.plain)
                }
            } footer: {
                Text("settings:general.colorTone.description")
            }
            .disabled(!viewModel.hasLoaded)
            SettingsErrorSection(message: viewModel.errorMessage)
        }
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
    }
}

private struct ColorToneRow: View {
    let tone: ColorTone
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            ColorToneSwatch(tone: tone)
            Text(tone.title)
                .foregroundStyle(.primary)
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .fontWeight(.semibold)
                    // A glyph on the page: the tone's ink, which reads where its fill may not.
                    .foregroundStyle(tone.inkColor)
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// The tone's primary as a dot, the desktop's swatch.
struct ColorToneSwatch: View {
    let tone: ColorTone
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 22

    var body: some View {
        Circle()
            .fill(tone.color)
            .overlay { Circle().strokeBorder(.primary.opacity(0.12), lineWidth: 1) }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
