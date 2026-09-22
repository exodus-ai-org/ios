import SwiftUI

/// One workspace in the sidebar. An unavailable workspace is disabled and says why.
struct WorkspaceRow: View {
    let option: AppWorkspace
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Label {
                    Text(option.title)
                } icon: {
                    Image(systemName: option.systemImage)
                }
                if !option.isAvailable {
                    Spacer()
                    Text("Coming soon")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            // `.plain` hit-tests the label, not the row, so stretch it and give it a shape: without this
            // a tap to the right of the title would miss. Same pattern as the Recents and search rows.
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        // `.plain` keeps the row's own foreground instead of the button tint, consistent with the
        // Recents rows and lets the unavailable workspace read as unavailable; `RowPressStyle` gives
        // it the same press tint those rows get, since `.plain` alone gives none.
        .buttonStyle(RowPressStyle())
        .foregroundStyle(option.isAvailable ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        .disabled(!option.isAvailable)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The same near-imperceptible press tint the Recents and search rows use (`SidebarRow` in
/// ChatFeature — a different module, so this is its own small copy rather than shared API), so
/// every row in the sidebar responds to a touch the same way.
private struct RowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.primary.opacity(0.06) : Color.clear)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
