import Foundation
import AVFoundation

/// Service for text-to-speech functionality using AVSpeechSynthesizer
class SpeechService {
    static let shared = SpeechService()
    
    private let synthesizer: AVSpeechSynthesizer
    
    private init() {
        synthesizer = AVSpeechSynthesizer()
    }
    
    /// Speak the given text
    /// - Parameter text: The text to speak
    func speak(_ text: String) {
        // Validate text is not empty
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            #if DEBUG
            print("SpeechService: Attempted to speak empty text")
            #endif
            return
        }
        
        // Stop any current speech
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        
        // Create utterance
        let utterance = AVSpeechUtterance(string: trimmedText)
        
        // Configure voice (defaults to system language)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        
        // Configure speech parameters
        utterance.rate = 0.5 // Normal speech rate (0.0 to 1.0)
        utterance.pitchMultiplier = 1.0 // Normal pitch (0.5 to 2.0)
        utterance.volume = 1.0 // Full volume (0.0 to 1.0)
        
        // Speak
        synthesizer.speak(utterance)
    }
    
    /// Stop current speech
    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }
    
    /// Check if currently speaking
    var isSpeaking: Bool {
        return synthesizer.isSpeaking
    }
}
