#if DEBUG
import SwiftUI

/// DEBUG-only pages another module owns, pushed from the bottom of the Settings hub. The App sets them; Release has none.
@MainActor
public enum SettingsDebugHooks {
    public static var cardPrototypes: (() -> AnyView)?
}

struct SettingsDebugSection: View {
    var body: some View {
        if let cardPrototypes = SettingsDebugHooks.cardPrototypes {
            Section {
                NavigationLink {
                    cardPrototypes()
                } label: {
                    Label {
                        Text(verbatim: "Card prototypes")
                    } icon: {
                        Image(systemName: "rectangle.stack")
                    }
                }
            } header: {
                Text(verbatim: "Debug")
            }
        }
    }
}
#endif
