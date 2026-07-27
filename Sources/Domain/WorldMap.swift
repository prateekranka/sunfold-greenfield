import Foundation
import simd

/// A point on the world plane. World space is metres on the XZ plane, Y up.
/// North is -Z, so a camera at yaw 0 looks north-up.
typealias WorldPoint = SIMD2<Float>

/// The named regions of the proof map. Every system — renderer, pathing, minimap,
/// AI, camera bounds, deposits, spawn points and selection — resolves position
/// through this contract, so a place that looks walkable is walkable.
enum RegionID: String, CaseIterable, Sendable {
    case sunwovenHome
    case gravemarkHome
    case dominion
    case sunwovenExpansion
    case gravemarkExpansion
    case neutralOutcropNorth
    case neutralOutcropSouth

    var isHome: Bool { self == .sunwovenHome || self == .gravemarkHome }

    /// Which side, if any, owns this region at match start.
    var startingOwner: Faction? {
        switch self {
        case .sunwovenHome: .sunwoven
        case .gravemarkHome: .gravemark
        default: nil
        }
    }
}

/// One habitable land fragment drifting in the void.
struct Fragment: Sendable {
    let id: RegionID
    /// Centre on the world plane.
    let center: WorldPoint
    /// Nominal radius. The rendered silhouette is jittered around this.
    let radius: Float
    /// How far the underside tapers below the surface.
    let depth: Float
}

/// A void route usable only by transports. Land units may never enter one.
struct VoidLane: Sendable {
    let from: RegionID
    let to: RegionID
}

/// A luminous gravity causeway carrying land units between two fragments.
struct Causeway: Sendable {
    let from: RegionID
    let to: RegionID
    /// When set, the causeway stays dormant until this faction has established
    /// its expansion Outpost. This is what forces the first crossing to be made
    /// by transport while still leaving a complete land route for a later Strike.
    let wovenByOutpostOf: Faction?

    var isAlwaysOpen: Bool { wovenByOutpostOf == nil }
}

/// The authored, seed-locked proof map.
///
/// Layout is symmetric under a 180° rotation about the origin, so neither side
/// has a shorter path to the Dominion, to a neutral outcrop, or to the enemy Core.
struct WorldMap: Sendable {
    let seed: UInt64
    let fragments: [RegionID: Fragment]
    let voidLanes: [VoidLane]
    let causeways: [Causeway]

    /// Half-extent of the playable area, used for camera bounds. Deliberately
    /// larger than the fragment envelope so void always remains visible at the edges.
    let bounds: WorldPoint

    static func proofMap(seed: UInt64) -> WorldMap {
        let authored: [Fragment] = [
            Fragment(id: .sunwovenHome, center: [-70, 22], radius: 24, depth: 23),
            Fragment(id: .gravemarkHome, center: [70, -22], radius: 24, depth: 23),
            Fragment(id: .dominion, center: [0, 0], radius: 20, depth: 20),
            Fragment(id: .sunwovenExpansion, center: [-26, -26], radius: 14, depth: 15),
            Fragment(id: .gravemarkExpansion, center: [26, 26], radius: 14, depth: 15),
            Fragment(id: .neutralOutcropNorth, center: [-40, 46], radius: 9, depth: 11),
            Fragment(id: .neutralOutcropSouth, center: [40, -46], radius: 9, depth: 11),
        ]

        var table: [RegionID: Fragment] = [:]
        for fragment in authored { table[fragment.id] = fragment }

        // Transports cross these. A home is reachable from its expansion only by
        // void until that side's Outpost weaves the causeway.
        let lanes: [VoidLane] = [
            VoidLane(from: .sunwovenHome, to: .sunwovenExpansion),
            VoidLane(from: .sunwovenHome, to: .neutralOutcropNorth),
            VoidLane(from: .gravemarkHome, to: .gravemarkExpansion),
            VoidLane(from: .gravemarkHome, to: .neutralOutcropSouth),
            VoidLane(from: .sunwovenExpansion, to: .dominion),
            VoidLane(from: .gravemarkExpansion, to: .dominion),
        ]

        // The central land spine is always open; the home links are woven by the
        // owning side's Outpost, which is what completes a legal Strike route.
        let ways: [Causeway] = [
            Causeway(from: .sunwovenExpansion, to: .dominion, wovenByOutpostOf: nil),
            Causeway(from: .gravemarkExpansion, to: .dominion, wovenByOutpostOf: nil),
            Causeway(from: .sunwovenHome, to: .sunwovenExpansion, wovenByOutpostOf: .sunwoven),
            Causeway(from: .gravemarkHome, to: .gravemarkExpansion, wovenByOutpostOf: .gravemark),
        ]

        return WorldMap(
            seed: seed,
            fragments: table,
            voidLanes: lanes,
            causeways: ways,
            bounds: [118, 86]
        )
    }

    func fragment(_ id: RegionID) -> Fragment {
        // Every RegionID is authored above; a miss is a programming error, not
        // a runtime condition to absorb silently.
        guard let fragment = fragments[id] else {
            preconditionFailure("WorldMap is missing authored fragment \(id.rawValue)")
        }
        return fragment
    }

    /// True when `point` lies on solid land in `id`.
    func contains(_ point: WorldPoint, in id: RegionID) -> Bool {
        let fragment = fragment(id)
        return simd_distance(point, fragment.center) <= fragment.radius
    }

    /// The region containing `point`, if any. Void otherwise.
    func region(at point: WorldPoint) -> RegionID? {
        RegionID.allCases.first { contains(point, in: $0) }
    }

    /// A land-side staging point on `id`'s rim, facing `target`. Boarding citizens
    /// walk here rather than chasing a hull out into the void.
    func stagingPoint(on id: RegionID, facing target: RegionID) -> WorldPoint {
        let source = fragment(id)
        let heading = simd_normalize(fragment(target).center - source.center)
        return source.center + heading * (source.radius - 2.5)
    }

    /// The matching dock position just off `id`'s rim, where a transport hull sits.
    func dockPoint(on id: RegionID, facing target: RegionID) -> WorldPoint {
        let source = fragment(id)
        let heading = simd_normalize(fragment(target).center - source.center)
        return source.center + heading * (source.radius + 3.0)
    }
}
