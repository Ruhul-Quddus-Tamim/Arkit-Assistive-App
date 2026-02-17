import UIKit
import ARKit
import SceneKit

private enum ComposeKeyboardLayout: String, CaseIterable {
    case qwerty = "QWERTY"
    case alphabetical = "ABC"
    case frequency = "Common"
    
    var letterOrder: [Character] {
        switch self {
        case .qwerty: return Array("QWERTYUIOPASDFGHJKLZXCVBNM")
        case .alphabetical: return Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        case .frequency: return Array("ETAOINSRHLDCUMFPGWYBVKXJQZ")
        }
    }
}

class MessageComposeViewController: UIViewController {
    
    let contact: Contact
    
    private var backButton: UIButton!
    private var headerLabel: UILabel!
    private var messageLabel: UILabel!
    private var phraseContainer: UIView!
    private var phraseButtons: [UIButton] = []
    private var letterContainer: UIView!
    private var letterButtons: [UIButton] = []
    private var presetSegmented: UISegmentedControl!
    private var speakButton: UIButton!
    private var sendButton: UIButton!
    private var deleteButton: UIButton!
    private var spaceButton: UIButton!
    
    private let defaultPhrases = ["I am good", "Doing well", "In pain"]
    private var messageText = "" {
        didSet {
            messageLabel.text = messageText.isEmpty ? "Type a message" : messageText
            messageLabel.textColor = messageText.isEmpty ? .placeholderText : .label
            updateComposeBubble()
        }
    }
    
    // WhatsApp-style colors
    private let headerGreen = UIColor(red: 0.07, green: 0.37, blue: 0.33, alpha: 1.0)
    private let chatBackground = UIColor(red: 0.93, green: 0.90, blue: 0.87, alpha: 1.0)   // #EDE7DE
    private let sentBubbleGreen = UIColor(red: 0.86, green: 0.97, blue: 0.78, alpha: 1.0) // #DCF8C6
    private let inputBarGray = UIColor(red: 0.96, green: 0.96, blue: 0.96, alpha: 1.0)
    private let whatsAppGreen = UIColor(red: 0.07, green: 0.49, blue: 0.42, alpha: 1.0)   // #128C7E
    
    private var currentPreset: ComposeKeyboardLayout = .qwerty {
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
        view.bounds.width > 0 && view.bounds.height > 0 ? view.bounds.size : CGSize(width: 1311, height: 603)
    }
    
    private var currentDwellingButton: UIButton?
    private var isNavigating = false
    private var isSending = false
    private var cursorSmoothingFactor: Float = 0.8
    private var lastCursorPosition: CGPoint?
    
    init(contact: Contact) {
        self.contact = contact
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = chatBackground
        
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
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        isNavigating = false
        startFaceTracking()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sceneView.session.pause()
        dwellDetector.cancelDwell()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        eyeTracker.phoneScreenPointSize = phoneScreenPointSize
        layoutPhraseButtons()
        layoutLetterButtons()
    }
    
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
    
    private var composeBubbleView: UIView!
    private var composeBubbleHeightConstraint: NSLayoutConstraint!
    
    private func setupUI() {
        let padding: CGFloat = 16
        
        // WhatsApp-style header
        let headerView = UIView()
        headerView.backgroundColor = headerGreen
        headerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerView)
        
        // MND-friendly: large back button (min 70pt)
        backButton = UIButton(type: .system)
        backButton.setTitle("← Back", for: .normal)
        backButton.setTitleColor(.white, for: .normal)
        backButton.titleLabel?.font = .systemFont(ofSize: 28, weight: .semibold)
        backButton.backgroundColor = .clear
        backButton.contentHorizontalAlignment = .center
        backButton.tag = 100
        backButton.accessibilityIdentifier = "back"
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        backButton.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(backButton)
        
        headerLabel = UILabel()
        headerLabel.text = contact.firstName
        headerLabel.font = .systemFont(ofSize: 26, weight: .bold)
        headerLabel.textColor = .white
        headerLabel.textAlignment = .center
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(headerLabel)
        
        // Message compose bubble (WhatsApp sent-message style)
        composeBubbleView = UIView()
        composeBubbleView.backgroundColor = sentBubbleGreen
        composeBubbleView.layer.cornerRadius = 12
        composeBubbleView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        composeBubbleView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(composeBubbleView)
        
        messageLabel = UILabel()
        messageLabel.text = "Type a message"
        messageLabel.textColor = .placeholderText
        messageLabel.font = .systemFont(ofSize: 20, weight: .regular)
        messageLabel.textAlignment = .natural
        messageLabel.numberOfLines = 4
        messageLabel.isUserInteractionEnabled = false
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        composeBubbleView.addSubview(messageLabel)
        
        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 80),
            backButton.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: padding),
            backButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 100),
            backButton.heightAnchor.constraint(equalToConstant: 70),
            headerLabel.leadingAnchor.constraint(greaterThanOrEqualTo: backButton.trailingAnchor, constant: 12),
            headerLabel.trailingAnchor.constraint(lessThanOrEqualTo: headerView.trailingAnchor, constant: -100),
            headerLabel.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            headerLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            composeBubbleView.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: padding),
            composeBubbleView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: padding),
            composeBubbleView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -padding),
            
            messageLabel.topAnchor.constraint(equalTo: composeBubbleView.topAnchor, constant: 12),
            messageLabel.leadingAnchor.constraint(equalTo: composeBubbleView.leadingAnchor, constant: 14),
            messageLabel.trailingAnchor.constraint(equalTo: composeBubbleView.trailingAnchor, constant: -14),
            messageLabel.bottomAnchor.constraint(equalTo: composeBubbleView.bottomAnchor, constant: -12)
        ])
        composeBubbleHeightConstraint = composeBubbleView.heightAnchor.constraint(equalToConstant: 72)
        composeBubbleHeightConstraint.isActive = true
        
        phraseContainer = UIView()
        phraseContainer.backgroundColor = .clear
        phraseContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(phraseContainer)
        
        for phrase in defaultPhrases {
            let btn = createPhraseButton(text: phrase)
            phraseContainer.addSubview(btn)
            phraseButtons.append(btn)
        }
        
        presetSegmented = UISegmentedControl(items: ComposeKeyboardLayout.allCases.map { $0.rawValue })
        presetSegmented.selectedSegmentIndex = 0
        presetSegmented.selectedSegmentTintColor = whatsAppGreen
        presetSegmented.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
        presetSegmented.setTitleTextAttributes([.foregroundColor: UIColor.darkGray], for: .normal)
        presetSegmented.addTarget(self, action: #selector(presetChanged), for: .valueChanged)
        presetSegmented.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(presetSegmented)
        
        letterContainer = UIView()
        letterContainer.backgroundColor = .clear
        letterContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(letterContainer)
        
        rebuildLetterButtons()
        
        deleteButton = createActionButton(title: "Delete", color: UIColor(red: 1.0, green: 0.23, blue: 0.19, alpha: 1.0), identifier: "compose:delete")
        deleteButton.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)
        view.addSubview(deleteButton)
        
        spaceButton = createActionButton(title: "Space", color: UIColor(red: 0.55, green: 0.55, blue: 0.57, alpha: 1.0), identifier: "compose:space")
        spaceButton.addTarget(self, action: #selector(spaceTapped), for: .touchUpInside)
        view.addSubview(spaceButton)
        
        speakButton = UIButton(type: .system)
        speakButton.setTitle("Speak", for: .normal)
        speakButton.setTitleColor(.white, for: .normal)
        speakButton.titleLabel?.font = .systemFont(ofSize: 24, weight: .bold)
        speakButton.backgroundColor = whatsAppGreen
        speakButton.layer.cornerRadius = 14
        speakButton.accessibilityIdentifier = "compose:speak"
        speakButton.addTarget(self, action: #selector(speakTapped), for: .touchUpInside)
        speakButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(speakButton)
        
        sendButton = createActionButton(title: "Send", color: whatsAppGreen, identifier: "compose:send")
        sendButton.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)
        view.addSubview(sendButton)
        
        NSLayoutConstraint.activate([
            speakButton.topAnchor.constraint(equalTo: composeBubbleView.bottomAnchor, constant: padding),
            speakButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: padding),
            speakButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -padding),
            speakButton.heightAnchor.constraint(equalToConstant: 64),
            
            phraseContainer.topAnchor.constraint(equalTo: speakButton.bottomAnchor, constant: padding),
            phraseContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: padding),
            phraseContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -padding),
            phraseContainer.heightAnchor.constraint(equalToConstant: 56),
            
            presetSegmented.topAnchor.constraint(equalTo: phraseContainer.bottomAnchor, constant: padding),
            presetSegmented.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: padding),
            presetSegmented.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -padding),
            presetSegmented.heightAnchor.constraint(equalToConstant: 44),
            
            letterContainer.topAnchor.constraint(equalTo: presetSegmented.bottomAnchor, constant: padding),
            letterContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: padding),
            letterContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -padding),
            letterContainer.bottomAnchor.constraint(equalTo: deleteButton.topAnchor, constant: -padding),
            
            deleteButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: padding),
            deleteButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -padding),
            deleteButton.widthAnchor.constraint(equalTo: spaceButton.widthAnchor),
            deleteButton.heightAnchor.constraint(equalToConstant: 64),
            
            spaceButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spaceButton.bottomAnchor.constraint(equalTo: deleteButton.bottomAnchor),
            spaceButton.heightAnchor.constraint(equalToConstant: 64),
            spaceButton.widthAnchor.constraint(equalToConstant: 120),
            
            sendButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -padding),
            sendButton.bottomAnchor.constraint(equalTo: deleteButton.bottomAnchor),
            sendButton.widthAnchor.constraint(equalTo: deleteButton.widthAnchor),
            sendButton.heightAnchor.constraint(equalToConstant: 64)
        ])
    }
    
    private func createPhraseButton(text: String) -> UIButton {
        let btn = UIButton(type: .system)
        btn.frame = CGRect(x: 0, y: 0, width: 100, height: 56)
        btn.setTitle(text, for: .normal)
        btn.setTitleColor(.white, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 20, weight: .semibold)
        btn.backgroundColor = whatsAppGreen
        btn.layer.cornerRadius = 20
        btn.tag = 100
        btn.accessibilityIdentifier = "compose:phrase:\(text)"
        btn.addTarget(self, action: #selector(phraseTapped(_:)), for: .touchUpInside)
        return btn
    }
    
    private func createLetterButton(character: Character) -> UIButton {
        let btn = UIButton(type: .system)
        btn.frame = CGRect(x: 0, y: 0, width: 56, height: 56)
        btn.setTitle(String(character), for: .normal)
        btn.setTitleColor(.black, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 24, weight: .semibold)
        btn.backgroundColor = UIColor.white
        btn.layer.cornerRadius = 8
        btn.layer.shadowColor = UIColor.black.cgColor
        btn.layer.shadowOffset = CGSize(width: 0, height: 1)
        btn.layer.shadowOpacity = 0.08
        btn.layer.shadowRadius = 2
        btn.tag = 100
        btn.accessibilityIdentifier = "compose:letter:\(character)"
        btn.addTarget(self, action: #selector(letterTapped(_:)), for: .touchUpInside)
        return btn
    }
    
    private func createActionButton(title: String, color: UIColor, identifier: String) -> UIButton {
        let btn = UIButton(type: .system)
        btn.setTitle(title, for: .normal)
        btn.setTitleColor(.white, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 20, weight: .bold)
        btn.backgroundColor = color
        btn.layer.cornerRadius = 10
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
            btn.frame = CGRect(x: CGFloat(i) * (w + spacing), y: 0, width: w, height: 56)
        }
    }
    
    private func layoutLetterButtons() {
        guard letterContainer.bounds.width > 0 && letterContainer.bounds.height > 0, !letterButtons.isEmpty else { return }
        let cols: CGFloat = 6
        let spacing: CGFloat = 12
        let minButtonSize: CGFloat = 52
        let w = letterContainer.bounds.width
        let h = letterContainer.bounds.height
        var buttonWidth = (w - spacing * (cols - 1)) / cols
        let rows = ceil(CGFloat(letterButtons.count) / cols)
        var buttonHeight = (h - spacing * (rows - 1)) / rows
        buttonWidth = max(minButtonSize, buttonWidth)
        buttonHeight = max(minButtonSize, buttonHeight)
        for (i, btn) in letterButtons.enumerated() {
            let row = CGFloat(i / Int(cols))
            let col = CGFloat(i % Int(cols))
            btn.frame = CGRect(x: col * (buttonWidth + spacing), y: row * (buttonHeight + spacing), width: buttonWidth, height: buttonHeight)
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
        
        let innerDot = UIView(frame: CGRect(x: 20, y: 20, width: 20, height: 20))
        innerDot.backgroundColor = .systemBlue
        innerDot.layer.cornerRadius = 10
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
    
    private func updateComposeBubble() {
        let baseHeight: CGFloat = 72
        let lineHeight: CGFloat = 24
        let estimatedLines = max(1, (messageText.count + 25) / 26)
        let targetHeight = min(baseHeight + CGFloat(estimatedLines - 1) * lineHeight, 140)
        composeBubbleHeightConstraint.constant = targetHeight
    }
    
    @objc private func presetChanged() {
        let index = presetSegmented.selectedSegmentIndex
        if index >= 0 && index < ComposeKeyboardLayout.allCases.count {
            currentPreset = ComposeKeyboardLayout.allCases[index]
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
    
    @objc private func backTapped() {
        guard !isNavigating else { return }
        isNavigating = true
        navigationController?.popViewController(animated: true)
    }
    
    @objc private func sendTapped() {
        performSend()
    }
    
    private func performSend() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return }
        guard !isSending else { return }
        isSending = true
        
        WhatsAppMessageService.shared.sendText(to: contact.phoneNumber, body: text) { [weak self] result in
            guard let self = self else { return }
            self.isSending = false
            
            DispatchQueue.main.async {
                switch result {
                case .success:
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    SpeechService.shared.speak("Message sent to \(self.contact.firstName)")
                    self.messageText = ""
                case .failure:
                    // Fallback: try template
                    WhatsAppMessageService.shared.sendTemplate(to: self.contact.phoneNumber) { [weak self] templateResult in
                        DispatchQueue.main.async {
                            guard let self = self else { return }
                            switch templateResult {
                            case .success:
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                SpeechService.shared.speak("Message sent to \(self.contact.firstName)")
                                self.messageText = ""
                            case .failure:
                                SpeechService.shared.speak("Failed to send")
                            }
                        }
                    }
                }
            }
        }
    }
    
    private var allDwellButtons: [UIButton] {
        var buttons: [UIButton] = [backButton, speakButton]
        buttons.append(contentsOf: phraseButtons)
        buttons.append(contentsOf: letterButtons)
        buttons.append(deleteButton)
        buttons.append(spaceButton)
        buttons.append(sendButton)
        return buttons
    }
}

extension MessageComposeViewController: EyeTrackerDelegate {
    func eyeTracker(_ tracker: EyeTracker, didUpdateGazeScreenPosition screenPosition: CGPoint, lookAtPoint: simd_float3) {
        let absPos = CGPoint(x: view.bounds.width / 2 + screenPosition.x, y: view.bounds.height / 2 + screenPosition.y)
        let r: CGFloat = 30
        var tx = max(r, min(view.bounds.width - r, absPos.x))
        var ty = max(r, min(view.bounds.height - r, absPos.y))
        if let last = lastCursorPosition {
            tx = CGFloat(cursorSmoothingFactor) * last.x + CGFloat(1 - cursorSmoothingFactor) * tx
            ty = CGFloat(cursorSmoothingFactor) * last.y + CGFloat(1 - cursorSmoothingFactor) * ty
        }
        lastCursorPosition = CGPoint(x: tx, y: ty)
        dwellDetector.updateGazePosition(CGPoint(x: tx, y: ty), in: view)
        gazeCursor?.center = CGPoint(x: tx, y: ty)
        if gazeCursor?.isHidden == true, eyeTracker.calibrationData?.isCalibrated == true {
            gazeCursor?.isHidden = false
        }
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

extension MessageComposeViewController: DwellDetectorDelegate {
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
            guard !isNavigating else { currentDwellingButton = nil; return }
            isNavigating = true
            navigationController?.popViewController(animated: true)
            currentDwellingButton = nil
            return
        }
        
        if id == "compose:speak" {
            let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { SpeechService.shared.speak(text) }
            currentDwellingButton = nil
            return
        }
        
        if id.hasPrefix("compose:phrase:") {
            let phrase = String(id.dropFirst("compose:phrase:".count))
            if !messageText.isEmpty { messageText += " " }
            messageText += phrase
            currentDwellingButton = nil
            return
        }
        
        if id.hasPrefix("compose:letter:") {
            let char = id.dropFirst("compose:letter:".count).first ?? Character(" ")
            messageText += String(char)
            currentDwellingButton = nil
            return
        }
        
        if id == "compose:delete" {
            if !messageText.isEmpty { messageText.removeLast() }
            currentDwellingButton = nil
            return
        }
        
        if id == "compose:space" {
            messageText += " "
            currentDwellingButton = nil
            return
        }
        
        if id == "compose:send" {
            performSend()
            currentDwellingButton = nil
        }
    }
    
    func dwellDetector(_ detector: DwellDetector, didCancelDwellOn view: UIView) {
        if let btn = view as? UIButton {
            UIView.animate(withDuration: 0.2) { btn.alpha = 1.0; btn.transform = .identity }
            if currentDwellingButton === btn { currentDwellingButton = nil }
        }
    }
}

extension MessageComposeViewController: ARSCNViewDelegate {
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
        if let pov = sceneView.pointOfView { virtualPhoneNode.transform = pov.transform }
    }
    func renderer(_ renderer: SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor) {
        eyeTracker.reset()
        dwellDetector.reset()
    }
}

extension MessageComposeViewController: ARSessionDelegate {
    func session(_ session: ARSession, didFailWithError error: Error) { Logger.error("AR failed: \(error.localizedDescription)") }
    func sessionWasInterrupted(_ session: ARSession) {}
    func sessionInterruptionEnded(_ session: ARSession) {
        sceneView.session.run(ARFaceTrackingConfiguration(), options: [.resetTracking])
    }
}
