import AppKit
import CoreGraphics

class ViewController: NSViewController {
    
    private var connectionStatusLabel: NSTextField!
    private var containerView: NSView!
    private var serverStarted = false
    
    private let networkServer = TrackingDataServer()
    private let computerScreenMapper = ComputerScreenMapper()
    private let fallbackScreenMapper = ScreenMapper() // For backward compatibility
    private let cursorController = CursorController()
    private let dwellDetector = DwellDetector()
    private var cursorView: CursorView?
    private var navigationView: NavigationView?
    
    override func loadView() {
        view = NSView()
        view.wantsLayer = true
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupComponents()
        startServer()
    }
    
    override func viewWillAppear() {
        super.viewWillAppear()
        // Ensure cursor view covers entire window
        if let window = view.window {
            cursorView?.frame = window.contentView?.bounds ?? view.bounds
        }
    }
    
    private func setupUI() {
        // Create connection status label
        connectionStatusLabel = NSTextField(labelWithString: "Waiting for iPhone...")
        connectionStatusLabel.textColor = .systemOrange
        connectionStatusLabel.font = .systemFont(ofSize: 14, weight: .medium)
        connectionStatusLabel.frame = NSRect(x: 20, y: view.bounds.height - 40, width: view.bounds.width - 40, height: 20)
        connectionStatusLabel.autoresizingMask = [.width, .minYMargin]
        view.addSubview(connectionStatusLabel)
        
        // Create container view for navigation
        containerView = NSView()
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        containerView.frame = NSRect(x: 0, y: 0, width: view.bounds.width, height: view.bounds.height - 60)
        containerView.autoresizingMask = [.width, .height]
        view.addSubview(containerView)
        
        // Create cursor view (overlay)
        let cursor = CursorView(frame: view.bounds)
        cursor.autoresizingMask = [.width, .height]
        view.addSubview(cursor, positioned: .above, relativeTo: nil)
        cursorView = cursor
        
        // Create navigation view
        let navView = NavigationView(frame: containerView.bounds)
        navView.autoresizingMask = [.width, .height]
        navView.delegate = self
        containerView.addSubview(navView)
        navigationView = navView
    }
    
    private func setupComponents() {
        // Set up network server delegate
        networkServer.delegate = self
        
        // Set up dwell detector
        dwellDetector.setDwellThreshold(1.5) // 1.5 seconds
        dwellDetector.delegate = self
        
        // Set up computer screen mapper smoothing
        computerScreenMapper.setSmoothingFactor(0.7)
        
        // Set up fallback screen mapper smoothing (for backward compatibility)
        fallbackScreenMapper.setSmoothingFactor(0.7)
        
        // Set up cursor controller update rate (~30 Hz)
        cursorController.setMinUpdateInterval(0.033)
    }
    
    private func startServer() {
        guard !serverStarted else {
            print("Mac: Server start already called")
            return
        }
        serverStarted = true
        networkServer.start()
        updateConnectionStatus("Server started. Waiting for iPhone...", color: .systemOrange)
    }
    
    private func updateConnectionStatus(_ text: String, color: NSColor) {
        DispatchQueue.main.async {
            self.connectionStatusLabel.stringValue = text
            self.connectionStatusLabel.textColor = color
        }
    }
    
    private func processGazeData(_ data: GazeTrackingData) {
        guard data.eyesOpen else {
            // Eyes closed, hide cursor
            DispatchQueue.main.async {
                self.cursorView?.hide()
                self.dwellDetector.reset()
                self.cursorController.reset()
            }
            return
        }
        
        // Use calibrated screen coordinates from iPhone if available, otherwise fall back to old method
        let screenPoint: CGPoint
        
        if let iphoneScreenPosition = data.screenPosition?.cgPoint,
           let phoneScreenSize = data.phoneScreenSize?.cgSize {
            // Use new method: map iPhone calibrated coordinates to macOS screen
            screenPoint = computerScreenMapper.mapiPhoneToComputerScreen(
                iphoneScreenPosition: iphoneScreenPosition,
                phoneScreenSize: phoneScreenSize
            )
        } else {
            // Fallback to old method: map from gaze vector (less accurate)
            // This maintains backward compatibility if screenPosition is not available
            screenPoint = fallbackScreenMapper.mapGazeToScreen(
                gazeVector: data.gazeVector.simd3,
                faceTransform: data.faceTransform.matrix
            )
        }
        
        // Move actual system cursor
        cursorController.moveCursor(to: screenPoint)
        
        // Update visual cursor overlay
        DispatchQueue.main.async {
            self.cursorView?.updatePosition(to: screenPoint)
            self.cursorView?.show()
            
            // Update dwell detection
            self.dwellDetector.updateGazePosition(screenPoint)
        }
    }
}

// MARK: - TrackingDataServerDelegate
extension ViewController: TrackingDataServerDelegate {
    
    func server(_ server: TrackingDataServer, didReceiveGazeData data: GazeTrackingData) {
        processGazeData(data)
    }
    
    func server(_ server: TrackingDataServer, didConnect client: String) {
        updateConnectionStatus("Connected to iPhone", color: .systemGreen)
    }
    
    func server(_ server: TrackingDataServer, didDisconnect client: String) {
        updateConnectionStatus("Disconnected. Waiting for iPhone...", color: .systemOrange)
        
        DispatchQueue.main.async {
            self.cursorView?.hide()
            self.dwellDetector.reset()
            self.computerScreenMapper.reset()
            self.fallbackScreenMapper.reset()
            self.cursorController.reset()
        }
    }
    
    func server(_ server: TrackingDataServer, didEncounterError error: Error) {
        updateConnectionStatus("Error: \(error.localizedDescription)", color: .systemRed)
    }
}

// MARK: - DwellDetectorDelegate
extension ViewController: DwellDetectorDelegate {
    
    func dwellDetector(_ detector: DwellDetector, didStartDwellingOn view: NSView) {
        navigationView?.highlightButton(view)
        cursorView?.setDwelling(true)
    }
    
    func dwellDetector(_ detector: DwellDetector, didUpdateDwellProgress progress: Float, on view: NSView) {
        navigationView?.updateDwellProgress(for: view, progress: progress)
    }
    
    func dwellDetector(_ detector: DwellDetector, didCompleteDwellOn view: NSView) {
        // Simulate button click
        if let button = view as? NSButton {
            button.performClick(nil)
        }
        
        navigationView?.removeHighlight(from: view)
        cursorView?.setDwelling(false)
    }
    
    func dwellDetector(_ detector: DwellDetector, didCancelDwellOn view: NSView) {
        navigationView?.removeHighlight(from: view)
        cursorView?.setDwelling(false)
    }
}

// MARK: - NavigationViewDelegate
extension ViewController: NavigationViewDelegate {
    
    func navigationView(_ view: NavigationView, didSelectButton button: NSButton) {
        let alert = NSAlert()
        alert.messageText = "Button Selected"
        alert.informativeText = "You selected: \(button.title)"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

