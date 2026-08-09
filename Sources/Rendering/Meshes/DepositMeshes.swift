import Foundation
import RealityKit
import UIKit
import simd

/// The four gatherable resource nodes.
///
/// The panel note that drove this rewrite: *"resource props are one low-poly
/// spiked sphere in one colour — the player cannot parse resource types at a
/// glance."* The fix is not more polygons. It is that each kind now owns a
/// different **silhouette class**, a different **height band**, a different
/// **footprint** and a different **hue**, so the read survives at the game's
/// actual camera distance where a node is 60 px tall and its texture is one
/// value.
///
/// | Kind       | Silhouette class            | Footprint | Height | Hue        |
/// |------------|-----------------------------|-----------|--------|------------|
/// | Matter     | broken scree nest, spiked   | ~4.6 m    | ~1.9 m | cool grey  |
/// | Lumen      | vertical druse, radiating   | ~3.6 m    | ~4.8 m | warm gold  |
/// | Aether     | airborne, ground nearly bare| ~3.2 m    | ~3.3 m | turquoise  |
/// | Provisions | low arching dome, no spikes | ~2.6 m    | ~1.2 m | olive-saff.|
///
/// Wide-and-low against tall-and-narrow against floating against domed is a
/// separation that reads as a black shape on a white card, which is the only
/// test a silhouette actually has to pass. Height and footprint never overlap
/// between two kinds, so even a partly occluded node is unambiguous.
///
/// Deposits still share one cue that scenery never gets: a **low luminous pool
/// on the ground at the node's base**, tinted to the resource. It is now a
/// stain rather than a lamp — the previous version was authored at full emitter
/// brightness and rendered as a white splat that ate the rock it was supposed
/// to sit under (`strength: 1` normalises the brightest channel to 1.0, which
/// is right for a seam and wrong for ground bounce). Pools are authored with
/// `strength` low and `whiten` at zero so the hue survives and the value stays
/// below the surface it lies on.
///
/// Every cluster is jittered from its own deterministic stream *and* the
/// finished entity is given a per-instance yaw and scale, so thirty nodes on a
/// map are thirty different objects while a given seed always rebuilds
/// identically.
@MainActor
enum DepositMeshes {

    /// Every lit zone in this file is a boulder, a crystal, a frond or a spire —
    /// there is not one axis-aligned plate among them. Dominant-axis box mapping
    /// stretches a face by `1 / cos θ` against its axis, which on a 50°-slanted
    /// crystal facet is a 1.5x directional smear of the mineral grain; projecting
    /// onto each face's own plane has no stretch at any angle, and the UV break it
    /// costs lands exactly on the facet edges where the normal already breaks.
    /// Same `MaterialLibrary.metersPerTile`, so the density still matches
    /// everything else in frame.
    private static let crystalUV = MaterialLibrary.facePlanarUVProjection

    // MARK: - Matter

    /// A grey rock nest with pale mineral crystal pushed up through the middle —
    /// the arrangement the approved concept frame shows.
    ///
    /// ~4.6 m across, ~1.9 m tall. It is the **widest and lowest** node, and the
    /// only one built mostly of debris: five nest boulders, fourteen scree
    /// chunks and six bright chips. The chips are the "edge wear" read — freshly
    /// broken rock exposes a lighter face than the weathered body around it, so
    /// chipping is authored as a *value* zone rather than hoped for from a
    /// normal map that is one texel wide at this camera distance.
    static func matter(seed: UInt64) -> Entity {
        var random = DeterministicRandom.stream(seed: seed, tag: "deposit.matter")

        var rock = StructureBuilder(uv: crystalUV)
        var scree = StructureBuilder(uv: crystalUV)
        var chip = StructureBuilder(uv: crystalUV)
        var crystal = StructureBuilder(uv: crystalUV)
        var pool = StructureBuilder(uv: crystalUV)

        // The nest wall: five heavy boulders on a jittered ring, deliberately
        // uneven in mass so one side reads as the back of the nest and the
        // crystal in the middle is framed rather than centred in a donut.
        for index in 0..<5 {
            let angle = Float(index) / 5 * 2 * .pi + random.float(in: -0.34...0.34)
            let distance = random.float(in: 1.28...1.86)
            let heavy = random.float(in: 0...1) < 0.5
            rock.addBoulder(
                center: [cos(angle) * distance, sin(angle) * distance],
                radius: heavy ? random.float(in: 0.72...0.98) : random.float(in: 0.48...0.70),
                height: heavy ? random.float(in: 0.86...1.28) : random.float(in: 0.52...0.82),
                sides: heavy ? 6 : 5,
                random: &random
            )
        }

        // Scree: what turns "a few objects dropped on the ground" into "this
        // rock broke here". Spread wider than the nest so the footprint tapers
        // out rather than ending on a hard boulder line.
        for index in 0..<14 {
            let angle = Float(index) * 2.399_963 + random.float(in: -0.30...0.30)
            let distance = random.float(in: 0.86...2.42)
            scree.addBoulder(
                center: [cos(angle) * distance, sin(angle) * distance],
                radius: random.float(in: 0.16...0.34),
                height: random.float(in: 0.11...0.40),
                sides: random.float(in: 0...1) < 0.55 ? 4 : 5,
                random: &random
            )
        }

        // Fresh-broken chips, in a lighter zone. Six is enough to sparkle the
        // skirt without the cluster losing its grey mass.
        for index in 0..<6 {
            let angle = Float(index) * 1.256 + random.float(in: -0.5...0.5)
            let distance = random.float(in: 0.70...2.24)
            chip.addBoulder(
                center: [cos(angle) * distance, sin(angle) * distance],
                radius: random.float(in: 0.09...0.19),
                height: random.float(in: 0.08...0.22),
                sides: 4, random: &random
            )
        }

        // The mineral itself: six faceted prisms leaning out of the nest floor.
        // Prisms rather than boulders — a boulder with a small top ring still
        // reads as a rock, and the concept's node is unambiguously crystal.
        for index in 0..<6 {
            let yaw = Float(index) / 6 * 2 * .pi + random.float(in: -0.4...0.4)
            let distance = random.float(in: 0.12...0.62)
            addCrystal(
                into: &crystal,
                base: [cos(yaw) * distance, 0.02, sin(yaw) * distance],
                axis: tiltedAxis(yaw: yaw, tilt: random.float(in: 0.10...0.42)),
                length: random.float(in: 0.95...1.85),
                radius: random.float(in: 0.13...0.24),
                sides: 5,
                random: &random
            )
        }

        pool.addCap(
            ring: StructureGeometry.ring(sides: 7, radius: 2.15, y: 0.03),
            pivot: [0, -0.2, 0]
        )

        let entity = StructureAssembly.entity(
            named: "deposit.matter",
            zones: [
                StructureZone(
                    "rock", rock,
                    StructureMaterial.matte(
                        StructureMaterial.shade(SunfoldPalette.neutralRock, 0.88),
                        roughness: 1.0, surface: .rimStone
                    )
                ),
                StructureZone(
                    "scree", scree,
                    StructureMaterial.matte(
                        SunfoldPalette.neutralRock,
                        roughness: 0.96, surface: .rimStone
                    )
                ),
                StructureZone(
                    "chip", chip,
                    StructureMaterial.matte(
                        StructureMaterial.blend(SunfoldPalette.neutralSurface, MaterialLibrary.coolStone, 0.40),
                        roughness: 0.80, surface: .rimStone
                    )
                ),
                // Matter is ore, not a lamp, so the emissive is a lift rather
                // than a source: enough to hold a pale value against grey rock
                // in shadow, well under the post-process bright pass.
                StructureZone(
                    "crystal", crystal,
                    MaterialLibrary.material(
                        .rawMatter,
                        tint: SunfoldPalette.resourceTint(.matter),
                        roughness: 0.34,
                        emissiveIntensity: 0.55
                    )
                ),
                StructureZone(
                    "pool", pool,
                    StructureMaterial.glow(
                        SunfoldPalette.resourceTint(.matter),
                        opacity: 0.13, strength: 0.45, whiten: 0
                    )
                ),
            ]
        )
        return varied(entity, random: &random, spread: 0.88...1.14)
    }

    // MARK: - Lumen

    /// A luminous crystal druse: a tight fan of tapered gold and ivory prisms
    /// radiating off a small rock collar.
    ///
    /// ~3.6 m across, ~4.8 m tall after CP-09. Still the **tallest and narrowest**
    /// node — Matter spreads, Lumen spikes — but the concept's left-side cluster
    /// is a landmark, not a jewellery tip, so the major prisms and collar both
    /// grew without approaching the Core's mass.
    static func lumen(seed: UInt64) -> Entity {
        var random = DeterministicRandom.stream(seed: seed, tag: "deposit.lumen")

        var collar = StructureBuilder(uv: crystalUV)
        var ivory = StructureBuilder(uv: crystalUV)
        var gold = StructureBuilder(uv: crystalUV)
        var core = StructureBuilder(uv: crystalUV)
        var pool = StructureBuilder(uv: crystalUV)

        // Collar wide enough to seat the taller prisms without becoming a plinth.
        collar.addSolid(
            lower: StructureGeometry.ring(sides: 7, radius: 1.28, y: 0, phase: random.float(in: 0...1)),
            upper: StructureGeometry.ring(sides: 7, radius: 1.05, y: 0.36)
        )
        for index in 0..<6 {
            let angle = Float(index) / 6 * 2 * .pi + random.float(in: -0.5...0.5)
            let distance = random.float(in: 1.10...1.55)
            collar.addBoulder(
                center: [cos(angle) * distance, sin(angle) * distance],
                radius: random.float(in: 0.28...0.48),
                height: random.float(in: 0.22...0.48),
                sides: 5, random: &random
            )
        }

        // Six pale prisms splayed hard outward — the fan that makes the
        // cluster read as grown rather than assembled.
        for index in 0..<6 {
            let yaw = Float(index) / 6 * 2 * .pi + random.float(in: -0.28...0.28)
            let distance = random.float(in: 0.34...0.72)
            addCrystal(
                into: &ivory,
                base: [cos(yaw) * distance, 0.28, sin(yaw) * distance],
                axis: tiltedAxis(yaw: yaw, tilt: random.float(in: 0.24...0.56)),
                length: random.float(in: 2.10...3.20),
                radius: random.float(in: 0.18...0.34),
                sides: 5,
                random: &random
            )
        }

        // Four near-vertical gold prisms carry the spike of the silhouette and
        // all of the node's light.
        for index in 0..<4 {
            let yaw = Float(index) / 4 * 2 * .pi + random.float(in: -0.5...0.5)
            let distance = random.float(in: 0.06...0.36)
            addCrystal(
                into: &gold,
                base: [cos(yaw) * distance, 0.30, sin(yaw) * distance],
                axis: tiltedAxis(yaw: yaw, tilt: random.float(in: 0.02...0.22)),
                length: random.float(in: 3.20...4.40),
                radius: random.float(in: 0.24...0.38),
                sides: 6,
                random: &random
            )
        }

        // Unlit inner slivers: excluded from the shadow map by `LightingRig`, so
        // they sit *inside* the cluster as a light leak rather than as more
        // geometry casting more shadow onto the crystal around them.
        for index in 0..<4 {
            let yaw = Float(index) / 4 * 2 * .pi + 0.9
            let distance = random.float(in: 0.22...0.52)
            addCrystal(
                into: &core,
                base: [cos(yaw) * distance, 0.28, sin(yaw) * distance],
                axis: tiltedAxis(yaw: yaw, tilt: random.float(in: 0.05...0.30)),
                length: random.float(in: 1.40...2.40),
                radius: random.float(in: 0.07...0.13),
                sides: 3,
                random: &random
            )
        }

        pool.addCap(
            ring: StructureGeometry.ring(sides: 7, radius: 1.85, y: 0.04),
            pivot: [0, -0.2, 0]
        )

        let entity = StructureAssembly.entity(
            named: "deposit.lumen",
            zones: [
                StructureZone(
                    "collar", collar,
                    StructureMaterial.matte(
                        StructureMaterial.shade(SunfoldPalette.neutralRock, 0.94),
                        roughness: 0.98, surface: .rimStone
                    )
                ),
                StructureZone(
                    "crystal", ivory,
                    MaterialLibrary.material(
                        .crystallineLumen,
                        tint: SunfoldPalette.sunwovenIvory,
                        roughness: 0.26,
                        emissiveIntensity: 1.7
                    )
                ),
                StructureZone(
                    "gold", gold,
                    MaterialLibrary.material(
                        .crystallineLumen,
                        tint: SunfoldPalette.resourceTint(.lumen),
                        roughness: 0.22,
                        emissiveIntensity: 3.4
                    )
                ),
                StructureZone("core", core, StructureMaterial.glow(SunfoldPalette.resourceTint(.lumen), opacity: 0.92)),
                StructureZone(
                    "pool", pool,
                    StructureMaterial.glow(
                        SunfoldPalette.resourceTint(.lumen),
                        opacity: 0.20, strength: 0.55, whiten: 0
                    )
                ),
            ]
        )
        return varied(entity, random: &random, spread: 0.90...1.18)
    }

    // MARK: - Aether

    /// A vapour vent: a bare stone lip with everything of interest suspended in
    /// the air above it.
    ///
    /// ~3.2 m across, ~3.3 m tall, and almost all of that height is empty. The
    /// previous version put a solid boulder in the middle, which made it read at
    /// a glance as a small Matter node; a *crater lip* of seven low stones with
    /// nothing inside reads as a hole in the ground with something coming out of
    /// it, and nothing else in the world does that. The floating shards are the
    /// only geometry in the game that does not touch the ground — that is the
    /// point, and it only lands if the ground is left empty.
    static func aether(seed: UInt64) -> Entity {
        var random = DeterministicRandom.stream(seed: seed, tag: "deposit.aether")

        var lip = StructureBuilder(uv: crystalUV)
        var shard = StructureBuilder(uv: crystalUV)
        var wisp = StructureBuilder(uv: crystalUV)
        var mote = StructureBuilder(uv: crystalUV)
        var pool = StructureBuilder(uv: crystalUV)

        // The vent lip: low stones on a ring, uneven enough that the opening is
        // read as broken rather than as a built kerb.
        for index in 0..<7 {
            let angle = Float(index) / 7 * 2 * .pi + random.float(in: -0.22...0.22)
            let distance = random.float(in: 0.82...1.10)
            lip.addBoulder(
                center: [cos(angle) * distance, sin(angle) * distance],
                radius: random.float(in: 0.26...0.44),
                height: random.float(in: 0.16...0.42),
                sides: 5, random: &random
            )
        }
        // Two chips thrown clear of the lip so the footprint is not a clean
        // circle at any camera yaw.
        for index in 0..<2 {
            let angle = Float(index) * 2.9 + random.float(in: 0...1)
            let distance = random.float(in: 1.24...1.58)
            lip.addBoulder(
                center: [cos(angle) * distance, sin(angle) * distance],
                radius: random.float(in: 0.12...0.22),
                height: random.float(in: 0.08...0.18),
                sides: 4, random: &random
            )
        }

        // Suspended shards. One hero shard high and central, three smaller ones
        // orbiting it — a constellation, so the eye reads a group rather than
        // three unrelated floating objects.
        let heroHeight = random.float(in: 1.95...2.55)
        let heroSpan = random.float(in: 0.52...0.72)
        shard.addShard(
            ring: StructureGeometry.ring(
                sides: 5, radius: random.float(in: 0.30...0.42),
                y: heroHeight, phase: random.float(in: 0...1)
            ),
            top: [0, heroHeight + heroSpan, 0],
            bottom: [0, heroHeight - heroSpan * 0.82, 0]
        )
        for index in 0..<3 {
            let angle = Float(index) / 3 * 2 * .pi + random.float(in: -0.4...0.4)
            let distance = random.float(in: 0.58...1.04)
            let center = SIMD2<Float>(cos(angle) * distance, sin(angle) * distance)
            let height = random.float(in: 1.10...2.05)
            let span = random.float(in: 0.26...0.44)
            shard.addShard(
                ring: StructureGeometry.ring(
                    sides: 4, radius: random.float(in: 0.14...0.24),
                    y: height, phase: angle, center: center
                ),
                top: [center.x, height + span, center.y],
                bottom: [center.x, height - span, center.y]
            )
        }

        // Motes: unlit, tiny, spread over the whole height band so the column of
        // air above the vent is legibly occupied.
        for index in 0..<6 {
            let angle = Float(index) * 2.399_963 + random.float(in: -0.3...0.3)
            let distance = random.float(in: 0.34...1.36)
            let center = SIMD2<Float>(cos(angle) * distance, sin(angle) * distance)
            let height = random.float(in: 0.55...3.10)
            mote.addShard(
                ring: StructureGeometry.ring(sides: 3, radius: random.float(in: 0.06...0.11), y: height, center: center),
                top: [center.x, height + 0.19, center.y],
                bottom: [center.x, height - 0.19, center.y]
            )
        }

        // Three rising wisps, each a thin ribbon on a slow helix. Thinner than
        // before: a wisp that is wide enough to read as a plate stops reading as
        // vapour.
        for index in 0..<3 {
            let start = random.float(in: 0...(2 * .pi))
            let radius = random.float(in: 0.46...0.78)
            let turn = random.float(in: 1.5...2.5) * (index == 1 ? -1 : 1)
            let top = random.float(in: 2.05...2.75)

            func node(_ step: Int) -> SIMD3<Float> {
                let t = Float(step) / 5
                let angle = start + turn * t
                // The helix opens as it rises, so the column reads as dispersing
                // rather than as a drawn cylinder.
                let sweep = radius * (1 + t * 0.55)
                return [cos(angle) * sweep, 0.28 + t * top, sin(angle) * sweep]
            }

            for step in 0..<5 {
                let low = node(step)
                let high = node(step + 1)
                let outward = StructureGeometry.direction([low.x + high.x, 0, low.z + high.z])
                let width = 0.075 * (1 - Float(step) / 6)
                let side = simd_cross([0, 1, 0], outward) * width
                wisp.addQuad(low - side, low + side, high + side, high - side, facing: outward)
            }
        }

        pool.addCap(
            ring: StructureGeometry.ring(sides: 8, radius: 1.15, y: 0.04),
            pivot: [0, -0.2, 0]
        )

        let entity = StructureAssembly.entity(
            named: "deposit.aether",
            zones: [
                // Lighter than the old outcrop on purpose. At this camera the
                // previous near-black rock plus a dark pool read as a hole cut
                // in the regolith rather than as stone.
                StructureZone(
                    "lip", lip,
                    StructureMaterial.matte(
                        StructureMaterial.blend(SunfoldPalette.neutralRock, SunfoldPalette.gravemarkRock, 0.42),
                        roughness: 0.98, surface: .rimStone
                    )
                ),
                StructureZone(
                    "shard", shard,
                    MaterialLibrary.material(
                        .crystallineAether,
                        tint: SunfoldPalette.resourceTint(.aether),
                        roughness: 0.20,
                        emissiveIntensity: 3.4
                    )
                ),
                StructureZone("wisp", wisp, StructureMaterial.glow(SunfoldPalette.sunwovenTurquoise, opacity: 0.34)),
                StructureZone("mote", mote, StructureMaterial.glow(SunfoldPalette.resourceTint(.aether), opacity: 0.88)),
                StructureZone(
                    "pool", pool,
                    StructureMaterial.glow(
                        SunfoldPalette.resourceTint(.aether),
                        opacity: 0.17, strength: 0.55, whiten: 0
                    )
                ),
            ]
        )
        return varied(entity, random: &random, spread: 0.88...1.12)
    }

    // MARK: - Provisions

    /// A cultivated patch: a tilled soil mound under a low dome of arching
    /// fronds, with pale seed heads standing above it.
    ///
    /// ~2.6 m across, ~1.2 m tall. Renewable, so it stays humble — but it also
    /// has to separate from the map's ambient gold scrub, which is a *spiked
    /// ball*. So nothing here is spiked: every frond is a three-segment arc that
    /// rises and turns back over, giving a domed, drooping canopy that is the
    /// opposite silhouette. Three straight furrow ridges under it say
    /// "cultivated" without needing a fence, and the hue is pulled off pure gold
    /// toward olive so the patch separates from scrub by colour as well as form.
    static func provisions(seed: UInt64) -> Entity {
        var random = DeterministicRandom.stream(seed: seed, tag: "deposit.provisions")

        var soil = StructureBuilder(uv: crystalUV)
        var frond = StructureBuilder(uv: crystalUV)
        var head = StructureBuilder(uv: crystalUV)
        var husk = StructureBuilder(uv: crystalUV)
        var pool = StructureBuilder(uv: crystalUV)

        soil.addBoulder(
            center: [0, 0], radius: 0.86,
            height: random.float(in: 0.20...0.30),
            sides: 7, random: &random
        )

        // Three parallel furrow ridges. Straight, evenly spaced and man-made —
        // the one deliberately regular thing in a file of jittered rock, because
        // regularity is what "tilled" means.
        let furrowYaw = random.float(in: 0...(2 * .pi))
        let along = SIMD3<Float>(cos(furrowYaw), 0, sin(furrowYaw))
        let across = SIMD3<Float>(-sin(furrowYaw), 0, cos(furrowYaw))
        for index in -1...1 {
            let offset = across * (Float(index) * 0.44)
            let reach = random.float(in: 0.58...0.74)
            let halfWidth = across * 0.13
            let start = offset - along * reach + [0, 0.14, 0]
            soil.addFin(
                start - halfWidth,
                start + halfWidth,
                start + [0, 0.11, 0],
                extrude: along * (reach * 2)
            )
        }

        // Ten arching fronds. Three segments each: up, over, down.
        for index in 0..<10 {
            let yaw = Float(index) / 10 * 2 * .pi + random.float(in: -0.24...0.24)
            let root = SIMD3<Float>(cos(yaw) * random.float(in: 0.10...0.30), 0.22, sin(yaw) * random.float(in: 0.10...0.30))
            addArchingFrond(
                into: &frond,
                base: root,
                yaw: yaw,
                reach: random.float(in: 0.78...1.16),
                rise: random.float(in: 0.52...0.80),
                width: random.float(in: 0.085...0.135),
                segments: 3
            )
        }

        // Pale seed heads on straight stems, standing proud of the canopy. The
        // one high-value accent in an otherwise mid-value patch — without it the
        // dome has no top edge and dissolves into the ground behind it.
        for index in 0..<5 {
            let yaw = Float(index) / 5 * 2 * .pi + random.float(in: -0.4...0.4)
            let distance = random.float(in: 0.14...0.42)
            let center = SIMD2<Float>(cos(yaw) * distance, sin(yaw) * distance)
            let top = random.float(in: 0.92...1.20)
            head.addSpire(
                base: StructureGeometry.ring(sides: 4, radius: random.float(in: 0.07...0.11), y: 0.46, phase: yaw, center: center),
                apex: [center.x, top, center.y]
            )
        }

        // Dry stalks: a darker, straighter minority so the canopy is not one
        // flat tone and one flat direction.
        for index in 0..<5 {
            let yaw = Float(index) / 5 * 2 * .pi + 0.8
            let base = SIMD3<Float>(cos(yaw) * 0.42, 0.16, sin(yaw) * 0.42)
            let tip = base + [
                cos(yaw) * random.float(in: 0.14...0.34),
                random.float(in: 0.34...0.58),
                sin(yaw) * random.float(in: 0.14...0.34),
            ]
            husk.addBlade(base: base, tip: tip, side: [0.06, 0, 0], lift: 0.05)
        }

        pool.addCap(
            ring: StructureGeometry.ring(sides: 7, radius: 1.06, y: 0.03),
            pivot: [0, -0.2, 0]
        )

        let entity = StructureAssembly.entity(
            named: "deposit.provisions",
            zones: [
                StructureZone(
                    "soil", soil,
                    StructureMaterial.matte(
                        StructureMaterial.shade(SunfoldPalette.sunwovenRock, 0.74),
                        roughness: 0.99, surface: .regolithGround
                    )
                ),
                // Saffron pulled 16% toward turquoise: still a mix of two locked
                // palette colours, no new hue, but far enough off pure gold that
                // a patch never reads as one of the map's gold scrub bushes.
                StructureZone(
                    "frond", frond,
                    StructureMaterial.matte(
                        StructureMaterial.blend(SunfoldPalette.resourceTint(.provisions), SunfoldPalette.sunwovenTurquoise, 0.16),
                        roughness: 0.95, surface: .growth
                    )
                ),
                StructureZone(
                    "head", head,
                    StructureMaterial.matte(
                        StructureMaterial.shade(SunfoldPalette.sunwovenIvory, 0.94),
                        roughness: 0.88, surface: .wovenIvory
                    )
                ),
                StructureZone(
                    "husk", husk,
                    StructureMaterial.matte(
                        StructureMaterial.shade(SunfoldPalette.resourceTint(.provisions), 0.66),
                        roughness: 0.98, surface: .growth
                    )
                ),
                StructureZone(
                    "pool", pool,
                    StructureMaterial.glow(
                        SunfoldPalette.resourceTint(.provisions),
                        opacity: 0.15, strength: 0.45, whiten: 0
                    )
                ),
            ]
        )
        return varied(entity, random: &random, spread: 0.84...1.18)
    }

    // MARK: - Per-instance variation

    /// Gives a finished node its own yaw and scale.
    ///
    /// Mesh jitter alone is not enough: two clusters built from different seeds
    /// still share a *mass distribution*, and at 60 px tall that is most of what
    /// the eye compares. A yaw plus a 0.85–1.18 spread and an independent height
    /// factor breaks the remaining regularity for four float draws.
    ///
    /// Set on the root transform, which is safe: `EntityPresenter` only assigns
    /// `entity.position` afterwards, and that writes translation alone.
    private static func varied(
        _ entity: Entity,
        random: inout DeterministicRandom,
        spread: ClosedRange<Float>
    ) -> Entity {
        let yaw = random.float(in: 0...(2 * .pi))
        let plan = random.float(in: spread)
        let lift = random.float(in: 0.92...1.14)
        entity.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
        entity.scale = [plan, plan * lift, plan]
        return entity
    }

    // MARK: - Crystal primitive

    /// A tapered faceted prism growing from `base` along `axis`.
    ///
    /// `StructureBuilder.addBoulder` cannot express this: its rings are always
    /// horizontal, so a leaning crystal comes out as a leaning *rock*. A prism
    /// needs rings perpendicular to its own growth axis, which is what gives the
    /// long unbroken facets that catch the key light as one bright band — the
    /// single strongest cue that something is crystal rather than stone.
    ///
    /// Four rings, not two: foot, belly, shoulder, apex. The belly bulge is what
    /// keeps the form from reading as a cone, and the shared per-facet radius
    /// profile is what keeps opposite facets from being identical widths.
    private static func addCrystal(
        into builder: inout StructureBuilder,
        base: SIMD3<Float>,
        axis: SIMD3<Float>,
        length: Float,
        radius: Float,
        sides: Int,
        random: inout DeterministicRandom
    ) {
        let normal = StructureGeometry.direction(axis)
        let (u, v) = orthonormal(normal)
        let count = max(sides, 3)
        let phase = random.float(in: 0...(2 * .pi))
        let profile = (0..<count).map { _ in random.float(in: 0.80...1.18) }
        let shoulderAt = random.float(in: 0.60...0.78)
        let waist = random.float(in: 0.40...0.62)

        // The foot sinks below `base` so a crystal never shows a floating hem
        // where it meets rock or soil.
        let foot = prismRing(
            center: base - normal * (radius * 0.45),
            u: u, v: v,
            radii: profile.map { $0 * radius * 0.86 },
            phase: phase
        )
        let belly = prismRing(
            center: base + normal * (length * 0.17),
            u: u, v: v,
            radii: profile.map { $0 * radius },
            phase: phase
        )
        let shoulder = prismRing(
            center: base + normal * (length * shoulderAt),
            u: u, v: v,
            radii: profile.map { $0 * radius * waist },
            phase: phase
        )
        // The tip is nudged off-axis so the termination is asymmetric, the way a
        // real crystal's is.
        let apex = base + normal * length + u * (random.float(in: -0.28...0.28) * radius)

        let pivot = base + normal * (length * 0.34)
        builder.addBand(lower: foot, upper: belly, pivot: pivot)
        builder.addBand(lower: belly, upper: shoulder, pivot: pivot)
        builder.addFan(ring: shoulder, apex: apex, pivot: pivot)
    }

    /// A closed polygon in the plane spanned by `u` and `v`, centred on `center`.
    private static func prismRing(
        center: SIMD3<Float>,
        u: SIMD3<Float>,
        v: SIMD3<Float>,
        radii: [Float],
        phase: Float
    ) -> [SIMD3<Float>] {
        let count = radii.count
        guard count >= 3 else { return [] }
        return (0..<count).map { index in
            let angle = phase + Float(index) / Float(count) * 2 * .pi
            return center + u * (cos(angle) * radii[index]) + v * (sin(angle) * radii[index])
        }
    }

    /// Any two unit vectors perpendicular to `axis` and to each other.
    ///
    /// The reference vector is swapped near the poles: crossing with a vector
    /// almost parallel to the axis gives a near-zero result and a ring that
    /// degenerates to a line, and a vertical crystal is the common case.
    private static func orthonormal(_ axis: SIMD3<Float>) -> (SIMD3<Float>, SIMD3<Float>) {
        let normal = StructureGeometry.direction(axis)
        let reference: SIMD3<Float> = abs(normal.y) > 0.9 ? [1, 0, 0] : [0, 1, 0]
        let u = StructureGeometry.direction(simd_cross(reference, normal), fallback: [1, 0, 0])
        return (u, simd_cross(normal, u))
    }

    /// A unit growth axis leaning `tilt` radians away from vertical, in the
    /// compass direction `yaw`. Crystals lean *outward* from their cluster
    /// centre when the two share a yaw, which is what makes a fan a fan.
    private static func tiltedAxis(yaw: Float, tilt: Float) -> SIMD3<Float> {
        [sin(tilt) * cos(yaw), cos(tilt), sin(tilt) * sin(yaw)]
    }

    // MARK: - Foliage primitive

    /// A frond that rises, turns over and droops — a quadratic Bézier walked in
    /// `segments` folded blades, each narrower than the last.
    ///
    /// A straight blade from base to tip is the spiked-ball silhouette the panel
    /// called out. The arc is the whole difference: it puts the frond's highest
    /// point partway along its length instead of at its end, so a ring of them
    /// makes a dome rather than a star.
    private static func addArchingFrond(
        into builder: inout StructureBuilder,
        base: SIMD3<Float>,
        yaw: Float,
        reach: Float,
        rise: Float,
        width: Float,
        segments: Int
    ) {
        let count = max(segments, 1)
        let outward = SIMD3<Float>(cos(yaw), 0, sin(yaw))
        let control = base + outward * (reach * 0.30) + [0, rise * 1.40, 0]
        let tip = base + outward * reach + [0, rise * 0.34, 0]

        func point(_ t: Float) -> SIMD3<Float> {
            let inverse = 1 - t
            return base * (inverse * inverse) + control * (2 * inverse * t) + tip * (t * t)
        }

        var previous = base
        for index in 0..<count {
            let next = point(Float(index + 1) / Float(count))
            let along = StructureGeometry.direction(next - previous, fallback: outward)
            let taper = width * (1 - 0.68 * Float(index) / Float(count))
            let side = StructureGeometry.direction(simd_cross([0, 1, 0], along), fallback: [1, 0, 0]) * taper
            builder.addBlade(base: previous, tip: next, side: side, lift: taper * 0.6)
            previous = next
        }
    }
}
