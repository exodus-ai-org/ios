import NetworkingKit
import SwiftUI

/// Holds the app behind Face ID while the pairing credential is locked: on a
/// cold start, and after more than `ServerConnection.backgroundGrace` in the
/// background. The token lives in the Keychain behind biometrics and is only
/// ever held in memory between those moments. An unpaired app (the Simulator)
/// has nothing to unlock and goes straight through.
struct UnlockGate<Content: View>: View {
    let connection: ServerConnection
    @ViewBuilder let content: () -> Content

    @Environment(\.scenePhase) private var scenePhase
    @State private var isLocked: Bool
    @State private var isUnlocking = false
    @State private var backgroundedAt: Date?

    init(connection: ServerConnection, @ViewBuilder content: @escaping () -> Content) {
        self.connection = connection
        self.content = content
        _isLocked = State(initialValue: connection.isPaired && !connection.isUnlocked)
    }

    var body: some View {
        Group {
            if isLocked {
                lockedView
            } else {
                content()
            }
        }
        .task { await unlockIfNeeded() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                backgroundedAt = Date()
            case .active:
                if let since = backgroundedAt,
                   Date().timeIntervalSince(since) > ServerConnection.backgroundGrace,
                   connection.isPaired
                {
                    connection.lock()
                    isLocked = true
                }
                backgroundedAt = nil
                Task { await unlockIfNeeded() }
            default:
                break
            }
        }
    }

    private var lockedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Exodus is locked")
                .font(.headline)
            Button("Unlock") { Task { await unlockIfNeeded() } }
                .buttonStyle(.borderedProminent)
                .disabled(isUnlocking)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func unlockIfNeeded() async {
        guard isLocked, !isUnlocking else { return }
        isUnlocking = true
        defer { isUnlocking = false }
        do {
            try await connection.unlock(reason: String(localized: "Unlock the connection to your computer"))
            // Unpaired meanwhile (revoked, then cleared): nothing left to guard.
            isLocked = connection.isPaired && !connection.isUnlocked
        } catch {
            // Cancelled or failed: stay locked; the button tries again.
        }
    }
}
