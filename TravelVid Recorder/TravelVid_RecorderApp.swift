import SwiftUI
import AVFoundation

@main
struct TravelVid_RecorderApp: App {
    
    // Create an init to set up global things on launch
    init() {
        // 1. Initialize AdMob
        AdMobManager.shared.initializeAdMob()
        
        // 2. Configure Audio Session (Important for video recording)
        setupAudioSession()
    }

    var body: some Scene {
        WindowGroup {
            MainView()
                .preferredColorScheme(.light) // Optional: Keep app in light mode
        }
    }
    
    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            // Allow mixing (so music doesn't stop) and default to speaker
            try session.setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers])
            try session.setActive(true)
        } catch {
            print("Failed to set up audio session: \(error)")
        }
    }
}
