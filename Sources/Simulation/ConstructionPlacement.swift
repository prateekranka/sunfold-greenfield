import Foundation
import simd

/// Footprint legality and placeable kinds for G2 land construction.
///
/// Soft ghost feel is locked (#11). Explored fog paint is not shipped yet —
/// G2a treats the player's home land as the explored region for placement.
@MainActor
enum ConstructionPlacement {

    /// Live ghost while the player is placing. Presentation-only.
    struct Session: Equatable {
        var kind: BuildingKind
        var position: WorldPoint
        var isLegal: Bool
        /// Seconds since session start (presentation pulse / age).
        var age: Double = 0
        /// Brief illegal flash (visual only).
        var denyUntil: Double = 0
        /// Successful place flash; foundation already exists in sim.
        var placeUntil: Double = 0
    }

    /// Everything a citizen may put down.
    ///
    /// The Formation Yard, Expansion Outpost and Dawn Loom were added to the
    /// command grid by CP-C1 and **not** added here, so all three tiles read as
    /// affordable, lit and live, and tapping them did nothing at all —
    /// `beginBuildGhost` bounced off this list without a word. Found on device
    /// during CP-C4, trying to build the Yard that trains the Vanguard that
    /// captures the Dominion: the player could not reach *either* win path,
    /// because the only military building in the game was unbuildable.
    ///
    /// The Civilization Core is not here because nobody builds one, and the
    /// Dominion Spire is not here because nobody owns one.
    static var placeableKinds: [BuildingKind] {
        [.farm, .matterExtractor, .dwelling, .formationYard, .lumenSpire, .expansionOutpost, .dawnLoom]
    }

    /// How far outside Core / deposit / building discs a ghost must stay.
    private static let clearance: Float = 0.75
    /// Land field must clear this everywhere under the footprint.
    private static let minLand: Float = 0.2

    /// Axis-aligned half-extents for rectangular footprints. `nil` → circle.
    /// Farm matches the authored 7 × 7 m plot mesh.
    static func halfExtents(for kind: BuildingKind) -> SIMD2<Float>? {
        switch kind {
        case .farm: SIMD2(3.5, 3.5)
        default: nil
        }
    }

    /// Conservative radius for distance checks against circular blockers.
    static func collisionRadius(for kind: BuildingKind) -> Float {
        if let half = halfExtents(for: kind) {
            return simd_length(half)
        }
        return kind.footprintRadius
    }

    /// True when the entire footprint sits on the player's home land, clear of
    /// void and other footprints. Green only when every sample passes.
    static func isLegal(
        kind: BuildingKind,
        at point: WorldPoint,
        in simulation: SkirmishSimulation
    ) -> Bool {
        let map = simulation.map
        let radius = collisionRadius(for: kind)
        let homeRegion = simulation.playerFaction.homeRegion

        for sample in footprintSamples(kind: kind, center: point) {
            guard map.landField(at: sample) > minLand else { return false }
            guard map.region(at: sample) == homeRegion else { return false }
        }

        for building in simulation.buildings.values {
            let need = collisionRadius(for: building.kind) + radius + clearance
            if simd_distance(building.position, point) < need { return false }
        }
        for deposit in simulation.deposits.values {
            let need = Deposit.workRadius + radius + clearance
            if simd_distance(deposit.position, point) < need { return false }
        }
        return true
    }

    /// Centre + edge/corner samples so green means the full plot fits.
    private static func footprintSamples(
        kind: BuildingKind,
        center: WorldPoint
    ) -> [WorldPoint] {
        if let half = halfExtents(for: kind) {
            var points: [WorldPoint] = [center]
            let xs: [Float] = [-half.x, 0, half.x]
            let zs: [Float] = [-half.y, 0, half.y]
            for x in xs {
                for z in zs {
                    if x == 0 && z == 0 { continue }
                    points.append(center + WorldPoint(x, z))
                }
            }
            let inset: Float = 0.92
            for x in [-half.x, half.x] {
                for z in [-half.y, half.y] {
                    points.append(center + WorldPoint(x * inset, z * inset))
                }
            }
            return points
        }

        let radius = kind.footprintRadius
        var points: [WorldPoint] = [center]
        for ring in [radius * 0.5, radius] as [Float] {
            let steps = ring == radius ? 16 : 8
            for index in 0..<steps {
                let angle = Float(index) / Float(steps) * 2 * .pi
                points.append(center + WorldPoint(cos(angle) * ring, sin(angle) * ring))
            }
        }
        return points
    }
}
