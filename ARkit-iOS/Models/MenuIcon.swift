import UIKit

/// Types of icons available in the menu
enum IconType {
    case headProfile      // Red, head with speech/audio
    case shoppingCart     // Blue, shopping cart
    case phone           // Green, phone/speech bubble
    case alarm           // Yellow, alarm/siren
    case playButton      // Red, play button
    case turntable       // Black, turntable/vinyl
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
        case .shoppingCart: return "Shopping"
        case .phone: return "Communication"
        case .alarm: return "Alerts"
        case .playButton: return "Media Playback"
        case .turntable: return "Music"
        }
    }
    
    /// SF Symbol name for the icon
    var iconName: String {
        switch iconType {
        case .headProfile: return "person.wave.2.fill"
        case .shoppingCart: return "cart.fill"
        case .phone: return "message.fill"
        case .alarm: return "bell.fill"
        case .playButton: return "play.circle.fill"
        case .turntable: return "music.note"
        }
    }
    
    /// All 6 grid icons as defined in the reference design
    static let allIcons: [MenuIcon] = [
        MenuIcon(
            id: "head_profile",
            iconType: .headProfile,
            backgroundColor: UIColor(red: 1.0, green: 0.23, blue: 0.19, alpha: 1.0), // #FF3B30
            destinationType: .placeholder
        ),
        MenuIcon(
            id: "shopping_cart",
            iconType: .shoppingCart,
            backgroundColor: UIColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 1.0), // #007AFF
            destinationType: .placeholder
        ),
        MenuIcon(
            id: "phone",
            iconType: .phone,
            backgroundColor: UIColor(red: 0.20, green: 0.78, blue: 0.35, alpha: 1.0), // #34C759
            destinationType: .placeholder
        ),
        MenuIcon(
            id: "alarm",
            iconType: .alarm,
            backgroundColor: UIColor(red: 1.0, green: 0.80, blue: 0.0, alpha: 1.0), // #FFCC00
            destinationType: .placeholder
        ),
        MenuIcon(
            id: "play_button",
            iconType: .playButton,
            backgroundColor: UIColor(red: 1.0, green: 0.23, blue: 0.19, alpha: 1.0), // #FF3B30
            destinationType: .placeholder
        ),
        MenuIcon(
            id: "turntable",
            iconType: .turntable,
            backgroundColor: UIColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0), // #000000
            destinationType: .placeholder
        )
    ]
}
