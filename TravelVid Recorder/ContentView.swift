import SwiftUI
import AVFoundation
import Photos
import PhotosUI
import UIKit

struct ContentView: View {
    @ObservedObject var manager: RecordingManager

    @State private var showControls = true
    @State private var showSettings = false

    @AppStorage("coverImageData") private var coverImageData: Data?
    @AppStorage("defaultResolution") private var defaultResolutionString = Resolution.p1080.rawValue
    @AppStorage("defaultAudio") private var defaultAudio = true
    @AppStorage("autoSave") private var autoSave = true

    // Computed
    var coverImage: UIImage? {
        guard let data = coverImageData else { return nil }
        return UIImage(data: data)
    }

    var defaultResolution: Resolution {
        Resolution(rawValue: defaultResolutionString) ?? .p1080
    }

    var body: some View {
        NavigationView {
            ZStack {
                backgroundView
                if manager.isRecording { recordingIndicator }
                mainInterface
            }
            .navigationTitle("TravelVid Recorder")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Settings") { showSettings = true }
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .onTapGesture {
                showControls = true
                hideControlsAfterDelay()
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(
                    coverImageData: $coverImageData,
                    defaultResolutionString: $defaultResolutionString,
                    defaultAudio: $defaultAudio,
                    autoSave: $autoSave
                )
            }
            .onAppear(perform: onAppear)
            .onChange(of: manager.isRecording, perform: handleRecordingChange)
        }
    }

    // MARK: - Subviews
    private var backgroundView: some View {
        Group {
            if let image = coverImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                    .blur(radius: manager.isRecording ? 1.5 : 0)
                    .animation(.easeInOut, value: manager.isRecording)
            } else {
                Color.black.ignoresSafeArea()
            }
        }
    }

    private var recordingIndicator: some View {
        Circle()
            .fill(Color.red)
            .frame(width: 10, height: 10)
            .position(x: 25, y: 50)
    }

    private var mainInterface: some View {
        VStack {
            Spacer()
            if showControls { controlPanel.transition(.move(edge: .bottom)) }
            if !manager.recordings.isEmpty { recordingsList }
        }
    }

    private var controlPanel: some View {
        VStack(spacing: 20) {
            Text(timeString(from: manager.currentDuration))
                .font(.title2.monospacedDigit())
                .foregroundColor(.white)
                .bold()

            controlButtons

            if manager.selectedResolution != .p4K {
                lensPicker
            }

            Toggle("Audio", isOn: $manager.audioOn)
                .foregroundColor(.white)
                .tint(.blue)
                .padding(.horizontal)
        }
        .padding()
        .background(Color.black.opacity(0.55))
        .cornerRadius(20)
        .padding(.bottom, 50)
        .animation(.easeInOut, value: showControls)
    }

    private var controlButtons: some View {
        HStack(spacing: 25) {
            recordButton
            resolutionPicker
        }
    }

    private var recordButton: some View {
        Button(action: toggleRecording) {
            Circle()
                .fill(manager.isRecording ? .red : .green)
                .frame(width: 80, height: 80)
                .overlay(
                    Image(systemName: manager.isRecording ? "stop.fill" : "record.circle.fill")
                        .font(.largeTitle)
                        .foregroundColor(.white)
                )
                .shadow(radius: 5)
        }
    }

    private var resolutionPicker: some View {
        Picker("Resolution", selection: $manager.selectedResolution) {
            ForEach(Resolution.allCases, id: \.self) { res in
                Text(res.rawValue).tag(res)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 200)
    }

    private var lensPicker: some View {
        Picker("Lens", selection: $manager.selectedCameraType) {
            ForEach(CameraType.allCases, id: \.self) { type in
                Text(type.rawValue).tag(type)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 280)
    }

    private var recordingsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recordings")
                .font(.headline)
                .foregroundColor(.white)

            ScrollView {
                ForEach(manager.recordings) { recording in
                    recordingRow(for: recording)
                }
            }
            .frame(height: 180)
        }
        .padding(.horizontal)
    }

    private func recordingRow(for recording: Recording) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(recording.name)
                    .font(.headline)
                    .foregroundColor(.white)

                Text("\(timeString(from: recording.duration)) • \(formatFileSize(recording.size))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer()

            Menu {
                Button("Save to Photos") {
                    manager.exportToPhotos(recording)
                }
                Button("Delete", role: .destructive) {
                    manager.deleteRecording(recording)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundColor(.white)
                    .padding(.horizontal)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(Color.white.opacity(0.15))
        .cornerRadius(8)
    }

    // MARK: - Actions / lifecycle
    private func onAppear() {
        requestPermissions()
        hideControlsAfterDelay()

        // prepare session on first entry (back/wide)
        Task {
            manager.selectedCameraType = .wide
            _ = await manager.prepareIfAuthorized(
                resolution: defaultResolution,
                audioOn: defaultAudio,
                cameraPosition: .back
            )
        }
    }

    private func handleRecordingChange(_ isRecording: Bool) {
        if isRecording {
            provideFeedback(.started)
        } else {
            provideFeedback(.stopped)
        }
    }

    private func toggleRecording() {
        if manager.isRecording {
            manager.stopRecording(autoSave: autoSave)
        } else {
            manager.startRecording()
        }

        showControls = true
        hideControlsAfterDelay()
    }

    private func hideControlsAfterDelay() {
        // capture current recording state to avoid hiding controls after stop
        let shouldHideIfStillRecording = manager.isRecording
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            if manager.isRecording && shouldHideIfStillRecording {
                showControls = false
            }
        }
    }

    // MARK: - System Helpers
    private func requestPermissions() {
        DispatchQueue.main.async {
            AVCaptureDevice.requestAccess(for: .video) { _ in }
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
            PHPhotoLibrary.requestAuthorization { _ in }
        }
    }

    private func provideFeedback(_ type: FeedbackType) {
        let gen = UINotificationFeedbackGenerator()
        gen.prepare()
        gen.notificationOccurred(type == .started ? .success : .warning)
    }

    private func timeString(from t: TimeInterval) -> String {
        let m = Int(t) / 60
        let s = Int(t) % 60
        return String(format: "%02d:%02d", m, s)
    }

    private func formatFileSize(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useMB, .useGB]
        f.countStyle = .file
        return f.string(fromByteCount: bytes)
    }

    enum FeedbackType { case started, stopped }
}

// MARK: - SettingsView
import PhotosUI

struct SettingsView: View {
    @Binding var coverImageData: Data?
    @Binding var defaultResolutionString: String
    @Binding var defaultAudio: Bool
    @Binding var autoSave: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var pickerItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            Form {
                coverSection
                defaultsSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        if let image = selectedImage {
                            coverImageData = image.jpegData(compressionQuality: 0.8)
                        }
                        dismiss()
                    }
                }
            }
            .onChange(of: pickerItem, perform: handlePicker)
        }
    }

    private var coverSection: some View {
        Section("Cover Image") {
            PhotosPicker("Select Cover Image", selection: $pickerItem, matching: .images)

            if let image = selectedImage {
                imagePreview(image)
            } else if let data = coverImageData,
                      let image = UIImage(data: data) {
                imagePreview(image)
            } else {
                Text("No cover image selected")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundColor(.red)
            }
        }
    }

    private var defaultsSection: some View {
        Section("Defaults") {
            Picker("Default Resolution", selection: $defaultResolutionString) {
                ForEach(Resolution.allCases.map(\.rawValue), id: \.self) { Text($0).tag($0) }
            }
            Toggle("Default Audio On", isOn: $defaultAudio)
            Toggle("Auto-Save to Photos", isOn: $autoSave)
        }
    }

    private func imagePreview(_ img: UIImage) -> some View {
        Image(uiImage: img)
            .resizable()
            .scaledToFit()
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func handlePicker(_ item: PhotosPickerItem?) {
        Task {
            do {
                if let data = try await item?.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    selectedImage = image
                    errorMessage = nil
                } else {
                    errorMessage = "Failed to load image."
                }
            } catch {
                errorMessage = "Image import error: \(error.localizedDescription)"
            }
        }
    }
}
