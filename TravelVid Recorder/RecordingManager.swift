import Foundation
import AVFoundation
import Photos
import SwiftUI
import UIKit
import os

private let logger = Logger(subsystem: "TravelVidRecorder", category: "RecordingManager")

// MARK: - Resolution
enum Resolution: String, CaseIterable, Identifiable {
    case p720 = "720p"
    case p1080 = "1080p"
    case p2K = "2K"
    case p4K = "4K"

    var id: String { rawValue }

    var preset: AVCaptureSession.Preset {
        switch self {
        case .p1080: return .hd1920x1080
        case .p2K:   return .hd1920x1080 // placeholder
        case .p720:  return .hd1280x720
        case .p4K:   return .hd4K3840x2160
        }
    }
}

// MARK: - CameraType
enum CameraType: String, CaseIterable, Identifiable {
    case ultraWide = "Ultra-Wide"
    case wide = "Wide"
    case telephoto = "Telephoto"

    var id: String { rawValue }

    var avDeviceType: AVCaptureDevice.DeviceType {
        switch self {
        case .ultraWide: return .builtInUltraWideCamera
        case .telephoto: return .builtInTelephotoCamera
        case .wide:      return .builtInWideAngleCamera
        }
    }
}

// MARK: - Recording model
struct Recording: Identifiable {
    let id = UUID()
    let name: String
    let duration: TimeInterval
    let size: Int64
    let url: URL
    let creationDate: Date?
}

// MARK: - RecordingManager
@MainActor
class RecordingManager: NSObject, ObservableObject {

    // UI-facing state
    @Published var isRecording = false
    @Published var currentDuration: TimeInterval = 0
    @Published var selectedResolution: Resolution = .p1080
    @Published var audioOn = true
    @Published var recordings: [Recording] = []
    @Published var lastErrorMessage: String?
    @Published var selectedCameraType: CameraType = .ultraWide   // safer default than ultraWide
    @Published var lastSegmentSaved: Date?

    // segment length in seconds (default 2 min)
    @Published var segmentDuration: TimeInterval = 120

    // Capture session internals
    private var captureSession: AVCaptureSession?
    private var isSessionConfigured = false

    private var videoDeviceInput: AVCaptureDeviceInput?
    private var audioDeviceInput: AVCaptureDeviceInput?
    private var movieOutput: AVCaptureMovieFileOutput?

    private var activeSegmentURL: URL?

    // state flags
    private var isSegmenting = false
    private var isStoppingForGood = false

    // timers
    private var durationTimer: Timer?
    private var segmentTimer: Timer?

    // brightness
    private var originalBrightness: CGFloat = UIScreen.main.brightness
    private var brightnessDimmed = false

    // export prefs
    private var shouldAutoSave = true

    // background task
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    // MARK: - Init / Deinit
    override init() {
        super.init()
        createVideoDirectory()
        Task { await loadExistingRecordings() }
    }


    // MARK: - Public high-level entry point
    /// Call this from the UI before presenting RecordingView.
    /// Ensures permissions and a configured running session.
    func prepareIfAuthorized(
        resolution: Resolution,
        audioOn: Bool,
        cameraPosition: AVCaptureDevice.Position = .back
    ) async -> Bool {

        // Camera permission
        let camOK = await Self.requestVideoPermission()
        if !camOK {
            lastErrorMessage = "Camera access denied. Please enable it in Settings."
            return false
        }

        // Mic permission (optional if audioOn == false)
        var micOK = true
        if audioOn {
            micOK = await Self.requestAudioPermission()
            if !micOK {
                logger.warning("⚠️ Mic access denied, continuing video-only.")
            }
        }

        // Configure once
        configureSessionIfNeeded(
            resolution: resolution,
            audioOn: audioOn && micOK,
            cameraPosition: cameraPosition
        )

        // Start session
        if let session = captureSession, !session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async {
                session.startRunning()
                logger.info("✅ Session running")
            }
        }

        return true
    }

    // MARK: - Permissions
    private static func requestVideoPermission() async -> Bool {
        await withCheckedContinuation { cont in
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                cont.resume(returning: true)
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video) { allowed in
                    cont.resume(returning: allowed)
                }
            default:
                cont.resume(returning: false)
            }
        }
    }

    private static func requestAudioPermission() async -> Bool {
        await withCheckedContinuation { cont in
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized:
                cont.resume(returning: true)
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .audio) { allowed in
                    cont.resume(returning: allowed)
                }
            default:
                cont.resume(returning: false)
            }
        }
    }

    // MARK: - Session configuration
    private func configureSessionIfNeeded(
        resolution: Resolution,
        audioOn: Bool,
        cameraPosition: AVCaptureDevice.Position
    ) {
        if isSessionConfigured {
            // Update UI expectations without tearing apart a running session
            self.selectedResolution = resolution
            self.audioOn = audioOn
            return
        }

        selectedResolution = resolution
        self.audioOn = audioOn

        let session = AVCaptureSession()
        captureSession = session
        session.beginConfiguration()
        session.sessionPreset = resolution.preset

        // VIDEO INPUT
        let preferredType = selectedCameraType.avDeviceType
        let videoDevice = AVCaptureDevice.default(preferredType, for: .video, position: cameraPosition)
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: cameraPosition)

        guard let videoDevice else {
            lastErrorMessage = "No compatible camera."
            session.commitConfiguration()
            return
        }

        do {
            let vInput = try AVCaptureDeviceInput(device: videoDevice)
            if session.canAddInput(vInput) {
                session.addInput(vInput)
                videoDeviceInput = vInput
            } else {
                logger.error("❌ Cannot add video input")
            }
        } catch {
            lastErrorMessage = "Video input error: \(error.localizedDescription)"
            logger.error("Video input error: \(error.localizedDescription)")
        }

        // AUDIO INPUT
        if audioOn, let mic = AVCaptureDevice.default(for: .audio) {
            do {
                let aInput = try AVCaptureDeviceInput(device: mic)
                if session.canAddInput(aInput) {
                    session.addInput(aInput)
                    audioDeviceInput = aInput
                }
            } catch {
                logger.warning("Audio input failed: \(error.localizedDescription)")
            }
        }

        // MOVIE OUTPUT
        let movie = AVCaptureMovieFileOutput()
        if session.canAddOutput(movie) {
            session.addOutput(movie)
            movieOutput = movie
        } else {
            lastErrorMessage = "Cannot add movie output."
            logger.error("❌ Cannot add movie output")
        }

        session.commitConfiguration()
        isSessionConfigured = true

        setupInterruptionObservers()
        logger.info("🎛 Session configured (res: \(resolution.rawValue), audio:\(audioOn))")
    }

    // MARK: - Start / Stop recording
    func startRecording() {
        guard let session = captureSession,
              let output = movieOutput else {
            lastErrorMessage = "Session not ready."
            return
        }

        if !session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async {
                session.startRunning()
            }
        }

        // no-op if already rolling
        if isRecording { return }

        isStoppingForGood = false

        // build fresh file URL
        let url = getOutputURL()
        activeSegmentURL = url
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }

        beginBackgroundTaskIfNeeded()
        dimScreenForStealth()

        output.startRecording(to: url, recordingDelegate: self)

        // UI state
        isRecording = true
        currentDuration = 0
        startDurationTimer()
        startSegmentTimer()

        logger.info("🎥 Started recording: \(url.lastPathComponent)")
    }

    func stopRecording(autoSave: Bool = true) {
        // idempotent
        guard isRecording else { return }

        shouldAutoSave = autoSave
        isStoppingForGood = true

        stopDurationTimer()
        stopSegmentTimer()

        movieOutput?.stopRecording()
        logger.info("🟥 Stop recording called")
        // We do not set isRecording = false yet.
    }

    // MARK: - Segment rotation
    private func startSegmentTimer() {
        stopSegmentTimer()
        segmentTimer = Timer.scheduledTimer(withTimeInterval: segmentDuration, repeats: true) { [weak self] _ in
            self?.rotateRecordingSegment()
        }
    }

    private func stopSegmentTimer() {
        segmentTimer?.invalidate()
        segmentTimer = nil
    }

    private func rotateRecordingSegment() {
        guard isRecording, !isSegmenting else { return }
        isSegmenting = true
        logger.info("⏸ Rotating segment...")

        // finish current file
        movieOutput?.stopRecording()

        // slight pause for disk flush, then restart if still recording
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            guard self.isRecording, !self.isStoppingForGood else {
                self.isSegmenting = false
                return
            }

            let newURL = self.getOutputURL()
            self.activeSegmentURL = newURL

            if FileManager.default.fileExists(atPath: newURL.path) {
                try? FileManager.default.removeItem(at: newURL)
            }

            if let output = self.movieOutput {
                output.startRecording(to: newURL, recordingDelegate: self)
                logger.info("▶️ Started new segment: \(newURL.lastPathComponent)")
            }

            self.isSegmenting = false
        }
    }

    // MARK: - Timers
    private func startDurationTimer() {
        stopDurationTimer()
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.currentDuration += 0.1
            }
        }
    }

    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }

    // MARK: - File helpers
    private func getOutputURL() -> URL {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        let stamp = fmt.string(from: Date())
        let random = UUID().uuidString.prefix(6)
        let fileName = "TravelVid_\(stamp)_\(random).mov"
        return getVideoDirectory().appendingPathComponent(fileName)
    }

    private func getVideoDirectory() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("Videos", isDirectory: true)
    }

    private func createVideoDirectory() {
        let dir = getVideoDirectory()
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            logger.info("📂 Created video directory at \(dir.path)")
        }
    }

    // MARK: - Load recordings
    private func loadExistingRecordings() async {
        let dir = getVideoDirectory()

        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.fileSizeKey, .creationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        var list: [Recording] = []

        for url in files where ["mov", "mp4"].contains(url.pathExtension.lowercased()) {
            let attr = try? FileManager.default.attributesOfItem(atPath: url.path)
            let size = attr?[.size] as? Int64 ?? 0
            let creation = attr?[.creationDate] as? Date

            let asset = AVAsset(url: url)
            var duration: Double = 0
            do {
                if #available(iOS 16.0, *) {
                    let d = try await asset.load(.duration)
                    duration = d.seconds
                } else {
                    duration = asset.duration.seconds
                }
            } catch {}

            list.append(Recording(
                name: url.lastPathComponent,
                duration: duration,
                size: size,
                url: url,
                creationDate: creation
            ))
        }

        let sorted = list.sorted { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
        await MainActor.run {
            self.recordings = sorted
        }
    }

    // MARK: - Export / delete
    func exportToPhotos(_ recording: Recording) {
        PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: recording.url)
        } completionHandler: { success, error in
            if success {
                logger.info("✅ Exported \(recording.name)")
            } else {
                Task { @MainActor in
                    self.lastErrorMessage = "Export failed: \(error?.localizedDescription ?? "")"
                }
            }
        }
    }

    func deleteRecording(_ recording: Recording) {
        try? FileManager.default.removeItem(at: recording.url)
        recordings.removeAll { $0.id == recording.id }
        logger.info("🗑 Deleted \(recording.name)")
    }

    func deleteAllRecordings() {
        let dir = getVideoDirectory()
        if let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for f in files where ["mov", "mp4"].contains(f.pathExtension.lowercased()) {
                try? FileManager.default.removeItem(at: f)
            }
        }
        recordings.removeAll()
    }

    // MARK: - Interruption observers
    private func setupInterruptionObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionRuntimeError(_:)),
            name: .AVCaptureSessionRuntimeError,
            object: captureSession
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionWasInterrupted(_:)),
            name: .AVCaptureSessionWasInterrupted,
            object: captureSession
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionInterruptionEnded(_:)),
            name: .AVCaptureSessionInterruptionEnded,
            object: captureSession
        )
    }

    @objc private func appDidBecomeActive() {
        if let s = captureSession, !s.isRunning {
            DispatchQueue.global(qos: .userInitiated).async {
                s.startRunning()
            }
        }
    }

    @objc private func appWillResignActive() {
        if isRecording {
            stopRecording(autoSave: true)
        } else {
            captureSession?.stopRunning()
        }
        restoreBrightnessIfNeeded()
    }

    @objc private func sessionRuntimeError(_ note: Notification) {
        logger.error("⚠️ AVCaptureSessionRuntimeError")
        if let s = captureSession {
            DispatchQueue.global(qos: .userInitiated).async {
                if !s.isRunning { s.startRunning() }
            }
        }
    }

    @objc private func sessionWasInterrupted(_ note: Notification) {
        logger.warning("⏸ Session interrupted")
    }

    @objc private func sessionInterruptionEnded(_ note: Notification) {
        logger.info("▶️ Session interruption ended")
        if let s = captureSession, !s.isRunning {
            DispatchQueue.global(qos: .userInitiated).async {
                s.startRunning()
            }
        }
    }

    // MARK: - Brightness control
    private func dimScreenForStealth() {
        if !brightnessDimmed {
            originalBrightness = UIScreen.main.brightness
            UIScreen.main.brightness = 0.3
            brightnessDimmed = true
        }
    }

    private func restoreBrightnessIfNeeded() {
        if brightnessDimmed {
            UIScreen.main.brightness = originalBrightness
            brightnessDimmed = false
        }
    }

    // MARK: - Background task helpers
    private func beginBackgroundTaskIfNeeded() {
        if backgroundTaskID == .invalid {
            backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "RecordingBackgroundTask") {
                UIApplication.shared.endBackgroundTask(self.backgroundTaskID)
                self.backgroundTaskID = .invalid
            }
        }
    }

    private func endBackgroundTaskIfNeeded() {
        if backgroundTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
        }
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate
extension RecordingManager: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        Task { @MainActor in
            if let error {
                logger.error("⚠️ Recording delegate error: \(error.localizedDescription)")
            }

            // metadata for list
            let asset = AVAsset(url: outputFileURL)

            var duration: Double = 0
            do {
                if #available(iOS 16.0, *) {
                    duration = try await asset.load(.duration).seconds
                } else {
                    duration = asset.duration.seconds
                }
            } catch {
                logger.warning("Couldn't load duration for final asset")
            }

            let attrs = try? FileManager.default.attributesOfItem(atPath: outputFileURL.path)
            let size = (attrs?[.size] as? Int64) ?? 0
            let creation = attrs?[.creationDate] as? Date

            let rec = Recording(
                name: outputFileURL.lastPathComponent,
                duration: duration,
                size: size,
                url: outputFileURL,
                creationDate: creation
            )

            // prepend in UI list
            self.recordings.insert(rec, at: 0)

            // "segment saved" pulse
            self.lastSegmentSaved = Date()

            if self.isStoppingForGood {
                // Full stop path
                self.isRecording = false

                self.stopDurationTimer()
                self.stopSegmentTimer()

                self.restoreBrightnessIfNeeded()
                self.endBackgroundTaskIfNeeded()
            } else {
                // Continuing in a new segment --
                // reset visible timer.
                self.currentDuration = 0
            }

            logger.info("✅ Finalized segment: \(rec.name)")
        }
    }
}
