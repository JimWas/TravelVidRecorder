# TravelVid Recorder Complete Documentation

This file provides comprehensive guidance to AI assistants when working with this codebase.

---

## PROJECT OVERVIEW

**TravelVid Recorder** is a video recording iOS app designed for travel safety and documentation. It can display cover interfaces (cover image, games, fake calls, calculator) while recording video with a configurable recording indicator.

**Target Use Case**: Personal safety/security - recording incidents with clear recording status.

---

## BUILD & RUN

### Prerequisites
- iOS 15.0+
- Xcode with SwiftUI support
- Physical device (camera features don't work in simulator)
- CocoaPods installed

### Setup
```bash
# Install dependencies
cd "TravelVid Recorder"
pod install

# IMPORTANT: Open the workspace, NOT the project
open "TravelVid Recorder.xcworkspace"

# In Xcode:
# 1. Select your development team in Signing & Capabilities
# 2. Build and run on physical device
```

### Required Capabilities (already configured)
- Background Modes: Audio (keeps app alive in background)
- Camera usage permission
- Microphone usage permission
- Photo Library usage permission
- Location When In Use permission

---

## ARCHITECTURE OVERVIEW

### Design Pattern
- **Singleton Managers**: All managers use `@MainActor` for thread safety
- **MVVM**: Views observe managers via `@StateObject`/`@ObservedObject`
- **Reactive**: `@Published` properties for automatic UI updates

### File Structure
```
TravelVid Recorder/
├── TravelVid_RecorderApp.swift    # App entry point, audio session setup
├── MainView.swift                  # Main hub - settings, gallery, controls
├── RecordingView.swift             # Full-screen recording with decoy UI
├── RecordingManager.swift          # Core recording logic
├── SafeRecordingHandler.swift      # Background execution, file safety
├── LocationManager.swift           # GPS tracking, reverse geocoding
├── SubscriptionManager.swift       # StoreKit v2 subscriptions
├── AdMobManager.swift              # Google AdMob ads
├── HardwareButtonBlocker.swift     # Volume button interception
├── PaywallView.swift               # Premium subscription purchase UI
├── FakeCallingView.swift           # Fake phone call interface
├── TetrisGame.swift                # Full Tetris game
├── FlappyBirdView.swift            # Flappy Bird with difficulty levels
├── CalculatorView.swift            # Functional calculator
├── BitcoinPriceView.swift          # Bitcoin price tracker
├── LoopingVideoPlayerView.swift    # Looping video player
└── Assets.xcassets/                # App icons, images
```

---

## CORE MANAGERS

### 1. RecordingManager.swift
**The heart of the app** - handles all video recording logic.

#### Key Published Properties
```swift
@Published var isRecording = false              // Current recording state
@Published var recordings: [Recording] = []     // Library of saved recordings
@Published var segmentLength: TimeInterval = 120 // Segment duration (seconds)
@Published var selectedResolution: Resolution = .p1080
@Published var audioOn = true                   // Include audio
@Published var enableStabilization = false      // Video stabilization
@Published var showFakePopups = true            // Show fake "storage full" alerts
@Published var recordingDisplayMode: RecordingDisplayMode = .coverImage
@Published var stopGesture: StopRecordingGesture = .fiveTaps
@Published var holdDuration: Int = 2            // For tap & hold gesture (1-10s)
@Published var cameraPosition: AVCaptureDevice.Position = .back
@Published var cameraType: CameraType = .ultraWide
@Published var selectedVideoURL: URL?           // For video playback mode
@Published var showRecordingIndicator: Bool = true
@Published var fakeCallContactName: String = "Customer Service"
```

#### Key Enums
```swift
enum RecordingDisplayMode: String, CaseIterable {
    case coverImage = "Cover Image"      // FREE - Static image
    case videoPlayback = "Video Playback" // PREMIUM - Looping video
    case fakeCall = "Fake Call"          // PREMIUM - Fake phone call UI
    case tetris = "Tetris"               // FREE - Playable game
    case flappyBird = "Flappy Bird"      // PREMIUM - Playable game
    case bitcoin = "Bitcoin Price"       // PREMIUM - Price tracker
    case calculator = "Calculator"       // PREMIUM - Working calculator

    var requiresPremium: Bool {
        switch self {
        case .coverImage, .tetris:
            return false
        default:
            return true
        }
    }
}

enum StopRecordingGesture: String, CaseIterable {
    case fourTaps = "4 Taps Anywhere"
    case fiveTaps = "5 Taps Anywhere"
    case swipeDown = "Swipe Down"
    case swipeLeft = "Swipe Left"
    case swipeRight = "Swipe Right"
    case topLeftCorner = "5 Taps Top-Left Corner"
    case topRightCorner = "5 Taps Top-Right Corner"
    case doubleTapHold = "Tap & Hold"
}

enum Resolution: String, CaseIterable {
    case p720 = "720p"   // AVCaptureSession.Preset.hd1280x720
    case p1080 = "1080p" // AVCaptureSession.Preset.hd1920x1080
    case p4K = "4K"      // AVCaptureSession.Preset.hd4K3840x2160
}

enum CameraType: String, CaseIterable {
    case wide = "Wide"           // builtInWideAngleCamera
    case ultraWide = "Ultra-Wide" // builtInUltraWideCamera
}
```

#### Key Methods
```swift
// Session management
func prepareSession() async -> Bool  // Initialize AVCaptureSession
func startRecording()                // Begin recording with all timers
func stopRecording()                 // End recording, cleanup

// Internal
private func rotateSegment()         // Split recording into segments
private func watchdogCheck()         // Verify recording is active
private func checkDiskSpaceAndWarn() // Monitor storage
private func handleThermalStateChange() // Respond to device temperature

// File management
func loadRecordings() async          // Scan Documents/Videos/
func deleteRecording(_ rec)          // Remove video and metadata
func exportRecording(_ rec)          // Save to Photos with GPS
func saveSelectedVideo(from: URL)    // Save video for playback mode
```

#### Reliability Features (recently added)
- **Watchdog Timer**: Every 10s verifies `movieOutput.isRecording` matches `isRecording`
- **Watchdog Log Throttle**: Recording stats log at most once per 60s to reduce debug overhead
- **Thermal Monitoring**: Forces segment save at "serious", stops at "critical"
- **Memory Pressure**: Forces segment save on low memory warning
- **Disk Space Monitor**: Warns at <500MB, saves at <250MB, stops at <100MB
- **Session Interruption Handling**: Detects camera/audio interruptions, auto-recovers
- **Foreground Recovery**: Verifies recording when app returns from background

### 2. SafeRecordingHandler.swift
**Keeps app alive in background** and handles file safety.

#### Key Features
```swift
// Silent audio keeps app running indefinitely in background
private var silentAudioPlayer: AVAudioPlayer?

func startBackgroundAudio()  // Start silent audio loop
func stopBackgroundAudio()   // Stop silent audio

func startRecordingSession(url: URL)  // Begin background task + audio
func endRecordingSession()            // End background task + audio

func checkDiskSpace() -> (available: Int64, isLow: Bool)
func verifyFileIntegrity(at url: URL) -> Bool
func cleanupCorruptedFiles(in directory: URL) async
```

#### How Background Execution Works
1. App enters background
2. Silent audio (0.5s WAV at 0% volume) loops infinitely
3. iOS sees app is "playing audio" and doesn't suspend it
4. Recording continues indefinitely
5. When recording stops, silent audio stops, app can suspend

### 3. LocationManager.swift
**GPS tracking with reverse geocoding.**

```swift
static let shared = LocationManager()

@Published var currentLocation: CLLocation?
@Published var authorizationStatus: CLAuthorizationStatus

var onLocationUpdate: ((CLLocation) -> Void)?  // Callback during recording

func requestPermission()
func startTracking()   // Begin location updates (10m filter)
func stopTracking()
func getAddress(for location: CLLocation) async -> String?
```

#### Location Data Model
```swift
struct LocationPoint: Codable {
    let latitude: Double
    let longitude: Double
    let timestamp: Date
}
```

### 4. SubscriptionManager.swift
**StoreKit v2 subscription management.**

```swift
static let shared = SubscriptionManager()

@Published private(set) var isPremium: Bool = false
@Published private(set) var products: [Product] = []

private let productID = "com.jimwas.travelvid.premium"

func loadProducts() async
func purchase() async
func restorePurchases() async
func updateSubscriptionStatus() async
func isEligibleForIntroOffer() async -> Bool

// DEBUG ONLY: Auto-unlocks premium in debug builds
private let developerOverrideEnabled: Bool  // Set to true for testing
func togglePremiumForTesting()              // Manual toggle in DEBUG
```

#### Subscription Details
- **Product ID**: `com.jimwas.travelvid.premium`
- **Price**: $3.99/month
- **Trial**: 2-week free introductory offer

### 5. AdMobManager.swift
**Google AdMob integration.**

```swift
static let shared = AdMobManager()

private let interstitialID = "ca-app-pub-3057383894764696/4200169611"
private let rewardedID = "ca-app-pub-3057383894764696/5439021675"

func initializeAdMob() // Lazy-safe wrapper
func loadRewardedAd()
func showRewardedAd(completion: @escaping (Bool) -> Void)
func showInterstitialAd(completion: @escaping () -> Void)
```

**Ad Flow**: Free users must watch rewarded ad to export videos. Premium users skip ads. AdMob SDK now initializes lazily on first ad request, not at app launch.

### 6. HardwareButtonBlocker.swift
**Prevents volume buttons from working during recording.**

Uses KVO on `AVAudioSession.outputVolume` to detect button presses, then resets volume via hidden `MPVolumeView` slider.

---

## UI VIEWS

### MainView.swift
**Main hub** with three sections:

1. **Hero Preview**: Shows current mode with edit controls
2. **Configuration**: Camera, resolution, segment length, gestures, audio, stabilization
3. **Library**: Grid of recorded videos with export/delete actions

**Library Interactions**:
- Tap recording → Opens video preview player
- Tap map thumbnail → Opens full map view with location
- Long press / Select mode → Multi-select for batch operations

**Supporting Views in MainView.swift**:
- `MapSnapshotView` - Thumbnail map preview for recordings with GPS
- `FullMapView` - Full-screen map with recording location and path
- `VideoPreviewView` - Video playback with AVKit player and metadata display
- `AdvancedSettingsSection` - Recording indicator toggle and advanced options

### RecordingView.swift
**Full-screen recording interface** that:
- Displays selected decoy mode (game, fake call, etc.)
- Detects stop gestures
- Shows fake "iPhone Storage Full" popups (repeating timer while enabled)
- Activates hardware button blocker

#### Gesture Detection Logic
```swift
// Tap counting (4 or 5 taps)
- Count taps within 2-second window
- Reset counter if >2s since last tap

// Swipes (down/left/right)
- Minimum 100px movement in primary direction
- Maximum 50px movement in perpendicular direction

// Corner taps (top-left or top-right)
- 100x100px invisible tap zone
- Requires 5 taps within zone

// Tap & Hold
- LongPressGesture with configurable duration (1-10s)
```

### Decoy Views

#### FakeCallingView.swift
Simulates iOS phone call interface with:
- "Calling..." status
- Customizable contact name
- Mute, Keypad, Audio, Add Call, FaceTime, Contacts buttons
- Red end call button

#### TetrisGame.swift
Full Tetris implementation:
- 20x10 board
- 7 piece types with colors
- Rotation with wall kick
- Line clearing with scoring
- Levels (speed increases every 1000 points)
- Pause/resume functionality

#### FlappyBirdView.swift
Flappy Bird with:
- 3 difficulty levels (Easy/Medium/Hard)
- High score persistence
- Pipe gap and speed vary by difficulty

#### CalculatorView.swift
Fully functional iOS-style calculator:
- Basic operations (+, -, ×, ÷)
- Percentage, sign change, clear
- Decimal support
- Proper operator precedence

#### BitcoinPriceView.swift
Bitcoin price tracker (simulated data):
- Current price display
- Price change (amount and percentage)
- Line chart with 50 data points
- Time period selector (1H, 24H, 1W, 1M, 1Y)
- Stats: 24h high/low, volume, market cap
- Updates every 2 seconds

#### LoopingVideoPlayerView.swift
Seamless video looping:
- Uses AVQueuePlayer + AVPlayerLooper
- Muted playback
- Aspect fill scaling

### Utility Views (in MainView.swift)

#### VideoPreviewView
Video playback for library recordings:
- Full AVKit `VideoPlayer` with standard controls
- Auto-plays on appear, pauses on dismiss
- Displays metadata: filename, duration, size, location, creation date
- Presented as sheet from library tap

#### FullMapView
Full-screen map for recording locations:
- MapKit `Map` with recording marker
- Shows location path as blue polyline (if tracked)
- Info panel with address, coordinates, point count
- Graceful handling when no GPS data (shows "No Location Data" message with Settings button)

#### MapSnapshotView
Thumbnail map preview:
- Uses `MKMapSnapshotter` for static image
- 44x44pt size in library rows
- Tappable to open FullMapView

---

## DATA MODELS

### Recording
```swift
struct Recording: Identifiable {
    let id = UUID()
    let name: String           // Filename
    let duration: TimeInterval // Length in seconds
    let size: Int64           // File size in bytes
    let url: URL              // Full file path
    let creation: Date?       // Creation timestamp
    let latitude: Double?     // Start GPS latitude
    let longitude: Double?    // Start GPS longitude
    let address: String?      // Reverse-geocoded address
    let locationPath: [LocationPoint]?  // GPS path during recording
}
```

### RecordingMetadata (JSON persistence)
```swift
struct RecordingMetadata: Codable {
    let latitude: Double?
    let longitude: Double?
    let address: String?
    let locationPath: [LocationPoint]?
}
```

---

## FILE STORAGE

```
Documents/
└── Videos/
    ├── 2024-01-15-14-30-22-ABC123.mov  // Recorded videos
    ├── 2024-01-15-14-32-22-DEF456.mov
    ├── metadata.json                    // GPS data for all videos
    └── SelectedVideos/
        └── selected-video-UUID.mov      // Video for playback mode
```

### Metadata JSON Format
```json
{
  "2024-01-15-14-30-22-ABC123.mov": {
    "latitude": 37.7749,
    "longitude": -122.4194,
    "address": "123 Main St, San Francisco, CA",
    "locationPath": [
      {"latitude": 37.7749, "longitude": -122.4194, "timestamp": "2024-01-15T14:30:22Z"},
      {"latitude": 37.7750, "longitude": -122.4195, "timestamp": "2024-01-15T14:30:32Z"}
    ]
  }
}
```

---

## NOTIFICATION SYSTEM

Cross-component communication via NotificationCenter:

```swift
// Request graceful stop (deprecated - now continues in background)
NotificationCenter.default.post(name: NSNotification.Name("SafeStopRecording"), object: nil)

// Force immediate stop (app termination)
NotificationCenter.default.post(name: NSNotification.Name("EmergencyStopRecording"), object: nil)
```

---

## RECORDING FLOW

### Start Recording
1. User configures settings in MainView
2. User taps "Start Recording"
3. RecordingView appears and calls `prepareSession()`
4. AVCaptureSession starts with selected resolution/camera
5. `startRecording()` called:
   - Creates segment file URL
   - Starts SafeRecordingHandler (background audio + task)
   - Starts LocationManager tracking
   - Starts movieOutput recording
   - Starts segment timer
   - Starts watchdog timer
   - Starts disk space monitor

### During Recording
- Video written to current segment file
- Location updates collected
- Watchdog verifies recording every 10s (stats logging throttled to 60s)
- Disk space checked every 30s
- Thermal state monitored
- Segment timer fires every N seconds (default 120s)

### Segment Rotation
1. Timer fires or forced by thermal/memory pressure
2. `rotateSegment()` called
3. Current movieOutput stops
4. Delegate receives completion, saves file with metadata
5. New segment file created
6. Recording continues to new file

### Stop Recording
1. User performs stop gesture
2. `stopRecording()` called:
   - Sets `isRecording = false`
   - Invalidates all timers
   - Stops movieOutput
   - Stops LocationManager
   - Stops SafeRecordingHandler (background audio)
3. RecordingView dismissed
4. MainView shows updated library

---

## PREMIUM FEATURES

| Feature | Free | Premium |
|---------|:----:|:-------:|
| Cover Image Mode | ✓ | ✓ |
| Video Playback Mode | | ✓ |
| Fake Call Mode | | ✓ |
| Tetris Mode | ✓ | ✓ |
| Flappy Bird Mode | | ✓ |
| Bitcoin Mode | | ✓ |
| Calculator Mode | | ✓ |
| Ad-Free Exports | | ✓ |
| GPS Tracking | ✓ | ✓ |
| Video Segmentation | ✓ | ✓ |
| All Resolutions | ✓ | ✓ |

---

## TESTING

### Unlock Premium in Debug
In `SubscriptionManager.swift`, premium is auto-unlocked in DEBUG builds:
```swift
private let developerOverrideEnabled: Bool = {
    #if DEBUG
    return true  // Set to false to test paywall
    #else
    return false
    #endif
}()
```

### Test Recording Reliability
Watch Xcode console for these logs:
```
📊 Watchdog: Recording active - 45s, 12340KB   // every ~60s
🌡️ Thermal state: Fair - device warming up
✅ Saved segment: 2024-01-15-14-30-22-ABC123.mov (120s, 245MB)
⚠️ Disk space getting low: 450MB available
🚨 Watchdog detected recording stopped unexpectedly!
```

### Test Background Recording
1. Start recording
2. Press Home button
3. Wait 10+ minutes
4. Return to app
5. Stop recording
6. Verify all segments saved

---

## COMMON MODIFICATIONS

### Add New Recording Mode
1. Add case to `RecordingDisplayMode` enum in RecordingManager.swift
2. Set `requiresPremium` if needed
3. Create new SwiftUI view for the mode
4. Add case to switch in RecordingView.swift
5. Add preview in MainView.swift hero section

### Change Segment Length Limits
In MainView.swift, find the Slider:
```swift
Slider(value: $segmentMinutes, in: 1...10, step: 1)
```

### Add New Stop Gesture
1. Add case to `StopRecordingGesture` enum
2. Add description in `description(holdDuration:)` method
3. Implement detection in RecordingView.swift `applyStopGestures()`

### Modify Ad Behavior
In AdMobManager.swift:
- Change ad unit IDs for production
- Keep lazy initialization (`ensureSDKInitialized`) when adding new ad entry points

---

## DEPENDENCIES

### CocoaPods (Podfile)
```ruby
pod 'Google-Mobile-Ads-SDK'
```

### Frameworks
- AVFoundation - Video recording
- CoreLocation - GPS tracking
- StoreKit - In-app purchases
- PhotosUI - Photo/video picker
- MapKit - Map display
- AVKit - Video playback

---

## IMPORTANT NOTES

1. **Always test on physical device** - Camera doesn't work in simulator
2. **Open .xcworkspace** not .xcodeproj (CocoaPods requirement)
3. **Background audio mode is essential** - Without it, recording stops when backgrounded
4. **Segment length affects reliability** - Shorter segments = less data loss on crash
5. **Thermal monitoring is critical** - iOS will kill camera access if device overheats
6. **Location permission is "When In Use"** - GPS only tracks while app is active/recording

---

## DEBUGGING TIPS

### Recording Stops Unexpectedly
1. Check Xcode console for interruption logs
2. Look for thermal state changes
3. Verify disk space
4. Check if another app used camera/mic

### Videos Not Saving
1. Check disk space (needs >100MB)
2. Verify Documents/Videos/ directory exists
3. Look for file integrity errors in console
4. Check if segment was too short (<0.5s)

### Background Recording Fails
1. Verify UIBackgroundModes includes "audio" in Info.plist
2. Check silent audio player initialized
3. Look for audio session interruption logs
4. Verify app wasn't force-quit by user

### Premium Not Working
1. Check `developerOverrideEnabled` in SubscriptionManager
2. Verify StoreKit configuration file exists
3. Check console for product loading errors
4. Try "Restore Purchases"
