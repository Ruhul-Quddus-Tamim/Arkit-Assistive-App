import UIKit

class DetailViewController: UIViewController {
    
    private var titleLabel: UILabel!
    private var descriptionLabel: UILabel!
    private var icon: MenuIcon?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .systemBackground
        
        setupUI()
    }
    
    func configure(with icon: MenuIcon) {
        self.icon = icon
        titleLabel?.text = icon.title
        descriptionLabel?.text = "This is a placeholder screen for \(icon.title).\n\nFunctionality will be implemented based on your requirements."
    }
    
    private func setupUI() {
        titleLabel = UILabel()
        titleLabel.text = "Detail"
        titleLabel.font = .systemFont(ofSize: 28, weight: .bold)
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)
        
        descriptionLabel = UILabel()
        descriptionLabel.text = "Placeholder screen"
        descriptionLabel.font = .systemFont(ofSize: 16)
        descriptionLabel.textAlignment = .center
        descriptionLabel.numberOfLines = 0
        descriptionLabel.textColor = .secondaryLabel
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(descriptionLabel)
        
        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 40),
            
            descriptionLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            descriptionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 20),
            descriptionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            descriptionLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40)
        ])
        
        // Navigation bar
        navigationItem.title = "Detail"
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(closeTapped)
        )
    }
    
    @objc private func closeTapped() {
        navigationController?.popViewController(animated: true)
    }
}
