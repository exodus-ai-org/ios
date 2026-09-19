import SwiftUI

public struct PhilharmonicPlaceholderView: View {
    public init() {}

    public var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "hourglass")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Coming soon")
                .font(.title2)
                .fontWeight(.semibold)
            Text("The Philharmonic multi-agent workspace hasn't been ported to iOS yet.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
