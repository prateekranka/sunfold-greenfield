import Foundation

/// Scene complexity readouts captured alongside frame timings.
struct SceneScaleSnapshot: Codable, Sendable {
    var simulationUnits: Int
    var simulationBuildings: Int
    var simulationDeposits: Int
    var presentedEntities: Int
    var simulationTick: UInt64
    var mapID: String
    var cameraZoom: Float

    /// RealityKit does not expose per-frame draw-call or material counts through
    /// public API without Instruments. These fields are reserved for future hook-up.
    var drawCalls: Int? = nil
    var materialCount: Int? = nil
    var meshCount: Int? = nil
}
