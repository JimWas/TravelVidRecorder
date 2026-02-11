# Changelog

All notable changes to TravelVid Recorder will be documented in this file.

---

## [Unreleased] - 2025-02-09

### New Features

#### Video Preview
- Tap any recording in the library to preview/playback the video
- Full-screen video player with standard playback controls (play, pause, scrub)
- Auto-plays when opened
- Displays recording metadata: filename, duration, file size, location, creation date/time

#### Map View Improvements
- Fixed white screen when recording has no GPS data
- Now shows helpful "No Location Data" message with explanation
- Added "Open Settings" button to enable location permissions

### Recording Reliability Improvements

#### AVCaptureSession Handling
- Added `AVCaptureSessionWasInterrupted` notification observer to detect when camera is taken by another app
- Added `AVCaptureSessionInterruptionEnded` notification observer for recovery
- Added `AVCaptureSessionRuntimeError` notification observer with automatic restart on media services reset
- Recording now handles interruptions gracefully instead of silently failing

#### Audio Session Handling
- Added `AVAudioSession.interruptionNotification` observer
- Detects phone calls, Siri activation, and other audio interruptions
- Recording continues and resumes audio when interruption ends

#### Recording Delegate Error Handling
- Recording delegate now properly checks the `error` parameter (was previously ignored)
- Validates files have actual video content (>0.5s duration) before saving
- Discards corrupted/empty segments and automatically restarts recording
- Logs successful saves with duration and file size

#### Thermal State Monitoring
- Added `ProcessInfo.thermalStateDidChangeNotification` observer
- Forces segment save at "Serious" thermal state
- Stops recording at "Critical" thermal state to protect device
- Logs thermal state changes to console

#### Memory Pressure Handling
- Added `UIApplication.didReceiveMemoryWarningNotification` observer
- Forces segment save on low memory warning to prevent data loss

#### Watchdog Timer
- New 10-second watchdog timer verifies `movieOutput.isRecording` matches `isRecording` flag
- Automatically restarts recording if it silently stopped
- Logs recording stats (duration, file size) every 10 seconds

#### Disk Space Monitoring
- New 30-second disk space monitor during recording
- Warns at <500MB available
- Forces segment save at <250MB
- Stops recording at <100MB to prevent corruption

#### Foreground Recovery
- Added `UIApplication.didBecomeActiveNotification` observer
- Verifies recording is still active when app returns from background
- Attempts automatic restart if recording stopped unexpectedly

### Background Execution Improvements

#### Silent Audio Player
- Added silent audio player (0.5s WAV at 0% volume) to keep app alive indefinitely in background
- Audio session properly activated before playback
- Verifies audio is playing when entering background
- Restarts audio if needed during background task expiration

#### Background Task Management
- Removed aggressive 25-second auto-stop that was causing premature recording stops
- Background task now requests renewal when expiring
- Better logging of background task status

#### Info.plist
- Added `audio` to `UIBackgroundModes` array (was empty, causing background recording to fail)

### Developer Testing

#### Premium Sandbox Bypass
- Added `developerOverrideEnabled` flag in `SubscriptionManager.swift`
- Automatically unlocks all premium features in DEBUG builds
- Added `togglePremiumForTesting()` method for manual toggle
- Sandbox environment detection via receipt URL

### Documentation

#### CLAUDE.md
- Complete rewrite with comprehensive documentation (599 lines)
- Covers all managers, views, enums, and data models
- Includes recording flow, file storage structure, and notification system
- Added debugging tips and common modification guides

#### Documentation.md
- Copy of CLAUDE.md for general documentation purposes

### Bug Fixes

#### Build Errors Fixed
- Fixed MainActor isolation error in `BitcoinPriceView.swift` timer callback
- Fixed MainActor isolation error in `FlappyBirdView.swift` timer callback
- Fixed MainActor isolation error in `RecordingManager.swift` thermal notification
- Fixed deprecated `onChange(of:perform:)` in `CalculatorView.swift` (iOS 17+)
- Fixed unused variable warning in `CalculatorView.swift`

#### Location Manager
- Improved error handling with specific messages for permission denied vs location unavailable

### Console Logging

Added comprehensive logging throughout the app:
- `📊 Watchdog: Recording active - 45s, 12340KB` - Recording status
- `🌡️ Thermal state: Fair/Serious/Critical` - Device temperature
- `✅ Saved segment: filename.mov (120s, 245MB)` - Successful saves
- `⚠️ Disk space getting low: 450MB available` - Storage warnings
- `🚨 Watchdog detected recording stopped unexpectedly!` - Failure detection
- `🔇 Background audio started (keeps app alive)` - Background status
- `📍 Location permission denied` - Permission issues

---

## Previous Versions

### Initial Release
- Stealth video recording with decoy interfaces
- Cover Image, Video Playback, Fake Call modes
- Tetris, Flappy Bird, Bitcoin, Calculator game modes
- GPS tracking with reverse geocoding
- Video segmentation (1-10 minute chunks)
- Multiple resolutions (720p, 1080p, 4K)
- Front/back camera with wide/ultra-wide lens options
- Hardware volume button blocking
- Configurable stop gestures
- Premium subscription ($3.99/month with 2-week trial)
- AdMob rewarded ads for free users
- Export to Photos with GPS metadata
