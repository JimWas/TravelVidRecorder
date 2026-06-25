# TravelVid Recorder

> Discreet, reliable video recording for travelers who need peace of mind.

TravelVid Recorder captures video in the background while displaying a convincing cover screen — a fake phone call, a working game, a world clock, a calculator, and more. Built for personal safety and travel documentation, it records continuously without anyone knowing.

---

## Features

### Decoy Modes
Keep recording while your screen shows something completely unrelated.

| Mode | Free | Premium |
|------|:----:|:-------:|
| Cover Image | ✓ | ✓ |
| Tetris | ✓ | ✓ |
| Video Playback | | ✓ |
| Fake Phone Call | | ✓ |
| Flappy Bird | | ✓ |
| Bitcoin Price Tracker | | ✓ |
| Calculator | | ✓ |
| LED Banner | | ✓ |
| Currency Converter | | ✓ |
| World Clock | | ✓ |

### Recording
- **Resolutions**: 720p, 1080p, 4K
- **Cameras**: Front, Back (Wide + Ultra-Wide)
- **Auto-segmentation**: splits recordings into configurable chunks (1–10 min) so no data is lost on interruption
- **Stabilization**: optional video stabilization
- **Audio toggle**: record with or without audio
- **Watchdog**: background timer verifies recording is active every 10 seconds and auto-recovers if it stalls

### Stop Gestures
Discreetly stop recording without it being obvious.
- 4 or 5 taps anywhere on screen
- Swipe down, left, or right
- 5 taps in top-left or top-right corner
- Tap and hold (1–10 seconds, configurable)

### Storage & Safety
- Live **storage indicator** on the main screen showing free vs. used space, color-coded green → orange → red
- **Disk space checks** before saving or exporting — alerts you if there isn't enough room
- **Quick-delete after export** — after saving to Photos, offers to remove the in-app copy to free space
- **Honest export results** — clearly tells you if some or all videos failed to save so nothing is lost silently
- Auto-stops recording if disk space drops below 100 MB

### GPS & Location
- Optional GPS tracking during recording
- Reverse-geocoded address saved with each video
- GPS path recorded and viewable on a full-screen map
- Location data embedded in exported videos

### Library
- Thumbnail grid of all recordings
- Tap to preview with full playback controls
- Tap map thumbnail to open full GPS path view
- Multi-select for batch export or delete
- Export progress bar with live X-of-Y counter

### Premium
- Unlock all decoy modes
- Ad-free video exports
- **$3.99/month** with a **2-week free trial**
- Promo code redemption built-in

---

## Requirements

- iOS 15.0+
- Physical device required (camera does not work in Simulator)
- Permissions: Camera, Microphone, Photos Library
- Location permission optional (for GPS tagging)

---

## Build From Source

### Prerequisites
- Xcode with SwiftUI support
- CocoaPods installed (`brew install cocoapods`)

### Setup

```bash
git clone https://github.com/JimWas/TravelVidRecorder.git
cd TravelVidRecorder/TravelVid\ Recorder
pod install
open "TravelVid Recorder.xcworkspace"
```

Then in Xcode:
1. Select your development team under **Signing & Capabilities**
2. Connect a physical iOS device
3. Build and run

> **Important:** Always open the `.xcworkspace` file, not `.xcodeproj`.

### Dependencies

| Package | Purpose |
|---------|---------|
| Google-Mobile-Ads-SDK | AdMob interstitial & rewarded ads |

### Frameworks Used

- `AVFoundation` — video recording
- `CoreLocation` — GPS tracking
- `StoreKit` — in-app subscriptions
- `PhotosUI` — photo/video picker & export
- `MapKit` — GPS map display
- `AVKit` — video playback

---

## Architecture

```
TravelVid Recorder/
├── TravelVid_RecorderApp.swift     # App entry point
├── MainView.swift                   # Main screen — settings, library, controls
├── RecordingView.swift              # Full-screen recording + decoy UI
├── RecordingManager.swift           # Core recording logic (AVFoundation)
├── SafeRecordingHandler.swift       # File safety, background tasks, disk checks
├── LocationManager.swift            # GPS tracking + reverse geocoding
├── SubscriptionManager.swift        # StoreKit v2 subscriptions + promo codes
├── AdMobManager.swift               # Google AdMob ads
├── HardwareButtonBlocker.swift      # Volume button interception during recording
├── PaywallView.swift                # Premium subscription UI
├── FakeCallingView.swift            # Fake phone call decoy
├── TetrisGame.swift                 # Playable Tetris
├── FlappyBirdView.swift             # Playable Flappy Bird
├── CalculatorView.swift             # Functional calculator
├── BitcoinPriceView.swift           # Bitcoin price tracker
├── WorldClockView.swift             # Live world clock (44 cities)
├── LoopingVideoPlayerView.swift     # Seamless looping video player
└── Assets.xcassets/                 # App icons, images
```

**Design pattern**: `@MainActor` singleton managers observed by SwiftUI views via `@StateObject` / `@ObservedObject`. Fully reactive with `@Published` properties.

---

## Reliability

TravelVid Recorder is built to keep recording even under adverse conditions:

- **Watchdog timer** — verifies recording is active every 10 seconds, restarts if stalled
- **Thermal monitoring** — forces segment save at "serious" heat, stops at "critical"
- **Memory pressure** — forces segment save on low memory warning
- **Disk space monitor** — warns at <500 MB, forces segment save at <250 MB, stops at <100 MB
- **Session interruption handling** — detects camera/audio interruptions, auto-recovers
- **Foreground recovery** — verifies recording state when app returns from background
- **Short segments** — configurable segment length minimizes data loss on crash

---

## Legal & Ethical Use

TravelVid Recorder is intended for lawful personal safety and documentation use. You are solely responsible for complying with all applicable laws in your jurisdiction, including those governing recording consent. Always obtain consent where required by law.

---

## Support

Open a [GitHub Issue](https://github.com/JimWas/TravelVidRecorder/issues) for bug reports or feature requests.
