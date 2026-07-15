import Foundation
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
    case fakeCall = "Fake Call"
    case tetris = "Tetris"
    case flappyBird = "Flappy Bird"
    case bitcoin = "Bitcoin Price"
    case calculator = "Calculator"
    case ledBanner = "LED Banner"
    case currencyConverter = "Currency Converter"
    case worldClock = "World Clock"

    var id: String { rawValue }

    /// Whether this mode requires a premium subscription
    var requiresPremium: Bool {
        switch self {
        case .coverImage, .tetris:
            return false
        case .videoPlayback, .fakeCall, .flappyBird, .bitcoin, .calculator, .ledBanner, .currencyConverter, .worldClock:
            return true
        }
    }
}

enum CurrencyConverterBase: String, CaseIterable, Identifiable {
    case usdToVnd = "USD to VND"
    case vndToUsd = "VND to USD"

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
    case doubleTapHold = "Tap & Hold"
    case volumeUp = "Double-Press Vol Up"
    case volumeDown = "Double-Press Vol Down"

    var id: String { rawValue }

    func description(holdDuration: Int = 2) -> String {
        switch self {
        case .fourTaps: return "Tap screen 4 times quickly"
        case .fiveTaps: return "Tap screen 5 times quickly"
        case .swipeDown: return "Swipe down from top"
        case .swipeLeft: return "Swipe left across screen"
        case .swipeRight: return "Swipe right across screen"
        case .topLeftCorner: return "Tap top-left corner 5 times"
        case .topRightCorner: return "Tap top-right corner 5 times"
        case .doubleTapHold: return "Tap and hold for \(holdDuration) seconds"
        case .volumeUp: return "Press volume up twice quickly"
        case .volumeDown: return "Press volume down twice quickly"
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

// MARK: - Recording History Entry
struct RecordingHistoryEntry: Codable, Identifiable {
    let id: UUID
    let startDate: Date
    let duration: TimeInterval
    let segmentCount: Int
    let totalBytes: Int64
    let address: String?
    let latitude: Double?
    let longitude: Double?

    init(startDate: Date, duration: TimeInterval, segmentCount: Int, totalBytes: Int64, address: String?, latitude: Double?, longitude: Double?) {
        self.id = UUID()
        self.startDate = startDate
        self.duration = duration
        self.segmentCount = segmentCount
        self.totalBytes = totalBytes
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
    }
}

// MARK: - Recording Metadata (for persistence)
struct RecordingMetadata: Codable {
    let latitude: Double?
    let longitude: Double?
    let address: String?
    let locationPath: [LocationPoint]?
}

// MARK: - Recording Reliability
enum RecordingReliabilityLevel: Equatable {
    case checking
    case ready
    case warning
    case unavailable
}

struct RecordingReliabilityItem: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let level: RecordingReliabilityLevel
}

struct CompletedSegmentSummary: Equatable {
    let filename: String
    let duration: TimeInterval
    let size: Int64
    let completedAt: Date
}

struct RecordingReliabilityStatus: Equatable {
    let level: RecordingReliabilityLevel
    let items: [RecordingReliabilityItem]
    let estimatedRemainingDuration: TimeInterval?
    let lastSegment: CompletedSegmentSummary?

    static let checking = RecordingReliabilityStatus(
        level: .checking,
        items: [],
        estimatedRemainingDuration: nil,
        lastSegment: nil
    )

    var canStartRecording: Bool { level != .unavailable }
}

enum RecordingRecoveryState: Equatable {
    case idle
    case recording
    case interrupted(String)
    case recovering(attempt: Int)
    case failed(String)
}

// MARK: - RecordingManager
@MainActor
class RecordingManager: NSObject, ObservableObject {

    @Published var isRecording = false
    @Published var recordings: [Recording] = []
    @Published var isLoadingRecordings = true
    @Published var availableStorageBytes: Int64 = 0
    @Published var totalStorageBytes: Int64 = 0
    @Published var recordingHistory: [RecordingHistoryEntry] = []
    @Published var segmentLength: TimeInterval = 120
    @Published var selectedResolution: Resolution = .p1080
    @Published var audioOn = true
    @Published var enableStabilization = false
    @Published private(set) var reliabilityStatus: RecordingReliabilityStatus = .checking
    @Published private(set) var recoveryState: RecordingRecoveryState = .idle

    // NEW: Popup toggle, display mode, and stop gesture
    @Published var showFakePopups = true
    @Published var recordingDisplayMode: RecordingDisplayMode = .coverImage
    @Published var stopGesture: StopRecordingGesture = .fiveTaps
    @Published var holdDuration: Int = 2 // 1-10 seconds for tap & hold gesture

    @Published var cameraPosition: AVCaptureDevice.Position = .back
    @Published var cameraType: CameraType = .ultraWide
    @Published var selectedVideoURL: URL?
    @Published var showRecordingIndicator: Bool = true {
        didSet {
            UserDefaults.standard.set(showRecordingIndicator, forKey: "showRecordingIndicator")
        }
    }
    @Published var fakeCallContactName: String = "Customer Service" {
        didSet {
            UserDefaults.standard.set(fakeCallContactName, forKey: "fakeCallContactName")
        }
    }
    @Published var ledBannerText: String = "RECORDING" {
        didSet {
            UserDefaults.standard.set(ledBannerText, forKey: "ledBannerText")
        }
    }
    @Published var ledBannerUseNasalization: Bool = true {
        didSet {
            UserDefaults.standard.set(ledBannerUseNasalization, forKey: "ledBannerUseNasalization")
        }
    }
    @Published var ledBannerSpeed: Double = 40 {
        didSet {
            UserDefaults.standard.set(ledBannerSpeed, forKey: "ledBannerSpeed")
        }
    }
    @Published var converterBase: CurrencyConverterBase = .usdToVnd {
        didSet {
            UserDefaults.standard.set(converterBase.rawValue, forKey: "converterBase")
        }
    }
    @Published var converterAmount: String = "100" {
        didSet {
            UserDefaults.standard.set(converterAmount, forKey: "converterAmount")
        }
    }
    @Published var stealthBrightness: Bool = false {
        didSet {
            UserDefaults.standard.set(stealthBrightness, forKey: "stealthBrightness")
        }
    }
    @Published var autoStartOnLaunch: Bool = false {
        didSet {
            UserDefaults.standard.set(autoStartOnLaunch, forKey: "autoStartOnLaunch")
        }
    }

    private var captureSession: AVCaptureSession?
    private var movieOutput: AVCaptureMovieFileOutput?
    private var videoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?

    private var segmentTimer: DispatchSourceTimer?
    private let segmentTimerQueue = DispatchQueue(label: "com.jimwas.travelvid.segmentTimer")
    private var isSegmenting = false
    private var activeSegmentURL: URL?
    private var activeSegmentStartedAt: Date?
    private var recordingLocation: CLLocation?
    private var recordingPath: [LocationPoint] = []

    private var sessionStartDate: Date?
    private var sessionSegmentCount: Int = 0

    // Reliability monitoring
    private var watchdogTimer: Timer?
    private var lastRecordingCheck: Date?
    private var lastWatchdogStatsLogAt: Date?
    private var diskSpaceTimer: Timer?
    private var thermalStateObserver: NSObjectProtocol?
    private var lastRecordingErrorAt: Date?
    private var lastCompletedSegment: CompletedSegmentSummary?
    private var shouldResumeAfterInterruption = false
    private var recoveryPending = false
    private var recoveryTask: Task<Void, Never>?

    override init() {
        super.init()
        createDirectory()
        Task {
            await SafeRecordingHandler.shared.cleanupCorruptedFiles(in: directory())
            await loadRecordings()
        }
        setupSafetyNotifications()
        loadPersistedVideo()
        loadPersistedSettings()
        refreshStorageInfo()
        recordingHistory = loadHistory()
        refreshReliabilityStatus()
    }

    func refreshStorageInfo() {
        let space = SafeRecordingHandler.shared.checkDiskSpace()
        availableStorageBytes = space.available
        totalStorageBytes = space.total
    }

    func refreshReliabilityStatus() {
        refreshStorageInfo()

        var items: [RecordingReliabilityItem] = []
        var overall: RecordingReliabilityLevel = .ready

        let cameraAuthorization = AVCaptureDevice.authorizationStatus(for: .video)
        let cameraAvailable = bestDevice() != nil
        let preferredCameraAvailable: Bool
        if cameraPosition == .front {
            preferredCameraAvailable = AVCaptureDevice.default(
                .builtInWideAngleCamera,
                for: .video,
                position: .front
            ) != nil
        } else {
            preferredCameraAvailable = AVCaptureDevice.default(
                cameraType.avType,
                for: .video,
                position: .back
            ) != nil
        }
        let cameraLevel: RecordingReliabilityLevel
        let cameraDetail: String

        switch cameraAuthorization {
        case .authorized where cameraAvailable && preferredCameraAvailable:
            cameraLevel = .ready
            cameraDetail = cameraPosition == .front ? "Front camera ready" : "Back \(cameraType.rawValue) camera ready"
        case .authorized where cameraAvailable:
            cameraLevel = .warning
            cameraDetail = "Standard camera ready · \(cameraType.rawValue) unavailable"
        case .notDetermined:
            cameraLevel = .warning
            cameraDetail = "Permission will be requested when recording starts"
        case .authorized:
            cameraLevel = .unavailable
            cameraDetail = "Selected camera is unavailable"
        default:
            cameraLevel = .unavailable
            cameraDetail = "Camera access is disabled in Settings"
        }
        items.append(.init(id: "camera", title: "Camera", detail: cameraDetail, level: cameraLevel))
        overall = combinedReliabilityLevel(overall, cameraLevel)

        let microphoneAuthorization = AVCaptureDevice.authorizationStatus(for: .audio)
        let microphoneLevel: RecordingReliabilityLevel
        let microphoneDetail: String
        if !audioOn {
            microphoneLevel = .ready
            microphoneDetail = "Audio recording is turned off"
        } else {
            switch microphoneAuthorization {
            case .authorized:
                microphoneLevel = .ready
                microphoneDetail = "Recording audio"
            case .notDetermined:
                microphoneLevel = .warning
                microphoneDetail = "Permission will be requested when recording starts"
            default:
                microphoneLevel = .warning
                microphoneDetail = "Video will record without audio"
            }
        }
        items.append(.init(id: "microphone", title: "Microphone", detail: microphoneDetail, level: microphoneLevel))
        overall = combinedReliabilityLevel(overall, microphoneLevel)

        let storageLevel: RecordingReliabilityLevel
        if availableStorageBytes < 100 * 1_024 * 1_024 {
            storageLevel = .unavailable
        } else if availableStorageBytes < 500 * 1_024 * 1_024 {
            storageLevel = .warning
        } else {
            storageLevel = .ready
        }
        let remaining = estimatedRemainingRecordingDuration()
        let storageDetail = "\(formattedStorage(availableStorageBytes)) free" +
            (remaining.map { " · about \(formattedDuration($0)) remaining" } ?? "")
        items.append(.init(id: "storage", title: "Storage", detail: storageDetail, level: storageLevel))
        overall = combinedReliabilityLevel(overall, storageLevel)

        items.append(.init(
            id: "segments",
            title: "Segments",
            detail: "Every \(formattedDuration(segmentLength))",
            level: .ready
        ))

        let lastDetail: String
        if let lastCompletedSegment {
            lastDetail = "\(formattedClipDuration(lastCompletedSegment.duration)) · \(formattedStorage(lastCompletedSegment.size)) · \(lastCompletedSegment.completedAt.formatted(.relative(presentation: .named)))"
        } else {
            lastDetail = "No completed segment yet"
        }
        items.append(.init(id: "lastSegment", title: "Last saved", detail: lastDetail, level: .ready))

        reliabilityStatus = RecordingReliabilityStatus(
            level: overall,
            items: items,
            estimatedRemainingDuration: remaining,
            lastSegment: lastCompletedSegment
        )
    }

    private func combinedReliabilityLevel(
        _ current: RecordingReliabilityLevel,
        _ new: RecordingReliabilityLevel
    ) -> RecordingReliabilityLevel {
        if current == .unavailable || new == .unavailable { return .unavailable }
        if current == .warning || new == .warning { return .warning }
        if current == .checking || new == .checking { return .checking }
        return .ready
    }

    private func estimatedRemainingRecordingDuration() -> TimeInterval? {
        let recent = recordings.prefix(10).filter { $0.duration > 0 && $0.size > 0 }
        let measuredBytes = recent.reduce(Int64(0)) { $0 + $1.size }
        let measuredDuration = recent.reduce(0.0) { $0 + $1.duration }

        let bytesPerSecond: Double
        if measuredDuration > 0 && measuredBytes > 0 {
            bytesPerSecond = Double(measuredBytes) / measuredDuration
        } else {
            switch selectedResolution {
            case .p720: bytesPerSecond = 1_000_000
            case .p1080: bytesPerSecond = 2_000_000
            case .p4K: bytesPerSecond = 6_000_000
            }
        }

        guard bytesPerSecond > 0 else { return nil }
        return Double(max(0, availableStorageBytes - 100 * 1_024 * 1_024)) / bytesPerSecond
    }

    private func formattedStorage(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let totalMinutes = max(1, Int(duration / 60))
        if totalMinutes < 60 { return "\(totalMinutes) min" }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return minutes == 0 ? "\(hours) hr" : "\(hours) hr \(minutes) min"
    }

    private func formattedClipDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration.rounded()))
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    private func loadPersistedSettings() {
        if let savedContactName = UserDefaults.standard.string(forKey: "fakeCallContactName") {
            fakeCallContactName = savedContactName
        }
        if let savedBannerText = UserDefaults.standard.string(forKey: "ledBannerText") {
            ledBannerText = savedBannerText
        }
        if UserDefaults.standard.object(forKey: "showRecordingIndicator") != nil {
            showRecordingIndicator = UserDefaults.standard.bool(forKey: "showRecordingIndicator")
        }
        if UserDefaults.standard.object(forKey: "ledBannerUseNasalization") != nil {
            ledBannerUseNasalization = UserDefaults.standard.bool(forKey: "ledBannerUseNasalization")
        }
        if UserDefaults.standard.object(forKey: "ledBannerSpeed") != nil {
            ledBannerSpeed = UserDefaults.standard.double(forKey: "ledBannerSpeed")
        }
        if let savedConverterBase = UserDefaults.standard.string(forKey: "converterBase"),
           let converterBase = CurrencyConverterBase(rawValue: savedConverterBase) {
            self.converterBase = converterBase
        }
        if let savedConverterAmount = UserDefaults.standard.string(forKey: "converterAmount") {
            converterAmount = savedConverterAmount
        }
        if UserDefaults.standard.object(forKey: "stealthBrightness") != nil {
            stealthBrightness = UserDefaults.standard.bool(forKey: "stealthBrightness")
        }
        if UserDefaults.standard.object(forKey: "autoStartOnLaunch") != nil {
            autoStartOnLaunch = UserDefaults.standard.bool(forKey: "autoStartOnLaunch")
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

        // CRITICAL: Listen for AVCaptureSession interruptions
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSessionInterruption),
            name: .AVCaptureSessionWasInterrupted,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSessionInterruptionEnded),
            name: .AVCaptureSessionInterruptionEnded,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSessionRuntimeError),
            name: .AVCaptureSessionRuntimeError,
            object: nil
        )

        // Listen for audio session interruptions
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioSessionInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )

        // Monitor thermal state changes
        thermalStateObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleThermalStateChange()
            }
        }

        // Monitor memory warnings
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )

        // Monitor when app returns to foreground
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    // MARK: - Thermal State Monitoring
    private func handleThermalStateChange() {
        let state = ProcessInfo.processInfo.thermalState

        switch state {
        case .nominal:
            print("🌡️ Thermal state: Nominal")
        case .fair:
            print("🌡️ Thermal state: Fair - device warming up")
        case .serious:
            print("🔥 Thermal state: Serious - device is hot!")
            // Consider saving current segment more frequently
            if isRecording && segmentLength > 60 {
                print("📼 Forcing early segment save due to thermal pressure")
                rotateSegment()
            }
        case .critical:
            print("🚨 Thermal state: CRITICAL - iOS may kill camera soon!")
            if isRecording {
                print("🛑 Stopping recording due to critical thermal state")
                stopRecording()
                recoveryState = .failed("Recording stopped because the device became too hot")
            }
        @unknown default:
            break
        }
    }

    // MARK: - Memory Pressure Handling
    @objc private func handleMemoryWarning() {
        print("⚠️ Memory warning received!")

        if isRecording {
            // Force segment rotation to free up memory
            print("📼 Forcing segment save due to memory pressure")
            rotateSegment()
        }
    }

    // MARK: - Foreground Recovery
    @objc private func handleAppDidBecomeActive() {
        if isRecording {
            if captureSession?.isInterrupted == true {
                recoveryState = .interrupted("Waiting for the camera interruption to end")
            } else if recoveryPending {
                beginRecordingRecovery(reason: "Returned to foreground")
            } else {
                verifyRecordingActive()
            }
        }
        refreshReliabilityStatus()
    }

    private func verifyRecordingActive() {
        guard isRecording, let output = movieOutput else { return }

        guard canAttemptRestart() else {
            print("ℹ️ Skipping restart; app not active or session not ready")
            return
        }

        if !output.isRecording {
            print("🚨 Recording flag is true but movieOutput is not recording!")
            beginRecordingRecovery(reason: "Recording output stopped unexpectedly")
        } else {
            print("✅ Recording verified active")
            recoveryState = .recording
        }
    }

    // MARK: - Session Interruption Handling
    @objc private func handleSessionInterruption(_ notification: Notification) {
        if let sourceSession = notification.object as? AVCaptureSession,
           let captureSession,
           sourceSession !== captureSession {
            return
        }

        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVCaptureSessionInterruptionReasonKey] as? Int,
              let reason = AVCaptureSession.InterruptionReason(rawValue: reasonValue) else {
            return
        }

        print("⚠️ AVCaptureSession interrupted: \(reason)")
        guard isRecording else { return }

        shouldResumeAfterInterruption = true
        recoveryPending = true
        recoveryState = .interrupted(interruptionDescription(reason))
        stopSegmentTimer()

        if let output = movieOutput, output.isRecording, !isSegmenting {
            isSegmenting = true
            output.stopRecording()
        }

        switch reason {
        case .videoDeviceNotAvailableInBackground:
            print("📱 Camera paused by iOS in the background; preserving the completed segment")
        case .audioDeviceInUseByAnotherClient:
            print("🎤 Audio device taken by another app")
        case .videoDeviceInUseByAnotherClient:
            print("📷 Camera taken by another app")
        case .videoDeviceNotAvailableWithMultipleForegroundApps:
            print("📱 Camera not available with multiple foreground apps")
        case .videoDeviceNotAvailableDueToSystemPressure:
            print("🔥 System pressure - camera temporarily unavailable")
        case .sensitiveContentMitigationActivated:
            print("⚠️ Sensitive content mitigation activated - camera output may be limited")
        @unknown default:
            print("❓ Unknown interruption reason")
        }
    }

    @objc private func handleSessionInterruptionEnded(_ notification: Notification) {
        if let sourceSession = notification.object as? AVCaptureSession,
           let captureSession,
           sourceSession !== captureSession {
            return
        }
        print("✅ AVCaptureSession interruption ended")
        guard isRecording, shouldResumeAfterInterruption else { return }
        beginRecordingRecovery(reason: "Camera interruption ended")
    }

    @objc private func handleSessionRuntimeError(_ notification: Notification) {
        if let sourceSession = notification.object as? AVCaptureSession,
           let captureSession,
           sourceSession !== captureSession {
            return
        }
        guard let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError else {
            return
        }

        print("🚨 AVCaptureSession runtime error: \(error.localizedDescription)")
        guard isRecording else { return }

        lastRecordingErrorAt = Date()
        shouldResumeAfterInterruption = true
        recoveryPending = true
        recoveryState = .interrupted(error.localizedDescription)
        stopSegmentTimer()

        if let output = movieOutput, output.isRecording, !isSegmenting {
            isSegmenting = true
            output.stopRecording()
        }

        beginRecordingRecovery(
            reason: error.localizedDescription,
            rebuildSession: error.code == .mediaServicesWereReset
        )
    }

    @objc private func handleAudioSessionInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            print("🔇 Audio session interrupted (phone call, Siri, etc.)")
            if isRecording {
                shouldResumeAfterInterruption = true
                recoveryState = .interrupted("Audio interrupted")
            }
        case .ended:
            print("🔊 Audio session interruption ended")
            guard isRecording else { return }
            let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume) || shouldResumeAfterInterruption {
                beginRecordingRecovery(reason: "Audio interruption ended")
            }
        @unknown default:
            break
        }
    }

    private func interruptionDescription(_ reason: AVCaptureSession.InterruptionReason) -> String {
        switch reason {
        case .videoDeviceNotAvailableInBackground: return "Camera paused while app is in background"
        case .audioDeviceInUseByAnotherClient: return "Microphone is being used by another app"
        case .videoDeviceInUseByAnotherClient: return "Camera is being used by another app"
        case .videoDeviceNotAvailableWithMultipleForegroundApps: return "Camera unavailable during multitasking"
        case .videoDeviceNotAvailableDueToSystemPressure: return "Camera paused due to system pressure"
        case .sensitiveContentMitigationActivated: return "Camera temporarily restricted by iOS"
        @unknown default: return "Camera temporarily interrupted"
        }
    }

    private func beginRecordingRecovery(reason: String, rebuildSession: Bool = false) {
        guard isRecording else { return }

        recoveryTask?.cancel()
        recoveryTask = Task { [weak self] in
            guard let self else { return }

            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }

            for attempt in 1...3 {
                guard self.isRecording, !Task.isCancelled else { return }
                self.recoveryState = .recovering(attempt: attempt)

                var finalizationChecks = 0
                while self.isSegmenting && finalizationChecks < 20 {
                    try? await Task.sleep(for: .milliseconds(100))
                    finalizationChecks += 1
                }

                guard UIApplication.shared.applicationState == .active else {
                    self.recoveryState = .interrupted("Waiting for TravelVid to return to the foreground")
                    return
                }

                if self.captureSession?.isInterrupted == true {
                    self.recoveryState = .interrupted("Waiting for the camera interruption to end")
                    return
                }

                try? AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)

                let needsRebuild = rebuildSession || attempt > 1 || self.captureSession == nil || self.movieOutput == nil
                let sessionReady = await self.makeCaptureSessionReady(rebuild: needsRebuild)

                if sessionReady, let output = self.movieOutput {
                    if !output.isRecording {
                        let url = self.nextURL()
                        self.activeSegmentURL = url
                        self.activeSegmentStartedAt = Date()
                        self.isSegmenting = false
                        self.recoveryPending = false
                        output.startRecording(to: url, recordingDelegate: self)
                    } else {
                        self.recoveryPending = false
                    }

                    self.shouldResumeAfterInterruption = false
                    self.recoveryState = .recording
                    self.startSegmentTimer()
                    self.startWatchdogTimer()
                    self.startDiskSpaceMonitoring()
                    self.refreshReliabilityStatus()
                    print("▶️ Recording recovered in a new segment after: \(reason)")
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    return
                }

                try? await Task.sleep(for: .milliseconds(500 * attempt))
            }

            let message = "Unable to restart the camera after \(reason.lowercased())"
            self.recoveryPending = false
            self.shouldResumeAfterInterruption = false
            self.stopRecording()
            self.recoveryState = .failed(message)
            self.refreshReliabilityStatus()
            print("❌ \(message)")
        }
    }

    private func makeCaptureSessionReady(rebuild: Bool) async -> Bool {
        if rebuild {
            if let oldSession = captureSession, oldSession.isRunning {
                await withCheckedContinuation { continuation in
                    DispatchQueue.global(qos: .userInitiated).async {
                        oldSession.stopRunning()
                        continuation.resume()
                    }
                }
            }
            captureSession = nil
            movieOutput = nil
            videoInput = nil
            audioInput = nil
            return await prepareSession()
        }

        guard let session = captureSession else { return false }
        if session.isRunning { return true }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                session.startRunning()
                let running = session.isRunning
                DispatchQueue.main.async {
                    continuation.resume(returning: running)
                }
            }
        }
    }

    @objc private func handleSafeStop() {
        print("🛡️ Safe stop requested")
        // Note: We no longer automatically stop recording here.
        // With background audio mode enabled, recording can continue in background.
        // This handler is now only called for critical situations like imminent termination.
        // For normal backgrounding, we let recording continue.
    }
    
    @objc private func handleEmergencyStop() {
        print("🚨 Emergency stop - forcing immediate save")
        if isRecording {
            isRecording = false
            stopSegmentTimer()
            
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

        applyPreset(to: session)

        guard configureInputs(session: session, micEnabled: mic) else {
            session.commitConfiguration()
            return false
        }

        if !configureOutput(session: session) {
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

        // Start location tracking early to get a fix before recording starts
        LocationManager.shared.startTracking()

        return true
    }

    func reconfigureSessionIfNeeded() async {
        guard let session = captureSession else { return }
        guard !isRecording else { return }

        let cam = await requestVideo()
        if !cam { return }

        let mic = audioOn ? await requestAudio() : true

        session.beginConfiguration()
        applyPreset(to: session)

        if let vInput = videoInput {
            session.removeInput(vInput)
            videoInput = nil
        }
        if let aInput = audioInput {
            session.removeInput(aInput)
            audioInput = nil
        }

        guard configureInputs(session: session, micEnabled: mic) else {
            session.commitConfiguration()
            return
        }

        if movieOutput == nil {
            _ = configureOutput(session: session)
        } else if enableStabilization,
                  let output = movieOutput,
                  let connection = output.connection(with: .video),
                  connection.isVideoStabilizationSupported {
            connection.preferredVideoStabilizationMode = .standard
        }

        session.commitConfiguration()
    }

    private func applyPreset(to session: AVCaptureSession) {
        var presetToUse = selectedResolution.preset
        if !session.canSetSessionPreset(presetToUse) {
            logger.warning("Requested preset \(presetToUse.rawValue) not supported, trying fallback")
            let fallbacks: [AVCaptureSession.Preset] = [.hd1920x1080, .hd1280x720, .high]
            presetToUse = fallbacks.first { session.canSetSessionPreset($0) } ?? .high
        }
        session.sessionPreset = presetToUse
    }

    private func configureInputs(session: AVCaptureSession, micEnabled: Bool) -> Bool {
        guard let vdevice = bestDevice() else {
            logger.error("No suitable camera device found")
            return false
        }

        do {
            let vInput = try AVCaptureDeviceInput(device: vdevice)
            if session.canAddInput(vInput) {
                session.addInput(vInput)
                videoInput = vInput
            } else {
                logger.error("Cannot add video input to session")
                return false
            }
        } catch {
            logger.error("Failed to create video input: \(error.localizedDescription)")
            return false
        }

        if micEnabled, let micDev = AVCaptureDevice.default(for: .audio) {
            do {
                let aInput = try AVCaptureDeviceInput(device: micDev)
                if session.canAddInput(aInput) { session.addInput(aInput); audioInput = aInput }
            } catch {
                logger.warning("Failed to add audio input: \(error.localizedDescription)")
            }
        }

        return true
    }

    private func configureOutput(session: AVCaptureSession) -> Bool {
        let movie = AVCaptureMovieFileOutput()
        if session.canAddOutput(movie) {
            session.addOutput(movie)
            movieOutput = movie

            if enableStabilization, let connection = movie.connection(with: .video) {
                if connection.isVideoStabilizationSupported {
                    connection.preferredVideoStabilizationMode = .standard
                }
            }
            return true
        } else {
            logger.error("Cannot add movie output to session")
            return false
        }
    }

    private func bestDevice() -> AVCaptureDevice? {
        if cameraPosition == .front {
            return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        }

        return AVCaptureDevice.default(cameraType.avType, for: .video, position: .back)
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
    }

    // MARK: - Recording
    @discardableResult
    func startRecording() -> Bool {
        guard let output = movieOutput else { return false }

        refreshReliabilityStatus()
        guard reliabilityStatus.canStartRecording else {
            print("⛔️ Recording start blocked by reliability checks")
            return false
        }

        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()

        recoveryTask?.cancel()
        recoveryTask = nil
        recoveryPending = false
        shouldResumeAfterInterruption = false
        recoveryState = .recording
        isRecording = true
        isSegmenting = false
        sessionStartDate = Date()
        sessionSegmentCount = 0
        let url = nextURL()
        activeSegmentURL = url
        activeSegmentStartedAt = Date()

        // IMPORTANT: Start background audio BEFORE anything else
        // This must happen while app is in foreground to be effective
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
            
            // Capture initial location if we didn't have one at start
            if self.recordingLocation == nil {
                self.recordingLocation = location
            }
            
            let point = LocationPoint(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                timestamp: Date()
            )
            self.recordingPath.append(point)
        }

        output.startRecording(to: url, recordingDelegate: self)
        startSegmentTimer()
        startWatchdogTimer()
        startDiskSpaceMonitoring()
        return true
    }

    func stopRecording() {
        guard isRecording else { return }
        isRecording = false

        recoveryTask?.cancel()
        recoveryTask = nil
        recoveryPending = false
        shouldResumeAfterInterruption = false
        recoveryState = .idle

        UINotificationFeedbackGenerator().notificationOccurred(.success)

        stopSegmentTimer()
        activeSegmentStartedAt = nil
        watchdogTimer?.invalidate()
        diskSpaceTimer?.invalidate()
        movieOutput?.stopRecording()

        // Stop location tracking
        LocationManager.shared.stopTracking()
        LocationManager.shared.onLocationUpdate = nil

        // Append history entry
        if let start = sessionStartDate {
            let elapsed = Date().timeIntervalSince(start)
            let entry = RecordingHistoryEntry(
                startDate: start,
                duration: elapsed,
                segmentCount: max(1, sessionSegmentCount),
                totalBytes: 0,
                address: recordingLocation.flatMap { _ in nil },
                latitude: recordingLocation?.coordinate.latitude,
                longitude: recordingLocation?.coordinate.longitude
            )
            recordingHistory.insert(entry, at: 0)
            saveHistory(recordingHistory)
        }
        sessionStartDate = nil
        refreshReliabilityStatus()

        print("🛑 Recording stopped and all timers invalidated")
    }

    // MARK: - Segmentation
    private func startSegmentTimer() {
        stopSegmentTimer()

        let timer = DispatchSource.makeTimerSource(queue: segmentTimerQueue)
        timer.schedule(deadline: .now() + segmentLength, leeway: .seconds(1))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.rotateSegment()
            }
        }
        segmentTimer = timer
        timer.resume()
    }

    private func rotateSegment() {
        guard isRecording, !isSegmenting else { return }
        isSegmenting = true
        sessionSegmentCount += 1
        stopSegmentTimer()
        movieOutput?.stopRecording()
    }

    private func stopSegmentTimer() {
        guard let timer = segmentTimer else { return }
        segmentTimer = nil
        timer.setEventHandler {}
        timer.cancel()
    }

    // MARK: - Watchdog Timer (Detects Silent Recording Failures)
    private func startWatchdogTimer() {
        watchdogTimer?.invalidate()
        lastRecordingCheck = Date()
        lastWatchdogStatsLogAt = nil

        // Check every 10 seconds that recording is still active
        watchdogTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.watchdogCheck() }
        }
    }

    private func watchdogCheck() {
        guard isRecording else {
            watchdogTimer?.invalidate()
            return
        }

        guard let output = movieOutput else {
            print("🚨 Watchdog: movieOutput is nil while isRecording=true!")
            return
        }

        if !output.isRecording && !isSegmenting {
            print("🚨 Watchdog detected recording stopped unexpectedly!")
            recoveryPending = true
            beginRecordingRecovery(reason: "Watchdog detected a stopped recording")
            return
        }

        // Timer-based rotation can occasionally be delayed when the recorder is busy.
        // Use the actual segment start timestamp as a backstop so recordings still split.
        if let segmentStartedAt = activeSegmentStartedAt,
           !isSegmenting,
           Date().timeIntervalSince(segmentStartedAt) >= segmentLength + 5 {
            print("⏱️ Watchdog forcing overdue segment rotation")
            rotateSegment()
            return
        }

        // Log stats less frequently to reduce debug console overhead.
        let now = Date()
        if lastWatchdogStatsLogAt == nil || now.timeIntervalSince(lastWatchdogStatsLogAt ?? .distantPast) >= 60 {
            let recordedDuration = output.recordedDuration.seconds
            let fileSize = output.recordedFileSize
            print("📊 Watchdog: Recording active - \(Int(recordedDuration))s, \(fileSize / 1024)KB")
            lastWatchdogStatsLogAt = now
        }

        lastRecordingCheck = Date()
    }

    private func canAttemptRestart() -> Bool {
        if UIApplication.shared.applicationState != .active {
            return false
        }
        if let session = captureSession, !session.isRunning {
            return false
        }
        if isSegmenting {
            return false
        }
        if let lastError = lastRecordingErrorAt, Date().timeIntervalSince(lastError) < 5 {
            return false
        }
        return true
    }

    // MARK: - Disk Space Monitoring
    private func startDiskSpaceMonitoring() {
        diskSpaceTimer?.invalidate()

        // Check disk space every 30 seconds
        diskSpaceTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.checkDiskSpaceAndWarn() }
        }
    }

    private func checkDiskSpaceAndWarn() {
        let diskSpace = SafeRecordingHandler.shared.checkDiskSpace()
        let availableMB = diskSpace.available / 1024 / 1024
        refreshReliabilityStatus()

        if diskSpace.available < 100 * 1024 * 1024 { // Less than 100MB
            print("🚨 CRITICAL: Only \(availableMB)MB disk space left! Stopping recording.")
            stopRecording()
            recoveryState = .failed("Recording stopped because device storage is critically low")
            refreshReliabilityStatus()
        } else if diskSpace.available < 250 * 1024 * 1024 { // Less than 250MB
            print("⚠️ WARNING: Low disk space (\(availableMB)MB) - forcing segment save")
            rotateSegment()
        } else if diskSpace.isLow { // Less than 500MB
            print("⚠️ Disk space getting low: \(availableMB)MB available")
        }
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

    // MARK: - History Persistence
    private func historyURL() -> URL {
        directory().appendingPathComponent("history.json")
    }

    private func loadHistory() -> [RecordingHistoryEntry] {
        guard let data = try? Data(contentsOf: historyURL()),
              let entries = try? JSONDecoder().decode([RecordingHistoryEntry].self, from: data) else {
            return []
        }
        return entries
    }

    private func saveHistory(_ entries: [RecordingHistoryEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: historyURL(), options: .atomic)
    }

    func clearHistory() {
        recordingHistory = []
        saveHistory([])
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

        // Check disk space before copying
        let diskSpace = SafeRecordingHandler.shared.checkDiskSpace()
        let sourceSize = (try? FileManager.default.attributesOfItem(atPath: sourceURL.path)[.size] as? Int64) ?? 0
        let requiredSpace = sourceSize + 100 * 1024 * 1024 // file size + 100MB buffer
        if diskSpace.available < requiredSpace {
            throw NSError(domain: "TravelVidRecorder", code: 507,
                          userInfo: [NSLocalizedDescriptionKey: "Not enough storage space to save this video. Please free up space and try again."])
        }

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
        isLoadingRecordings = true
        let fm = FileManager.default
        let dir = directory()

        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.creationDateKey, .fileSizeKey])
        else {
            recordings = []
            isLoadingRecordings = false
            refreshReliabilityStatus()
            return
        }

        var list: [Recording] = []
        let metadataByFilename = loadMetadata()

        for url in files where url.pathExtension.lowercased() == "mov" {
            let attr = try? fm.attributesOfItem(atPath: url.path)
            let size = attr?[.size] as? Int64 ?? 0
            let creation = attr?[.creationDate] as? Date

            // Fast startup path: skip obviously corrupt tiny files without full AVAsset checks.
            if size < 1024 {
                continue
            }

            let asset = AVAsset(url: url)
            let duration: TimeInterval

            if #available(iOS 16, *) {
                duration = (try? await asset.load(.duration))?.seconds ?? 0
            } else {
                duration = asset.duration.seconds
            }

            // Load GPS metadata if available
            let metadata = metadataByFilename[url.lastPathComponent]

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
        if let latest = recordings.first {
            lastCompletedSegment = CompletedSegmentSummary(
                filename: latest.name,
                duration: latest.duration,
                size: latest.size,
                completedAt: latest.creation ?? Date()
            )
        }
        isLoadingRecordings = false
        refreshReliabilityStatus()
    }

    // MARK: - Export
    func exportAll() {
        for rec in recordings {
            exportRecording(rec)
        }
    }

    func exportRecording(_ rec: Recording) {
        // Check disk space before exporting — Photos needs room to import the video
        let diskSpace = SafeRecordingHandler.shared.checkDiskSpace()
        let requiredSpace = rec.size + 50 * 1024 * 1024 // file size + 50MB buffer
        guard diskSpace.available >= requiredSpace else {
            print("⚠️ Export skipped for \(rec.name): insufficient storage (\(diskSpace.available / 1024 / 1024)MB available, need \(requiredSpace / 1024 / 1024)MB)")
            return
        }
        refreshStorageInfo()
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
        if lastCompletedSegment?.filename == rec.name {
            lastCompletedSegment = recordings.first.map {
                CompletedSegmentSummary(
                    filename: $0.name,
                    duration: $0.duration,
                    size: $0.size,
                    completedAt: $0.creation ?? Date()
                )
            }
        }
        refreshStorageInfo()
        refreshReliabilityStatus()
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

            // CRITICAL: Check for recording errors
            if let error = error {
                print("🚨 Recording error: \(error.localizedDescription)")
                self.lastRecordingErrorAt = Date()

                // Check if any usable video was recorded despite the error
                let errorCode = (error as NSError).code
                let errorDomain = (error as NSError).domain

                // AVError codes that might still have partial video
                let partialVideoErrorCodes = [
                    AVError.diskFull.rawValue,
                    AVError.sessionWasInterrupted.rawValue,
                    AVError.deviceWasDisconnected.rawValue,
                    AVError.maximumFileSizeReached.rawValue
                ]

                if errorDomain == AVFoundationErrorDomain && partialVideoErrorCodes.contains(errorCode) {
                    print("⚠️ Recording ended with error but may have partial video - checking file...")
                    // Continue to check if file has any usable content
                } else {
                    print("❌ Recording failed completely: \(errorDomain) code \(errorCode)")
                    try? FileManager.default.removeItem(at: outputFileURL)
                    self.isSegmenting = false
                    self.activeSegmentStartedAt = nil
                    if self.isRecording {
                        self.recoveryPending = true
                        self.beginRecordingRecovery(reason: error.localizedDescription)
                    } else {
                        SafeRecordingHandler.shared.endRecordingSession()
                    }
                    return
                }
            }

            // Verify file exists and has content
            guard FileManager.default.fileExists(atPath: outputFileURL.path) else {
                print("❌ Recording file doesn't exist: \(outputFileURL.lastPathComponent)")
                self.isSegmenting = false
                self.activeSegmentStartedAt = nil
                if self.isRecording {
                    self.recoveryPending = true
                    self.beginRecordingRecovery(reason: "Completed segment file was missing")
                }
                return
            }

            let asset = AVAsset(url: outputFileURL)
            let duration: TimeInterval

            if #available(iOS 16, *) {
                duration = (try? await asset.load(.duration))?.seconds ?? 0
            } else {
                duration = asset.duration.seconds
            }

            // Skip files with no usable duration
            if duration < 0.5 {
                print("⚠️ Recording too short (\(duration)s) - discarding: \(outputFileURL.lastPathComponent)")
                try? FileManager.default.removeItem(at: outputFileURL)
                self.isSegmenting = false

                // Try to restart recording if we're still supposed to be recording
                if self.isRecording && !self.recoveryPending {
                    let newURL = self.nextURL()
                    self.activeSegmentStartedAt = Date()
                    output.startRecording(to: newURL, recordingDelegate: self)
                    self.activeSegmentURL = newURL
                    self.startSegmentTimer()
                } else {
                    self.activeSegmentStartedAt = nil
                }
                return
            }

            let attrs = try? FileManager.default.attributesOfItem(atPath: outputFileURL.path)
            let size = attrs?[.size] as? Int64 ?? 0
            let creation = attrs?[.creationDate] as? Date

            self.lastCompletedSegment = CompletedSegmentSummary(
                filename: outputFileURL.lastPathComponent,
                duration: duration,
                size: size,
                completedAt: Date()
            )
            self.refreshReliabilityStatus()

            // Verify file size is reasonable (at least 10KB for any video)
            if size < 10_000 {
                print("⚠️ Recording file too small (\(size) bytes) - may be corrupted")
            }

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

            print("✅ Saved segment: \(outputFileURL.lastPathComponent) (\(Int(duration))s, \(size / 1024)KB)")

            if self.isRecording {
                if self.recoveryPending {
                    self.activeSegmentStartedAt = nil
                    self.isSegmenting = false
                    print("⏸️ Segment saved; waiting for the camera interruption to end")
                } else if !output.isRecording {
                    let newURL = self.nextURL()
                    self.activeSegmentStartedAt = Date()
                    output.startRecording(to: newURL, recordingDelegate: self)
                    self.activeSegmentURL = newURL
                    self.isSegmenting = false
                    self.startSegmentTimer()
                } else {
                    // Recovery already started the next segment while metadata was finishing.
                    self.isSegmenting = false
                }
            } else {
                // Recording stopped - end background task immediately
                self.activeSegmentStartedAt = nil
                self.isSegmenting = false
                SafeRecordingHandler.shared.endRecordingSession()
            }
        }
    }
}
