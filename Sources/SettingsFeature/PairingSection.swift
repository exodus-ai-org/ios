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
        Section("Computer") {
            if viewModel.isPaired {
                if let name = viewModel.computerName {
                    Text("Paired with \(name)")
                }
                Button("Unpair", role: .destructive) { confirmUnpair = true }
            } else if viewModel.isWorking {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Pairing…")
                }
            } else {
                Text(
                    "Pair this iPhone with Exodus on your computer: open Settings → Devices there and choose Pair a device."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                if QRScannerView.isSupported {
                    Button("Scan pairing code") { Task { await openScanner() } }
                        .navigationDestination(isPresented: $isScanning) {
                            ScannerScreen { link in
                                scannedLink = link
                                isScanning = false
                            }
                        }
                }
                Button("Paste pairing link") {
                    pair(from: UIPasteboard.general.string)
                }
            }
        }
        .onChange(of: isScanning) { _, showing in
            if !showing { pairWithScannedLink() }
        }
        .alert("Unpair from this computer?", isPresented: $confirmUnpair) {
            Button("Unpair", role: .destructive) {
                viewModel.unpair()
                onChange()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You will need to scan a new pairing code to connect again.")
        }
        .alert("Camera access is off", isPresented: $cameraDenied) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Allow Exodus to use the camera in Settings, or paste the pairing link instead.")
        }
        .alert(
            "Pairing failed",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.clearError() } })
        ) {
            Button("OK", role: .cancel) {}
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
