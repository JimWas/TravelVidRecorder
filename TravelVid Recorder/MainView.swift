import SwiftUI
import AVFoundation
import Photos
import PhotosUI
import UIKit
import AVKit

struct MainView: View {
    @StateObject private var manager = RecordingManager()

    @State private var showImagePicker = false
    @State private var showRecordingView = false
    @State private var showDeleteAlert = false
    @State private var isSimulator = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil

    @State private var selectedRecording: Recording?
    @State private var showShareSheet = false
    @State private var showVideoPlayer = false

    @AppStorage("coverImageData") private var coverImageData: Data?
    @AppStorage("defaultResolution") private var defaultResolutionString = Resolution.p1080.rawValue
    @AppStorage("defaultAudio") private var defaultAudio = true
    @AppStorage("cameraPosition") private var cameraPositionString = "Back"

    // Computed
    var coverImage: UIImage? {
        if let data = coverImageData { return UIImage(data: data) }
        return nil
    }

    var defaultResolution: Resolution {
        Resolution(rawValue: defaultResolutionString) ?? .p1080
    }

    var cameraPosition: AVCaptureDevice.Position {
        cameraPositionString == "Back" ? .back : .front
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 30) {

                    // Title
                    Text("TravelVid Recorder")
                        .font(.largeTitle.bold())
                        .padding(.top, 20)

                    // Cover Image
                    SectionBox(title: "Cover Image") {
                        if let image = coverImage {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(height: 150)
                                .clipped()
                                .cornerRadius(10)
                        } else {
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                                .frame(height: 150)
                                .cornerRadius(10)
                                .overlay(
                                    Text("No image selected")
                                        .foregroundColor(.secondary)
                                )
                        }

                        Button("Select Image") {
                            showImagePicker = true
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    // Clip length
                    SectionBox(title: "Clip Length (minutes)") {
                        Slider(value: Binding(
                            get: { manager.segmentDuration / 60 },
                            set: { manager.segmentDuration = $0 * 60 }
                        ), in: 1...10, step: 1)
                        Text("\(Int(manager.segmentDuration / 60)) minute segments")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }

                    // Resolution
                    SectionBox(title: "Resolution") {
                        Picker("Resolution", selection: $defaultResolutionString) {
                            ForEach(Resolution.allCases.map(\.rawValue), id: \.self) { res in
                                Text(res).tag(res)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    // Camera
                    SectionBox(title: "Camera") {
                        Picker("Camera Position", selection: $cameraPositionString) {
                            ForEach(["Front", "Back"], id: \.self) { pos in
                                Text(pos).tag(pos)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text("Lens: Wide")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // Audio
                    SectionBox(title: "Audio") {
                        Toggle("Record Audio", isOn: $defaultAudio)
                            .tint(.blue)
                    }

                    // Start Recording Button
                    Button {
                        if !isSimulator {
                            Task {
                                // lock wide for stealth
                                manager.selectedCameraType = .wide

                                let ok = await manager.prepareIfAuthorized(
                                    resolution: defaultResolution,
                                    audioOn: defaultAudio,
                                    cameraPosition: cameraPosition
                                )

                                if ok {
                                    showRecordingView = true
                                } else {
                                    print("⚠️ Could not prepare session: \(manager.lastErrorMessage ?? "Unknown error")")
                                }
                            }
                        } else {
                            print("❌ Camera not supported on Simulator.")
                        }
                    } label: {
                        Text("Start Recording")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(coverImage == nil || isSimulator)
                    .padding(.vertical, 10)

                    if coverImage == nil {
                        Text("Please select a cover image before recording.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }

                    // Recordings Section
                    SectionBox(title: "Recordings") {
                        if manager.recordings.isEmpty {
                            Text("No saved recordings")
                                .foregroundColor(.secondary)
                        } else {
                            Text("\(manager.recordings.count) saved recordings")
                                .font(.subheadline)
                                .padding(.bottom, 5)

                            // Delete All
                            Button(role: .destructive) {
                                showDeleteAlert = true
                            } label: {
                                Label("Delete All Recordings", systemImage: "trash")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .padding(.bottom, 5)

                            // Recording list
                            VStack(spacing: 10) {
                                ForEach(manager.recordings) { rec in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(rec.name)
                                                .font(.subheadline.bold())
                                                .lineLimit(1)

                                            Text("\(formatDuration(rec.duration)) • \(formatSize(rec.size))")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()

                                        Menu {
                                            Button {
                                                selectedRecording = rec
                                                showVideoPlayer = true
                                            } label: {
                                                Label("Play", systemImage: "play.circle")
                                            }

                                            Button {
                                                manager.exportToPhotos(rec)
                                            } label: {
                                                Label("Save to Photos", systemImage: "square.and.arrow.down")
                                            }

                                            Button {
                                                selectedRecording = rec
                                                showShareSheet = true
                                            } label: {
                                                Label("Share", systemImage: "square.and.arrow.up")
                                            }

                                            Button(role: .destructive) {
                                                manager.deleteRecording(rec)
                                            } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                        } label: {
                                            Image(systemName: "ellipsis.circle")
                                                .font(.title3)
                                                .foregroundColor(.blue)
                                        }
                                    }
                                    .padding(10)
                                    .background(Color.white.opacity(0.9))
                                    .cornerRadius(10)
                                    .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 2)
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Settings")

            // Sheets
            .sheet(isPresented: $showImagePicker) {
                ImagePickerView(coverImageData: $coverImageData)
            }
            .fullScreenCover(isPresented: $showRecordingView) {
                RecordingView(manager: manager, coverImage: coverImage)
            }
            .sheet(isPresented: $showShareSheet) {
                if let rec = selectedRecording {
                    ShareSheet(activityItems: [rec.url])
                }
            }
            .sheet(isPresented: $showVideoPlayer) {
                if let rec = selectedRecording {
                    VideoPlayer(player: AVPlayer(url: rec.url))
                        .edgesIgnoringSafeArea(.all)
                }
            }

            // Delete all alert
            .alert("Delete All Recordings?", isPresented: $showDeleteAlert) {
                Button("Delete All", role: .destructive) {
                    manager.deleteAllRecordings()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will permanently remove all saved videos from the app.")
            }
            .onAppear { requestPermissions() }
        }
    }

    // Helpers
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func formatSize(_ size: Int64) -> String {
        let mb = Double(size) / (1024 * 1024)
        return String(format: "%.1f MB", mb)
    }

    private func requestPermissions() {
        DispatchQueue.main.async {
            AVCaptureDevice.requestAccess(for: .video) { _ in }
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
            PHPhotoLibrary.requestAuthorization { _ in }
        }
    }
}

// Reusable section box
struct SectionBox<Content: View>: View {
    let title: String
    let content: () -> Content

    init(title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(15)
    }
}

// Image picker
struct ImagePickerView: View {
    @Binding var coverImageData: Data?
    @Environment(\.dismiss) private var dismiss
    @State private var pickerItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                PhotosPicker("Select Cover Image", selection: $pickerItem, matching: .images)
                    .buttonStyle(.borderedProminent)

                if let image = selectedImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                } else if let error = errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                }
            }
            .padding()
            .navigationTitle("Pick Cover")
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
            .onChange(of: pickerItem) { newItem in
                Task {
                    do {
                        if let data = try await newItem?.loadTransferable(type: Data.self),
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
    }
}

// ShareSheet
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
