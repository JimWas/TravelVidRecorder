import SwiftUI
import PhotosUI
import MapKit

struct MainView: View {
    @StateObject private var manager = RecordingManager()
    @StateObject private var locationManager = LocationManager.shared
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    
    // MARK: - UI States
    @State private var coverImageData: Data?
    @State private var pickerItem: PhotosPickerItem?
    @State private var videoPickerItem: PhotosPickerItem?
    @State private var isLoadingVideo = false
    @State private var showRecorder = false
    
    // Selection & Deletion
    @State private var selectMode = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var showDeleteAllAlert = false
    @State private var showDeleteSelectedAlert = false
    @State private var showPaywall = false
    
    // Export States
    @State private var showExportAllAlert = false
    @State private var showExportComplete = false
    @State private var exportedCount = 0
    
    // Advanced Settings
    @State private var showAdvancedSettings = false

    // Map State
    @State private var showMap = false
    @State private var selectedMapRecording: Recording?

    // Video Preview State
    @State private var showVideoPreview = false
    @State private var previewRecording: Recording?
    
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
                        
                        // Hero Section (Image/Tetris/FlappyBird)
                        heroPreviewSection
                        
                        // Main Settings Card
                        configurationSection
                        
                        // Advanced Settings
                        advancedSettingsSection
                        
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
            .onAppear {
                locationManager.requestPermission()
            }

            // Present Recording View
            .fullScreenCover(isPresented: $showRecorder) {
                RecordingView(manager: manager, coverImage: coverImage)
                    .interactiveDismissDisabled(true)
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
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

            // Full Map Sheet
            .sheet(isPresented: $showMap) {
                if let rec = selectedMapRecording {
                    FullMapView(recording: rec)
                }
            }

            // Video Preview Sheet
            .sheet(isPresented: $showVideoPreview) {
                if let rec = previewRecording {
                    VideoPreviewView(recording: rec)
                }
            }
        }
        // Load Image Task
        .onChange(of: pickerItem) {
            Task {
                if let data = try? await pickerItem?.loadTransferable(type: Data.self) {
                    coverImageData = data
                }
            }
        }
        // Reconfigure capture session when settings change (if not recording)
        .onChange(of: manager.cameraPosition) { _ in
            Task { await manager.reconfigureSessionIfNeeded() }
        }
        .onChange(of: manager.cameraType) { _ in
            Task { await manager.reconfigureSessionIfNeeded() }
        }
        .onChange(of: manager.selectedResolution) { _ in
            Task { await manager.reconfigureSessionIfNeeded() }
        }
        .onChange(of: manager.audioOn) { _ in
            Task { await manager.reconfigureSessionIfNeeded() }
        }
        .onChange(of: manager.enableStabilization) { _ in
            Task { await manager.reconfigureSessionIfNeeded() }
        }
        // Load Video Task
        .onChange(of: videoPickerItem) {
            guard videoPickerItem != nil else { return }
            isLoadingVideo = true

            Task {
                defer { isLoadingVideo = false }

                do {
                    // Load the video URL using loadTransferable
                    if let movie = try await videoPickerItem?.loadTransferable(type: Movie.self) {
                        // Save to app's directory
                        let savedURL = try await manager.saveSelectedVideo(from: movie.url)
                        await MainActor.run {
                            manager.selectedVideoURL = savedURL
                        }
                    }
                } catch {
                    print("Error loading video: \(error)")
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
            VStack(spacing: 4) {
                Toggle("Fake Popups", isOn: $manager.showFakePopups)
                    .labelsHidden()
                    .toggleStyle(SwitchToggleStyle(tint: .orange))
                Text("Fake Popups")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.top, 10)
    }
    
    private var heroPreviewSection: some View {
        VStack(spacing: 12) {
            // Mode picker in a scrollable menu style for 4 options
            Menu {
                ForEach(RecordingDisplayMode.allCases) { mode in
                    Button {
                        if mode.requiresPremium && !subscriptionManager.isPremium {
                            showPaywall = true
                        } else {
                            manager.recordingDisplayMode = mode
                        }
                    } label: {
                        HStack {
                            Text(mode.rawValue)
                            if mode.requiresPremium && !subscriptionManager.isPremium {
                                Image(systemName: "lock.fill")
                            }
                            if manager.recordingDisplayMode == mode {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    Text(manager.recordingDisplayMode.rawValue)
                        .font(.headline)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption)
                }
                .foregroundColor(.primary)
                .padding()
                .background(Color(uiColor: .secondarySystemBackground))
                .cornerRadius(12)
            }
            .padding(.horizontal)
            
            ZStack {
                switch manager.recordingDisplayMode {
                case .coverImage:
                    if let img = coverImage {
                        Image(uiImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(height: 220)
                            .clipped()
                    } else {
                        placeholderView(icon: "photo", text: "Select Cover Image")
                    }

                case .videoPlayback:
                    if let videoURL = manager.selectedVideoURL {
                        VideoThumbnailView(videoURL: videoURL)
                            .frame(height: 220)
                            .clipped()
                    } else {
                        placeholderView(icon: "video.fill", text: "Select Video", color: .purple)
                    }

                case .fakeCall:
                    placeholderView(icon: "phone.fill", text: "Fake Call Mode Active", color: .green)

                case .tetris:
                    placeholderView(icon: "gamecontroller.fill", text: "Tetris Mode Active", color: .blue)

                case .flappyBird:
                    placeholderView(icon: "bird.fill", text: "Flappy Bird Mode Active", color: .orange)

                case .bitcoin:
                    placeholderView(icon: "bitcoinsign.circle.fill", text: "Bitcoin Tracker Active", color: .orange)

                case .calculator:
                    placeholderView(icon: "plus.forwardslash.minus", text: "Calculator Mode Active", color: .gray)
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

                // Overlay Button for Video Picker
                if manager.recordingDisplayMode == .videoPlayback {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            if isLoadingVideo {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(1.5)
                                    .padding(10)
                            } else {
                                let hasVideo = manager.selectedVideoURL != nil
                                PhotosPicker(selection: $videoPickerItem, matching: .videos) {
                                    Image(systemName: hasVideo ? "pencil.circle.fill" : "video.badge.plus")
                                        .font(.system(size: 32))
                                        .foregroundColor(.white)
                                        .shadow(radius: 4)
                                }
                                .padding(10)
                            }
                        }
                    }
                }

                // Contact Name Input for Fake Call
                if manager.recordingDisplayMode == .fakeCall {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            TextField("Contact Name", text: $manager.fakeCallContactName)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 200)
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
                            Text("Standard").tag(CameraType.wide)
                            Text("Ultra-Wide").tag(CameraType.ultraWide)
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

                // Hold Duration (only show for tap & hold gesture)
                if manager.stopGesture == .doubleTapHold {
                    VStack(alignment: .leading) {
                        HStack {
                            Label("Hold Duration", systemImage: "hand.tap.fill")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(manager.holdDuration)s")
                                .font(.system(.body, design: .monospaced))
                                .bold()
                        }
                        Slider(
                            value: Binding(
                                get: { Double(manager.holdDuration) },
                                set: { manager.holdDuration = Int($0) }
                            ),
                            in: 1...10,
                            step: 1
                        )
                        .tint(.orange)
                    }
                }
                
                // Audio Toggle
                Toggle(isOn: $manager.audioOn) {
                    Label("Record Audio", systemImage: "mic.fill")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .tint(.blue)

                // Stabilization Toggle
                Toggle(isOn: $manager.enableStabilization) {
                    Label("Stabilization", systemImage: "waveform.path")
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

    private var advancedSettingsSection: some View {
        VStack(spacing: 0) {
            DisclosureGroup(isExpanded: $showAdvancedSettings) {
                VStack(spacing: 12) {
                    Toggle(isOn: $manager.showRecordingIndicator) {
                        Label("Recording Indicator", systemImage: "record.circle")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .tint(.red)
                }
                .padding(.top, 8)
            } label: {
                HStack {
                    Label("Advanced Settings", systemImage: "slider.horizontal.3")
                        .font(.headline)
                    Spacer()
                }
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
                (manager.recordingDisplayMode == .coverImage && coverImage == nil) ||
                (manager.recordingDisplayMode == .videoPlayback && manager.selectedVideoURL == nil)
                ? Color.gray : Color.red
            )
            .cornerRadius(16)
            .shadow(color: .red.opacity(0.3), radius: 10, y: 5)
        }
        .disabled(
            (manager.recordingDisplayMode == .coverImage && coverImage == nil) ||
            (manager.recordingDisplayMode == .videoPlayback && manager.selectedVideoURL == nil)
        )
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

            // Icon or Map Thumbnail
            if let lat = rec.latitude, let lon = rec.longitude {
                MapSnapshotView(latitude: lat, longitude: lon)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .onTapGesture {
                        selectedMapRecording = rec
                        showMap = true
                    }
            } else {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.1))
                        .frame(width: 44, height: 44)
                    Image(systemName: "play.fill")
                        .foregroundColor(.blue)
                        .font(.caption)
                }
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

                // Location info if available
                if let address = rec.address {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.caption2)
                        Text(address)
                            .font(.caption2)
                            .lineLimit(1)
                    }
                    .foregroundColor(.green)
                } else if let lat = rec.latitude, let lon = rec.longitude {
                    HStack(spacing: 4) {
                        Image(systemName: "location.fill")
                            .font(.caption2)
                        Text("\(String(format: "%.4f", lat)), \(String(format: "%.4f", lon))")
                            .font(.caption2)
                    }
                    .foregroundColor(.green)
                }
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
            } else {
                // Open video preview
                previewRecording = rec
                showVideoPreview = true
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
        if subscriptionManager.isPremium {
            exportAllWithConfirmation()
            return
        }
        
        // 2. Attempt to show Ad
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
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
    }
    private func exportAllWithConfirmation() {
        var successCount = 0

        Task {
            for rec in manager.recordings {
                do {
                    try await PHPhotoLibrary.shared().performChanges {
                        let request = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: rec.url)

                        // Embed GPS metadata if available
                        if let lat = rec.latitude, let lon = rec.longitude {
                            request?.location = CLLocation(latitude: lat, longitude: lon)
                        }

                        // Set creation date if available
                        if let creation = rec.creation {
                            request?.creationDate = creation
                        }
                    }
                    successCount += 1
                } catch {
                    print("Failed to export \(rec.name): \(error)")
                }
            }

            await MainActor.run {
                exportedCount = successCount
                showExportComplete = true
            }
        }
    }
    
    private func exportSelectedWithConfirmation() {
        let selectedRecordings = manager.recordings.filter { selectedIDs.contains($0.id) }
        var successCount = 0

        Task {
            for rec in selectedRecordings {
                do {
                    try await PHPhotoLibrary.shared().performChanges {
                        let request = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: rec.url)

                        // Embed GPS metadata if available
                        if let lat = rec.latitude, let lon = rec.longitude {
                            request?.location = CLLocation(latitude: lat, longitude: lon)
                        }

                        // Set creation date if available
                        if let creation = rec.creation {
                            request?.creationDate = creation
                        }
                    }
                    successCount += 1
                } catch {
                    print("Failed to export \(rec.name): \(error)")
                }
            }

            await MainActor.run {
                exportedCount = successCount
                showExportComplete = true
            }
        }
    }
}

// MARK: - Video Helpers
import UniformTypeIdentifiers
import AVKit

struct Movie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let copy = URL.documentsDirectory.appending(path: "tmp-\(UUID().uuidString).mov")
            try FileManager.default.copyItem(at: received.file, to: copy)
            return Self.init(url: copy)
        }
    }
}

struct VideoThumbnailView: View {
    let videoURL: URL
    @State private var thumbnail: UIImage?

    var body: some View {
        Group {
            if let thumbnail = thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Color.gray.opacity(0.3)
                    ProgressView()
                }
            }
        }
        .onAppear {
            generateThumbnail()
        }
    }

    private func generateThumbnail() {
        Task {
            let asset = AVAsset(url: videoURL)
            let imageGenerator = AVAssetImageGenerator(asset: asset)
            imageGenerator.appliesPreferredTrackTransform = true

            do {
                let cgImage = try imageGenerator.copyCGImage(at: .zero, actualTime: nil)
                await MainActor.run {
                    thumbnail = UIImage(cgImage: cgImage)
                }
            } catch {
                print("Error generating thumbnail: \(error)")
            }
        }
    }
}

struct MapSnapshotView: View {
    let latitude: Double
    let longitude: Double
    @State private var snapshotImage: UIImage?
    private static let cache = NSCache<NSString, UIImage>()

    var body: some View {
        Group {
            if let image = snapshotImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Color.gray.opacity(0.2)
                    Image(systemName: "map")
                        .foregroundColor(.gray)
                }
            }
        }
        .onAppear {
            generateSnapshot()
        }
    }

    private func generateSnapshot() {
        let cacheKey = NSString(string: String(format: "%.6f,%.6f", latitude, longitude))
        if let cached = Self.cache.object(forKey: cacheKey) {
            snapshotImage = cached
            return
        }

        let options = MKMapSnapshotter.Options()
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        options.region = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
        options.size = CGSize(width: 88, height: 88) // 2x for retina
        options.scale = UIScreen.main.scale

        let snapshotter = MKMapSnapshotter(options: options)
        snapshotter.start { snapshot, error in
            guard let snapshot = snapshot, error == nil else { return }

            // Draw pin on snapshot
            let image = UIGraphicsImageRenderer(size: options.size).image { context in
                snapshot.image.draw(at: .zero)

                // Draw red pin
                let pinPoint = snapshot.point(for: coordinate)
                let pinSize: CGFloat = 20
                let pinRect = CGRect(
                    x: pinPoint.x - pinSize / 2,
                    y: pinPoint.y - pinSize,
                    width: pinSize,
                    height: pinSize
                )

                UIColor.systemRed.setFill()
                let pinPath = UIBezierPath(ovalIn: pinRect)
                pinPath.fill()
            }

            DispatchQueue.main.async {
                Self.cache.setObject(image, forKey: cacheKey)
                self.snapshotImage = image
            }
        }
    }
}

struct FullMapView: View {
    let recording: Recording
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let lat = recording.latitude, let lon = recording.longitude {
                    Map(initialPosition: .region(MKCoordinateRegion(
                        center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                    ))) {
                        // Main recording location
                        Marker("Recording Location", coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon))
                            .tint(.red)

                        // Show path if available
                        if let path = recording.locationPath, path.count > 1 {
                            MapPolyline(coordinates: path.map {
                                CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                            })
                            .stroke(.blue, lineWidth: 3)
                        }
                    }
                    .mapControls {
                        MapUserLocationButton()
                        MapCompass()
                        MapScaleView()
                    }

                    // Info Panel
                    VStack(alignment: .leading, spacing: 12) {
                        Text(recording.name)
                            .font(.headline)

                        if let address = recording.address {
                            HStack(spacing: 8) {
                                Image(systemName: "mappin.and.ellipse")
                                    .foregroundColor(.red)
                                Text(address)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }

                        HStack(spacing: 8) {
                            Image(systemName: "location.fill")
                                .foregroundColor(.blue)
                            Text("\(String(format: "%.6f", lat)), \(String(format: "%.6f", lon))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        if let path = recording.locationPath {
                            HStack(spacing: 8) {
                                Image(systemName: "point.bottomleft.forward.to.arrowtriangle.uturn.scurvepath")
                                    .foregroundColor(.green)
                                Text("\(path.count) location points tracked")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.ultraThinMaterial)
                } else {
                    // No location data available
                    VStack(spacing: 20) {
                        Image(systemName: "location.slash")
                            .font(.system(size: 60))
                            .foregroundColor(.gray.opacity(0.5))

                        Text("No Location Data")
                            .font(.title2.weight(.semibold))

                        Text("This recording doesn't have GPS coordinates.\nEnable location permissions to track recording locations.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Label("Open Settings", systemImage: "gear")
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Recording Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Video Preview View
import AVKit

struct VideoPreviewView: View {
    let recording: Recording
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Video Player
                if let player = player {
                    VideoPlayer(player: player)
                        .ignoresSafeArea(edges: .horizontal)
                } else {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Loading video...")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                }

                // Info Panel
                VStack(alignment: .leading, spacing: 12) {
                    Text(recording.name)
                        .font(.headline)
                        .lineLimit(1)

                    HStack(spacing: 16) {
                        Label(formatDuration(recording.duration), systemImage: "clock")
                        Label(formatSize(recording.size), systemImage: "doc")
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                    if let address = recording.address {
                        HStack(spacing: 8) {
                            Image(systemName: "mappin.and.ellipse")
                                .foregroundColor(.red)
                            Text(address)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                    }

                    if let creation = recording.creation {
                        HStack(spacing: 8) {
                            Image(systemName: "calendar")
                                .foregroundColor(.blue)
                            Text(creation, style: .date)
                            Text("at")
                            Text(creation, style: .time)
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial)
            }
            .background(Color.black)
            .navigationTitle("Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        player?.pause()
                        dismiss()
                    }
                }
            }
            .onAppear {
                player = AVPlayer(url: recording.url)
                player?.play()
            }
            .onDisappear {
                player?.pause()
                player = nil
            }
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func formatSize(_ bytes: Int64) -> String {
        let mb = Double(bytes) / (1024 * 1024)
        return String(format: "%.1f MB", mb)
    }
}
