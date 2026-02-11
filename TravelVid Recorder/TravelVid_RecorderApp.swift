import SwiftUI
import AVFoundation
import AppTrackingTransparency
import StoreKit

@main
struct TravelVid_RecorderApp: App {

    // Start subscription transaction listener early
    @StateObject private var subscriptionManager = SubscriptionManager.shared

    // Create an init to set up global things on launch
    init() {
        // Configure Audio Session (Important for video recording)
        // Note: AdMob initialization moved to after ATT request
        setupAudioSession()
    }

    var body: some Scene {
        WindowGroup {
            MainView()
                .preferredColorScheme(.light) // Optional: Keep app in light mode
                .task {
                    await requestTrackingPermission()
                }
        }
    }

    private func requestTrackingPermission() async {
        // Wait for app to be fully active
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay

        // Check current status first
        let currentStatus = ATTrackingManager.trackingAuthorizationStatus

        if currentStatus == .notDetermined {
            // Request permission - this will show the popup
            await ATTrackingManager.requestTrackingAuthorization()
        }

        // Initialize AdMob after ATT (regardless of user's choice)
        await MainActor.run {
            AdMobManager.shared.initializeAdMob()
        }
    }

    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            // Allow mixing (so music doesn't stop) and default to speaker
            try session.setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetoothA2DP, .mixWithOthers])
            try session.setActive(true)
        } catch {
            print("Failed to set up audio session: \(error)")
        }
    }
}
