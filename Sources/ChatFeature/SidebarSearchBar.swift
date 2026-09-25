import SwiftUI

/// The sidebar's search field: a native `TextField` in a glass capsule with a Cancel button. Built by
/// hand because `.searchable` did not respond inside the drawer (see the spec, section 3).
struct SidebarSearchBar: View {
    @Binding var text: String
    let onCancel: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("ios:chat.search.label", text: $text)
                    .focused($focused)
                    .submitLabel(.search)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("searchField")
                if !text.isEmpty {
                    Button {
                        text = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("ios:chat.search.clearButton")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .glassEffect(.regular, in: .capsule)

            Button("common:action.cancel", action: onCancel)
                .accessibilityIdentifier("searchCancel")
        }
        .padding(.horizontal, 12)
        .onAppear { focused = true }
    }
}
