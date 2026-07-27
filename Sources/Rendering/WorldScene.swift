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
            ModelComponent(mesh: built.top, materials: [surfaceMaterial(colors.surface)])
        )

        let underside = Entity()
        underside.name = "\(entity.name).under"
        underside.components.set(
            ModelComponent(mesh: built.underside, materials: [rockMaterial(colors.rock)])
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

    private static func surfaceMaterial(_ color: UIColor) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: color)
        material.roughness = .init(floatLiteral: 0.92)
        material.metallic = .init(floatLiteral: 0.0)
        material.faceCulling = .none
        return material
    }

    /// Cool stone under warm ground.
    ///
    /// Darkening the flank was tried first and was the wrong variable: in concept
    /// 01 the rim rock is close to the habitable top in *value*, and the read
    /// comes from it being cooler and from having real mass. Pulling the palette
    /// rock toward a neutral cool grey separates it from the sand without
    /// inventing a hue or fighting the key light.
    private static func rockMaterial(_ color: UIColor) -> PhysicallyBasedMaterial {
        let cool = UIColor(red: 0.55, green: 0.575, blue: 0.625, alpha: 1)
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: StructureMaterial.blend(color, cool, 0.46))
        material.roughness = .init(floatLiteral: 0.98)
        material.metallic = .init(floatLiteral: 0.0)
        material.faceCulling = .none
        return material
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

        let railColor = lit
            ? SunfoldPalette.sunwovenGold
            : StructureMaterial.shade(SunfoldPalette.sunwovenGold, 0.30)

        for side in [Float(-1), Float(1)] {
            let rail = Entity()
            rail.name = "\(entity.name).rail"
            rail.position = [side * deckWidth * 0.5, 0.03, 0]
            rail.components.set(
                ModelComponent(
                    mesh: .generatePlane(width: 0.5, depth: span * 0.97, cornerRadius: 0.25),
                    materials: [StructureMaterial.glow(railColor)]
                )
            )
            entity.addChild(rail)
        }

        return entity
    }

    // MARK: - Lighting

    /// Key light from above-camera with a cool fill, matching the bible's
    /// "soft directional key, gentle rim on fragment edges" without an IBL asset.
    private static func makeLighting() -> Entity {
        let root = Entity()
        root.name = "world.lighting"

        let key = Entity()
        var keyLight = DirectionalLightComponent(
            color: UIColor(red: 1.0, green: 0.94, blue: 0.84, alpha: 1),
            intensity: 2700
        )
        keyLight.isRealWorldProxy = false
        key.components.set(keyLight)
        key.look(at: [0, 0, 0], from: [-90, 150, 110], relativeTo: nil)

        let fill = Entity()
        var fillLight = DirectionalLightComponent(
            color: UIColor(red: 0.62, green: 0.72, blue: 0.95, alpha: 1),
            intensity: 850
        )
        fillLight.isRealWorldProxy = false
        fill.components.set(fillLight)
        fill.look(at: [0, 0, 0], from: [120, 90, -140], relativeTo: nil)

        root.addChild(key)
        root.addChild(fill)
        return root
    }
}
