import SwiftUI
import AVFoundation
import AVKit
import Photos

struct VideoTrimmerView: View {
    let recording: Recording
    let onExport: (URL) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var player: AVPlayer?
    @State private var startFraction: Double = 0.0
    @State private var endFraction: Double = 1.0
    @State private var isExporting = false
    @State private var exportError: String?
    @State private var showErrorAlert = false
    @State private var timelineWidth: CGFloat = 0

    private var videoDuration: Double {
        recording.duration > 0 ? recording.duration : 1
    }

    private var startTime: Double { startFraction * videoDuration }
    private var endTime: Double { endFraction * videoDuration }
    private var trimmedDuration: Double { endTime - startTime }

    // Minimum 1 second window expressed as a fraction
    private var minimumFraction: Double { 1.0 / videoDuration }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Video player
                    if let player {
                        VideoPlayer(player: player)
                            .aspectRatio(16 / 9, contentMode: .fit)
                            .background(Color.black)
                            .padding(.top, 8)
                    } else {
                        Rectangle()
                            .fill(Color(white: 0.1))
                            .aspectRatio(16 / 9, contentMode: .fit)
                            .overlay(
                                ProgressView()
                                    .tint(.white)
                            )
                            .padding(.top, 8)
                    }

                    Spacer(minLength: 16)

                    // Trim timeline
                    VStack(spacing: 12) {
                        TrimTimelineView(
                            startFraction: $startFraction,
                            endFraction: $endFraction,
                            minimumFraction: minimumFraction,
                            onStartChanged: { seekPlayer(to: startTime) }
                        )
                        .frame(height: 44)
                        .padding(.horizontal, 16)

                        // Time labels
                        HStack {
                            Text(formatTime(startTime))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.white)
                            Spacer()
                            Text(formatTime(endTime))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 20)

                        // Duration indicator
                        Text("Duration: \(formatTime(trimmedDuration))")
                            .font(.subheadline)
                            .foregroundStyle(Color(white: 0.7))
                    }
                    .padding(.bottom, 24)
                }

                // Export loading overlay
                if isExporting {
                    Color.black.opacity(0.6)
                        .ignoresSafeArea()

                    VStack(spacing: 16) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(1.4)
                            .tint(.white)
                        Text("Exporting…")
                            .font(.headline)
                            .foregroundStyle(.white)
                    }
                    .padding(32)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
            .navigationTitle("Trim Video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        player?.pause()
                        dismiss()
                    }
                    .foregroundStyle(.white)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        exportTrimmedVideo()
                    } label: {
                        if isExporting {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .scaleEffect(0.75)
                                    .tint(.white)
                                Text("Export")
                            }
                        } else {
                            Text("Export")
                        }
                    }
                    .disabled(isExporting)
                    .foregroundStyle(isExporting ? Color(white: 0.5) : .blue)
                }
            }
            .alert("Export Failed", isPresented: $showErrorAlert, presenting: exportError) { _ in
                Button("OK", role: .cancel) {}
            } message: { error in
                Text(error)
            }
            .onAppear {
                setupPlayer()
            }
            .onDisappear {
                player?.pause()
            }
        }
    }

    // MARK: - Player setup

    private func setupPlayer() {
        let asset = AVURLAsset(url: recording.url)
        let item = AVPlayerItem(asset: asset)
        let avPlayer = AVPlayer(playerItem: item)
        avPlayer.isMuted = false
        player = avPlayer
        avPlayer.play()
    }

    private func seekPlayer(to time: Double) {
        guard let player else { return }
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    // MARK: - Export

    private func exportTrimmedVideo() {
        isExporting = true

        let asset = AVURLAsset(url: recording.url)
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("trimmed-\(UUID().uuidString).mov")

        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            DispatchQueue.main.async {
                isExporting = false
                exportError = "Could not create export session."
                showErrorAlert = true
            }
            return
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mov

        let start = CMTime(seconds: startTime, preferredTimescale: 600)
        let duration = CMTime(seconds: trimmedDuration, preferredTimescale: 600)
        exportSession.timeRange = CMTimeRange(start: start, duration: duration)

        exportSession.exportAsynchronously {
            DispatchQueue.main.async {
                isExporting = false
                switch exportSession.status {
                case .completed:
                    player?.pause()
                    onExport(outputURL)
                    dismiss()
                case .failed:
                    exportError = exportSession.error?.localizedDescription
                        ?? "Export failed for an unknown reason."
                    showErrorAlert = true
                case .cancelled:
                    exportError = "Export was cancelled."
                    showErrorAlert = true
                default:
                    exportError = "Unexpected export status."
                    showErrorAlert = true
                }
            }
        }
    }

    // MARK: - Helpers

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && !seconds.isNaN else { return "0:00" }
        let total = Int(max(0, seconds))
        let m = total / 60
        let s = total % 60
        return "\(m):\(String(format: "%02d", s))"
    }
}

// MARK: - Trim Timeline

private struct TrimTimelineView: View {
    @Binding var startFraction: Double
    @Binding var endFraction: Double
    let minimumFraction: Double
    let onStartChanged: () -> Void

    // Track drag start values so we apply deltas, not raw positions
    @State private var dragStartStart: Double? = nil
    @State private var dragEndStart: Double? = nil

    private let trackHeight: CGFloat = 6
    private let handleWidth: CGFloat = 4
    private let handleHeight: CGFloat = 44

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width

            ZStack(alignment: .leading) {
                // Full track background
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(white: 0.25))
                    .frame(height: trackHeight)
                    .frame(maxHeight: .infinity)

                // Selected range highlight
                let leftX = startFraction * width
                let rightX = endFraction * width
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.blue.opacity(0.8))
                    .frame(width: max(0, rightX - leftX), height: trackHeight)
                    .frame(maxHeight: .infinity)
                    .offset(x: leftX)

                // Start handle
                handleView()
                    .offset(x: max(0, startFraction * width - handleWidth / 2))
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if dragStartStart == nil {
                                    dragStartStart = startFraction
                                }
                                let base = dragStartStart ?? startFraction
                                let delta = value.translation.width / width
                                let newVal = (base + delta).clamped(
                                    to: 0...max(0, endFraction - minimumFraction)
                                )
                                if newVal != startFraction {
                                    startFraction = newVal
                                    onStartChanged()
                                }
                            }
                            .onEnded { _ in
                                dragStartStart = nil
                            }
                    )

                // End handle
                handleView()
                    .offset(x: min(width - handleWidth, endFraction * width - handleWidth / 2))
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if dragEndStart == nil {
                                    dragEndStart = endFraction
                                }
                                let base = dragEndStart ?? endFraction
                                let delta = value.translation.width / width
                                let newVal = (base + delta).clamped(
                                    to: min(1, startFraction + minimumFraction)...1
                                )
                                endFraction = newVal
                            }
                            .onEnded { _ in
                                dragEndStart = nil
                            }
                    )
            }
            .frame(maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func handleView() -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(.white)
                .frame(width: handleWidth + 16, height: handleHeight)
                .shadow(color: .black.opacity(0.4), radius: 3, x: 0, y: 1)

            // Grip lines
            VStack(spacing: 3) {
                ForEach(0..<3) { _ in
                    Capsule()
                        .fill(Color(white: 0.45))
                        .frame(width: 2, height: 6)
                }
            }
        }
        .frame(width: handleWidth + 16, height: handleHeight)
        // Expand hit area without changing visual size
        .contentShape(Rectangle().size(width: handleWidth + 32, height: handleHeight + 16))
    }
}

// MARK: - Comparable clamping

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
