import Foundation

/// Serializes and deserializes gaze tracking data for network transmission
class DataSerializer {
    
    /// Serialize gaze tracking data to JSON Data
    /// - Parameter data: GazeTrackingData to serialize
    /// - Returns: JSON Data ready for network transmission
    static func serialize(_ data: GazeTrackingData) -> Data? {
        let encoder = JSONEncoder()
        // Default encoding is already compact (no extra whitespace)
        return try? encoder.encode(data)
    }
    
    /// Deserialize JSON Data to GazeTrackingData
    /// - Parameter data: JSON Data received from network
    /// - Returns: GazeTrackingData if deserialization succeeds
    static func deserialize(_ data: Data) -> GazeTrackingData? {
        let decoder = JSONDecoder()
        return try? decoder.decode(GazeTrackingData.self, from: data)
    }
}
