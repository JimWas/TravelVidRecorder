import SwiftUI
import AVFoundation
import Photos

struct OnboardingView: View {
    @Binding var isPresented: Bool
    let stopGesture: StopRecordingGesture

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @StateObject private var locationManager = LocationManager.shared

    @State private var step = 0
    @State private var cameraStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var micStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    @State private var photosStatus: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)

    private let totalSteps = 4

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                TabView(selection: $step) {
                    introStep
                        .tag(0)
                    cameraMicStep
                        .tag(1)
                    photosLocationStep
                        .tag(2)
                    stopTutorialStep
                        .tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))

                footer
            }
        }
        .onAppear {
            refreshStatuses()
        }
        .onChange(of: locationManager.authorizationStatus) {
            refreshStatuses()
        }
    }

    private var introStep: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "video.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.blue)

            Text("Welcome to TravelVid Recorder")
                .font(.title.bold())
                .multilineTextAlignment(.center)

            Text("Record reliably while staying focused. We'll walk you through permissions and how to stop recording.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            VStack(alignment: .leading, spacing: 10) {
                featureRow(icon: "checkmark.seal.fill", title: "Clear recording status")
                featureRow(icon: "lock.shield.fill", title: "Safe, segmented recordings")
                featureRow(icon: "hand.tap.fill", title: "Hidden stop gesture")
            }
            .padding(.horizontal, 28)
            .padding(.top, 8)

            Spacer()
        }
    }

    private var cameraMicStep: some View {
        VStack(spacing: 18) {
            Spacer()
            Text("Camera & Microphone")
                .font(.title.bold())

            Text("These are required to record video and audio.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

            permissionRow(
                title: "Camera",
                status: statusText(for: cameraStatus),
                isGranted: cameraStatus == .authorized,
                actionTitle: "Continue",
                action: requestCamera
            )

            permissionRow(
                title: "Microphone",
                status: statusText(for: micStatus),
                isGranted: micStatus == .authorized,
                actionTitle: "Continue",
                action: requestMicrophone
            )

            Text("You can change permissions any time in Settings.")
                .font(.footnote)
                .foregroundColor(.secondary)
                .padding(.top, 8)

            Spacer()
        }
        .padding(.horizontal, 24)
    }

    private var photosLocationStep: some View {
        VStack(spacing: 18) {
            Spacer()
            Text("Photos & Location")
                .font(.title.bold())

            Text("Photos lets you export recordings. Location adds optional GPS tags.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

            permissionRow(
                title: "Photos",
                status: statusText(for: photosStatus),
                isGranted: photosStatus == .authorized || photosStatus == .limited,
                actionTitle: "Continue",
                action: requestPhotos
            )

            permissionRow(
                title: "Location (Optional)",
                status: locationStatusText,
                isGranted: locationManager.authorizationStatus == .authorizedAlways || locationManager.authorizationStatus == .authorizedWhenInUse,
                actionTitle: "Continue",
                action: requestLocation
            )

            Spacer()
        }
        .padding(.horizontal, 24)
    }

    private var stopTutorialStep: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("How to Stop Recording")
                .font(.title.bold())

            Text(stopGestureTitle)
                .font(.headline)
                .padding(.top, 6)

            Text(stopGestureDescription)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

            VStack(alignment: .leading, spacing: 8) {
                featureRow(icon: "hand.raised.fill", title: "Stop gesture can be changed on the main screen")
                featureRow(icon: "eye.slash.fill", title: "Gestures are designed to stay discreet")
            }
            .padding(.top, 8)

            Spacer()
        }
        .padding(.horizontal, 24)
    }

    private var footer: some View {
        VStack(spacing: 12) {
            Text("Step \(step + 1) of \(totalSteps)")
                .font(.footnote)
                .foregroundColor(.secondary)

            HStack(spacing: 12) {
                Button("Back") {
                    step = max(0, step - 1)
                }
                .buttonStyle(.bordered)
                .disabled(step == 0)

                Spacer()

                if step < totalSteps - 1 {
                    Button("Next") {
                        step = min(totalSteps - 1, step + 1)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Finish") {
                        hasCompletedOnboarding = true
                        isPresented = false
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .padding(.top, 8)
        .background(Color(uiColor: .secondarySystemBackground))
    }

    private func featureRow(icon: String, title: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(.blue)
            Text(title)
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func permissionRow(title: String, status: String, isGranted: Bool, actionTitle: String, action: @escaping () -> Void) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(status)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(actionTitle) {
                action()
            }
            .buttonStyle(.bordered)
            .disabled(isGranted)
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(12)
    }

    private func requestCamera() {
        AVCaptureDevice.requestAccess(for: .video) { _ in
            DispatchQueue.main.async {
                refreshStatuses()
            }
        }
    }

    private func requestMicrophone() {
        AVCaptureDevice.requestAccess(for: .audio) { _ in
            DispatchQueue.main.async {
                refreshStatuses()
            }
        }
    }

    private func requestPhotos() {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { _ in
            DispatchQueue.main.async {
                refreshStatuses()
            }
        }
    }

    private func requestLocation() {
        locationManager.requestPermission()
        refreshStatuses()
    }

    private func refreshStatuses() {
        cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        photosStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    private func statusText(for status: AVAuthorizationStatus) -> String {
        switch status {
        case .authorized:
            return "Allowed"
        case .denied:
            return "Denied"
        case .restricted:
            return "Restricted"
        case .notDetermined:
            return "Not yet requested"
        @unknown default:
            return "Unknown"
        }
    }

    private func statusText(for status: PHAuthorizationStatus) -> String {
        switch status {
        case .authorized:
            return "Allowed"
        case .limited:
            return "Limited"
        case .denied:
            return "Denied"
        case .restricted:
            return "Restricted"
        case .notDetermined:
            return "Not yet requested"
        @unknown default:
            return "Unknown"
        }
    }

    private var locationStatusText: String {
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return "Allowed"
        case .denied:
            return "Denied"
        case .restricted:
            return "Restricted"
        case .notDetermined:
            return "Not yet requested"
        @unknown default:
            return "Unknown"
        }
    }

    private var stopGestureTitle: String {
        switch stopGesture {
        case .fourTaps:
            return "4 taps anywhere"
        case .fiveTaps:
            return "5 taps anywhere"
        case .swipeDown:
            return "Swipe down"
        case .swipeLeft:
            return "Swipe left"
        case .swipeRight:
            return "Swipe right"
        case .topLeftCorner:
            return "5 taps in the top-left corner"
        case .topRightCorner:
            return "5 taps in the top-right corner"
        case .doubleTapHold:
            return "Tap and hold"
        case .volumeUp:
            return "Double-press vol up"
        case .volumeDown:
            return "Double-press vol down"
        }
    }

    private var stopGestureDescription: String {
        switch stopGesture {
        case .fourTaps:
            return "Tap anywhere 4 times to stop. Keep taps quick and close together."
        case .fiveTaps:
            return "Tap anywhere 5 times to stop. Keep taps quick and close together."
        case .swipeDown:
            return "Swipe down with a short, firm gesture to stop recording."
        case .swipeLeft:
            return "Swipe left with a short, firm gesture to stop recording."
        case .swipeRight:
            return "Swipe right with a short, firm gesture to stop recording."
        case .topLeftCorner:
            return "Tap the top-left corner 5 times to stop recording."
        case .topRightCorner:
            return "Tap the top-right corner 5 times to stop recording."
        case .doubleTapHold:
            return "Tap and hold for the configured duration to stop recording."
        case .volumeUp:
            return "Press volume up twice quickly (within 1 second) to stop recording."
        case .volumeDown:
            return "Press volume down twice quickly (within 1 second) to stop recording."
        }
    }
}
