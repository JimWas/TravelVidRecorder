import SwiftUI

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
    @State private var doubleTapDetected = false

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
                
            case .tetris:
                // Tetris Game
                TetrisGameView()
                    .ignoresSafeArea(.all)
                
            case .flappyBird:
                // Flappy Bird Game
                FlappyBirdView()
                    .ignoresSafeArea(.all)
            }

            // POPUP (only if enabled)
            if showFakePopup && manager.showFakePopups {
                Color.black.opacity(0.45)
                    .ignoresSafeArea(.all)

                fakeAlert
                    .zIndex(9999)
            }
            
            // Invisible corner tap zones (for corner tap gestures)
            if manager.stopGesture == .topLeftCorner || manager.stopGesture == .topRightCorner {
                cornerTapZones
            }
        }
        .contentShape(Rectangle())
        .applyStopGestures(manager: manager,
                          showFakePopup: showFakePopup,
                          onTap: handleTap,
                          onStop: stopAndDismiss)
        .onAppear {
            _ = HardwareButtonBlocker.shared  // Activate volume blocker

            Task {
                let ok = await manager.prepareSession()
                if ok {
                    manager.startRecording()
                    if manager.showFakePopups {
                        showFakePopupsForever()
                    }
                }
            }
        }
        .onDisappear {
            holdTimer?.invalidate()
            if manager.isRecording {
                manager.stopRecording()
            }
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
    private func showFakePopupsForever() {
        // Schedule popups more safely to avoid integer overflow
        let maxPopups = 1000 // Reasonable limit instead of 9999
        
        for i in 0..<maxPopups {
            let delay = Double(i) * 2.0
            
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.spring()) {
                    self.showFakePopup = true
                }
            }
        }
    }

    private func stopAndDismiss() {
        manager.stopRecording()
        dismiss()
    }

    // MARK: - Fake Alert UI
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

// MARK: - Gesture View Modifier
struct StopGestureModifier: ViewModifier {
    @ObservedObject var manager: RecordingManager
    let showFakePopup: Bool
    let onTap: () -> Void
    let onStop: () -> Void
    
    func body(content: Content) -> some View {
        switch manager.stopGesture {
        case .fourTaps, .fiveTaps:
            content
                .simultaneousGesture(
                    TapGesture(count: 1)
                        .onEnded { _ in
                            if !showFakePopup {
                                onTap()
                            }
                        }
                )
            
        case .swipeDown:
            content
                .simultaneousGesture(
                    DragGesture(minimumDistance: 50)
                        .onEnded { value in
                            if value.translation.height > 100 && abs(value.translation.width) < 50 {
                                onStop()
                            }
                        }
                )
            
        case .swipeLeft:
            content
                .simultaneousGesture(
                    DragGesture(minimumDistance: 50)
                        .onEnded { value in
                            if value.translation.width < -100 && abs(value.translation.height) < 50 {
                                onStop()
                            }
                        }
                )
            
        case .swipeRight:
            content
                .simultaneousGesture(
                    DragGesture(minimumDistance: 50)
                        .onEnded { value in
                            if value.translation.width > 100 && abs(value.translation.height) < 50 {
                                onStop()
                            }
                        }
                )
            
        case .topLeftCorner, .topRightCorner:
            // Corner taps are handled with invisible tap zones
            content
            
        case .doubleTapHold:
            content
                .simultaneousGesture(
                    TapGesture(count: 2)
                        .onEnded { _ in
                            // Trigger hold check after double tap
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                // Will check if user is still holding
                            }
                        }
                )
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 2.0)
                        .onEnded { _ in
                            onStop()
                        }
                )
        }
    }
}

extension View {
    func applyStopGestures(manager: RecordingManager,
                          showFakePopup: Bool,
                          onTap: @escaping () -> Void,
                          onStop: @escaping () -> Void) -> some View {
        self.modifier(StopGestureModifier(manager: manager,
                                         showFakePopup: showFakePopup,
                                         onTap: onTap,
                                         onStop: onStop))
    }
}
