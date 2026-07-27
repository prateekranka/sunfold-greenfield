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

        for causeway in map.causeways {
            root.addChild(makeCauseway(causeway, map: map))
        }
        for region in RegionID.allCases {
            root.addChild(
                makeFragment(map.fragment(region), seed: map.seed, keepClear: keepClear)
            )
        }

        DebugLog.info("World built: \(RegionID.allCases.count) fragments, seed \(map.seed).")
        return (root, rig)
    }

    // MARK: - Fragments

    private static func makeFragment(
        _ fragment: Fragment,
        seed: UInt64,
        keepClear: [TerrainDressing.KeepClear]
    ) -> Entity {
        let built = FragmentMeshFactory.build(fragment: fragment, seed: seed)
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
                rimRadii: built.rimRadii,
                seed: seed,
                keepClear: keepClear
            )
        )
        return entity
    }

    // MARK: - Causeways

    /// A broad luminous gravity band. Causeways that a side's Outpost has not yet
    /// woven render dim, so the player can read a future route without mistaking
    /// it for a walkable one today.
    private static func makeCauseway(_ causeway: Causeway, map: WorldMap) -> Entity {
        let from = map.fragment(causeway.from)
        let to = map.fragment(causeway.to)

        let start = map.dockPoint(on: causeway.from, facing: causeway.to)
        let end = map.dockPoint(on: causeway.to, facing: causeway.from)
        let midpoint = (start + end) * 0.5
        let span = simd_distance(start, end)
        let heading = end - start

        let entity = Entity()
        entity.name = "causeway.\(from.id.rawValue)-\(to.id.rawValue)"
        entity.position = [midpoint.x, -0.35, midpoint.y]
        entity.orientation = simd_quatf(angle: atan2(heading.x, heading.y), axis: [0, 1, 0])

        // Twice calibrated against the rendered build, and a single flat plane
        // will not do it. The first version's alpha was never applied at all —
        // `UnlitMaterial` ignores tint alpha until `blending` is set — so it drew
        // as an opaque gold slab that overwhelmed the fragments it connects. Once
        // transparency worked, a dim gold over the near-black void simply went
        // brown: against black, alpha *is* brightness, and dark gold is brown.
        //
        // A causeway is a walkable woven span, so it is built like one — a faint
        // gravity field wide enough to carry units, read by two lit rails at its
        // edges. The rails carry the light; the field only has to hold the width.
        //
        // The field is cool, not gold. Gravity is the cool half of the identity,
        // and more practically a warm tint at low alpha over a black void is
        // simply brown — that is what the previous two passes both produced.
        //
        // The rails are opaque. At 0.92 alpha they came back grey rather than
        // luminous: transparent surfaces do not reliably sort above the field
        // beneath them, so the dim deck composited back over the bright rail. An
        // opaque material draws in the opaque pass and writes depth, which makes
        // the read unconditional.
        let lit = causeway.isAlwaysOpen
        let deckWidth: Float = 6.0

        let field = Entity()
        field.name = "\(entity.name).field"
        field.components.set(
            ModelComponent(
                mesh: .generatePlane(width: deckWidth, depth: span, cornerRadius: 2.4),
                materials: [
                    StructureMaterial.glow(SunfoldPalette.starCool, opacity: lit ? 0.16 : 0.06)
                ]
            )
        )
        entity.addChild(field)

        // The rails carry the one piece of gameplay information a causeway has:
        // woven or not. That is encoded in *brightness*, which makes it the one
        // place `StructureMaterial.glow`'s default emitter lift is wrong — the
        // lift normalises the brightest channel to full, so a dimmed gold and a
        // full gold come out of it as the same colour and an unwoven route would
        // read as walkable. The unwoven rail therefore opts out of the lift
        // entirely (`strength: 0, whiten: 0`) and renders the authored dim gold,
        // whose linear luminance sits far below the bloom threshold. The woven
        // rail keeps the full emitter treatment and is one of the things the
        // bright pass is meant to find.
        let railMaterial = lit
            ? StructureMaterial.glow(SunfoldPalette.sunwovenGold)
            : StructureMaterial.glow(
                StructureMaterial.shade(SunfoldPalette.sunwovenGold, 0.30),
                strength: 0,
                whiten: 0
            )

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

    // MARK: - Lighting

    /// Warm shadow-casting key, cool fill, rim, and a procedurally generated
    /// image-based light. Everything about the look — including the tuning
    /// constants — lives in `LightingRig`.
    private static func makeLighting() -> Entity {
        LightingRig.makeLighting()
    }
}
