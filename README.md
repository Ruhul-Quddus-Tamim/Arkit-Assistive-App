# ARKit Eye Tracking System

A dual-platform eye tracking application that uses iPhone's TrueDepth camera for gaze detection and displays interactive UI on MacBook.

## Architecture

- **iOS Companion App** (iPhone): Captures ARKit face tracking data and streams it to Mac
- **macOS Main App** (MacBook): Receives gaze data and displays eye-controlled UI

## Requirements

### iOS App
- iPhone X or later (TrueDepth camera required)
- **iPhone 17 Pro is perfect! ✅**
- iOS 13.0+ (iOS 14.0+ recommended for Neural Engine, iOS 18+ fully supported)
- Same WiFi network as MacBook

### macOS App
- macOS 11.0+ (macOS 13.0+ recommended)
- Same WiFi network as iPhone

## Setup Instructions

### 1. Build iOS App
1. Open `ARkit-iOS` project in Xcode
2. Set deployment target to iOS 13.0+
3. Connect iPhone and build/run
4. Grant camera permission when prompted

### 2. Build macOS App
1. Open `ARkit-macOS` project in Xcode
2. Set deployment target to macOS 11.0+
3. Build and run on MacBook

### 3. Connect Devices

**Option A: Automatic Discovery (Bonjour)**
1. Start macOS app first (server)
2. Start iOS app
3. Tap "Auto Connect" button
4. App will automatically discover and connect

**Option B: Manual IP Connection**
1. Start macOS app first
2. Find Mac's IP address: System Settings → Network → Wi-Fi → Details
3. Start iOS app
4. Enter Mac's IP address
5. Tap "Connect (Manual)"

## Usage

1. **Start macOS app** - Server will start and wait for connection
2. **Start iOS app** - Grant camera permission
3. **Connect** - Use auto-connect or manual IP
4. **Look at screen** - Cursor follows your gaze
5. **Dwell to select** - Look at buttons for 1.5 seconds to select

## Project Structure

```
ARkit/
├── Shared/
│   └── TrackingData.swift          # Shared data structures
├── ARkit-iOS/                      # iOS Companion App
│   ├── CameraViewController.swift  # Main AR view controller
│   ├── EyeTracking/
│   │   ├── EyeTracker.swift        # Core eye tracking
│   │   ├── GazeCalculator.swift   # Gaze calculations
│   │   └── DataSerializer.swift   # Data serialization
│   └── Network/
│       └── TrackingDataClient.swift # Network client
└── ARkit-macOS/                    # macOS Main App
    ├── ViewController.swift        # Main view controller
    ├── EyeTracking/
    │   ├── CursorView.swift        # Visual cursor
    │   └── DwellDetector.swift    # Dwell detection
    ├── UI/
    │   ├── NavigationView.swift    # Navigation UI
    │   └── ButtonView.swift       # Dwell buttons
    ├── Network/
    │   └── TrackingDataServer.swift # Network server
    └── Utilities/
        └── ScreenMapper.swift      # Screen coordinate mapping
```

## Features

- ✅ Real-time eye tracking via ARKit
- ✅ Network streaming (Bonjour or manual IP)
- ✅ Visual cursor following gaze
- ✅ Dwell-to-select interaction
- ✅ Smooth cursor movement
- ✅ Connection status indicators

## Troubleshooting

- **Can't find Mac**: Ensure both devices are on same WiFi network
- **Connection fails**: Check Mac firewall settings
- **No cursor**: Verify camera permission on iPhone

## Future Enhancements

- Speech-to-text integration
- Web browser component
- Audio input handling
- More sophisticated UI navigation
