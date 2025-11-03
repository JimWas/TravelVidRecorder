import SwiftUI
import UIKit

struct RecordingView: View {
    @ObservedObject var manager: RecordingManager
    let coverImage: UIImage?
    @Environment(\.dismiss) private var dismiss

    @State private var dragOffset: CGSize = .zero
    @State private var showStopOverlay = false
    @State private var showHint = false
    @State private var isStopping = false
    @State private var showFakeStorageAlert = false

    var body: some View {
        ZStack(alignment: .topLeading) {

            // MARK: - Background
            if let image = coverImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
            }

            // MARK: - Timer Overlay
            if manager.isRecording {
                VStack {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)

                        Text(timeString(from: manager.currentDuration))
                            .font(.title3.monospacedDigit())
                            .bold()
                            .foregroundColor(.white)

                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 50)

                    Spacer()
                }
                .transition(.opacity)
                .animation(.easeInOut, value: manager.isRecording)
            }

            // MARK: - Hint Overlay
            if showHint {
                VStack {
                    Spacer()
                    Text("⬇︎ Swipe down, triple tap, or tap top-left to stop")
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 14)
                        .background(Color.black.opacity(0.4))
                        .cornerRadius(12)
                        .shadow(radius: 4)
                        .transition(.opacity)
                        .padding(.bottom, 80)
                }
                .animation(.easeInOut(duration: 0.5), value: showHint)
            }

            // MARK: - Stop Overlay
            if showStopOverlay {
                VStack {
                    Text("Recording Stopped")
                        .font(.headline)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 20)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(14)
                        .foregroundColor(.white)
                        .shadow(radius: 10)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.scale)
            }

            // MARK: - Hot Corner to Stop
            Button {
                if manager.isRecording { stopFlow() }
            } label: {
                Color.clear
                    .frame(width: 80, height: 80)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 40)
            .padding(.leading, 10)

            // MARK: - Fake System Alert Overlay
            if showFakeStorageAlert {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onAppear {
                        let generator = UINotificationFeedbackGenerator()
                        generator.notificationOccurred(.error)
                    }

                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.yellow)

                    Text("iPhone Storage Full")
                        .font(.title3.bold())
                        .foregroundColor(.white)

                    Text("You can manage your storage in Settings.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 220)

                    Button("OK") {
                        withAnimation(.easeInOut) { showFakeStorageAlert = false }
                    }
                    .font(.headline)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.9))
                    .foregroundColor(.blue)
                    .cornerRadius(8)
                }
                .padding(30)
                .background(.ultraThinMaterial)
                .cornerRadius(20)
                .shadow(radius: 20)
                .transition(.scale)
            }
        }

        // MARK: - Gestures
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    if value.translation.height > 80,
                       abs(value.translation.width) < 60,
                       manager.isRecording {
                        stopFlow()
                    }
                }
        )
        .simultaneousGesture(
            TapGesture(count: 3)
                .onEnded { if manager.isRecording { stopFlow() } }
        )

        // MARK: - Lifecycle
        .onAppear {
            provideFeedback(.started)
            showRecordingHint()

            if !manager.isRecording {
                manager.startRecording()
            }

            // Trigger fake alert after short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                withAnimation(.spring()) { showFakeStorageAlert = true }
            }
        }
        .onDisappear {
            if manager.isRecording {
                manager.stopRecording(autoSave: true)
            }
        }
        .onChange(of: manager.isRecording) { newValue in
            if !newValue {
                provideFeedback(.stopped)
                withAnimation(.spring()) { showStopOverlay = false }
                cleanupAndDismiss()
            }
        }
        .animation(.easeInOut, value: manager.isRecording)
    }

    // MARK: - Stop Flow
    private func stopFlow() {
        guard !isStopping else { return }
        isStopping = true

        withAnimation(.spring()) {
            showStopOverlay = true
        }
        provideFeedback(.stopped)

        manager.stopRecording(autoSave: true)
    }

    private func cleanupAndDismiss() {
        isStopping = false
        dismiss()
    }

    // MARK: - Hint
    private func showRecordingHint() {
        withAnimation(.easeInOut(duration: 0.5)) { showHint = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation(.easeInOut(duration: 0.5)) { showHint = false }
        }
    }

    // MARK: - Haptics / Util
    private func provideFeedback(_ type: FeedbackType) {
        let gen = UINotificationFeedbackGenerator()
        gen.prepare()
        switch type {
        case .started: gen.notificationOccurred(.success)
        case .stopped: gen.notificationOccurred(.warning)
        }
    }

    private func timeString(from t: TimeInterval) -> String {
        let m = Int(t) / 60
        let s = Int(t) % 60
        return String(format: "%02d:%02d", m, s)
    }

    enum FeedbackType { case started, stopped }
}
