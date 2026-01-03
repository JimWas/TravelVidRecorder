import SwiftUI
import PhotosUI

struct MainView: View {
    @StateObject private var manager = RecordingManager()
    
    // MARK: - UI States
    @State private var coverImageData: Data?
    @State private var pickerItem: PhotosPickerItem?
    @State private var showRecorder = false
    
    // Selection & Deletion
    @State private var selectMode = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var showDeleteAllAlert = false
    @State private var showDeleteSelectedAlert = false
    
    // Export States
    @State private var showExportAllAlert = false
    @State private var showExportComplete = false
    @State private var exportedCount = 0
    
    var coverImage: UIImage? {
        guard let data = coverImageData else { return nil }
        return UIImage(data: data)
    }
    
    // MARK: - Body
    var body: some View {
        NavigationStack {
            ZStack {
                // 1. Sleek Background
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        
                        // Header
                        headerView
                        
                        // Hero Section (Image/Tetris)
                        heroPreviewSection
                        
                        // Main Settings Card
                        configurationSection
                        
                        // Big Action Button
                        startRecordingButton
                        
                        Divider()
                            .padding(.vertical)
                        
                        // Gallery Section
                        recordingsGallerySection
                    }
                    .padding()
                    .padding(.bottom, 50)
                }
            }
            .navigationTitle("")
            .navigationBarHidden(true)
            
            // Present Recording View
            .fullScreenCover(isPresented: $showRecorder) {
                RecordingView(manager: manager, coverImage: coverImage)
                    .interactiveDismissDisabled(true)
            }
            
            // MARK: - Alerts
            
            // 1. Export All Alert (With Ad Logic)
            .alert("Export All Videos?", isPresented: $showExportAllAlert) {
                Button("Watch Ad to Save") {
                    attemptExportAll()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Watch a short video to save all \(manager.recordings.count) video(s) to your Photos library.")
            }
            
            // 2. Export Success
            .alert("Export Complete", isPresented: $showExportComplete) {
                Button("OK") {}
            } message: {
                Text("Successfully saved \(exportedCount) video(s).")
            }
            
            // 3. Delete All
            .alert("Delete ALL videos?", isPresented: $showDeleteAllAlert) {
                Button("Delete All", role: .destructive) {
                    manager.recordings.forEach { manager.deleteRecording($0) }
                }
                Button("Cancel", role: .cancel) {}
            }
            
            // 4. Delete Selected
            .alert("Delete selected?", isPresented: $showDeleteSelectedAlert) {
                Button("Delete", role: .destructive) {
                    for rec in manager.recordings where selectedIDs.contains(rec.id) {
                        manager.deleteRecording(rec)
                    }
                    selectedIDs.removeAll()
                    selectMode = false
                }
                Button("Cancel", role: .cancel) {}
            }
        }
        // Load Image Task
        .onChange(of: pickerItem) { item in
            Task {
                if let data = try? await item?.loadTransferable(type: Data.self) {
                    coverImageData = data
                }
            }
        }
    }
    
    // MARK: - View Components
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("TravelVid")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundColor(.primary)
                Text("Recorder")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer()
            // Quick Storage Toggle
            Toggle("Fake Popups", isOn: $manager.showFakePopups)
                .labelsHidden()
                .toggleStyle(SwitchToggleStyle(tint: .orange))
                .overlay(
                    Text("Fake Popups")
                        .font(.caption2)
                        .offset(y: 20)
                        .fixedSize()
                )
        }
        .padding(.top, 10)
    }
    
    private var heroPreviewSection: some View {
        VStack(spacing: 12) {
            Picker("", selection: $manager.recordingDisplayMode) {
                Text("Cover").tag(RecordingDisplayMode.coverImage)
                Text("Tetris").tag(RecordingDisplayMode.tetris)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            
            ZStack {
                if manager.recordingDisplayMode == .coverImage {
                    if let img = coverImage {
                        Image(uiImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(height: 220)
                            .clipped()
                    } else {
                        placeholderView(icon: "photo", text: "Select Cover Image")
                    }
                } else {
                    placeholderView(icon: "gamecontroller.fill", text: "Tetris Mode Active", color: .blue)
                }
                
                // Overlay Button for Image Picker
                if manager.recordingDisplayMode == .coverImage {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            PhotosPicker(selection: $pickerItem, matching: .images) {
                                Image(systemName: "pencil.circle.fill")
                                    .font(.system(size: 32))
                                    .foregroundColor(.white)
                                    .shadow(radius: 4)
                            }
                            .padding(10)
                        }
                    }
                }
            }
            .frame(height: 220)
            .cornerRadius(20)
            .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
        }
    }
    
    private func placeholderView(icon: String, text: String, color: Color = .gray) -> some View {
        ZStack {
            Color(uiColor: .secondarySystemBackground)
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 40))
                    .foregroundColor(color)
                Text(text)
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var configurationSection: some View {
        VStack(spacing: 0) {
            // Row 1: Camera & Lens
            HStack {
                settingsMenu(title: "Camera", icon: "camera.fill") {
                    Picker("Camera", selection: $manager.cameraPosition) {
                        Text("Back").tag(AVCaptureDevice.Position.back)
                        Text("Front").tag(AVCaptureDevice.Position.front)
                    }
                }
                
                Spacer()
                
                if manager.cameraPosition == .back {
                    settingsMenu(title: "Lens", icon: "arrow.triangle.2.circlepath.camera") {
                        Picker("Lens", selection: $manager.cameraType) {
                            Text("Wide").tag(CameraType.wide)
                            Text("Ultra").tag(CameraType.ultraWide)
                        }
                    }
                    Spacer()
                }
                
                settingsMenu(title: "Quality", icon: "4k.tv") {
                    Picker("Resolution", selection: $manager.selectedResolution) {
                        ForEach(Resolution.allCases) { r in
                            Text(r.rawValue).tag(r)
                        }
                    }
                }
            }
            .padding()
            
            Divider()
            
            // Row 2: Sliders & Toggles
            VStack(spacing: 16) {
                // Segment Length
                VStack(alignment: .leading) {
                    HStack {
                        Label("Segment Length", systemImage: "timer")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(Int(manager.segmentLength/60)) min")
                            .font(.system(.body, design: .monospaced))
                            .bold()
                    }
                    Slider(
                        value: Binding(
                            get: { manager.segmentLength / 60 },
                            set: { manager.segmentLength = $0 * 60 }
                        ),
                        in: 1...10,
                        step: 1
                    )
                    .tint(.blue)
                }
                
                // Stop Gesture
                HStack {
                    Label("Stop Gesture", systemImage: "hand.raised.fill")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Picker("", selection: $manager.stopGesture) {
                        ForEach(StopRecordingGesture.allCases) { gesture in
                            Text(gesture.rawValue).tag(gesture)
                        }
                    }
                    .accentColor(.primary)
                }
                
                // Audio Toggle
                Toggle(isOn: $manager.audioOn) {
                    Label("Record Audio", systemImage: "mic.fill")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .tint(.blue)
            }
            .padding()
        }
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    // Custom Mini Menu Builder
    private func settingsMenu<Content: View>(title: String, icon: String, @ViewBuilder content: @escaping () -> Content) -> some View {
        Menu {
            content()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title3)
                Text(title)
                    .font(.caption2)
                    .textCase(.uppercase)
            }
            .foregroundColor(.primary)
            .frame(width: 70, height: 60)
            .background(Color(uiColor: .secondarySystemBackground))
            .cornerRadius(12)
        }
    }
    
    private var startRecordingButton: some View {
        Button {
            showRecorder = true
        } label: {
            HStack {
                Image(systemName: "record.circle")
                Text("Start Recording")
            }
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 55)
            .background(
                (manager.recordingDisplayMode == .coverImage && coverImage == nil)
                ? Color.gray : Color.red
            )
            .cornerRadius(16)
            .shadow(color: .red.opacity(0.3), radius: 10, y: 5)
        }
        .disabled(manager.recordingDisplayMode == .coverImage && coverImage == nil)
    }
    
    private var recordingsGallerySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section Header
            HStack {
                Text("Library")
                    .font(.title2.bold())
                
                Spacer()
                
                if !manager.recordings.isEmpty {
                    // Actions Menu
                    Menu {
                        Button {
                            withAnimation {
                                selectMode.toggle()
                                selectedIDs.removeAll()
                            }
                        } label: {
                            Label(selectMode ? "Done" : "Select", systemImage: "checkmark.circle")
                        }
                        
                        Divider()
                        
                        Button {
                            // Trigger the Ad/Save Flow
                            showExportAllAlert = true
                        } label: {
                            Label("Save All to Photos", systemImage: "square.and.arrow.up")
                        }
                        
                        Button(role: .destructive) {
                            showDeleteAllAlert = true
                        } label: {
                            Label("Delete All", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle.fill")
                            .font(.title2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            if selectMode {
                HStack {
                    Button("Delete Selected (\(selectedIDs.count))") { showDeleteSelectedAlert = true }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .disabled(selectedIDs.isEmpty)
                    
                    Spacer()
                    
                    Button("Save Selected") { exportSelectedWithConfirmation() }
                        .buttonStyle(.bordered)
                        .disabled(selectedIDs.isEmpty)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            if manager.recordings.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "video.slash")
                        .font(.largeTitle)
                        .foregroundColor(.gray.opacity(0.3))
                    Text("No recordings yet")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(manager.recordings) { rec in
                        recordingRow(rec)
                    }
                }
            }
        }
    }
    
    private func recordingRow(_ rec: Recording) -> some View {
        HStack(spacing: 15) {
            if selectMode {
                Image(systemName: selectedIDs.contains(rec.id) ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundColor(selectedIDs.contains(rec.id) ? .blue : .gray.opacity(0.5))
            }
            
            // Icon
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 44, height: 44)
                Image(systemName: "play.fill")
                    .foregroundColor(.blue)
                    .font(.caption)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(rec.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                
                HStack(spacing: 6) {
                    Label("\(Int(rec.duration))s", systemImage: "clock")
                    Text("•")
                    Text(formatSize(rec.size))
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.gray.opacity(0.5))
        }
        .padding()
        .background(Color.white)
        .cornerRadius(12)
        .onTapGesture {
            if selectMode {
                toggleSelect(rec.id)
            }
        }
    }
    
    // MARK: - Logic Helpers
    
    private func toggleSelect(_ id: UUID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }
    
    func formatSize(_ bytes: Int64) -> String {
        let mb = Double(bytes)/(1024*1024)
        return String(format: "%.1f MB", mb)
    }
    
    private func attemptExportAll() {
        // 1. Bypass for Premium
        if UserDefaults.standard.bool(forKey: "isPremium") {
            exportAllWithConfirmation()
            return
        }
        
        // 2. Attempt to show Ad
        AdMobManager.shared.showRewardedAd { rewardEarned in
            // We trigger the export if they earned the reward
            // OR if you want to be nice: if the ad failed to load/show.
            if rewardEarned {
                exportAllWithConfirmation()
            } else {
                // FALLBACK: Ad failed or was dismissed.
                // To ensure the user isn't stuck, you can either:
                // A) Force the save anyway (Good UX if ad failed)
                // B) Show an alert saying "Ad failed, please try again."
                
                print("Ad failed or skipped. Saving anyway to ensure no data loss.")
                exportAllWithConfirmation()
            }
        }
    }
    
    private func exportAllWithConfirmation() {
        let count = manager.recordings.count
        PHPhotoLibrary.shared().performChanges {
            for rec in manager.recordings {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: rec.url)
            }
        } completionHandler: { success, error in
            DispatchQueue.main.async {
                if success {
                    exportedCount = count
                    showExportComplete = true
                }
            }
        }
    }
    
    private func exportSelectedWithConfirmation() {
        let selectedRecordings = manager.recordings.filter { selectedIDs.contains($0.id) }
        let count = selectedRecordings.count
        
        PHPhotoLibrary.shared().performChanges {
            for rec in selectedRecordings {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: rec.url)
            }
        } completionHandler: { success, error in
            DispatchQueue.main.async {
                if success {
                    exportedCount = count
                    showExportComplete = true
                }
            }
        }
    }
}

