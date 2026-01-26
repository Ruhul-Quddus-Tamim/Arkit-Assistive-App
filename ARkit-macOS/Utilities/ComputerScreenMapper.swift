import Foundation
import AppKit
import CoreGraphics

/// Maps iPhone screen coordinates to macOS computer screen coordinates
/// iPhone coordinates are centered at (0,0), macOS uses top-left origin (0,0)
class ComputerScreenMapper {
    
    private var smoothingFactor: Float = 0.7 // 0.0 = no smoothing, 1.0 = full smoothing
    private var lastScreenPoint: CGPoint?
    private var hasLoggedScreenInfo = false
    
    /// Map iPhone screen coordinates to macOS screen coordinates
    /// - Parameters:
    ///   - iphoneScreenPosition: Screen position from iPhone (centered at 0,0)
    ///   - phoneScreenSize: iPhone screen size in points
    /// - Returns: macOS screen coordinates (top-left origin, Quartz coordinates)
    func mapiPhoneToComputerScreen(iphoneScreenPosition: CGPoint, phoneScreenSize: CGSize) -> CGPoint {
        // Get macOS main screen bounds
        // Use visibleFrame to account for menu bar and dock, and convert to Quartz coordinates
        guard let screen = NSScreen.main else {
            return CGPoint.zero
        }
        
        // NSScreen.frame uses Cocoa coordinates (bottom-left origin)
        // NSScreen.visibleFrame also uses Cocoa coordinates
        // CGWarpMouseCursorPosition uses Quartz coordinates (top-left origin)
        // We need to convert from Cocoa to Quartz
        
        let cocoaFrame = screen.visibleFrame // Visible area excluding menu bar/dock
        let mainScreenHeight = screen.frame.height // Full screen height for coordinate conversion
        
        // Log screen info once for debugging
        if !hasLoggedScreenInfo {
            print("ComputerScreenMapper: Mac screen info -")
            print("  Full frame (Cocoa): \(screen.frame)")
            print("  Visible frame (Cocoa): \(cocoaFrame)")
            print("  Main screen height: \(mainScreenHeight)")
            hasLoggedScreenInfo = true
        }
        
        // Convert Cocoa frame to Quartz coordinates
        // Cocoa: Y=0 at bottom, Quartz: Y=0 at top
        let quartzX = cocoaFrame.origin.x
        let quartzY = mainScreenHeight - cocoaFrame.origin.y - cocoaFrame.height
        let quartzWidth = cocoaFrame.width
        let quartzHeight = cocoaFrame.height
        
        // Convert iPhone centered coordinates to absolute (top-left origin)
        // iPhone: center is (0,0), X: negative (left) to positive (right), Y: negative (down) to positive (up)
        // iPhone absolute: top-left is (0,0), Y increases downward
        
        // Step 1: Convert iPhone centered coordinates to absolute (top-left origin)
        // iPhone centered: X negative (left) to positive (right), Y negative (down) to positive (up)
        // iPhone absolute (UIKit): top-left is (0,0), X increases right, Y increases down
        
        let iphoneAbsoluteX = iphoneScreenPosition.x + phoneScreenSize.width / 2
        
        // For Y: iPhone centered Y positive = up, but UIKit Y increases downward
        // The iPhone code uses: absoluteY = centerY + screenPosition.y
        // But based on user feedback, Y-axis is inverted, so we need to flip it:
        //   - If centeredY is positive (up): we want smaller absoluteY (top)
        //   - If centeredY is negative (down): we want larger absoluteY (bottom)
        // So: absoluteY = height/2 - centeredY (inverted from iPhone's conversion)
        let iphoneAbsoluteY = phoneScreenSize.height / 2 - iphoneScreenPosition.y
        
        // Step 2: Normalize to 0-1 range (relative to iPhone screen)
        // normalizedX: 0 = left edge, 1 = right edge
        // normalizedY: 0 = top edge, 1 = bottom edge
        let normalizedX = iphoneAbsoluteX / phoneScreenSize.width
        let normalizedY = iphoneAbsoluteY / phoneScreenSize.height
        
        // Step 3: Map to macOS visible screen area (Quartz coordinates, top-left origin)
        // IMPORTANT: Invert Y-axis because user reports looking down makes cursor go up
        // Quartz: Y=0 at top, Y increases downward
        // So we flip normalizedY: 1 - normalizedY maps top to top correctly
        let computerX = quartzX + normalizedX * quartzWidth
        let computerY = quartzY + (1.0 - normalizedY) * quartzHeight
        
        // Debug logging
        if abs(iphoneScreenPosition.y) > 50 { // Log when Y is significant
            print("ComputerScreenMapper: iPhone centered(\(iphoneScreenPosition.x), \(iphoneScreenPosition.y)) -> absolute(\(iphoneAbsoluteX), \(iphoneAbsoluteY)) -> normalized(\(normalizedX), \(normalizedY)) -> Mac(\(computerX), \(computerY))")
        }
        
        // Clamp to visible screen bounds
        let clampedX = max(quartzX, min(quartzX + quartzWidth, computerX))
        let clampedY = max(quartzY, min(quartzY + quartzHeight, computerY))
        
        let screenPoint = CGPoint(x: clampedX, y: clampedY)
        
        // Debug logging (can be removed later)
        // print("ComputerScreenMapper: iPhone(\(iphoneScreenPosition.x), \(iphoneScreenPosition.y)) -> Mac(\(clampedX), \(clampedY))")
        
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
