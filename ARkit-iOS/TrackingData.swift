import Foundation
import simd
import QuartzCore

/// Shared data structure for gaze tracking data transmitted from iPhone to Mac
struct GazeTrackingData: Codable {
    let timestamp: TimeInterval
    let gazeVector: GazeVector
    let faceTransform: FaceTransform
    let eyeBlinkLeft: Float
    let eyeBlinkRight: Float
    let eyesOpen: Bool
    
    init(timestamp: TimeInterval = CACurrentMediaTime(),
         gazeVector: SIMD3<Float>,
         faceTransform: simd_float4x4,
         eyeBlinkLeft: Float,
         eyeBlinkRight: Float,
         eyesOpen: Bool) {
        self.timestamp = timestamp
        self.gazeVector = GazeVector(x: gazeVector.x, y: gazeVector.y, z: gazeVector.z)
        self.faceTransform = FaceTransform(matrix: faceTransform)
        self.eyeBlinkLeft = eyeBlinkLeft
        self.eyeBlinkRight = eyeBlinkRight
        self.eyesOpen = eyesOpen
    }
}

/// Codable wrapper for SIMD3<Float>
struct GazeVector: Codable {
    let x: Float
    let y: Float
    let z: Float
    
    var simd3: SIMD3<Float> {
        SIMD3<Float>(x, y, z)
    }
    
    init(x: Float, y: Float, z: Float) {
        self.x = x
        self.y = y
        self.z = z
    }
}

/// Codable wrapper for simd_float4x4
struct FaceTransform: Codable {
    let flat: [Float]
    
    var matrix: simd_float4x4 {
        precondition(flat.count == 16, "FaceTransform.flat must have 16 elements")
        let c0 = SIMD4<Float>(flat[0], flat[1], flat[2], flat[3])
        let c1 = SIMD4<Float>(flat[4], flat[5], flat[6], flat[7])
        let c2 = SIMD4<Float>(flat[8], flat[9], flat[10], flat[11])
        let c3 = SIMD4<Float>(flat[12], flat[13], flat[14], flat[15])
        return simd_float4x4(columns: (c0, c1, c2, c3))
    }
    
    init(matrix: simd_float4x4) {
        let c0 = matrix.columns.0
        let c1 = matrix.columns.1
        let c2 = matrix.columns.2
        let c3 = matrix.columns.3
        self.flat = [c0.x, c0.y, c0.z, c0.w,
                     c1.x, c1.y, c1.z, c1.w,
                     c2.x, c2.y, c2.z, c2.w,
                     c3.x, c3.y, c3.z, c3.w]
    }
    
    enum CodingKeys: String, CodingKey { case flat }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.flat = try container.decode([Float].self, forKey: .flat)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(flat, forKey: .flat)
    }
}

