import Foundation
import AVFoundation
import UIKit

/// Handles safe recording with proper cleanup and interruption handling
class SafeRecordingHandler: NSObject {

    static let shared = SafeRecordingHandler()

    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private var activeRecordingURL: URL?

    // Silent background audio disabled (App Store guideline 2.5.4)
    private var silentAudioPlayer: AVAudioPlayer?
    private var isBackgroundAudioActive = false

    private override init() {
        super.init()
        setupNotifications()
    }

    // MARK: - Silent Audio Setup (Keeps App Alive in Background)
    private func prepareSilentAudio() {
        // Background audio is disabled for App Store compliance.
        return
        // Create a very short silent audio file in memory
        // This keeps the audio session active so iOS doesn't suspend us
        do {
            // Generate 0.5 seconds of silence (minimal CPU usage)
            let sampleRate: Double = 44100
            let duration: Double = 0.5
            let numSamples = Int(sampleRate * duration)

            var audioData = Data()

            // WAV header
            let headerSize: UInt32 = 44
            let dataSize: UInt32 = UInt32(numSamples * 2)
            let fileSize: UInt32 = headerSize + dataSize - 8

            // RIFF header
            audioData.append(contentsOf: "RIFF".utf8)
            audioData.append(contentsOf: withUnsafeBytes(of: fileSize.littleEndian) { Array($0) })
            audioData.append(contentsOf: "WAVE".utf8)

            // fmt chunk
            audioData.append(contentsOf: "fmt ".utf8)
            audioData.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) }) // chunk size
            audioData.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })  // PCM format
            audioData.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })  // mono
            audioData.append(contentsOf: withUnsafeBytes(of: UInt32(44100).littleEndian) { Array($0) }) // sample rate
            audioData.append(contentsOf: withUnsafeBytes(of: UInt32(88200).littleEndian) { Array($0) }) // byte rate
            audioData.append(contentsOf: withUnsafeBytes(of: UInt16(2).littleEndian) { Array($0) })  // block align
            audioData.append(contentsOf: withUnsafeBytes(of: UInt16(16).littleEndian) { Array($0) }) // bits per sample

            // data chunk
            audioData.append(contentsOf: "data".utf8)
            audioData.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Array($0) })

            // Silent samples (zeros)
            audioData.append(Data(count: Int(dataSize)))

            silentAudioPlayer = try AVAudioPlayer(data: audioData)
            silentAudioPlayer?.numberOfLoops = -1 // Loop forever
            silentAudioPlayer?.volume = 0.0 // Completely silent
            silentAudioPlayer?.prepareToPlay()

            print("✅ Silent audio player prepared for background execution")
        } catch {
            print("⚠️ Failed to prepare silent audio: \(error)")
        }
    }

    func startBackgroundAudio() {
        return
        guard !isBackgroundAudioActive else { return }

        // Ensure audio session is active before playing
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setActive(true)
            print("🔊 Audio session activated")
        } catch {
            print("⚠️ Failed to activate audio session: \(error)")
        }

        guard let player = silentAudioPlayer else {
            print("⚠️ Silent audio player not initialized!")
            return
        }

        let started = player.play()
        if started {
            isBackgroundAudioActive = true
            print("🔇 Background audio started (keeps app alive) - isPlaying: \(player.isPlaying)")
        } else {
            print("⚠️ Failed to start background audio!")
        }
    }

    func stopBackgroundAudio() {
        return
        guard isBackgroundAudioActive else { return }

        silentAudioPlayer?.stop()
        isBackgroundAudioActive = false
        print("🔇 Background audio stopped")
    }
    
    // MARK: - Setup Notifications
    private func setupNotifications() {
        // Monitor app lifecycle events
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillTerminate),
            name: UIApplication.willTerminateNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )

        // Background audio is disabled; no audio interruption handling needed.
    }
    
    @objc private func handleAudioSessionInterruption(notification: Notification) {
        return
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            print("🔇 Audio session interruption began - silent audio paused")
        case .ended:
            print("🔊 Audio session interruption ended - attempting to resume silent audio")
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) && isBackgroundAudioActive {
                    // Reclaim session and resume
                    try? AVAudioSession.sharedInstance().setActive(true)
                    silentAudioPlayer?.play()
                    print("✅ Silent audio resumed successfully")
                }
            }
        @unknown default:
            break
        }
    }
    
    // MARK: - Recording Session Management
    @MainActor
    func startRecordingSession(url: URL) {
        activeRecordingURL = url
        startBackgroundTask()
    }

    @MainActor
    func endRecordingSession() {
        activeRecordingURL = nil
        endBackgroundTask()
    }
    
    // MARK: - Background Task
    @MainActor
    private func startBackgroundTask() {
        // End existing task first
        endBackgroundTask()
        
        // Request extra time to finish recording if app goes to background
        backgroundTaskID = UIApplication.shared.beginBackgroundTask { [weak self] in
            // Called when time expires
            guard let self = self else { return }
            Task { @MainActor in
                self.handleBackgroundTimeout()
            }
        }
        
        // Monitor remaining time
        if backgroundTaskID != .invalid {
            let remainingTime = UIApplication.shared.backgroundTimeRemaining

            // Check if time is valid (not infinite)
            if remainingTime != .greatestFiniteMagnitude && remainingTime.isFinite {
                print("🕐 Background task started. Remaining time: \(Int(remainingTime))s")
            } else {
                print("🕐 Background task started. Remaining time: unlimited")
            }

            // Note: We no longer auto-end the background task after 25s because:
            // 1. Silent audio playback gives us unlimited background time
            // 2. The old 25s timeout was causing premature recording stops
            // The expiration handler will still be called if iOS decides to suspend us
        }
    }
    
    @MainActor
    private func endBackgroundTask() {
        if backgroundTaskID != .invalid {
            print("✅ Ending background task")
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
        }
    }
    
    @MainActor
    private func handleBackgroundTimeout() {
        // Background task is expiring - end to avoid termination.
        print("⚠️ Background task expiring - ending background task")
        endBackgroundTask()

        // Do not re-request background time without an eligible background mode.
    }
    
    // MARK: - App Lifecycle Handlers
    @objc private func handleAppWillResignActive() {
        // App losing focus (power button, incoming call, etc.)
        print("📱 App will resign active - continuing recording in background")

        // Previously this stopped recording, but now we continue in background
        // thanks to the silent audio playback keeping the app alive.
        // Only post SafeStopRecording if we need to stop for some reason
        // (handled by RecordingManager's interruption handlers instead)
    }
    
    @objc private func handleAppWillTerminate() {
        // App being force-closed by user or system
        print("🛑 App will terminate - emergency video save")
        
        // Last chance to save anything
        NotificationCenter.default.post(
            name: NSNotification.Name("EmergencyStopRecording"),
            object: nil
        )
    }
    
    @MainActor @objc private func handleAppDidEnterBackground() {
        print("🌙 App entered background - maintaining background task")

        // Ensure we have background time
        if backgroundTaskID == .invalid {
            startBackgroundTask()
        }
    }
    
    // MARK: - Disk Space Monitoring
    func checkDiskSpace() -> (available: Int64, isLow: Bool) {
        let fileURL = URL(fileURLWithPath: NSHomeDirectory())
        
        if let values = try? fileURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let capacity = values.volumeAvailableCapacityForImportantUsage {
            
            let minimumRequired: Int64 = 500 * 1024 * 1024 // 500MB minimum
            return (capacity, capacity < minimumRequired)
        }
        
        return (0, true)
    }
    
    // MARK: - Safe File Operations

    /// Synchronous file integrity check - only checks file size and basic attributes
    /// Use this for quick checks that won't block the main thread
    func verifyFileIntegrityQuick(at url: URL) -> Bool {
        // Check if file exists and is readable
        guard FileManager.default.fileExists(atPath: url.path) else {
            return false
        }

        // Quick check: verify file has reasonable size (more than 1KB)
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? Int64 {
            return size > 1024
        }

        return false
    }

    /// Async file integrity check - thoroughly verifies the file is playable
    /// This should be used when you can await the result
    func verifyFileIntegrity(at url: URL) async -> Bool {
        // Check if file exists and is readable
        guard FileManager.default.fileExists(atPath: url.path) else {
            return false
        }

        // Quick size check first
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? Int64,
           size < 1024 {
            return false
        }

        // Try to load the file as an asset to verify it's not corrupted
        let asset = AVAsset(url: url)

        // Check if asset is playable
        if #available(iOS 16.0, *) {
            return (try? await asset.load(.isPlayable)) ?? false
        } else {
            return asset.duration.seconds > 0
        }
    }

    func cleanupCorruptedFiles(in directory: URL) async {
        let fileManager = FileManager.default

        guard let files = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for file in files where file.pathExtension.lowercased() == "mov" {
            // Check file size - if it's very small, it's likely corrupted
            if let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize,
               size < 1024 { // Less than 1KB is definitely corrupted
                print("🗑️ Removing corrupted file: \(file.lastPathComponent)")
                try? fileManager.removeItem(at: file)
                continue
            }

            // Verify file integrity asynchronously (no deadlock risk)
            let isValid = await verifyFileIntegrity(at: file)
            if !isValid {
                print("🗑️ Removing unplayable file: \(file.lastPathComponent)")
                try? fileManager.removeItem(at: file)
            }
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        
        // End background task if still active
        if backgroundTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
        }
    }
}
