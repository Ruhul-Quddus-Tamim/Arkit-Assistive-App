import UIKit

class IconCollectionViewCell: UICollectionViewCell {
    static let identifier = "IconCollectionViewCell"
    
    private let iconImageView = UIImageView()
    private let progressView = DwellProgressView()
    private var highlightLayer: CALayer?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        // Set tag for dwell detection
        tag = 100
        
        // Configure cell
        contentView.backgroundColor = .clear
        contentView.layer.cornerRadius = 12
        contentView.clipsToBounds = true
        
        // Icon image view
        iconImageView.contentMode = .scaleAspectFit
        iconImageView.tintColor = .white
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(iconImageView)
        
        // Progress view (initially hidden)
        progressView.isHidden = true
        progressView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(progressView)
        
        NSLayoutConstraint.activate([
            iconImageView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            iconImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconImageView.widthAnchor.constraint(equalTo: contentView.widthAnchor, multiplier: 0.5),
            iconImageView.heightAnchor.constraint(equalTo: contentView.heightAnchor, multiplier: 0.5),
            
            progressView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            progressView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            progressView.widthAnchor.constraint(equalTo: contentView.widthAnchor, multiplier: 1.2),
            progressView.heightAnchor.constraint(equalTo: contentView.heightAnchor, multiplier: 1.2)
        ])
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        removeHighlight()
        hideProgress()
    }
    
    func configure(with icon: MenuIcon) {
        contentView.backgroundColor = icon.backgroundColor
        
        // Set icon image
        let config = UIImage.SymbolConfiguration(pointSize: 40, weight: .medium)
        iconImageView.image = UIImage(systemName: icon.iconName, withConfiguration: config)
        iconImageView.tintColor = .white
        
        // Accessibility
        accessibilityLabel = icon.title
        isAccessibilityElement = true
    }
    
    /// Show highlight effect when dwelling
    func showHighlight() {
        if highlightLayer == nil {
            let layer = CALayer()
            layer.frame = bounds
            layer.cornerRadius = 12
            layer.backgroundColor = UIColor.white.withAlphaComponent(0.2).cgColor
            contentView.layer.insertSublayer(layer, at: 0)
            highlightLayer = layer
        }
        
        // Animate highlight appearance
        highlightLayer?.opacity = 0
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.2)
        highlightLayer?.opacity = 1.0
        CATransaction.commit()
    }
    
    /// Remove highlight effect
    func removeHighlight() {
        highlightLayer?.removeFromSuperlayer()
        highlightLayer = nil
    }
    
    /// Show progress indicator
    func showProgress() {
        progressView.show()
    }
    
    /// Update progress (0.0 to 1.0)
    func updateProgress(_ progress: Float) {
        progressView.setProgress(progress)
    }
    
    /// Hide progress indicator
    func hideProgress() {
        progressView.hide()
    }
    
    /// Animate selection/press
    func animatePress() {
        UIView.animate(withDuration: 0.1, animations: {
            self.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)
        }) { _ in
            UIView.animate(withDuration: 0.1) {
                self.transform = .identity
            }
        }
    }
}
