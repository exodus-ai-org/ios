import SwiftUI

/// A label above its field and an optional description under it: the desktop's vertical settings row. The label
/// is hidden from VoiceOver because the field carries the same title.
struct SettingsFieldRow<Label: View, Field: View>: View {
    var description: Text?
    @ViewBuilder let label: Label
    @ViewBuilder let field: Field

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            label
                .font(.subheadline.weight(.medium))
                .accessibilityHidden(true)
            field
            if let description {
                description
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
