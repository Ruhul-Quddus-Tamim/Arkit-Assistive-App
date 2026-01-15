import UIKit
import ARKit
import SceneKit

/// Protocol for calibration completion
protocol CalibrationViewControllerDelegate: AnyObject {
    func calibrationDidComplete(_ calibration: CalibrationData)
    func calibrationDidCancel()
}

/// View controller that guides user through eye tracking calibration
/// Shows 9 dots at different screen positions and collects raw gaze data
class CalibrationViewController: UIViewController {
    
    weak var delegate: CalibrationViewControllerDelegate?
    
    // MARK: - UI Elements
    private var sceneView: ARSCNView!
    private var calibrationDot: UIView!
    private var instructionLabel: UILabel!
    private var progressLabel: UILabel!
    private var cancelButton: UIButton!
    
    // MARK: - SceneKit nodes (same as CameraViewController for hit testing)
    private var faceNode: SCNNode = SCNNode()
    
    private var eyeLNode: SCNNode = {
        let geometry = SCNCone(topRadius: 0.005, bottomRadius: 0, height: 0.2)
        geometry.radialSegmentCount = 3
        geometry.firstMaterial?.diffuse.contents = UIColor.blue
        let node = SCNNode()
        node.geometry = geometry
        node.eulerAngles.x = -.pi / 2
        node.position.z = 0.1
        let parentNode = SCNNode()
        parentNode.addChildNode(node)
        return parentNode
    }()
    
    private var eyeRNode: SCNNode = {
        let geometry = SCNCone(topRadius: 0.005, bottomRadius: 0, height: 0.2)
        geometry.radialSegmentCount = 3
        geometry.firstMaterial?.diffuse.contents = UIColor.blue
        let node = SCNNode()
        node.geometry = geometry
        node.eulerAngles.x = -.pi / 2
        node.position.z = 0.1
        let parentNode = SCNNode()
        parentNode.addChildNode(node)
        return parentNode
    }()
    
    private var lookAtTargetEyeLNode: SCNNode = SCNNode()
    private var lookAtTargetEyeRNode: SCNNode = SCNNode()
    private var virtualPhoneNode: SCNNode = SCNNode()
    private var virtualScreenNode: SCNNode = SCNNode()
    
    // Phone screen size (same as CameraViewController)
    private let phoneScreenSize = CGSize(width: 0.0718, height: 0.157)
    
    // MARK: - Calibration State
    private var calibrationPoints: [CGPoint] = []
    private var currentPointIndex: Int = 0
    private var rawSamplesForCurrentPoint: [CGPoint] = []
    private var collectedRawPoints: [CGPoint] = []
    private var collectedScreenPoints: [CGPoint] = []
    
    private let samplesPerPoint: Int = 60 // ~2 seconds at 30fps
    private let marginPercent: CGFloat = 0.1 // 10% margin from screen edges
    
    private var isCollecting: Bool = false
    private var countdownTimer: Timer?
    private var countdown: Int = 3
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .black
        
        setupARScene()
        setupUI()
        // Don't setup calibration points here - view.bounds might be zero
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Setup calibration points now that view bounds are available
        // Only set up if bounds are valid (non-zero) and points haven't been set up yet
        if view.bounds.width > 0 && view.bounds.height > 0 && calibrationPoints.isEmpty {
            setupCalibrationPoints()
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startARSession()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sceneView.session.pause()
        countdownTimer?.invalidate()
    }
    
    // MARK: - Setup
    
    private func setupARScene() {
        sceneView = ARSCNView()
        sceneView.translatesAutoresizingMaskIntoConstraints = false
        sceneView.delegate = self
        sceneView.session.delegate = self
        // Make scene view mostly transparent so we can see the dots
        sceneView.alpha = 0.3
        view.addSubview(sceneView)
        
        NSLayoutConstraint.activate([
            sceneView.topAnchor.constraint(equalTo: view.topAnchor),
            sceneView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            sceneView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sceneView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        
        // Setup scene graph
        sceneView.scene.rootNode.addChildNode(faceNode)
        sceneView.scene.rootNode.addChildNode(virtualPhoneNode)
        
        // Create virtual screen geometry
        let screenGeometry = SCNPlane(width: phoneScreenSize.width, height: phoneScreenSize.height)
        screenGeometry.firstMaterial?.isDoubleSided = true
        screenGeometry.firstMaterial?.diffuse.contents = UIColor.clear
        virtualScreenNode.geometry = screenGeometry
        virtualPhoneNode.addChildNode(virtualScreenNode)
        
        faceNode.addChildNode(eyeLNode)
        faceNode.addChildNode(eyeRNode)
        eyeLNode.addChildNode(lookAtTargetEyeLNode)
        eyeRNode.addChildNode(lookAtTargetEyeRNode)
        lookAtTargetEyeLNode.position.z = 2
        lookAtTargetEyeRNode.position.z = 2
    }
    
    private func setupUI() {
        // Calibration dot (large, pulsing)
        // Use frame-based positioning (NOT Auto Layout) so we can set center directly
        calibrationDot = UIView(frame: CGRect(x: 0, y: 0, width: 50, height: 50))
        calibrationDot.backgroundColor = .systemGreen
        calibrationDot.layer.cornerRadius = 25
        calibrationDot.translatesAutoresizingMaskIntoConstraints = true // Use frame-based positioning
        calibrationDot.isHidden = true
        view.addSubview(calibrationDot)
        
        // Instruction label
        instructionLabel = UILabel()
        instructionLabel.text = "Eye Tracking Calibration"
        instructionLabel.textColor = .white
        instructionLabel.font = .systemFont(ofSize: 24, weight: .bold)
        instructionLabel.textAlignment = .center
        instructionLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(instructionLabel)
        
        // Progress label
        progressLabel = UILabel()
        progressLabel.text = "Look at each dot as it appears"
        progressLabel.textColor = .lightGray
        progressLabel.font = .systemFont(ofSize: 16)
        progressLabel.textAlignment = .center
        progressLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(progressLabel)
        
        // Cancel button
        cancelButton = UIButton(type: .system)
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.setTitleColor(.white, for: .normal)
        cancelButton.backgroundColor = .systemRed.withAlphaComponent(0.8)
        cancelButton.layer.cornerRadius = 8
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cancelButton)
        
        NSLayoutConstraint.activate([
            instructionLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            instructionLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -50),
            
            progressLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            progressLabel.topAnchor.constraint(equalTo: instructionLabel.bottomAnchor, constant: 20),
            
            cancelButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            cancelButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -30),
            cancelButton.widthAnchor.constraint(equalToConstant: 120),
            cancelButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }
    
    private func setupCalibrationPoints() {
        // Generate 9 calibration points with margin from edges
        let w = view.bounds.width
        let h = view.bounds.height
        let marginX = w * marginPercent
        let marginY = h * marginPercent
        
        print("CalibrationVC: View bounds: \(w)x\(h), margins: \(marginX)x\(marginY)")
        
        calibrationPoints = [
            // Center
            CGPoint(x: w / 2, y: h / 2),
            // Corners
            CGPoint(x: marginX, y: marginY),                    // Top-left
            CGPoint(x: w - marginX, y: marginY),                // Top-right
            CGPoint(x: marginX, y: h - marginY),                // Bottom-left
            CGPoint(x: w - marginX, y: h - marginY),            // Bottom-right
            // Edges (midpoints)
            CGPoint(x: w / 2, y: marginY),                      // Top-center
            CGPoint(x: w / 2, y: h - marginY),                  // Bottom-center
            CGPoint(x: marginX, y: h / 2),                      // Left-center
            CGPoint(x: w - marginX, y: h / 2)                   // Right-center
        ]
        
        print("CalibrationVC: Setup \(calibrationPoints.count) calibration points:")
        for (index, point) in calibrationPoints.enumerated() {
            print("  Point \(index + 1): (\(point.x), \(point.y))")
        }
    }
    
    private func startARSession() {
        guard ARFaceTrackingConfiguration.isSupported else {
            showError("Face tracking not supported on this device")
            return
        }
        
        let configuration = ARFaceTrackingConfiguration()
        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        
        // Start calibration after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.startCalibration()
        }
    }
    
    // MARK: - Calibration Flow
    
    private func startCalibration() {
        currentPointIndex = 0
        collectedRawPoints.removeAll()
        collectedScreenPoints.removeAll()
        
        showNextPoint()
    }
    
    private func showNextPoint() {
        // Ensure calibration points are set up with valid bounds
        // First point is center, so check if it's at (0,0) which would indicate zero bounds were used
        let needsRecalculation = calibrationPoints.isEmpty || 
            (calibrationPoints.first == CGPoint.zero) ||
            (calibrationPoints.first?.x ?? 0 < 10) // Center should be at least screenWidth/2
        
        if needsRecalculation {
            if view.bounds.width > 0 && view.bounds.height > 0 {
                calibrationPoints.removeAll()
                setupCalibrationPoints()
            } else {
                // View bounds still not available, wait and retry
                print("CalibrationVC: Waiting for valid view bounds...")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.showNextPoint()
                }
                return
            }
        }
        
        guard currentPointIndex < calibrationPoints.count else {
            finishCalibration()
            return
        }
        
        let point = calibrationPoints[currentPointIndex]
        
        // Debug: print the point position
        print("CalibrationVC: Showing point \(currentPointIndex + 1) at (\(point.x), \(point.y)) - screen: \(view.bounds.width)x\(view.bounds.height)")
        
        // Update UI
        instructionLabel.text = "Look at the dot"
        progressLabel.text = "Point \(currentPointIndex + 1) of \(calibrationPoints.count)"
        
        // Position and show dot
        calibrationDot.center = point
        calibrationDot.isHidden = false
        calibrationDot.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
        calibrationDot.alpha = 0
        
        // Animate dot appearance
        UIView.animate(withDuration: 0.3) {
            self.calibrationDot.transform = .identity
            self.calibrationDot.alpha = 1
        }
        
        // Start pulsing animation
        startPulseAnimation()
        
        // Start countdown before collecting
        countdown = 2 // Give user 2 seconds to look at dot
        instructionLabel.text = "Look at the dot..."
        
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            
            self.countdown -= 1
            if self.countdown <= 0 {
                timer.invalidate()
                self.startCollecting()
            }
        }
    }
    
    private func startPulseAnimation() {
        UIView.animate(withDuration: 0.5, delay: 0, options: [.autoreverse, .repeat], animations: {
            self.calibrationDot.transform = CGAffineTransform(scaleX: 1.2, y: 1.2)
        })
    }
    
    private func stopPulseAnimation() {
        calibrationDot.layer.removeAllAnimations()
        calibrationDot.transform = .identity
    }
    
    private func startCollecting() {
        isCollecting = true
        rawSamplesForCurrentPoint.removeAll()
        
        instructionLabel.text = "Recording..."
        calibrationDot.backgroundColor = .systemYellow
        
        print("CalibrationVC: Starting collection for point \(currentPointIndex + 1)")
    }
    
    private func processGazeSample(_ rawPoint: CGPoint) {
        guard isCollecting else { return }
        
        rawSamplesForCurrentPoint.append(rawPoint)
        
        // Update progress
        let progress = Float(rawSamplesForCurrentPoint.count) / Float(samplesPerPoint)
        progressLabel.text = "Recording... \(Int(progress * 100))%"
        
        if rawSamplesForCurrentPoint.count >= samplesPerPoint {
            finishCurrentPoint()
        }
    }
    
    private func finishCurrentPoint() {
        isCollecting = false
        stopPulseAnimation()
        
        // Calculate average raw position for this point
        guard !rawSamplesForCurrentPoint.isEmpty else {
            print("CalibrationVC: No samples collected for point \(currentPointIndex + 1)")
            currentPointIndex += 1
            showNextPoint()
            return
        }
        
        let avgX = rawSamplesForCurrentPoint.map { $0.x }.reduce(0, +) / CGFloat(rawSamplesForCurrentPoint.count)
        let avgY = rawSamplesForCurrentPoint.map { $0.y }.reduce(0, +) / CGFloat(rawSamplesForCurrentPoint.count)
        let avgRawPoint = CGPoint(x: avgX, y: avgY)
        
        collectedRawPoints.append(avgRawPoint)
        collectedScreenPoints.append(calibrationPoints[currentPointIndex])
        
        print("CalibrationVC: Point \(currentPointIndex + 1) - screen:(\(calibrationPoints[currentPointIndex].x), \(calibrationPoints[currentPointIndex].y)) raw:(\(avgX), \(avgY))")
        
        // Animate dot completion
        calibrationDot.backgroundColor = .systemGreen
        UIView.animate(withDuration: 0.2, animations: {
            self.calibrationDot.transform = CGAffineTransform(scaleX: 1.5, y: 1.5)
            self.calibrationDot.alpha = 0
        }) { _ in
            self.calibrationDot.isHidden = true
            self.calibrationDot.transform = .identity
            self.currentPointIndex += 1
            
            // Short delay before next point
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.showNextPoint()
            }
        }
    }
    
    private func finishCalibration() {
        countdownTimer?.invalidate()
        calibrationDot.isHidden = true
        
        instructionLabel.text = "Calculating calibration..."
        progressLabel.text = "Please wait"
        
        // Calculate calibration from collected points
        if let calibration = CalibrationData.calculate(rawPoints: collectedRawPoints, screenPoints: collectedScreenPoints) {
            calibration.save()
            
            instructionLabel.text = "Calibration Complete!"
            progressLabel.text = "Eye tracking is now calibrated"
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self.delegate?.calibrationDidComplete(calibration)
            }
        } else {
            showError("Calibration failed. Please try again.")
        }
    }
    
    private func showError(_ message: String) {
        instructionLabel.text = "Error"
        progressLabel.text = message
        calibrationDot.isHidden = true
    }
    
    @objc private func cancelTapped() {
        countdownTimer?.invalidate()
        sceneView.session.pause()
        delegate?.calibrationDidCancel()
    }
    
    // MARK: - Gaze Calculation (simplified version for calibration)
    
    private func calculateRawGaze(from faceAnchor: ARFaceAnchor) -> CGPoint? {
        // Use the same hit testing logic as EyeTracker/GazeCalculator
        let phoneScreenPointSize = view.bounds.size
        
        let phoneScreenEyeRHitTestResults = virtualPhoneNode.hitTestWithSegment(
            from: lookAtTargetEyeRNode.worldPosition,
            to: eyeRNode.worldPosition,
            options: nil
        )
        
        let phoneScreenEyeLHitTestResults = virtualPhoneNode.hitTestWithSegment(
            from: lookAtTargetEyeLNode.worldPosition,
            to: eyeLNode.worldPosition,
            options: nil
        )
        
        var eyeRLookAt = CGPoint()
        var eyeLLookAt = CGPoint()
        var hasRightEyeResult = false
        var hasLeftEyeResult = false
        
        for result in phoneScreenEyeRHitTestResults {
            let localX = CGFloat(result.localCoordinates.x)
            let localY = CGFloat(result.localCoordinates.y)
            eyeRLookAt.x = localX / (phoneScreenSize.width / 2) * phoneScreenPointSize.width
            eyeRLookAt.y = localY / (phoneScreenSize.height / 2) * phoneScreenPointSize.height
            hasRightEyeResult = true
            break
        }
        
        for result in phoneScreenEyeLHitTestResults {
            let localX = CGFloat(result.localCoordinates.x)
            let localY = CGFloat(result.localCoordinates.y)
            eyeLLookAt.x = localX / (phoneScreenSize.width / 2) * phoneScreenPointSize.width
            eyeLLookAt.y = localY / (phoneScreenSize.height / 2) * phoneScreenPointSize.height
            hasLeftEyeResult = true
            break
        }
        
        guard hasRightEyeResult && hasLeftEyeResult else { return nil }
        
        let averagedX = (eyeLLookAt.x + eyeRLookAt.x) / 2
        let averagedY = (eyeLLookAt.y + eyeRLookAt.y) / 2
        
        // Return raw point without Y-axis flip - calibration will handle the mapping
        return CGPoint(x: averagedX, y: averagedY)
    }
}

// MARK: - ARSCNViewDelegate
extension CalibrationViewController: ARSCNViewDelegate {
    
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        guard anchor is ARFaceAnchor else { return }
        faceNode.transform = node.transform
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard let faceAnchor = anchor as? ARFaceAnchor else { return }
        
        faceNode.transform = node.transform
        eyeLNode.simdTransform = faceAnchor.leftEyeTransform
        eyeRNode.simdTransform = faceAnchor.rightEyeTransform
        
        // Calculate and process gaze sample
        if let rawGaze = calculateRawGaze(from: faceAnchor) {
            DispatchQueue.main.async {
                self.processGazeSample(rawGaze)
            }
        }
    }
    
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        if let pointOfView = sceneView.pointOfView {
            virtualPhoneNode.transform = pointOfView.transform
        }
    }
}

// MARK: - ARSessionDelegate
extension CalibrationViewController: ARSessionDelegate {
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        print("CalibrationVC: AR session failed - \(error)")
        showError("AR session error")
    }
}
