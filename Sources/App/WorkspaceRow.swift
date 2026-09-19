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
        }
        // Without a style the row takes the button tint; `.plain` plus an explicit foreground keeps it
        // consistent with the Recents rows and lets the unavailable workspace read as unavailable.
        .buttonStyle(.plain)
        .foregroundStyle(option.isAvailable ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        .disabled(!option.isAvailable)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
