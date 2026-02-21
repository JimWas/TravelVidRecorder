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

    @Environment(\.scenePhase) var scenePhase
    @State private var isInactive = false

    var body: some Scene {
        WindowGroup {
            ZStack {
                MainView()
                    .preferredColorScheme(.light)
                
                // Privacy Mask for Stealth: Hide app content in switcher
                if isInactive {
                    Color.black
                        .ignoresSafeArea()
                        .zIndex(99999)
                }
            }
            .task {
                await requestTrackingPermission()
            }
            .onChange(of: scenePhase, initial: false) { _, newPhase in
                switch newPhase {
                case .inactive, .background:
                    isInactive = true
                case .active:
                    isInactive = false
                @unknown default:
                    break
                }
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

        // AdMob now initializes lazily when an ad is first requested.
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
