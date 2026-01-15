import Foundation
import CoreGraphics

/// Stores calibration parameters for eye tracking
/// Maps raw gaze coordinates to screen positions using linear transformation:
/// screenX = rawX * scaleX + offsetX
/// screenY = rawY * scaleY + offsetY
struct CalibrationData: Codable {
    var scaleX: CGFloat
    var scaleY: CGFloat
    var offsetX: CGFloat
    var offsetY: CGFloat
    
    /// Whether calibration has been completed
    var isCalibrated: Bool
    
    /// Timestamp of last calibration
    var calibrationDate: Date?
    
    // MARK: - UserDefaults Keys
    private static let userDefaultsKey = "EyeTrackingCalibrationData"
    
    // MARK: - Initialization
    
    /// Create default (identity) calibration - no transformation
    init() {
        self.scaleX = 1.0
        self.scaleY = 1.0
        self.offsetX = 0.0
        self.offsetY = 0.0
        self.isCalibrated = false
        self.calibrationDate = nil
    }
    
    /// Create calibration with specific parameters
    init(scaleX: CGFloat, scaleY: CGFloat, offsetX: CGFloat, offsetY: CGFloat) {
        self.scaleX = scaleX
        self.scaleY = scaleY
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.isCalibrated = true
        self.calibrationDate = Date()
    }
    
    // MARK: - Apply Calibration
    
    /// Apply calibration transform to raw gaze point
    /// - Parameter rawPoint: Raw gaze coordinates from hit testing
    /// - Returns: Calibrated screen position
    func apply(rawPoint: CGPoint) -> CGPoint {
        let calibratedX = rawPoint.x * scaleX + offsetX
        let calibratedY = rawPoint.y * scaleY + offsetY
        return CGPoint(x: calibratedX, y: calibratedY)
    }
    
    // MARK: - Persistence
    
    /// Save calibration to UserDefaults
    func save() {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(self)
            UserDefaults.standard.set(data, forKey: CalibrationData.userDefaultsKey)
            print("CalibrationData: Saved calibration - scale:(\(scaleX), \(scaleY)) offset:(\(offsetX), \(offsetY))")
        } catch {
            print("CalibrationData: Failed to save - \(error)")
        }
    }
    
    /// Load calibration from UserDefaults
    /// - Returns: Saved calibration or default if none exists
    static func load() -> CalibrationData {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else {
            print("CalibrationData: No saved calibration, using defaults")
            return CalibrationData()
        }
        
        do {
            let decoder = JSONDecoder()
            let calibration = try decoder.decode(CalibrationData.self, from: data)
            print("CalibrationData: Loaded calibration - scale:(\(calibration.scaleX), \(calibration.scaleY)) offset:(\(calibration.offsetX), \(calibration.offsetY))")
            return calibration
        } catch {
            print("CalibrationData: Failed to load - \(error)")
            return CalibrationData()
        }
    }
    
    /// Clear saved calibration
    static func clear() {
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
        print("CalibrationData: Cleared saved calibration")
    }
    
    // MARK: - Calculate Calibration from Points
    
    /// Calculate calibration parameters from collected sample points
    /// Uses simple linear regression for X and Y axes independently
    /// - Parameters:
    ///   - rawPoints: Array of raw gaze positions collected during calibration
    ///   - screenPoints: Array of known screen positions (where dots were shown)
    /// - Returns: Calibrated CalibrationData, or nil if calculation fails
    static func calculate(rawPoints: [CGPoint], screenPoints: [CGPoint]) -> CalibrationData? {
        guard rawPoints.count == screenPoints.count, rawPoints.count >= 2 else {
            print("CalibrationData: Need at least 2 matching points for calibration")
            return nil
        }
        
        let n = CGFloat(rawPoints.count)
        
        // Calculate linear regression for X axis
        // screenX = rawX * scaleX + offsetX
        var sumRawX: CGFloat = 0
        var sumScreenX: CGFloat = 0
        var sumRawXScreenX: CGFloat = 0
        var sumRawX2: CGFloat = 0
        
        // Calculate linear regression for Y axis
        var sumRawY: CGFloat = 0
        var sumScreenY: CGFloat = 0
        var sumRawYScreenY: CGFloat = 0
        var sumRawY2: CGFloat = 0
        
        for i in 0..<rawPoints.count {
            let rawX = rawPoints[i].x
            let rawY = rawPoints[i].y
            let screenX = screenPoints[i].x
            let screenY = screenPoints[i].y
            
            sumRawX += rawX
            sumScreenX += screenX
            sumRawXScreenX += rawX * screenX
            sumRawX2 += rawX * rawX
            
            sumRawY += rawY
            sumScreenY += screenY
            sumRawYScreenY += rawY * screenY
            sumRawY2 += rawY * rawY
        }
        
        // Calculate scale and offset for X axis
        let denominatorX = n * sumRawX2 - sumRawX * sumRawX
        var scaleX: CGFloat = 1.0
        var offsetX: CGFloat = 0.0
        
        if abs(denominatorX) > 0.0001 {
            scaleX = (n * sumRawXScreenX - sumRawX * sumScreenX) / denominatorX
            offsetX = (sumScreenX - scaleX * sumRawX) / n
        } else {
            // Fallback: use average offset if raw X values are all the same
            offsetX = (sumScreenX - sumRawX) / n
        }
        
        // Calculate scale and offset for Y axis
        let denominatorY = n * sumRawY2 - sumRawY * sumRawY
        var scaleY: CGFloat = 1.0
        var offsetY: CGFloat = 0.0
        
        if abs(denominatorY) > 0.0001 {
            scaleY = (n * sumRawYScreenY - sumRawY * sumScreenY) / denominatorY
            offsetY = (sumScreenY - scaleY * sumRawY) / n
        } else {
            // Fallback: use average offset if raw Y values are all the same
            offsetY = (sumScreenY - sumRawY) / n
        }
        
        print("CalibrationData: Calculated - scaleX:\(scaleX) scaleY:\(scaleY) offsetX:\(offsetX) offsetY:\(offsetY)")
        
        return CalibrationData(scaleX: scaleX, scaleY: scaleY, offsetX: offsetX, offsetY: offsetY)
    }
}
