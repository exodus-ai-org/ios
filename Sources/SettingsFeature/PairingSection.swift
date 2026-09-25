import AVFoundation
import NetworkingKit
import SwiftUI
import UIKit

/// Settings → Computer. A device reaches Exodus only after it has been paired:
/// the computer shows a QR code (Settings → Devices → Pair a device) carrying a
/// one-time code and the fingerprint of the certificate to trust.
struct PairingSection: View {
    @State private var viewModel: PairingViewModel
    @State private var isScanning = false
    /// A link the scanner found; acted on once its screen has been popped, so
    /// the result alert isn't presented into a transition and lost.
    @State private var scannedLink: String?
    @State private var cameraDenied = false
    @State private var confirmUnpair = false
    private let onChange: () -> Void

    /// `onChange` fires after pairing or unpairing — the server the rest of
    /// Settings talks to has just changed.
    init(connection: ServerConnection, onChange: @escaping () -> Void) {
        _viewModel = State(
            initialValue: PairingViewModel(connection: connection, deviceName: UIDevice.current.name))
        self.onChange = onChange
    }

    var body: some View {
        Section("ios:settings.pairing.sectionTitle") {
            if viewModel.isPaired {
                if let name = viewModel.computerName {
                    Text(
                        String(
                            localized: "ios:settings.pairing.pairedWith", defaultValue: "Paired with \(name)",
                            comment: "Settings → Computer. %@ is the computer's name."))
                }
                Button("ios:settings.pairing.unpair", role: .destructive) { confirmUnpair = true }
            } else if viewModel.isWorking {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("ios:settings.pairing.inProgress")
                }
            } else {
                Text(
                    "ios:settings.pairing.instructions"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                if QRScannerView.isSupported {
                    Button("ios:settings.pairing.scanCode") { Task { await openScanner() } }
                        .navigationDestination(isPresented: $isScanning) {
                            ScannerScreen { link in
                                scannedLink = link
                                isScanning = false
                            }
                        }
                }
                Button("ios:settings.pairing.pasteLink") {
                    pair(from: UIPasteboard.general.string)
                }
            }
        }
        .onChange(of: isScanning) { _, showing in
            if !showing { pairWithScannedLink() }
        }
        .alert("ios:settings.pairing.unpairConfirmTitle", isPresented: $confirmUnpair) {
            Button("ios:settings.pairing.unpair", role: .destructive) {
                viewModel.unpair()
                onChange()
            }
            Button("common:action.cancel", role: .cancel) {}
        } message: {
            Text("ios:settings.pairing.unpairConfirmMessage")
        }
        .alert("ios:settings.pairing.cameraDeniedTitle", isPresented: $cameraDenied) {
            Button("ios:settings.pairing.openSystemSettings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("common:action.cancel", role: .cancel) {}
        } message: {
            Text("ios:settings.pairing.cameraDeniedMessage")
        }
        .alert(
            "ios:settings.pairing.failedTitle",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.clearError() } })
        ) {
            Button("ios:app.alert.ok", role: .cancel) {}
        } message: {
            // The reason, then the technical detail beneath it — what to report.
            Text(verbatim: [viewModel.errorMessage, viewModel.errorDetail].compactMap { $0 }.joined(separator: "\n\n"))
        }
    }

    /// The system prompt comes up here, before the scanner screen, not over it.
    private func openScanner() async {
        guard await AVCaptureDevice.requestAccess(for: .video) else {
            cameraDenied = true
            return
        }
        isScanning = true
    }

    private func pairWithScannedLink() {
        guard let link = scannedLink else { return }
        scannedLink = nil
        pair(from: link)
    }

    private func pair(from text: String?) {
        Task {
            if await viewModel.pair(from: text) { onChange() }
        }
    }
}
