import UIKit
import ARKit
import SceneKit

class MessagesViewController: UIViewController {
    
    private var backButton: UIButton!
    private var contactsContainer: UIView!
    private var contactButtons: [UIButton] = []
    
    private let contacts: [Contact] = [
        Contact(firstName: "Ruhul", phoneNumber: "601127388501")
    ]
    
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
    private var cursorSmoothingFactor: Float = 0.8
    private var lastCursorPosition: CGPoint?
    
    // WhatsApp-style colors
    private let headerGreen = UIColor(red: 0.07, green: 0.37, blue: 0.33, alpha: 1.0)   // #128C7E
    private let listBackground = UIColor(red: 0.97, green: 0.97, blue: 0.97, alpha: 1.0) // #F7F7F7
    private let rowBackground = UIColor.white
    private let dividerColor = UIColor(red: 0.89, green: 0.89, blue: 0.91, alpha: 1.0)   // #E4E4E8
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = listBackground
        
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
        layoutContactButtons()
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
    
    private func setupUI() {
        let padding: CGFloat = 16
        
        // Header bar (WhatsApp-style dark green)
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
        
        let titleLabel = UILabel()
        titleLabel.text = "Chats"
        titleLabel.font = .systemFont(ofSize: 26, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(titleLabel)
        
        contactsContainer = UIView()
        contactsContainer.backgroundColor = listBackground
        contactsContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contactsContainer)
        
        for (index, contact) in contacts.enumerated() {
            let row = createContactRow(contact: contact, tag: index)
            contactsContainer.addSubview(row.container)
            contactButtons.append(row.button)
        }
        
        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 80),
            
            backButton.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: padding),
            backButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 100),
            backButton.heightAnchor.constraint(equalToConstant: 70),
            
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: backButton.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: headerView.trailingAnchor, constant: -100),
            titleLabel.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            
            contactsContainer.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 32),
            contactsContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contactsContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contactsContainer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }
    
    private func createContactRow(contact: Contact, tag: Int) -> (container: UIView, button: UIButton) {
        let container = UIView()
        container.backgroundColor = rowBackground
        container.translatesAutoresizingMaskIntoConstraints = false
        
        let btn = UIButton(type: .system)
        btn.backgroundColor = rowBackground
        btn.tag = tag
        btn.accessibilityIdentifier = "contact:\(tag)"
        btn.addTarget(self, action: #selector(contactTapped(_:)), for: .touchUpInside)
        btn.translatesAutoresizingMaskIntoConstraints = false
        
        let avatarView = UIView()
        avatarView.backgroundColor = headerGreen
        avatarView.layer.cornerRadius = 32
        avatarView.isUserInteractionEnabled = false
        
        let initialLabel = UILabel()
        initialLabel.text = String(contact.firstName.prefix(1)).uppercased()
        initialLabel.font = .systemFont(ofSize: 28, weight: .bold)
        initialLabel.textColor = .white
        initialLabel.isUserInteractionEnabled = false
        
        let nameLabel = UILabel()
        nameLabel.text = contact.firstName
        nameLabel.font = .systemFont(ofSize: 24, weight: .semibold)
        nameLabel.textColor = .black
        nameLabel.isUserInteractionEnabled = false
        
        btn.addSubview(avatarView)
        btn.addSubview(initialLabel)
        btn.addSubview(nameLabel)
        container.addSubview(btn)
        
        NSLayoutConstraint.activate([
            btn.topAnchor.constraint(equalTo: container.topAnchor),
            btn.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            btn.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            btn.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            avatarView.leadingAnchor.constraint(equalTo: btn.leadingAnchor, constant: 16),
            avatarView.centerYAnchor.constraint(equalTo: btn.centerYAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 64),
            avatarView.heightAnchor.constraint(equalToConstant: 64),
            initialLabel.centerXAnchor.constraint(equalTo: avatarView.centerXAnchor),
            initialLabel.centerYAnchor.constraint(equalTo: avatarView.centerYAnchor),
            nameLabel.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 16),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: btn.trailingAnchor, constant: -16),
            nameLabel.centerYAnchor.constraint(equalTo: btn.centerYAnchor)
        ])
        avatarView.translatesAutoresizingMaskIntoConstraints = false
        initialLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        
        return (container, btn)
    }
    
    private func layoutContactButtons() {
        guard contactsContainer.bounds.width > 0 else { return }
        
        let rowHeight: CGFloat = 88
        let topPadding: CGFloat = 20
        for (index, btn) in contactButtons.enumerated() {
            guard let container = btn.superview else { continue }
            let y = topPadding + CGFloat(index) * rowHeight
            container.frame = CGRect(x: 0, y: y, width: contactsContainer.bounds.width, height: rowHeight)
            container.layoutIfNeeded()
            
            container.subviews.filter { $0.tag == 999 }.forEach { $0.removeFromSuperview() }
            let divider = UIView()
            divider.backgroundColor = dividerColor
            divider.frame = CGRect(x: 80, y: rowHeight - 0.5, width: contactsContainer.bounds.width - 80, height: 0.5)
            divider.tag = 999
            divider.isUserInteractionEnabled = false
            container.addSubview(divider)
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
    
    @objc private func backTapped() {
        guard !isNavigating else { return }
        isNavigating = true
        navigationController?.popViewController(animated: true)
    }
    
    @objc private func contactTapped(_ sender: UIButton) {
        handleContactSelection(tag: sender.tag)
    }
    
    private func handleContactSelection(tag: Int) {
        guard tag >= 0 && tag < contacts.count, !isNavigating else { return }
        isNavigating = true
        let contact = contacts[tag]
        let composeVC = MessageComposeViewController(contact: contact)
        navigationController?.pushViewController(composeVC, animated: true)
    }
    
    private var allDwellButtons: [UIButton] {
        var buttons: [UIButton] = [backButton]
        buttons.append(contentsOf: contactButtons)
        return buttons
    }
}

extension MessagesViewController: EyeTrackerDelegate {
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

extension MessagesViewController: DwellDetectorDelegate {
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
        
        guard let btn = view as? UIButton, allDwellButtons.contains(btn) else {
            currentDwellingButton = nil
            return
        }
        
        UIView.animate(withDuration: 0.2) {
            btn.alpha = 1.0
            btn.transform = .identity
        }
        
        if btn === backButton {
            guard !isNavigating else { currentDwellingButton = nil; return }
            isNavigating = true
            navigationController?.popViewController(animated: true)
        } else if let id = btn.accessibilityIdentifier, id.hasPrefix("contact:") {
            let tagStr = id.replacingOccurrences(of: "contact:", with: "")
            if let tag = Int(tagStr) {
                handleContactSelection(tag: tag)
            }
        }
        currentDwellingButton = nil
    }
    func dwellDetector(_ detector: DwellDetector, didCancelDwellOn view: UIView) {
        if let btn = view as? UIButton {
            UIView.animate(withDuration: 0.2) { btn.alpha = 1.0; btn.transform = .identity }
            if currentDwellingButton === btn { currentDwellingButton = nil }
        }
    }
}

extension MessagesViewController: ARSCNViewDelegate {
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

extension MessagesViewController: ARSessionDelegate {
    func session(_ session: ARSession, didFailWithError error: Error) { Logger.error("AR failed: \(error.localizedDescription)") }
    func sessionWasInterrupted(_ session: ARSession) {}
    func sessionInterruptionEnded(_ session: ARSession) {
        sceneView.session.run(ARFaceTrackingConfiguration(), options: [.resetTracking])
    }
}
