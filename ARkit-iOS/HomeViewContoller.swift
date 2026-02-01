import UIKit
import ARKit
import SceneKit

class HomeViewController: UIViewController {
    
    // MARK: - UI Components
    
    private var linkUserButton: UIButton!
    private var iconCollectionView: UICollectionView!
    private var bottomNavContainer: UIView!
    private var backButton: UIButton!
    private var upButton: UIButton!
    private var downButton: UIButton!
    private var gazeCursor: UIView?
    
    // MARK: - Eye Tracking
    
    private var sceneView: ARSCNView!
    private let eyeTracker = EyeTracker()
    private let dwellDetector = DwellDetector()
    
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
    private var currentDwellingCell: IconCollectionViewCell?
    private var currentDwellingButton: UIButton?
    
    // Blink detection
    private var lastBlinkTime: Date?
    private let blinkCooldown: TimeInterval = 0.5 // Prevent double-triggers
    
    // Cursor smoothing
    private var cursorSmoothingFactor: Float = 0.7 // 0.0 = no smoothing, 1.0 = maximum smoothing
    private var lastCursorPosition: CGPoint?
    
    // MARK: - Data
    
    private let icons = MenuIcon.allIcons
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = createBackgroundPattern()
        
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
        startFaceTracking()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sceneView.session.pause()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        eyeTracker.phoneScreenPointSize = phoneScreenPointSize
    }
    
    // MARK: - Setup
    
    private func createBackgroundPattern() -> UIColor {
        // Create subtle leaf pattern background
        // For now, use a light green gradient as placeholder
        // Can be replaced with actual pattern image later
        return UIColor(red: 0.95, green: 0.98, blue: 0.95, alpha: 1.0)
    }
    
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
        // Link User Button
        linkUserButton = UIButton(type: .system)
        linkUserButton.setTitle("Link User", for: .normal)
        linkUserButton.setTitleColor(.white, for: .normal)
        linkUserButton.titleLabel?.font = .systemFont(ofSize: 20, weight: .semibold)
        linkUserButton.backgroundColor = UIColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 1.0) // System blue
        linkUserButton.layer.cornerRadius = 12
        linkUserButton.tag = 100 // Mark as selectable for dwell detection
        
        // Add eye icon
        let eyeIcon = UIImage(systemName: "eye.fill")
        linkUserButton.setImage(eyeIcon, for: .normal)
        linkUserButton.tintColor = .white
        linkUserButton.imageEdgeInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 10)
        linkUserButton.titleEdgeInsets = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 0)
        
        linkUserButton.addTarget(self, action: #selector(linkUserButtonTapped), for: .touchUpInside)
        linkUserButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(linkUserButton)
        
        // Icon Collection View
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 20
        layout.minimumLineSpacing = 20
        layout.sectionInset = UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        
        iconCollectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        iconCollectionView.backgroundColor = .clear
        iconCollectionView.delegate = self
        iconCollectionView.dataSource = self
        iconCollectionView.register(IconCollectionViewCell.self, forCellWithReuseIdentifier: IconCollectionViewCell.identifier)
        iconCollectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(iconCollectionView)
        
        // Bottom Navigation Container
        bottomNavContainer = UIView()
        bottomNavContainer.backgroundColor = .clear
        bottomNavContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bottomNavContainer)
        
        // Back Button
        backButton = createNavButton(iconName: "arrow.left", color: .white, action: #selector(backButtonTapped))
        backButton.tag = 100
        bottomNavContainer.addSubview(backButton)
        
        // Up Button
        upButton = createNavButton(iconName: "chevron.up", color: .gray, action: #selector(upButtonTapped))
        upButton.tag = 100
        bottomNavContainer.addSubview(upButton)
        
        // Down Button
        downButton = createNavButton(iconName: "chevron.down", color: .red, action: #selector(downButtonTapped))
        downButton.tag = 100
        bottomNavContainer.addSubview(downButton)
        
        // Constraints
        NSLayoutConstraint.activate([
            linkUserButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            linkUserButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            linkUserButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            linkUserButton.heightAnchor.constraint(equalToConstant: 60),
            
            iconCollectionView.topAnchor.constraint(equalTo: linkUserButton.bottomAnchor, constant: 30),
            iconCollectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            iconCollectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            iconCollectionView.bottomAnchor.constraint(equalTo: bottomNavContainer.topAnchor, constant: -20),
            
            bottomNavContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            bottomNavContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            bottomNavContainer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            bottomNavContainer.heightAnchor.constraint(equalToConstant: 60),
            
            backButton.leadingAnchor.constraint(equalTo: bottomNavContainer.leadingAnchor),
            backButton.centerYAnchor.constraint(equalTo: bottomNavContainer.centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 50),
            backButton.heightAnchor.constraint(equalToConstant: 50),
            
            upButton.centerXAnchor.constraint(equalTo: bottomNavContainer.centerXAnchor),
            upButton.centerYAnchor.constraint(equalTo: bottomNavContainer.centerYAnchor),
            upButton.widthAnchor.constraint(equalToConstant: 50),
            upButton.heightAnchor.constraint(equalToConstant: 50),
            
            downButton.trailingAnchor.constraint(equalTo: bottomNavContainer.trailingAnchor),
            downButton.centerYAnchor.constraint(equalTo: bottomNavContainer.centerYAnchor),
            downButton.widthAnchor.constraint(equalToConstant: 50),
            downButton.heightAnchor.constraint(equalToConstant: 50)
        ])
    }
    
    private func createNavButton(iconName: String, color: UIColor, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 24, weight: .medium)
        button.setImage(UIImage(systemName: iconName, withConfiguration: config), for: .normal)
        button.tintColor = color
        button.backgroundColor = color.withAlphaComponent(0.1)
        button.layer.cornerRadius = 10
        button.addTarget(self, action: action, for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }
    
    private func setupGazeCursor() {
        // Create gaze cursor - a large green circle for visibility
        // Use frame-based positioning (NOT Auto Layout) so we can set center directly
        let cursorSize: CGFloat = 60
        gazeCursor = UIView(frame: CGRect(x: 0, y: 0, width: cursorSize, height: cursorSize))
        gazeCursor?.translatesAutoresizingMaskIntoConstraints = true // Frame-based positioning
        gazeCursor?.isHidden = true
        gazeCursor?.backgroundColor = .clear
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
        dwellDetector.setDwellThreshold(1.5) // 1.5 seconds
    }
    
    private func startFaceTracking() {
        guard ARFaceTrackingConfiguration.isSupported else {
            print("Face tracking not supported")
            return
        }
        
        let configuration = ARFaceTrackingConfiguration()
        configuration.maximumNumberOfTrackedFaces = 1
        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }
    
    // MARK: - Actions
    
    @objc private func linkUserButtonTapped() {
        // Hide cursor when presenting calibration
        gazeCursor?.isHidden = true
        
        let calibrationVC = CalibrationViewController()
        calibrationVC.delegate = self
        present(calibrationVC, animated: true)
    }
    
    @objc private func backButtonTapped() {
        // Back/exit action
        if let navController = navigationController, navController.viewControllers.count > 1 {
            navController.popViewController(animated: true)
        }
    }
    
    @objc private func upButtonTapped() {
        // Scroll up or expand action
        print("Up button tapped")
    }
    
    @objc private func downButtonTapped() {
        // Scroll down or collapse action
        print("Down button tapped")
    }
    
    private func navigateToDetail(for icon: MenuIcon) {
        let detailVC = DetailViewController()
        detailVC.configure(with: icon)
        navigationController?.pushViewController(detailVC, animated: true)
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
        
        // Adjust animation duration based on smoothing factor (higher smoothing = longer duration)
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
    
    /// Set cursor smoothing factor (0.0 = no smoothing, 1.0 = maximum smoothing)
    /// Higher values reduce jitter but increase latency
    func setCursorSmoothingFactor(_ factor: Float) {
        cursorSmoothingFactor = max(0.0, min(1.0, factor))
    }
    
    private func handleBlinkOnView(_ view: UIView) {
        // Check cooldown
        if let lastBlink = lastBlinkTime, Date().timeIntervalSince(lastBlink) < blinkCooldown {
            return
        }
        
        lastBlinkTime = Date()
        
        // Trigger action based on view type
        if view === linkUserButton {
            linkUserButtonTapped()
        } else if let cell = view as? IconCollectionViewCell,
                  let indexPath = iconCollectionView.indexPath(for: cell) {
            let icon = icons[indexPath.item]
            navigateToDetail(for: icon)
        } else if view === backButton {
            backButtonTapped()
        } else if view === upButton {
            upButtonTapped()
        } else if view === downButton {
            downButtonTapped()
        }
    }
}

// MARK: - UICollectionViewDataSource

extension HomeViewController: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return icons.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: IconCollectionViewCell.identifier, for: indexPath) as! IconCollectionViewCell
        cell.configure(with: icons[indexPath.item])
        return cell
    }
}

// MARK: - UICollectionViewDelegateFlowLayout

extension HomeViewController: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let spacing: CGFloat = 20
        let columns: CGFloat = 2
        let totalSpacing = spacing * (columns + 1)
        let width = (collectionView.bounds.width - totalSpacing) / columns
        return CGSize(width: width, height: width) // Square cells
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let icon = icons[indexPath.item]
        navigateToDetail(for: icon)
    }
}

// MARK: - EyeTrackerDelegate

extension HomeViewController: EyeTrackerDelegate {
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
        if isBlinking {
            // Find which view is currently being gazed at
            if let dwellingView = currentDwellingCell ?? currentDwellingButton {
                handleBlinkOnView(dwellingView)
            }
        }
    }
    
    func eyeTrackerDidLoseTracking(_ tracker: EyeTracker) {
        dwellDetector.reset()
        currentDwellingCell = nil
        currentDwellingButton = nil
        // Hide cursor when tracking is lost
        gazeCursor?.isHidden = true
        // Reset cursor smoothing
        lastCursorPosition = nil
    }
}

// MARK: - DwellDetectorDelegate

extension HomeViewController: DwellDetectorDelegate {
    func dwellDetector(_ detector: DwellDetector, didStartDwellingOn view: UIView) {
        if let cell = view as? IconCollectionViewCell {
            currentDwellingCell = cell
            cell.showHighlight()
            cell.showProgress()
        } else if let button = view as? UIButton {
            currentDwellingButton = button
            // Add highlight to button
            UIView.animate(withDuration: 0.2) {
                button.alpha = 0.7
            }
        }
    }
    
    func dwellDetector(_ detector: DwellDetector, didUpdateDwellProgress progress: Float, on view: UIView) {
        if let cell = view as? IconCollectionViewCell {
            cell.updateProgress(progress)
        }
    }
    
    func dwellDetector(_ detector: DwellDetector, didCompleteDwellOn view: UIView) {
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        
        if let cell = view as? IconCollectionViewCell {
            cell.animatePress()
            cell.hideProgress()
            cell.removeHighlight()
            
            if let indexPath = iconCollectionView.indexPath(for: cell) {
                let icon = icons[indexPath.item]
                navigateToDetail(for: icon)
            }
            currentDwellingCell = nil
        } else if let button = view as? UIButton {
            UIView.animate(withDuration: 0.2) {
                button.alpha = 1.0
            }
            
            if button === linkUserButton {
                linkUserButtonTapped()
            } else if button === backButton {
                backButtonTapped()
            } else if button === upButton {
                upButtonTapped()
            } else if button === downButton {
                downButtonTapped()
            }
            currentDwellingButton = nil
        }
    }
    
    func dwellDetector(_ detector: DwellDetector, didCancelDwellOn view: UIView) {
        if let cell = view as? IconCollectionViewCell {
            cell.hideProgress()
            cell.removeHighlight()
            if currentDwellingCell === cell {
                currentDwellingCell = nil
            }
        } else if let button = view as? UIButton {
            UIView.animate(withDuration: 0.2) {
                button.alpha = 1.0
            }
            if currentDwellingButton === button {
                currentDwellingButton = nil
            }
        }
    }
}

// MARK: - ARSCNViewDelegate

extension HomeViewController: ARSCNViewDelegate {
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

extension HomeViewController: ARSessionDelegate {
    func session(_ session: ARSession, didFailWithError error: Error) {
        print("AR session failed: \(error.localizedDescription)")
    }
    
    func sessionWasInterrupted(_ session: ARSession) {
        print("AR session interrupted")
    }
    
    func sessionInterruptionEnded(_ session: ARSession) {
        let configuration = ARFaceTrackingConfiguration()
        sceneView.session.run(configuration, options: [.resetTracking])
    }
}

// MARK: - CalibrationViewControllerDelegate

extension HomeViewController: CalibrationViewControllerDelegate {
    func calibrationDidComplete(_ calibration: CalibrationData) {
        eyeTracker.calibrationData = calibration
        print("Calibration completed and applied")
        
        // Show cursor after calibration completes
        // Use a small delay to ensure view is visible after dismissal animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.gazeCursor?.isHidden = false
            self.gazeCursor?.alpha = 0
            UIView.animate(withDuration: 0.5) {
                self.gazeCursor?.alpha = 1.0
            }
        }
    }
    
    func calibrationDidCancel() {
        print("Calibration cancelled")
        // Don't show cursor if calibration was cancelled
    }
}
