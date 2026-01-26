import Foundation
import AppKit
import simd

/// Maps 3D gaze vector to 2D screen coordinates
class ScreenMapper {
    
    private var smoothingFactor: Float = 0.7 // 0.0 = no smoothing, 1.0 = full smoothing
    private var lastScreenPoint: CGPoint?
    
    /// Map gaze vector to screen coordinates
    /// - Parameters:
    ///   - gazeVector: Normalized 3D gaze direction vector
    ///   - faceTransform: Face position/orientation transform
    /// - Returns: Screen coordinates (0,0 is top-left)
    func mapGazeToScreen(gazeVector: SIMD3<Float>, faceTransform: simd_float4x4) -> CGPoint {
        // Get screen bounds
        guard let screen = NSScreen.main else {
            return CGPoint.zero
        }
        
        let screenSize = screen.frame.size
        
        // Extract horizontal and vertical components from gaze vector
        // gazeVector.x = horizontal (-1.0 to 1.0, left to right)
        // gazeVector.y = vertical (-1.0 to 1.0, down to up)
        
        // Map from [-1, 1] to [0, screenSize]
        let normalizedX = (gazeVector.x + 1.0) / 2.0 // 0.0 to 1.0
        let normalizedY = (gazeVector.y + 1.0) / 2.0 // 0.0 to 1.0
        
        // Convert to screen coordinates
        // Note: macOS coordinate system has origin at bottom-left
        // We'll use top-left for consistency with UI
        let screenX = CGFloat(normalizedX) * screenSize.width
        let screenY = CGFloat(1.0 - normalizedY) * screenSize.height // Flip Y axis
        
        let screenPoint = CGPoint(x: screenX, y: screenY)
        
        // Apply smoothing to reduce jitter
        if let lastPoint = lastScreenPoint {
            let smoothedX = CGFloat(smoothingFactor) * lastPoint.x + CGFloat(1.0 - smoothingFactor) * screenPoint.x
            let smoothedY = CGFloat(smoothingFactor) * lastPoint.y + CGFloat(1.0 - smoothingFactor) * screenPoint.y
            let smoothedPoint = CGPoint(x: smoothedX, y: smoothedY)
            lastScreenPoint = smoothedPoint
            return smoothedPoint
        } else {
            lastScreenPoint = screenPoint
            return screenPoint
        }
    }
    
    /// Reset smoothing (call when gaze is lost)
    func reset() {
        lastScreenPoint = nil
    }
    
    /// Set smoothing factor (0.0 = no smoothing, 1.0 = maximum smoothing)
    func setSmoothingFactor(_ factor: Float) {
        smoothingFactor = max(0.0, min(1.0, factor))
    }
}
