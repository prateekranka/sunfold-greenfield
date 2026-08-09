import Foundation
import RealityKit
import UIKit
import simd

/// Builds the RealityKit scene graph from the map contract.
///
/// This type reads simulation truth and produces entities. It decides nothing:
/// no legality, no ownership, no rules — only how existing state is shown.
@MainActor
enum WorldScene {

    /// Assembles the whole world under one root, and returns the camera rig with it.
    ///
    /// `keepClear` is the ground the simulation's starting entities already own.
    /// Terrain dressing is static and is laid down once, so it needs to be told
    /// where not to scatter rather than discovering it later.
    static func build(
        map: WorldMap,
        tuning: SkirmishTuning,
        keepClear: [TerrainDressing.KeepClear] = []
    ) -> (root: Entity, rig: CameraRig) {
        let root = Entity()
        root.name = "world.root"

        let rig = CameraRig(
            tuning: tuning,
            map: map,
            focus: map.fragment(.sunwovenHome).center
        )

        // The void rides the rig, so it is seamless at every yaw and zoom.
        rig.attachSky(StarfieldFactory.makeSky(seed: map.seed, tuning: tuning))

        root.addChild(rig.root)
        root.addChild(makeLighting())

        // Water is one world-space surface. Building it once prevents each
        // fragment from drawing a separate floor with a separate seam.
        if let water = VoidWaterMeshFactory.build(map: map) {
            root.addChild(water)
        }

        for causeway in map.causeways {
            root.addChild(makeCauseway(causeway, map: map))
        }
        for region in RegionID.allCases {
            root.addChild(
                makeFragment(map.fragment(region), map: map, keepClear: keepClear)
            )
        }

        DebugLog.info("World built: \(RegionID.allCases.count) fragments, seed \(map.seed).")
        return (root, rig)
    }

    // MARK: - Fragments

    private static func makeFragment(
        _ fragment: Fragment,
        map: WorldMap,
        keepClear: [TerrainDressing.KeepClear]
    ) -> Entity {
        let seed = map.seed
        let built = FragmentMeshFactory.build(fragment: fragment, map: map, seed: seed)
        let colors = SunfoldPalette.fragmentColors(for: fragment.id)

        let entity = Entity()
        entity.name = "fragment.\(fragment.id.rawValue)"
        entity.position = [fragment.center.x, 0, fragment.center.y]

        let top = Entity()
        top.name = "\(entity.name).top"
        top.components.set(
            ModelComponent(
                mesh: built.top,
                materials: FragmentMeshFactory.topMaterials(
                    surface: colors.surface,
                    rock: colors.rock
                )
            )
        )

        let underside = Entity()
        underside.name = "\(entity.name).under"
        underside.components.set(
            ModelComponent(
                mesh: built.underside,
                materials: FragmentMeshFactory.cliffMaterials(
                    surface: colors.surface,
                    rock: colors.rock
                )
            )
        )

        entity.addChild(top)
        entity.addChild(underside)
        entity.addChild(
            TerrainDressing.build(
                fragment: fragment,
                map: map,
                rimRadii: built.rimRadii,
                seed: seed,
                keepClear: keepClear
            )
        )
        return entity
    }

    // MARK: - Causeways

    /// A pair of luminous rails marking an established gravity causeway.
    private static func makeCauseway(_ causeway: Causeway, map: WorldMap) -> Entity {
        let from = map.fragment(causeway.from)
        let to = map.fragment(causeway.to)

        let start = map.dockPoint(on: causeway.from, facing: causeway.to)
        let end = map.dockPoint(on: causeway.to, facing: causeway.from)

        let entity = Entity()
        entity.name = "causeway.\(from.id.rawValue)-\(to.id.rawValue)"

        // The field used to be a translucent plane. It sorted against the void
        // and read as a floating slab. The rails below are opaque and carry the
        // causeway read without introducing another surface over the water.
        let lit = causeway.isAlwaysOpen
        let deckWidth: Float = 6.0

        // Unwoven home→expansion links share their dock point with the parked
        // transport. Drawing a solid field there produced the "dark spar" that
        // read as a slab bolted to the hull. Future routes stay on the minimap
        // as dashed intention; the diorama only shows a causeway once it is
        // walkable.
        //
        // A causeway is drawn only where there is something to cross, and only
        // *across* it.
        //
        // CP-13 decided the first part by asking whether the two plates overlapped,
        // which was a fair proxy while the only void was the outer ocean. It stopped
        // being one the moment rivers arrived: two plates can overlap and still have
        // a channel between them, and a route across water is exactly when a player
        // needs to see the span.
        //
        // The second part is what CP-14's first cut got wrong on screen. The span
        // ran dock to dock, and a dock is a berth out in the middle of the water —
        // so on a map where the two plates nearly touch, the deck was a translucent
        // slab lying across forty metres of dry ground with rocks poking through it,
        // then hanging off the coast into the void. A bridge is the length of the
        // water, not the distance between two harbours.
        guard lit, let crossing = waterCrossing(from: start, to: end, map: map) else {
            return entity
        }
        let midpoint = (crossing.enters + crossing.leaves) * 0.5
        let span = simd_distance(crossing.enters, crossing.leaves)
        let heading = crossing.leaves - crossing.enters
        entity.position = [midpoint.x, -0.35, midpoint.y]
        entity.orientation = simd_quatf(angle: atan2(heading.x, heading.y), axis: [0, 1, 0])

        // The rails carry the one piece of gameplay information a causeway has:
        // it is woven and open. Only woven routes reach this branch now.
        let railMaterial = StructureMaterial.glow(SunfoldPalette.sunwovenGold)

        for side in [Float(-1), Float(1)] {
            let rail = Entity()
            rail.name = "\(entity.name).rail"
            rail.position = [side * deckWidth * 0.5, 0.03, 0]
            rail.components.set(
                ModelComponent(
                    mesh: .generatePlane(width: 0.5, depth: span * 0.97, cornerRadius: 0.25),
                    materials: [railMaterial]
                )
            )
            entity.addChild(rail)
        }

        return entity
    }

    /// Whether any void lies on the straight line between two points.
    /// The stretch of void a straight route from `from` to `to` has to bridge, or
    /// `nil` if it never leaves the land.
    ///
    /// Returns the first and last wet samples, each pushed `landing` metres back
    /// onto the bank so the deck ends on solid ground rather than at the waterline
    /// — a span that stops exactly at the shore reads as a jetty that fell short.
    /// The interval spans from the first wet point to the last, so a route crossing
    /// two channels with an island between them gets one deck over the whole run
    /// rather than a gap where a unit would appear to step onto nothing.
    private static func waterCrossing(
        from: WorldPoint,
        to: WorldPoint,
        map: WorldMap,
        landing: Float = 3
    ) -> (enters: WorldPoint, leaves: WorldPoint)? {
        let steps = 96
        let span = to - from
        var first: Int?
        var last: Int?
        for step in 0...steps {
            let point = from + span * (Float(step) / Float(steps))
            // A causeway is a land route across authored void water. The outer
            // backdrop is also outside every region, but it is not a crossing
            // and must never become a deck-shaped slab.
            guard map.isSubmerged(point) else { continue }
            if first == nil { first = step }
            last = step
        }
        guard let first, let last else { return nil }

        let length = simd_length(span)
        guard length > 0.001 else { return nil }
        let along = span / length
        let enters = from + span * (Float(first) / Float(steps)) - along * landing
        let leaves = from + span * (Float(last) / Float(steps)) + along * landing
        return (enters, leaves)
    }

    // MARK: - Lighting

    /// Warm shadow-casting key, cool fill, rim, and a procedurally generated
    /// image-based light. Everything about the look — including the tuning
    /// constants — lives in `LightingRig`.
    private static func makeLighting() -> Entity {
        LightingRig.makeLighting()
    }
}
