import Foundation
import AVFoundation
import UIKit

/// Handles safe recording with proper cleanup and interruption handling
class SafeRecordingHandler: NSObject {
    
    static let shared = SafeRecordingHandler()
    
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private var activeRecordingURL: URL?
    
    private override init() {
        super.init()
        setupNotifications()
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
        
        // Monitor remaining time and warn if getting low
        if backgroundTaskID != .invalid {
            let remainingTime = UIApplication.shared.backgroundTimeRemaining
            
            // Check if time is valid (not infinite)
            if remainingTime != .greatestFiniteMagnitude && remainingTime.isFinite {
                print("🕐 Background task started. Remaining time: \(Int(remainingTime))s")
            } else {
                print("🕐 Background task started. Remaining time: unlimited")
            }
            
            // Schedule automatic cleanup before iOS force-kills us
            Task { @MainActor in
                // Wait for 25 seconds (leaving 5 second buffer before 30s limit)
                try? await Task.sleep(for: .seconds(25))
                
                if self.backgroundTaskID != .invalid {
                    print("⏰ Background task approaching limit - cleaning up")
                    self.endBackgroundTask()
                }
            }
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
        // Emergency cleanup if we run out of background time
        print("⚠️ Background task expiring - emergency cleanup")
        endBackgroundTask()
    }
    
    // MARK: - App Lifecycle Handlers
    @objc private func handleAppWillResignActive() {
        // App losing focus (power button, incoming call, etc.)
        print("📱 App will resign active - ensuring video file safety")
        
        // Post notification for RecordingManager to gracefully stop
        NotificationCenter.default.post(
            name: NSNotification.Name("SafeStopRecording"),
            object: nil
        )
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
        
        // Ensure we have background time to finish current segment
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
    func verifyFileIntegrity(at url: URL) -> Bool {
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
    func verifyFileIntegrityAsync(at url: URL) async -> Bool {
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
            let isValid = await verifyFileIntegrityAsync(at: file)
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
