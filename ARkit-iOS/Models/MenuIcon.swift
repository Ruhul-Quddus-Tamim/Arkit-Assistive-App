import UIKit

/// Types of icons available in the menu
enum IconType {
    case headProfile      // Red, head with speech/audio
    case phone           // Green, phone/speech bubble
    case computerAgent   // Purple, Computer Use Agent
}

/// Destination types for navigation
enum DestinationType {
    case detailScreen    // Navigate to detail screen
    case calibration     // Navigate to calibration
    case camera          // Navigate to camera view
    case placeholder     // Placeholder for future implementation
}

/// Model representing a menu icon
struct MenuIcon {
    let id: String
    let iconType: IconType
    let backgroundColor: UIColor
    let destinationType: DestinationType
    
    /// Title for the icon (optional, for accessibility)
    var title: String {
        switch iconType {
        case .headProfile: return "Voice Input"
        case .phone: return "Communication"
        case .computerAgent: return "Computer Agent"
        }
    }
    
    /// SF Symbol name for the icon
    var iconName: String {
        switch iconType {
        case .headProfile: return "person.wave.2.fill"
        case .phone: return "message.fill"
        case .computerAgent: return "desktopcomputer"
        }
    }
    
    /// Main grid icons (Voice Input, Messages, Computer Agent)
    static let allIcons: [MenuIcon] = [
        MenuIcon(
            id: "head_profile",
            iconType: .headProfile,
            backgroundColor: UIColor(red: 1.0, green: 0.23, blue: 0.19, alpha: 1.0), // #FF3B30
            destinationType: .placeholder
        ),
        MenuIcon(
            id: "phone",
            iconType: .phone,
            backgroundColor: UIColor(red: 0.20, green: 0.78, blue: 0.35, alpha: 1.0), // #34C759
            destinationType: .placeholder
        ),
        MenuIcon(
            id: "computer_agent",
            iconType: .computerAgent,
            backgroundColor: UIColor(red: 0.35, green: 0.34, blue: 0.84, alpha: 1.0), // #5856D6
            destinationType: .placeholder
        )
    ]
}
