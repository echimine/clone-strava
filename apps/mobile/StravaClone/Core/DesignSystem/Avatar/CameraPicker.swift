import AVFoundation
import SwiftUI
import UIKit

/// The camera for "Prendre une photo" (ADR-037 §2), behind `NSCameraUsageDescription`.
enum CameraAccess {
    /// False on the simulator and on a device without a camera: the menu hides the choice.
    @MainActor static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    /// Asks iOS the first time; false once refused (or restricted).
    static func request() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: true
        case .notDetermined: await AVCaptureDevice.requestAccess(for: .video)
        default: false
        }
    }
}

/// iOS's camera screen; hands back the picture, or nil on "Annuler".
struct CameraPicker: UIViewControllerRepresentable {
    let finish: @MainActor (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraDevice = .front
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(finish: finish) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let finish: @MainActor (UIImage?) -> Void

        init(finish: @escaping @MainActor (UIImage?) -> Void) {
            self.finish = finish
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let image = info[.originalImage] as? UIImage
            MainActor.assumeIsolated { finish(image) }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            MainActor.assumeIsolated { finish(nil) }
        }
    }
}
