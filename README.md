# ARKit Eye Tracking System

This is a prototype/MVP for patients with Motor Neuron Diseases. 

Patient can use eye to track, speak, type, express feelings, control computer by AI agents to navigate browser

A dual-platform eye tracking application that uses iPhone's TrueDepth camera for gaze detection.

### Architecture

- **iOS Companion App** (iPhone): Captures ARKit face tracking data.

### Requirements

#### iOS App
- iPhone X or later (TrueDepth camera required)
- **iPhone Pro**
- iOS 13.0+ (iOS 14.0+ recommended for Neural Engine, iOS 18+ fully supported)
- Same WiFi network as MacBook

### Setup Instructions

#### Build iOS App
1. Open `ARkit-iOS` project in Xcode
2. Set deployment target to your own iPhone or any Simulation devices available
3. Connect iPhone, build & run
4. Grant camera permission when prompted

### Usage

1. **Start iOS app** - Grant camera permission
2. **Connect** - Use auto-connect or manual IP
3. **Look at screen** - Cursor follows your gaze
4. **Dwell to select** - Look at buttons for 1.5 seconds to select

### Features

- ✅ Real-time eye tracking
- ✅ Network streaming (Bonjour or manual IP)
- ✅ Visual cursor following gaze
- ✅ Dwell-to-select interaction
- ✅ Smooth cursor movement
- ✅ Computer Use Agent by Gemini

### Troubleshooting

- **Can't find Mac**: Ensure both devices are on same WiFi network
- **Connection fails**: Check Mac firewall settings
- **No cursor**: Verify camera permission on iPhone
