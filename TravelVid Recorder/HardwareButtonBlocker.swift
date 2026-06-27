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

    /// When set, two quick presses of volume-up fires onVolumeUp; two quick presses of
    /// volume-down fires onVolumeDown. Single presses are blocked silently as normal.
    var onVolumeUp: (() -> Void)?
    var onVolumeDown: (() -> Void)?

    private let doublePressWindow: TimeInterval = 1.0
    private var lastUpPressTime: Date?
    private var lastDownPressTime: Date?

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
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let window = windowScene.windows.first {
                    window.addSubview(self.volumeView)
                }
            } else {
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
        guard keyPath == "outputVolume",
              let newVolume = change?[.newKey] as? Float else { return }

        let isUp = newVolume > lastVolume

        // Always reset volume so the HUD never shows
        resetVolume()

        let now = Date()

        if isUp {
            if let last = lastUpPressTime, now.timeIntervalSince(last) <= doublePressWindow {
                // Second press within window — fire and reset
                lastUpPressTime = nil
                onVolumeUp?()
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
            } else {
                // First press — record time, light feedback
                lastUpPressTime = now
                lastDownPressTime = nil
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
            }
        } else {
            if let last = lastDownPressTime, now.timeIntervalSince(last) <= doublePressWindow {
                lastDownPressTime = nil
                onVolumeDown?()
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
            } else {
                lastDownPressTime = now
                lastUpPressTime = nil
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
            }
        }
    }

    private func resetVolume() {
        guard let slider else { return }
        slider.value = lastVolume
    }

    func clearCallbacks() {
        onVolumeUp = nil
        onVolumeDown = nil
        lastUpPressTime = nil
        lastDownPressTime = nil
    }

    deinit {
        audioSession.removeObserver(self, forKeyPath: "outputVolume")
    }
}
