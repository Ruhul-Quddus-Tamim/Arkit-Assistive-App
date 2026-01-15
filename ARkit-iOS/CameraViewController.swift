import UIKit
import ARKit
import SceneKit

class CameraViewController: UIViewController {
    
    private var sceneView: ARSCNView!
    private var statusLabel: UILabel!
    private var connectionStatusLabel: UILabel!
    private var ipAddressTextField: UITextField!
    private var connectButton: UIButton!
    private var autoConnectButton: UIButton!
    private var calibrateButton: UIButton!
    
    // Single gaze cursor
    private var gazeCursor: UIView!
    private var cursorRing: UIView!
    private var gazeDebugLabel: UILabel!
    
    private let eyeTracker = EyeTracker()
    private let networkClient = TrackingDataClient()
    private var isTracking = false
    
    // MARK: - SceneKit Scene Graph for Hit Testing
    
    // Face tracking nodes
    private var faceNode: SCNNode = SCNNode()
    
    // Eye nodes
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
    
    // LookAt target nodes (2 meters away from eyes)
    private var lookAtTargetEyeLNode: SCNNode = SCNNode()
    private var lookAtTargetEyeRNode: SCNNode = SCNNode()
    
    // Virtual phone and screen nodes
    private var virtualPhoneNode: SCNNode = SCNNode()
    
    // Virtual screen node - will be set up with correct size in setupSceneGraph
    private var virtualScreenNode: SCNNode = SCNNode()
    
    // iPhone 17 Pro screen constants
    // Physical screen size in meters (portrait orientation: width < height)
    // iPhone 17 Pro: ~71.8mm x 157mm display
    private let phoneScreenSize = CGSize(width: 0.0718, height: 0.157)
    
    // Screen point size - will be set after view loads
    private var phoneScreenPointSize: CGSize {
        // Use view bounds if available (after viewDidLoad)
        if view.bounds.width > 0 && view.bounds.height > 0 {
            return view.bounds.size
        }
        // Fallback to calculated values for iPhone 17 Pro
        return CGSize(width: 1311, height: 603)
    }
    
    override func loadView() {
        print("CameraViewController: loadView called")
        view = UIView()
        view.backgroundColor = .black
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        print("CameraViewController: viewDidLoad called")
        
        setupUI()
        setupEyeTracking()
        setupNetworkClient()
        print("CameraViewController: Setup complete")
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Update screen size now that view is laid out
        eyeTracker.phoneScreenPointSize = phoneScreenPointSize
        startFaceTracking()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Update screen size when layout changes (e.g., rotation)
        eyeTracker.phoneScreenPointSize = phoneScreenPointSize
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sceneView.session.pause()
    }
    
    private func setupUI() {
        print("CameraViewController: Setting up UI")
        
        // Create AR Scene View
        sceneView = ARSCNView()
        sceneView.translatesAutoresizingMaskIntoConstraints = false
        sceneView.backgroundColor = .black
        view.addSubview(sceneView)
        print("CameraViewController: ARSCNView added")
        
        // Create status label
        statusLabel = UILabel()
        statusLabel.text = "Initializing..."
        statusLabel.textColor = .white
        statusLabel.font = .systemFont(ofSize: 16, weight: .medium)
        statusLabel.textAlignment = .center
        statusLabel.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        statusLabel.layer.cornerRadius = 8
        statusLabel.clipsToBounds = true
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)
        
        // Create connection status label
        connectionStatusLabel = UILabel()
        connectionStatusLabel.text = "Not Connected"
        connectionStatusLabel.textColor = .red
        connectionStatusLabel.font = .systemFont(ofSize: 14)
        connectionStatusLabel.textAlignment = .center
        connectionStatusLabel.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        connectionStatusLabel.layer.cornerRadius = 8
        connectionStatusLabel.clipsToBounds = true
        connectionStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(connectionStatusLabel)
        
        // Create gaze debug label
        gazeDebugLabel = UILabel()
        gazeDebugLabel.text = "Gaze: --"
        gazeDebugLabel.textColor = .cyan
        gazeDebugLabel.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        gazeDebugLabel.textAlignment = .left
        gazeDebugLabel.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        gazeDebugLabel.layer.cornerRadius = 6
        gazeDebugLabel.clipsToBounds = true
        gazeDebugLabel.numberOfLines = 3
        gazeDebugLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(gazeDebugLabel)
        
        // Create single gaze cursor - a large green circle for visibility
        // Use frame-based positioning (NOT Auto Layout) so we can set center directly
        let cursorSize: CGFloat = 60
        gazeCursor = UIView(frame: CGRect(x: 0, y: 0, width: cursorSize, height: cursorSize))
        gazeCursor.translatesAutoresizingMaskIntoConstraints = true // Frame-based positioning
        gazeCursor.isHidden = true
        gazeCursor.backgroundColor = .clear
        view.addSubview(gazeCursor)
        
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
        gazeCursor.addSubview(outerRing)
        
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
        gazeCursor.addSubview(innerDot)
        
        // Store cursorRing reference for animations
        cursorRing = outerRing
        
        // Create IP address text field
        ipAddressTextField = UITextField()
        ipAddressTextField.placeholder = "Enter Mac IP (e.g., 192.168.1.100)"
        ipAddressTextField.keyboardType = .numbersAndPunctuation
        ipAddressTextField.returnKeyType = .done
        ipAddressTextField.borderStyle = .roundedRect
        ipAddressTextField.backgroundColor = .white
        ipAddressTextField.delegate = self
        ipAddressTextField.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(ipAddressTextField)
        
        // Create connect button
        connectButton = UIButton(type: .system)
        connectButton.setTitle("Connect (Manual)", for: .normal)
        connectButton.backgroundColor = .systemBlue
        connectButton.setTitleColor(.white, for: .normal)
        connectButton.layer.cornerRadius = 8
        connectButton.addTarget(self, action: #selector(connectButtonTapped(_:)), for: .touchUpInside)
        connectButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(connectButton)
        
        // Create auto connect button
        autoConnectButton = UIButton(type: .system)
        autoConnectButton.setTitle("Auto Connect", for: .normal)
        autoConnectButton.backgroundColor = .systemGreen
        autoConnectButton.setTitleColor(.white, for: .normal)
        autoConnectButton.layer.cornerRadius = 8
        autoConnectButton.addTarget(self, action: #selector(autoConnectButtonTapped(_:)), for: .touchUpInside)
        autoConnectButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(autoConnectButton)
        
        // Create calibrate button
        calibrateButton = UIButton(type: .system)
        calibrateButton.setTitle("Calibrate Eye Tracking", for: .normal)
        calibrateButton.backgroundColor = .systemOrange
        calibrateButton.setTitleColor(.white, for: .normal)
        calibrateButton.layer.cornerRadius = 8
        calibrateButton.addTarget(self, action: #selector(calibrateButtonTapped(_:)), for: .touchUpInside)
        calibrateButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(calibrateButton)
        
        // Setup constraints
        NSLayoutConstraint.activate([
            sceneView.topAnchor.constraint(equalTo: view.topAnchor),
            sceneView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sceneView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            sceneView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            statusLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            statusLabel.heightAnchor.constraint(equalToConstant: 40),
            
            connectionStatusLabel.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 10),
            connectionStatusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            connectionStatusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            connectionStatusLabel.heightAnchor.constraint(equalToConstant: 30),
            
            gazeDebugLabel.topAnchor.constraint(equalTo: connectionStatusLabel.bottomAnchor, constant: 10),
            gazeDebugLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            gazeDebugLabel.widthAnchor.constraint(equalToConstant: 220),
            gazeDebugLabel.heightAnchor.constraint(equalToConstant: 70),
            
            // Note: gazeCursor uses frame-based positioning, no constraints needed
            
            calibrateButton.bottomAnchor.constraint(equalTo: ipAddressTextField.topAnchor, constant: -20),
            calibrateButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            calibrateButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            calibrateButton.heightAnchor.constraint(equalToConstant: 44),
            
            ipAddressTextField.bottomAnchor.constraint(equalTo: connectButton.topAnchor, constant: -10),
            ipAddressTextField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            ipAddressTextField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            ipAddressTextField.heightAnchor.constraint(equalToConstant: 44),
            
            connectButton.bottomAnchor.constraint(equalTo: autoConnectButton.topAnchor, constant: -10),
            connectButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            connectButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            connectButton.heightAnchor.constraint(equalToConstant: 44),
            
            autoConnectButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            autoConnectButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            autoConnectButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            autoConnectButton.heightAnchor.constraint(equalToConstant: 44)
        ])
        
        print("CameraViewController: UI setup complete")
    }
    
    private func setupEyeTracking() {
        eyeTracker.delegate = self
        
        // TEMPORARY: Clear any bad calibration from previous runs
        // Remove this line after confirming calibration works correctly
        CalibrationData.clear()
        
        // Load saved calibration if available
        let savedCalibration = CalibrationData.load()
        if savedCalibration.isCalibrated {
            eyeTracker.calibrationData = savedCalibration
            print("CameraViewController: Loaded saved calibration")
            updateCalibrationButtonTitle(isCalibrated: true)
        } else {
            print("CameraViewController: No saved calibration - please calibrate")
            updateCalibrationButtonTitle(isCalibrated: false)
        }
        
        // Setup SceneKit scene graph for hit testing
        setupSceneGraph()
        
        // Pass SceneKit nodes and screen constants to EyeTracker
        eyeTracker.eyeLNode = eyeLNode
        eyeTracker.eyeRNode = eyeRNode
        eyeTracker.lookAtTargetEyeLNode = lookAtTargetEyeLNode
        eyeTracker.lookAtTargetEyeRNode = lookAtTargetEyeRNode
        eyeTracker.virtualPhoneNode = virtualPhoneNode
        eyeTracker.phoneScreenSize = phoneScreenSize
        eyeTracker.phoneScreenPointSize = phoneScreenPointSize
        eyeTracker.useHitTesting = true
    }
    
    private func setupSceneGraph() {
        // Setup scene graph hierarchy
        sceneView.scene.rootNode.addChildNode(faceNode)
        sceneView.scene.rootNode.addChildNode(virtualPhoneNode)
        
        // Create virtual screen geometry - MUST match phoneScreenSize for correct coordinate conversion
        // The formula in GazeCalculator divides localX by (phoneScreenSize.width/2)
        // So the plane must be phoneScreenSize dimensions for the math to work
        let screenGeometry = SCNPlane(width: phoneScreenSize.width, height: phoneScreenSize.height)
        screenGeometry.firstMaterial?.isDoubleSided = true
        // Make it visible for debugging (can reduce alpha later)
        screenGeometry.firstMaterial?.diffuse.contents = UIColor.green.withAlphaComponent(0.1)
        // Ensure geometry is hittable
        screenGeometry.firstMaterial?.readsFromDepthBuffer = true
        screenGeometry.firstMaterial?.writesToDepthBuffer = true
        virtualScreenNode.geometry = screenGeometry
        
        // Add virtual screen to virtual phone
        virtualPhoneNode.addChildNode(virtualScreenNode)
        
        // Add eye nodes to face node
        faceNode.addChildNode(eyeLNode)
        faceNode.addChildNode(eyeRNode)
        
        // Add lookAtTarget nodes to eye nodes
        eyeLNode.addChildNode(lookAtTargetEyeLNode)
        eyeRNode.addChildNode(lookAtTargetEyeRNode)
        
        // Set lookAtTarget nodes 2 meters away from eyes
        lookAtTargetEyeLNode.position.z = 2
        lookAtTargetEyeRNode.position.z = 2
        
        print("CameraViewController: Scene graph setup complete")
        print("CameraViewController: Virtual screen size: \(phoneScreenSize.width)x\(phoneScreenSize.height) meters (\(phoneScreenSize.width*100)cm x \(phoneScreenSize.height*100)cm)")
        print("CameraViewController: virtualScreenNode has geometry: \(virtualScreenNode.geometry != nil)")
        print("CameraViewController: virtualScreenNode parent: \(virtualScreenNode.parent?.name ?? "unnamed")")
        print("CameraViewController: virtualPhoneNode children count: \(virtualPhoneNode.childNodes.count)")
    }
    
    private func setupNetworkClient() {
        networkClient.delegate = self
    }
    
    private func startFaceTracking() {
        print("CameraViewController: Starting face tracking")
        
        guard ARFaceTrackingConfiguration.isSupported else {
            print("ERROR: Face tracking not supported on this device")
            showUnsupportedDeviceAlert()
            return
        }
        
        print("CameraViewController: Face tracking is supported")
        sceneView.delegate = self
        sceneView.session.delegate = self
        
        let configuration = ARFaceTrackingConfiguration()
        configuration.maximumNumberOfTrackedFaces = 1
        
        print("CameraViewController: Running AR session")
        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        statusLabel.text = "Face tracking active"
        isTracking = true
        print("CameraViewController: AR session started")
    }
    
    private func showUnsupportedDeviceAlert() {
        let alert = UIAlertController(
            title: "Device Not Supported",
            message: "Face tracking requires iPhone X or later with TrueDepth camera.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
        statusLabel.text = "Device not supported"
    }
    
    @objc func connectButtonTapped(_ sender: UIButton) {
        guard let ipAddress = ipAddressTextField.text, !ipAddress.isEmpty else {
            showAlert(title: "Error", message: "Please enter Mac IP address")
            return
        }
        
        connectionStatusLabel.text = "Connecting..."
        connectionStatusLabel.textColor = .orange
        networkClient.connectToMac(ipAddress: ipAddress)
    }
    
    @objc func autoConnectButtonTapped(_ sender: UIButton) {
        connectionStatusLabel.text = "Searching..."
        connectionStatusLabel.textColor = .orange
        networkClient.startDiscovery()
    }
    
    @objc func calibrateButtonTapped(_ sender: UIButton) {
        // Clear any existing calibration before starting fresh
        CalibrationData.clear()
        eyeTracker.calibrationData = nil
        
        // Pause AR session before calibration
        sceneView.session.pause()
        
        // Present calibration view controller
        let calibrationVC = CalibrationViewController()
        calibrationVC.delegate = self
        calibrationVC.modalPresentationStyle = .fullScreen
        present(calibrationVC, animated: true)
    }
    
    /// Update cursor position on screen using screen coordinates centered at (0,0) like prototype
    private func updateCursorScreenPosition(_ screenPosition: CGPoint) {
        let screenWidth = view.bounds.width
        let screenHeight = view.bounds.height
        
        print("CameraViewController: updateCursorScreenPosition - screenSize: (\(screenWidth), \(screenHeight)), input: (\(screenPosition.x), \(screenPosition.y))")
        
        // screenPosition is in screen points, centered at (0,0) like prototype
        // Convert to absolute screen coordinates: center + offset
        // Prototype uses: CGAffineTransform(translationX: x, y: y) which is relative to center
        let centerX = screenWidth / 2
        let centerY = screenHeight / 2
        
        let absoluteX = centerX + screenPosition.x
        let absoluteY = centerY + screenPosition.y
        
        // Clamp to screen bounds
        let clampedX = max(25, min(screenWidth - 25, absoluteX))
        let clampedY = max(25, min(screenHeight - 25, absoluteY))
        
        print("CameraViewController: Cursor center will be: (\(clampedX), \(clampedY))")
        
        // Animate cursor movement smoothly - longer duration for stability
        UIView.animate(withDuration: 0.15, delay: 0, options: [.curveEaseOut, .allowUserInteraction, .beginFromCurrentState], animations: {
            self.gazeCursor.center = CGPoint(x: clampedX, y: clampedY)
        })
        
        gazeCursor.isHidden = false
        view.bringSubviewToFront(gazeCursor) // Make sure cursor is above all other views
        print("CameraViewController: Cursor is now visible at center: (\(self.gazeCursor.center.x), \(self.gazeCursor.center.y))")
    }
    
    /// Update cursor position on screen (legacy method for normalized coordinates)
    private func updateCursor(screenPosition: SIMD2<Float>) {
        let screenWidth = view.bounds.width
        let screenHeight = view.bounds.height
        
        // Convert from normalized (-1 to 1) to screen coordinates
        // screenPosition.x: -1 (left) to 1 (right)
        // screenPosition.y: -1 (down) to 1 (up)
        let normalizedX = (screenPosition.x + 1.0) / 2.0 // 0 to 1
        let normalizedY = (screenPosition.y + 1.0) / 2.0 // 0 to 1
        
        let x = CGFloat(normalizedX) * screenWidth
        let y = CGFloat(1.0 - normalizedY) * screenHeight // Flip Y for screen coordinates
        
        // Clamp to screen bounds
        let clampedX = max(25, min(screenWidth - 25, x))
        let clampedY = max(25, min(screenHeight - 25, y))
        
        // Animate cursor movement smoothly - longer duration for stability
        UIView.animate(withDuration: 0.15, delay: 0, options: [.curveEaseOut, .allowUserInteraction, .beginFromCurrentState], animations: {
            self.gazeCursor.center = CGPoint(x: clampedX, y: clampedY)
        })
        
        gazeCursor.isHidden = false
    }
    
    /// Visual feedback when blink is detected
    private func showBlinkFeedback() {
        // Pulse animation on cursor
        UIView.animate(withDuration: 0.1, animations: {
            self.cursorRing.transform = CGAffineTransform(scaleX: 1.5, y: 1.5)
            self.cursorRing.layer.borderColor = UIColor.systemYellow.cgColor
        }) { _ in
            UIView.animate(withDuration: 0.1) {
                self.cursorRing.transform = .identity
                self.cursorRing.layer.borderColor = UIColor.white.cgColor
            }
        }
    }
    
    /// Update calibration button title based on calibration status
    private func updateCalibrationButtonTitle(isCalibrated: Bool) {
        if isCalibrated {
            calibrateButton.setTitle("Recalibrate Eye Tracking ✓", for: .normal)
            calibrateButton.backgroundColor = .systemTeal
        } else {
            calibrateButton.setTitle("Calibrate Eye Tracking", for: .normal)
            calibrateButton.backgroundColor = .systemOrange
        }
    }
}

// MARK: - CalibrationViewControllerDelegate
extension CameraViewController: CalibrationViewControllerDelegate {
    
    func calibrationDidComplete(_ calibration: CalibrationData) {
        // Apply calibration to eye tracker
        eyeTracker.calibrationData = calibration
        updateCalibrationButtonTitle(isCalibrated: true)
        
        // Dismiss calibration view and restart AR session
        dismiss(animated: true) {
            self.startFaceTracking()
            self.statusLabel.text = "Calibration complete!"
        }
    }
    
    func calibrationDidCancel() {
        // Dismiss calibration view and restart AR session
        dismiss(animated: true) {
            self.startFaceTracking()
        }
    }
}

// MARK: - ARSCNViewDelegate
extension CameraViewController: ARSCNViewDelegate {
    
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        guard anchor is ARFaceAnchor else { return }
        print("Face detected!")
        
        // Update face node transform
        faceNode.transform = node.transform
        
        DispatchQueue.main.async {
            self.statusLabel.text = "Face detected - Tracking"
        }
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard let faceAnchor = anchor as? ARFaceAnchor else { return }
        
        // Update face node transform
        faceNode.transform = node.transform
        
        // Update eye node transforms from face anchor
        eyeLNode.simdTransform = faceAnchor.leftEyeTransform
        eyeRNode.simdTransform = faceAnchor.rightEyeTransform
        
        // Process face anchor with hit testing eye tracking
        eyeTracker.processFaceAnchor(faceAnchor)
    }
    
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        // Update virtual phone node to match camera's point of view
        // This keeps the virtual screen aligned with the camera
        if let pointOfView = sceneView.pointOfView {
            virtualPhoneNode.transform = pointOfView.transform
        }
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor) {
        print("Face lost")
        DispatchQueue.main.async {
            self.statusLabel.text = "Face lost - Waiting..."
            self.gazeDebugLabel.text = "Gaze: --"
            self.gazeCursor.isHidden = true
            self.eyeTracker.reset()
        }
    }
}

// MARK: - ARSessionDelegate
extension CameraViewController: ARSessionDelegate {
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        print("ARKit session failed: \(error.localizedDescription)")
        DispatchQueue.main.async {
            self.statusLabel.text = "Session error"
        }
    }
    
    func sessionWasInterrupted(_ session: ARSession) {
        print("ARKit session interrupted")
        DispatchQueue.main.async {
            self.statusLabel.text = "Session interrupted"
        }
    }
    
    func sessionInterruptionEnded(_ session: ARSession) {
        print("ARKit session resumed")
        DispatchQueue.main.async {
            self.statusLabel.text = "Session resumed"
        }
        let configuration = ARFaceTrackingConfiguration()
        sceneView.session.run(configuration, options: [.resetTracking])
    }
}

// MARK: - EyeTrackerDelegate
extension CameraViewController: EyeTrackerDelegate {
    
    /// New method: screen coordinates centered at (0,0) like prototype
    func eyeTracker(_ tracker: EyeTracker, didUpdateGazeScreenPosition screenPosition: CGPoint, lookAtPoint: simd_float3) {
        print("CameraViewController: Delegate called with screenPosition: (\(screenPosition.x), \(screenPosition.y))")
        DispatchQueue.main.async {
            // Update cursor position using screen coordinates (centered at 0,0)
            self.updateCursorScreenPosition(screenPosition)
            
            // Update debug label with screen coordinates
            self.gazeDebugLabel.text = String(format: " Screen: X:%.1f Y:%.1f\n LookAt: %.2f,%.2f,%.2f",
                                              screenPosition.x, screenPosition.y,
                                              lookAtPoint.x, lookAtPoint.y, lookAtPoint.z)
        }
        
        // TODO: Send gaze data to Mac when connected
        // networkClient.sendGazeData(...)
    }
    
    /// Legacy method: normalized coordinates (kept for backward compatibility)
    func eyeTracker(_ tracker: EyeTracker, didUpdateGaze screenPosition: SIMD2<Float>, lookAtPoint: simd_float3, rawAngles: SIMD2<Float>) {
        DispatchQueue.main.async {
            // Update cursor position
            self.updateCursor(screenPosition: screenPosition)
            
            // Update debug label with more info
            // rawAngles are in radians: ~0.5 rad = 30 degrees
            self.gazeDebugLabel.text = String(format: " Screen: X:%.2f Y:%.2f\n Angles: H:%.2f V:%.2f\n LookAt: %.2f,%.2f",
                                              screenPosition.x, screenPosition.y,
                                              rawAngles.x, rawAngles.y,
                                              lookAtPoint.x, lookAtPoint.y)
        }
        
        // TODO: Send gaze data to Mac when connected
        // networkClient.sendGazeData(...)
    }
    
    func eyeTracker(_ tracker: EyeTracker, didDetectBlink isBlinking: Bool) {
        if isBlinking {
            print("Blink detected!")
            DispatchQueue.main.async {
                self.showBlinkFeedback()
            }
        }
    }
    
    func eyeTrackerDidLoseTracking(_ tracker: EyeTracker) {
        DispatchQueue.main.async {
            self.gazeCursor.isHidden = true
            self.gazeDebugLabel.text = "Gaze: Lost"
        }
    }
}

// MARK: - TrackingDataClientDelegate
extension CameraViewController: TrackingDataClientDelegate {
    
    func clientDidConnect(_ client: TrackingDataClient) {
        DispatchQueue.main.async {
            self.connectionStatusLabel.text = "Connected"
            self.connectionStatusLabel.textColor = .green
        }
    }
    
    func clientDidDisconnect(_ client: TrackingDataClient) {
        DispatchQueue.main.async {
            self.connectionStatusLabel.text = "Disconnected"
            self.connectionStatusLabel.textColor = .red
        }
    }
    
    func client(_ client: TrackingDataClient, didEncounterError error: Error) {
        DispatchQueue.main.async {
            self.connectionStatusLabel.text = "Error: \(error.localizedDescription)"
            self.connectionStatusLabel.textColor = .red
        }
    }
}

// MARK: - UITextFieldDelegate
extension CameraViewController: UITextFieldDelegate {
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
    
    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
