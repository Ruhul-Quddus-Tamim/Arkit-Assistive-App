import AppKit

/// Visual cursor indicator that follows gaze
class CursorView: NSView {
    
    private var cursorLayer: CAShapeLayer?
    private var isDwelling = false
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupCursor()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupCursor()
    }
    
    private func setupCursor() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        
        // Create cursor shape (circle)
        let cursorLayer = CAShapeLayer()
        cursorLayer.fillColor = NSColor.systemBlue.cgColor
        cursorLayer.strokeColor = NSColor.white.cgColor
        cursorLayer.lineWidth = 2.0
        cursorLayer.opacity = 0.8
        
        self.cursorLayer = cursorLayer
        layer?.addSublayer(cursorLayer)
        
        isHidden = true
    }
    
    /// Update cursor position
    /// - Parameter point: Screen coordinates
    func updatePosition(to point: CGPoint) {
        isHidden = false
        
        // Create circle path
        let radius: CGFloat = 15.0
        let rect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
        let path = CGPath(ellipseIn: rect, transform: nil)
        
        cursorLayer?.path = path
        
        // Update color based on dwell state
        if isDwelling {
            cursorLayer?.fillColor = NSColor.systemOrange.cgColor
        } else {
            cursorLayer?.fillColor = NSColor.systemBlue.cgColor
        }
    }
    
    /// Set dwell state (changes cursor appearance)
    /// - Parameter dwelling: Whether user is dwelling on an element
    func setDwelling(_ dwelling: Bool) {
        isDwelling = dwelling
        
        if dwelling {
            cursorLayer?.fillColor = NSColor.systemOrange.cgColor
            // Add pulsing animation
            let pulse = CABasicAnimation(keyPath: "transform.scale")
            pulse.fromValue = 1.0
            pulse.toValue = 1.2
            pulse.duration = 0.5
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            cursorLayer?.add(pulse, forKey: "pulse")
        } else {
            cursorLayer?.fillColor = NSColor.systemBlue.cgColor
            cursorLayer?.removeAnimation(forKey: "pulse")
        }
    }
    
    /// Hide cursor
    func hide() {
        isHidden = true
    }
    
    /// Show cursor
    func show() {
        isHidden = false
    }
}
