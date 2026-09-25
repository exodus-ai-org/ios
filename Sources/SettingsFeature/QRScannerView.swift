import NetworkingKit
import SwiftUI
import VisionKit

/// The camera, looking for a QR code. Reports each new payload once; the caller
/// decides whether it is a pairing link. Not available in the Simulator (no
/// camera) — `isSupported` says so, and the pairing screen offers pasting the
/// link instead.
struct QRScannerView: UIViewControllerRepresentable {
    let onPayload: (String) -> Void
    /// The camera could not be started, or stopped working — with the reason.
    let onUnavailable: (String) -> Void

    @MainActor static var isSupported: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    func makeUIViewController(context: Context) -> ScannerHostController {
        ScannerHostController(onPayload: onPayload, onUnavailable: onUnavailable)
    }

    func updateUIViewController(_ controller: ScannerHostController, context: Context) {}
}

/// Hosts the scanner as a child and starts it only once the view is on screen:
/// `startScanning()` before that point fails and the camera never comes up.
final class ScannerHostController: UIViewController, DataScannerViewControllerDelegate {
    private let onPayload: (String) -> Void
    private let onUnavailable: (String) -> Void
    private var reported = Set<String>()
    private let scanner = DataScannerViewController(
        recognizedDataTypes: [.barcode(symbologies: [.qr])],
        qualityLevel: .balanced,
        recognizesMultipleItems: false,
        isHighlightingEnabled: true)

    init(onPayload: @escaping (String) -> Void, onUnavailable: @escaping (String) -> Void) {
        self.onPayload = onPayload
        self.onUnavailable = onUnavailable
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        addChild(scanner)
        scanner.view.frame = view.bounds
        scanner.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(scanner.view)
        scanner.didMove(toParent: self)
        scanner.delegate = self
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !scanner.isScanning else { return }
        do {
            try scanner.startScanning()
        } catch {
            onUnavailable(String(describing: error))
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        scanner.stopScanning()
    }

    func dataScanner(
        _ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem],
        allItems: [RecognizedItem]
    ) {
        for case .barcode(let barcode) in addedItems {
            guard let payload = barcode.payloadStringValue, reported.insert(payload).inserted
            else { continue }
            onPayload(payload)
        }
    }

    func dataScanner(
        _ dataScanner: DataScannerViewController,
        becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable
    ) {
        onUnavailable(String(describing: error))
    }
}

/// The scanning screen: pushed onto Settings' navigation stack rather than
/// presented as a sheet — a modal on top of the Settings sheet, hosting a
/// camera, dismissed itself on the device; a push has nothing to collide with.
struct ScannerScreen: View {
    let onLink: (String) -> Void
    @State private var unavailable: String?

    var body: some View {
        ZStack(alignment: .bottom) {
            QRScannerView(
                onPayload: { payload in
                    // Anything else in view is not ours; keep looking.
                    guard PairingLink(string: payload) != nil else { return }
                    onLink(payload)
                },
                onUnavailable: { unavailable = $0 }
            )
            .ignoresSafeArea()

            if let unavailable {
                VStack(spacing: 8) {
                    Text("ios:settings.scanner.cameraUnavailable")
                        .font(.headline)
                    Text(verbatim: unavailable)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(.regularMaterial)
            } else {
                Text("ios:settings.scanner.hint")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(.regularMaterial)
            }
        }
        .navigationTitle("ios:settings.pairing.scanCode")
        .navigationBarTitleDisplayMode(.inline)
    }
}
