import AppKit

/// Custom button view that shows dwell progress
class DwellButton: NSButton {
    
    private var progressLayer: CALayer?
    private var progress: Float = 0.0 {
        didSet {
            updateProgressDisplay()
        }
    }
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupProgressIndicator()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupProgressIndicator()
    }
    
    private func setupProgressIndicator() {
        wantsLayer = true
        
        // Create progress layer
        let progressLayer = CALayer()
        progressLayer.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.3).cgColor
        progressLayer.frame = bounds
        progressLayer.anchorPoint = CGPoint(x: 0, y: 0)
        progressLayer.isHidden = true
        
        self.progressLayer = progressLayer
        layer?.addSublayer(progressLayer)
    }
    
    override func layout() {
        super.layout()
        progressLayer?.frame = bounds
    }
    
    /// Update dwell progress (0.0 to 1.0)
    /// - Parameter progress: Progress value
    func updateDwellProgress(_ progress: Float) {
        self.progress = max(0.0, min(1.0, progress))
        
        if progress > 0.0 {
            progressLayer?.isHidden = false
        } else {
            progressLayer?.isHidden = true
        }
    }
    
    private func updateProgressDisplay() {
        guard let progressLayer = progressLayer else { return }
        
        let width = bounds.width * CGFloat(progress)
        progressLayer.frame = CGRect(x: 0, y: 0, width: width, height: bounds.height)
    }
    
    /// Reset progress indicator
    func resetProgress() {
        progress = 0.0
        progressLayer?.isHidden = true
    }
    
    /// Highlight button (when hovered)
    func highlight() {
        layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.2).cgColor
    }
    
    /// Remove highlight
    func removeHighlight() {
        layer?.backgroundColor = NSColor.clear.cgColor
    }
}
