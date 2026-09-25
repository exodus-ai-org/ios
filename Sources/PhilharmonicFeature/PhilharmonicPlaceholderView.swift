import SwiftUI

public struct PhilharmonicPlaceholderView: View {
    public init() {}

    public var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "hourglass")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("ios:app.workspace.comingSoon")
                .font(.title2)
                .fontWeight(.semibold)
            Text("ios:philharmonic.placeholder.message")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
