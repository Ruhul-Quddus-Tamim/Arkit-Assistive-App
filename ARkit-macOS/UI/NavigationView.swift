import AppKit

/// Main navigation view with selectable buttons
class NavigationView: NSView {
    
    weak var delegate: NavigationViewDelegate?
    
    private var buttons: [DwellButton] = []
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }
    
    private func setupUI() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        
        // Create sample buttons
        let buttonTitles = ["Home", "Search", "Settings", "About"]
        
        var yPosition: CGFloat = frame.height - 60
        
        for (index, title) in buttonTitles.enumerated() {
            let button = DwellButton(frame: NSRect(x: 20, y: yPosition, width: 200, height: 40))
            button.title = title
            button.bezelStyle = .rounded
            button.target = self
            button.action = #selector(buttonClicked(_:))
            button.tag = 100 // Mark as selectable
            button.identifier = NSUserInterfaceItemIdentifier(title)
            
            addSubview(button)
            buttons.append(button)
            
            yPosition -= 50
        }
    }
    
    @objc private func buttonClicked(_ sender: DwellButton) {
        delegate?.navigationView(self, didSelectButton: sender)
    }
    
    /// Get button at screen coordinates
    /// - Parameter point: Screen coordinates
    /// - Returns: Button view if point is over a button, nil otherwise
    func button(at point: CGPoint) -> NSView? {
        let viewPoint = convert(point, from: nil)
        
        for button in buttons {
            if button.frame.contains(viewPoint) {
                return button
            }
        }
        
        return nil
    }
    
    /// Update dwell progress for a button
    /// - Parameters:
    ///   - button: Button to update
    ///   - progress: Progress value (0.0 to 1.0)
    func updateDwellProgress(for button: NSView, progress: Float) {
        if let dwellButton = button as? DwellButton {
            dwellButton.updateDwellProgress(progress)
        }
    }
    
    /// Highlight button
    /// - Parameter button: Button to highlight
    func highlightButton(_ button: NSView) {
        if let dwellButton = button as? DwellButton {
            dwellButton.highlight()
        }
    }
    
    /// Remove highlight from button
    /// - Parameter button: Button to unhighlight
    func removeHighlight(from button: NSView) {
        if let dwellButton = button as? DwellButton {
            dwellButton.removeHighlight()
            dwellButton.resetProgress()
        }
    }
}

/// Protocol for navigation view events
protocol NavigationViewDelegate: AnyObject {
    func navigationView(_ view: NavigationView, didSelectButton button: NSButton)
}
