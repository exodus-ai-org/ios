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
        .disabled(!option.isAvailable)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
