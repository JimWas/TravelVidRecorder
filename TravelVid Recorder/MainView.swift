import SwiftUI
import PhotosUI
import MapKit
import StoreKit
import Photos
import CoreLocation

struct MainView: View {
    @StateObject private var manager = RecordingManager()
    @StateObject private var locationManager = LocationManager.shared
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    
    // MARK: - UI States
    @State private var coverImageData: Data?
    @State private var pickerItem: PhotosPickerItem?

    // Persisted cover image helpers
    private static let coverImageFilename = "cover_image.jpg"
    private static var coverImageURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(coverImageFilename)
    }
    @State private var videoPickerItem: PhotosPickerItem?
    @State private var isLoadingVideo = false
    @State private var showRecorder = false
    @State private var showOnboarding = false
    
    // Selection & Deletion
    @State private var selectMode = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var showDeleteAllAlert = false
    @State private var showDeleteSelectedAlert = false
    @State private var showPaywall = false
    @State private var showRecordingModePicker = false
    @State private var isShowingOfferCodeRedemption = false
    @State private var showSubscriptionError = false
    
    // Export States
    @State private var showExportAllAlert = false
    @State private var showExportComplete = false
    @State private var showExportPartial = false
    @State private var showExportFailed = false
    @State private var exportedCount = 0
    @State private var exportFailedCount = 0
    @State private var showQuickDelete = false
    @State private var exportedRecordings: [Recording] = []
    @State private var isExporting = false
    @State private var exportProgress: Double = 0   // 0.0 – 1.0
    @State private var exportTotal: Int = 0
    @State private var exportDone: Int = 0

    // Advanced Settings
    @State private var showAdvancedSettings = false

    // Storage error
    @State private var showStorageError = false
    @State private var storageErrorMessage = ""

    // Map State
    @State private var selectedMapRecording: Recording?

    // Video Preview State
    @State private var previewRecording: Recording?
    @State private var showHistory = false
    
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

                        // Storage indicator
                        storageIndicatorView

                        // Hero Section (Image/Tetris/FlappyBird)
                        heroPreviewSection

                        // Primary thumb-reach action directly below the selected mode preview.
                        startRecordingButton
                        
                        // Main Settings Card
                        configurationSection

                        // Advanced Settings
                        advancedSettingsSection

                        // Passive preflight status; recording still starts with one tap.
                        recordingReliabilitySection

                        // Repeated action for users reviewing all settings before recording.
                        startRecordingButton

                        // Premium entry point (always visible for App Review discoverability)
                        premiumCtaSection
                        
                        Divider()
                            .padding(.vertical)
                        
                        // Gallery Section
                        recordingsGallerySection
                    }
                    .padding()
                    .padding(.bottom, 50)
                }

                // Export progress overlay
                if isExporting {
                    exportProgressOverlay
                }
            }
            .navigationTitle("")
            .navigationBarHidden(true)
            .onAppear {
                AdMobManager.shared.initializeAdMob()
                manager.refreshReliabilityStatus()
                if !hasCompletedOnboarding {
                    showOnboarding = true
                }
                // Restore persisted cover image
                if coverImageData == nil,
                   let data = try? Data(contentsOf: MainView.coverImageURL) {
                    coverImageData = data
                }
                // Auto-start recording if enabled (only after onboarding, only if ready to record)
                if manager.autoStartOnLaunch && hasCompletedOnboarding {
                    let coverReady = manager.recordingDisplayMode != .coverImage || coverImage != nil
                    let videoReady = manager.recordingDisplayMode != .videoPlayback || manager.selectedVideoURL != nil
                    if coverReady && videoReady {
                        showRecorder = true
                    }
                }
            }
            .onChange(of: scenePhase, initial: false) { _, newPhase in
                switch newPhase {
                case .inactive, .background:
                    NotificationManager.shared.scheduleUnsavedVideosNotification(count: manager.recordings.count)
                case .active:
                    NotificationManager.shared.clearUnsavedVideosNotification()
                    manager.refreshReliabilityStatus()
                @unknown default:
                    break
                }
            }

            // Present Recording View
            .fullScreenCover(isPresented: $showRecorder) {
                RecordingView(manager: manager, coverImage: coverImage)
                    .interactiveDismissDisabled(true)
            }
            .fullScreenCover(isPresented: $showOnboarding) {
                OnboardingView(isPresented: $showOnboarding, stopGesture: manager.stopGesture)
                    .interactiveDismissDisabled(true)
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
            .sheet(isPresented: $showRecordingModePicker) {
                RecordingModePickerView(
                    selectedMode: manager.recordingDisplayMode,
                    isPremium: subscriptionManager.isPremium
                ) { mode in
                    showRecordingModePicker = false

                    if mode.requiresPremium && !subscriptionManager.isPremium {
                        // Let the mode sheet finish dismissing before presenting the paywall.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            showPaywall = true
                        }
                    } else {
                        manager.recordingDisplayMode = mode
                    }
                }
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showHistory) {
                RecordingHistoryView(log: manager.recordingHistory) {
                    manager.clearHistory()
                }
            }
            // MARK: - Alerts
            
            // 1. Export All Alert (With Ad Logic)
            .alert("Export All Videos?", isPresented: $showExportAllAlert) {
                Button("Continue") {
                    attemptExportAll()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will save all \(manager.recordings.count) video(s) to your Photos library.")
            }
            
            // 2. Export Success
            .alert("Export Complete", isPresented: $showExportComplete) {
                Button("Delete from App", role: .destructive) {
                    exportedRecordings.forEach { manager.deleteRecording($0) }
                    exportedRecordings = []
                }
                Button("Keep in App") { exportedRecordings = [] }
            } message: {
                Text("Successfully saved \(exportedCount) video(s) to your Photos library. Delete them from the app to free up storage?")
            }

            // 2b. Export Partial
            .alert("Some Videos Not Saved", isPresented: $showExportPartial) {
                Button("Delete Saved Videos", role: .destructive) {
                    exportedRecordings.forEach { manager.deleteRecording($0) }
                    exportedRecordings = []
                }
                Button("Keep All") { exportedRecordings = [] }
            } message: {
                Text("\(exportedCount) of \(exportedCount + exportFailedCount) video(s) were saved to Photos. \(exportFailedCount) could not be saved, likely due to insufficient storage. Delete the \(exportedCount) saved video(s) from the app to free up space?")
            }

            // 2c. Export Failed
            .alert("Export Failed", isPresented: $showExportFailed) {
                Button("OK") { exportedRecordings = [] }
            } message: {
                Text("None of the \(exportFailedCount) video(s) could be saved. Your device may not have enough storage space. Please free up space and try again.")
            }

            // 3. Delete All
            .alert("Delete \(manager.recordings.count) video(s)?", isPresented: $showDeleteAllAlert) {
                Button("Delete \(manager.recordings.count) Video(s)", role: .destructive) {
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
            // 5. Storage error
            .alert("Not Enough Storage", isPresented: $showStorageError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(storageErrorMessage)
            }
            .alert("Subscription", isPresented: $showSubscriptionError) {
                Button("OK", role: .cancel) {
                    subscriptionManager.purchaseError = nil
                }
            } message: {
                Text(subscriptionManager.purchaseError ?? "Something went wrong while redeeming your offer code.")
            }
            .offerCodeRedemption(isPresented: $isShowingOfferCodeRedemption) { result in
                switch result {
                case .success:
                    Task {
                        await subscriptionManager.refreshAfterOfferCodeRedemption()
                        if subscriptionManager.purchaseError != nil {
                            showSubscriptionError = true
                        }
                    }
                case .failure(let error):
                    subscriptionManager.purchaseError = "Offer code redemption failed: \(error.localizedDescription)"
                    showSubscriptionError = true
                }
            }

            // Full Map Sheet
            .sheet(item: $selectedMapRecording) { rec in
                FullMapView(recording: rec)
            }

            // Video Preview Sheet
            .sheet(item: $previewRecording) { rec in
                VideoPreviewView(recording: rec)
            }
        }
        // Load Image Task
        .onChange(of: pickerItem) {
            Task {
                if let data = try? await pickerItem?.loadTransferable(type: Data.self),
                   let image = UIImage(data: data),
                   let jpeg = image.jpegData(compressionQuality: 0.8) {
                    coverImageData = jpeg
                    try? jpeg.write(to: MainView.coverImageURL, options: .atomic)
                }
            }
        }
        // Reconfigure capture session when settings change (if not recording)
        .onChange(of: manager.cameraPosition) {
            manager.refreshReliabilityStatus()
            Task { await manager.reconfigureSessionIfNeeded() }
        }
        .onChange(of: manager.cameraType) {
            manager.refreshReliabilityStatus()
            Task { await manager.reconfigureSessionIfNeeded() }
        }
        .onChange(of: manager.selectedResolution) {
            manager.refreshReliabilityStatus()
            Task { await manager.reconfigureSessionIfNeeded() }
        }
        .onChange(of: manager.audioOn) {
            manager.refreshReliabilityStatus()
            Task { await manager.reconfigureSessionIfNeeded() }
        }
        .onChange(of: manager.enableStabilization) {
            Task { await manager.reconfigureSessionIfNeeded() }
        }
        .onChange(of: manager.segmentLength) {
            manager.refreshReliabilityStatus()
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
                    let msg = (error as NSError).localizedDescription
                    await MainActor.run {
                        storageErrorMessage = msg
                        showStorageError = true
                    }
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
            Button {
                showHistory = true
            } label: {
                Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.top, 10)
    }
    
    private var storageIndicatorView: some View {
        let available = manager.availableStorageBytes
        let total = manager.totalStorageBytes
        let used = total > 0 ? total - available : 0

        let availableGB = Double(available) / 1_073_741_824
        let isLow = available < 500 * 1024 * 1024      // < 500 MB
        let isCritical = available < 100 * 1024 * 1024 // < 100 MB

        let freeLabel: String
        if availableGB >= 1 {
            freeLabel = String(format: "%.1f GB free", availableGB)
        } else {
            freeLabel = String(format: "%d MB free", Int(available / 1_048_576))
        }

        // Bar fills with used space (more fill = less room), like iPhone Settings
        let usedFraction: Double = total > 0 ? min(1.0, Double(used) / Double(total)) : 0
        let barColor: Color = isCritical ? .red : isLow ? .orange : .accentColor

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: isCritical ? "exclamationmark.triangle.fill" : "internaldrive")
                    .foregroundColor(barColor)
                    .font(.caption)
                Text("Storage: \(freeLabel)")
                    .font(.caption)
                    .foregroundColor(isCritical ? .red : isLow ? .orange : .secondary)
                Spacer()
                if isCritical {
                    Text("Low — free up space!")
                        .font(.caption2.bold())
                        .foregroundColor(.red)
                } else if isLow {
                    Text("Getting low")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(uiColor: .systemFill))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(barColor)
                        .frame(width: geo.size.width * usedFraction, height: 6)
                }
            }
            .frame(height: 6)
        }
        .padding(.horizontal, 2)
        .onAppear { manager.refreshStorageInfo() }
    }

    private var exportProgressOverlay: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 36))
                    .foregroundColor(.white)

                Text("Saving to Photos…")
                    .font(.headline)
                    .foregroundColor(.white)

                Text("\(exportDone) of \(exportTotal)")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white.opacity(0.3))
                            .frame(height: 12)
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white)
                            .frame(width: geo.size.width * exportProgress, height: 12)
                            .animation(.easeInOut(duration: 0.2), value: exportProgress)
                    }
                }
                .frame(height: 12)
                .padding(.horizontal, 4)
            }
            .padding(32)
            .background(.ultraThinMaterial)
            .cornerRadius(20)
            .padding(.horizontal, 48)
        }
    }

    private var heroPreviewSection: some View {
        VStack(spacing: 12) {
            Button {
                showRecordingModePicker = true
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
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
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
                            .allowsHitTesting(false)
                    } else {
                        placeholderView(icon: "photo", text: "Select Cover Image")
                    }

                case .videoPlayback:
                    if let videoURL = manager.selectedVideoURL {
                        VideoThumbnailView(videoURL: videoURL)
                            .frame(height: 220)
                            .clipped()
                            .allowsHitTesting(false)
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

                case .ledBanner:
                    LEDBannerView(
                        text: manager.ledBannerText,
                        useNasalization: manager.ledBannerUseNasalization,
                        speed: manager.ledBannerSpeed,
                        isPreview: true
                    )
                    .frame(height: 220)

                case .currencyConverter:
                    CurrencyConverterView(
                        amountText: $manager.converterAmount,
                        base: $manager.converterBase,
                        isPreview: true
                    )
                    .frame(height: 220)

                case .worldClock:
                    placeholderView(icon: "clock.fill", text: "World Clock Active", color: .cyan)

                case .travelDashboard:
                    TravelDashboardView(
                        speedUnit: manager.travelSpeedUnit,
                        audioLevelDB: nil,
                        audioEnabled: manager.audioOn,
                        isPreview: true
                    )
                    .frame(height: 220)
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

                if manager.recordingDisplayMode == .currencyConverter {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            VStack(alignment: .trailing, spacing: 8) {
                                Picker("Direction", selection: $manager.converterBase) {
                                    ForEach(CurrencyConverterBase.allCases) { option in
                                        Text(option.rawValue).tag(option)
                                    }
                                }
                                .pickerStyle(.menu)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(.ultraThinMaterial)
                                .cornerRadius(10)

                                TextField("Amount", text: $manager.converterAmount)
                                    .keyboardType(.decimalPad)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: 150)
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

                if manager.recordingDisplayMode == .travelDashboard {
                    HStack {
                        Label("Speed Unit", systemImage: "speedometer")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        Picker("Speed Unit", selection: $manager.travelSpeedUnit) {
                            ForEach(TravelSpeedUnit.allCases) { unit in
                                Text(unit.rawValue).tag(unit)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 150)
                    }
                }

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
                    HStack(spacing: 12) {
                        Image(systemName: "record.circle")
                            .font(.title3)
                            .foregroundColor(.red)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Status Indicator")
                                .font(.subheadline.weight(.semibold))
                            Text("Show or hide the on-screen recording status indicator.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: $manager.showRecordingIndicator)
                            .labelsHidden()
                            .tint(.red)
                    }
                    .padding(12)
                    .background(Color(uiColor: .secondarySystemBackground))
                    .cornerRadius(12)

                    HStack(spacing: 12) {
                        Image(systemName: "bolt.fill")
                            .font(.title3)
                            .foregroundColor(.yellow)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Auto-Start on Launch")
                                .font(.subheadline.weight(.semibold))
                            Text("Recording begins immediately when the app opens.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: $manager.autoStartOnLaunch)
                            .labelsHidden()
                            .tint(.yellow)
                    }
                    .padding(12)
                    .background(Color(uiColor: .secondarySystemBackground))
                    .cornerRadius(12)

                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.bubble")
                            .font(.title3)
                            .foregroundColor(.orange)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Fake Popups")
                                .font(.subheadline.weight(.semibold))
                            Text("Shows repeating 'Storage Full' alerts during recording.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: $manager.showFakePopups)
                            .labelsHidden()
                            .tint(.orange)
                    }
                    .padding(12)
                    .background(Color(uiColor: .secondarySystemBackground))
                    .cornerRadius(12)

                    if manager.recordingDisplayMode == .ledBanner {
                        VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            Image(systemName: "textformat")
                                .font(.title3)
                                .foregroundColor(.green)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text("LED Banner")
                                        .font(.subheadline.weight(.semibold))
                                    if !subscriptionManager.isPremium {
                                        Image(systemName: "lock.fill")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Text("Displays your custom text in LED marquee style.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }

                        TextField("Banner text", text: $manager.ledBannerText, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(2)

                        Toggle("Use Nasalization font", isOn: $manager.ledBannerUseNasalization)
                            .tint(.green)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Scroll Speed")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("\(Int(manager.ledBannerSpeed)) px/s")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Slider(value: $manager.ledBannerSpeed, in: 10...120, step: 5)
                                .tint(.green)
                        }
                    }
                        .padding(12)
                        .background(Color(uiColor: .secondarySystemBackground))
                        .cornerRadius(12)
                        .disabled(!subscriptionManager.isPremium)
                        .opacity(subscriptionManager.isPremium ? 1 : 0.6)
                    }
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

    private var premiumCtaSection: some View {
        HStack(spacing: 12) {
            Image(systemName: "star.circle.fill")
                .font(.title2)
                .foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 4) {
                Text(subscriptionManager.isPremium ? "TravelVid Premium Active" : "TravelVid Premium")
                    .font(.subheadline.weight(.semibold))
                Text(subscriptionManager.isPremium ? "Manage subscription and restore purchases" : "Unlock Fake Call, Bitcoin, LED Banner, Currency Converter, and more")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                Button(subscriptionManager.isPremium ? "Manage" : "Go Premium") {
                    showPaywall = true
                }
                .buttonStyle(.borderedProminent)

                Button("Redeem Code") {
                    isShowingOfferCodeRedemption = true
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }

    private var recordingReliabilitySection: some View {
        let status = manager.reliabilityStatus

        return VStack(spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: reliabilityIcon(for: status.level))
                    .foregroundStyle(reliabilityColor(for: status.level))
                Text("Recording Readiness")
                    .font(.headline)
                Spacer()
                Text(reliabilityTitle(for: status.level))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(reliabilityColor(for: status.level))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(reliabilityColor(for: status.level).opacity(0.12))
                    .clipShape(Capsule())
            }

            if case .recovering(let attempt) = manager.recoveryState {
                reliabilityNotice(
                    icon: "arrow.clockwise",
                    text: "Recovering camera connection (attempt \(attempt) of 3)",
                    color: .orange
                )
            } else if case .interrupted(let message) = manager.recoveryState {
                reliabilityNotice(icon: "pause.circle.fill", text: message, color: .orange)
            } else if case .failed(let message) = manager.recoveryState {
                reliabilityNotice(icon: "exclamationmark.triangle.fill", text: message, color: .red)
            }

            VStack(spacing: 12) {
                ForEach(status.items) { item in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: reliabilityIcon(for: item.level))
                            .font(.caption)
                            .foregroundStyle(reliabilityColor(for: item.level))
                            .frame(width: 18, height: 18)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.subheadline.weight(.semibold))
                            Text(item.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }

    private func reliabilityNotice(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
            Text(text)
                .font(.caption.weight(.medium))
            Spacer()
        }
        .foregroundStyle(color)
        .padding(10)
        .background(color.opacity(0.1))
        .cornerRadius(10)
    }

    private func reliabilityTitle(for level: RecordingReliabilityLevel) -> String {
        switch level {
        case .checking: return "Checking"
        case .ready: return "Ready"
        case .warning: return "Ready with warning"
        case .unavailable: return "Unavailable"
        }
    }

    private func reliabilityIcon(for level: RecordingReliabilityLevel) -> String {
        switch level {
        case .checking: return "arrow.clockwise"
        case .ready: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.circle.fill"
        case .unavailable: return "xmark.circle.fill"
        }
    }

    private func reliabilityColor(for level: RecordingReliabilityLevel) -> Color {
        switch level {
        case .checking: return .secondary
        case .ready: return .green
        case .warning: return .orange
        case .unavailable: return .red
        }
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
        let displayModeReady = !(
            (manager.recordingDisplayMode == .coverImage && coverImage == nil) ||
            (manager.recordingDisplayMode == .videoPlayback && manager.selectedVideoURL == nil)
        )
        let canStart = displayModeReady && manager.reliabilityStatus.canStartRecording

        return Button {
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
            .background(canStart ? Color.red : Color.gray)
            .cornerRadius(16)
            .shadow(color: .red.opacity(0.3), radius: 10, y: 5)
        }
        .disabled(!canStart)
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
                    
                    Button("Save Selected") { attemptExportSelected() }
                        .buttonStyle(.bordered)
                        .disabled(selectedIDs.isEmpty)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            if manager.isLoadingRecordings {
                VStack(spacing: 12) {
                    ProgressView()
                        .progressViewStyle(.circular)
                    Text("Loading recordings...")
                        .font(.headline)
                    Text("Your saved videos are still being scanned.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else if manager.recordings.isEmpty {
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
                attemptOpenPreview(for: rec)
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
        if subscriptionManager.isPremium {
            exportAllWithConfirmation()
            return
        }

        AdMobManager.shared.showInterstitialAd {
            exportAllWithConfirmation()
        }
    }

    private func attemptExportSelected() {
        if subscriptionManager.isPremium {
            exportSelectedWithConfirmation()
            return
        }

        AdMobManager.shared.showInterstitialAd {
            exportSelectedWithConfirmation()
        }
    }

    private func attemptOpenPreview(for rec: Recording) {
        if subscriptionManager.isPremium {
            previewRecording = rec
            return
        }

        AdMobManager.shared.showInterstitialAd {
            previewRecording = rec
        }
    }
    private func exportAllWithConfirmation() {
        let recordings = manager.recordings
        guard !recordings.isEmpty else { return }
        var successCount = 0
        var failCount = 0
        var saved: [Recording] = []

        exportTotal = recordings.count
        exportDone = 0
        exportProgress = 0
        isExporting = true

        Task {
            for rec in recordings {
                do {
                    try await PHPhotoLibrary.shared().performChanges {
                        let request = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: rec.url)
                        if let lat = rec.latitude, let lon = rec.longitude {
                            request?.location = CLLocation(latitude: lat, longitude: lon)
                        }
                        if let creation = rec.creation {
                            request?.creationDate = creation
                        }
                    }
                    successCount += 1
                    saved.append(rec)
                } catch {
                    failCount += 1
                    print("Failed to export \(rec.name): \(error)")
                }
                await MainActor.run {
                    exportDone += 1
                    exportProgress = Double(exportDone) / Double(exportTotal)
                }
            }

            await MainActor.run {
                isExporting = false
                exportedCount = successCount
                exportFailedCount = failCount
                exportedRecordings = saved
                if failCount == 0 {
                    showExportComplete = true
                } else if successCount == 0 {
                    showExportFailed = true
                } else {
                    showExportPartial = true
                }
                manager.refreshStorageInfo()
            }
        }
    }
    
    private func exportSelectedWithConfirmation() {
        let selectedRecordings = manager.recordings.filter { selectedIDs.contains($0.id) }
        guard !selectedRecordings.isEmpty else { return }
        var successCount = 0
        var failCount = 0
        var saved: [Recording] = []

        exportTotal = selectedRecordings.count
        exportDone = 0
        exportProgress = 0
        isExporting = true

        Task {
            for rec in selectedRecordings {
                do {
                    try await PHPhotoLibrary.shared().performChanges {
                        let request = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: rec.url)
                        if let lat = rec.latitude, let lon = rec.longitude {
                            request?.location = CLLocation(latitude: lat, longitude: lon)
                        }
                        if let creation = rec.creation {
                            request?.creationDate = creation
                        }
                    }
                    successCount += 1
                    saved.append(rec)
                } catch {
                    failCount += 1
                    print("Failed to export \(rec.name): \(error)")
                }
                await MainActor.run {
                    exportDone += 1
                    exportProgress = Double(exportDone) / Double(exportTotal)
                }
            }

            await MainActor.run {
                isExporting = false
                exportedCount = successCount
                exportFailedCount = failCount
                exportedRecordings = saved
                if failCount == 0 {
                    showExportComplete = true
                } else if successCount == 0 {
                    showExportFailed = true
                } else {
                    showExportPartial = true
                }
                manager.refreshStorageInfo()
            }
        }
    }
}

// MARK: - Video Helpers
import UniformTypeIdentifiers
import AVKit

private struct RecordingModePickerView: View {
    let selectedMode: RecordingDisplayMode
    let isPremium: Bool
    let onSelect: (RecordingDisplayMode) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(RecordingDisplayMode.allCases) { mode in
                Button {
                    onSelect(mode)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: iconName(for: mode))
                            .frame(width: 28)
                            .foregroundStyle(.tint)

                        Text(mode.rawValue)
                            .foregroundStyle(.primary)

                        Spacer()

                        if mode.requiresPremium && !isPremium {
                            Image(systemName: "lock.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if mode == selectedMode {
                            Image(systemName: "checkmark")
                                .fontWeight(.semibold)
                                .foregroundStyle(.tint)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Recording Mode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func iconName(for mode: RecordingDisplayMode) -> String {
        switch mode {
        case .coverImage: return "photo"
        case .videoPlayback: return "play.rectangle.fill"
        case .fakeCall: return "phone.fill"
        case .tetris: return "gamecontroller.fill"
        case .flappyBird: return "bird.fill"
        case .bitcoin: return "bitcoinsign.circle.fill"
        case .calculator: return "plus.forwardslash.minus"
        case .ledBanner: return "textformat"
        case .currencyConverter: return "arrow.left.arrow.right"
        case .worldClock: return "clock.fill"
        case .travelDashboard: return "location.north.circle.fill"
        }
    }
}

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
            GeometryReader { geo in
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
                    .frame(width: geo.size.width, height: max(260, geo.size.height * 0.6))
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
import AVFoundation

struct VideoPreviewView: View {
    let recording: Recording
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var isLoading = true
    @State private var playbackError: String?
    @State private var loadTask: Task<Void, Never>?
    @State private var showTrimmer = false
    @State private var showTrimExportSuccess = false

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                VStack(spacing: 0) {
                    // Video Player
                    if let player = player {
                        VideoPlayer(player: player)
                            .frame(width: geo.size.width, height: max(260, geo.size.height * 0.6))
                            .background(Color.black)
                    } else {
                        VStack(spacing: 16) {
                            if isLoading {
                                ProgressView()
                                Text("Loading video...")
                                    .foregroundColor(.secondary)
                            } else {
                                Image(systemName: "video.slash")
                                    .font(.title2)
                                    .foregroundColor(.secondary)
                                Text(playbackError ?? "Unable to play this video.")
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                Button("Retry Playback") {
                                    startLoadingPlayback()
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                        .frame(width: geo.size.width, height: max(260, geo.size.height * 0.6))
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
            }
            .background(Color.black)
            .navigationTitle("Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        player?.pause()
                        showTrimmer = true
                    } label: {
                        Label("Trim", systemImage: "trim")
                    }
                    .disabled(player == nil)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        player?.pause()
                        loadTask?.cancel()
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showTrimmer) {
                VideoTrimmerView(recording: recording) { trimmedURL in
                    PHPhotoLibrary.shared().performChanges {
                        let req = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: trimmedURL)
                        if let lat = recording.latitude, let lon = recording.longitude {
                            req?.location = CLLocation(latitude: lat, longitude: lon)
                        }
                    }
                    showTrimExportSuccess = true
                }
            }
            .alert("Exported", isPresented: $showTrimExportSuccess) {
                Button("OK") {}
            } message: {
                Text("Trimmed video saved to your Photos library.")
            }
            .onAppear {
                startLoadingPlayback()
            }
            .onDisappear {
                player?.pause()
                player = nil
                loadTask?.cancel()
            }
        }
    }

    private func startLoadingPlayback() {
        loadTask?.cancel()
        loadTask = Task {
            await loadPlaybackWithRetry()
        }
    }

    private func loadPlaybackWithRetry() async {
        await MainActor.run {
            isLoading = true
            playbackError = nil
            player?.pause()
            player = nil
        }

        let maxAttempts = 8
        for attempt in 1...maxAttempts {
            if Task.isCancelled { return }

            let fileExists = FileManager.default.fileExists(atPath: recording.url.path)
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: recording.url.path)[.size] as? Int64) ?? 0

            if fileExists && fileSize > 1024 {
                let asset = AVURLAsset(url: recording.url)
                let isPlayable: Bool
                if #available(iOS 16.0, *) {
                    isPlayable = (try? await asset.load(.isPlayable)) ?? false
                } else {
                    isPlayable = asset.isPlayable
                }

                if isPlayable {
                    await MainActor.run {
                        player = AVPlayer(url: recording.url)
                        isLoading = false
                        playbackError = nil
                        player?.play()
                    }
                    return
                }
            }

            if attempt < maxAttempts {
                try? await Task.sleep(nanoseconds: 350_000_000)
            }
        }

        await MainActor.run {
            isLoading = false
            playbackError = "Video is still finalizing. Please retry in a moment."
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
