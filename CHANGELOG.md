# Changelog

All notable changes to TravelVid Recorder are documented here.  
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [Unreleased]

---

## [1.5.0] — 2026-06-27

### Added

#### In-App Video Trimmer
- New `VideoTrimmerView` — drag start/end handles on a scrubber timeline to trim any recording before export
- Trim toolbar button appears when previewing any recording in the library
- Uses `AVAssetExportSession` to write the trimmed clip to a temp file, then export to Photos
- Player seeks to the handle position as you drag so you can preview exactly what will be cut
- Export success alert on completion

#### Recording History Log
- New `RecordingHistoryView` — shows every session ever recorded: date, time, duration, segment count, and GPS location if available
- Accessible via clock icon in the main screen header
- All-time stats panel: total sessions, total recording time, sessions with GPS
- "Clear History" button with confirmation dialog
- History persisted to `Documents/Videos/history.json` across relaunches
- `RecordingHistoryEntry` struct (Codable/Identifiable): `id`, `startDate`, `duration`, `segmentCount`, `totalBytes`, `address`, `latitude`, `longitude`
- Session start tracking via `sessionStartDate` and `sessionSegmentCount` properties on `RecordingManager`
- History entry appended automatically in `stopRecording()` after each session

#### World Clock Decoy Mode
- New `WorldClockView` — 44 global cities, iOS Clock app style, black background
- Displays local time per city, day offset (TODAY / TOMORROW / YESTERDAY), and relative hour difference
- Live timer updates every second
- Cities include: New York, Los Angeles, Chicago, Toronto, São Paulo, London, Paris, Berlin, Rome, Madrid, Amsterdam, Stockholm, Dubai, Riyadh, Mumbai, Delhi, Bangkok, Singapore, Kuala Lumpur, Jakarta, Ho Chi Minh City, Phnom Penh, Siem Reap, Hanoi, Hong Kong, Taipei, Seoul, Tokyo, Shanghai, Beijing, Sydney, Melbourne, Auckland, Nairobi, Cairo, Johannesburg, Lagos, Casablanca, Istanbul, Moscow, Karachi, Dhaka, Colombo

#### Double-Press Volume Button Stop Gesture
- New `StopRecordingGesture` cases: `.volumeUp` ("Double-Press Vol Up") and `.volumeDown` ("Double-Press Vol Down")
- First press: light haptic feedback + starts 1-second window
- Second press within 1 second: fires stop gesture + medium haptic
- Pressing the opposite button resets the counter — prevents accidental triggers
- `HardwareButtonBlocker` rewritten with `onVolumeUp`, `onVolumeDown` callbacks and double-press timing logic
- `clearCallbacks()` method resets all state on recording stop

#### Auto-Start Recording on Launch
- Toggle in Advanced Settings to begin recording the moment the app opens
- Persisted to `UserDefaults` as `autoStartOnLaunch`
- Yellow bolt icon indicator in UI

#### Orphan File Cleanup
- `cleanupCorruptedFiles()` called on startup before loading the recording library
- Deletes `.mov` files under 1 KB (incomplete or zero-duration segments from crashes)
- Prevents the library from filling with unplayable orphan files

#### Auto-Resume After Phone Call
- `resumeAfterInterruption()` async method on `RecordingManager`
- Called when `AVAudioSession.InterruptionOptions.shouldResume` is set after a phone call ends
- Reactivates the audio session, restarts the capture session if needed, begins a new segment

#### Haptic Feedback
- `UIImpactFeedbackGenerator(style: .heavy)` fires on recording start
- `UINotificationFeedbackGenerator().notificationOccurred(.success)` fires on recording stop

---

## [1.4.0] — 2026-05-01

### Added

#### Storage Indicator
- Live storage bar on the main screen showing used vs. available space
- Bar fills with used space (same convention as iOS Settings — more fill = less room)
- Color shifts: green → orange → red as storage runs low
- Available and total GB displayed as text
- `refreshStorageInfo()` called on `RecordingManager` init and when the main view appears
- `SafeRecordingHandler.checkDiskSpace()` updated to return `(available, total, isLow)` tuple

#### Storage Check Before Export
- Export all videos now checks free space before starting
- Shows an alert if there isn't enough room, explains how many videos will fit
- Exports as many as will fit, then shows an honest result alert
- Three distinct outcome alerts: all saved, partial save (N of M saved), none saved

#### Export Progress Indicator
- Progress overlay shown while exporting multiple videos to Photos
- Displays "Saving X of Y…" counter
- Dismisses automatically when all exports complete

#### Quick-Delete After Export
- After saving videos to Photos, an alert offers to delete the in-app copies to free space
- "Delete from App" / "Keep in App" choice — non-destructive default

#### Cover Image Persistence
- Selected cover image saved to `Documents/Videos/cover_image.jpg` on picker change
- Loaded back automatically on every app launch — user never has to re-select after closing the app

#### Custom Promo Codes
- In-app promo code redemption (Apple offer codes are random strings, not human-readable)
- Valid codes: `NASAEMPLOYEES`, `TRAVELVIPFREE`, `JIMWAS2025`
- Code stored in `UserDefaults` as `redeemedPromoCode`; unlocks premium permanently on that device
- `SubscriptionManager.redeemPromoCode(_:) -> Bool`

#### World Clock Decoy Mode (placeholder)
- `.worldClock` added to `RecordingDisplayMode` enum
- Hero preview updated with clock icon placeholder (full view added in 1.5.0)

### Fixed

- **Inverted storage bar** — bar previously showed a full bar even when nearly out of space; now correctly fills with *used* space
- **Export always showing success** — export completion previously always displayed "Export Complete" regardless of failures; now accurately reports partial and full failure
- **OnboardingView non-exhaustive switch** — missing `.volumeUp`/`.volumeDown` cases in `stopGestureTitle` and `stopGestureDescription` switches

---

## [1.3.0] — 2026-03-15

### Added

#### Volume Button Stop Gestures (single-press, later revised to double-press in 1.5.0)
- `.volumeUp` and `.volumeDown` added to `StopRecordingGesture` enum
- `HardwareButtonBlocker` extended with `onVolumeUp` / `onVolumeDown` optional callbacks
- `RecordingView` wires the appropriate callback based on selected gesture

#### Auto-Start on Launch
- `autoStartOnLaunch` toggle in Advanced Settings
- `RecordingManager` reads the flag on init and begins recording automatically

---

## [1.2.0] — 2026-02-20

### Added

#### Performance Improvements

**Ad Loading**
- Switched AdMob initialization to lazy startup (first ad request) instead of app launch
- Added safe one-time SDK initialization queue to prevent duplicate startup calls

**Recording UI**
- Replaced fake popup pre-scheduling loop with a single repeating timer
- Eliminated thousands of queued `DispatchQueue.main.asyncAfter` tasks in long sessions
- Explicit popup timer cleanup on setting changes and view dismissal

**Watchdog Logging**
- Watchdog health checks remain at 10-second intervals
- Stats logging throttled to once per 60 seconds to reduce console/main-thread pressure

#### Video Preview
- Tap any recording in the library to preview and play the video
- Full-screen player with standard controls (play, pause, scrub)
- Auto-plays on open; displays filename, duration, file size, location, creation date

#### Map View Improvements
- Fixed white screen when recording has no GPS data
- Now shows "No Location Data" message with explanation and Settings deep-link button

### Fixed

- **MainActor isolation** — timer callbacks in `BitcoinPriceView`, `FlappyBirdView`, and `RecordingManager` thermal notification now correctly annotated
- **Deprecated `onChange`** — updated `CalculatorView` to use non-deprecated `onChange(of:)` form (iOS 17+)
- **Unused variable warning** in `CalculatorView`
- **Location Manager error handling** — specific messages for permission denied vs. location unavailable

---

## [1.1.0] — 2026-01-10

### Added

#### Recording Reliability

**AVCaptureSession Interruption Handling**
- `AVCaptureSessionWasInterrupted` observer detects when another app takes the camera
- `AVCaptureSessionInterruptionEnded` observer for automatic recovery
- `AVCaptureSessionRuntimeError` observer restarts session on media services reset

**Audio Session Interruption Handling**
- `AVAudioSession.interruptionNotification` observer
- Detects phone calls and Siri activation
- Resumes audio when interruption ends (foreground sessions)

**Recording Delegate Error Handling**
- Delegate now checks the `error` parameter (previously ignored)
- Validates segments are >0.5s before saving; discards and restarts on corrupt segments

**Thermal State Monitoring**
- `ProcessInfo.thermalStateDidChangeNotification` observer
- Forces segment rotation at "Serious" thermal state
- Stops recording at "Critical" to protect the device

**Memory Pressure Handling**
- `UIApplication.didReceiveMemoryWarningNotification` observer forces segment rotation

**Watchdog Timer**
- 10-second timer verifies `movieOutput.isRecording` matches `isRecording` flag
- Auto-restarts recording if it silently stopped

**Disk Space Monitoring**
- 30-second monitor during recording
- Warns at <500 MB, forces rotation at <250 MB, stops at <100 MB

**Foreground Recovery**
- `UIApplication.didBecomeActiveNotification` verifies recording is still active
- Auto-restarts if recording stopped while app was backgrounded

#### Background Task Management
- Removed 25-second auto-stop that caused premature recording ends
- Better logging of background task lifecycle

### Changed

- Removed `audio` from `UIBackgroundModes` for App Store compliance

### Fixed

- **Duplicate ad failure delegate** — AdMob delegate was registered twice, causing redundant callbacks
- **Stop gesture capture layer** — gestures weren't captured when fake popups were disabled
- **Fake popup dismissal** — stop gestures now disabled while a popup is being dismissed
- **Map sheet sizing** — full map sheet no longer clips on smaller devices

---

## [1.0.0] — 2025-12-01 — Initial Release

### Features

- Stealth video recording behind configurable decoy interfaces
- **Decoy modes**: Cover Image (free), Video Playback, Fake Call, Tetris (free), Flappy Bird, Bitcoin Price Tracker, Calculator
- GPS tracking with reverse geocoding; location path recorded during session
- Video segmentation: 1–10 minute chunks, configurable
- Resolutions: 720p, 1080p, 4K
- Front/back camera; wide and ultra-wide lens
- Hardware volume button blocking (KVO on `AVAudioSession.outputVolume` + hidden `MPVolumeView` slider)
- Configurable stop gestures: 4 taps, 5 taps, swipe down/left/right, top-left/right corner 5 taps, tap-and-hold
- Recording indicator toggle (hidden dot shows live recording status)
- Premium subscription: $3.99/month with 2-week free trial (StoreKit v2, product ID `com.jimwas.travelvid.premium`)
- AdMob rewarded ads for free user exports; interstitial on video playback
- Export to Photos with embedded GPS metadata
- Library with thumbnail, duration, size, map preview per recording
- Batch export and delete with select mode
- Onboarding flow: permissions walkthrough + stop gesture tutorial

---

## Console Log Reference

| Emoji | Meaning |
|-------|---------|
| `📊` | Watchdog stats (duration, file size every ~60s) |
| `🌡️` | Thermal state change (Fair / Serious / Critical) |
| `✅` | Segment saved successfully |
| `⚠️` | Disk space warning |
| `🚨` | Watchdog detected recording stopped unexpectedly |
| `📍` | Location permission or update event |

---

## Architecture Notes for Future Developers

- All managers use `@MainActor` — never call `@Published` setters from a background thread without `await MainActor.run {}`
- `PBXFileSystemSynchronizedRootGroup` is used in the Xcode project — new `.swift` files added to the `TravelVid Recorder/` folder are picked up automatically, no need to edit `project.pbxproj`
- Premium is auto-unlocked in DEBUG builds via `developerOverrideEnabled` in `SubscriptionManager.swift`; set to `false` to test the paywall
- AdMob initializes lazily on the first ad request — do not call `initializeAdMob()` at app launch
- SourceKit reports false "Cannot find X in scope" errors on this project due to cross-file symbol resolution; always verify with `xcodebuild` before concluding there is a real compiler error
