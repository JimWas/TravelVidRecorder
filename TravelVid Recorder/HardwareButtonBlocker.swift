import Foundation
import AVFoundation
import MediaPlayer
import UIKit

final class HardwareButtonBlocker: NSObject {

    static let shared = HardwareButtonBlocker()

    private var audioSession = AVAudioSession.sharedInstance()
    private var volumeView: MPVolumeView = MPVolumeView(frame: .zero)
    private var lastVolume: Float = 0.5
    private var slider: UISlider?

    override private init() {
        super.init()
        setup()
    }

    private func setup() {

        // Hide the MPVolumeView
        volumeView.alpha = 0.01
        
        // Add to window scene (iOS 15+ compatible)
        DispatchQueue.main.async {
            if #available(iOS 15.0, *) {
                // Use UIWindowScene for iOS 15+
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let window = windowScene.windows.first {
                    window.addSubview(self.volumeView)
                }
            } else {
                // Fallback for older iOS versions
                if let window = UIApplication.shared.windows.first {
                    window.addSubview(self.volumeView)
                }
            }
        }

        // Prepare audio session
        try? audioSession.setCategory(.ambient, options: [.mixWithOthers])
        try? audioSession.setActive(true)

        // Find slider inside MPVolumeView
        for sub in volumeView.subviews {
            if let s = sub as? UISlider {
                slider = s
                break
            }
        }

        // Save initial volume
        lastVolume = audioSession.outputVolume

        // Observe volume changes
        audioSession.addObserver(
            self,
            forKeyPath: "outputVolume",
            options: [.new],
            context: nil
        )
    }

    // MARK: - Volume Button Intercept (KVO)
    override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey : Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        guard keyPath == "outputVolume" else { return }

        // Silent haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()

        // Reset volume to previous level
        resetVolume()
    }

    private func resetVolume() {
        guard let slider else { return }
        slider.value = lastVolume
    }

    deinit {
        audioSession.removeObserver(self, forKeyPath: "outputVolume")
    }
}
