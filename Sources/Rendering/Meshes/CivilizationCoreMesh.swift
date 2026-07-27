import Foundation
import RealityKit
import UIKit
import simd

/// The visual anchor of a home fragment: ~10 m across, ~8 m tall — roughly four
/// citizen-heights of vertical mass, so it dominates its fragment at the default
/// 82 m zoom without swallowing the buildable ground around it.
///
/// The two Cores are authored to separate in a black-and-white thumbnail, which
/// is the bible's real test of civilization identity:
///
/// - **Sunwoven** — a flared solar-fabric canopy with a drooping hem, ribbed in
///   gold, sitting over an ivory drum on a stepped apron. Four pennant masts
///   push the silhouette outward. The read is *pavilion*: light, tented, woven.
/// - **Gravemark** — three battered plated tiers stacked into a keep, ringed by
///   copper seams, with four angular corner pylons and a blunt central spire.
///   The read is *bunker*: heavy, terraced, planted.
///
/// Nothing here is a stock primitive. Every volume is a tapered polygonal solid
/// with a deliberate batter, and every structure carries at least one identity
/// detail that survives at thumbnail size.
@MainActor
enum CivilizationCoreMesh {

    static func make(faction: Faction, seed: UInt64) -> Entity {
        switch faction {
        case .sunwoven: sunwoven(seed: seed)
        case .gravemark: gravemark(seed: seed)
        }
    }

    // MARK: - Sunwoven

    private static func sunwoven(seed: UInt64) -> Entity {
        var random = DeterministicRandom.stream(seed: seed, tag: "core.sunwoven")

        var stone = StructureBuilder()
        var ivory = StructureBuilder()
        var gold = StructureBuilder()
        var glow = StructureBuilder()

        let sides = 8
        // Half a segment of phase puts a flat face toward +Z, which is the face
        // the default north-up camera looks straight at.
        let phase = Float.pi / Float(sides)

        // Stepped apron. Uncapped: the gold collar lands on the same ring, so a
        // cap here would only ever be hidden geometry.
        //
        // The apron is deliberately wider than the canopy above it. An apron
        // tucked inside the overhang disappears from a 57° top-down view, which
        // flattens the whole building into a disc — measured in the rendered
        // build, not assumed.
        let apronFoot = StructureGeometry.ring(sides: sides, radius: 5.30, y: 0, phase: phase)
        let apronTop = StructureGeometry.ring(sides: sides, radius: 5.00, y: 0.52, phase: phase)
        stone.addSolid(lower: apronFoot, upper: apronTop, capTop: false)

        // Woven-gold collar. Its cap is the visible walkway ring around the drum.
        let collarTop = StructureGeometry.ring(sides: sides, radius: 4.62, y: 0.90, phase: phase)
        gold.addSolid(lower: apronTop, upper: collarTop)

        // Ivory drum.
        let drumFoot = StructureGeometry.ring(sides: sides, radius: 3.50, y: 0.90, phase: phase)
        let drumTop = StructureGeometry.ring(sides: sides, radius: 3.28, y: 3.35, phase: phase)
        ivory.addSolid(lower: drumFoot, upper: drumTop, capTop: false)

        // Light-lattice inlays on alternating drum faces — the restrained
        // turquoise the bible allows as an accent, never as a body colour.
        for face in stride(from: 0, to: sides, by: 2) {
            glow.addFacePanel(
                lower: drumFoot,
                upper: drumTop,
                face: face,
                inset: 0.30,
                from: 0.22,
                to: 0.78,
                proud: 0.07
            )
        }

        // Canopy: an overhanging hem, then the long flare up to the crown. Its
        // eaves stop short of the apron rim so the pennant masts stand outside
        // the silhouette rather than inside a tent they cannot be seen through.
        let crownY = random.float(in: 6.15...6.45)
        let hem = StructureGeometry.ring(sides: sides, radius: 3.86, y: 2.96, phase: phase)
        let eaves = StructureGeometry.ring(sides: sides, radius: 4.42, y: 3.35, phase: phase)
        let crown = StructureGeometry.ring(sides: sides, radius: 1.15, y: crownY, phase: phase)
        ivory.addBand(lower: hem, upper: eaves, pivot: [0, 3.15, 0])
        ivory.addBand(lower: eaves, upper: crown, pivot: [0, 4.10, 0])

        // Gold ribbing along every canopy fold. These are what make the dome read
        // as woven fabric over a frame rather than as a smooth cone.
        for index in 0..<sides {
            gold.addRib(from: eaves[index], to: crown[index], axis: .zero, halfWidth: 0.11, taper: 0.55, proud: 0.05)
        }

        // Finial drum and spire.
        let finialFoot = StructureGeometry.ring(sides: 6, radius: 1.05, y: crownY)
        let finialTop = StructureGeometry.ring(sides: 6, radius: 0.78, y: crownY + 0.55)
        gold.addSolid(lower: finialFoot, upper: finialTop, capTop: false)
        gold.addSpire(base: finialTop, apex: [0, random.float(in: 7.85...8.15), 0])

        // Four pennant masts on the apron, outboard of the canopy eaves. They
        // break the dome's rotational symmetry, which is what stops it reading
        // as a bare hemisphere from directly above.
        for index in 0..<4 {
            let angle = phase + (Float(index) + 0.5) * .pi / 2
            let base = SIMD2<Float>(cos(angle) * 4.78, sin(angle) * 4.78)
            let topY = random.float(in: 2.55...3.05)

            let poleFoot = StructureGeometry.ring(sides: 4, radius: 0.12, y: 0.90, phase: .pi / 4, center: base)
            let poleTop = StructureGeometry.ring(sides: 4, radius: 0.085, y: topY, phase: .pi / 4, center: base)
            gold.addSolid(lower: poleFoot, upper: poleTop, capTop: false)
            gold.addSpire(base: poleTop, apex: [base.x, topY + 0.30, base.y])

            let radial = StructureGeometry.direction([base.x, 0, base.y])
            let tangent = simd_cross([0, 1, 0], radial)
            let anchor = SIMD3<Float>(base.x, topY - 0.12, base.y)
            glow.addQuad(
                anchor,
                anchor + tangent * 0.72 - [0, 0.22, 0],
                anchor + tangent * 0.72 - [0, 0.82, 0],
                anchor - [0, 0.68, 0],
                facing: radial
            )
        }

        return StructureAssembly.entity(
            named: "core.sunwoven",
            zones: [
                StructureZone("apron", stone, StructureMaterial.matte(SunfoldPalette.sunwovenSurface)),
                StructureZone("shell", ivory, StructureMaterial.matte(SunfoldPalette.sunwovenIvory, roughness: 0.88)),
                StructureZone("gold", gold, StructureMaterial.matte(SunfoldPalette.sunwovenGold, roughness: 0.86)),
                StructureZone("seam", glow, StructureMaterial.glow(SunfoldPalette.sunwovenTurquoise, opacity: 0.88)),
            ]
        )
    }

    // MARK: - Gravemark

    private static func gravemark(seed: UInt64) -> Entity {
        var random = DeterministicRandom.stream(seed: seed, tag: "core.gravemark")

        var rock = StructureBuilder()
        var plate = StructureBuilder()
        var copper = StructureBuilder()
        var glow = StructureBuilder()

        // Octagonal apron under a hexagonal keep: the mismatch in symmetry is
        // deliberate and reads as a fortified platform carrying a separate mass.
        let apronFoot = StructureGeometry.ring(sides: 8, radius: 5.20, y: 0, phase: .pi / 8)
        let apronTop = StructureGeometry.ring(sides: 8, radius: 4.95, y: 0.38, phase: .pi / 8)
        rock.addSolid(lower: apronFoot, upper: apronTop, capTop: false)

        // Three battered tiers. Alternating phase gives each tier its own corner
        // rhythm, so the stack does not read as one extruded prism.
        let tierOneFoot = StructureGeometry.ring(sides: 6, radius: 4.30, y: 0.38)
        let tierOneTop = StructureGeometry.ring(sides: 6, radius: 3.85, y: 2.05)
        plate.addSolid(lower: tierOneFoot, upper: tierOneTop)

        let tierTwoFoot = StructureGeometry.ring(sides: 6, radius: 3.15, y: 2.05, phase: .pi / 6)
        let tierTwoTop = StructureGeometry.ring(sides: 6, radius: 2.75, y: 3.95, phase: .pi / 6)
        plate.addSolid(lower: tierTwoFoot, upper: tierTwoTop)

        let tierThreeFoot = StructureGeometry.ring(sides: 6, radius: 2.05, y: 3.95)
        let tierThreeTop = StructureGeometry.ring(sides: 6, radius: 1.68, y: 5.55)
        plate.addSolid(lower: tierThreeFoot, upper: tierThreeTop, capTop: false)

        // Blunt central spire — squared, not needle-thin, so it reads as mass.
        let spireFoot = StructureGeometry.ring(sides: 4, radius: 1.05, y: 5.55, phase: .pi / 4)
        let spireNeck = StructureGeometry.ring(sides: 4, radius: 0.44, y: 7.15, phase: .pi / 4)
        plate.addSolid(lower: spireFoot, upper: spireNeck, capTop: false)
        plate.addSpire(base: spireNeck, apex: [0, random.float(in: 7.85...8.15), 0])

        // Copper seams at the tier joints — the oxidised-metal signature.
        copper.addBand(
            lower: StructureGeometry.ring(sides: 6, radius: 3.97, y: 1.78),
            upper: StructureGeometry.ring(sides: 6, radius: 3.97, y: 2.06),
            pivot: [0, 1.92, 0]
        )
        copper.addBand(
            lower: StructureGeometry.ring(sides: 6, radius: 2.88, y: 3.66, phase: .pi / 6),
            upper: StructureGeometry.ring(sides: 6, radius: 2.88, y: 3.96, phase: .pi / 6),
            pivot: [0, 3.81, 0]
        )

        // Four corner pylons, tapering to copper tips. These are the strongest
        // thumbnail cue: a spiked crown no Sunwoven building ever has.
        for index in 0..<4 {
            let angle = (Float(index) + 0.5) * .pi / 2
            let base = SIMD2<Float>(cos(angle) * 4.15, sin(angle) * 4.15)
            let shoulderY = random.float(in: 3.10...3.55)

            let shaftFoot = StructureGeometry.ring(sides: 4, radius: 0.58, y: 0.38, phase: angle, center: base)
            let shaftTop = StructureGeometry.ring(sides: 4, radius: 0.32, y: shoulderY, phase: angle, center: base)
            rock.addSolid(lower: shaftFoot, upper: shaftTop, capTop: false)
            copper.addSpire(base: shaftTop, apex: [base.x, shoulderY + 0.95, base.y])
        }

        // Mineral-blue glow slots recessed into the lower tiers.
        for face in [0, 2, 4] {
            glow.addFacePanel(
                lower: tierOneFoot, upper: tierOneTop, face: face,
                inset: 0.40, from: 0.18, to: 0.74, proud: 0.06
            )
        }
        for face in [1, 4] {
            glow.addFacePanel(
                lower: tierTwoFoot, upper: tierTwoTop, face: face,
                inset: 0.38, from: 0.20, to: 0.72, proud: 0.06
            )
        }

        return StructureAssembly.entity(
            named: "core.gravemark",
            zones: [
                StructureZone("apron", rock, StructureMaterial.matte(SunfoldPalette.gravemarkRock, roughness: 0.97)),
                StructureZone("plate", plate, StructureMaterial.matte(SunfoldPalette.gravemarkSurface)),
                StructureZone("copper", copper, StructureMaterial.matte(SunfoldPalette.gravemarkCopper, roughness: 0.85)),
                StructureZone("seam", glow, StructureMaterial.glow(SunfoldPalette.gravemarkMineral, opacity: 0.85)),
            ]
        )
    }
}

// MARK: - Shared structure toolkit

// `FlatMeshBuilder` lives at the bottom of `FragmentMeshFactory.swift` because
// that was the first factory to need it. The same convention applies here: the
// vocabulary every authored structure shares lives under the first factory that
// needed it, rather than in a file that exists only to hold helpers.

/// A `FlatMeshBuilder` paired with a live triangle tally.
///
/// The tally is how an authored structure is held inside the bible's "clear
/// low-poly" band — roughly 40–200 triangles apiece — and it also lets a
/// material zone that ended up empty be dropped instead of handed to
/// `MeshResource` as an empty descriptor.
struct StructureBuilder {
    private var flat = FlatMeshBuilder()
    private(set) var triangleCount = 0

    /// Adds a triangle facing away from `reference`, exactly as
    /// `FlatMeshBuilder` does, and counts it.
    mutating func addTriangle(
        _ a: SIMD3<Float>,
        _ b: SIMD3<Float>,
        _ c: SIMD3<Float>,
        facing reference: SIMD3<Float>
    ) {
        // Mirrors FlatMeshBuilder's degeneracy rejection so the tally describes
        // the geometry that actually reaches the mesh, not the calls made.
        guard simd_length_squared(simd_cross(b - a, c - a)) > 1e-12 else { return }
        flat.addTriangle(a, b, c, facing: reference)
        triangleCount += 1
    }

    /// Two triangles across a corner loop, all facing `reference`.
    mutating func addQuad(
        _ a: SIMD3<Float>,
        _ b: SIMD3<Float>,
        _ c: SIMD3<Float>,
        _ d: SIMD3<Float>,
        facing reference: SIMD3<Float>
    ) {
        addTriangle(a, b, c, facing: reference)
        addTriangle(a, c, d, facing: reference)
    }

    /// A quad on a closed solid: outward is simply "away from the interior
    /// point", which is correct for every convex volume built here and removes
    /// per-face normal reasoning entirely.
    mutating func addQuad(
        _ a: SIMD3<Float>,
        _ b: SIMD3<Float>,
        _ c: SIMD3<Float>,
        _ d: SIMD3<Float>,
        pivot: SIMD3<Float>
    ) {
        addQuad(a, b, c, d, facing: (a + b + c + d) * 0.25 - pivot)
    }

    /// Joins two matched rings with a strip of quads. `pivot` is any point
    /// inside the volume the band belongs to.
    ///
    /// Pass `outward: false` for a surface seen from the inside — the wall of a
    /// grow trough or a sunken kerb — where the lit face is the one turned back
    /// toward the axis.
    mutating func addBand(
        lower: [SIMD3<Float>],
        upper: [SIMD3<Float>],
        pivot: SIMD3<Float>,
        outward: Bool = true
    ) {
        guard lower.count == upper.count, lower.count >= 3 else { return }
        for index in lower.indices {
            let next = (index + 1) % lower.count
            let a = lower[index], b = lower[next], c = upper[next], d = upper[index]
            let reference = (a + b + c + d) * 0.25 - pivot
            addQuad(a, b, c, d, facing: outward ? reference : -reference)
        }
    }

    /// A standing ring: an annulus extruded along Z, built as `segments` radial
    /// slabs. The Sunwoven Outpost's whole silhouette is this shape, so it is a
    /// primitive rather than a one-off.
    mutating func addStandingRing(
        center: SIMD3<Float>,
        outerRadius: Float,
        innerRadius: Float,
        halfThickness: Float,
        segments: Int
    ) {
        let count = max(segments, 3)
        for index in 0..<count {
            let start = Float(index) / Float(count) * 2 * .pi
            let end = Float(index + 1) / Float(count) * 2 * .pi
            let middle = (start + end) * 0.5
            let radial = SIMD3<Float>(cos(middle), sin(middle), 0)

            func point(_ angle: Float, _ radius: Float, _ depth: Float) -> SIMD3<Float> {
                center + [cos(angle) * radius, sin(angle) * radius, depth]
            }

            let outerNear = point(start, outerRadius, halfThickness)
            let outerFar = point(end, outerRadius, halfThickness)
            let innerNear = point(start, innerRadius, halfThickness)
            let innerFar = point(end, innerRadius, halfThickness)
            let outerNearBack = point(start, outerRadius, -halfThickness)
            let outerFarBack = point(end, outerRadius, -halfThickness)
            let innerNearBack = point(start, innerRadius, -halfThickness)
            let innerFarBack = point(end, innerRadius, -halfThickness)

            addQuad(outerNear, outerFar, outerFarBack, outerNearBack, facing: radial)
            addQuad(innerNear, innerNearBack, innerFarBack, innerFar, facing: -radial)
            addQuad(outerNear, innerNear, innerFar, outerFar, facing: [0, 0, 1])
            addQuad(outerNearBack, outerFarBack, innerFarBack, innerNearBack, facing: [0, 0, -1])
        }
    }

    /// Fans a ring to a single point — a cone, a cap, or a spire tip.
    mutating func addFan(ring: [SIMD3<Float>], apex: SIMD3<Float>, pivot: SIMD3<Float>) {
        guard ring.count >= 3 else { return }
        for index in ring.indices {
            let next = (index + 1) % ring.count
            let centroid = (ring[index] + ring[next] + apex) / 3
            addTriangle(ring[index], ring[next], apex, facing: centroid - pivot)
        }
    }

    /// A flat cap closing `ring` at its own centre.
    mutating func addCap(ring: [SIMD3<Float>], pivot: SIMD3<Float>) {
        addFan(ring: ring, apex: StructureGeometry.centroid(ring), pivot: pivot)
    }

    /// A closed tapering solid between two matched rings. The default omits the
    /// bottom cap: structures sit on the ground, so their underside is never seen.
    mutating func addSolid(
        lower: [SIMD3<Float>],
        upper: [SIMD3<Float>],
        capTop: Bool = true,
        capBottom: Bool = false
    ) {
        let pivot = StructureGeometry.centroid(lower + upper)
        addBand(lower: lower, upper: upper, pivot: pivot)
        if capTop { addCap(ring: upper, pivot: pivot) }
        if capBottom { addCap(ring: lower, pivot: pivot) }
    }

    /// A cone rising from `base` to a point.
    mutating func addSpire(base: [SIMD3<Float>], apex: SIMD3<Float>) {
        addFan(ring: base, apex: apex, pivot: (StructureGeometry.centroid(base) + apex) * 0.5)
    }

    /// A double-ended shard: a ring pulled to a point above and below. Used for
    /// suspended Aether motes, where a closed floating form is the whole read.
    mutating func addShard(ring: [SIMD3<Float>], top: SIMD3<Float>, bottom: SIMD3<Float>) {
        let pivot = StructureGeometry.centroid(ring)
        addFan(ring: ring, apex: top, pivot: pivot)
        addFan(ring: ring, apex: bottom, pivot: pivot)
    }

    /// A triangular prism — a buttress fin, a furrow ridge, a hull strake.
    mutating func addFin(
        _ a: SIMD3<Float>,
        _ b: SIMD3<Float>,
        _ c: SIMD3<Float>,
        extrude offset: SIMD3<Float>
    ) {
        let a2 = a + offset, b2 = b + offset, c2 = c + offset
        let pivot = (a + b + c + a2 + b2 + c2) / 6
        addQuad(a, b, b2, a2, pivot: pivot)
        addQuad(b, c, c2, b2, pivot: pivot)
        addQuad(c, a, a2, c2, pivot: pivot)
        addTriangle(a, b, c, facing: (a + b + c) / 3 - pivot)
        addTriangle(a2, b2, c2, facing: (a2 + b2 + c2) / 3 - pivot)
    }

    /// A narrow raised rib running along a surface fold, pushed proud of the
    /// wall behind it so it never z-fights.
    ///
    /// `axis` is the XZ position of the solid's centreline, which is what "proud"
    /// is measured away from.
    mutating func addRib(
        from start: SIMD3<Float>,
        to end: SIMD3<Float>,
        axis: SIMD2<Float>,
        halfWidth: Float,
        taper: Float,
        proud: Float
    ) {
        let along = StructureGeometry.direction(end - start)
        let radial = StructureGeometry.direction([start.x - axis.x, 0, start.z - axis.y])
        let side = StructureGeometry.direction(simd_cross(along, radial), fallback: [1, 0, 0])
        let outward = StructureGeometry.direction(simd_cross(side, along), fallback: radial)
        let lift = outward * proud
        addQuad(
            start - side * halfWidth + lift,
            start + side * halfWidth + lift,
            end + side * (halfWidth * taper) + lift,
            end - side * (halfWidth * taper) + lift,
            facing: outward
        )
    }

    /// A flat inlay set into one face of a band, addressed by face index.
    ///
    /// `inset` is the fraction trimmed from each side, `from`/`to` are heights
    /// along the face in 0...1, and `proud` lifts the panel off the wall.
    mutating func addFacePanel(
        lower: [SIMD3<Float>],
        upper: [SIMD3<Float>],
        face index: Int,
        inset: Float,
        from bottom: Float,
        to top: Float,
        proud: Float,
        axis: SIMD2<Float> = .zero
    ) {
        guard lower.count == upper.count, lower.count >= 3 else { return }
        let next = (index + 1) % lower.count
        let footLeft = lower[index], footRight = lower[next]
        let headLeft = upper[index], headRight = upper[next]

        func corner(_ across: Float, _ up: Float) -> SIMD3<Float> {
            let foot = footLeft + (footRight - footLeft) * across
            let head = headLeft + (headRight - headLeft) * across
            return foot + (head - foot) * up
        }

        let middle = (footLeft + footRight + headLeft + headRight) * 0.25
        let outward = StructureGeometry.direction([middle.x - axis.x, 0, middle.z - axis.y])
        let lift = outward * proud

        addQuad(
            corner(inset, bottom) + lift,
            corner(1 - inset, bottom) + lift,
            corner(1 - inset, top) + lift,
            corner(inset, top) + lift,
            facing: outward
        )
    }

    /// A folded blade: two triangles meeting along a raised spine, so a frond or
    /// crop leaf still reads when the camera yaws to look along it edge-on.
    mutating func addBlade(base: SIMD3<Float>, tip: SIMD3<Float>, side: SIMD3<Float>, lift: Float) {
        let ridge = base + [0, lift, 0]
        addTriangle(base - side, ridge, tip, facing: -side + [0, 0.5, 0])
        addTriangle(base + side, ridge, tip, facing: side + [0, 0.5, 0])
    }

    /// An irregular faceted boulder: a jittered footprint, a smaller shoulder
    /// ring shoved off-axis, and one apex. No two draws are alike, which is what
    /// keeps a deposit cluster from reading as stamped copies.
    mutating func addBoulder(
        center: SIMD2<Float>,
        radius: Float,
        height: Float,
        sides: Int,
        random: inout DeterministicRandom
    ) {
        let phase = random.float(in: 0...(2 * .pi))
        let footRadii = (0..<sides).map { _ in radius * random.float(in: 0.74...1.12) }
        let shoulderRadii = (0..<sides).map { _ in radius * random.float(in: 0.34...0.62) }
        let lean = SIMD2<Float>(
            random.float(in: -0.22...0.22) * radius,
            random.float(in: -0.22...0.22) * radius
        )

        let foot = StructureGeometry.ring(radii: footRadii, y: 0, phase: phase, center: center)
        let shoulder = StructureGeometry.ring(
            radii: shoulderRadii,
            y: height * random.float(in: 0.48...0.66),
            phase: phase,
            center: center + lean
        )
        let apex = SIMD3<Float>(
            center.x + lean.x * 1.6,
            height,
            center.y + lean.y * 1.6
        )

        let pivot = SIMD3<Float>(center.x, height * 0.35, center.y)
        addBand(lower: foot, upper: shoulder, pivot: pivot)
        addFan(ring: shoulder, apex: apex, pivot: pivot)
    }

    /// Lofts a hull through matched cross-sections and caps both ends.
    mutating func addLoft(sections: [[SIMD3<Float>]], nose: SIMD3<Float>?, tail: SIMD3<Float>?) {
        guard let first = sections.first, let last = sections.last, sections.count >= 2 else { return }
        let pivot = StructureGeometry.centroid(sections.flatMap { $0 })
        for index in 0..<(sections.count - 1) {
            addBand(lower: sections[index], upper: sections[index + 1], pivot: pivot)
        }
        if let nose { addFan(ring: first, apex: nose, pivot: pivot) }
        if let tail { addFan(ring: last, apex: tail, pivot: pivot) }
    }

    /// A model entity for this zone, or `nil` when nothing was built.
    @MainActor
    func makeEntity(named name: String, material: any RealityKit.Material) -> Entity? {
        guard triangleCount > 0 else { return nil }
        let entity = Entity()
        entity.name = name
        entity.components.set(
            ModelComponent(mesh: flat.makeMesh(named: name), materials: [material])
        )
        return entity
    }
}

/// Point generators shared by every authored structure. Pure maths: no
/// RealityKit, no actor isolation, trivially testable.
enum StructureGeometry {

    /// A closed horizontal polygon.
    static func ring(
        sides: Int,
        radius: Float,
        y: Float,
        phase: Float = 0,
        center: SIMD2<Float> = .zero
    ) -> [SIMD3<Float>] {
        ring(radii: Array(repeating: radius, count: max(sides, 3)), y: y, phase: phase, center: center)
    }

    /// A closed horizontal polygon with a per-vertex radius, for jittered rock.
    static func ring(
        radii: [Float],
        y: Float,
        phase: Float = 0,
        center: SIMD2<Float> = .zero
    ) -> [SIMD3<Float>] {
        let count = radii.count
        guard count >= 3 else { return [] }
        return (0..<count).map { index in
            let angle = phase + Float(index) / Float(count) * 2 * .pi
            return SIMD3<Float>(
                center.x + cos(angle) * radii[index],
                y,
                center.y + sin(angle) * radii[index]
            )
        }
    }

    /// A closed horizontal ellipse, for hulls and long plated slabs.
    static func ring(
        sides: Int,
        radiusX: Float,
        radiusZ: Float,
        y: Float,
        phase: Float = 0,
        center: SIMD2<Float> = .zero
    ) -> [SIMD3<Float>] {
        let count = max(sides, 3)
        return (0..<count).map { index in
            let angle = phase + Float(index) / Float(count) * 2 * .pi
            return SIMD3<Float>(
                center.x + cos(angle) * radiusX,
                y,
                center.y + sin(angle) * radiusZ
            )
        }
    }

    /// Four corners, counter-clockwise seen from above.
    static func rectangle(
        width: Float,
        depth: Float,
        y: Float,
        center: SIMD2<Float> = .zero
    ) -> [SIMD3<Float>] {
        let halfWidth = width * 0.5
        let halfDepth = depth * 0.5
        return [
            [center.x + halfWidth, y, center.y + halfDepth],
            [center.x - halfWidth, y, center.y + halfDepth],
            [center.x - halfWidth, y, center.y - halfDepth],
            [center.x + halfWidth, y, center.y - halfDepth],
        ]
    }

    static func centroid(_ points: [SIMD3<Float>]) -> SIMD3<Float> {
        guard !points.isEmpty else { return .zero }
        return points.reduce(SIMD3<Float>.zero, +) / Float(points.count)
    }

    /// Normalises, or returns `fallback` rather than a NaN vector.
    static func direction(
        _ vector: SIMD3<Float>,
        fallback: SIMD3<Float> = [0, 1, 0]
    ) -> SIMD3<Float> {
        let lengthSquared = simd_length_squared(vector)
        return lengthSquared > 1e-12 ? vector / sqrt(lengthSquared) : fallback
    }
}

/// The material vocabulary. Structures are matte and unlit-free except where
/// something is genuinely self-luminous, which is what keeps the key light
/// doing the shape-reading work.
@MainActor
enum StructureMaterial {

    /// Non-metallic and rough, per the bible's flat/soft PBR ceiling.
    static func matte(_ color: UIColor, roughness: Float = 0.92) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: color)
        material.roughness = .init(floatLiteral: roughness)
        material.metallic = .init(floatLiteral: 0.0)
        material.faceCulling = .none
        return material
    }

    /// Reserved for glow seams, lumen light and drive wash — nothing else.
    ///
    /// An alpha on the tint alone does not make an `UnlitMaterial` translucent —
    /// it renders fully opaque until `blending` is set. Measured in the rendered
    /// build: ground seams asked for 0.34 and came back solid gold. Anything
    /// wanting partial opacity must say so on `blending`.
    static func glow(_ color: UIColor, opacity: CGFloat = 1.0) -> UnlitMaterial {
        var material = UnlitMaterial(color: color)
        material.faceCulling = .none
        if opacity < 1 {
            material.blending = .transparent(opacity: .init(floatLiteral: Float(opacity)))
        }
        return material
    }

    /// Mixes two colours. Nothing built from this invents a hue that is not
    /// already in the locked identity — it only sits between two of them.
    static func blend(_ from: UIColor, _ to: UIColor, _ amount: CGFloat) -> UIColor {
        var fromRed: CGFloat = 0, fromGreen: CGFloat = 0, fromBlue: CGFloat = 0, fromAlpha: CGFloat = 1
        var toRed: CGFloat = 0, toGreen: CGFloat = 0, toBlue: CGFloat = 0, toAlpha: CGFloat = 1
        guard from.getRed(&fromRed, green: &fromGreen, blue: &fromBlue, alpha: &fromAlpha),
              to.getRed(&toRed, green: &toGreen, blue: &toBlue, alpha: &toAlpha)
        else { return from }
        return UIColor(
            red: fromRed + (toRed - fromRed) * amount,
            green: fromGreen + (toGreen - fromGreen) * amount,
            blue: fromBlue + (toBlue - fromBlue) * amount,
            alpha: fromAlpha
        )
    }

    /// Shifts a palette colour's value without inventing a new hue, so soil,
    /// crop and crystal tones all stay traceable to the locked identity.
    static func shade(_ color: UIColor, _ factor: CGFloat) -> UIColor {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 1
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return color }
        return UIColor(
            red: min(red * factor, 1),
            green: min(green * factor, 1),
            blue: min(blue * factor, 1),
            alpha: alpha
        )
    }
}

/// One material zone of an authored structure.
@MainActor
struct StructureZone {
    let suffix: String
    let builder: StructureBuilder
    let material: any RealityKit.Material

    init(_ suffix: String, _ builder: StructureBuilder, _ material: any RealityKit.Material) {
        self.suffix = suffix
        self.builder = builder
        self.material = material
    }
}

/// Assembles material zones into one named entity whose origin is its footprint
/// centre and whose base sits at y = 0.
@MainActor
enum StructureAssembly {
    static func entity(named name: String, zones: [StructureZone]) -> Entity {
        let root = Entity()
        root.name = name

        var total = 0
        for zone in zones {
            total += zone.builder.triangleCount
            guard let child = zone.builder.makeEntity(
                named: "\(name).\(zone.suffix)",
                material: zone.material
            ) else { continue }
            root.addChild(child)
        }

        DebugLog.info("Structure '\(name)': \(total) triangles across \(root.children.count) zones.")
        return root
    }
}
