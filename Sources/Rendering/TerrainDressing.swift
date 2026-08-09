import Foundation
import RealityKit
import UIKit
import simd

/// Dresses the habitable surface of a fragment.
///
/// Concept 01's home island is not a blank plate: it carries tonal variation in
/// the soil, a darker band where the ground turns down into the rim, sun-woven
/// gold lattice seams running across the terrain, and — the part that actually
/// makes it read as a *place* — planting. Slender pale trees standing in a
/// corner grove, low golden scrub massed into irregular thickets, loose grass
/// tufts between them, and grey rock scattered in clusters, all separated by
/// large areas of bare ground.
///
/// Three properties of that planting are load-bearing, and each is implemented
/// here rather than assumed:
///
/// 1. **Class variety.** Four authored prop forms, not one lump: `paleTree`,
///    `scrubClump`, `bladeTuft`, `rockScatter` (plus `mineralSpikes` on
///    Gravemark ground). They differ in silhouette *and* in material — bark is
///    woven ivory, foliage is growth, rock is fractured stone — so a player can
///    tell wood from leaf from stone without reading a tooltip.
/// 2. **Clustered density.** Placement is masked by a deterministic fbm field,
///    so growth thickens into thickets and thins to nothing in between. An
///    even carpet of props reads as a scatter debug pass; concept 01's negative
///    space is as deliberate as its planting.
/// 3. **Ground contact.** Every prop's lowest geometry sinks slightly below
///    y = 0, is shaded down a value ladder toward the ground colour, and stands
///    on a soft dust decal. Without those three a prop meets the terrain on a
///    hard intersection line and reads as a decal standing on end.
///
/// Everything here is decoration. It never changes where a unit may stand, never
/// blocks a tap, and never carries state — legality lives in `WorldMap` and
/// `MovementSystem` alone. The only rule it obeys is *stay out of the way*: props
/// avoid the circles the simulation has already claimed, so nothing is ever
/// buried under a Core or a deposit.
@MainActor
enum TerrainDressing {

    /// A circle of ground that scatter must leave alone, in world space.
    struct KeepClear {
        let center: WorldPoint
        let radius: Float
    }

    /// Flat ground decals: box mapping, shared plane, shared origin.
    private static let groundUV = MaterialLibrary.structureUVProjection
    /// Scattered props: face-plane projection, no stretch at any slant.
    private static let propUV = MaterialLibrary.facePlanarUVProjection

    // MARK: - Claimed ground

    /// The circles the simulation's own entities occupy at match start, plus the
    /// dock and staging points a player will walk through.
    ///
    /// Read once, at scene build. Dressing is static: a Farm built later simply
    /// stands on the grass, which is the correct read anyway.
    static func keepClear(for simulation: SkirmishSimulation) -> [KeepClear] {
        var circles: [KeepClear] = []

        for building in simulation.buildings.values {
            // Cores get a wide plaza keep-clear so the opening fight / staging
            // ground stays open; other buildings keep a modest ring.
            let pad: Float = building.kind == .civilizationCore ? 7.5 : 2.2
            circles.append(
                KeepClear(center: building.position, radius: building.kind.footprintRadius + pad)
            )
        }
        for unit in simulation.units.values {
            circles.append(
                KeepClear(center: unit.position, radius: unit.kind.footprintRadius + 1.6)
            )
        }
        for deposit in simulation.deposits.values {
            // Wide enough that a citizen can stand anywhere in the work radius
            // without a rock through their shins — plus a little open apron so
            // gather rings do not sit inside a thicket.
            circles.append(
                KeepClear(center: deposit.position, radius: Deposit.workRadius + 2.4)
            )
        }

        // Causeway landings and boarding points: the two places a player is
        // guaranteed to route units through.
        let map = simulation.map
        for causeway in map.causeways {
            circles.append(
                KeepClear(center: map.dockPoint(on: causeway.from, facing: causeway.to), radius: 5.0)
            )
            circles.append(
                KeepClear(center: map.dockPoint(on: causeway.to, facing: causeway.from), radius: 5.0)
            )
            circles.append(
                KeepClear(center: map.stagingPoint(on: causeway.from, facing: causeway.to), radius: 4.0)
            )
            circles.append(
                KeepClear(center: map.stagingPoint(on: causeway.to, facing: causeway.from), radius: 4.0)
            )
        }

        return circles
    }

    // MARK: - Build

    /// Builds the dressing for one fragment, in fragment-local coordinates.
    ///
    /// `rimRadii` is the jittered rim the fragment mesh actually used, so seams
    /// and props stop at the real edge rather than at a nominal circle — no prop
    /// left hanging over the void, no seam cut off in mid-air.
    static func build(
        fragment: Fragment,
        map: WorldMap,
        rimRadii: [Float],
        seed: UInt64,
        keepClear: [KeepClear]
    ) -> Entity {
        var random = DeterministicRandom.stream(seed: seed, tag: "dressing.\(fragment.id.rawValue)")

        let character = character(of: fragment.id)
        let colors = SunfoldPalette.fragmentColors(for: fragment.id)
        // A shore margin as well as the waterline itself: a tree whose trunk is
        // exactly on the bank still has half its crown over the channel, and the
        // bank wall is the one place on the plate where that is unmistakable.
        let rim = RimProfile(radii: rimRadii, fallback: fragment.radius) { local in
            let point = fragment.center + local
            return !map.isLand(point) || map.waterDepth(at: point) > -1.6
        }

        // Local-space keep-clear, so the scatter never has to think in world space.
        let claimed: [KeepClear] = keepClear.map {
            KeepClear(center: $0.center - fragment.center, radius: $0.radius)
        }

        // Two projections, chosen per zone rather than per file.
        //
        // The shore band, the tone patches, the dust decals and the seams are
        // all horizontal decals lying on the habitable top, so box mapping is
        // exactly right: every one of them projects onto the same XZ plane from
        // the same origin, which keeps the decoration grained continuously with
        // the ground under it instead of restarting at every triangle.
        //
        // The scatter is the opposite — boulders, leaning shards, tree crowns
        // and folded blades, all arbitrarily slanted — so it takes face-plane
        // projection, which has no stretch at any angle. Both quote the same
        // `MaterialLibrary.metersPerTile`, so a rock and the ground it sits on
        // still carry the same texels per metre.
        var shore = StructureBuilder(uv: groundUV)
        var toneWarm = StructureBuilder(uv: groundUV)
        var toneCool = StructureBuilder(uv: groundUV)
        var seams = StructureBuilder(uv: groundUV)
        var props = Props(uv: propUV, groundUV: groundUV)

        // The decal zones lie *on* the ground, so they drape: every vertex takes
        // the terrain height under it and a seam bends over a swell rather than
        // slicing through it. The props are handled separately, per instance, in
        // `addScatter` — a tree translates onto the ground, it does not drape
        // over it.
        let drape: (SIMD2<Float>) -> Float = { [radius = fragment.radius] point in
            FragmentMeshFactory.groundHeight(local: point, radius: radius)
        }
        shore.lift = drape
        toneWarm.lift = drape
        toneCool.lift = drape
        seams.lift = drape

        addShoreBand(into: &shore, rim: rim)
        addTonePatches(
            warm: &toneWarm,
            cool: &toneCool,
            fragment: fragment,
            rim: rim,
            random: &random
        )
        addSeams(
            into: &seams,
            fragment: fragment,
            rim: rim,
            character: character,
            seed: seed &+ salt(fragment.id),
            random: &random
        )

        // Gold ground-inlay around the Core — concept 01's plaza rosette. Home
        // fragments only; draped through the same height field as other decals
        // so it rides the settlement pan instead of floating as a flat disc.
        var rosette = StructureBuilder(uv: groundUV)
        rosette.lift = drape
        if fragment.id.isHome {
            addCoreRosette(into: &rosette, random: &random)
        }

        addScatter(
            into: &props,
            fragment: fragment,
            rim: rim,
            character: character,
            claimed: claimed,
            seed: seed &+ salt(fragment.id),
            random: &random
        )

        // Every zone names its surface class rather than letting the library
        // infer one from the tint. Inference is right for a hue that is only ever
        // one material, but a Gravemark fragment's ground colour *is* the colour
        // of its armour plate — left to infer, the habitable top of a Gravemark
        // fragment would come back as brushed metal instead of dust.
        //
        // It matters twice as much on the props: a foliage tint blended toward
        // the soil for ground contact would otherwise be classified as regolith
        // and come back grained like dirt instead of like leaf.
        var zones: [StructureZone] = [
            StructureZone(
                "shore",
                shore,
                StructureMaterial.matte(shade(colors.surface, 0.88), surface: .regolithGround)
            ),
            StructureZone(
                "tone.warm",
                toneWarm,
                StructureMaterial.matte(shade(colors.surface, 1.028), surface: .regolithGround)
            ),
            StructureZone(
                "tone.cool",
                toneCool,
                StructureMaterial.matte(shade(colors.surface, 0.962), surface: .regolithGround)
            ),
            StructureZone("seam", seams, seamMaterial(character: character, surface: colors.surface)),
            StructureZone(
                "rosette",
                rosette,
                StructureMaterial.glow(SunfoldPalette.sunwovenGold, opacity: 0.38)
            ),
        ]
        zones.append(contentsOf: props.zones(character: character, colors: colors))

        let root = Entity()
        root.name = "dressing.\(fragment.id.rawValue)"
        var total = 0
        for zone in zones {
            total += zone.builder.triangleCount
            guard let child = zone.builder.makeEntity(
                named: "\(root.name).\(zone.suffix)",
                material: zone.material
            ) else { continue }
            root.addChild(child)
        }

        DebugLog.info(
            "Terrain dressing '\(fragment.id.rawValue)': \(total) triangles across \(root.children.count) zones."
        )
        return root
    }

    // MARK: - Core plaza rosette

    /// A gold inlay ring with petal lobes around the Civilization Core.
    ///
    /// Placed in fragment-local space at the origin (the Core sits on
    /// `fragment.center`). Clearance sits on `Height.rosette` so the drape
    /// clears `FragmentMeshFactory.chordError` across the settlement pan.
    private static func addCoreRosette(
        into builder: inout StructureBuilder,
        random: inout DeterministicRandom
    ) {
        let up = SIMD3<Float>(0, 1, 0)
        let petals = 8
        let phase = random.float(in: 0...(Float.pi / Float(petals)))
        let inner: Float = 5.55
        let outer: Float = 8.85
        let mid: Float = 7.05
        let y = Height.rosette

        // Outer annulus.
        let outerRing = StructureGeometry.ring(sides: petals * 4, radius: outer, y: y, phase: phase)
        let midRing = StructureGeometry.ring(sides: petals * 4, radius: mid, y: y, phase: phase)
        let innerRing = StructureGeometry.ring(sides: petals * 4, radius: inner, y: y, phase: phase)
        for index in outerRing.indices {
            let next = (index + 1) % outerRing.count
            builder.addQuad(midRing[index], outerRing[index], outerRing[next], midRing[next], facing: up)
            builder.addQuad(innerRing[index], midRing[index], midRing[next], innerRing[next], facing: up)
        }

        // Petal lobes between the mid and outer rings — soft diamonds, not spikes.
        for petal in 0..<petals {
            let a0 = phase + Float(petal) / Float(petals) * 2 * .pi
            let a1 = phase + Float(petal + 1) / Float(petals) * 2 * .pi
            let midAngle = (a0 + a1) * 0.5
            let tipR = outer + random.float(in: 0.35...0.75)
            let tip = point(midAngle, tipR, y: y)
            let left = point(a0, mid + 0.15, y: y)
            let right = point(a1, mid + 0.15, y: y)
            let root = point(midAngle, mid - 0.35, y: y)
            builder.addTriangle(root, left, tip, facing: up)
            builder.addTriangle(root, tip, right, facing: up)
        }

        // Thin radial spokes from the plinth kerb out to mid — plaza geometry.
        for spoke in 0..<petals {
            let angle = phase + (Float(spoke) + 0.5) / Float(petals) * 2 * .pi
            let halfWidth: Float = 0.11
            let along = SIMD2<Float>(cos(angle), sin(angle))
            let side = SIMD2<Float>(-along.y, along.x) * halfWidth
            let a = SIMD2<Float>(along.x * (inner + 0.08), along.y * (inner + 0.08)) + side
            let b = SIMD2<Float>(along.x * (inner + 0.08), along.y * (inner + 0.08)) - side
            let c = SIMD2<Float>(along.x * (mid - 0.1), along.y * (mid - 0.1)) - side
            let d = SIMD2<Float>(along.x * (mid - 0.1), along.y * (mid - 0.1)) + side
            builder.addQuad(
                [a.x, y + 0.001, a.y],
                [b.x, y + 0.001, b.y],
                [c.x, y + 0.001, c.y],
                [d.x, y + 0.001, d.y],
                facing: up
            )
        }
    }

    // MARK: - Shore band

    /// A darker ring of ground just inside the rim. This is what stops the
    /// habitable top reading as a flat plate: the eye gets an edge to land on
    /// before the surface turns down into rock.
    private static func addShoreBand(into builder: inout StructureBuilder, rim: RimProfile) {
        let sides = rim.radii.count
        guard sides >= 3 else { return }
        let up = SIMD3<Float>(0, 1, 0)

        for index in 0..<sides {
            let next = (index + 1) % sides
            let angleA = Float(index) / Float(sides) * 2 * .pi
            let angleB = Float(next) / Float(sides) * 2 * .pi
            let outerA = point(angleA, rim.radii[index] * 0.998, y: Height.shore)
            let outerB = point(angleB, rim.radii[next] * 0.998, y: Height.shore)
            let innerA = point(angleA, rim.radii[index] * 0.845, y: Height.shore)
            let innerB = point(angleB, rim.radii[next] * 0.845, y: Height.shore)
            builder.addQuad(innerA, outerA, outerB, innerB, facing: up)
        }
    }

    // MARK: - Tone patches

    /// Broad, soft polygons of slightly shifted soil tone. Warm and cool are two
    /// zones rather than a tint per patch, so the whole fragment still costs two
    /// draws no matter how many patches it carries.
    private static func addTonePatches(
        warm: inout StructureBuilder,
        cool: inout StructureBuilder,
        fragment: Fragment,
        rim: RimProfile,
        random: inout DeterministicRandom
    ) {
        let count = max(3, Int(fragment.radius * 0.42))
        let up = SIMD3<Float>(0, 1, 0)

        for index in 0..<count {
            let angle = random.float(in: 0...(2 * .pi))
            let localRim = rim.radius(atAngle: angle)
            let distance = random.float(in: 0...(localRim * 0.58))
            let wanted = fragment.radius * random.float(in: 0.16...0.34)
            // Never let a patch spill past the shore band.
            let radius = min(wanted, max(localRim * 0.82 - distance, 0))
            guard radius > 1.2 else { continue }

            let center = SIMD2<Float>(cos(angle) * distance, sin(angle) * distance)
            let sides = 11
            let phase = random.float(in: 0...(2 * .pi))
            let radii = (0..<sides).map { _ in radius * random.float(in: 0.84...1.16) }
            // Each patch gets its own hairline so overlapping patches never
            // z-fight against one another.
            let y = Height.tone + Float(index) * 0.0016
            let ring = StructureGeometry.ring(radii: radii, y: y, phase: phase, center: center)
            let apex = SIMD3<Float>(center.x, y, center.y)

            for vertex in ring.indices {
                let next = (vertex + 1) % ring.count
                if index.isMultiple(of: 2) {
                    warm.addTriangle(apex, ring[vertex], ring[next], facing: up)
                } else {
                    cool.addTriangle(apex, ring[vertex], ring[next], facing: up)
                }
            }
        }
    }

    // MARK: - Seams

    /// Sunwoven ground carries a lattice of hairline gold seams tracing irregular
    /// cells — the weave the civilisation has run through the rock. Gravemark
    /// ground carries the opposite idea: gravity fractures wandering out from a
    /// stress point. Neutral ground gets a few quiet stone veins.
    ///
    /// The two silhouettes are the identity read at a glance: order versus damage.
    private static func addSeams(
        into builder: inout StructureBuilder,
        fragment: Fragment,
        rim: RimProfile,
        character: Character,
        seed: UInt64,
        random: inout DeterministicRandom
    ) {
        switch character {
        case .planted:
            addLattice(into: &builder, fragment: fragment, rim: rim, seed: seed)
        }
    }

    /// A jittered hexagonal cell network.
    ///
    /// Two crossing straight families read as graph paper, which is not what
    /// concept 01 shows — its seams enclose irregular cells the way dried ground
    /// or leaded glass does. A hex tiling gives closed cells for free; jittering
    /// each corner by a hash of its own position, rather than per-hex, keeps
    /// shared corners agreeing so the network stays watertight instead of
    /// splitting into loose sticks.
    private static func addLattice(
        into builder: inout StructureBuilder,
        fragment: Fragment,
        rim: RimProfile,
        seed: UInt64
    ) {
        // Measured against the rendered build: at 0.215 the cells were large
        // and regular enough to read as a honeycomb. Small cells with wander
        // past half the spacing destroy the hexagon and leave the irregular
        // closed cells concept 01 actually shows.
        let spacing = fragment.radius * 0.115
        let reach = Int(ceil(fragment.radius / spacing)) + 1
        let wander = spacing * 0.52

        /// Corner positions are derived independently by each adjoining hex, so
        /// the jitter must be a pure function of the corner itself. Quantising to
        /// a centimetre makes the two derivations agree exactly.
        func settled(_ point: SIMD2<Float>) -> SIMD2<Float> {
            let keyX = UInt64(bitPattern: Int64((point.x * 100).rounded()))
            let keyZ = UInt64(bitPattern: Int64((point.y * 100).rounded()))
            var hash = seed &+ keyX &* 0x9E37_79B9_7F4A_7C15 &+ keyZ &* 0xBF58_476D_1CE4_E5B9
            func next() -> Float {
                hash ^= hash >> 30
                hash = hash &* 0xBF58_476D_1CE4_E5B9
                hash ^= hash >> 27
                return Float(hash >> 40) / Float(1 << 24) * 2 - 1  // -1 ... 1
            }
            return point + SIMD2<Float>(next(), next()) * wander
        }

        for q in -reach...reach {
            for r in -reach...reach {
                let centre = SIMD2<Float>(
                    spacing * 1.5 * Float(q),
                    spacing * 1.732_05 * (Float(r) + Float(q) * 0.5)
                )
                guard simd_length(centre) < fragment.radius + spacing else { continue }

                let corners = (0..<6).map { index -> SIMD2<Float> in
                    let angle = Float(index) / 6 * 2 * .pi
                    return settled(centre + SIMD2<Float>(cos(angle), sin(angle)) * spacing)
                }

                // Edges 0–2 of every hex cover each shared edge exactly once;
                // 3–5 are the neighbour's copy of the same three.
                for index in 0..<3 {
                    addSeamSegment(
                        into: &builder,
                        from: corners[index],
                        to: corners[(index + 1) % 6],
                        rim: rim,
                        halfWidth: 0.075
                    )
                }
            }
        }
    }

    /// One straight seam segment, dropped entirely if either end is off the land.
    /// The ragged boundary that produces is correct — concept 01's cells break up
    /// as they approach the rim rather than stopping on a clean circle.
    private static func addSeamSegment(
        into builder: inout StructureBuilder,
        from start: SIMD2<Float>,
        to end: SIMD2<Float>,
        rim: RimProfile,
        halfWidth: Float
    ) {
        guard rim.contains(start, margin: 0.955), rim.contains(end, margin: 0.955) else { return }
        let delta = end - start
        let length = simd_length(delta)
        guard length > 1e-3 else { return }
        let side = SIMD2<Float>(-delta.y, delta.x) / length * halfWidth

        builder.addQuad(
            SIMD3<Float>(start.x - side.x, Height.seam, start.y - side.y),
            SIMD3<Float>(start.x + side.x, Height.seam, start.y + side.y),
            SIMD3<Float>(end.x + side.x, Height.seam, end.y + side.y),
            SIMD3<Float>(end.x - side.x, Height.seam, end.y - side.y),
            facing: [0, 1, 0]
        )
    }

    /// A wandering crack from a stress point, narrowing as it runs out.
    private static func addFractures(
        into builder: inout StructureBuilder,
        fragment: Fragment,
        rim: RimProfile,
        count: Int,
        random: inout DeterministicRandom
    ) {
        let up = SIMD3<Float>(0, 1, 0)

        for _ in 0..<count {
            let startAngle = random.float(in: 0...(2 * .pi))
            let startDistance = random.float(in: 0...(fragment.radius * 0.22))
            var cursor = SIMD2<Float>(cos(startAngle) * startDistance, sin(startAngle) * startDistance)
            var heading = random.float(in: 0...(2 * .pi))
            let segmentLength = fragment.radius * 0.17
            let segments = 6
            var width = fragment.radius * 0.022 + 0.16

            for segment in 0..<segments {
                heading += random.float(in: -0.46...0.46)
                let direction = SIMD2<Float>(sin(heading), cos(heading))
                let next = cursor + direction * segmentLength
                guard rim.contains(next, margin: 0.90) else { break }

                let side = SIMD2<Float>(-direction.y, direction.x)
                let taper = 1 - Float(segment) / Float(segments) * 0.78
                let nextWidth = width * taper

                let a = SIMD3<Float>(cursor.x - side.x * width, Height.seam, cursor.y - side.y * width)
                let b = SIMD3<Float>(cursor.x + side.x * width, Height.seam, cursor.y + side.y * width)
                let c = SIMD3<Float>(next.x + side.x * nextWidth, Height.seam, next.y + side.y * nextWidth)
                let d = SIMD3<Float>(next.x - side.x * nextWidth, Height.seam, next.y - side.y * nextWidth)
                builder.addQuad(a, b, c, d, facing: up)

                cursor = next
                width = nextWidth
            }
        }
    }

    // MARK: - Scatter

    /// One authored prop form. The class decides silhouette, height band, the
    /// material zone the geometry lands in, and how wide a dust decal it earns.
    private enum PropClass {
        case paleTree
        case branchingMass
        case scrubClump
        case bladeTuft
        case rockScatter
        case mineralSpikes
    }

    /// Per-instance variation, drawn once per prop and threaded through the
    /// whole build so silhouette, footprint and value all move together.
    ///
    /// `wide` and `tall` are deliberately independent: a uniform scale makes
    /// twenty copies of one object at twenty sizes, which still reads as one
    /// object. Non-uniform scale in 0.8–1.3 is what makes a squat wide shrub and
    /// a lean tall one look like two plants rather than two zoom levels.
    fileprivate struct Instance {
        var center: SIMD2<Float>
        var yaw: Float
        var wide: Float
        var tall: Float
        /// Which step of the class's value ladder the lit part of this prop uses.
        /// This is the per-instance hue/value jitter, and it is the same axis the
        /// ground-contact shading walks down — see `Contact`.
        var top: Int
    }

    /// Growth and rock, placed by a masked, clustered rejection sample.
    ///
    /// Three things decide where a prop lands, in order:
    ///
    /// 1. **The clustering mask.** A deterministic fbm field over fragment-local
    ///    space. A candidate survives with probability `mask²`, which is what
    ///    turns an even scatter into thickets separated by open ground. It is a
    ///    pure function of position, so it costs no draws from the random stream
    ///    and adding it cannot shift any other subsystem's numbers.
    /// 2. **Legality.** Inside the real jittered rim, off every claimed circle.
    /// 3. **Crowding.** Cluster *sites* keep well apart; members within one
    ///    cluster deliberately do not, because touching neighbours are what make
    ///    a thicket read as one mass instead of as three separate bushes.
    ///
    /// Two passes. A fringe follows the rim, because concept 01's growth thickens
    /// into a band around the edge of the island and that band is most of what
    /// gives the fragment a silhouette from above. A second pass fills the
    /// interior, which is where structures will later stand.
    private static func addScatter(
        into props: inout Props,
        fragment: Fragment,
        rim: RimProfile,
        character: Character,
        claimed: [KeepClear],
        seed: UInt64,
        random: inout DeterministicRandom
    ) {
        var sites: [SIMD2<Float>] = []

        // The mask's feature size, in metres. Larger span + harder gate → fewer,
        // more separated thickets with deliberate open fight ground between them
        // (post-CP-14 sparse retune; CP-06 densified toward concept 01).
        let maskSpan = fragment.radius * 3.2
        let maskSalt = UInt32(truncatingIfNeeded: seed >> 17) | 1

        /// The clumping field at a fragment-local point, in 0...1.
        func mask(_ point: SIMD2<Float>) -> Float {
            let u = point.x / maskSpan + 0.5
            let v = point.y / maskSpan + 0.5
            let raw = ProceduralNoise.fbm(u, v, octaves: 3, cellsX: 5, cellsY: 5, gain: 0.55, salt: maskSalt)
            return ProceduralNoise.smoothstep(0.46, 0.74, raw)
        }

        /// Accepts a cluster site only if it is on land, off every claimed
        /// circle, and not crowding an already-placed site.
        ///
        /// **This is what caps density, not the candidate count.** A minimum
        /// separation applied by sequential rejection saturates: the reachable
        /// site count is roughly `0.55 · area / (π · spacing²)`, and past that
        /// every further candidate is refused no matter how many are offered.
        /// CP-06's first render proved it — nearly tripling the candidates moved
        /// planting coverage only 0.057 → 0.088 against concept 01's 0.271,
        /// because the 3.2 m spacing had already jammed. The spacings below are
        /// the dial; the candidate counts only need to be large enough to reach
        /// the limit they set.
        func site(_ candidate: SIMD2<Float>, spacing: Float) -> Bool {
            guard rim.contains(candidate, margin: 0.93) else { return false }
            guard claimed.allSatisfy({ simd_distance($0.center, candidate) > $0.radius }) else {
                return false
            }
            guard sites.allSatisfy({ simd_distance($0, candidate) > spacing }) else { return false }
            sites.append(candidate)
            return true
        }

        /// One prop, with its own scale, yaw, ladder step and dust decal.
        func place(_ kind: PropClass, at center: SIMD2<Float>, vigour: Float) {
            guard rim.contains(center, margin: 0.945) else { return }
            guard claimed.allSatisfy({ simd_distance($0.center, center) > $0.radius }) else { return }

            // Vigour is the mask value at the site: growth in the heart of a
            // thicket is taller and greener than the stragglers at its edge,
            // which is what makes a clump read as one organism rather than as
            // n independent draws that happen to be adjacent.
            let ladder = props.ladderCount(for: kind)
            let bias = Int((vigour * 1.2 + random.unitFloat() * 0.9).rounded(.down))
            let instance = Instance(
                center: center,
                yaw: random.float(in: 0...(2 * .pi)),
                wide: random.float(in: 0.80...1.30),
                tall: random.float(in: 0.80...1.30) * (0.86 + vigour * 0.28),
                top: min(max(ladder - 3 + bias, Contact.drop), ladder - 1)
            )

            // Rigid, not draped: one height for the whole prop, taken under its
            // footing. Draping a trunk would shear it, and the flare each prop
            // deliberately sinks below its own local zero is what hides the
            // difference between its flat base and the ground's real slope.
            let footing = FragmentMeshFactory.groundHeight(
                local: center,
                radius: fragment.radius
            )
            props.lift = { _ in footing }
            defer { props.lift = nil }

            switch kind {
            case .paleTree: addPaleTree(into: &props, instance, random: &random)
            case .branchingMass: addBranchingMass(into: &props, instance, random: &random)
            case .scrubClump: addScrubClump(into: &props, instance, random: &random)
            case .bladeTuft: addBladeTuft(into: &props, instance, random: &random)
            case .rockScatter: addRockScatter(into: &props, instance, random: &random)
            case .mineralSpikes: addMineralSpikes(into: &props, instance, random: &random)
            }
        }

        /// A cluster: one lead prop plus a falling-off tail of companions, all
        /// of the same class. This is the second scale of clumping — the mask
        /// decides *where* growth happens, the cluster decides that growth
        /// arrives in twos and threes rather than singly.
        func cluster(at center: SIMD2<Float>, vigour: Float, kinds: [PropClass], spread: Float) {
            guard let lead = kinds.first else { return }
            place(lead, at: center, vigour: vigour)

            // Companions do not go through `site`, so unlike the lead they are
            // not subject to the jamming limit — this is the one lever that
            // thickens a thicket rather than adding another one. Kept lean so
            // thickets read as accents, not carpets that choke fight space.
            let companions = Int(vigour * 2.0 + random.unitFloat() * 1.2)
            for index in 0..<companions {
                let angle = random.float(in: 0...(2 * .pi))
                let distance = spread * random.float(in: 0.42...1.15)
                let kind = kinds[min(index + 1, kinds.count - 1)]
                place(
                    kind,
                    at: center + SIMD2<Float>(cos(angle), sin(angle)) * distance,
                    vigour: vigour * random.float(in: 0.55...0.95)
                )
            }
        }

        /// Shared planted mix for every fragment. Land is civilization-
        /// independent (CP-12); faction identity is not carried by ground props.
        func kinds(vigour: Float) -> ([PropClass], Float) {
            let roll = random.unitFloat()
            let treeChance: Float = 0.10
            if roll < treeChance * (0.5 + vigour) {
                return ([.paleTree, .scrubClump, .bladeTuft], 2.4)
            }
            if roll < 0.72 {
                return ([.scrubClump, .bladeTuft, .bladeTuft], 1.7)
            }
            // Occasional mineral accent — rock variety, not a faction paint.
            if roll < 0.86 {
                return ([.rockScatter, .bladeTuft], 1.4)
            }
            return ([.mineralSpikes, .rockScatter], 1.3)
        }

        // Fringe: walk the rim at a fixed arc spacing so density is independent
        // of how large the fragment is, then let the mask thin it out.
        //
        // Post-CP-14 sparse retune: CP-06's 1.5 m arc packed the rim into a
        // continuous hedge. ~3.0 m keeps a planted silhouette without boxing
        // units into corridors of scrub.
        let fringeSpacing: Float = 3.0
        let fringeCount = max(8, Int(2 * .pi * fragment.radius / fringeSpacing))

        for index in 0..<fringeCount {
            let angle = Float(index) / Float(fringeCount) * 2 * .pi + random.float(in: -0.09...0.09)
            let localRim = rim.radius(atAngle: angle)
            let distance = localRim * random.float(in: 0.78...0.90)
            let candidate = SIMD2<Float>(cos(angle) * distance, sin(angle) * distance)

            let vigour = max(mask(candidate), 0.28)
            guard random.unitFloat() < vigour * 0.72 else { continue }
            guard site(candidate, spacing: 2.6) else { continue }

            let (classes, spread) = kinds(vigour: vigour)
            cluster(at: candidate, vigour: vigour, kinds: classes, spread: spread)
        }

        // Interior: area-uniform candidates, hard-masked. Most are still
        // rejected — open plateau between thickets is the fight ground.
        // Spacing (not candidate count) caps density; ~3.0 m leaves room for
        // unit formations that 1.5 m packing denied.
        let candidates = max(10, Int(fragment.radius * fragment.radius * 0.38))
        for _ in 0..<candidates {
            let angle = random.float(in: 0...(2 * .pi))
            let localRim = rim.radius(atAngle: angle)
            // Keep interior growth off the Core plaza band (inner ~40% of radius).
            let distance = sqrt(random.unitFloat()) * localRim * 0.78
            guard distance > localRim * 0.38 else { continue }
            let candidate = SIMD2<Float>(cos(angle) * distance, sin(angle) * distance)

            let vigour = mask(candidate)
            guard random.unitFloat() < vigour * vigour * vigour else { continue }
            guard site(candidate, spacing: 3.0) else { continue }

            let (classes, spread) = kinds(vigour: vigour)
            cluster(at: candidate, vigour: vigour, kinds: classes, spread: spread)
        }

        // Canopy pass: a few large branching masses on every fragment. Land is
        // civilization-independent — the planted silhouette is shared.
        do {
            var canopySites: [SIMD2<Float>] = []
            // Sparse tree-scale accents — enough for silhouette, not a grove.
            let canopySpacing: Float = 11.0
            let canopyCandidates = max(4, Int(fragment.radius * fragment.radius * 0.022))
            for _ in 0..<canopyCandidates {
                let angle = random.float(in: 0...(2 * .pi))
                let localRim = rim.radius(atAngle: angle)
                // Prefer mid-ring / fringe so crowns silhouette against void and
                // stay clear of the Core's claimed circle.
                let distance = localRim * random.float(in: 0.48...0.82)
                let candidate = SIMD2<Float>(cos(angle) * distance, sin(angle) * distance)

                let vigour = mask(candidate)
                guard vigour > 0.32 else { continue }
                guard random.unitFloat() < 0.40 + vigour * 0.20 else { continue }
                guard rim.contains(candidate, margin: 0.93) else { continue }
                // Extra clearance past claimed radii so large crowns do not lean
                // over the pavilion (try3).
                guard claimed.allSatisfy({
                    simd_distance($0.center, candidate) > $0.radius + 3.5
                }) else { continue }
                guard canopySites.allSatisfy({ simd_distance($0, candidate) > canopySpacing }) else {
                    continue
                }
                canopySites.append(candidate)

                place(.branchingMass, at: candidate, vigour: max(vigour, 0.55))
                if random.unitFloat() < 0.28 {
                    let footAngle = random.float(in: 0...(2 * .pi))
                    let footDist = random.float(in: 2.0...3.0)
                    place(
                        .scrubClump,
                        at: candidate + SIMD2<Float>(cos(footAngle), sin(footAngle)) * footDist,
                        vigour: vigour * 0.75
                    )
                }
            }
        }
    }

    // MARK: - Prop meshes

    /// A slender pale tree: a bare tapering trunk with a root flare, two broken
    /// branch stubs, and a crown of three small offset lobes.
    ///
    /// Concept 01's trees are *thin* and their foliage is sparse and lobed —
    /// nothing like a single ball on a stick. The three-lobe crown is what makes
    /// the silhouette break up from directly above, which is the only angle this
    /// game's camera ever sees it from.
    private static func addPaleTree(
        into props: inout Props,
        _ instance: Instance,
        random: inout DeterministicRandom
    ) {
        let center = instance.center
        let height = random.float(in: 3.4...5.0) * instance.tall
        let wide = instance.wide

        // The trunk leans, and its head is offset from its foot. A vertical
        // cylinder reads as a fence post.
        let leanAngle = instance.yaw + random.float(in: -0.7...0.7)
        let lean = random.float(in: 0.12...0.40) * wide
        let head = center + SIMD2<Float>(cos(leanAngle), sin(leanAngle)) * lean

        func along(_ t: Float) -> SIMD2<Float> { center + (head - center) * t }

        let sides = 5
        let phase = instance.yaw
        // The flare sits *below* y = 0. A trunk that stops exactly on the ground
        // plane meets it on a hard line; one that continues into it reads as
        // rooted, and the ladder darkens those verts toward the soil colour.
        let flare = StructureGeometry.ring(
            radii: (0..<sides).map { _ in 0.30 * wide * random.float(in: 0.82...1.24) },
            y: -0.09,
            phase: phase,
            center: center
        )
        let shin = StructureGeometry.ring(
            radii: (0..<sides).map { _ in 0.17 * wide * random.float(in: 0.90...1.10) },
            y: height * 0.15,
            phase: phase,
            center: along(0.15)
        )
        let waist = StructureGeometry.ring(
            sides: sides, radius: 0.115 * wide, y: height * 0.46, phase: phase, center: along(0.46)
        )
        let neck = StructureGeometry.ring(
            sides: sides, radius: 0.072 * wide, y: height * 0.72, phase: phase, center: along(0.72)
        )

        let bark = Contact(foot: -0.09, reach: height * 0.34, top: instance.top(for: props.barkSteps))
        props.bark.band(lower: flare, upper: shin, pivot: [center.x, height * 0.2, center.y], bark)
        props.bark.band(lower: shin, upper: waist, pivot: [center.x, height * 0.3, center.y], bark)
        props.bark.band(lower: waist, upper: neck, pivot: [center.x, height * 0.5, center.y], bark)

        // Two broken branch stubs. They cost four triangles each and they are
        // the difference between a tree and a broom handle.
        for index in 0..<2 {
            let t = index == 0 ? Float(0.50) : Float(0.66)
            let angle = instance.yaw + Float(index) * 2.3 + random.float(in: -0.5...0.5)
            let root = along(t)
            let socket = StructureGeometry.ring(
                sides: 3, radius: 0.075 * wide, y: height * t, phase: angle, center: root
            )
            let reach = random.float(in: 0.34...0.72) * wide
            let tip = SIMD3<Float>(
                root.x + cos(angle) * reach,
                height * (t + random.float(in: 0.10...0.20)),
                root.y + sin(angle) * reach
            )
            props.bark.fan(ring: socket, apex: tip, pivot: [root.x, height * t, root.y], bark)
        }

        // Crown: three small lobes at different heights and offsets.
        let foliage = Contact(
            foot: height * 0.55,
            reach: height * 0.30,
            top: instance.top(for: props.foliageSteps)
        )
        let crownRadius = random.float(in: 0.72...1.15) * wide
        for lobe in 0..<3 {
            let angle = instance.yaw + Float(lobe) / 3 * 2 * .pi + random.float(in: -0.4...0.4)
            let offset = crownRadius * random.float(in: 0.20...0.58)
            let seat = head + SIMD2<Float>(cos(angle), sin(angle)) * offset
            let radius = crownRadius * random.float(in: 0.52...0.94)
            let base = height * random.float(in: 0.60...0.80)
            let rise = radius * random.float(in: 0.66...1.05)

            addLobe(
                into: &props.foliage,
                center: seat,
                radius: radius,
                base: base,
                rise: rise,
                sides: 6,
                phase: angle,
                contact: foliage,
                capBottom: true,
                random: &random
            )
        }

        addContactDecal(into: &props, at: center, radius: crownRadius * 1.05 + 0.35 * wide, random: &random)
    }

    /// A large branching mass: a thick trunk that splits into three spreading
    /// limbs, each tipped with a lobed crown.
    ///
    /// Concept 01's remaining planting gap after CP-06 was never count — it was
    /// that every prop was a medium spiky clump while the concept carries a few
    /// tree-scale golden silhouettes. This is that silhouette. Kept rare by the
    /// canopy pass's 4.8 m spacing.
    private static func addBranchingMass(
        into props: inout Props,
        _ instance: Instance,
        random: inout DeterministicRandom
    ) {
        let center = instance.center
        // Tree-scale but not pavilion-burying: try3 crowns at 2.4–3.6·wide ate the Core.
        let height = random.float(in: 7.0...9.5) * instance.tall
        let wide = instance.wide * random.float(in: 1.10...1.35)

        let leanAngle = instance.yaw + random.float(in: -0.4...0.4)
        let lean = random.float(in: 0.18...0.55) * wide
        let head = center + SIMD2<Float>(cos(leanAngle), sin(leanAngle)) * lean
        func along(_ t: Float) -> SIMD2<Float> { center + (head - center) * t }

        let sides = 6
        let phase = instance.yaw
        let flare = StructureGeometry.ring(
            radii: (0..<sides).map { _ in 0.48 * wide * random.float(in: 0.82...1.22) },
            y: -0.14,
            phase: phase,
            center: center
        )
        let shin = StructureGeometry.ring(
            radii: (0..<sides).map { _ in 0.30 * wide * random.float(in: 0.90...1.10) },
            y: height * 0.18,
            phase: phase,
            center: along(0.18)
        )
        let fork = StructureGeometry.ring(
            sides: sides, radius: 0.22 * wide, y: height * 0.42, phase: phase, center: along(0.42)
        )

        let bark = Contact(foot: -0.14, reach: height * 0.40, top: instance.top(for: props.barkSteps))
        props.bark.band(lower: flare, upper: shin, pivot: [center.x, height * 0.2, center.y], bark)
        props.bark.band(lower: shin, upper: fork, pivot: [center.x, height * 0.35, center.y], bark)

        let foliage = Contact(
            foot: height * 0.40,
            reach: height * 0.40,
            top: instance.top(for: props.foliageSteps)
        )

        // Three primary limbs radiating from the fork, each with its own crown.
        let limbCount = 3
        var crownReach: Float = 0
        for limb in 0..<limbCount {
            let angle = instance.yaw + Float(limb) / Float(limbCount) * 2 * .pi
                + random.float(in: -0.35...0.35)
            let reach = random.float(in: 2.0...3.2) * wide
            crownReach = max(crownReach, reach)
            let forkPoint = along(0.42)
            let tipXZ = forkPoint + SIMD2<Float>(cos(angle), sin(angle)) * reach
            let tipY = height * random.float(in: 0.72...0.95)

            let socket = StructureGeometry.ring(
                sides: 4, radius: 0.14 * wide, y: height * 0.42, phase: angle, center: forkPoint
            )
            let midCenter = forkPoint + (tipXZ - forkPoint) * 0.55
            let mid = StructureGeometry.ring(
                sides: 4,
                radius: 0.09 * wide,
                y: (height * 0.42 + tipY) * 0.55,
                phase: angle,
                center: midCenter
            )
            let tipCenter = forkPoint + (tipXZ - forkPoint) * 0.92
            let tipRing = StructureGeometry.ring(
                sides: 4, radius: 0.05 * wide, y: tipY * 0.92, phase: angle, center: tipCenter
            )

            props.bark.band(lower: socket, upper: mid, pivot: [forkPoint.x, height * 0.5, forkPoint.y], bark)
            props.bark.band(lower: mid, upper: tipRing, pivot: [tipCenter.x, tipY * 0.7, tipCenter.y], bark)

            // Open lobed crown — sparse enough to read as tree, not another scrub mound.
            let lobeCount = random.unitFloat() < 0.45 ? 3 : 2
            let crownRadius = random.float(in: 1.60...2.40) * wide
            for lobe in 0..<lobeCount {
                let lobeAngle = angle + Float(lobe) / Float(lobeCount) * 1.6
                    + random.float(in: -0.3...0.3)
                let offset = crownRadius * random.float(in: 0.28...0.78)
                let seat = tipXZ + SIMD2<Float>(cos(lobeAngle), sin(lobeAngle)) * offset
                let radius = crownRadius * random.float(in: 0.48...0.88)
                let base = tipY * random.float(in: 0.72...0.90)
                let rise = radius * random.float(in: 0.85...1.35)

                addLobe(
                    into: &props.foliage,
                    center: seat,
                    radius: radius,
                    base: base,
                    rise: rise,
                    sides: 6,
                    phase: lobeAngle,
                    contact: foliage,
                    capBottom: true,
                    random: &random
                )
            }
        }

        addContactDecal(
            into: &props,
            at: center,
            radius: crownReach * 0.85 + 0.55 * wide,
            random: &random
        )
    }

    /// Low golden scrub: a small compact mass with a corona of thin folded
    /// blades pushing well past it.
    ///
    /// The mass alone reads as a mound and the blades alone read as a flat
    /// asterisk from a 57° camera — both were tried in the rendered build. What
    /// concept 01 actually shows is *lacy*: enough body to hold a silhouette,
    /// with most of the volume made of open branch tips. So the domes stay low
    /// and the blades reach roughly twice their height.
    private static func addScrubClump(
        into props: inout Props,
        _ instance: Instance,
        random: inout DeterministicRandom
    ) {
        let center = instance.center
        let wide = instance.wide
        let spread = random.float(in: 0.80...1.45) * wide
        let body = random.float(in: 0.34...0.66) * instance.tall
        let crown = body * random.float(in: 2.0...3.1)

        let contact = Contact(foot: -0.06, reach: crown * 0.55, top: instance.top(for: props.foliageSteps))

        let lobes = spread > 1.1 * wide ? 3 : 2
        var seats: [SIMD2<Float>] = []
        for lobe in 0..<lobes {
            let angle = instance.yaw + Float(lobe) / Float(lobes) * 2 * .pi + random.float(in: -0.5...0.5)
            let offset = lobe == 0 ? Float(0) : spread * random.float(in: 0.30...0.62)
            let seat = center + SIMD2<Float>(cos(angle), sin(angle)) * offset
            seats.append(seat)

            addLobe(
                into: &props.foliage,
                center: seat,
                radius: spread * (lobe == 0 ? 0.72 : random.float(in: 0.42...0.62)),
                base: -0.06,
                rise: body * (lobe == 0 ? 1.0 : random.float(in: 0.62...0.88)),
                sides: 6,
                phase: angle,
                contact: contact,
                capBottom: false,
                random: &random
            )
        }

        // The corona. Roots sit on the domes' shoulders, tips arc outward and
        // up, and each blade is folded along a spine so it survives the camera
        // yawing to look along it edge-on.
        let blades = 9 + Int(random.float(in: 0...4.99))
        for index in 0..<blades {
            let angle = instance.yaw + Float(index) / Float(blades) * 2 * .pi + random.float(in: -0.30...0.30)
            let seat = seats[index % seats.count]
            let radius = spread * random.float(in: 0.18...0.52)
            let root = seat + SIMD2<Float>(cos(angle), sin(angle)) * radius

            let base = SIMD3<Float>(root.x, body * random.float(in: 0.30...0.62), root.y)
            let reach = spread * random.float(in: 0.30...0.72)
            let tip = SIMD3<Float>(
                root.x + cos(angle) * reach,
                crown * random.float(in: 0.68...1.05),
                root.y + sin(angle) * reach
            )
            let side = SIMD3<Float>(-sin(angle), 0, cos(angle)) * (0.16 * wide)
            props.foliage.blade(base: base, tip: tip, side: side, lift: body * 0.28, contact)
        }

        addContactDecal(into: &props, at: center, radius: spread * 1.15, random: &random)
    }

    /// A loose tuft of blades and nothing else. The cheapest prop in the game —
    /// twenty triangles — and the one that fills the ground *between* thickets
    /// so the transition from planting to bare soil is graded rather than abrupt.
    private static func addBladeTuft(
        into props: inout Props,
        _ instance: Instance,
        random: inout DeterministicRandom
    ) {
        let center = instance.center
        let height = random.float(in: 0.34...0.78) * instance.tall
        let splay = random.float(in: 0.16...0.40) * instance.wide
        let contact = Contact(foot: -0.04, reach: height * 0.7, top: instance.top(for: props.foliageSteps))

        let blades = 6 + Int(random.float(in: 0...4.99))
        for index in 0..<blades {
            let angle = instance.yaw + Float(index) / Float(blades) * 2 * .pi + random.float(in: -0.4...0.4)
            let root = center + SIMD2<Float>(cos(angle), sin(angle)) * (splay * random.float(in: 0...0.35))
            let base = SIMD3<Float>(root.x, -0.04, root.y)
            let tip = SIMD3<Float>(
                root.x + cos(angle) * splay * random.float(in: 0.5...1.3),
                height * random.float(in: 0.68...1.15),
                root.y + sin(angle) * splay * random.float(in: 0.5...1.3)
            )
            let side = SIMD3<Float>(-sin(angle), 0, cos(angle)) * (0.075 * instance.wide)
            props.foliage.blade(base: base, tip: tip, side: side, lift: height * 0.18, contact)
        }
    }

    /// A rock and its chips. Two silhouettes, chosen per instance: a broad slab
    /// with a flat weathered top, or an angular shard pulled to a point. Both
    /// sink their footprint below the ground plane.
    private static func addRockScatter(
        into props: inout Props,
        _ instance: Instance,
        random: inout DeterministicRandom
    ) {
        let center = instance.center
        let slab = random.unitFloat() < 0.55
        let radius = random.float(in: 0.36...0.86) * instance.wide
        let height = random.float(in: 0.30...0.95) * instance.tall * (slab ? 0.72 : 1.25)
        let contact = Contact(foot: -0.08, reach: max(height * 0.62, 0.12), top: instance.top(for: props.stoneSteps))

        addAngularRock(
            into: &props.stone,
            center: center,
            radius: radius,
            height: height,
            flatTop: slab,
            phase: instance.yaw,
            contact: contact,
            random: &random
        )

        // Chips. A lone boulder reads as a placed object; a boulder with debris
        // around it reads as rock that broke where it lies.
        let chips = Int(random.float(in: 0...2.99))
        for _ in 0..<chips {
            let angle = random.float(in: 0...(2 * .pi))
            let distance = radius * random.float(in: 1.1...2.2)
            let seat = center + SIMD2<Float>(cos(angle), sin(angle)) * distance
            let chipRadius = radius * random.float(in: 0.22...0.46)
            addAngularRock(
                into: &props.stone,
                center: seat,
                radius: chipRadius,
                height: chipRadius * random.float(in: 0.55...1.3),
                flatTop: random.unitFloat() < 0.5,
                phase: angle,
                contact: contact,
                random: &random
            )
        }

        addContactDecal(into: &props, at: center, radius: radius * 1.5, random: &random)
    }

    /// Two or three leaning mineral spikes out of a low rubble seat. Gravemark
    /// ground grows nothing, so its scatter is entirely rock and cold mineral.
    private static func addMineralSpikes(
        into props: inout Props,
        _ instance: Instance,
        random: inout DeterministicRandom
    ) {
        let center = instance.center
        let contact = Contact(foot: -0.06, reach: 0.55, top: instance.top(for: props.mineralSteps))

        let spikes = 2 + Int(random.float(in: 0...1.99))
        var tallest: Float = 0
        for index in 0..<spikes {
            let angle = instance.yaw + Float(index) / Float(spikes) * 2 * .pi + random.float(in: -0.5...0.5)
            let offset = random.float(in: 0...0.42) * instance.wide
            let seat = center + SIMD2<Float>(cos(angle), sin(angle)) * offset
            let base = StructureGeometry.ring(
                sides: 4,
                radius: random.float(in: 0.16...0.30) * instance.wide,
                y: -0.06,
                phase: angle,
                center: seat
            )
            let lean = random.float(in: 0.10...0.36)
            let top = random.float(in: 0.75...1.85) * instance.tall * (index == 0 ? 1 : random.float(in: 0.45...0.85))
            tallest = max(tallest, top)
            let apex = SIMD3<Float>(
                seat.x + cos(angle) * lean,
                top,
                seat.y + sin(angle) * lean
            )
            props.mineral.fan(ring: base, apex: apex, pivot: [seat.x, top * 0.5, seat.y], contact)
        }

        addContactDecal(into: &props, at: center, radius: 0.55 * instance.wide + tallest * 0.18, random: &random)
    }

    // MARK: - Prop primitives

    /// One irregular faceted lobe: a jittered footprint, a smaller shoulder ring
    /// shoved off-axis, and one apex. Every foliage crown and dome in the file
    /// is built from this, and no two draws are alike.
    private static func addLobe(
        into ladder: inout Ladder,
        center: SIMD2<Float>,
        radius: Float,
        base: Float,
        rise: Float,
        sides: Int,
        phase: Float,
        contact: Contact,
        capBottom: Bool,
        random: inout DeterministicRandom
    ) {
        let footRadii = (0..<sides).map { _ in radius * random.float(in: 0.74...1.14) }
        let shoulderRadii = (0..<sides).map { _ in radius * random.float(in: 0.36...0.66) }
        let lean = SIMD2<Float>(
            random.float(in: -0.24...0.24) * radius,
            random.float(in: -0.24...0.24) * radius
        )

        let foot = StructureGeometry.ring(radii: footRadii, y: base, phase: phase, center: center)
        let shoulder = StructureGeometry.ring(
            radii: shoulderRadii,
            y: base + rise * random.float(in: 0.50...0.68),
            phase: phase,
            center: center + lean
        )
        let apex = SIMD3<Float>(
            center.x + lean.x * 1.6,
            base + rise,
            center.y + lean.y * 1.6
        )

        let pivot = SIMD3<Float>(center.x, base + rise * 0.35, center.y)
        ladder.band(lower: foot, upper: shoulder, pivot: pivot, contact)
        ladder.fan(ring: shoulder, apex: apex, pivot: pivot, contact)
        // A crown carried on a trunk is the one lobe whose underside is open to
        // the camera when it yaws low, so it closes; a dome sitting on the
        // ground never shows its own floor.
        if capBottom { ladder.cap(ring: foot, pivot: pivot, contact) }
    }

    /// An angular rock: a sunk irregular footprint rising to either a flat
    /// weathered cap or a single point.
    private static func addAngularRock(
        into ladder: inout Ladder,
        center: SIMD2<Float>,
        radius: Float,
        height: Float,
        flatTop: Bool,
        phase: Float,
        contact: Contact,
        random: inout DeterministicRandom
    ) {
        let sides = 6
        let footRadii = (0..<sides).map { _ in radius * random.float(in: 0.70...1.18) }
        let capRadii = (0..<sides).map { _ in radius * random.float(in: 0.30...0.62) }
        let lean = SIMD2<Float>(
            random.float(in: -0.30...0.30) * radius,
            random.float(in: -0.30...0.30) * radius
        )

        let foot = StructureGeometry.ring(radii: footRadii, y: -0.08, phase: phase, center: center)
        let capY = flatTop ? height : height * random.float(in: 0.55...0.72)
        let cap = StructureGeometry.ring(radii: capRadii, y: capY, phase: phase, center: center + lean)
        let pivot = SIMD3<Float>(center.x, height * 0.35, center.y)

        ladder.band(lower: foot, upper: cap, pivot: pivot, contact)
        if flatTop {
            ladder.cap(ring: cap, pivot: pivot, contact)
        } else {
            let apex = SIMD3<Float>(center.x + lean.x * 1.7, height, center.y + lean.y * 1.7)
            ladder.fan(ring: cap, apex: apex, pivot: pivot, contact)
        }
    }

    /// The dust a prop has kicked up around its own base.
    ///
    /// Real shadows do most of the contact work now, but a shadow map that
    /// covers the whole world gives a 1 m shrub about ten texels — not enough to
    /// seat it. Two concentric rings of darkened soil, the inner one stronger,
    /// grade the ground into the prop instead of letting it meet the terrain on
    /// a hard silhouette line.
    private static func addContactDecal(
        into props: inout Props,
        at center: SIMD2<Float>,
        radius: Float,
        random: inout DeterministicRandom
    ) {
        guard radius > 0.20 else { return }
        let sides = 7
        let phase = random.float(in: 0...(2 * .pi))
        let up = SIMD3<Float>(0, 1, 0)

        let innerRadii = (0..<sides).map { _ in radius * random.float(in: 0.86...1.20) }
        let outerRadii = (0..<sides).map { _ in radius * random.float(in: 1.45...2.05) }
        let inner = StructureGeometry.ring(radii: innerRadii, y: Height.dust, phase: phase, center: center)
        let outer = StructureGeometry.ring(
            radii: outerRadii, y: Height.dust - 0.0012, phase: phase, center: center
        )
        let hub = SIMD3<Float>(center.x, Height.dust, center.y)

        for index in 0..<sides {
            let next = (index + 1) % sides
            props.dust.triangle(hub, inner[index], inner[next], facing: up, step: 0)
            props.dust.quad(inner[index], outer[index], outer[next], inner[next], facing: up, step: 1)
        }
    }

    // MARK: - Value ladders

    /// How a prop's geometry walks down its class's value ladder as it
    /// approaches the ground.
    ///
    /// RealityKit's `MeshDescriptor` carries no colour semantic and
    /// `PhysicallyBasedMaterial` reads no vertex colour, so a per-vertex AO
    /// gradient is simply not expressible on this renderer. The equivalent that
    /// *is* expressible — and is how hand-painted RTS props have always been
    /// authored — is a small ladder of tinted materials: a triangle's height
    /// above the prop's foot picks which rung it is emitted into, and the lower
    /// rungs are both darker and mixed toward the soil colour.
    ///
    /// The same ladder carries the per-instance jitter: `top` is drawn per prop,
    /// so two neighbouring shrubs sit at different rungs and read as different
    /// plants, while each individually still darkens by `drop` rungs into its
    /// own contact shadow.
    private struct Contact {
        /// How many rungs darker a prop's contact geometry is than its lit top.
        static let drop = 2

        let foot: Float
        let reach: Float
        let top: Int

        func step(_ y: Float) -> Int {
            guard reach > 1e-4 else { return top }
            let t = min(max((y - foot) / reach, 0), 1)
            let eased = t * t * (3 - 2 * t)
            let level = Float(top) - Float(Contact.drop) * (1 - eased)
            return max(Int(level.rounded()), 0)
        }
    }

    /// A stack of builders, one per rung of a value ladder. Geometry is routed
    /// into a rung by height, and each rung becomes one draw.
    private struct Ladder {
        private(set) var steps: [StructureBuilder]

        init(_ count: Int, uv: MeshUVProjection) {
            steps = (0..<max(count, 1)).map { _ in StructureBuilder(uv: uv) }
        }

        var count: Int { steps.count }

        /// See `FlatMeshBuilder.lift`. Applied to every rung, since one prop's
        /// geometry is spread across several of them and all of it has to move
        /// together.
        var lift: ((SIMD2<Float>) -> Float)? {
            get { steps.first?.lift }
            set { for index in steps.indices { steps[index].lift = newValue } }
        }

        /// Clamps into the ladder, so a `Contact` can be written without
        /// knowing how many rungs its class happens to have.
        private func clamp(_ step: Int) -> Int { min(max(step, 0), steps.count - 1) }

        // Explicit-rung primitives. Only the ground decals use these; props go
        // through the `Contact` overloads so their shading follows their height.

        mutating func triangle(
            _ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>,
            facing reference: SIMD3<Float>, step: Int
        ) {
            steps[clamp(step)].addTriangle(a, b, c, facing: reference)
        }

        mutating func quad(
            _ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ d: SIMD3<Float>,
            facing reference: SIMD3<Float>, step: Int
        ) {
            steps[clamp(step)].addQuad(a, b, c, d, facing: reference)
        }

        // Contact-shaded primitives.

        mutating func triangle(
            _ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>,
            facing reference: SIMD3<Float>, _ contact: Contact
        ) {
            triangle(a, b, c, facing: reference, step: contact.step((a.y + b.y + c.y) / 3))
        }

        /// One rung for the whole quad, taken from its centroid: splitting a quad
        /// across two rungs would put a value break on its diagonal, which reads
        /// as a triangulation artefact rather than as shading.
        mutating func quad(
            _ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ d: SIMD3<Float>,
            facing reference: SIMD3<Float>, _ contact: Contact
        ) {
            quad(a, b, c, d, facing: reference, step: contact.step((a.y + b.y + c.y + d.y) * 0.25))
        }

        mutating func band(
            lower: [SIMD3<Float>], upper: [SIMD3<Float>], pivot: SIMD3<Float>, _ contact: Contact
        ) {
            guard lower.count == upper.count, lower.count >= 3 else { return }
            for index in lower.indices {
                let next = (index + 1) % lower.count
                let a = lower[index], b = lower[next], c = upper[next], d = upper[index]
                quad(a, b, c, d, facing: (a + b + c + d) * 0.25 - pivot, contact)
            }
        }

        mutating func fan(ring: [SIMD3<Float>], apex: SIMD3<Float>, pivot: SIMD3<Float>, _ contact: Contact) {
            guard ring.count >= 3 else { return }
            for index in ring.indices {
                let next = (index + 1) % ring.count
                let centroid = (ring[index] + ring[next] + apex) / 3
                triangle(ring[index], ring[next], apex, facing: centroid - pivot, contact)
            }
        }

        mutating func cap(ring: [SIMD3<Float>], pivot: SIMD3<Float>, _ contact: Contact) {
            fan(ring: ring, apex: StructureGeometry.centroid(ring), pivot: pivot, contact)
        }

        /// A folded blade: two triangles meeting along a raised spine, so a frond
        /// still reads when the camera yaws to look along it edge-on.
        mutating func blade(
            base: SIMD3<Float>, tip: SIMD3<Float>, side: SIMD3<Float>, lift: Float, _ contact: Contact
        ) {
            let ridge = base + [0, lift, 0]
            triangle(base - side, ridge, tip, facing: -side + [0, 0.5, 0], contact)
            triangle(base + side, ridge, tip, facing: side + [0, 0.5, 0], contact)
        }
    }

    /// Every prop ladder on a fragment, plus the ground dust they stand on.
    ///
    /// Four classes, four ladders, four genuinely different surface classes —
    /// this is what answers "nothing distinguishes stone from wood from
    /// foliage". Bark is `.wovenIvory` (fine weave, low roughness), foliage is
    /// `.growth`, rock is `.rimStone` (coarse fractured stone), mineral is
    /// `.rawMatter` (faceted, part-metallic).
    private struct Props {
        var foliage: Ladder
        var bark: Ladder
        var stone: Ladder
        var mineral: Ladder
        var dust: Ladder

        /// Five foliage rungs and four stone rungs give three distinct
        /// per-instance levels above a two-rung contact drop. Bark and mineral
        /// carry less area on screen and get the minimum that still reads.
        init(uv: MeshUVProjection, groundUV: MeshUVProjection) {
            foliage = Ladder(5, uv: uv)
            bark = Ladder(3, uv: uv)
            stone = Ladder(4, uv: uv)
            mineral = Ladder(3, uv: uv)
            dust = Ladder(2, uv: groundUV)
        }

        /// See `FlatMeshBuilder.lift`. Set once per scattered instance to the
        /// ground height under that instance, so each prop translates onto the
        /// terrain as a rigid body while the next one lands at its own height.
        var lift: ((SIMD2<Float>) -> Float)? {
            get { foliage.lift }
            set {
                foliage.lift = newValue
                bark.lift = newValue
                stone.lift = newValue
                mineral.lift = newValue
                dust.lift = newValue
            }
        }

        var foliageSteps: Int { foliage.count }
        var barkSteps: Int { bark.count }
        var stoneSteps: Int { stone.count }
        var mineralSteps: Int { mineral.count }

        func ladderCount(for kind: PropClass) -> Int {
            switch kind {
            case .paleTree, .branchingMass, .scrubClump, .bladeTuft: foliage.count
            case .rockScatter: stone.count
            case .mineralSpikes: mineral.count
            }
        }

        @MainActor
        func zones(character: Character, colors: (surface: UIColor, rock: UIColor)) -> [StructureZone] {
            // The soil tone every ladder's bottom rung is mixed toward. Blending
            // the contact geometry toward the ground it stands on is what removes
            // the hard intersection line; darkening alone leaves a crisp dark
            // silhouette, which is the same defect one value down.
            let soil = StructureMaterial.shade(colors.surface, 0.52)

            var zones: [StructureZone] = []

            zones.append(
                contentsOf: rungs(
                    foliage,
                    named: "growth",
                    surface: .growth,
                    tints: TerrainDressing.ladderTints(
                        body: TerrainDressing.growthColor(character: character),
                        soil: soil,
                        count: foliage.count,
                        floorMix: 0.46,
                        floorValue: 0.62,
                        topValue: 1.06
                    ),
                    roughness: 0.99
                )
            )
            zones.append(
                contentsOf: rungs(
                    bark,
                    named: "bark",
                    surface: .wovenIvory,
                    tints: TerrainDressing.ladderTints(
                        body: TerrainDressing.barkColor(character: character),
                        soil: soil,
                        count: bark.count,
                        floorMix: 0.42,
                        floorValue: 0.66,
                        topValue: 1.04
                    ),
                    roughness: 0.90
                )
            )
            zones.append(
                contentsOf: rungs(
                    stone,
                    named: "stone",
                    surface: .rimStone,
                    tints: TerrainDressing.ladderTints(
                        body: StructureMaterial.shade(colors.rock, 1.12),
                        soil: soil,
                        count: stone.count,
                        floorMix: 0.38,
                        floorValue: 0.64,
                        topValue: 1.08
                    ),
                    roughness: 0.98
                )
            )
            zones.append(
                contentsOf: rungs(
                    mineral,
                    named: "mineral",
                    surface: .rawMatter,
                    tints: TerrainDressing.ladderTints(
                        body: StructureMaterial.blend(
                            SunfoldPalette.neutralRock,
                            SunfoldPalette.landRock,
                            0.40
                        ),
                        soil: soil,
                        count: mineral.count,
                        floorMix: 0.40,
                        floorValue: 0.66,
                        topValue: 1.02
                    ),
                    roughness: 0.62
                )
            )
            zones.append(
                contentsOf: rungs(
                    dust,
                    named: "dust",
                    surface: .regolithGround,
                    tints: [
                        StructureMaterial.shade(colors.surface, 0.74),
                        StructureMaterial.shade(colors.surface, 0.88),
                    ],
                    roughness: 0.96
                )
            )

            return zones
        }

        @MainActor
        private func rungs(
            _ ladder: Ladder,
            named name: String,
            surface: MaterialLibrary.Surface,
            tints: [UIColor],
            roughness: Float
        ) -> [StructureZone] {
            ladder.steps.indices.compactMap { index in
                guard ladder.steps[index].triangleCount > 0 else { return nil }
                let tint = tints[min(index, tints.count - 1)]
                return StructureZone(
                    "\(name).\(index)",
                    ladder.steps[index],
                    StructureMaterial.matte(tint, roughness: roughness, surface: surface)
                )
            }
        }
    }

    /// A class's value ladder: `count` tints running from a soil-mixed contact
    /// tone at rung 0 up to the lit body colour at the top.
    ///
    /// Nothing here invents a hue. `body` is already a blend of locked palette
    /// colours and `soil` is the fragment's own surface colour darkened, so every
    /// rung sits on a line between two colours the identity already owns.
    private static func ladderTints(
        body: UIColor,
        soil: UIColor,
        count: Int,
        floorMix: CGFloat,
        floorValue: CGFloat,
        topValue: CGFloat
    ) -> [UIColor] {
        (0..<max(count, 1)).map { index in
            let t = count > 1 ? CGFloat(index) / CGFloat(count - 1) : 1
            let value = floorValue + (topValue - floorValue) * t
            return shade(blend(body, soil, floorMix * (1 - t)), value)
        }
    }

    // MARK: - Identity

    /// Dressing style for land. One shared planted look — never faction-keyed
    /// (user constraint 2026-07-28). The enum remains so call sites stay typed.
    private enum Character {
        case planted
    }

    /// A stable per-region offset, so two fragments of the same size never get
    /// the identical lattice. Derived from case order rather than `hashValue`,
    /// which is randomised per process and would break replay.
    private static func salt(_ region: RegionID) -> UInt64 {
        UInt64(RegionID.allCases.firstIndex(of: region) ?? 0) &* 0x9E37_79B9_7F4A_7C15
    }

    private static func character(of region: RegionID) -> Character {
        _ = region
        return .planted
    }

    private static func seamMaterial(character: Character, surface: UIColor) -> any RealityKit.Material {
        _ = character
        _ = surface
        // Quiet gold weave on every fragment — concept 01's ground language,
        // shared rather than faction-painted.
        return StructureMaterial.glow(SunfoldPalette.sunwovenGold, opacity: 0.34)
    }

    /// Foliage is straw, not metal. Full-strength `sunwovenGold` came back from
    /// the simulator reading as saturated orange against the cream surface and
    /// competing with the Core's own gold ribbing, which must stay the brightest
    /// warm note on the fragment.
    private static func growthColor(character: Character) -> UIColor {
        _ = character
        return blend(SunfoldPalette.sunwovenGold, SunfoldPalette.sunwovenIvory, 0.38)
    }

    /// Concept 01's trees are *pale* — near-bone trunks that read lighter than
    /// the soil, which is what separates them from the amber foliage they carry
    /// and from the grey rock beside them. Value separation, not hue.
    private static func barkColor(character: Character) -> UIColor {
        _ = character
        return blend(SunfoldPalette.sunwovenIvory, SunfoldPalette.landSurface, 0.26)
    }

    private static func blend(_ from: UIColor, _ to: UIColor, _ amount: CGFloat) -> UIColor {
        StructureMaterial.blend(from, to, amount)
    }

    private static func shade(_ color: UIColor, _ factor: CGFloat) -> UIColor {
        StructureMaterial.shade(color, factor)
    }

    // MARK: - Layering

    /// Ground decoration stacks in a fixed order with visible gaps, so nothing
    /// ever z-fights: surface, tone, shore, dust, seams, then selection feedback
    /// and the order marker, both owned by `EntityPresenter`.
    ///
    /// The whole stack sits on `FragmentMeshFactory.chordError`, and that is the
    /// load-bearing part. These were 0.008…0.022 while the terrain was flat, when
    /// clearing the surface meant clearing zero. On real relief the mesh's flat
    /// triangles ride *above* the height field across every dip, by up to
    /// `chordError` — so a decal that drapes on the continuous function at 0.022
    /// spends most of its length buried. That is what happened on the first CP-04
    /// render: the gold seam network came back thin and broken.
    ///
    /// `dust` is the exception, and takes a third of the clearance. Contact rings
    /// are emitted inside a prop's own dispatch, so they ride that prop's rigid
    /// lift and are measured from a footing that is exact *at that point* — the
    /// chord error is zero where the prop stands and only grows across the metre
    /// or so the ring spans. Giving them the full clearance would float a collar
    /// of dust around every trunk; giving them none, as the first CP-04 render
    /// did, buries half of each ring and the props lose their contact shadow.
    private enum Height {
        static let tone = FragmentMeshFactory.chordError + 0.005
        static let shore = FragmentMeshFactory.chordError + 0.013
        static let seam = FragmentMeshFactory.chordError + 0.025
        /// Plaza inlay sits between tone and seams so it reads as set into the
        /// pan without fighting the gold lattice above it.
        static let rosette = FragmentMeshFactory.chordError + 0.019
        static let dust = FragmentMeshFactory.chordError / 3 + 0.008
    }

    private static func point(_ angle: Float, _ radius: Float, y: Float) -> SIMD3<Float> {
        [cos(angle) * radius, y, sin(angle) * radius]
    }
}

extension TerrainDressing.Instance {
    /// This instance's lit rung, clamped into a ladder of `count` rungs while
    /// leaving room underneath for the contact drop.
    fileprivate func top(for count: Int) -> Int {
        min(max(top, min(TerrainDressing.Contact.drop, count - 1)), count - 1)
    }
}

/// The fragment's real, jittered rim, sampled by angle.
///
/// `FragmentMeshFactory` lays its rim vertices at `angle = i / sides * 2π` with
/// `x = cos(angle) · r` and `z = sin(angle) · r`, so the angle of a local point
/// is `atan2(z, x)` and this profile reads directly against the built mesh.
struct RimProfile {
    let radii: [Float]
    let fallback: Float
    /// Where the map's water is, in the same fragment-local space as `radii`.
    ///
    /// Carried here rather than checked at each of the five call sites because
    /// every one of them already asks this type "is this point on land?". A
    /// rivermouth is a place a prop must not stand for exactly the same reason
    /// the open void is, and a scatter that knows about one and not the other
    /// grows a thicket in midstream.
    var isSubmerged: (SIMD2<Float>) -> Bool = { _ in false }

    init(
        radii: [Float],
        fallback: Float,
        isSubmerged: @escaping (SIMD2<Float>) -> Bool = { _ in false }
    ) {
        self.radii = radii
        self.fallback = fallback
        self.isSubmerged = isSubmerged
    }

    func radius(atAngle angle: Float) -> Float {
        guard radii.count >= 2 else { return fallback }
        let count = Float(radii.count)
        var position = angle / (2 * .pi) * count
        position = position.truncatingRemainder(dividingBy: count)
        if position < 0 { position += count }

        let index = Int(position)
        let blend = position - Float(index)
        let a = radii[index % radii.count]
        let b = radii[(index + 1) % radii.count]
        return a + (b - a) * blend
    }

    /// Whether a local point is on land, pulled in by `margin`.
    func contains(_ point: SIMD2<Float>, margin: Float) -> Bool {
        guard !isSubmerged(point) else { return false }
        let distance = simd_length(point)
        guard distance > 1e-4 else { return true }
        return distance < radius(atAngle: atan2(point.y, point.x)) * margin
    }
}
