import UIKit
import ARKit
import SceneKit

class CommunicationViewController: UIViewController {
    
    // MARK: - UI Components
    
    private var backButton: UIButton!
    private var buttonsContainer: UIView!
    private var communicationButtons: [UIButton] = []
    
    // Button configuration
    private struct CommunicationButton {
        let title: String
        let iconName: String?
        let backgroundColor: UIColor
        let textColor: UIColor
        let action: ButtonAction
    }
    
    private enum ButtonAction {
        case speak(String)
        case navigateToBody
        case navigateToFeeling
        case exit
        case keyboard
    }
    
    private let buttonConfigs: [CommunicationButton] = [
        CommunicationButton(title: "Yes", iconName: "checkmark", backgroundColor: UIColor(red: 0.20, green: 0.78, blue: 0.35, alpha: 1.0), textColor: .white, action: .speak("Yes")),
        CommunicationButton(title: "No", iconName: "xmark", backgroundColor: UIColor(red: 1.0, green: 0.23, blue: 0.19, alpha: 1.0), textColor: .white, action: .speak("No")),
        CommunicationButton(title: "Hi", iconName: nil, backgroundColor: UIColor(red: 0.20, green: 0.78, blue: 0.35, alpha: 1.0), textColor: .black, action: .speak("Hi")),
        CommunicationButton(title: "Bye", iconName: nil, backgroundColor: UIColor(red: 1.0, green: 0.23, blue: 0.19, alpha: 1.0), textColor: .black, action: .speak("Bye")),
        CommunicationButton(title: "Body", iconName: "figure.stand", backgroundColor: .black, textColor: .white, action: .navigateToBody),
        CommunicationButton(title: "Feeling", iconName: "brain.head.profile", backgroundColor: UIColor(red: 1.0, green: 0.80, blue: 0.0, alpha: 1.0), textColor: .black, action: .navigateToFeeling),
        CommunicationButton(title: "Exit", iconName: "arrow.left.square", backgroundColor: .white, textColor: .black, action: .exit),
        CommunicationButton(title: "keyboard", iconName: "keyboard", backgroundColor: .white, textColor: .black, action: .keyboard)
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
    
    // Navigation guard flags
    private var isNavigating = false
    private var lastActionTime: Date?
    private let actionCooldown: TimeInterval = 1.0 // 1 second cooldown
    
    // Cursor smoothing
    private var cursorSmoothingFactor: Float = 0.75
    private var lastCursorPosition: CGPoint?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Light cream background with subtle pattern
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
        // Reset navigation flag when view appears (user navigated back)
        isNavigating = false
        // Don't start tracking here - wait for layout in viewDidAppear
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        Logger.debug("=== CommunicationViewController viewDidAppear ===")
        Logger.debug("Communication buttons count: \(communicationButtons.count)")
        
        // Ensure buttons are laid out before starting eye tracking
        view.layoutIfNeeded()
        
        // Verify buttons have valid frames and log them
        for (index, button) in communicationButtons.enumerated() {
            Logger.debug("Button \(index): identifier='\(button.accessibilityIdentifier ?? "nil")', frame=\(button.frame)")
        }
        
        let buttonsHaveFrames = communicationButtons.allSatisfy { button in
            button.frame.width > 0 && button.frame.height > 0
        }
        
        Logger.debug("All buttons have valid frames: \(buttonsHaveFrames)")
        
        if buttonsHaveFrames {
            startFaceTracking()
        } else {
            // Layout not ready, try again after a short delay
            Logger.debug("Layout not ready, retrying in 0.1s...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.view.layoutIfNeeded()
                for (index, button) in self.communicationButtons.enumerated() {
                    Logger.debug("Button \(index) (after delay): identifier='\(button.accessibilityIdentifier ?? "nil")', frame=\(button.frame)")
                }
                self.startFaceTracking()
            }
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        Logger.debug("=== CommunicationViewController viewWillDisappear - STOPPING eye tracking and dwell ===")
        sceneView.session.pause()
        // CRITICAL: Cancel any pending dwell to prevent it from completing after navigation
        dwellDetector.cancelDwell()
        // Reset navigation flag when view disappears
        isNavigating = false
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        eyeTracker.phoneScreenPointSize = phoneScreenPointSize
        layoutButtons()
    }
    
    // MARK: - Setup
    
    private func setupARScene() {
        // Hidden AR scene view for face tracking
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
        // Back Button
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
        view.addSubview(backButton)
        
        // Buttons container
        buttonsContainer = UIView()
        buttonsContainer.backgroundColor = .clear
        buttonsContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(buttonsContainer)
        
        // Create buttons
        for config in buttonConfigs {
            let button = createButton(with: config)
            buttonsContainer.addSubview(button)
            communicationButtons.append(button)
        }
        
        NSLayoutConstraint.activate([
            backButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            backButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            backButton.widthAnchor.constraint(equalToConstant: 120),
            backButton.heightAnchor.constraint(equalToConstant: 50),
            
            buttonsContainer.topAnchor.constraint(equalTo: backButton.bottomAnchor, constant: 30),
            buttonsContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            buttonsContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            buttonsContainer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20)
        ])
    }
    
    private func createButton(with config: CommunicationButton) -> UIButton {
        // Create button with initial non-zero frame to prevent Auto Layout conflicts
        // The actual frame will be set later in layoutButtons()
        let button = UIButton(type: .system)
        button.frame = CGRect(x: 0, y: 0, width: 100, height: 100) // Initial frame to prevent constraint conflicts
        button.backgroundColor = config.backgroundColor
        button.layer.cornerRadius = 12
        button.tag = 100 // Mark as selectable for dwell detection
        button.clipsToBounds = true // Ensure all subviews are contained within button bounds
        
        // Create a container view for icon and text
        // Use frame-based layout to avoid Auto Layout conflicts with frame-based button
        let containerView = UIView()
        containerView.backgroundColor = .clear
        containerView.isUserInteractionEnabled = false
        containerView.autoresizingMask = [.flexibleLeftMargin, .flexibleRightMargin, .flexibleTopMargin, .flexibleBottomMargin]
        button.addSubview(containerView)
        
        // Add icon if available
        if let iconName = config.iconName {
            let iconImageView = UIImageView()
            let iconConfig = UIImage.SymbolConfiguration(pointSize: 40, weight: .medium)
            iconImageView.image = UIImage(systemName: iconName, withConfiguration: iconConfig)
            iconImageView.tintColor = config.textColor
            iconImageView.contentMode = .scaleAspectFit
            iconImageView.isUserInteractionEnabled = false // Prevent interference with button hit testing
            iconImageView.frame = CGRect(x: 0, y: 0, width: 50, height: 50)
            containerView.addSubview(iconImageView)
            
            // Add title label
            let titleLabel = UILabel()
            titleLabel.text = config.title
            titleLabel.textColor = config.textColor
            titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
            titleLabel.textAlignment = .center
            titleLabel.isUserInteractionEnabled = false // Prevent interference with button hit testing
            titleLabel.sizeToFit()
            titleLabel.frame = CGRect(x: 0, y: 58, width: max(titleLabel.frame.width, 50), height: titleLabel.frame.height)
            containerView.addSubview(titleLabel)
            
            // Size containerView to fit content
            let containerWidth = max(50, titleLabel.frame.width)
            let containerHeight: CGFloat = 58 + titleLabel.frame.height
            containerView.frame = CGRect(x: 0, y: 0, width: containerWidth, height: containerHeight)
            
            // Center icon and label within containerView
            iconImageView.center.x = containerWidth / 2
            titleLabel.center.x = containerWidth / 2
        } else {
            // Text only
            let titleLabel = UILabel()
            titleLabel.text = config.title
            titleLabel.textColor = config.textColor
            titleLabel.font = .systemFont(ofSize: 24, weight: .bold)
            titleLabel.textAlignment = .center
            titleLabel.isUserInteractionEnabled = false // Prevent interference with button hit testing
            titleLabel.sizeToFit()
            containerView.addSubview(titleLabel)
            
            // Size containerView to fit label
            containerView.frame = CGRect(x: 0, y: 0, width: titleLabel.frame.width, height: titleLabel.frame.height)
            titleLabel.frame = containerView.bounds
        }
        
        // Center containerView in button (will be updated in layoutButtons)
        containerView.center = CGPoint(x: button.bounds.midX, y: button.bounds.midY)
        
        // Store action in button's accessibility identifier for later retrieval
        switch config.action {
        case .speak(let text):
            button.accessibilityIdentifier = "speak:\(text)"
        case .navigateToBody:
            button.accessibilityIdentifier = "navigate:body"
        case .navigateToFeeling:
            button.accessibilityIdentifier = "navigate:feeling"
        case .exit:
            button.accessibilityIdentifier = "exit"
        case .keyboard:
            button.accessibilityIdentifier = "keyboard"
        }
        
        button.addTarget(self, action: #selector(communicationButtonTapped(_:)), for: .touchUpInside)
        
        return button
    }
    
    private func layoutButtons() {
        guard buttonsContainer.bounds.width > 0 && buttonsContainer.bounds.height > 0 else { return }
        
        let columns: CGFloat = 2
        let rows: CGFloat = 4
        let spacing: CGFloat = 20
        let containerWidth = buttonsContainer.bounds.width
        let containerHeight = buttonsContainer.bounds.height
        
        let buttonWidth = (containerWidth - spacing) / columns
        let buttonHeight = (containerHeight - spacing * (rows - 1)) / rows
        
        for (index, button) in communicationButtons.enumerated() {
            let row = CGFloat(index / Int(columns))
            let col = CGFloat(index % Int(columns))
            
            button.frame = CGRect(
                x: col * (buttonWidth + spacing),
                y: row * (buttonHeight + spacing),
                width: buttonWidth,
                height: buttonHeight
            )
            
            // Recenter the containerView (first subview) within the button
            if let containerView = button.subviews.first {
                containerView.center = CGPoint(x: button.bounds.midX, y: button.bounds.midY)
            }
        }
    }
    
    private func setupGazeCursor() {
        let cursorSize: CGFloat = 60
        gazeCursor = UIView(frame: CGRect(x: 0, y: 0, width: cursorSize, height: cursorSize))
        gazeCursor?.translatesAutoresizingMaskIntoConstraints = true
        gazeCursor?.isHidden = true
        gazeCursor?.backgroundColor = .clear
        gazeCursor?.isUserInteractionEnabled = false // Prevent cursor from interfering with hit testing
        view.addSubview(gazeCursor!)
        
        // Outer green ring
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
        
        // Inner dot
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
        isNavigating = false // Reset flag before navigation
        navigationController?.popViewController(animated: true)
    }
    
    @objc private func communicationButtonTapped(_ sender: UIButton) {
        handleButtonAction(sender)
    }
    
    private func handleButtonAction(_ button: UIButton) {
        guard let identifier = button.accessibilityIdentifier else {
            Logger.error("Button has no accessibility identifier")
            return
        }
        
        // STRICT GUARD: Speech buttons are handled FIRST before ANY other logic
        // This check is FIRST - before cooldown, before navigation checks
        // Speech buttons can NEVER navigate under any circumstances
        if identifier.hasPrefix("speak:") {
            let text = String(identifier.dropFirst(6))
            if !text.isEmpty {
                Logger.debug("handleButtonAction: Speech button - speaking '\(text)'")
                SpeechService.shared.speak(text)
            }
            return // ALWAYS return here - no exceptions, no navigation possible
        }
        
        // Prevent rapid repeated actions (only for navigation buttons)
        if let lastTime = lastActionTime {
            let timeSinceLastAction = Date().timeIntervalSince(lastTime)
            if timeSinceLastAction < actionCooldown {
                Logger.debug("Action ignored - too soon after last action")
                return
            }
        }
        
        // Prevent multiple navigations
        guard !isNavigating else {
            Logger.debug("Navigation already in progress, ignoring duplicate request")
            return
        }
        
        // Navigation actions only for non-speech buttons
        if identifier == "navigate:body" {
            isNavigating = true
            lastActionTime = Date()
            let bodyVC = BodyViewController()
            // Check if already on stack (Apple docs: pushViewController throws exception if already on stack)
            if let navController = navigationController,
               !navController.viewControllers.contains(where: { $0 is BodyViewController }) {
                navController.pushViewController(bodyVC, animated: true)
            } else {
                Logger.debug("BodyViewController already on stack, skipping push")
                isNavigating = false
            }
        } else if identifier == "navigate:feeling" {
            isNavigating = true
            lastActionTime = Date()
            let feelingVC = FeelingViewController()
            // Check if already on stack (Apple docs: pushViewController throws exception if already on stack)
            if let navController = navigationController,
               !navController.viewControllers.contains(where: { $0 is FeelingViewController }) {
                navController.pushViewController(feelingVC, animated: true)
            } else {
                Logger.debug("FeelingViewController already on stack, skipping push")
                isNavigating = false
            }
        } else if identifier == "exit" {
            isNavigating = true
            lastActionTime = Date()
            navigationController?.popToRootViewController(animated: true)
        } else if identifier == "back" {
            // Handle back button via eye gaze
            isNavigating = true
            lastActionTime = Date()
            navigationController?.popViewController(animated: true)
        } else if identifier == "keyboard" {
            isNavigating = true
            lastActionTime = Date()
            let keyboardVC = KeyboardViewController()
            if let navController = navigationController,
               !navController.viewControllers.contains(where: { $0 is KeyboardViewController }) {
                navController.pushViewController(keyboardVC, animated: true)
            } else {
                Logger.debug("KeyboardViewController already on stack, skipping push")
                isNavigating = false
            }
        } else {
            Logger.error("Unknown button identifier: \(identifier)")
        }
    }
    
    // MARK: - Eye Tracking Helpers
    
    private func convertGazeToAbsolutePosition(_ screenPosition: CGPoint) -> CGPoint {
        // Ensure view bounds are valid
        guard view.bounds.width > 0 && view.bounds.height > 0 else {
            Logger.debug("View bounds not ready: \(view.bounds)")
            return screenPosition // Return relative position if bounds not ready
        }
        
        let screenWidth = view.bounds.width
        let screenHeight = view.bounds.height
        
        let centerX = screenWidth / 2
        let centerY = screenHeight / 2
        
        let absoluteX = centerX + screenPosition.x
        let absoluteY = centerY + screenPosition.y
        
        return CGPoint(x: absoluteX, y: absoluteY)
    }
    
    /// Apply smoothing to gaze position - used for BOTH cursor display AND hit testing
    /// This ensures visual cursor and hit test are always synchronized
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
        
        // Position is already smoothed by applyCursorSmoothing
        let baseDuration: TimeInterval = 0.1
        let maxDuration: TimeInterval = 0.3
        let animationDuration = baseDuration + (maxDuration - baseDuration) * Double(cursorSmoothingFactor)
        
        UIView.animate(withDuration: animationDuration, delay: 0, options: [.curveEaseOut, .allowUserInteraction, .beginFromCurrentState], animations: {
            cursor.center = smoothedPosition
        })
        
        if cursor.isHidden {
            if self.eyeTracker.calibrationData?.isCalibrated == true {
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

extension CommunicationViewController: EyeTrackerDelegate {
    func eyeTracker(_ tracker: EyeTracker, didUpdateGazeScreenPosition screenPosition: CGPoint, lookAtPoint: simd_float3) {
        let absolutePosition = convertGazeToAbsolutePosition(screenPosition)
        
        // CRITICAL: Apply smoothing FIRST, then use smoothed position for BOTH
        // cursor display AND hit testing to ensure they are synchronized
        let smoothedPosition = applyCursorSmoothing(absolutePosition)
        
        // Use the SAME smoothed position for both operations
        dwellDetector.updateGazePosition(smoothedPosition, in: view)
        updateGazeCursor(smoothedPosition)
    }
    
    func eyeTracker(_ tracker: EyeTracker, didUpdateGaze screenPosition: SIMD2<Float>, lookAtPoint: simd_float3, rawAngles: SIMD2<Float>) {
        // Legacy method
    }
    
    func eyeTracker(_ tracker: EyeTracker, didDetectBlink isBlinking: Bool) {
        // Blink detection
    }
    
    func eyeTrackerDidLoseTracking(_ tracker: EyeTracker) {
        dwellDetector.reset()
        currentDwellingButton = nil
        gazeCursor?.isHidden = true
        lastCursorPosition = nil
    }
}

// MARK: - DwellDetectorDelegate

extension CommunicationViewController: DwellDetectorDelegate {
    func dwellDetector(_ detector: DwellDetector, didStartDwellingOn view: UIView) {
        if let button = view as? UIButton {
            currentDwellingButton = button
            UIView.animate(withDuration: 0.2) {
                button.alpha = 0.7
                button.transform = CGAffineTransform(scaleX: 1.05, y: 1.05)
            }
        }
    }
    
    func dwellDetector(_ detector: DwellDetector, didUpdateDwellProgress progress: Float, on view: UIView) {
        // Progress indicator can be added here if needed
    }
    
    func dwellDetector(_ detector: DwellDetector, didCompleteDwellOn view: UIView) {
        // CRITICAL: Ignore dwell completions if this view is not visible
        // This prevents stale dwells from triggering after navigation
        guard self.viewIfLoaded?.window != nil else {
            Logger.debug("CommunicationViewController: Ignoring dwell completion - view is not visible")
            return
        }
        
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        
        // Ensure we have a button and it's one of our communication buttons
        guard let button = view as? UIButton,
              communicationButtons.contains(button) || button === backButton else {
            Logger.error("Dwell completed on non-button or unknown button")
            return
        }
        
        UIView.animate(withDuration: 0.2) {
            button.alpha = 1.0
            button.transform = .identity
        }
        
        // Verify button has identifier before handling action
        guard let identifier = button.accessibilityIdentifier else {
            Logger.error("Button has no accessibility identifier in dwell completion")
            currentDwellingButton = nil
            return
        }
        
        // Debug: Log button details
        Logger.debug("Dwell completed - Button frame: \(button.frame), identifier: \(identifier)")
        
        // SAFETY CHECK: Speech buttons are handled directly here
        // This is a STRICT guard - speech buttons can NEVER navigate
        if identifier.hasPrefix("speak:") {
            let text = String(identifier.dropFirst(6))
            if !text.isEmpty {
                Logger.debug("Speech button detected - speaking '\(text)' and returning immediately")
                SpeechService.shared.speak(text)
            }
            currentDwellingButton = nil
            return // ALWAYS return here - no exceptions, no navigation
        }
        
        // Only non-speech buttons reach handleButtonAction
        handleButtonAction(button)
        currentDwellingButton = nil
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

extension CommunicationViewController: ARSCNViewDelegate {
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        guard anchor is ARFaceAnchor else { return }
        faceNode.transform = node.transform
        
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

extension CommunicationViewController: ARSessionDelegate {
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
