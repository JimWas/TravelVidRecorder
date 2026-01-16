import Foundation
import AVFoundation
import Photos
import UIKit
import os
import CoreLocation

@preconcurrency import AVFoundation   // Suppress non-Sendable warnings

private let logger = Logger(subsystem: "TravelVidRecorder", category: "RecordingManager")

// MARK: - Resolution
enum Resolution: String, CaseIterable, Identifiable {
    case p720 = "720p"
    case p1080 = "1080p"
    case p4K = "4K"

    var id: String { rawValue }

    var preset: AVCaptureSession.Preset {
        switch self {
        case .p720: return .hd1280x720
        case .p1080: return .hd1920x1080
        case .p4K: return .hd4K3840x2160
        }
    }
}

// MARK: - CameraType
enum CameraType: String, CaseIterable, Identifiable {
    case wide = "Wide"
    case ultraWide = "Ultra-Wide"

    var id: String { rawValue }

    var avType: AVCaptureDevice.DeviceType {
        switch self {
        case .wide: return .builtInWideAngleCamera
        case .ultraWide: return .builtInUltraWideCamera
        }
    }
}

// MARK: - RecordingDisplayMode
enum RecordingDisplayMode: String, CaseIterable, Identifiable {
    case coverImage = "Cover Image"
    case videoPlayback = "Video Playback"
    case fakeCall = "Phone Call"
    case tetris = "Tetris"
    case flappyBird = "Flappy Bird"
    case bitcoin = "Bitcoin Price"

    var id: String { rawValue }
}

// MARK: - Stop Recording Gesture
enum StopRecordingGesture: String, CaseIterable, Identifiable {
    case fourTaps = "4 Taps Anywhere"
    case fiveTaps = "5 Taps Anywhere"
    case swipeDown = "Swipe Down"
    case swipeLeft = "Swipe Left"
    case swipeRight = "Swipe Right"
    case topLeftCorner = "5 Taps Top-Left Corner"
    case topRightCorner = "5 Taps Top-Right Corner"
    case doubleTapHold = "Double Tap & Hold (2s)"
    
    var id: String { rawValue }
    
    var description: String {
        switch self {
        case .fourTaps: return "Tap screen 4 times quickly"
        case .fiveTaps: return "Tap screen 5 times quickly"
        case .swipeDown: return "Swipe down from top"
        case .swipeLeft: return "Swipe left across screen"
        case .swipeRight: return "Swipe right across screen"
        case .topLeftCorner: return "Tap top-left corner 5 times"
        case .topRightCorner: return "Tap top-right corner 5 times"
        case .doubleTapHold: return "Double tap then hold for 2 seconds"
        }
    }
}

// MARK: - Location Data
struct LocationPoint: Codable {
    let latitude: Double
    let longitude: Double
    let timestamp: Date
}

// MARK: - Recording Model
struct Recording: Identifiable {
    let id = UUID()
    let name: String
    let duration: TimeInterval
    let size: Int64
    let url: URL
    let creation: Date?
    let latitude: Double?
    let longitude: Double?
    let address: String?
    let locationPath: [LocationPoint]?
}

// MARK: - Recording Metadata (for persistence)
struct RecordingMetadata: Codable {
    let latitude: Double?
    let longitude: Double?
    let address: String?
    let locationPath: [LocationPoint]?
}

// MARK: - RecordingManager
@MainActor
class RecordingManager: NSObject, ObservableObject {

    @Published var isRecording = false
    @Published var recordings: [Recording] = []
    @Published var segmentLength: TimeInterval = 120
    @Published var selectedResolution: Resolution = .p1080
    @Published var audioOn = true
    @Published var enableStabilization = false

    // NEW: Popup toggle, display mode, and stop gesture
    @Published var showFakePopups = true
    @Published var recordingDisplayMode: RecordingDisplayMode = .coverImage
    @Published var stopGesture: StopRecordingGesture = .fiveTaps

    @Published var cameraPosition: AVCaptureDevice.Position = .back
    @Published var cameraType: CameraType = .wide
    @Published var selectedVideoURL: URL?
    @Published var fakeCallContactName: String = "Customer Service" {
        didSet {
            UserDefaults.standard.set(fakeCallContactName, forKey: "fakeCallContactName")
        }
    }

    private var captureSession: AVCaptureSession?
    private var movieOutput: AVCaptureMovieFileOutput?
    private var videoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?

    private var segmentTimer: Timer?
    private var isSegmenting = false
    private var activeSegmentURL: URL?
    private var recordingLocation: CLLocation?
    private var recordingPath: [LocationPoint] = []

    override init() {
        super.init()
        createDirectory()
        Task { await loadRecordings() }
        setupSafetyNotifications()
        loadPersistedVideo()
        loadPersistedSettings()
    }

    private func loadPersistedSettings() {
        if let savedContactName = UserDefaults.standard.string(forKey: "fakeCallContactName") {
            fakeCallContactName = savedContactName
        }
    }
    
    // MARK: - Safety Notifications (NEW)
    private func setupSafetyNotifications() {
        // Listen for safe stop requests
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSafeStop),
            name: NSNotification.Name("SafeStopRecording"),
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleEmergencyStop),
            name: NSNotification.Name("EmergencyStopRecording"),
            object: nil
        )
    }
    
    @objc private func handleSafeStop() {
        print("🛡️ Safe stop requested - gracefully stopping recording")
        if isRecording {
            // Stop recording immediately when app backgrounds
            stopRecording()
        }
    }
    
    @objc private func handleEmergencyStop() {
        print("🚨 Emergency stop - forcing immediate save")
        if isRecording {
            isRecording = false
            segmentTimer?.invalidate()
            
            // Force synchronous stop
            movieOutput?.stopRecording()
        }
    }

    // MARK: - Permissions
    private func requestVideo() async -> Bool {
        await withCheckedContinuation { cont in
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: cont.resume(returning: true)
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video) { allowed in cont.resume(returning: allowed) }
            default: cont.resume(returning: false)
            }
        }
    }

    private func requestAudio() async -> Bool {
        await withCheckedContinuation { cont in
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized: cont.resume(returning: true)
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .audio) { allowed in cont.resume(returning: allowed) }
            default: cont.resume(returning: false)
            }
        }
    }

    // MARK: - Session Setup
    func prepareSession() async -> Bool {
        let cam = await requestVideo()
        if !cam {
            logger.error("Camera permission denied")
            return false
        }

        let mic = audioOn ? await requestAudio() : true

        let session = AVCaptureSession()
        session.beginConfiguration()

        // Try to set the requested preset, fall back to lower resolutions if not supported
        var presetToUse = selectedResolution.preset
        if !session.canSetSessionPreset(presetToUse) {
            logger.warning("Requested preset \(presetToUse.rawValue) not supported, trying fallback")
            // Try fallback presets in order of preference
            let fallbacks: [AVCaptureSession.Preset] = [.hd1920x1080, .hd1280x720, .high]
            presetToUse = fallbacks.first { session.canSetSessionPreset($0) } ?? .high
        }
        session.sessionPreset = presetToUse

        // Video input
        guard let vdevice = bestDevice() else {
            logger.error("No suitable camera device found")
            session.commitConfiguration()
            return false
        }

        do {
            let vInput = try AVCaptureDeviceInput(device: vdevice)
            if session.canAddInput(vInput) {
                session.addInput(vInput)
                videoInput = vInput
            } else {
                logger.error("Cannot add video input to session")
                session.commitConfiguration()
                return false
            }
        } catch {
            logger.error("Failed to create video input: \(error.localizedDescription)")
            session.commitConfiguration()
            return false
        }

        // Audio input
        if mic, let micDev = AVCaptureDevice.default(for: .audio) {
            do {
                let aInput = try AVCaptureDeviceInput(device: micDev)
                if session.canAddInput(aInput) { session.addInput(aInput); audioInput = aInput }
            } catch {
                logger.warning("Failed to add audio input: \(error.localizedDescription)")
            }
        }

        // Output
        let movie = AVCaptureMovieFileOutput()
        if session.canAddOutput(movie) {
            session.addOutput(movie)
            movieOutput = movie

            // Enable stabilization if requested
            if enableStabilization, let connection = movie.connection(with: .video) {
                if connection.isVideoStabilizationSupported {
                    connection.preferredVideoStabilizationMode = .standard
                }
            }
        } else {
            logger.error("Cannot add movie output to session")
            session.commitConfiguration()
            return false
        }

        session.commitConfiguration()
        captureSession = session

        // Swift 6 safe – start session on background thread with timeout
        let sessionStarted = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            // Use a timeout to prevent hanging indefinitely
            var didResume = false
            let timeoutTask = DispatchWorkItem {
                if !didResume {
                    didResume = true
                    logger.error("Session start timed out")
                    continuation.resume(returning: false)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: timeoutTask)

            Task.detached {
                session.startRunning()
                DispatchQueue.main.async {
                    timeoutTask.cancel()
                    if !didResume {
                        didResume = true
                        continuation.resume(returning: session.isRunning)
                    }
                }
            }
        }

        if !sessionStarted {
            logger.error("Failed to start capture session")
            return false
        }

        return true
    }


    private func bestDevice() -> AVCaptureDevice? {
        if cameraPosition == .front {
            return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        }

        return AVCaptureDevice.default(cameraType.avType, for: .video, position: .back)
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
    }

    // MARK: - Recording
    func startRecording() {
        guard let output = movieOutput else { return }

        isRecording = true
        let url = nextURL()
        activeSegmentURL = url

        // NEW: Notify safety handler
        SafeRecordingHandler.shared.startRecordingSession(url: url)

        // NEW: Check disk space before starting
        let diskSpace = SafeRecordingHandler.shared.checkDiskSpace()
        if diskSpace.isLow {
            print("⚠️ Low disk space: \(diskSpace.available / 1024 / 1024)MB available")
        }

        // Start location tracking
        LocationManager.shared.startTracking()
        recordingLocation = LocationManager.shared.currentLocation
        recordingPath = []

        // Track location updates during recording
        LocationManager.shared.onLocationUpdate = { [weak self] location in
            guard let self = self, self.isRecording else { return }
            let point = LocationPoint(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                timestamp: Date()
            )
            self.recordingPath.append(point)
        }

        output.startRecording(to: url, recordingDelegate: self)
        startSegmentTimer()
    }

    func stopRecording() {
        guard isRecording else { return }
        isRecording = false

        segmentTimer?.invalidate()
        movieOutput?.stopRecording()

        // Stop location tracking
        LocationManager.shared.stopTracking()
        LocationManager.shared.onLocationUpdate = nil

        // NEW: Notify safety handler
        SafeRecordingHandler.shared.endRecordingSession()
    }

    // MARK: - Segmentation
    private func startSegmentTimer() {
        segmentTimer?.invalidate()

        segmentTimer = Timer.scheduledTimer(withTimeInterval: segmentLength, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.rotateSegment() }
        }
    }

    private func rotateSegment() {
        guard isRecording, !isSegmenting else { return }
        isSegmenting = true
        movieOutput?.stopRecording()
    }

    // MARK: - File Helpers
    private func nextURL() -> URL {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        let stamp = df.string(from: Date())
        let random = String(UUID().uuidString.prefix(6))
        return directory().appendingPathComponent("\(stamp)-\(random).mov")
    }

    private func directory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Videos")
    }

    private func createDirectory() {
        try? FileManager.default.createDirectory(at: directory(), withIntermediateDirectories: true)
    }

    // MARK: - Metadata Persistence
    private func metadataURL() -> URL {
        directory().appendingPathComponent("metadata.json")
    }

    private func loadMetadata() -> [String: RecordingMetadata] {
        guard let data = try? Data(contentsOf: metadataURL()),
              let metadata = try? JSONDecoder().decode([String: RecordingMetadata].self, from: data) else {
            return [:]
        }
        return metadata
    }

    private func saveMetadata(_ metadata: [String: RecordingMetadata]) {
        guard let data = try? JSONEncoder().encode(metadata) else { return }
        try? data.write(to: metadataURL())
    }

    private func saveRecordingMetadata(filename: String, latitude: Double?, longitude: Double?, address: String?, locationPath: [LocationPoint]?) {
        var metadata = loadMetadata()
        metadata[filename] = RecordingMetadata(latitude: latitude, longitude: longitude, address: address, locationPath: locationPath)
        saveMetadata(metadata)
    }

    private func getRecordingMetadata(filename: String) -> RecordingMetadata? {
        let metadata = loadMetadata()
        return metadata[filename]
    }

    // MARK: - Video Playback Persistence
    private func videoDirectory() -> URL {
        directory().appendingPathComponent("SelectedVideos")
    }

    private func createVideoDirectory() {
        try? FileManager.default.createDirectory(at: videoDirectory(), withIntermediateDirectories: true)
    }

    private func loadPersistedVideo() {
        if let filename = UserDefaults.standard.string(forKey: "selectedVideoFilename"),
           !filename.isEmpty {
            let url = videoDirectory().appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: url.path) {
                selectedVideoURL = url
            } else {
                // File was deleted, clear the preference
                UserDefaults.standard.removeObject(forKey: "selectedVideoFilename")
            }
        }
    }

    func saveSelectedVideo(from sourceURL: URL) async throws -> URL {
        createVideoDirectory()

        // Generate unique filename to avoid conflicts
        let filename = "selected-video-\(UUID().uuidString).mov"
        let destURL = videoDirectory().appendingPathComponent(filename)

        // Delete old video if exists
        if let oldURL = selectedVideoURL {
            try? FileManager.default.removeItem(at: oldURL)
        }

        // Copy file to app's directory
        try FileManager.default.copyItem(at: sourceURL, to: destURL)

        // Save filename to UserDefaults
        UserDefaults.standard.set(filename, forKey: "selectedVideoFilename")

        return destURL
    }

    func clearSelectedVideo() {
        if let url = selectedVideoURL {
            try? FileManager.default.removeItem(at: url)
        }
        selectedVideoURL = nil
        UserDefaults.standard.removeObject(forKey: "selectedVideoFilename")
    }

    // MARK: - Load existing
    private func loadRecordings() async {
        let fm = FileManager.default
        let dir = directory()
        
        // NEW: Clean up any corrupted files first
        await SafeRecordingHandler.shared.cleanupCorruptedFiles(in: dir)

        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.creationDateKey, .fileSizeKey])
        else { return }

        var list: [Recording] = []

        for url in files where url.pathExtension.lowercased() == "mov" {
            // NEW: Verify file integrity before adding to list
            guard SafeRecordingHandler.shared.verifyFileIntegrity(at: url) else {
                print("⚠️ Skipping corrupted file: \(url.lastPathComponent)")
                continue
            }
            
            let attr = try? fm.attributesOfItem(atPath: url.path)
            let size = attr?[.size] as? Int64 ?? 0
            let creation = attr?[.creationDate] as? Date

            let asset = AVAsset(url: url)
            let duration: TimeInterval

            if #available(iOS 16, *) {
                duration = (try? await asset.load(.duration))?.seconds ?? 0
            } else {
                duration = asset.duration.seconds
            }

            // Load GPS metadata if available
            let metadata = getRecordingMetadata(filename: url.lastPathComponent)

            list.append(Recording(name: url.lastPathComponent,
                                  duration: duration,
                                  size: size,
                                  url: url,
                                  creation: creation,
                                  latitude: metadata?.latitude,
                                  longitude: metadata?.longitude,
                                  address: metadata?.address,
                                  locationPath: metadata?.locationPath))
        }

        recordings = list.sorted { ($0.creation ?? .distantPast) > ($1.creation ?? .distantPast) }
    }

    // MARK: - Export
    func exportAll() {
        for rec in recordings {
            exportRecording(rec)
        }
    }

    func exportRecording(_ rec: Recording) {
        PHPhotoLibrary.shared().performChanges {
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
    }

    func deleteRecording(_ rec: Recording) {
        try? FileManager.default.removeItem(at: rec.url)
        recordings.removeAll { $0.id == rec.id }

        // Clean up metadata
        var metadata = loadMetadata()
        metadata.removeValue(forKey: rec.name)
        saveMetadata(metadata)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Delegate
extension RecordingManager: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {

        Task { @MainActor in

            let asset = AVAsset(url: outputFileURL)
            let duration: TimeInterval

            if #available(iOS 16, *) {
                duration = (try? await asset.load(.duration))?.seconds ?? 0
            } else {
                duration = asset.duration.seconds
            }

            let attrs = try? FileManager.default.attributesOfItem(atPath: outputFileURL.path)
            let size = attrs?[.size] as? Int64 ?? 0
            let creation = attrs?[.creationDate] as? Date

            // Save location data
            let latitude = self.recordingLocation?.coordinate.latitude
            let longitude = self.recordingLocation?.coordinate.longitude
            let path = self.recordingPath.isEmpty ? nil : self.recordingPath

            // Get address via reverse geocoding
            var address: String?
            if let location = self.recordingLocation {
                address = await LocationManager.shared.getAddress(for: location)
            }

            // Persist GPS metadata to disk
            self.saveRecordingMetadata(filename: outputFileURL.lastPathComponent,
                                       latitude: latitude,
                                       longitude: longitude,
                                       address: address,
                                       locationPath: path)

            recordings.insert(
                Recording(name: outputFileURL.lastPathComponent,
                          duration: duration,
                          size: size,
                          url: outputFileURL,
                          creation: creation,
                          latitude: latitude,
                          longitude: longitude,
                          address: address,
                          locationPath: path),
                at: 0
            )

            if self.isRecording {
                let newURL = self.nextURL()
                output.startRecording(to: newURL, recordingDelegate: self)
                self.isSegmenting = false
                self.activeSegmentURL = newURL
            } else {
                // Recording stopped - end background task immediately
                SafeRecordingHandler.shared.endRecordingSession()
            }
        }
    }
}
