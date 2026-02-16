import UIKit

/// Circular progress view for showing dwell progress
class DwellProgressView: UIView {
    private var progressLayer: CAShapeLayer!
    private var backgroundLayer: CAShapeLayer!
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        backgroundColor = .clear
        
        // Background circle (subtle)
        backgroundLayer = CAShapeLayer()
        backgroundLayer.strokeColor = UIColor.white.withAlphaComponent(0.3).cgColor
        backgroundLayer.fillColor = UIColor.clear.cgColor
        backgroundLayer.lineWidth = 3.0
        layer.addSublayer(backgroundLayer)
        
        // Progress circle
        progressLayer = CAShapeLayer()
        progressLayer.strokeColor = UIColor.systemBlue.cgColor
        progressLayer.fillColor = UIColor.clear.cgColor
        progressLayer.lineWidth = 3.0
        progressLayer.lineCap = .round
        layer.addSublayer(progressLayer)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        updatePaths()
    }
    
    private func updatePaths() {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = min(bounds.width, bounds.height) / 2 - 2
        let path = UIBezierPath(arcCenter: center, radius: radius, startAngle: -CGFloat.pi / 2, endAngle: 3 * CGFloat.pi / 2, clockwise: true)
        
        backgroundLayer.path = path.cgPath
        progressLayer.path = path.cgPath
    }
    
    /// Update progress (0.0 to 1.0)
    func setProgress(_ progress: Float) {
        progressLayer.strokeEnd = CGFloat(progress)
        
        // Animate color change as progress increases
        if progress > 0.8 {
            progressLayer.strokeColor = UIColor.systemGreen.cgColor
        } else if progress > 0.5 {
            progressLayer.strokeColor = UIColor.systemYellow.cgColor
        } else {
            progressLayer.strokeColor = UIColor.systemBlue.cgColor
        }
    }
    
    /// Show the progress view
    func show() {
        isHidden = false
        alpha = 0
        transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
        
        UIView.animate(withDuration: 0.2) {
            self.alpha = 1.0
            self.transform = .identity
        }
    }
    
    /// Hide the progress view
    func hide() {
        UIView.animate(withDuration: 0.2, animations: {
            self.alpha = 0
            self.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
        }) { _ in
            self.isHidden = true
            self.transform = .identity
            self.setProgress(0)
        }
    }
}
