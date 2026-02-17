import UIKit
import ARKit
import SceneKit

class BodyViewController: UIViewController {
    
    // MARK: - UI Components
    
    private var backButton: UIButton!
    private var buttonsContainer: UIView!
    private var bodyButtons: [UIButton] = []      // Nose, Leg, Back, Arm, Skin, Eyelash
    private var sensationButtons: [UIButton] = []  // Itchy, Pain
    private var exitButton: UIButton!
    
    // Button configuration
    private struct BodyButton {
        let title: String
        let iconName: String
        let speechText: String
    }
    
    private let bodyButtonConfigs: [BodyButton] = [
        BodyButton(title: "Nose", iconName: "face.smiling", speechText: "Nose"),
        BodyButton(title: "Leg", iconName: "figure.walk", speechText: "Leg"),
        BodyButton(title: "Back", iconName: "figure.stand", speechText: "Back"),
        BodyButton(title: "Arm", iconName: "hand.raised", speechText: "Arm"),
        BodyButton(title: "Skin", iconName: "circle.grid.2x2", speechText: "Skin"),
        BodyButton(title: "Eyelash", iconName: "eye", speechText: "Eyelash")
    ]
    
    private let sensationConfigs: [(title: String, speechText: String)] = [
        ("Itchy", "Itchy"),
        ("Pain", "Pain")
    ]
    
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
    
    // Navigation guard flag
    private var isNavigating = false
    
    // Cursor smoothing
    private var cursorSmoothingFactor: Float = 0.8
    private var lastCursorPosition: CGPoint?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Light cream background matching Communication/Feeling (with subtle leaf feel)
        view.backgroundColor = UIColor(red: 0.95, green: 0.98, blue: 0.95, alpha: 1.0)
        
        setupARScene()
        setupUI()
        setupGazeCursor()
        setupEyeTracking()
        setupDwellDetector()
        
        // Load calibration if available
        let calibration = CalibrationData.load()
        if calibration.isCalibrated {
            eyeTracker.calibrationData = calibration
            gazeCursor?.isHidden = false
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        isNavigating = false
        startFaceTracking()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        isNavigating = false
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        Logger.debug("=== BodyViewController viewWillDisappear - STOPPING eye tracking and dwell ===")
        sceneView.session.pause()
        dwellDetector.cancelDwell()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        eyeTracker.phoneScreenPointSize = phoneScreenPointSize
        layoutButtons()
    }
    
    // MARK: - Setup
    
    private func setupARScene() {
        sceneView = ARSCNView()
        sceneView.isHidden = true
        sceneView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sceneView)
        
        NSLayoutConstraint.activate([
            sceneView.topAnchor.constraint(equalTo: view.topAnchor),
            sceneView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sceneView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            sceneView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
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
        // Back Button (hidden by default - Exit serves as back on this screen)
        backButton = UIButton(type: .system)
        backButton.setTitle("← Back", for: .normal)
        backButton.setTitleColor(.white, for: .normal)
        backButton.titleLabel?.font = .systemFont(ofSize: 20, weight: .semibold)
        backButton.backgroundColor = UIColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 1.0)
        backButton.layer.cornerRadius = 12
        backButton.tag = 100
        backButton.accessibilityIdentifier = "back"
        backButton.addTarget(self, action: #selector(backButtonTapped), for: .touchUpInside)
        backButton.translatesAutoresizingMaskIntoConstraints = false
        backButton.isHidden = true
        view.addSubview(backButton)
        
        // Buttons container
        buttonsContainer = UIView()
        buttonsContainer.backgroundColor = .clear
        buttonsContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(buttonsContainer)
        
        // Yellow color for body parts (vibrant yellow from image)
        let bodyYellow = UIColor(red: 1.0, green: 0.85, blue: 0.2, alpha: 1.0)
        
        // Create body part buttons (3x2 grid)
        for config in bodyButtonConfigs {
            let button = createBodyButton(title: config.title, iconName: config.iconName, speechText: config.speechText, backgroundColor: bodyYellow)
            buttonsContainer.addSubview(button)
            bodyButtons.append(button)
        }
        
        // Orange-tan for sensation buttons
        let sensationOrange = UIColor(red: 0.93, green: 0.72, blue: 0.48, alpha: 1.0)
        
        // Create sensation buttons
        for config in sensationConfigs {
            let button = createSensationButton(title: config.title, speechText: config.speechText, backgroundColor: sensationOrange)
            buttonsContainer.addSubview(button)
            sensationButtons.append(button)
        }
        
        // Exit button (bottom left)
        exitButton = UIButton(type: .system)
        exitButton.backgroundColor = .white
        exitButton.layer.cornerRadius = 12
        exitButton.tag = 100
        exitButton.clipsToBounds = true
        
        let exitContainerView = UIView()
        exitContainerView.backgroundColor = .clear
        exitContainerView.isUserInteractionEnabled = false
        
        let exitIconImageView = UIImageView()
        let exitIconConfig = UIImage.SymbolConfiguration(pointSize: 40, weight: .medium)
        exitIconImageView.image = UIImage(systemName: "arrow.left.square", withConfiguration: exitIconConfig)
        exitIconImageView.tintColor = .black
        exitIconImageView.contentMode = .scaleAspectFit
        exitIconImageView.isUserInteractionEnabled = false
        exitIconImageView.translatesAutoresizingMaskIntoConstraints = false
        exitContainerView.addSubview(exitIconImageView)
        
        let exitTitleLabel = UILabel()
        exitTitleLabel.text = "Exit"
        exitTitleLabel.textColor = .black
        exitTitleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        exitTitleLabel.textAlignment = .center
        exitTitleLabel.isUserInteractionEnabled = false
        exitTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        exitContainerView.addSubview(exitTitleLabel)
        
        NSLayoutConstraint.activate([
            exitIconImageView.topAnchor.constraint(equalTo: exitContainerView.topAnchor),
            exitIconImageView.centerXAnchor.constraint(equalTo: exitContainerView.centerXAnchor),
            exitIconImageView.widthAnchor.constraint(equalToConstant: 50),
            exitIconImageView.heightAnchor.constraint(equalToConstant: 50),
            
            exitTitleLabel.topAnchor.constraint(equalTo: exitIconImageView.bottomAnchor, constant: 8),
            exitTitleLabel.centerXAnchor.constraint(equalTo: exitContainerView.centerXAnchor),
            exitTitleLabel.bottomAnchor.constraint(equalTo: exitContainerView.bottomAnchor)
        ])
        
        exitContainerView.translatesAutoresizingMaskIntoConstraints = false
        exitButton.addSubview(exitContainerView)
        
        NSLayoutConstraint.activate([
            exitContainerView.centerXAnchor.constraint(equalTo: exitButton.centerXAnchor),
            exitContainerView.centerYAnchor.constraint(equalTo: exitButton.centerYAnchor),
            exitContainerView.leadingAnchor.constraint(greaterThanOrEqualTo: exitButton.leadingAnchor, constant: 10),
            exitContainerView.trailingAnchor.constraint(lessThanOrEqualTo: exitButton.trailingAnchor, constant: -10)
        ])
        
        exitButton.accessibilityIdentifier = "exit"
        exitButton.addTarget(self, action: #selector(exitButtonTapped), for: .touchUpInside)
        exitButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(exitButton)
        
        NSLayoutConstraint.activate([
            buttonsContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            buttonsContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            buttonsContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            buttonsContainer.bottomAnchor.constraint(equalTo: exitButton.topAnchor, constant: -20),
            
            exitButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            exitButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            exitButton.widthAnchor.constraint(equalToConstant: 120),
            exitButton.heightAnchor.constraint(equalToConstant: 100)
        ])
    }
    
    private func createBodyButton(title: String, iconName: String, speechText: String, backgroundColor: UIColor) -> UIButton {
        let button = UIButton(type: .system)
        button.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        button.backgroundColor = backgroundColor
        button.layer.cornerRadius = 12
        button.tag = 100
        button.clipsToBounds = true
        
        let containerView = UIView()
        containerView.backgroundColor = .clear
        containerView.isUserInteractionEnabled = false
        containerView.autoresizingMask = [.flexibleLeftMargin, .flexibleRightMargin, .flexibleTopMargin, .flexibleBottomMargin]
        button.addSubview(containerView)
        
        let iconImageView = UIImageView()
        let iconConfig = UIImage.SymbolConfiguration(pointSize: 36, weight: .medium)
        iconImageView.image = UIImage(systemName: iconName, withConfiguration: iconConfig)
        iconImageView.tintColor = .black
        iconImageView.contentMode = .scaleAspectFit
        iconImageView.isUserInteractionEnabled = false
        iconImageView.frame = CGRect(x: 0, y: 0, width: 50, height: 50)
        containerView.addSubview(iconImageView)
        
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.textColor = .black
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textAlignment = .center
        titleLabel.isUserInteractionEnabled = false
        titleLabel.sizeToFit()
        titleLabel.frame = CGRect(x: 0, y: 54, width: max(titleLabel.frame.width, 50), height: titleLabel.frame.height)
        containerView.addSubview(titleLabel)
        
        let containerWidth = max(50, titleLabel.frame.width)
        let containerHeight: CGFloat = 54 + titleLabel.frame.height
        containerView.frame = CGRect(x: 0, y: 0, width: containerWidth, height: containerHeight)
        iconImageView.center.x = containerWidth / 2
        titleLabel.center.x = containerWidth / 2
        
        containerView.center = CGPoint(x: button.bounds.midX, y: button.bounds.midY)
        
        button.accessibilityIdentifier = "speak:\(speechText)"
        button.addTarget(self, action: #selector(bodyButtonTapped(_:)), for: .touchUpInside)
        
        return button
    }
    
    private func createSensationButton(title: String, speechText: String, backgroundColor: UIColor) -> UIButton {
        let button = UIButton(type: .system)
        button.frame = CGRect(x: 0, y: 0, width: 120, height: 50)
        button.backgroundColor = backgroundColor
        button.layer.cornerRadius = 12
        button.tag = 100
        button.clipsToBounds = true
        
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.textColor = .black
        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        titleLabel.textAlignment = .center
        titleLabel.isUserInteractionEnabled = false
        titleLabel.sizeToFit()
        button.addSubview(titleLabel)
        titleLabel.center = CGPoint(x: button.bounds.midX, y: button.bounds.midY)
        
        button.accessibilityIdentifier = "speak:\(speechText)"
        button.addTarget(self, action: #selector(sensationButtonTapped(_:)), for: .touchUpInside)
        
        return button
    }
    
    private func layoutButtons() {
        guard buttonsContainer.bounds.width > 0 && buttonsContainer.bounds.height > 0 else { return }
        
        let spacing: CGFloat = 16
        let containerWidth = buttonsContainer.bounds.width
        let containerHeight = buttonsContainer.bounds.height
        
        // Layout: 3 rows x 2 columns for body parts, then Exit left + sensations right
        // Body grid: 3x2
        let bodyCols: CGFloat = 2
        let bodyRows: CGFloat = 3
        let bodyGridHeight = containerHeight * 0.65
        let bodyButtonWidth = (containerWidth - spacing) / bodyCols
        let bodyButtonHeight = (bodyGridHeight - spacing * (bodyRows - 1)) / bodyRows
        
        for (index, button) in bodyButtons.enumerated() {
            let row = CGFloat(index / Int(bodyCols))
            let col = CGFloat(index % Int(bodyCols))
            button.frame = CGRect(
                x: col * (bodyButtonWidth + spacing),
                y: row * (bodyButtonHeight + spacing),
                width: bodyButtonWidth,
                height: bodyButtonHeight
            )
            if let containerView = button.subviews.first {
                containerView.center = CGPoint(x: button.bounds.midX, y: button.bounds.midY)
            }
        }
        
        // Sensation buttons + exit area: bottom section
        let bottomY = bodyGridHeight + spacing
        let bottomHeight = containerHeight - bodyGridHeight - spacing
        let rightColWidth = bodyButtonWidth
        let sensationButtonHeight = (bottomHeight - spacing) / 2
        
        for (index, button) in sensationButtons.enumerated() {
            button.frame = CGRect(
                x: bodyButtonWidth + spacing,
                y: bottomY + CGFloat(index) * (sensationButtonHeight + spacing),
                width: rightColWidth,
                height: sensationButtonHeight
            )
            if let label = button.subviews.first as? UILabel {
                label.center = CGPoint(x: button.bounds.midX, y: button.bounds.midY)
            }
        }
    }
    
    private func setupGazeCursor() {
        let cursorSize: CGFloat = 60
        gazeCursor = UIView(frame: CGRect(x: 0, y: 0, width: cursorSize, height: cursorSize))
        gazeCursor?.translatesAutoresizingMaskIntoConstraints = true
        gazeCursor?.isHidden = true
        gazeCursor?.backgroundColor = .clear
        gazeCursor?.isUserInteractionEnabled = false
        view.addSubview(gazeCursor!)
        
        let outerRing = UIView(frame: CGRect(x: 0, y: 0, width: cursorSize, height: cursorSize))
        outerRing.backgroundColor = .clear
        outerRing.layer.borderColor = UIColor.systemBlue.cgColor
        outerRing.layer.borderWidth = 4
        outerRing.layer.cornerRadius = cursorSize / 2
        outerRing.layer.shadowColor = UIColor.blue.cgColor
        outerRing.layer.shadowOffset = .zero
        outerRing.layer.shadowRadius = 8
        outerRing.layer.shadowOpacity = 0.8
        outerRing.isUserInteractionEnabled = false
        gazeCursor?.addSubview(outerRing)
        
        let innerDotSize: CGFloat = 20
        let innerDot = UIView(frame: CGRect(
            x: (cursorSize - innerDotSize) / 2,
            y: (cursorSize - innerDotSize) / 2,
            width: innerDotSize,
            height: innerDotSize
        ))
        innerDot.backgroundColor = .systemBlue
        innerDot.layer.cornerRadius = innerDotSize / 2
        innerDot.layer.shadowColor = UIColor.blue.cgColor
        innerDot.layer.shadowOffset = .zero
        innerDot.layer.shadowRadius = 5
        innerDot.layer.shadowOpacity = 1.0
        innerDot.isUserInteractionEnabled = false
        gazeCursor?.addSubview(innerDot)
    }
    
    private func setupEyeTracking() {
        eyeTracker.delegate = self
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
        dwellDetector.setDwellThreshold(1.8)
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
        guard !isNavigating else { return }
        isNavigating = true
        navigationController?.popViewController(animated: true)
    }
    
    @objc private func bodyButtonTapped(_ sender: UIButton) {
        handleButtonAction(sender)
    }
    
    @objc private func sensationButtonTapped(_ sender: UIButton) {
        handleButtonAction(sender)
    }
    
    @objc private func exitButtonTapped() {
        handleButtonAction(exitButton)
    }
    
    private func handleButtonAction(_ button: UIButton) {
        guard let identifier = button.accessibilityIdentifier else { return }
        
        // STRICT GUARD: Speech buttons - ONLY speak, NEVER navigate
        if identifier.hasPrefix("speak:") {
            let text = String(identifier.dropFirst(6))
            if !text.isEmpty {
                SpeechService.shared.speak(text)
            }
            return
        }
        
        // Exit or Back - navigate
        if identifier == "exit" || identifier == "back" {
            guard !isNavigating else { return }
            isNavigating = true
            navigationController?.popViewController(animated: true)
        }
    }
    
    // MARK: - Eye Tracking Helpers
    
    private func convertGazeToAbsolutePosition(_ screenPosition: CGPoint) -> CGPoint {
        guard view.bounds.width > 0 && view.bounds.height > 0 else { return screenPosition }
        let centerX = view.bounds.width / 2
        let centerY = view.bounds.height / 2
        return CGPoint(x: centerX + screenPosition.x, y: centerY + screenPosition.y)
    }
    
    private func applyCursorSmoothing(_ position: CGPoint) -> CGPoint {
        let screenWidth = view.bounds.width
        let screenHeight = view.bounds.height
        let cursorRadius: CGFloat = 30
        var targetX = max(cursorRadius, min(screenWidth - cursorRadius, position.x))
        var targetY = max(cursorRadius, min(screenHeight - cursorRadius, position.y))
        if let lastPos = lastCursorPosition {
            targetX = CGFloat(cursorSmoothingFactor) * lastPos.x + CGFloat(1.0 - cursorSmoothingFactor) * targetX
            targetY = CGFloat(cursorSmoothingFactor) * lastPos.y + CGFloat(1.0 - cursorSmoothingFactor) * targetY
        }
        let smoothedPosition = CGPoint(x: targetX, y: targetY)
        lastCursorPosition = smoothedPosition
        return smoothedPosition
    }
    
    private func updateGazeCursor(_ smoothedPosition: CGPoint) {
        guard let cursor = gazeCursor else { return }
        let baseDuration: TimeInterval = 0.1
        let maxDuration: TimeInterval = 0.3
        let animationDuration = baseDuration + (maxDuration - baseDuration) * Double(cursorSmoothingFactor)
        UIView.animate(withDuration: animationDuration, delay: 0, options: [.curveEaseOut, .allowUserInteraction, .beginFromCurrentState]) {
            cursor.center = smoothedPosition
        }
        if cursor.isHidden, eyeTracker.calibrationData?.isCalibrated == true {
            cursor.isHidden = false
            cursor.alpha = 0
            UIView.animate(withDuration: 0.3) { cursor.alpha = 1.0 }
        }
    }
    
    /// All buttons that can receive dwell (speech + exit)
    private var allDwellButtons: [UIButton] {
        bodyButtons + sensationButtons + [exitButton]
    }
}

// MARK: - EyeTrackerDelegate

extension BodyViewController: EyeTrackerDelegate {
    func eyeTracker(_ tracker: EyeTracker, didUpdateGazeScreenPosition screenPosition: CGPoint, lookAtPoint: simd_float3) {
        let absolutePosition = convertGazeToAbsolutePosition(screenPosition)
        let smoothedPosition = applyCursorSmoothing(absolutePosition)
        dwellDetector.updateGazePosition(smoothedPosition, in: view)
        updateGazeCursor(smoothedPosition)
    }
    
    func eyeTracker(_ tracker: EyeTracker, didUpdateGaze screenPosition: SIMD2<Float>, lookAtPoint: simd_float3, rawAngles: SIMD2<Float>) {}
    
    func eyeTracker(_ tracker: EyeTracker, didDetectBlink isBlinking: Bool) {}
    
    func eyeTrackerDidLoseTracking(_ tracker: EyeTracker) {
        dwellDetector.reset()
        currentDwellingButton = nil
        gazeCursor?.isHidden = true
        lastCursorPosition = nil
    }
}

// MARK: - DwellDetectorDelegate

extension BodyViewController: DwellDetectorDelegate {
    func dwellDetector(_ detector: DwellDetector, didStartDwellingOn view: UIView) {
        if let button = view as? UIButton {
            currentDwellingButton = button
            UIView.animate(withDuration: 0.2) {
                button.alpha = 0.7
                button.transform = CGAffineTransform(scaleX: 1.05, y: 1.05)
            }
        }
    }
    
    func dwellDetector(_ detector: DwellDetector, didUpdateDwellProgress progress: Float, on view: UIView) {}
    
    func dwellDetector(_ detector: DwellDetector, didCompleteDwellOn view: UIView) {
        guard self.viewIfLoaded?.window != nil else { return }
        
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        
        guard let button = view as? UIButton,
              allDwellButtons.contains(button) else {
            return
        }
        
        UIView.animate(withDuration: 0.2) {
            button.alpha = 1.0
            button.transform = .identity
        }
        
        guard let identifier = button.accessibilityIdentifier else { return }
        
        // SAFETY: Speech buttons - speak only, NEVER navigate
        if identifier.hasPrefix("speak:") {
            let text = String(identifier.dropFirst(6))
            if !text.isEmpty {
                SpeechService.shared.speak(text)
            }
            currentDwellingButton = nil
            return
        }
        
        // Exit - navigate
        if identifier == "exit" {
            guard !isNavigating else {
                currentDwellingButton = nil
                return
            }
            isNavigating = true
            navigationController?.popViewController(animated: true)
        }
        currentDwellingButton = nil
    }
    
    func dwellDetector(_ detector: DwellDetector, didCancelDwellOn view: UIView) {
        if let button = view as? UIButton {
            UIView.animate(withDuration: 0.2) {
                button.alpha = 1.0
                button.transform = .identity
            }
            if currentDwellingButton === button { currentDwellingButton = nil }
        }
    }
}

// MARK: - ARSCNViewDelegate

extension BodyViewController: ARSCNViewDelegate {
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        guard anchor is ARFaceAnchor else { return }
        faceNode.transform = node.transform
        if eyeTracker.calibrationData?.isCalibrated == true { gazeCursor?.isHidden = false }
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

extension BodyViewController: ARSessionDelegate {
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
