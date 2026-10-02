import AVFoundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// What Take Photo does about the camera's permission: open it, let the system ask (the first time only — a refusal
/// there is the system's own answer), or, once refused, explain and point to Settings.
enum CameraAccess: Equatable {
    case open, ask, explain

    static func decision(for status: AVAuthorizationStatus) -> CameraAccess {
        switch status {
        case .authorized: .open
        case .notDetermined: .ask
        default: .explain
        }
    }
}

/// The system camera: SwiftUI has no camera view, so UIKit's picker. Hands back the photo as full-quality JPEG (its
/// orientation kept in the EXIF), or nil when cancelled; `ComposerPicture` downscales it like any picked picture.
struct CameraPicker: UIViewControllerRepresentable {
    let onFinish: (Data?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.image.identifier]
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    @MainActor
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (Data?) -> Void

        init(onFinish: @escaping (Data?) -> Void) {
            self.onFinish = onFinish
        }

        func imagePickerController(
            _ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            onFinish((info[.originalImage] as? UIImage)?.jpegData(compressionQuality: 1))
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish(nil)
        }
    }
}
