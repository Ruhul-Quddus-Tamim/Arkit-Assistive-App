import Foundation
import CoreGraphics
import AppKit
import QuartzCore

/// Controls macOS system cursor using CGWarpMouseCursorPosition
/// Handles the 250ms delay limitation and provides smooth cursor movement
class CursorController {
    
    private var lastUpdateTime: CFTimeInterval = 0
    private var minUpdateInterval: CFTimeInterval = 0.033 // ~30 Hz (33ms between updates)
    private var lastPosition: CGPoint?
    
    /// Move cursor to specified screen position
    /// - Parameter position: Target position in Quartz coordinates (top-left origin)
    /// - Returns: true if cursor was moved, false if throttled
    @discardableResult
    func moveCursor(to position: CGPoint) -> Bool {
        let currentTime = CACurrentMediaTime()
        
        // Throttle updates to prevent overwhelming the system
        if currentTime - lastUpdateTime < minUpdateInterval {
            return false
        }
        
        // Check if position has changed significantly (avoid micro-movements)
        if let lastPos = lastPosition {
            let deltaX = abs(position.x - lastPos.x)
            let deltaY = abs(position.y - lastPos.y)
            // Skip if movement is less than 1 pixel
            if deltaX < 1.0 && deltaY < 1.0 {
                return false
            }
        }
        
        // Get screen bounds to clamp position
        guard let screen = NSScreen.main else {
            return false
        }
        let screenBounds = screen.frame
        
        // Clamp position to screen bounds
        let clampedX = max(screenBounds.minX, min(screenBounds.maxX - 1, position.x))
        let clampedY = max(screenBounds.minY, min(screenBounds.maxY - 1, position.y))
        let clampedPosition = CGPoint(x: clampedX, y: clampedY)
        
        // Mitigate 250ms delay by setting suppression interval to 0
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            print("CursorController: Failed to create event source")
            return false
        }
        let originalInterval = source.localEventsSuppressionInterval
        source.localEventsSuppressionInterval = 0.0
        
        // Move cursor
        let result = CGWarpMouseCursorPosition(clampedPosition)
        
        // Restore default suppression interval
        source.localEventsSuppressionInterval = originalInterval
        
        if result == .success {
            lastUpdateTime = currentTime
            lastPosition = clampedPosition
            return true
        } else {
            print("CursorController: Failed to move cursor - CGError: \(result)")
            return false
        }
    }
    
    /// Reset cursor controller state
    func reset() {
        lastUpdateTime = 0
        lastPosition = nil
    }
    
    /// Set minimum update interval (in seconds)
    /// - Parameter interval: Minimum time between cursor updates (default: 0.033 = ~30 Hz)
    func setMinUpdateInterval(_ interval: CFTimeInterval) {
        minUpdateInterval = max(0.016, min(0.1, interval)) // Clamp between 16ms and 100ms
    }
}
