import SwiftUI
import AVKit

struct RecordingView: View {

    @ObservedObject var manager: RecordingManager
    let coverImage: UIImage?
    @Environment(\.dismiss) private var dismiss

    @State private var showFakePopup = false
    @State private var tapCounter = 0
    @State private var cornerTapCounter = 0
    @State private var lastTapTime = Date()
    @State private var isHolding = false
    @State private var holdTimer: Timer?
    @State private var fakePopupTimer: Timer?
    @State private var doubleTapDetected = false
    @State private var sessionFailed = false
    @State private var isPreparingSession = true

    var body: some View {

        ZStack {

            // DISPLAY BASED ON MODE
            switch manager.recordingDisplayMode {
            case .coverImage:
                // Fullscreen Cover Image
                if let img = coverImage {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .ignoresSafeArea(.all)
                } else {
                    Color.black.ignoresSafeArea(.all)
                }

            case .videoPlayback:
                // Looping Video Playback
                if let videoURL = manager.selectedVideoURL {
                    LoopingVideoPlayerView(videoURL: videoURL)
                } else {
                    Color.black.ignoresSafeArea(.all)
                }

            case .fakeCall:
                // Fake Calling Screen
                FakeCallingView(contactName: manager.fakeCallContactName)
                    .ignoresSafeArea(.all)

            case .tetris:
                // Tetris Game
                TetrisGameView()
                    .ignoresSafeArea(.all)

            case .flappyBird:
                // Flappy Bird Game
                FlappyBirdView()
                    .ignoresSafeArea(.all)

            case .bitcoin:
                // Bitcoin Price Tracker
                BitcoinPriceView()
                    .ignoresSafeArea(.all)

            case .calculator:
                // Calculator
                CalculatorView()
                    .ignoresSafeArea(.all)
            }

            // POPUP (only if enabled)
            let popupVisible = showFakePopup && manager.showFakePopups
            if popupVisible {
                Color.black.opacity(0.45)
                    .ignoresSafeArea(.all)

                fakeAlert
                    .zIndex(9999)
            }
            
            // Invisible corner tap zones (for corner tap gestures)
            if manager.stopGesture == .topLeftCorner || manager.stopGesture == .topRightCorner {
                cornerTapZones
            }

            // Recording indicator (configurable via Advanced Settings)
            if manager.showRecordingIndicator && !sessionFailed && !isPreparingSession {
                VStack {
                    HStack {
                        Spacer()
                        recordingIndicator
                            .padding(.top, 60)
                            .padding(.trailing, 16)
                    }
                    Spacer()
                }
                .zIndex(10000) // Ensure indicator is always on top
                .allowsHitTesting(false)
            }

            // Loading indicator while preparing session
            if isPreparingSession {
                Color.black.opacity(0.7)
                    .ignoresSafeArea()
                VStack(spacing: 20) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                    Text("Preparing Camera...")
                        .foregroundColor(.white)
                        .font(.headline)
                }
                .zIndex(10001)
            }

            // Error message if session failed
            if sessionFailed {
                Color.black.opacity(0.85)
                    .ignoresSafeArea()
                VStack(spacing: 20) {
                    Image(systemName: "video.slash.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.red)
                    Text("Camera Unavailable")
                        .font(.title2.bold())
                        .foregroundColor(.white)
                    Text("Unable to access the camera. Please check your permissions in Settings.")
                        .font(.body)
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    Button("Go Back") {
                        dismiss()
                    }
                    .padding(.horizontal, 40)
                    .padding(.vertical, 12)
                    .background(Color.white)
                    .foregroundColor(.blue)
                    .cornerRadius(10)
                    .padding(.top, 10)
                }
                .zIndex(10001)
            }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture(count: 1)
                .onEnded { _ in
                    guard manager.stopGesture == .fourTaps || manager.stopGesture == .fiveTaps else { return }
                    handleTap()
                }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 50)
                .onEnded { value in
                    guard shouldHandleStopGestures else { return }

                    switch manager.stopGesture {
                    case .swipeDown:
                        if value.translation.height > 100 && abs(value.translation.width) < 50 {
                            stopAndDismiss()
                        }
                    case .swipeLeft:
                        if value.translation.width < -100 && abs(value.translation.height) < 50 {
                            stopAndDismiss()
                        }
                    case .swipeRight:
                        if value.translation.width > 100 && abs(value.translation.height) < 50 {
                            stopAndDismiss()
                        }
                    default:
                        break
                    }
                }
        )
        .simultaneousGesture(
            LongPressGesture(minimumDuration: Double(manager.holdDuration))
                .onEnded { _ in
                    guard manager.stopGesture == .doubleTapHold, shouldHandleStopGestures else { return }
                    stopAndDismiss()
                }
        )
        .onAppear {
            _ = HardwareButtonBlocker.shared  // Activate volume blocker

            Task {
                isPreparingSession = true
                sessionFailed = false

                let ok = await manager.prepareSession()

                await MainActor.run {
                    isPreparingSession = false

                    if ok {
                        manager.startRecording()
                        if manager.showFakePopups {
                            startFakePopupTimer()
                        }
                    } else {
                        // Session preparation failed - show error
                        sessionFailed = true
                    }
                }
            }
        }
        .onChange(of: manager.showFakePopups) {
            if !manager.showFakePopups {
                stopFakePopupTimer()
                showFakePopup = false
            } else if manager.isRecording {
                startFakePopupTimer()
            }
        }
        .onDisappear {
            holdTimer?.invalidate()
            stopFakePopupTimer()
            if manager.isRecording {
                manager.stopRecording()
            } else {
                // Ensure location tracking stops if we prepared the session but didn't record
                LocationManager.shared.stopTracking()
            }
        }
    }

    private var shouldHandleStopGestures: Bool {
        !(showFakePopup && manager.showFakePopups) && !sessionFailed && !isPreparingSession
    }
    
    // MARK: - Recording Indicator
    // Clearly shows video and audio are being recorded
    @State private var indicatorPulse = false

    private var recordingIndicator: some View {
        HStack(spacing: 10) {
            // Animated pulsing red dot
            Circle()
                .fill(Color.red)
                .frame(width: 16, height: 16)
                .overlay(
                    Circle()
                        .stroke(Color.red, lineWidth: 3)
                        .scaleEffect(indicatorPulse ? 2.0 : 1.0)
                        .opacity(indicatorPulse ? 0 : 0.8)
                        .animation(
                            .easeOut(duration: 1.0).repeatForever(autoreverses: false),
                            value: indicatorPulse
                        )
                )

            // Video recording icon
            Image(systemName: "video.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)

            // Audio recording icon
            Image(systemName: "mic.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)

            Text("REC")
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(Color.red.opacity(0.85))
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.5), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.6), radius: 6, x: 0, y: 3)
        .onAppear {
            indicatorPulse = true
        }
    }

    // MARK: - Corner Tap Zones
    private var cornerTapZones: some View {
        ZStack {
            // Top-left corner
            if manager.stopGesture == .topLeftCorner {
                Color.clear
                    .frame(width: 100, height: 100)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        handleCornerTap()
                    }
                    .position(x: 50, y: 50)
            }
            
            // Top-right corner
            if manager.stopGesture == .topRightCorner {
                GeometryReader { geo in
                    Color.clear
                        .frame(width: 100, height: 100)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            handleCornerTap()
                        }
                        .position(x: geo.size.width - 50, y: 50)
                }
            }
        }
        .allowsHitTesting(true)
    }
    
    // MARK: - Tap Handlers
    private func handleTap() {
        guard shouldHandleStopGestures else { return }
        let now = Date()
        
        // Reset counter if too much time has passed (more than 2 seconds)
        if now.timeIntervalSince(lastTapTime) > 2.0 {
            tapCounter = 0
        }
        
        lastTapTime = now
        tapCounter += 1
        
        let requiredTaps = manager.stopGesture == .fiveTaps ? 5 : 4
        
        if tapCounter >= requiredTaps {
            tapCounter = 0
            stopAndDismiss()
        }
    }
    
    private func handleCornerTap() {
        guard shouldHandleStopGestures else { return }
        let now = Date()
        
        // Reset counter if too much time has passed
        if now.timeIntervalSince(lastTapTime) > 2.0 {
            cornerTapCounter = 0
        }
        
        lastTapTime = now
        cornerTapCounter += 1
        
        if cornerTapCounter >= 5 {
            cornerTapCounter = 0
            stopAndDismiss()
        }
    }

    // MARK: - Popup Loop
    private func startFakePopupTimer() {
        stopFakePopupTimer()

        let timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            Task { @MainActor in
                guard manager.showFakePopups, manager.isRecording, !showFakePopup else { return }
                withAnimation(.spring()) {
                    showFakePopup = true
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        fakePopupTimer = timer
    }

    private func stopFakePopupTimer() {
        fakePopupTimer?.invalidate()
        fakePopupTimer = nil
    }

    private func stopAndDismiss() {
        manager.stopRecording()

        // Show interstitial ad after recording ends
        AdMobManager.shared.showInterstitialAd {
            // After ad is dismissed (or failed), dismiss the recording view
            dismiss()
        }
    }

    // MARK: - Storage Alert UI
    private var fakeAlert: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 52))
                .foregroundColor(.yellow)

            Text("iPhone Storage Full")
                .font(.title3.bold())
                .foregroundColor(.white)

            Text("You can manage your storage in Settings.")
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .frame(width: 240)

            Button("OK") {
                withAnimation { showFakePopup = false }
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.95))
            .foregroundColor(.blue)
            .cornerRadius(10)

        }
        .padding(28)
        .background(.ultraThinMaterial)
        .cornerRadius(20)
        .shadow(radius: 25)
    }
}
