import UIKit
import Darwin

/// Physical display size in **meters** for gaze hit-testing (`GazeCalculator` maps SceneKit
/// local coords to points using `phoneScreenSize` × `phoneScreenPointSize`).
///
/// Previously the app used one fixed pair for every iPhone, which skewed gaze on other sizes.
/// This type scales the original reference by **portrait point size** so each device gets a
/// consistent meters-per-point mapping. Optionally override per `hw.machine` when specs differ
/// from that linear model.
enum PhoneDisplayPhysicalSize {

    /// Portrait: physical width (short side) × height (long side) in meters.
    static func metersPortraitForGaze() -> CGSize {
        let id = machineIdentifier()
        if let size = knownSizes[id] {
            return size
        }
        for (prefix, size) in prefixSizes where id.hasPrefix(prefix) {
            return size
        }
        return scaledFallback()
    }

    private static func machineIdentifier() -> String {
        var sys = utsname()
        uname(&sys)
        return withUnsafePointer(to: &sys.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 256) {
                String(cString: $0)
            }
        }
    }

    /// Original hardcoded pair — matched ~71.8 mm × 157 mm (iPhone 17 Pro–class display).
    private static let referencePhysicalMeters = CGSize(width: 0.0718, height: 0.157)

    /// Logical portrait points for the device class that matched `referencePhysicalMeters`.
    /// Tune here if you re-measure physical glass on a specific reference phone.
    private static let referencePortraitPoints = CGSize(width: 402, height: 874)

    /// Scales reference physical size by current portrait `UIScreen.main.bounds` vs reference.
    private static func scaledFallback() -> CGSize {
        let bounds = UIScreen.main.bounds
        guard bounds.width > 0.5, bounds.height > 0.5 else {
            return referencePhysicalMeters
        }
        let wPt = min(bounds.width, bounds.height)
        let hPt = max(bounds.width, bounds.height)
        let mW = referencePhysicalMeters.width * (wPt / referencePortraitPoints.width)
        let mH = referencePhysicalMeters.height * (hPt / referencePortraitPoints.height)
        return CGSize(width: mW, height: mH)
    }

    // MARK: - Optional per-model overrides (meters, portrait width × height)

    /// When linear scaling is off for a model, add an exact `hw.machine` entry.
    /// See: `uname -m` / Xcode “Model Identifier” in device logs.
    private static let knownSizes: [String: CGSize] = [
        // iPhone SE (3rd gen) — smaller display; linear scaling from 402×874 is often close but can drift.
        "iPhone14,6": CGSize(width: 0.0585, height: 0.1041),
        // iPhone 13 mini
        "iPhone14,4": CGSize(width: 0.0640, height: 0.1310),
        // Add more as needed when testing on hardware.
    ]

    /// Prefix fallback (e.g. family with same display size).
    private static let prefixSizes: [(String, CGSize)] = []
}
