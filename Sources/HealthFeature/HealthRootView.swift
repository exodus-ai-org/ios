import NetworkingKit
import SwiftUI

enum HealthFeatureInfo {
    static let name = "Health"
}

/// The Health workspace. A placeholder until the home screen lands (plan 3).
public struct HealthRootView: View {
    let apiClient: APIClient

    public init(apiClient: APIClient) { self.apiClient = apiClient }

    public var body: some View {
        ContentUnavailableView("ios:app.workspace.health", systemImage: "heart.text.square")
    }
}
