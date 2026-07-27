import Foundation
import RealityKit
import UIKit
import simd

/// Dresses the habitable surface of a fragment.
///
/// Concept 01's home island is not a blank plate: it carries tonal variation in
/// the soil, a darker band where the ground turns down into the rim, sun-woven
/// gold lattice seams running across the terrain, and scattered growth and rock.
/// Without those, a fragment reads as an untextured placeholder no matter how
/// good the structures standing on it are.
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

    // MARK: - Claimed ground

    /// The circles the simulation's own entities occupy at match start, plus the
    /// dock and staging points a player will walk through.
    ///
    /// Read once, at scene build. Dressing is static: a Farm built later simply
    /// stands on the grass, which is the correct read anyway.
    static func keepClear(for simulation: SkirmishSimulation) -> [KeepClear] {
        var circles: [KeepClear] = []

        for building in simulation.buildings.values {
            circles.append(
                KeepClear(center: building.position, radius: building.kind.footprintRadius + 2.2)
            )
        }
        for unit in simulation.units.values {
            circles.append(
                KeepClear(center: unit.position, radius: unit.kind.footprintRadius + 1.6)
            )
        }
        for deposit in simulation.deposits.values {
            // Wide enough that a citizen can stand anywhere in the work radius
            // without a rock through their shins.
            circles.append(
                KeepClear(center: deposit.position, radius: Deposit.workRadius + 1.4)
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
        rimRadii: [Float],
        seed: UInt64,
        keepClear: [KeepClear]
    ) -> Entity {
        var random = DeterministicRandom.stream(seed: seed, tag: "dressing.\(fragment.id.rawValue)")

        let character = character(of: fragment.id)
        let colors = SunfoldPalette.fragmentColors(for: fragment.id)
        let rim = RimProfile(radii: rimRadii, fallback: fragment.radius)

        // Local-space keep-clear, so the scatter never has to think in world space.
        let claimed: [KeepClear] = keepClear.map {
            KeepClear(center: $0.center - fragment.center, radius: $0.radius)
        }

        var shore = StructureBuilder()
        var toneWarm = StructureBuilder()
        var toneCool = StructureBuilder()
        var seams = StructureBuilder()
        var growth = StructureBuilder()
        var stone = StructureBuilder()
        var mineral = StructureBuilder()

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
        addScatter(
            growth: &growth,
            stone: &stone,
            mineral: &mineral,
            fragment: fragment,
            rim: rim,
            character: character,
            claimed: claimed,
            random: &random
        )

        let zones: [StructureZone] = [
            StructureZone("shore", shore, StructureMaterial.matte(shade(colors.surface, 0.88))),
            StructureZone("tone.warm", toneWarm, StructureMaterial.matte(shade(colors.surface, 1.028))),
            StructureZone("tone.cool", toneCool, StructureMaterial.matte(shade(colors.surface, 0.962))),
            StructureZone("seam", seams, seamMaterial(character: character, surface: colors.surface)),
            StructureZone("growth", growth, StructureMaterial.matte(growthColor(character: character))),
            StructureZone("stone", stone, StructureMaterial.matte(shade(colors.rock, 1.10))),
            StructureZone("mineral", mineral, StructureMaterial.matte(SunfoldPalette.gravemarkMineral, roughness: 0.62)),
        ]

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
        case .sunwoven:
            addLattice(into: &builder, fragment: fragment, rim: rim, seed: seed)
        case .gravemark:
            addFractures(into: &builder, fragment: fragment, rim: rim, count: 6, random: &random)
        case .neutral:
            addFractures(into: &builder, fragment: fragment, rim: rim, count: 4, random: &random)
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

    /// Growth and rock, placed by rejection sampling: inside the real rim, off
    /// every claimed circle, and never crowding another prop.
    ///
    /// Two passes. A fringe follows the rim, because concept 01's growth thickens
    /// into a band around the edge of the island and that band is most of what
    /// gives the fragment a silhouette from above. A second, sparser pass fills
    /// the interior, which is where structures will later stand.
    private static func addScatter(
        growth: inout StructureBuilder,
        stone: inout StructureBuilder,
        mineral: inout StructureBuilder,
        fragment: Fragment,
        rim: RimProfile,
        character: Character,
        claimed: [KeepClear],
        random: inout DeterministicRandom
    ) {
        var placed: [SIMD2<Float>] = []

        /// Accepts a candidate only if it is on land, off every claimed circle,
        /// and not crowding an already-placed prop.
        func take(_ candidate: SIMD2<Float>, spacing: Float) -> Bool {
            guard rim.contains(candidate, margin: 0.93) else { return false }
            guard claimed.allSatisfy({ simd_distance($0.center, candidate) > $0.radius }) else {
                return false
            }
            guard placed.allSatisfy({ simd_distance($0, candidate) > spacing }) else { return false }
            placed.append(candidate)
            return true
        }

        func dress(_ candidate: SIMD2<Float>, foliageChance: Float, scale: Float) {
            let roll = random.unitFloat()
            switch character {
            case .sunwoven, .neutral:
                if roll < foliageChance {
                    // A minority of the growth stands tall. Concept 01's island
                    // reads as a *place* partly because its planting has three
                    // heights — trees, shrubs, low scrub — and a fringe of one
                    // repeated mound reads as a scatter pass instead.
                    let tall: Float = character == .sunwoven ? 0.16 : 0.07
                    if random.unitFloat() < tall {
                        addTree(into: &growth, at: candidate, scale: scale, random: &random)
                    } else {
                        addShrub(into: &growth, at: candidate, scale: scale, random: &random)
                    }
                } else {
                    addRock(into: &stone, at: candidate, random: &random)
                }
            case .gravemark:
                // Gravemark ground grows nothing. Its fringe is rubble and cold
                // mineral, which is the identity contrast doing the work.
                if roll < 0.26 {
                    addShard(into: &mineral, at: candidate, random: &random)
                } else {
                    addRock(into: &stone, at: candidate, random: &random)
                }
            }
        }

        // Fringe: walk the rim at a fixed arc spacing so density is independent
        // of how large the fragment is.
        let fringeSpacing: Float = 4.2
        let fringeCount = max(6, Int(2 * .pi * fragment.radius / fringeSpacing))
        let foliageChance: Float = character == .neutral ? 0.44 : 0.80

        for index in 0..<fringeCount {
            let angle = Float(index) / Float(fringeCount) * 2 * .pi + random.float(in: -0.05...0.05)
            let localRim = rim.radius(atAngle: angle)
            let distance = localRim * random.float(in: 0.80...0.915)
            let candidate = SIMD2<Float>(cos(angle) * distance, sin(angle) * distance)
            guard take(candidate, spacing: 2.5) else { continue }
            dress(candidate, foliageChance: foliageChance, scale: random.float(in: 0.58...1.35))
        }

        // Interior: area-uniform, sparser, and biased toward rock so the middle
        // of the island stays walkable-looking and readable under structures.
        let interior = max(4, Int(fragment.radius * fragment.radius * 0.045))
        var attempts = 0
        var taken = 0
        while taken < interior && attempts < interior * 22 {
            attempts += 1
            let angle = random.float(in: 0...(2 * .pi))
            let localRim = rim.radius(atAngle: angle)
            let distance = sqrt(random.unitFloat()) * localRim * 0.80
            let candidate = SIMD2<Float>(cos(angle) * distance, sin(angle) * distance)
            guard take(candidate, spacing: 3.6) else { continue }
            taken += 1
            dress(
                candidate,
                foliageChance: foliageChance * 0.62,
                scale: random.float(in: 0.52...1.15)
            )
        }
    }

    /// A shrub at the ~2–3 m scale concept 01 shows.
    ///
    /// A clump of splayed blades alone was tried first and failed in the rendered
    /// build: from a 57° camera a low fan of thin blades reads as a flat yellow
    /// asterisk, not as foliage. What makes stylised growth read from above is
    /// *mass* — so the clump is a faceted crown volume with blades breaking its
    /// silhouette, rather than blades alone. The blades stay folded along a spine
    /// so they survive the camera yawing to look along them edge-on.
    private static func addShrub(
        into builder: inout StructureBuilder,
        at center: SIMD2<Float>,
        scale: Float,
        random: inout DeterministicRandom
    ) {
        // Wider than it is tall. A crown taller than its own radius came back
        // from the simulator reading as a spiked ball, because the blades then
        // radiate off a cone instead of breaking a dome.
        let spread = random.float(in: 1.05...1.85) * scale
        let crown = random.float(in: 0.78...1.28) * scale

        // Two overlapping lobes on the larger shrubs, so a fringe of them never
        // reads as a row of identical mounds.
        let lobes = spread > 1.4 * scale ? 2 : 1
        for lobe in 0..<lobes {
            let offsetAngle = random.float(in: 0...(2 * .pi))
            let offset = lobe == 0
                ? SIMD2<Float>.zero
                : SIMD2<Float>(cos(offsetAngle), sin(offsetAngle)) * spread * 0.42
            builder.addBoulder(
                center: center + offset,
                radius: spread * (lobe == 0 ? 1.0 : 0.72),
                height: crown * (lobe == 0 ? 1.0 : 0.74),
                sides: 7,
                random: &random
            )
        }

        // Short, broad fronds hugging the crown's shoulder. Long thin ones read
        // as spines; these only need to keep the dome from ending on a clean arc.
        let fronds = 8 + Int(random.float(in: 0...4.99))
        for index in 0..<fronds {
            let angle = Float(index) / Float(fronds) * 2 * .pi + random.float(in: -0.26...0.26)
            let radius = spread * random.float(in: 0.42...0.78)
            let root = center + SIMD2<Float>(cos(angle), sin(angle)) * radius

            let base = SIMD3<Float>(root.x, crown * random.float(in: 0.42...0.66), root.y)
            let reach = spread * random.float(in: 0.14...0.32)
            let tip = SIMD3<Float>(
                root.x + cos(angle) * reach,
                crown * random.float(in: 1.00...1.24),
                root.y + sin(angle) * reach
            )
            let side = SIMD3<Float>(-sin(angle), 0, cos(angle)) * (0.30 * scale)
            builder.addBlade(base: base, tip: tip, side: side, lift: crown * 0.06)
        }
    }

    /// A slender bare trunk carrying a small offset crown — the tallest thing on
    /// the ground and the one that gives the fringe a skyline.
    private static func addTree(
        into builder: inout StructureBuilder,
        at center: SIMD2<Float>,
        scale: Float,
        random: inout DeterministicRandom
    ) {
        let height = random.float(in: 2.9...4.4) * scale
        let lean = random.float(in: 0...(2 * .pi))
        let sway = random.float(in: 0.10...0.42) * scale
        let head = center + SIMD2<Float>(cos(lean), sin(lean)) * sway

        let foot = StructureGeometry.ring(sides: 4, radius: 0.26 * scale, y: 0, center: center)
        let neck = StructureGeometry.ring(
            sides: 4,
            radius: 0.13 * scale,
            y: height * 0.72,
            center: head
        )
        builder.addSolid(lower: foot, upper: neck, capTop: false)

        // The crown is built at height directly. `addBoulder` always grows from
        // y = 0, so reusing it here would leave the foliage on the ground.
        let crown = random.float(in: 0.90...1.45) * scale
        let sides = 7
        let skirtRadii = (0..<sides).map { _ in crown * random.float(in: 0.80...1.16) }
        let shoulderRadii = (0..<sides).map { _ in crown * random.float(in: 0.44...0.70) }
        let phase = random.float(in: 0...(2 * .pi))

        let skirt = StructureGeometry.ring(
            radii: skirtRadii,
            y: height * 0.60,
            phase: phase,
            center: head
        )
        let shoulder = StructureGeometry.ring(
            radii: shoulderRadii,
            y: height * 0.88,
            phase: phase,
            center: head
        )
        let apex = SIMD3<Float>(
            head.x + random.float(in: -0.16...0.16) * scale,
            height,
            head.y + random.float(in: -0.16...0.16) * scale
        )
        let pivot = SIMD3<Float>(head.x, height * 0.74, head.y)

        builder.addCap(ring: skirt, pivot: pivot)   // Seen from a 57° camera only
        builder.addBand(lower: skirt, upper: shoulder, pivot: pivot)
        builder.addFan(ring: shoulder, apex: apex, pivot: pivot)
    }

    private static func addRock(
        into builder: inout StructureBuilder,
        at center: SIMD2<Float>,
        random: inout DeterministicRandom
    ) {
        builder.addBoulder(
            center: center,
            radius: random.float(in: 0.34...0.92),
            height: random.float(in: 0.36...1.15),
            sides: 5,
            random: &random
        )
    }

    /// A single leaning mineral spike. Gravemark ground grows nothing, so its
    /// scatter is entirely rock and cold mineral.
    private static func addShard(
        into builder: inout StructureBuilder,
        at center: SIMD2<Float>,
        random: inout DeterministicRandom
    ) {
        let base = StructureGeometry.ring(
            sides: 4,
            radius: random.float(in: 0.20...0.34),
            y: 0,
            phase: random.float(in: 0...(2 * .pi)),
            center: center
        )
        let leanAngle = random.float(in: 0...(2 * .pi))
        let lean = random.float(in: 0.10...0.34)
        let apex = SIMD3<Float>(
            center.x + cos(leanAngle) * lean,
            random.float(in: 0.95...1.95),
            center.y + sin(leanAngle) * lean
        )
        builder.addSpire(base: base, apex: apex)
    }

    // MARK: - Identity

    private enum Character {
        case sunwoven, gravemark, neutral
    }

    /// A stable per-region offset, so two fragments of the same size never get
    /// the identical lattice. Derived from case order rather than `hashValue`,
    /// which is randomised per process and would break replay.
    private static func salt(_ region: RegionID) -> UInt64 {
        UInt64(RegionID.allCases.firstIndex(of: region) ?? 0) &* 0x9E37_79B9_7F4A_7C15
    }

    private static func character(of region: RegionID) -> Character {
        switch region {
        case .sunwovenHome, .sunwovenExpansion: .sunwoven
        case .gravemarkHome, .gravemarkExpansion: .gravemark
        case .dominion, .neutralOutcropNorth, .neutralOutcropSouth: .neutral
        }
    }

    private static func seamMaterial(character: Character, surface: UIColor) -> any RealityKit.Material {
        switch character {
        case .sunwoven:
            // Woven light, not paint: this is the one place ground is allowed to
            // emit, and it is the Sunwoven identity mark.
            StructureMaterial.glow(SunfoldPalette.sunwovenGold, opacity: 0.34)
        case .gravemark:
            StructureMaterial.glow(SunfoldPalette.gravemarkMineral, opacity: 0.30)
        case .neutral:
            // Stone cracks are not lit. A matte darker tone keeps neutral ground
            // legibly *unclaimed* by either side.
            StructureMaterial.matte(shade(surface, 0.76))
        }
    }

    /// Foliage is straw, not metal. Full-strength `sunwovenGold` came back from
    /// the simulator reading as saturated orange against the cream surface and
    /// competing with the Core's own gold ribbing, which must stay the brightest
    /// warm note on the fragment.
    private static func growthColor(character: Character) -> UIColor {
        switch character {
        case .sunwoven: blend(SunfoldPalette.sunwovenGold, SunfoldPalette.sunwovenIvory, 0.38)
        case .gravemark: shade(SunfoldPalette.gravemarkSurface, 1.12)
        case .neutral: blend(SunfoldPalette.neutralSurface, SunfoldPalette.sunwovenGold, 0.22)
        }
    }

    private static func blend(_ from: UIColor, _ to: UIColor, _ amount: CGFloat) -> UIColor {
        StructureMaterial.blend(from, to, amount)
    }

    private static func shade(_ color: UIColor, _ factor: CGFloat) -> UIColor {
        StructureMaterial.shade(color, factor)
    }

    // MARK: - Layering

    /// Ground decoration stacks in a fixed order with visible gaps, so nothing
    /// ever z-fights: surface, tone, shore, seams, then selection feedback at
    /// 0.03 and the order marker at 0.04, both owned by `EntityPresenter`.
    private enum Height {
        static let tone: Float = 0.008
        static let shore: Float = 0.016
        static let seam: Float = 0.022
    }

    private static func point(_ angle: Float, _ radius: Float, y: Float) -> SIMD3<Float> {
        [cos(angle) * radius, y, sin(angle) * radius]
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
        let distance = simd_length(point)
        guard distance > 1e-4 else { return true }
        return distance < radius(atAngle: atan2(point.y, point.x)) * margin
    }
}
