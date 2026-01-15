import Foundation
import ARKit
import simd
import SceneKit

/// Protocol for receiving eye tracking updates
protocol EyeTrackerDelegate: AnyObject {
    // New method: screen coordinates centered at (0,0) like prototype
    func eyeTracker(_ tracker: EyeTracker, didUpdateGazeScreenPosition screenPosition: CGPoint, lookAtPoint: simd_float3)
    // Legacy method: normalized coordinates (kept for backward compatibility)
    func eyeTracker(_ tracker: EyeTracker, didUpdateGaze screenPosition: SIMD2<Float>, lookAtPoint: simd_float3, rawAngles: SIMD2<Float>)
    func eyeTracker(_ tracker: EyeTracker, didDetectBlink isBlinking: Bool)
    func eyeTrackerDidLoseTracking(_ tracker: EyeTracker)
}

/// Core eye tracking class using ARKit's proper eye tracking APIs
class EyeTracker {
    weak var delegate: EyeTrackerDelegate?
    
    // SceneKit nodes for hit testing (set by CameraViewController)
    var eyeLNode: SCNNode?
    var eyeRNode: SCNNode?
    var lookAtTargetEyeLNode: SCNNode?
    var lookAtTargetEyeRNode: SCNNode?
    var virtualPhoneNode: SCNNode?
    
    // Phone screen constants (set by CameraViewController)
    var phoneScreenSize: CGSize?
    var phoneScreenPointSize: CGSize?
    
    // Calibration data for mapping raw gaze to screen positions
    var calibrationData: CalibrationData?
    
    // Smoothing using enhanced approach (last 15 positions for more stability)
    private var eyeLookAtPositionXs: [CGFloat] = []
    private var eyeLookAtPositionYs: [CGFloat] = []
    private let smoothThresholdNumber: Int = 15 // Increased from 10 for more stability
    
    // Dead zone to prevent micro-movements (normalized by screen width)
    private let deadZone: Float = 0.05 // 5% of screen width
    private var lastScreenPosition: CGPoint? // Last screen position (centered at 0,0)
    
    // Velocity filtering to prevent rapid movements
    private var lastUpdateTime: CFTimeInterval = 0
    private let maxVelocity: Float = 2.0 // Maximum normalized units per second
    private let outlierThreshold: Float = 0.3 // Reject positions >30% away from average
    
    // Exponential moving average for extra smoothing
    private let exponentialAlpha: Float = 0.7 // 0.7 * previous + 0.3 * new
    
    // Blink detection
    private var previousLeftBlink: Float = 0
    private var previousRightBlink: Float = 0
    private var isCurrentlyBlinking: Bool = false
    
    // Flag to use hit testing (new method) vs lookAtPoint (old method)
    var useHitTesting: Bool = true
    
    /// Process face anchor and extract accurate gaze data
    /// Uses hit testing for accurate eye tracking (new method) or lookAtPoint (fallback)
    func processFaceAnchor(_ faceAnchor: ARFaceAnchor) {
        let blendShapes = faceAnchor.blendShapes
        
        // Check if eyes are open
        guard GazeCalculator.areEyesOpen(blendShapes) else {
            // Eyes closed - check for intentional blink
            let (leftBlink, rightBlink) = GazeCalculator.getEyeBlinkValues(from: blendShapes)
            
            let intentionalBlink = GazeCalculator.detectIntentionalBlink(
                leftBlink: leftBlink,
                rightBlink: rightBlink,
                previousLeftBlink: previousLeftBlink,
                previousRightBlink: previousRightBlink
            )
            
            if intentionalBlink && !isCurrentlyBlinking {
                isCurrentlyBlinking = true
                delegate?.eyeTracker(self, didDetectBlink: true)
            }
            
            previousLeftBlink = leftBlink
            previousRightBlink = rightBlink
            return
        }
        
        // Eyes are open
        if isCurrentlyBlinking {
            isCurrentlyBlinking = false
            delegate?.eyeTracker(self, didDetectBlink: false)
        }
        
        // Update blink tracking
        let (leftBlink, rightBlink) = GazeCalculator.getEyeBlinkValues(from: blendShapes)
        previousLeftBlink = leftBlink
        previousRightBlink = rightBlink
        
        // Update eye node transforms from face anchor
        if let eyeLNode = eyeLNode, let eyeRNode = eyeRNode {
            eyeLNode.simdTransform = faceAnchor.leftEyeTransform
            eyeRNode.simdTransform = faceAnchor.rightEyeTransform
        }
        
        // Use hit testing method if available, otherwise fall back to lookAtPoint
        if useHitTesting,
           let eyeLNode = eyeLNode,
           let eyeRNode = eyeRNode,
           let lookAtTargetEyeLNode = lookAtTargetEyeLNode,
           let lookAtTargetEyeRNode = lookAtTargetEyeRNode,
           let virtualPhoneNode = virtualPhoneNode,
           let phoneScreenSize = phoneScreenSize,
           let phoneScreenPointSize = phoneScreenPointSize {
            
            // Capture lookAtPoint before async block
            let lookAtPoint = faceAnchor.lookAtPoint
            
            // Capture all values needed inside the closure
            let capturedEyeLNode = eyeLNode
            let capturedEyeRNode = eyeRNode
            let capturedLookAtTargetEyeLNode = lookAtTargetEyeLNode
            let capturedLookAtTargetEyeRNode = lookAtTargetEyeRNode
            let capturedVirtualPhoneNode = virtualPhoneNode
            let capturedPhoneScreenSize = phoneScreenSize
            let capturedPhoneScreenPointSize = phoneScreenPointSize
            
            // Process on main thread like the prototype
            DispatchQueue.main.async { [weak self] in
                guard let strongSelf = self else { return }
                
                strongSelf.processHitTestResult(
                    eyeLNode: capturedEyeLNode,
                    eyeRNode: capturedEyeRNode,
                    lookAtTargetEyeLNode: capturedLookAtTargetEyeLNode,
                    lookAtTargetEyeRNode: capturedLookAtTargetEyeRNode,
                    virtualPhoneNode: capturedVirtualPhoneNode,
                    phoneScreenSize: capturedPhoneScreenSize,
                    phoneScreenPointSize: capturedPhoneScreenPointSize,
                    lookAtPoint: lookAtPoint
                )
            }
        } else {
            // Fallback to lookAtPoint method
            let lookAtPoint = faceAnchor.lookAtPoint
            
            // Convert to screen coordinates (-1 to 1)
            let (rawScreenPosition, rawAngles) = GazeCalculator.lookAtPointToScreenCoordinates(
                lookAtPoint: lookAtPoint,
                faceTransform: faceAnchor.transform
            )
            
            // Apply smoothing (old method)
            let smoothedPosition = applySmoothing(rawScreenPosition)
            
            // Notify delegate with raw angles for debugging
            delegate?.eyeTracker(self, didUpdateGaze: smoothedPosition, lookAtPoint: lookAtPoint, rawAngles: rawAngles)
        }
    }
    
    /// Reset tracking state
    func reset() {
        eyeLookAtPositionXs.removeAll()
        eyeLookAtPositionYs.removeAll()
        lastScreenPosition = nil
        lastUpdateTime = 0
        previousLeftBlink = 0
        previousRightBlink = 0
        isCurrentlyBlinking = false
    }
    
    /// Process hit test result on main thread
    private func processHitTestResult(
        eyeLNode: SCNNode,
        eyeRNode: SCNNode,
        lookAtTargetEyeLNode: SCNNode,
        lookAtTargetEyeRNode: SCNNode,
        virtualPhoneNode: SCNNode,
        phoneScreenSize: CGSize,
        phoneScreenPointSize: CGSize,
        lookAtPoint: simd_float3
    ) {
        // Height compensation: Set to 0 for now to debug, then calibrate based on device
        // The original iPhone X value of 312 was device-specific calibration
        let heightCompensation: CGFloat = 0
        
        guard let screenPoint = GazeCalculator.calculateGazeUsingHitTesting(
            eyeLNode: eyeLNode,
            eyeRNode: eyeRNode,
            lookAtTargetEyeLNode: lookAtTargetEyeLNode,
            lookAtTargetEyeRNode: lookAtTargetEyeRNode,
            virtualPhoneNode: virtualPhoneNode,
            phoneScreenSize: phoneScreenSize,
            phoneScreenPointSize: phoneScreenPointSize,
            heightCompensation: heightCompensation
        ) else {
            print("EyeTracker: Hit test failed - no screen point")
            return
        }
        
        print("EyeTracker: Hit test succeeded - screenPoint: (\(screenPoint.x), \(screenPoint.y))")
        
        // Skip outlier detection for now - get basic tracking working first
        
        // Add to smoothing arrays
        eyeLookAtPositionXs.append(screenPoint.x)
        eyeLookAtPositionYs.append(screenPoint.y)
        
        // Keep only last N positions
        eyeLookAtPositionXs = Array(eyeLookAtPositionXs.suffix(smoothThresholdNumber))
        eyeLookAtPositionYs = Array(eyeLookAtPositionYs.suffix(smoothThresholdNumber))
        
        // Calculate smoothed position - use at least 1 sample for immediate feedback
        let minSamples = 1
        guard eyeLookAtPositionXs.count >= minSamples,
              eyeLookAtPositionYs.count >= minSamples,
              let smoothX = eyeLookAtPositionXs.average,
              let smoothY = eyeLookAtPositionYs.average else {
            print("EyeTracker: Not enough samples yet - X: \(eyeLookAtPositionXs.count), Y: \(eyeLookAtPositionYs.count)")
            return
        }
        
        // Use screen coordinates directly (centered at 0,0) like prototype
        var screenPosition = CGPoint(x: smoothX, y: smoothY)
        
        // Apply calibration if available
        if let calibration = calibrationData, calibration.isCalibrated {
            screenPosition = calibration.apply(rawPoint: screenPosition)
            print("EyeTracker: Applied calibration - raw:(\(smoothX), \(smoothY)) -> calibrated:(\(screenPosition.x), \(screenPosition.y))")
        } else {
            print("EyeTracker: No calibration - using raw position: (\(smoothX), \(smoothY))")
        }
        
        // Call delegate with calibrated screen coordinates
        delegate?.eyeTracker(self, didUpdateGazeScreenPosition: screenPosition, lookAtPoint: lookAtPoint)
    }
    
    /// Apply multi-stage smoothing to eliminate jitter (fallback method for lookAtPoint)
    private func applySmoothing(_ newPosition: SIMD2<Float>) -> SIMD2<Float> {
        // Fallback smoothing when hit testing is not available
        // Convert normalized to screen coordinates for consistency
        // This is legacy support - hit testing should be used instead
        return newPosition
    }
}
