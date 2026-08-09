import Foundation
import RealityKit
import UIKit
import simd

/// The game's material vocabulary: one fully-populated `PhysicallyBasedMaterial`
/// per real surface class, built from the `ProceduralTexture` recipes and the
/// UVs `MeshUV` generates.
///
/// Before this, every material in the build was a flat `baseColor` tint plus a
/// scalar roughness — the single largest reason the frame read as a placeholder.
/// This file is where that is replaced: base colour, normal, roughness, ambient
/// occlusion, plus metallic and emissive on the surfaces that genuinely have
/// them, all cached and all resolved from `SunfoldPalette`.
///
/// Three rules the file holds itself to:
///
/// 1. **It adds material response, never a new hue.** `tint` means "the colour
///    this surface should read as in the frame", not "a multiplier on whatever
///    the recipe happened to bake". `correction(...)` divides the requested
///    colour by the recipe's authored mid-tone so the product lands back on the
///    palette. Nothing here can drift a faction off its locked identity.
/// 2. **Texel density is anchored in metres, never in entity size.** Every UV in
///    the project is generated at `metersPerTile`, and a surface's fine tiling is
///    a fixed multiple of that. A citizen and a Core therefore carry the same
///    number of texels per metre of hull, which is what makes them read as one
///    world instead of two scales of detail.
/// 3. **It fails open.** If a recipe produced no image, the material degrades to
///    the flat tint the call site asked for rather than to black.
enum MaterialLibrary {

    // MARK: - Texel density

    /// Metres of surface per texture tile, for every mesh in the project.
    ///
    /// This is the single number that makes scale consistent. `MeshUV` divides
    /// projected metres by it, so a 40 m fragment and a 1.2 m citizen get the
    /// same texels per metre; a surface that wants a finer pattern says so with
    /// `Spec.tileRepeat`, which is still a fixed multiple of world metres and so
    /// still cannot vary with how big the entity happens to be.
    static let metersPerTile: Float = 4

    /// The projection authored structures use: dominant-axis box mapping.
    ///
    /// Buildings, hulls, decks and kerbs are boxy, so faces that share a dominant
    /// axis share an origin and the pattern runs continuously across a whole wall
    /// instead of restarting at every triangle.
    static let structureUVProjection = MeshUVProjection.box(metersPerTile: metersPerTile)

    /// The projection fragments use: per-face planar, matching
    /// `FragmentMeshFactory.fragmentUVProjection`.
    ///
    /// A fragment's flanks are almost all slanted, and planar-onto-the-face is
    /// the only projection with zero stretch at an arbitrary slant.
    static let facePlanarUVProjection = MeshUVProjection.facePlanar(metersPerTile: metersPerTile)

    /// Texels per metre of real surface, for auditing that two surfaces agree.
    @MainActor
    static func texelsPerMeter(
        for surface: Surface,
        size: Int = ProceduralTexture.defaultSize
    ) -> Float {
        Float(size) * spec(for: surface).tileRepeat / metersPerTile
    }

    // MARK: - Surfaces

    /// The surface classes this game actually has. One case per material a
    /// player can point at and name.
    enum Surface: String, CaseIterable, Sendable {
        /// The habitable fragment top: weathered pale regolith.
        case regolithGround
        /// Fragment underside, rim rock and any exposed stone: cool and fractured.
        case rimStone
        /// Sunwoven woven fabric and ivory shell.
        case wovenIvory
        /// Burnished gold trim, kerbs, lattice and Core banding.
        case goldTrim
        /// Sunwoven luminous seams. The only surface class that is emissive by
        /// default; everything else asks for it explicitly.
        case luminousSeam
        /// Gravemark plated slate: brushed, part-oxidised armour plate.
        case platedSlate
        /// Gravemark oxidised copper seam and pipework.
        case oxidisedCopper
        /// Crystalline Lumen deposit.
        case crystallineLumen
        /// Crystalline Aether deposit.
        case crystallineAether
        /// Raw Matter mineral: the same faceted crystal, unlit and half-metallic.
        case rawMatter
        /// Sunwoven transport hull.
        case transportHull
        /// Gravemark transport hull.
        case armouredHull
        /// Cultivated growth, crop and organic cover.
        case growth

        var recipe: ProceduralTexture.Recipe { MaterialLibrary.spec(for: self).recipe }
    }

    /// How one surface class responds to light, and which recipe carries it.
    struct Spec {
        /// The procedural recipe this surface is cut from.
        var recipe: ProceduralTexture.Recipe
        /// The palette colour this surface reads as when nothing overrides it.
        var tint: UIColor
        /// The recipe's authored mid-tone, estimated from the mix endpoints in
        /// its own generator. `correction(...)` divides by this so a requested
        /// tint means the final colour rather than a multiplier on the bake.
        var reference: SIMD3<Float>
        /// Multiplies the recipe's roughness map. Below 1 is glossier.
        var roughnessScale: Float
        /// A scalar metallic that overrides the recipe's map. `nil` keeps the
        /// recipe's own metallic (or its fallback).
        var metallic: Float?
        /// Emissive strength when the caller does not say otherwise.
        var emissiveIntensity: Float
        /// The colour the emissive mask is tinted with. `nil` uses the base tint.
        var emissiveTint: UIColor?
        /// Texture repeats per `metersPerTile`. A fabric weave is genuinely finer
        /// than a regolith dune, so this varies by material — never by entity.
        var tileRepeat: Float
    }

    /// The locked description of every surface class.
    static func spec(for surface: Surface) -> Spec {
        switch surface {
        case .regolithGround:
            Spec(
                recipe: .regolith,
                tint: SunfoldPalette.sunwovenSurface,
                reference: [0.791, 0.742, 0.639],
                roughnessScale: 0.94,
                metallic: 0,
                emissiveIntensity: 0,
                emissiveTint: nil,
                tileRepeat: 1
            )
        case .rimStone:
            Spec(
                recipe: .fracturedStone,
                // `neutralRock` blended 0.46 toward `coolStone`, which is the
                // exact mix `WorldScene.rockMaterial` shipped and the mix the
                // `.fracturedStone` recipe is authored around. Written out
                // rather than computed so this stays free of main-actor state.
                tint: UIColor(red: 0.484, green: 0.489, blue: 0.504, alpha: 1),
                reference: [0.482, 0.487, 0.505],
                roughnessScale: 0.98,
                metallic: 0,
                emissiveIntensity: 0,
                emissiveTint: nil,
                tileRepeat: 1
            )
        case .wovenIvory:
            Spec(
                recipe: .wovenIvory,
                tint: SunfoldPalette.sunwovenIvory,
                reference: [0.921, 0.886, 0.813],
                roughnessScale: 0.86,
                metallic: 0,
                emissiveIntensity: 0,
                emissiveTint: nil,
                tileRepeat: 4
            )
        case .goldTrim:
            // The one genuinely metallic Sunwoven surface. Gold only reads as
            // gold when it has a specular response; a rough dielectric at this
            // hue reads as mustard paint.
            Spec(
                recipe: .gildedTrim,
                tint: SunfoldPalette.sunwovenGold,
                reference: [0.773, 0.613, 0.302],
                roughnessScale: 0.42,
                metallic: 0.85,
                emissiveIntensity: 0,
                emissiveTint: nil,
                tileRepeat: 4
            )
        case .luminousSeam:
            Spec(
                recipe: .crystalline,
                tint: SunfoldPalette.sunwovenTurquoise,
                reference: [0.744, 0.785, 0.850],
                roughnessScale: 0.30,
                metallic: 0,
                emissiveIntensity: 2.6,
                emissiveTint: SunfoldPalette.sunwovenTurquoise,
                tileRepeat: 3
            )
        case .platedSlate:
            Spec(
                recipe: .oxidisedMetal,
                tint: SunfoldPalette.gravemarkSurface,
                reference: [0.303, 0.314, 0.347],
                roughnessScale: 0.78,
                metallic: nil,
                emissiveIntensity: 0,
                emissiveTint: nil,
                tileRepeat: 2
            )
        case .oxidisedCopper:
            Spec(
                recipe: .oxidisedMetal,
                tint: SunfoldPalette.gravemarkCopper,
                reference: [0.303, 0.314, 0.347],
                roughnessScale: 0.62,
                metallic: 0.72,
                emissiveIntensity: 0,
                emissiveTint: nil,
                tileRepeat: 4
            )
        case .crystallineLumen:
            Spec(
                recipe: .crystalline,
                tint: SunfoldPalette.resourceTint(.lumen),
                reference: [0.744, 0.785, 0.850],
                roughnessScale: 0.26,
                metallic: 0,
                emissiveIntensity: 3.0,
                emissiveTint: SunfoldPalette.resourceTint(.lumen),
                tileRepeat: 2
            )
        case .crystallineAether:
            Spec(
                recipe: .crystalline,
                tint: SunfoldPalette.resourceTint(.aether),
                reference: [0.744, 0.785, 0.850],
                roughnessScale: 0.24,
                metallic: 0,
                emissiveIntensity: 3.2,
                emissiveTint: SunfoldPalette.resourceTint(.aether),
                tileRepeat: 2
            )
        case .rawMatter:
            // Matter is ore, not light. Same faceted crystal, no emissive, and
            // enough metallic to catch the key without becoming a mirror.
            Spec(
                recipe: .crystalline,
                tint: SunfoldPalette.resourceTint(.matter),
                reference: [0.744, 0.785, 0.850],
                roughnessScale: 0.55,
                metallic: 0.35,
                emissiveIntensity: 0,
                emissiveTint: nil,
                tileRepeat: 2
            )
        case .transportHull:
            Spec(
                recipe: .wovenIvory,
                tint: SunfoldPalette.sunwovenIvory,
                reference: [0.921, 0.886, 0.813],
                roughnessScale: 0.72,
                metallic: 0.05,
                emissiveIntensity: 0,
                emissiveTint: nil,
                tileRepeat: 3
            )
        case .armouredHull:
            Spec(
                recipe: .oxidisedMetal,
                tint: SunfoldPalette.gravemarkSurface,
                reference: [0.303, 0.314, 0.347],
                roughnessScale: 0.68,
                metallic: nil,
                emissiveIntensity: 0,
                emissiveTint: nil,
                tileRepeat: 3
            )
        case .growth:
            Spec(
                recipe: .regolith,
                tint: SunfoldPalette.sunwovenTurquoise,
                reference: [0.791, 0.742, 0.639],
                roughnessScale: 0.99,
                metallic: 0,
                emissiveIntensity: 0,
                emissiveTint: nil,
                tileRepeat: 2
            )
        }
    }

    /// The neutral cool the rim rock is pulled toward, matching the value the
    /// `.fracturedStone` recipe is authored around.
    static let coolStone = UIColor(red: 0.55, green: 0.575, blue: 0.625, alpha: 1)

    // MARK: - Building materials

    /// The surface class's own material, at its own palette colour.
    @MainActor
    static func material(_ surface: Surface) -> PhysicallyBasedMaterial {
        material(surface, tint: nil)
    }

    /// A surface class recoloured to `tint`.
    ///
    /// `tint` is the colour the surface should *read* as, not a multiplier: the
    /// requested colour is divided by the recipe's authored mid-tone before it
    /// reaches the material, so passing a palette colour renders that palette
    /// colour. Passing `nil` uses the surface's own canonical colour.
    ///
    /// - Parameters:
    ///   - roughness: Overrides `Spec.roughnessScale`. This is a multiplier on
    ///     the recipe's roughness map, so an existing call site's relative
    ///     intent (0.62 glossy mineral vs 0.98 dead rock) survives verbatim.
    ///   - emissiveIntensity: Overrides `Spec.emissiveIntensity`. Pass 0 to keep
    ///     a normally-luminous surface dark.
    ///   - metallic: Overrides `Spec.metallic`. **A metal in this scene is
    ///     mostly black.** A conductor has no diffuse term — everything it shows
    ///     is a reflection — and what surrounds these structures is a void with
    ///     one warm IBL lobe in it, so any facet not near the mirror direction
    ///     of the key reflects empty space. Measured at CP-07: `goldTrim` at its
    ///     authored 0.85 rendered the Core's entire armature as dark bronze,
    ///     against concept 01's bright pale gold. Lower it wherever gold has to
    ///     read as *lit metal* rather than as a mirror, and leave the spec alone
    ///     where a hard specular glint is the point.
    @MainActor
    static func material(
        _ surface: Surface,
        tint: UIColor?,
        roughness: Float? = nil,
        emissiveIntensity: Float? = nil,
        metallic: Float? = nil,
        size: Int = ProceduralTexture.defaultSize
    ) -> PhysicallyBasedMaterial {
        let spec = spec(for: surface)
        let requested = tint ?? spec.tint
        let roughnessScale = roughness ?? spec.roughnessScale
        let emissive = emissiveIntensity ?? spec.emissiveIntensity
        let metalness = metallic ?? spec.metallic

        let key = Key(
            surface: surface,
            tint: quantise(requested),
            roughness: roughnessScale.bitPattern,
            emissive: emissive.bitPattern,
            metallic: (metalness ?? -1).bitPattern,
            size: size
        )
        if let cached = cache[key] { return cached }

        let built = build(
            spec: spec,
            requested: requested,
            roughnessScale: roughnessScale,
            emissiveIntensity: emissive,
            metallic: metalness,
            size: size
        )
        cache[key] = built
        return built
    }

    /// A luminous Sunwoven seam as a *lit* emissive material.
    ///
    /// This is deliberately not the same thing as `StructureMaterial.glow`, which
    /// stays an `UnlitMaterial`: unlit geometry is excluded from the shadow map
    /// by `LightingRig`, and every existing seam relies on that. Use this only
    /// where a seam should also take the key light and cast — a Core spine, a
    /// hero lattice — and leave the thin decals unlit.
    @MainActor
    static func luminousSeam(
        _ tint: UIColor = SunfoldPalette.sunwovenTurquoise,
        intensity: Float = 2.6
    ) -> PhysicallyBasedMaterial {
        material(.luminousSeam, tint: tint, emissiveIntensity: intensity)
    }

    /// The surface class a palette colour belongs to.
    ///
    /// Every tint in the project is a `shade`/`blend` of a locked palette colour,
    /// so nearest-anchor in RGB recovers which surface the call site meant. This
    /// is what lets `StructureMaterial.matte` gain full PBR response at ~90 call
    /// sites without any of them being edited.
    static func surface(matching color: UIColor) -> Surface {
        let target = components(color)
        var best = Surface.regolithGround
        var bestDistance = Float.greatestFiniteMagnitude
        for (anchor, surface) in anchors {
            let delta = components(anchor) - target
            let distance = simd_length_squared(delta)
            if distance < bestDistance {
                bestDistance = distance
                best = surface
            }
        }
        return best
    }

    /// Generates every recipe this library can hand out, off the main actor.
    ///
    /// Call once from scene setup. Without it the first structure of each kind
    /// pays the generation cost inline (~570 ms per recipe in a Debug build).
    @MainActor
    static func preload(size: Int = ProceduralTexture.defaultSize) async {
        // Ordered dedupe rather than a `Set`: generation order cannot affect the
        // result, but an unordered warm-up would make a profile trace differ
        // run to run for no reason.
        var recipes: [ProceduralTexture.Recipe] = []
        for surface in Surface.allCases {
            let recipe = spec(for: surface).recipe
            if !recipes.contains(recipe) { recipes.append(recipe) }
        }
        await ProceduralTexture.preloadInBackground(recipes, size: size)
    }

    /// Drops every cached material. Only useful when retuning a spec live.
    @MainActor
    static func clearCache() {
        cache.removeAll()
    }

    // MARK: - Construction

    @MainActor
    private static func build(
        spec: Spec,
        requested: UIColor,
        roughnessScale: Float,
        emissiveIntensity: Float,
        metallic metalness: Float?,
        size: Int
    ) -> PhysicallyBasedMaterial {
        let maps = ProceduralTexture.maps(spec.recipe, size: size)

        var material = PhysicallyBasedMaterial()
        material.faceCulling = .none

        // Base colour. With a texture, the tint is the correction that lands the
        // product on the requested palette colour; without one it *is* the
        // requested colour, so a failed bake degrades to today's flat look
        // rather than to a wrongly-darkened one.
        if let baseColor = maps.baseColor {
            material.baseColor = .init(
                tint: correction(requested: requested, reference: spec.reference),
                texture: ProceduralTexture.bind(baseColor)
            )
        } else {
            material.baseColor = .init(tint: requested)
        }

        if let normal = maps.normal {
            material.normal = .init(texture: ProceduralTexture.bind(normal))
        }

        if let roughness = maps.roughness {
            material.roughness = .init(
                scale: roughnessScale,
                texture: ProceduralTexture.bind(roughness)
            )
        } else {
            material.roughness = .init(floatLiteral: clamp01(maps.fallbackRoughness * roughnessScale))
        }

        if let metallic = metalness {
            material.metallic = .init(floatLiteral: clamp01(metallic))
        } else if let metallic = maps.metallic {
            material.metallic = .init(scale: 1, texture: ProceduralTexture.bind(metallic))
        } else {
            material.metallic = .init(floatLiteral: clamp01(maps.fallbackMetallic))
        }

        if let occlusion = maps.ambientOcclusion {
            material.ambientOcclusion = .init(texture: ProceduralTexture.bind(occlusion))
        }

        if emissiveIntensity > 0 {
            let colour = spec.emissiveTint ?? requested
            if let emissive = maps.emissive {
                material.emissiveColor = .init(
                    color: colour,
                    texture: ProceduralTexture.bind(emissive)
                )
            } else {
                material.emissiveColor = .init(color: colour)
            }
            material.emissiveIntensity = emissiveIntensity
        }

        // Only the scale is non-identity, so the undocumented composition order
        // of offset/scale/rotation cannot bite. Fine tiling is a fixed multiple
        // of `metersPerTile`, which is what keeps density world-anchored.
        material.textureCoordinateTransform = .init(
            offset: .zero,
            scale: SIMD2<Float>(repeating: spec.tileRepeat),
            rotation: 0
        )

        return material
    }

    /// The tint that, multiplied by a recipe's authored mid-tone, lands on the
    /// colour the call site asked for.
    ///
    /// Clamped to 0...1: a request brighter than the bake caps at white rather
    /// than inventing headroom. Every palette anchor sits at or below its
    /// recipe's reference, so in practice the clamp only fires on deliberately
    /// over-bright shades, which then simply render at the recipe's own value.
    static func correction(requested: UIColor, reference: SIMD3<Float>) -> UIColor {
        let target = components(requested)
        let safe = simd_max(reference, SIMD3<Float>(repeating: 0.02))
        let ratio = simd_clamp(target / safe, SIMD3<Float>(repeating: 0), SIMD3<Float>(repeating: 1))
        return UIColor(
            red: CGFloat(ratio.x),
            green: CGFloat(ratio.y),
            blue: CGFloat(ratio.z),
            alpha: 1
        )
    }

    // MARK: - Cache

    private struct Key: Hashable {
        var surface: Surface
        var tint: UInt32
        var roughness: UInt32
        var emissive: UInt32
        var metallic: UInt32
        var size: Int
    }

    @MainActor
    private static var cache: [Key: PhysicallyBasedMaterial] = [:]

    /// 8 bits per channel is finer than any difference the frame can show, and
    /// it keeps two `shade(...)` results that differ in the ninth decimal from
    /// occupying two cache slots and two GPU materials.
    private static func quantise(_ color: UIColor) -> UInt32 {
        let rgb = simd_clamp(
            components(color),
            SIMD3<Float>(repeating: 0),
            SIMD3<Float>(repeating: 1)
        )
        let red = UInt32((rgb.x * 255).rounded())
        let green = UInt32((rgb.y * 255).rounded())
        let blue = UInt32((rgb.z * 255).rounded())
        return red << 16 | green << 8 | blue
    }

    private static func components(_ color: UIColor) -> SIMD3<Float> {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 1
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return SIMD3<Float>(repeating: 0.5)
        }
        return SIMD3<Float>(Float(red), Float(green), Float(blue))
    }

    private static func clamp01(_ value: Float) -> Float {
        min(max(value, 0), 1)
    }

    /// Palette colour -> surface class, for `surface(matching:)`.
    ///
    /// Every entry is a locked palette value. Nothing here introduces a colour
    /// that is not already in the identity.
    private static var anchors: [(UIColor, Surface)] {
        [
            (SunfoldPalette.sunwovenSurface, .regolithGround),
            (SunfoldPalette.dominionStone, .regolithGround),
            (SunfoldPalette.neutralSurface, .regolithGround),
            (SunfoldPalette.sunwovenRock, .rimStone),
            (SunfoldPalette.neutralRock, .rimStone),
            (SunfoldPalette.gravemarkRock, .rimStone),
            (coolStone, .rimStone),
            (SunfoldPalette.sunwovenIvory, .wovenIvory),
            (SunfoldPalette.sunwovenGold, .goldTrim),
            (SunfoldPalette.resourceTint(.provisions), .goldTrim),
            (SunfoldPalette.sunwovenTurquoise, .luminousSeam),
            (SunfoldPalette.gravemarkSurface, .platedSlate),
            (SunfoldPalette.gravemarkCopper, .oxidisedCopper),
            (SunfoldPalette.gravemarkMineral, .rawMatter),
            (SunfoldPalette.resourceTint(.lumen), .crystallineLumen),
            (SunfoldPalette.resourceTint(.aether), .crystallineAether),
            (SunfoldPalette.resourceTint(.matter), .rawMatter),
        ]
    }
}
