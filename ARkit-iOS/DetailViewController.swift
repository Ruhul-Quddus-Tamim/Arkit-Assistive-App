import UIKit
import ARKit
import SceneKit

class DetailViewController: UIViewController {
    
    private var titleLabel: UILabel!
    private var descriptionLabel: UILabel!
    private var backButton: UIButton!
    private var icon: MenuIcon?
    
    // MARK: - Eye Tracking
    
    private var sceneView: ARSCNView!
    private let eyeTracker = EyeTracker()
    private let dwellDetector = DwellDetector()
    private var gazeCursor: UIView?
    
    // SceneKit nodes for hit testing
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
    
    private let phoneScreenSize = CGSize(width: 0.0718, height: 0.157)
    private var phoneScreenPointSize: CGSize {
        if view.bounds.width > 0 && view.bounds.height > 0 {
            return view.bounds.size
        }
        return CGSize(width: 1311, height: 603)
    }
    
    // Dwell tracking
    private var currentDwellingButton: UIButton?
    
    // Cursor smoothing
    private var cursorSmoothingFactor: Float = 0.7
    private var lastCursorPosition: CGPoint?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .systemBackground
        
        setupARScene()
        setupUI()
        setupGazeCursor()
        setupEyeTracking()
        setupDwellDetector()
        
        // Load calibration if available
        let calibration = CalibrationData.load()
        if calibration.isCalibrated {
            eyeTracker.calibrationData = calibration
            // Show cursor if already calibrated
            gazeCursor?.isHidden = false
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        Logger.debug("=== DetailViewController viewWillAppear - THIS IS A PLACEHOLDER SCREEN ===")
        Logger.debug("You arrived here because you gazed on an icon that is NOT Voice Input")
        startFaceTracking()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        Logger.debug("=== DetailViewController viewWillDisappear - STOPPING eye tracking and dwell ===")
        sceneView.session.pause()
        // CRITICAL: Cancel any pending dwell to prevent it from completing after navigation
        dwellDetector.cancelDwell()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        eyeTracker.phoneScreenPointSize = phoneScreenPointSize
    }
    
    func configure(with icon: MenuIcon) {
        self.icon = icon
        titleLabel?.text = icon.title
        descriptionLabel?.text = "This is a placeholder screen for \(icon.title).\n\nFunctionality will be implemented based on your requirements."
    }
    
    // MARK: - Setup
    
    private func setupARScene() {
        // Hidden AR scene view for face tracking
        sceneView = ARSCNView()
        sceneView.isHidden = true // Hide but keep active for tracking
        sceneView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sceneView)
        
        NSLayoutConstraint.activate([
            sceneView.topAnchor.constraint(equalTo: view.topAnchor),
            sceneView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sceneView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            sceneView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        // Setup scene graph
        sceneView.scene.rootNode.addChildNode(faceNode)
        sceneView.scene.rootNode.addChildNode(virtualPhoneNode)
        
        let screenGeometry = SCNPlane(width: phoneScreenSize.width, height: phoneScreenSize.height)
        screenGeometry.firstMaterial?.isDoubleSided = true
        screenGeometry.firstMaterial?.diffuse.contents = UIColor.green.withAlphaComponent(0.01)
        virtualScreenNode.geometry = screenGeometry
        virtualPhoneNode.addChildNode(virtualScreenNode)
        
        faceNode.addChildNode(eyeLNode)
        faceNode.addChildNode(eyeRNode)
        eyeLNode.addChildNode(lookAtTargetEyeLNode)
        eyeRNode.addChildNode(lookAtTargetEyeRNode)
        lookAtTargetEyeLNode.position.z = 2
        lookAtTargetEyeRNode.position.z = 2
        
        sceneView.delegate = self
        sceneView.session.delegate = self
    }
    
    private func setupUI() {
        // Back Button - Large and visible in top-left
        backButton = UIButton(type: .system)
        backButton.setTitle("← Back", for: .normal)
        backButton.setTitleColor(.white, for: .normal)
        backButton.titleLabel?.font = .systemFont(ofSize: 20, weight: .semibold)
        backButton.backgroundColor = UIColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 1.0) // System blue
        backButton.layer.cornerRadius = 12
        backButton.tag = 100 // Mark as selectable for dwell detection
        backButton.accessibilityIdentifier = "back"
        backButton.addTarget(self, action: #selector(backButtonTapped), for: .touchUpInside)
        backButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(backButton)
        
        titleLabel = UILabel()
        titleLabel.text = "Detail"
        titleLabel.font = .systemFont(ofSize: 28, weight: .bold)
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)
        
        descriptionLabel = UILabel()
        descriptionLabel.text = "Placeholder screen"
        descriptionLabel.font = .systemFont(ofSize: 16)
        descriptionLabel.textAlignment = .center
        descriptionLabel.numberOfLines = 0
        descriptionLabel.textColor = .secondaryLabel
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(descriptionLabel)
        
        NSLayoutConstraint.activate([
            backButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            backButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            backButton.widthAnchor.constraint(equalToConstant: 120),
            backButton.heightAnchor.constraint(equalToConstant: 50),
            
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleLabel.topAnchor.constraint(equalTo: backButton.bottomAnchor, constant: 30),
            
            descriptionLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            descriptionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 20),
            descriptionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            descriptionLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40)
        ])
    }
    
    private func setupGazeCursor() {
        // Create gaze cursor - a large green circle for visibility
        let cursorSize: CGFloat = 60
        gazeCursor = UIView(frame: CGRect(x: 0, y: 0, width: cursorSize, height: cursorSize))
        gazeCursor?.translatesAutoresizingMaskIntoConstraints = true // Frame-based positioning
        gazeCursor?.isHidden = true
        gazeCursor?.backgroundColor = .clear
        gazeCursor?.isUserInteractionEnabled = false // Prevent cursor from interfering with hit testing
        view.addSubview(gazeCursor!)
        
        // Outer green ring with glow effect
        let outerRing = UIView(frame: CGRect(x: 0, y: 0, width: cursorSize, height: cursorSize))
        outerRing.backgroundColor = .clear
        outerRing.layer.borderColor = UIColor.systemGreen.cgColor
        outerRing.layer.borderWidth = 4
        outerRing.layer.cornerRadius = cursorSize / 2
        outerRing.layer.shadowColor = UIColor.green.cgColor
        outerRing.layer.shadowOffset = .zero
        outerRing.layer.shadowRadius = 8
        outerRing.layer.shadowOpacity = 0.8
        outerRing.isUserInteractionEnabled = false
        gazeCursor?.addSubview(outerRing)
        
        // Inner solid green dot
        let innerDotSize: CGFloat = 20
        let innerDot = UIView(frame: CGRect(
            x: (cursorSize - innerDotSize) / 2,
            y: (cursorSize - innerDotSize) / 2,
            width: innerDotSize,
            height: innerDotSize
        ))
        innerDot.backgroundColor = .systemGreen
        innerDot.layer.cornerRadius = innerDotSize / 2
        innerDot.layer.shadowColor = UIColor.green.cgColor
        innerDot.layer.shadowOffset = .zero
        innerDot.layer.shadowRadius = 5
        innerDot.layer.shadowOpacity = 1.0
        innerDot.isUserInteractionEnabled = false
        gazeCursor?.addSubview(innerDot)
    }
    
    private func setupEyeTracking() {
        eyeTracker.delegate = self
        
        // Setup SceneKit nodes
        eyeTracker.eyeLNode = eyeLNode
        eyeTracker.eyeRNode = eyeRNode
        eyeTracker.lookAtTargetEyeLNode = lookAtTargetEyeLNode
        eyeTracker.lookAtTargetEyeRNode = lookAtTargetEyeRNode
        eyeTracker.virtualPhoneNode = virtualPhoneNode
        eyeTracker.phoneScreenSize = phoneScreenSize
        eyeTracker.phoneScreenPointSize = phoneScreenPointSize
        eyeTracker.useHitTesting = true
    }
    
    private func setupDwellDetector() {
        dwellDetector.delegate = self
        dwellDetector.setDwellThreshold(1.8) // 1.8 seconds
    }
    
    private func startFaceTracking() {
        guard ARFaceTrackingConfiguration.isSupported else {
            Logger.error("Face tracking not supported")
            return
        }
        
        let configuration = ARFaceTrackingConfiguration()
        configuration.maximumNumberOfTrackedFaces = 1
        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }
    
    // MARK: - Actions
    
    @objc private func backButtonTapped() {
        // Navigate back to HomeViewController (root)
        navigationController?.popToRootViewController(animated: true)
    }
    
    // MARK: - Eye Tracking Helpers
    
    private func convertGazeToAbsolutePosition(_ screenPosition: CGPoint) -> CGPoint {
        let screenWidth = view.bounds.width
        let screenHeight = view.bounds.height
        
        // screenPosition is centered at (0,0), convert to absolute coordinates
        let centerX = screenWidth / 2
        let centerY = screenHeight / 2
        
        let absoluteX = centerX + screenPosition.x
        let absoluteY = centerY + screenPosition.y
        
        return CGPoint(x: absoluteX, y: absoluteY)
    }
    
    private func updateGazeCursor(_ position: CGPoint) {
        guard let cursor = gazeCursor else { return }
        
        let screenWidth = view.bounds.width
        let screenHeight = view.bounds.height
        
        // Clamp to screen bounds (accounting for cursor size)
        let cursorRadius: CGFloat = 30
        var targetX = max(cursorRadius, min(screenWidth - cursorRadius, position.x))
        var targetY = max(cursorRadius, min(screenHeight - cursorRadius, position.y))
        
        // Apply exponential moving average smoothing for cursor position
        if let lastPos = lastCursorPosition {
            targetX = CGFloat(cursorSmoothingFactor) * lastPos.x + CGFloat(1.0 - cursorSmoothingFactor) * targetX
            targetY = CGFloat(cursorSmoothingFactor) * lastPos.y + CGFloat(1.0 - cursorSmoothingFactor) * targetY
        }
        lastCursorPosition = CGPoint(x: targetX, y: targetY)
        
        // Adjust animation duration based on smoothing factor
        let baseDuration: TimeInterval = 0.1
        let maxDuration: TimeInterval = 0.3
        let animationDuration = baseDuration + (maxDuration - baseDuration) * Double(cursorSmoothingFactor)
        
        // Animate cursor movement smoothly
        UIView.animate(withDuration: animationDuration, delay: 0, options: [.curveEaseOut, .allowUserInteraction, .beginFromCurrentState], animations: {
            cursor.center = CGPoint(x: targetX, y: targetY)
        })
        
        // Show cursor if it's hidden and calibration is complete
        if cursor.isHidden {
            // Only show if calibration is done
            if eyeTracker.calibrationData?.isCalibrated == true {
                cursor.isHidden = false
                cursor.alpha = 0
                UIView.animate(withDuration: 0.3) {
                    cursor.alpha = 1.0
                }
            }
        }
    }
}

// MARK: - EyeTrackerDelegate

extension DetailViewController: EyeTrackerDelegate {
    func eyeTracker(_ tracker: EyeTracker, didUpdateGazeScreenPosition screenPosition: CGPoint, lookAtPoint: simd_float3) {
        let absolutePosition = convertGazeToAbsolutePosition(screenPosition)
        
        // Update dwell detector
        dwellDetector.updateGazePosition(absolutePosition, in: view)
        
        // Update gaze cursor position
        updateGazeCursor(absolutePosition)
    }
    
    func eyeTracker(_ tracker: EyeTracker, didUpdateGaze screenPosition: SIMD2<Float>, lookAtPoint: simd_float3, rawAngles: SIMD2<Float>) {
        // Legacy method - not used but required by protocol
    }
    
    func eyeTracker(_ tracker: EyeTracker, didDetectBlink isBlinking: Bool) {
        // Blink detection can be used for quick actions if needed
    }
    
    func eyeTrackerDidLoseTracking(_ tracker: EyeTracker) {
        dwellDetector.reset()
        currentDwellingButton = nil
        // Hide cursor when tracking is lost
        gazeCursor?.isHidden = true
        // Reset cursor smoothing
        lastCursorPosition = nil
    }
}

// MARK: - DwellDetectorDelegate

extension DetailViewController: DwellDetectorDelegate {
    func dwellDetector(_ detector: DwellDetector, didStartDwellingOn view: UIView) {
        if let button = view as? UIButton {
            currentDwellingButton = button
            // Add highlight to button
            UIView.animate(withDuration: 0.2) {
                button.alpha = 0.7
                button.transform = CGAffineTransform(scaleX: 1.05, y: 1.05)
            }
        }
    }
    
    func dwellDetector(_ detector: DwellDetector, didUpdateDwellProgress progress: Float, on view: UIView) {
        // Can add progress indicator if needed
    }
    
    func dwellDetector(_ detector: DwellDetector, didCompleteDwellOn view: UIView) {
        // CRITICAL: Ignore dwell completions if this view is not visible
        guard self.viewIfLoaded?.window != nil else {
            Logger.debug("DetailViewController: Ignoring dwell completion - view is not visible")
            return
        }
        
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        
        if let button = view as? UIButton {
            UIView.animate(withDuration: 0.2) {
                button.alpha = 1.0
                button.transform = .identity
            }
            
            if button === backButton {
                backButtonTapped()
            }
            currentDwellingButton = nil
        }
    }
    
    func dwellDetector(_ detector: DwellDetector, didCancelDwellOn view: UIView) {
        if let button = view as? UIButton {
            UIView.animate(withDuration: 0.2) {
                button.alpha = 1.0
                button.transform = .identity
            }
            if currentDwellingButton === button {
                currentDwellingButton = nil
            }
        }
    }
}

// MARK: - ARSCNViewDelegate

extension DetailViewController: ARSCNViewDelegate {
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        guard anchor is ARFaceAnchor else { return }
        faceNode.transform = node.transform
        
        // Show cursor when face tracking starts (if calibrated)
        if eyeTracker.calibrationData?.isCalibrated == true {
            gazeCursor?.isHidden = false
        }
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard let faceAnchor = anchor as? ARFaceAnchor else { return }
        
        faceNode.transform = node.transform
        eyeLNode.simdTransform = faceAnchor.leftEyeTransform
        eyeRNode.simdTransform = faceAnchor.rightEyeTransform
        
        eyeTracker.processFaceAnchor(faceAnchor)
    }
    
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        if let pointOfView = sceneView.pointOfView {
            virtualPhoneNode.transform = pointOfView.transform
        }
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor) {
        eyeTracker.reset()
        dwellDetector.reset()
    }
}

// MARK: - ARSessionDelegate

extension DetailViewController: ARSessionDelegate {
    func session(_ session: ARSession, didFailWithError error: Error) {
        Logger.error("AR session failed: \(error.localizedDescription)")
    }
    
    func sessionWasInterrupted(_ session: ARSession) {
        Logger.info("AR session interrupted")
    }
    
    func sessionInterruptionEnded(_ session: ARSession) {
        let configuration = ARFaceTrackingConfiguration()
        sceneView.session.run(configuration, options: [.resetTracking])
    }
}
