import SwiftUI
import AVKit

/// Volume-button trigger (iOS 17.2+ `AVCaptureEventInteraction`): the primary volume action is a Settings choice.
struct VolumeButtonObserver: UIViewControllerRepresentable {
    let onPress: (Bool) -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        let vc = UIViewController()
        vc.view.isUserInteractionEnabled = false
        if #available(iOS 17.2, *) {
            let interaction = AVCaptureEventInteraction { event in
                if event.phase == .began { DispatchQueue.main.async { onPress(true) } }
            }
            vc.view.addInteraction(interaction)
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}
