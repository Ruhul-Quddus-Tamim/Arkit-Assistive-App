import Foundation
import ARKit
import simd
import SceneKit

/// Calculates gaze direction using ARKit's proper eye tracking APIs
class GazeCalculator {
    
    // MARK: - Accurate Eye Tracking using lookAtPoint and Eye Transforms
    
    /// Calculate gaze direction from eye transforms (more accurate than blend shapes)
    /// Uses leftEyeTransform and rightEyeTransform to get actual eye orientation
    /// - Parameter faceAnchor: The ARFaceAnchor from ARKit
    /// - Returns: Gaze direction vector where eyes are looking
    static func calculateGazeFromEyeTransforms(faceAnchor: ARFaceAnchor) -> SIMD3<Float> {
        // Get lookAtPoint - Apple's estimate of where eyes are focused
        // This is in face coordinate space (meters from face center)
        let lookAtPoint = faceAnchor.lookAtPoint
        
        // lookAtPoint gives position relative to face:
        // x: positive = looking right, negative = looking left
        // y: positive = looking up, negative = looking down
        // z: distance in front of face (always positive, usually ~0.5m for screen distance)
        
        // Normalize to a gaze direction vector
        let gazeDirection = simd_normalize(lookAtPoint)
        
        return gazeDirection
    }
    
    /// Get the eye gaze direction from a single eye transform
    /// The z-axis of the transform points where the pupil is looking
    static func getEyeGazeDirection(from eyeTransform: simd_float4x4) -> SIMD3<Float> {
        // Extract the forward direction (z-axis) from the eye transform
        // Column 2 is the z-axis in the 4x4 transform matrix
        let zAxis = SIMD3<Float>(
            eyeTransform.columns.2.x,
            eyeTransform.columns.2.y,
            eyeTransform.columns.2.z
        )
        return simd_normalize(zAxis)
    }
    
    /// Calculate combined gaze from both eye transforms
    static func calculateCombinedEyeGaze(
        leftEyeTransform: simd_float4x4,
        rightEyeTransform: simd_float4x4
    ) -> SIMD3<Float> {
        let leftGaze = getEyeGazeDirection(from: leftEyeTransform)
        let rightGaze = getEyeGazeDirection(from: rightEyeTransform)
        
        // Average both eyes for stability
        let combinedGaze = (leftGaze + rightGaze) / 2.0
        return simd_normalize(combinedGaze)
    }
    
    /// Convert lookAtPoint to normalized screen coordinates (-1 to 1)
    /// This is what we use to position the cursor
    static func lookAtPointToScreenCoordinates(
        lookAtPoint: simd_float3,
        faceTransform: simd_float4x4
    ) -> (screenPosition: SIMD2<Float>, rawAngles: SIMD2<Float>) {
        // lookAtPoint is in face coordinate space (meters)
        // x: horizontal gaze direction (positive = right, negative = left)
        // y: vertical gaze direction (positive = up, negative = down)
        // z: depth (distance to point, typically 0.5-2m)
        
        // Calculate angle from the gaze direction
        // atan2 gives us the angle in radians
        let horizontalAngle = atan2(lookAtPoint.x, lookAtPoint.z)
        let verticalAngle = atan2(lookAtPoint.y, lookAtPoint.z)
        
        // Convert angles to screen coordinates
        // Increased sensitivity for better range coverage
        // Eye movement range: typically ±15-20 degrees for comfortable viewing
        let maxHorizontalAngle: Float = 0.35 // ~20 degrees - more sensitive horizontally
        let maxVerticalAngle: Float = 0.5 // ~30 degrees - eyes have more vertical range
        
        let screenX = clamp(horizontalAngle / maxHorizontalAngle, min: -1.0, max: 1.0)
        let screenY = clamp(verticalAngle / maxVerticalAngle, min: -1.0, max: 1.0)
        
        return (SIMD2<Float>(screenX, screenY), SIMD2<Float>(horizontalAngle, verticalAngle))
    }
    
    /// Clamp a value between min and max
    private static func clamp(_ value: Float, min: Float, max: Float) -> Float {
        return Swift.max(min, Swift.min(max, value))
    }
    
    // MARK: - Eye State Detection
    
    /// Check if eyes are open using blend shapes
    static func areEyesOpen(_ blendShapes: [ARFaceAnchor.BlendShapeLocation: NSNumber]) -> Bool {
        let leftBlink = blendShapes[.eyeBlinkLeft]?.floatValue ?? 0
        let rightBlink = blendShapes[.eyeBlinkRight]?.floatValue ?? 0
        return leftBlink < 0.5 && rightBlink < 0.5
    }
    
    /// Get eye blink values
    static func getEyeBlinkValues(from blendShapes: [ARFaceAnchor.BlendShapeLocation: NSNumber]) -> (left: Float, right: Float) {
        let left = blendShapes[.eyeBlinkLeft]?.floatValue ?? 0
        let right = blendShapes[.eyeBlinkRight]?.floatValue ?? 0
        return (left, right)
    }
    
    /// Detect intentional blink (for clicking)
    /// Returns true if both eyes blink together quickly
    static func detectIntentionalBlink(
        leftBlink: Float,
        rightBlink: Float,
        previousLeftBlink: Float,
        previousRightBlink: Float
    ) -> Bool {
        // Both eyes must blink together (both > 0.7)
        let bothClosed = leftBlink > 0.7 && rightBlink > 0.7
        let wereOpen = previousLeftBlink < 0.3 && previousRightBlink < 0.3
        
        // Detect transition from open to closed
        return bothClosed && wereOpen
    }
    
    // MARK: - Hit Testing Based Eye Tracking
    
    /// Calculate gaze position using SceneKit hit testing
    /// Performs geometric ray casting from eye positions through lookAtTarget nodes to virtual screen plane
    /// - Parameters:
    ///   - eyeLNode: Left eye SceneKit node
    ///   - eyeRNode: Right eye SceneKit node
    ///   - lookAtTargetEyeLNode: LookAt target node for left eye (2m away)
    ///   - lookAtTargetEyeRNode: LookAt target node for right eye (2m away)
    ///   - virtualPhoneNode: Virtual phone node containing the screen plane
    ///   - phoneScreenSize: Physical screen size in meters
    ///   - phoneScreenPointSize: Screen size in points
    ///   - heightCompensation: Height offset in points (device-specific, default 312 for iPhone X)
    /// - Returns: Screen position in points (CGPoint), or nil if hit test fails
    static func calculateGazeUsingHitTesting(
        eyeLNode: SCNNode,
        eyeRNode: SCNNode,
        lookAtTargetEyeLNode: SCNNode,
        lookAtTargetEyeRNode: SCNNode,
        virtualPhoneNode: SCNNode,
        phoneScreenSize: CGSize,
        phoneScreenPointSize: CGSize,
        heightCompensation: CGFloat = 312
    ) -> CGPoint? {
        // Perform hit test using ray segments from lookAtTarget to eye position
        // This casts a ray backwards from the target point through the eye to find screen intersection
        let rightEyeWorldPos = eyeRNode.worldPosition
        let rightTargetWorldPos = lookAtTargetEyeRNode.worldPosition
        let leftEyeWorldPos = eyeLNode.worldPosition
        let leftTargetWorldPos = lookAtTargetEyeLNode.worldPosition
        
        // Use nil options like the prototype does
        let phoneScreenEyeRHitTestResults = virtualPhoneNode.hitTestWithSegment(
            from: rightTargetWorldPos,
            to: rightEyeWorldPos,
            options: nil
        )
        
        let phoneScreenEyeLHitTestResults = virtualPhoneNode.hitTestWithSegment(
            from: leftTargetWorldPos,
            to: leftEyeWorldPos,
            options: nil
        )
        
        // Debug logging every 30 frames to avoid spam
        let frameCount = Int(CACurrentMediaTime() * 60) % 30
        if frameCount == 0 {
            print("=== GazeCalculator Debug ===")
            print("Right eye world: (\(String(format: "%.3f", rightEyeWorldPos.x)), \(String(format: "%.3f", rightEyeWorldPos.y)), \(String(format: "%.3f", rightEyeWorldPos.z)))")
            print("Right target world: (\(String(format: "%.3f", rightTargetWorldPos.x)), \(String(format: "%.3f", rightTargetWorldPos.y)), \(String(format: "%.3f", rightTargetWorldPos.z)))")
            print("Virtual phone world: (\(String(format: "%.3f", virtualPhoneNode.worldPosition.x)), \(String(format: "%.3f", virtualPhoneNode.worldPosition.y)), \(String(format: "%.3f", virtualPhoneNode.worldPosition.z)))")
            print("Hit test results - R: \(phoneScreenEyeRHitTestResults.count), L: \(phoneScreenEyeLHitTestResults.count)")
            if let screenNode = virtualPhoneNode.childNodes.first {
                print("Screen node world: (\(String(format: "%.3f", screenNode.worldPosition.x)), \(String(format: "%.3f", screenNode.worldPosition.y)), \(String(format: "%.3f", screenNode.worldPosition.z)))")
                if let geometry = screenNode.geometry as? SCNPlane {
                    print("Screen geometry: \(geometry.width)x\(geometry.height) meters")
                } else {
                    print("Screen has no SCNPlane geometry!")
                }
            } else {
                print("ERROR: No screen child node found!")
            }
        }
        
        var eyeRLookAt = CGPoint()
        var eyeLLookAt = CGPoint()
        var hasRightEyeResult = false
        var hasLeftEyeResult = false
        
        // Process right eye hit test results (prototype only processes if results exist)
        for result in phoneScreenEyeRHitTestResults {
            let localX = CGFloat(result.localCoordinates.x)
            let localY = CGFloat(result.localCoordinates.y)
            
            // Convert local coordinates to screen point coordinates
            // Formula: screenX = (localX / (screenWidth/2)) * pointWidth
            // Formula: screenY = (localY / (screenHeight/2)) * pointHeight + heightCompensation
            eyeRLookAt.x = localX / (phoneScreenSize.width / 2) * phoneScreenPointSize.width
            eyeRLookAt.y = localY / (phoneScreenSize.height / 2) * phoneScreenPointSize.height + heightCompensation
            hasRightEyeResult = true
            
            // Debug: print local and converted coordinates
            print("GazeCalc: Right eye local: (\(String(format: "%.4f", localX)), \(String(format: "%.4f", localY))) -> screen: (\(String(format: "%.1f", eyeRLookAt.x)), \(String(format: "%.1f", eyeRLookAt.y)))")
            break // Use first result (like prototype)
        }
        
        // Process left eye hit test results
        for result in phoneScreenEyeLHitTestResults {
            let localX = CGFloat(result.localCoordinates.x)
            let localY = CGFloat(result.localCoordinates.y)
            
            eyeLLookAt.x = localX / (phoneScreenSize.width / 2) * phoneScreenPointSize.width
            eyeLLookAt.y = localY / (phoneScreenSize.height / 2) * phoneScreenPointSize.height + heightCompensation
            hasLeftEyeResult = true
            
            // Debug: print local and converted coordinates
            print("GazeCalc: Left eye local: (\(String(format: "%.4f", localX)), \(String(format: "%.4f", localY))) -> screen: (\(String(format: "%.1f", eyeLLookAt.x)), \(String(format: "%.1f", eyeLLookAt.y)))")
            break // Use first result (like prototype)
        }
        
        // Only return result if both eyes have valid hit test results (like prototype)
        guard hasRightEyeResult && hasLeftEyeResult else {
            print("GazeCalc: No results - R:\(hasRightEyeResult) L:\(hasLeftEyeResult)")
            return nil // Hit test failed for one or both eyes
        }
        
        // Note: We don't validate bounds or eye consistency here.
        // The eyes are physically separated (~6-7cm), so their gaze rays naturally
        // hit different X coordinates on the screen. This parallax is normal.
        // The prototype just averages both eyes without strict validation.
        
        // Average left and right eye results
        let averagedX = (eyeLLookAt.x + eyeRLookAt.x) / 2
        let averagedY = (eyeLLookAt.y + eyeRLookAt.y) / 2
        
        // Return without Y-axis flip (screen Y increases downward, matching gaze direction)
        return CGPoint(x: averagedX, y: averagedY)
    }
}
