import UIKit
import ARKit
import SceneKit

/// Keyboard layout presets for MND-friendly letter arrangement
private enum KeyboardLayoutPreset: String, CaseIterable {
    case qwerty = "QWERTY"
    case alphabetical = "ABC"
    case frequency = "Common"
    
    var letterOrder: [Character] {
        switch self {
        case .qwerty:
            return Array("QWERTYUIOPASDFGHJKLZXCVBNM")
        case .alphabetical:
            return Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        case .frequency:
            return Array("ETAOINSRHLDCUMFPGWYBVKXJQZ")
        }
    }
}

class KeyboardViewController: UIViewController {
    
    // MARK: - UI Components
    
    private var backButton: UIButton!
    private var speakButton: UIButton!
    private var messageLabel: UILabel!
    private var phraseContainer: UIView!
    private var phraseButtons: [UIButton] = []
    private var letterButtons: [UIButton] = []
    private var presetSegmented: UISegmentedControl!
    private var letterContainer: UIView!
    private var deleteButton: UIButton!
    private var spaceButton: UIButton!
    private var sendButton: UIButton!
    
    private let defaultPhrases = ["I am good", "Doing well", "In pain"]
    private var messageText = "" {
        didSet {
            messageLabel.text = messageText.isEmpty ? "Type a message" : messageText
            messageLabel.textColor = messageText.isEmpty ? .placeholderText : .label
        }
    }
    
    private var currentPreset: KeyboardLayoutPreset = .qwerty {
        didSet {
            rebuildLetterButtons()
            layoutLetterButtons()
        }
    }
    
    // MARK: - Eye Tracking
    
    private var sceneView: ARSCNView!
    private let eyeTracker = EyeTracker()
    private let dwellDetector = DwellDetector()
    private var gazeCursor: UIView?
    
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
    
    private var currentDwellingButton: UIButton?
    private var isNavigating = false
    private var cursorSmoothingFactor: Float = 0.8
    private var lastCursorPosition: CGPoint?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.95, green: 0.98, blue: 0.95, alpha: 1.0)
        
        setupARScene()
        setupUI()
        setupGazeCursor()
        setupEyeTracking()
        setupDwellDetector()
        
        let calibration = CalibrationData.load()
        if calibration.isCalibrated {
            eyeTracker.calibrationData = calibration
            gazeCursor?.isHidden = false
        }
        
        // Restore saved layout preset
        if let saved = UserDefaults.standard.string(forKey: "keyboardLayoutPreset"),
           let preset = KeyboardLayoutPreset(rawValue: saved) {
            currentPreset = preset
            presetSegmented.selectedSegmentIndex = KeyboardLayoutPreset.allCases.firstIndex(of: preset) ?? 0
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        isNavigating = false
        startFaceTracking()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        Logger.debug("=== KeyboardViewController viewWillDisappear - STOPPING eye tracking and dwell ===")
        sceneView.session.pause()
        dwellDetector.cancelDwell()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        eyeTracker.phoneScreenPointSize = phoneScreenPointSize
        layoutPhraseButtons()
        layoutLetterButtons()
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
        let padding: CGFloat = 16
        
        // Speak button - green, full width
        speakButton = UIButton(type: .system)
        speakButton.setTitle("Speak", for: .normal)
        speakButton.setTitleColor(.white, for: .normal)
        speakButton.titleLabel?.font = .systemFont(ofSize: 22, weight: .bold)
        speakButton.backgroundColor = UIColor(red: 0.20, green: 0.78, blue: 0.35, alpha: 1.0)
        speakButton.layer.cornerRadius = 14
        speakButton.tag = 100
        speakButton.accessibilityIdentifier = "keyboard:speak"
        speakButton.addTarget(self, action: #selector(speakTapped), for: .touchUpInside)
        speakButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(speakButton)
        
        // Text field / message display
        messageLabel = UILabel()
        messageLabel.text = "Type a message"
        messageLabel.textColor = .placeholderText
        messageLabel.font = .systemFont(ofSize: 18, weight: .regular)
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 2
        messageLabel.backgroundColor = UIColor.systemGray5
        messageLabel.layer.cornerRadius = 10
        messageLabel.clipsToBounds = true
        messageLabel.isUserInteractionEnabled = false
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(messageLabel)
        
        // Phrase container and buttons
        phraseContainer = UIView()
        phraseContainer.backgroundColor = .clear
        phraseContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(phraseContainer)
        
        for phrase in defaultPhrases {
            let btn = createPhraseButton(text: phrase)
            phraseContainer.addSubview(btn)
            phraseButtons.append(btn)
        }
        
        // Preset selector
        presetSegmented = UISegmentedControl(items: KeyboardLayoutPreset.allCases.map { $0.rawValue })
        presetSegmented.selectedSegmentIndex = 0
        presetSegmented.addTarget(self, action: #selector(presetChanged), for: .valueChanged)
        presetSegmented.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(presetSegmented)
        
        // Letter container
        letterContainer = UIView()
        letterContainer.backgroundColor = .clear
        letterContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(letterContainer)
        
        // Rebuild letters from current preset
        rebuildLetterButtons()
        
        // Action buttons row
        deleteButton = createActionButton(title: "Delete", color: UIColor(red: 1.0, green: 0.23, blue: 0.19, alpha: 1.0), identifier: "keyboard:delete")
        deleteButton.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)
        view.addSubview(deleteButton)
        
        spaceButton = createActionButton(title: "Space", color: UIColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 1.0), identifier: "keyboard:space")
        spaceButton.addTarget(self, action: #selector(spaceTapped), for: .touchUpInside)
        view.addSubview(spaceButton)
        
        sendButton = createActionButton(title: "Send", color: UIColor(red: 0.20, green: 0.78, blue: 0.35, alpha: 1.0), identifier: "keyboard:send")
        sendButton.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)
        view.addSubview(sendButton)
        
        // Back button
        backButton = UIButton(type: .system)
        backButton.setTitle("← Back", for: .normal)
        backButton.setTitleColor(.white, for: .normal)
        backButton.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
        backButton.backgroundColor = UIColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 1.0)
        backButton.layer.cornerRadius = 12
        backButton.tag = 100
        backButton.accessibilityIdentifier = "back"
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        backButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(backButton)
        
        NSLayoutConstraint.activate([
            speakButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: padding),
            speakButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: padding),
            speakButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -padding),
            speakButton.heightAnchor.constraint(equalToConstant: 56),
            
            messageLabel.topAnchor.constraint(equalTo: speakButton.bottomAnchor, constant: padding),
            messageLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: padding),
            messageLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -padding),
            messageLabel.heightAnchor.constraint(equalToConstant: 52),
            
            phraseContainer.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: padding),
            phraseContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: padding),
            phraseContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -padding),
            phraseContainer.heightAnchor.constraint(equalToConstant: 44),
            
            presetSegmented.topAnchor.constraint(equalTo: phraseContainer.bottomAnchor, constant: padding),
            presetSegmented.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: padding),
            presetSegmented.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -padding),
            presetSegmented.heightAnchor.constraint(equalToConstant: 36),
            
            letterContainer.topAnchor.constraint(equalTo: presetSegmented.bottomAnchor, constant: padding),
            letterContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: padding),
            letterContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -padding),
            letterContainer.bottomAnchor.constraint(equalTo: deleteButton.topAnchor, constant: -padding),
            
            deleteButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: padding),
            deleteButton.bottomAnchor.constraint(equalTo: backButton.topAnchor, constant: -padding),
            deleteButton.widthAnchor.constraint(equalTo: spaceButton.widthAnchor),
            deleteButton.heightAnchor.constraint(equalToConstant: 52),
            
            spaceButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spaceButton.bottomAnchor.constraint(equalTo: deleteButton.bottomAnchor),
            spaceButton.heightAnchor.constraint(equalToConstant: 52),
            spaceButton.widthAnchor.constraint(equalToConstant: 100),
            
            sendButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -padding),
            sendButton.bottomAnchor.constraint(equalTo: deleteButton.bottomAnchor),
            sendButton.widthAnchor.constraint(equalTo: deleteButton.widthAnchor),
            sendButton.heightAnchor.constraint(equalToConstant: 52),
            
            backButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: padding),
            backButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -padding),
            backButton.widthAnchor.constraint(equalToConstant: 100),
            backButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }
    
    private func createPhraseButton(text: String) -> UIButton {
        let btn = UIButton(type: .system)
        btn.frame = CGRect(x: 0, y: 0, width: 100, height: 44)
        btn.setTitle(text, for: .normal)
        btn.setTitleColor(.white, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        btn.backgroundColor = UIColor(red: 0.93, green: 0.55, blue: 0.2, alpha: 1.0)
        btn.layer.cornerRadius = 22
        btn.tag = 100
        btn.accessibilityIdentifier = "keyboard:phrase:\(text)"
        btn.addTarget(self, action: #selector(phraseTapped(_:)), for: .touchUpInside)
        return btn
    }
    
    private func createLetterButton(character: Character) -> UIButton {
        let btn = UIButton(type: .system)
        btn.frame = CGRect(x: 0, y: 0, width: 56, height: 56)
        btn.setTitle(String(character), for: .normal)
        btn.setTitleColor(.white, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 28, weight: .bold)
        btn.backgroundColor = UIColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 1.0)
        btn.layer.cornerRadius = 12
        btn.tag = 100
        btn.accessibilityIdentifier = "keyboard:letter:\(character)"
        btn.addTarget(self, action: #selector(letterTapped(_:)), for: .touchUpInside)
        return btn
    }
    
    private func createActionButton(title: String, color: UIColor, identifier: String) -> UIButton {
        let btn = UIButton(type: .system)
        btn.setTitle(title, for: .normal)
        btn.setTitleColor(.white, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
        btn.backgroundColor = color
        btn.layer.cornerRadius = 12
        btn.tag = 100
        btn.accessibilityIdentifier = identifier
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }
    
    private func rebuildLetterButtons() {
        letterButtons.forEach { $0.removeFromSuperview() }
        letterButtons.removeAll()
        
        for char in currentPreset.letterOrder {
            let btn = createLetterButton(character: char)
            letterContainer.addSubview(btn)
            letterButtons.append(btn)
        }
    }
    
    private func layoutPhraseButtons() {
        guard phraseContainer.bounds.width > 0 else { return }
        let count = CGFloat(phraseButtons.count)
        let spacing: CGFloat = 12
        let totalWidth = phraseContainer.bounds.width
        let availableWidth = totalWidth - spacing * (count - 1)
        let w = availableWidth / count
        
        for (i, btn) in phraseButtons.enumerated() {
            btn.frame = CGRect(x: CGFloat(i) * (w + spacing), y: 0, width: w, height: 44)
        }
    }
    
    private func layoutLetterButtons() {
        guard letterContainer.bounds.width > 0 && letterContainer.bounds.height > 0,
              !letterButtons.isEmpty else { return }
        
        let cols: CGFloat = 6
        let spacing: CGFloat = 10
        let w = letterContainer.bounds.width
        let h = letterContainer.bounds.height
        let buttonWidth = (w - spacing * (cols - 1)) / cols
        let rows = ceil(CGFloat(letterButtons.count) / cols)
        let buttonHeight = (h - spacing * (rows - 1)) / rows
        
        for (i, btn) in letterButtons.enumerated() {
            let row = CGFloat(i / Int(cols))
            let col = CGFloat(i % Int(cols))
            btn.frame = CGRect(
                x: col * (buttonWidth + spacing),
                y: row * (buttonHeight + spacing),
                width: buttonWidth,
                height: buttonHeight
            )
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
        outerRing.isUserInteractionEnabled = false
        gazeCursor?.addSubview(outerRing)
        
        let innerDotSize: CGFloat = 20
        let innerDot = UIView(frame: CGRect(x: (cursorSize - innerDotSize) / 2, y: (cursorSize - innerDotSize) / 2, width: innerDotSize, height: innerDotSize))
        innerDot.backgroundColor = .systemBlue
        innerDot.layer.cornerRadius = innerDotSize / 2
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
        guard ARFaceTrackingConfiguration.isSupported else { return }
        let config = ARFaceTrackingConfiguration()
        config.maximumNumberOfTrackedFaces = 1
        sceneView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
    }
    
    // MARK: - Actions
    
    @objc private func presetChanged() {
        let index = presetSegmented.selectedSegmentIndex
        if index >= 0 && index < KeyboardLayoutPreset.allCases.count {
            currentPreset = KeyboardLayoutPreset.allCases[index]
            UserDefaults.standard.set(currentPreset.rawValue, forKey: "keyboardLayoutPreset")
        }
    }
    
    @objc private func speakTapped() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        SpeechService.shared.speak(text)
    }
    
    @objc private func phraseTapped(_ sender: UIButton) {
        guard let phrase = sender.title(for: .normal) else { return }
        if !messageText.isEmpty { messageText += " " }
        messageText += phrase
    }
    
    @objc private func letterTapped(_ sender: UIButton) {
        guard let title = sender.title(for: .normal), let char = title.first else { return }
        messageText += String(char)
    }
    
    @objc private func deleteTapped() {
        guard !messageText.isEmpty else { return }
        messageText.removeLast()
    }
    
    @objc private func spaceTapped() {
        messageText += " "
    }
    
    @objc private func sendTapped() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            SpeechService.shared.speak(text)
        }
        messageText = ""
    }
    
    @objc private func backTapped() {
        guard !isNavigating else { return }
        isNavigating = true
        navigationController?.popViewController(animated: true)
    }
    
    // MARK: - All dwell targets
    
    private var allDwellButtons: [UIButton] {
        var buttons: [UIButton] = []
        buttons.append(speakButton)
        buttons.append(contentsOf: phraseButtons)
        buttons.append(contentsOf: letterButtons)
        buttons.append(deleteButton)
        buttons.append(spaceButton)
        buttons.append(sendButton)
        buttons.append(backButton)
        return buttons
    }
    
    // MARK: - Eye Tracking Helpers
    
    private func convertGazeToAbsolutePosition(_ screenPosition: CGPoint) -> CGPoint {
        guard view.bounds.width > 0 && view.bounds.height > 0 else { return screenPosition }
        let cx = view.bounds.width / 2
        let cy = view.bounds.height / 2
        return CGPoint(x: cx + screenPosition.x, y: cy + screenPosition.y)
    }
    
    private func applyCursorSmoothing(_ position: CGPoint) -> CGPoint {
        let sw = view.bounds.width
        let sh = view.bounds.height
        let r: CGFloat = 30
        var tx = max(r, min(sw - r, position.x))
        var ty = max(r, min(sh - r, position.y))
        if let last = lastCursorPosition {
            tx = CGFloat(cursorSmoothingFactor) * last.x + CGFloat(1 - cursorSmoothingFactor) * tx
            ty = CGFloat(cursorSmoothingFactor) * last.y + CGFloat(1 - cursorSmoothingFactor) * ty
        }
        let p = CGPoint(x: tx, y: ty)
        lastCursorPosition = p
        return p
    }
    
    private func updateGazeCursor(_ pos: CGPoint) {
        guard let c = gazeCursor else { return }
        UIView.animate(withDuration: 0.15, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
            c.center = pos
        }
        if c.isHidden, eyeTracker.calibrationData?.isCalibrated == true {
            c.isHidden = false
            c.alpha = 0
            UIView.animate(withDuration: 0.3) { c.alpha = 1 }
        }
    }
}

// MARK: - EyeTrackerDelegate

extension KeyboardViewController: EyeTrackerDelegate {
    func eyeTracker(_ tracker: EyeTracker, didUpdateGazeScreenPosition screenPosition: CGPoint, lookAtPoint: simd_float3) {
        let absPos = convertGazeToAbsolutePosition(screenPosition)
        let smoothed = applyCursorSmoothing(absPos)
        dwellDetector.updateGazePosition(smoothed, in: view)
        updateGazeCursor(smoothed)
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

extension KeyboardViewController: DwellDetectorDelegate {
    func dwellDetector(_ detector: DwellDetector, didStartDwellingOn view: UIView) {
        if let btn = view as? UIButton {
            currentDwellingButton = btn
            UIView.animate(withDuration: 0.2) {
                btn.alpha = 0.7
                btn.transform = CGAffineTransform(scaleX: 1.05, y: 1.05)
            }
        }
    }
    
    func dwellDetector(_ detector: DwellDetector, didUpdateDwellProgress progress: Float, on view: UIView) {}
    
    func dwellDetector(_ detector: DwellDetector, didCompleteDwellOn view: UIView) {
        guard viewIfLoaded?.window != nil else { return }
        
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        
        guard let btn = view as? UIButton, allDwellButtons.contains(btn),
              let id = btn.accessibilityIdentifier else {
            currentDwellingButton = nil
            return
        }
        
        UIView.animate(withDuration: 0.2) {
            btn.alpha = 1.0
            btn.transform = .identity
        }
        
        if id == "back" {
            guard !isNavigating else {
                currentDwellingButton = nil
                return
            }
            isNavigating = true
            navigationController?.popViewController(animated: true)
            currentDwellingButton = nil
            return
        }
        
        if id == "keyboard:speak" {
            let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { SpeechService.shared.speak(text) }
            currentDwellingButton = nil
            return
        }
        
        if id.hasPrefix("keyboard:phrase:") {
            let phrase = String(id.dropFirst("keyboard:phrase:".count))
            if !messageText.isEmpty { messageText += " " }
            messageText += phrase
            currentDwellingButton = nil
            return
        }
        
        if id.hasPrefix("keyboard:letter:") {
            let char = id.dropFirst("keyboard:letter:".count).first ?? Character(" ")
            messageText += String(char)
            currentDwellingButton = nil
            return
        }
        
        if id == "keyboard:delete" {
            if !messageText.isEmpty { messageText.removeLast() }
            currentDwellingButton = nil
            return
        }
        
        if id == "keyboard:space" {
            messageText += " "
            currentDwellingButton = nil
            return
        }
        
        if id == "keyboard:send" {
            let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { SpeechService.shared.speak(text) }
            messageText = ""
            currentDwellingButton = nil
        }
    }
    
    func dwellDetector(_ detector: DwellDetector, didCancelDwellOn view: UIView) {
        if let btn = view as? UIButton {
            UIView.animate(withDuration: 0.2) {
                btn.alpha = 1.0
                btn.transform = .identity
            }
            if currentDwellingButton === btn { currentDwellingButton = nil }
        }
    }
}

// MARK: - ARSCNViewDelegate

extension KeyboardViewController: ARSCNViewDelegate {
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        guard anchor is ARFaceAnchor else { return }
        faceNode.transform = node.transform
        if eyeTracker.calibrationData?.isCalibrated == true { gazeCursor?.isHidden = false }
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard let fa = anchor as? ARFaceAnchor else { return }
        faceNode.transform = node.transform
        eyeLNode.simdTransform = fa.leftEyeTransform
        eyeRNode.simdTransform = fa.rightEyeTransform
        eyeTracker.processFaceAnchor(fa)
    }
    
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        if let pov = sceneView.pointOfView {
            virtualPhoneNode.transform = pov.transform
        }
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor) {
        eyeTracker.reset()
        dwellDetector.reset()
    }
}

// MARK: - ARSessionDelegate

extension KeyboardViewController: ARSessionDelegate {
    func session(_ session: ARSession, didFailWithError error: Error) {
        Logger.error("AR session failed: \(error.localizedDescription)")
    }
    func sessionWasInterrupted(_ session: ARSession) { Logger.info("AR session interrupted") }
    func sessionInterruptionEnded(_ session: ARSession) {
        sceneView.session.run(ARFaceTrackingConfiguration(), options: [.resetTracking])
    }
}
