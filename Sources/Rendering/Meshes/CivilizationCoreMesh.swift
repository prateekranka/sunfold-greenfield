import Foundation
import RealityKit
import UIKit
import simd

/// The visual anchor of a home fragment — and the single most important object
/// in the frame. ~10.8 m across at the plinth and ~15.4 m to the finial tip:
/// better than four times the height of every prop around it, which is what
/// makes it read as *the town centre* rather than as a large resource node.
///
/// The two Cores are authored to separate in a black-and-white thumbnail, which
/// is the bible's real test of civilization identity:
///
/// - **Sunwoven** — a tented pavilion: stepped stone plinth, a gold colonnade
///   with backlit fabric panels between its piers, two skirts of separate ivory
///   canopy petals split by a wide gold wheel, a pleated crown cone and a finial
///   spire, ringed by six banner masts slung with cords. The read is *pavilion*:
///   tall, woven, open, and the brightest thing on the fragment.
/// - **Gravemark** — four battered plated tiers stacked into a keep, ringed by
///   copper seams, with four angular corner pylons and a blunt central spire.
///   The read is *bunker*: heavy, terraced, planted.
///
/// Nothing here is a stock primitive. Every volume is a tapered polygonal solid
/// with a deliberate batter, and every structure carries at least one identity
/// detail that survives at thumbnail size.
///
/// ## Why the Core is the one structure that carries its own light
///
/// Every other building takes the world rig and nothing else. A Core carries a
/// `PointLightComponent` at its base because a landmark has to *do* something to
/// the ground around it: the warm pool it throws separates the settlement's
/// centre from the flat regolith at any zoom, and it is the only cue that
/// survives when the building itself is only a couple of hundred pixels tall.
/// It illuminates; it casts no shadows and touches no simulation state.
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

        // Twelve sides, not eight: the dome is the hero silhouette and eight
        // facets read as a folded paper cone at this size. Half a segment of
        // phase puts a flat *face* toward +Z, which is what the default
        // north-up camera looks straight at.
        let sides = 12
        let phase = Float.pi / Float(sides)

        var stone = StructureBuilder()
        var gold = StructureBuilder()
        var panel = StructureBuilder()
        var lantern = StructureBuilder()
        var banner = StructureBuilder()
        // The drum wraps, so it gets a cylindrical unwrap rather than box
        // mapping: the weave then runs continuously around it instead of
        // restarting at every facet.
        var drum = StructureBuilder(
            uv: .cylindrical(metersPerTile: MaterialLibrary.metersPerTile, tilesAround: 5.5)
        )
        // The canopy takes face-plane projection. A spherical unwrap is right
        // for one closed shell and wrong for two dozen separately slanted
        // panels; face-plane has no stretch at any angle.
        //
        // Two builders on alternating petals, as the dome had on alternating
        // gores, and for the same reason: a canopy that resolves to one flat
        // value is the failure this splits to prevent. The albedo gap is now
        // ~9% rather than the dome's 20%, because the petals differ in *normal*
        // far more than the dome's gores ever did — a long petal and a short one
        // droop at different angles, so the light does most of the separating
        // and the albedo only has to finish it.
        let canopyUV = MaterialLibrary.facePlanarUVProjection
        var canopyLight = StructureBuilder(uv: canopyUV)
        var canopyFold = StructureBuilder(uv: canopyUV)

        /// A flat gold strip laid along a near-horizontal run.
        ///
        /// `addRib` cannot do this one. It derives its side vector from
        /// `cross(along, radial)`, which collapses to nothing when the run *is*
        /// radial — every batten on a canopy petal and every spoke on the wheel
        /// would come out along the world X axis.
        func batten(
            from start: SIMD3<Float>,
            to end: SIMD3<Float>,
            halfWidth: Float,
            taper: Float = 0.34
        ) {
            let along = StructureGeometry.direction(end - start, fallback: [1, 0, 0])
            let side = StructureGeometry.direction(simd_cross([0, 1, 0], along), fallback: [1, 0, 0])
            let lift = SIMD3<Float>(0, 0.035, 0)
            gold.addQuad(
                start - side * halfWidth + lift,
                start + side * halfWidth + lift,
                end + side * (halfWidth * taper) + lift,
                end - side * (halfWidth * taper) + lift,
                facing: [0, 1, 0]
            )
        }

        /// One tier of the canopy: a petal per face of `root`, tips alternating
        /// long and short.
        ///
        /// The alternation is the point. A ring of identical petals is still a
        /// circle in silhouette, and a circle is what the old dome already was.
        /// Long and short tips scallop the skirt, so the tier has an outline
        /// that survives being 300 px tall.
        func canopyTier(
            root: [SIMD3<Float>],
            longRadius: Float,
            shortRadius: Float,
            longY: Float,
            shortY: Float,
            spine: Float,
            bulge: Float,
            gap: Float,
            tipWidth: Float
        ) {
            for index in root.indices {
                let next = (index + 1) % root.count
                let a = root[index], b = root[next]
                // The gap between petals is what the tier behind shows through.
                let rootLeft = a + (b - a) * gap
                let rootRight = a + (b - a) * (1 - gap)

                let long = index % 2 == 0
                let middle = (a + b) * 0.5
                let outward = StructureGeometry.direction([middle.x, 0, middle.z], fallback: [1, 0, 0])
                let reach = long ? longRadius : shortRadius
                let tipMid = SIMD3<Float>(outward.x * reach, long ? longY : shortY, outward.z * reach)

                // A blunt tip, sized as a fraction of the root's own width, so a
                // tier stays proportioned whatever radius it springs from.
                let across = StructureGeometry.direction(rootLeft - rootRight, fallback: [1, 0, 0])
                let half = simd_distance(rootLeft, rootRight) * 0.5 * tipWidth
                let tipLeft = tipMid + across * half
                let tipRight = tipMid - across * half

                let ridge: SIMD3<Float>
                if long {
                    ridge = canopyLight.addPetal(
                        rootLeft: rootLeft, rootRight: rootRight,
                        tipLeft: tipLeft, tipRight: tipRight,
                        spine: spine, bulge: bulge
                    )
                } else {
                    ridge = canopyFold.addPetal(
                        rootLeft: rootLeft, rootRight: rootRight,
                        tipLeft: tipLeft, tipRight: tipRight,
                        spine: spine * 0.78, bulge: bulge
                    )
                }
                batten(from: ridge, to: tipMid, halfWidth: 0.085)
            }
        }

        // MARK: Stepped plinth
        //
        // Three risers and three treads. The plinth is deliberately wider than
        // everything above it: an apron tucked inside the overhang disappears
        // from a 57° top-down view, which flattens the whole building into a
        // disc — measured in the rendered build, not assumed.
        let plinth: [(radius: Float, y: Float, tread: Float)] = [
            (5.40, 0.00, 5.02),
            (4.90, 0.26, 4.62),
            (4.50, 0.54, 4.22),
        ]
        var plinthFoot = StructureGeometry.ring(sides: sides, radius: plinth[0].radius, y: 0, phase: phase)
        for (index, step) in plinth.enumerated() {
            let riseTop = index + 1 < plinth.count ? plinth[index + 1].y : 0.82
            let foot = StructureGeometry.ring(sides: sides, radius: step.radius, y: step.y, phase: phase)
            let head = StructureGeometry.ring(sides: sides, radius: step.radius - 0.14, y: riseTop, phase: phase)
            let tread = StructureGeometry.ring(sides: sides, radius: step.tread, y: riseTop, phase: phase)
            stone.addBand(lower: foot, upper: head, pivot: [0, step.y, 0])
            stone.addTread(outer: head, inner: tread)
            if index == 0 { plinthFoot = foot }
        }
        _ = plinthFoot

        // MARK: Gold walkway kerb
        //
        // The band the colonnade stands on. Its tread is the visible ring of
        // gold decking around the drum — the first hard value break above the
        // pale stone, and the thing that stops the plinth and the shell reading
        // as one continuous mass.
        // The *edge* is gold; the deck it encloses is pale stone. Concept 01's
        // gold is line work — kerbs, ribs, battens, an armature — and CP-07's
        // second render showed what happens when a horizontal annulus this wide
        // is handed to it: two brass discs stacked around the building, reading
        // as mass rather than as trim.
        let kerbFoot = StructureGeometry.ring(sides: sides, radius: 4.22, y: 0.82, phase: phase)
        let kerbTop = StructureGeometry.ring(sides: sides, radius: 4.06, y: 1.14, phase: phase)
        let kerbTread = StructureGeometry.ring(sides: sides, radius: 3.38, y: 1.14, phase: phase)
        let kerbLip = StructureGeometry.ring(sides: sides, radius: 3.94, y: 1.14, phase: phase)
        gold.addBand(lower: kerbFoot, upper: kerbTop, pivot: [0, 0.82, 0])
        gold.addTread(outer: kerbTop, inner: kerbLip)
        stone.addTread(outer: kerbLip, inner: kerbTread)

        // MARK: Colonnade
        //
        // A ring of gold piers standing off an ivory inner drum, with backlit
        // fabric panels in the bays between them. This is the tier that reads as
        // *architecture* from above: six piers throw six separate shadows across
        // the plinth, which no smooth cone can do.
        let colonnadeFoot = StructureGeometry.ring(sides: sides, radius: 3.38, y: 1.14, phase: phase)
        let colonnadeTop = StructureGeometry.ring(sides: sides, radius: 3.26, y: 4.62, phase: phase)
        drum.addSolid(lower: colonnadeFoot, upper: colonnadeTop, capTop: false)

        // Bays on the even faces, piers on the odd ones — so the face the camera
        // looks straight at is a lit panel rather than a pier blocking it.
        for face in stride(from: 0, to: sides, by: 2) {
            panel.addFacePanel(
                lower: colonnadeFoot, upper: colonnadeTop, face: face,
                inset: 0.16, from: 0.06, to: 0.92, proud: 0.05
            )
        }
        for face in stride(from: 1, to: sides, by: 2) {
            let angle = phase + (Float(face) + 0.5) * 2 * .pi / Float(sides)
            let center = SIMD2<Float>(cos(angle) * 4.00, sin(angle) * 4.00)
            // Phase + π/4 turns a flat face of the square pier outward, so it
            // catches the key as a plane rather than as an edge.
            let shaftFoot = StructureGeometry.ring(sides: 4, radius: 0.40, y: 1.14, phase: angle + .pi / 4, center: center)
            let shaftTop = StructureGeometry.ring(sides: 4, radius: 0.33, y: 4.24, phase: angle + .pi / 4, center: center)
            let capital = StructureGeometry.ring(sides: 4, radius: 0.52, y: 4.62, phase: angle + .pi / 4, center: center)
            gold.addSolid(lower: shaftFoot, upper: shaftTop, capTop: false)
            gold.addSolid(lower: shaftTop, upper: capital, capTop: true)
        }

        // MARK: Architrave and cornice
        let architraveFoot = StructureGeometry.ring(sides: sides, radius: 4.58, y: 4.62, phase: phase)
        let architraveTop = StructureGeometry.ring(sides: sides, radius: 4.34, y: 5.18, phase: phase)
        let corniceLip = StructureGeometry.ring(sides: sides, radius: 4.20, y: 5.18, phase: phase)
        let cornice = StructureGeometry.ring(sides: sides, radius: 3.66, y: 5.18, phase: phase)
        gold.addBand(lower: architraveFoot, upper: architraveTop, pivot: [0, 4.62, 0])
        gold.addTread(outer: architraveTop, inner: corniceLip)
        stone.addTread(outer: corniceLip, inner: cornice)
        // Closed from below as well: the cornice overhangs the colonnade by more
        // than half a metre and, at this camera pitch, its underside is visible
        // on the far side of the building.
        gold.addTread(outer: architraveFoot, inner: colonnadeTop, up: false)

        // MARK: Lower canopy
        //
        // The first of the two skirts, springing straight off the cornice and
        // overhanging the plinth. Its tips reach 5.78 m against a plinth of
        // 5.40, so the canopy throws a scalloped shadow onto its own stonework —
        // which is the cue that says *this thing has an eave* at any zoom.
        //
        // The droop is 22° from horizontal, and that number is doing more work
        // than the silhouette. The key sits at 52° elevation, so a panel drooping
        // 22° toward it takes the light at 13° off its normal against the ground's
        // 38°: the sunward half of the canopy is brighter than the ground it
        // stands on. The old dome had no such facet anywhere — its gores ran
        // 55–70° from horizontal, took the key at a graze, and that, not the
        // albedo, is why the Core read as a dark hole in a bright frame.
        let lowerRoot = StructureGeometry.ring(sides: sides, radius: 3.52, y: 5.34, phase: phase)
        canopyTier(
            root: lowerRoot,
            longRadius: 4.94, shortRadius: 4.52,
            longY: 4.86, shortY: 5.00,
            spine: 0.24, bulge: 0.16, gap: 0.02, tipWidth: 0.44
        )

        // MARK: Middle drum
        //
        // Seen *between* the petals rather than around them, so its turquoise
        // insets read as glimpses into a lit interior instead of as windows in a
        // wall. That is the relationship concept 01 has and the old Core did not:
        // a closed shell can only ever put its glazing on the outside.
        let midFoot = StructureGeometry.ring(sides: sides, radius: 3.44, y: 5.18, phase: phase)
        let midTop = StructureGeometry.ring(sides: sides, radius: 3.16, y: 7.44, phase: phase)
        drum.addSolid(lower: midFoot, upper: midTop, capTop: false)
        for index in 0..<sides {
            gold.addRib(
                from: midFoot[index], to: midTop[index],
                axis: .zero, halfWidth: 0.12, taper: 0.92, proud: 0.05
            )
        }
        // Panels on the *odd* faces, which are the ones a petal gap exposes.
        for face in stride(from: 1, to: sides, by: 2) {
            panel.addFacePanel(
                lower: midFoot, upper: midTop, face: face,
                inset: 0.26, from: 0.14, to: 0.84, proud: 0.05
            )
        }

        // MARK: Gold wheel
        //
        // The single element of concept 01's Core that reads at every zoom: a
        // wide horizontal gold ring where the two skirts meet, with spokes
        // running in to the crown. It is also the structural excuse for two
        // separate tiers — without it they stack into one cone.
        let wheelSides = 24
        let wheelOuterLow = StructureGeometry.ring(sides: wheelSides, radius: 3.30, y: 7.36, phase: phase)
        let wheelOuterHigh = StructureGeometry.ring(sides: wheelSides, radius: 3.30, y: 7.58, phase: phase)
        let wheelInnerLow = StructureGeometry.ring(sides: wheelSides, radius: 2.92, y: 7.36, phase: phase)
        let wheelInnerHigh = StructureGeometry.ring(sides: wheelSides, radius: 2.92, y: 7.58, phase: phase)
        gold.addBand(lower: wheelOuterLow, upper: wheelOuterHigh, pivot: [0, 7.47, 0])
        gold.addBand(lower: wheelInnerLow, upper: wheelInnerHigh, pivot: [0, 7.47, 0], outward: false)
        gold.addTread(outer: wheelOuterHigh, inner: wheelInnerHigh)
        gold.addTread(outer: wheelOuterLow, inner: wheelInnerLow, up: false)
        for index in stride(from: 0, to: wheelSides, by: 2) {
            let hub = StructureGeometry.direction(
                [wheelInnerHigh[index].x, 0, wheelInnerHigh[index].z], fallback: [1, 0, 0]
            ) * 1.94
            batten(
                from: wheelInnerHigh[index],
                to: [hub.x, 7.58, hub.z],
                halfWidth: 0.07
            )
        }

        // MARK: Upper canopy
        let upperRoot = StructureGeometry.ring(sides: sides, radius: 2.42, y: 7.98, phase: phase)
        canopyTier(
            root: upperRoot,
            longRadius: 3.62, shortRadius: 3.30,
            longY: 7.54, shortY: 7.64,
            spine: 0.20, bulge: 0.13, gap: 0.025, tipWidth: 0.44
        )

        // MARK: Crown drum and crown rosette
        //
        // A third, small skirt rather than a bare cone. Every tier that is a ring
        // of near-horizontal petals is a tier that takes the overhead key
        // squarely; every tier that is a closed cone is one that does not, and
        // CP-07's first render showed exactly that split — the petals came back
        // white and the cone came back grey-lavender in the same frame.
        let crownFoot = StructureGeometry.ring(sides: sides, radius: 2.10, y: 7.58, phase: phase)
        let crownHead = StructureGeometry.ring(sides: sides, radius: 1.90, y: 9.02, phase: phase)
        drum.addSolid(lower: crownFoot, upper: crownHead, capTop: false)
        for face in stride(from: 0, to: sides, by: 2) {
            lantern.addFacePanel(
                lower: crownFoot, upper: crownHead, face: face,
                inset: 0.32, from: 0.22, to: 0.78, proud: 0.05
            )
        }

        let crownRosette = StructureGeometry.ring(sides: sides, radius: 1.56, y: 9.44, phase: phase)
        canopyTier(
            root: crownRosette,
            longRadius: 2.48, shortRadius: 2.26,
            longY: 9.14, shortY: 9.22,
            spine: 0.16, bulge: 0.10, gap: 0.03, tipWidth: 0.44
        )

        // MARK: Crown spire
        //
        // Slender *and* short on purpose. It is the one closed surface left on
        // the building, so it is kept narrow enough that its dark side costs the
        // silhouette nothing, and pleated so the lit side still breaks into
        // facets. Shortened at CP-07's sixth render: at 1.7 m of run it stood
        // clear above the crown rosette as a single unbroken cone, and a cone
        // under an overhead key has no facet pointing at it — it read as a brown
        // plug in the middle of the tented top. Under a metre it sits down in
        // the petals, which is where the concept's finial rises from anyway.
        let spireFoot = StructureGeometry.pleatedRing(sides: sides, radius: 0.92, valley: 0.86, y: 9.20, phase: phase)
        let spireWaist = StructureGeometry.pleatedRing(sides: sides, radius: 0.50, valley: 0.88, y: 10.05, phase: phase)
        let crownY = random.float(in: 10.85...11.10)
        canopyLight.addBand(lower: spireFoot, upper: spireWaist, pivot: [0, 8.8, 0])
        canopyLight.addFan(ring: spireWaist, apex: [0, crownY, 0], pivot: [0, 9.6, 0])
        for index in stride(from: 0, to: sides, by: 2) {
            gold.addRib(
                from: spireFoot[index], to: spireWaist[index],
                axis: .zero, halfWidth: 0.09, taper: 0.72, proud: 0.045
            )
        }

        // MARK: Finial
        let finialFoot = StructureGeometry.ring(sides: 6, radius: 0.46, y: crownY - 0.26)
        let finialNeck = StructureGeometry.ring(sides: 6, radius: 0.38, y: crownY + 0.66)
        let finialCollar = StructureGeometry.ring(sides: 6, radius: 0.22, y: crownY + 1.06)
        gold.addSolid(lower: finialFoot, upper: finialNeck, capTop: false)
        gold.addSolid(lower: finialNeck, upper: finialCollar, capTop: false)
        gold.addSpire(base: finialCollar, apex: [0, random.float(in: 15.25...15.60), 0])
        // A lantern in the finial drum. It is small, high and bright, which is
        // exactly what the post-process bright pass wants: the Core gains a
        // point of bloom at its tip that nothing else in the frame has.
        for face in stride(from: 0, to: 6, by: 2) {
            lantern.addFacePanel(
                lower: finialFoot, upper: finialNeck, face: face,
                inset: 0.20, from: 0.16, to: 0.84, proud: 0.05
            )
        }

        // MARK: Banner masts and cords
        //
        // Five, outboard on the plinth, and **taller than the canopy** — which is
        // the whole reason they exist. CP-07's first render put their heads at
        // 7.9 m, below the crown, and the cords then sagged straight across the
        // building's face and read as wires strung over it. In concept 01 the
        // masts are the tallest thing after the finial and their cords hang in
        // clear air, so they frame the pavilion instead of crossing it.
        //
        // Five, not six: an odd count cannot line two masts up on one axis, so
        // the ring never resolves into a pair of posts at any camera yaw.
        let mastCount = 5
        var mastHeads: [SIMD3<Float>] = []
        for index in 0..<mastCount {
            let angle = phase + (Float(index) + 0.5) * 2 * .pi / Float(mastCount)
            let base = SIMD2<Float>(cos(angle) * 5.06, sin(angle) * 5.06)
            let topY = random.float(in: 10.30...10.80)

            let poleFoot = StructureGeometry.ring(sides: 4, radius: 0.22, y: 0.54, phase: angle + .pi / 4, center: base)
            let poleTop = StructureGeometry.ring(sides: 4, radius: 0.14, y: topY, phase: angle + .pi / 4, center: base)
            gold.addSolid(lower: poleFoot, upper: poleTop, capTop: false)
            let head = SIMD3<Float>(base.x, topY + 0.62, base.y)
            gold.addSpire(base: poleTop, apex: head)
            mastHeads.append(head)

            // A turquoise banner hanging off a crossarm. Matte, not luminous:
            // concept 01's banners are dyed cloth taking the key like everything
            // else, and an emissive one would put a second light source on the
            // silhouette where the building wants exactly one.
            let radial = StructureGeometry.direction([base.x, 0, base.y])
            let tangent = simd_cross([0, 1, 0], radial)
            let arm = SIMD3<Float>(base.x, topY - 0.34, base.y)
            let drop = random.float(in: 2.55...3.10)
            gold.addRib(
                from: arm + [0, 0.10, 0], to: arm + tangent * 1.18 + [0, 0.10, 0],
                axis: .zero, halfWidth: 0.07, taper: 0.7, proud: 0.0
            )
            banner.addQuad(
                arm,
                arm + tangent * 1.18,
                arm + tangent * 0.90 - [0, drop, 0],
                arm - [0, drop * 0.86, 0],
                facing: radial
            )
        }

        // Cords between adjacent mast heads, sagging on a parabola — near enough
        // to a catenary at this sag ratio to be indistinguishable, and it costs
        // no `cosh`. Five segments a span is where the curve stops reading as a
        // polyline at full zoom.
        for index in 0..<mastCount {
            let from = mastHeads[index]
            let to = mastHeads[(index + 1) % mastCount]
            let segments = 5
            let sag: Float = 0.92
            var previous = from
            for step in 1...segments {
                let t = Float(step) / Float(segments)
                var point = from + (to - from) * t
                point.y -= sag * 4 * t * (1 - t)
                // Untapered: a cord is one thickness end to end, and a tapered
                // segment repeated five times reads as a string of beads.
                batten(from: previous, to: point, halfWidth: 0.05, taper: 1.0)
                previous = point
            }
        }

        let core = StructureAssembly.entity(
            named: "core.sunwoven",
            zones: [
                StructureZone("plinth", stone, plinthMaterial),
                StructureZone("shell", drum, shellMaterial),
                StructureZone("canopy", canopyLight, canopyPanelMaterial),
                StructureZone("canopyfold", canopyFold, canopyFoldMaterial),
                StructureZone("gold", gold, coreGoldMaterial),
                StructureZone("banner", banner, bannerMaterial),
                StructureZone("panel", panel, MaterialLibrary.luminousSeam(SunfoldPalette.sunwovenTurquoise, intensity: 1.15)),
                StructureZone("lantern", lantern, StructureMaterial.glow(SunfoldPalette.sunwovenTurquoise, opacity: 0.78)),
            ]
        )
        core.addChild(
            hearthLight(
                named: "core.sunwoven.hearth",
                color: StructureMaterial.blend(SunfoldPalette.sunwovenGold, .white, 0.34),
                intensity: 90_000,
                radius: 15,
                height: 1.6
            )
        )
        return core
    }

    // MARK: Sunwoven materials
    //
    // **The Core must out-value the ground it stands on.** In concept 01 the
    // canopy measures 1.15× the linear luminance of the surrounding regolith and
    // is the brightest object in the frame. Measured on `cp06-density-palette`,
    // the old dome came back at **0.57×** — darker than the ground, so the one
    // building the eye is supposed to land on read as a hole in the frame.
    //
    // Two things caused that and both are fixed here. The geometry is the larger
    // half: a steep dome takes an overhead key at a graze, and no albedo can
    // undo that. The albedo is the rest — the ivories were pulled down to 0.75
    // and 0.60 of the palette against a *ground albedo of 0.855*, which is to
    // say the canopy was authored darker than sand and then lit worse.
    //
    // The old note here warned that 0.96 clips. It is still true and still the
    // reason these sit below the palette rather than at it, but the headroom
    // moved twice since it was written: CP-03 took `exposureScale` to 0.67 and
    // CP-06 to 0.72. 0.90 is inside the shoulder at that exposure.

    /// The canopy's long petals. The frame's brightest lit surface by design.
    private static var canopyPanelMaterial: PhysicallyBasedMaterial {
        StructureMaterial.matte(
            StructureMaterial.shade(SunfoldPalette.sunwovenIvory, 0.90),
            // A multiplier on the recipe's 0.58–0.88 roughness map, so the
            // canopy lands near 0.35: a broad specular lobe that sweeps across
            // the petals instead of a matte surface with no highlight at all.
            roughness: 0.45,
            surface: .wovenIvory
        )
    }

    /// The canopy's short petals, ~9% darker. The old dome needed a 20% albedo
    /// split to keep its gores apart because every gore at one height shared a
    /// normal; separate petals at two different droops do not, so the light does
    /// most of that work now and the albedo only finishes it.
    private static var canopyFoldMaterial: PhysicallyBasedMaterial {
        StructureMaterial.matte(
            StructureMaterial.shade(SunfoldPalette.sunwovenIvory, 0.82),
            roughness: 0.52,
            surface: .wovenIvory
        )
    }

    /// The vertical drums. Brighter still, because a vertical face takes far
    /// less of an overhead key — the *rendered* values land close, which is what
    /// keeps the building one material.
    private static var shellMaterial: PhysicallyBasedMaterial {
        StructureMaterial.matte(
            StructureMaterial.shade(SunfoldPalette.sunwovenIvory, 0.94),
            roughness: 0.62,
            surface: .wovenIvory
        )
    }

    /// The armature: gold that is *lit* rather than mirrored.
    ///
    /// `goldTrim`'s authored 0.85 metalness is right for a glinting kerb and
    /// wrong for a whole frame of thin members. A conductor has no diffuse
    /// term — everything it shows is a reflection — and what surrounds this
    /// building is a void with a single warm IBL lobe in it, so every batten
    /// away from the key's mirror direction reflected empty space. Measured at
    /// CP-07's first render: the wheel, the architrave, the ribs and the masts
    /// all came back dark bronze to near-black against concept 01's pale gold.
    ///
    /// 0.30 keeps enough specular for it to read as metal and restores the
    /// diffuse term that a scene lit by one hard key and almost no ambient
    /// actually needs. The tint is pulled a third toward ivory for the same
    /// reason the canopy was: this armature is a *bright* element in the
    /// concept, not a dark outline around bright panels.
    private static var coreGoldMaterial: PhysicallyBasedMaterial {
        MaterialLibrary.material(
            .goldTrim,
            tint: StructureMaterial.blend(SunfoldPalette.sunwovenGold, SunfoldPalette.sunwovenIvory, 0.32),
            roughness: 0.55,
            metallic: 0.30
        )
    }

    /// Dyed turquoise cloth. Deliberately *not* luminous: concept 01's banners
    /// take the key like everything else, and an emissive one would put a second
    /// light source on a silhouette that wants exactly one. Lifted toward ivory
    /// because a banner hangs vertically, and a vertical face under a 52° key
    /// keeps barely half of what it is given.
    private static var bannerMaterial: PhysicallyBasedMaterial {
        StructureMaterial.matte(
            StructureMaterial.blend(SunfoldPalette.sunwovenTurquoise, SunfoldPalette.sunwovenIvory, 0.30),
            roughness: 0.74,
            surface: .wovenIvory
        )
    }

    /// Pale inlaid pavement. It reads *warm* and close to the regolith's own
    /// value — the plinth used to be pulled down to 0.80 to separate from the
    /// ground by value, which is the opposite of concept 01, where the pavement
    /// is as bright as the sand and the separation is done by the gold kerb.
    /// Darkening it only helped the Core sink further into the frame.
    ///
    /// The *surface* is `.wovenIvory` rather than `.rimStone` for the same
    /// reason. `.rimStone`'s spec is authored around a cool grey reference
    /// (`[0.482, 0.487, 0.505]`), and retinting divides by that reference, so a
    /// warm tint over it comes back muted rather than warm — measured at CP-07's
    /// fifth render as a slate cobble drum wrapping the whole base of the
    /// building, the largest cold mass left in the Core's silhouette. This is
    /// dressed pavement in concept 01, not fractured rock, and the fine weave is
    /// the closer read of it as well as the warmer one.
    private static var plinthMaterial: PhysicallyBasedMaterial {
        StructureMaterial.matte(
            StructureMaterial.blend(SunfoldPalette.sunwovenSurface, SunfoldPalette.sunwovenIvory, 0.86),
            roughness: 0.90,
            surface: .wovenIvory
        )
    }

    // MARK: - Gravemark

    private static func gravemark(seed: UInt64) -> Entity {
        var random = DeterministicRandom.stream(seed: seed, tag: "core.gravemark")

        var rock = StructureBuilder()
        var plate = StructureBuilder()
        var plateLit = StructureBuilder()
        var copper = StructureBuilder()
        var panel = StructureBuilder()
        var glow = StructureBuilder()

        // Octagonal apron under a hexagonal keep: the mismatch in symmetry is
        // deliberate and reads as a fortified platform carrying a separate mass.
        // Two steps rather than one, so the keep is *planted* on something.
        let apronFoot = StructureGeometry.ring(sides: 8, radius: 5.35, y: 0, phase: .pi / 8)
        let apronHead = StructureGeometry.ring(sides: 8, radius: 5.18, y: 0.32, phase: .pi / 8)
        let apronTread = StructureGeometry.ring(sides: 8, radius: 4.94, y: 0.32, phase: .pi / 8)
        rock.addBand(lower: apronFoot, upper: apronHead, pivot: [0, 0, 0])
        rock.addTread(outer: apronHead, inner: apronTread)

        let stepFoot = StructureGeometry.ring(sides: 8, radius: 4.86, y: 0.32, phase: .pi / 8)
        let stepHead = StructureGeometry.ring(sides: 8, radius: 4.72, y: 0.66, phase: .pi / 8)
        let stepTread = StructureGeometry.ring(sides: 8, radius: 4.44, y: 0.66, phase: .pi / 8)
        rock.addBand(lower: stepFoot, upper: stepHead, pivot: [0, 0.32, 0])
        rock.addTread(outer: stepHead, inner: stepTread)

        // Four battered tiers. Alternating phase gives each tier its own corner
        // rhythm, so the stack does not read as one extruded prism, and the
        // zones alternate so consecutive tiers separate by value as well.
        let tierOneFoot = StructureGeometry.ring(sides: 6, radius: 4.40, y: 0.66)
        let tierOneTop = StructureGeometry.ring(sides: 6, radius: 3.92, y: 3.10)
        plate.addSolid(lower: tierOneFoot, upper: tierOneTop)

        let tierTwoFoot = StructureGeometry.ring(sides: 6, radius: 3.38, y: 3.10, phase: .pi / 6)
        let tierTwoTop = StructureGeometry.ring(sides: 6, radius: 2.98, y: 5.90, phase: .pi / 6)
        plateLit.addSolid(lower: tierTwoFoot, upper: tierTwoTop)

        let tierThreeFoot = StructureGeometry.ring(sides: 6, radius: 2.56, y: 5.90)
        let tierThreeTop = StructureGeometry.ring(sides: 6, radius: 2.16, y: 8.34)
        plate.addSolid(lower: tierThreeFoot, upper: tierThreeTop)

        let tierFourFoot = StructureGeometry.ring(sides: 6, radius: 1.82, y: 8.34, phase: .pi / 6)
        let tierFourTop = StructureGeometry.ring(sides: 6, radius: 1.56, y: 10.15, phase: .pi / 6)
        // Capped: the four-sided spire that lands on it is narrower than this
        // ring, and an uncapped hexagon under it would read as a black hole.
        plateLit.addSolid(lower: tierFourFoot, upper: tierFourTop, capTop: true)

        // Blunt central spire — squared, not needle-thin, so it reads as mass.
        let spireFoot = StructureGeometry.ring(sides: 4, radius: 1.12, y: 10.10, phase: .pi / 4)
        let spireNeck = StructureGeometry.ring(sides: 4, radius: 0.50, y: 12.35, phase: .pi / 4)
        plate.addSolid(lower: spireFoot, upper: spireNeck, capTop: false)
        plate.addSpire(base: spireNeck, apex: [0, random.float(in: 13.75...14.15), 0])

        // Copper seams at the tier joints — the oxidised-metal signature.
        for joint in [
            (radius: Float(4.04), low: Float(2.80), high: Float(3.12), phase: Float(0)),
            (radius: Float(3.10), low: Float(5.58), high: Float(5.92), phase: .pi / 6),
            (radius: Float(2.28), low: Float(8.02), high: Float(8.36), phase: Float(0)),
            (radius: Float(1.68), low: Float(9.84), high: Float(10.16), phase: .pi / 6),
        ] {
            copper.addBand(
                lower: StructureGeometry.ring(sides: 6, radius: joint.radius, y: joint.low, phase: joint.phase),
                upper: StructureGeometry.ring(sides: 6, radius: joint.radius, y: joint.high, phase: joint.phase),
                pivot: [0, (joint.low + joint.high) * 0.5, 0]
            )
        }

        // Four corner pylons, tapering to copper tips. These are the strongest
        // thumbnail cue: a spiked crown no Sunwoven building ever has, and now
        // tall enough to break the keep's own silhouette rather than hide in it.
        for index in 0..<4 {
            let angle = (Float(index) + 0.5) * .pi / 2
            let base = SIMD2<Float>(cos(angle) * 4.22, sin(angle) * 4.22)
            let shoulderY = random.float(in: 5.05...5.65)

            let shaftFoot = StructureGeometry.ring(sides: 4, radius: 0.62, y: 0.66, phase: angle, center: base)
            let shaftWaist = StructureGeometry.ring(sides: 4, radius: 0.44, y: shoulderY * 0.62, phase: angle, center: base)
            let shaftTop = StructureGeometry.ring(sides: 4, radius: 0.30, y: shoulderY, phase: angle, center: base)
            rock.addSolid(lower: shaftFoot, upper: shaftWaist, capTop: false)
            rock.addSolid(lower: shaftWaist, upper: shaftTop, capTop: false)
            copper.addSpire(base: shaftTop, apex: [base.x, shoulderY + 1.35, base.y])

            // A mineral slit up the outboard face of every pylon.
            let radial = StructureGeometry.direction([base.x, 0, base.y])
            let tangent = simd_cross([0, 1, 0], radial)
            let face = SIMD3<Float>(base.x, 0, base.y) + radial * 0.34
            glow.addQuad(
                face + tangent * 0.13 + [0, shoulderY * 0.30, 0],
                face - tangent * 0.13 + [0, shoulderY * 0.30, 0],
                face - tangent * 0.10 + [0, shoulderY * 0.92, 0],
                face + tangent * 0.10 + [0, shoulderY * 0.92, 0],
                facing: radial
            )
        }

        // Mineral-blue glow slots recessed into the tiers. The big ones are lit
        // emissive so they still take the key and read as *lit windows in a
        // wall*; the pylon slits stay unlit so they hold their colour at size.
        for face in [0, 2, 4] {
            panel.addFacePanel(
                lower: tierOneFoot, upper: tierOneTop, face: face,
                inset: 0.36, from: 0.14, to: 0.78, proud: 0.06
            )
        }
        for face in [1, 3, 5] {
            panel.addFacePanel(
                lower: tierTwoFoot, upper: tierTwoTop, face: face,
                inset: 0.34, from: 0.16, to: 0.80, proud: 0.06
            )
        }
        for face in [0, 3] {
            panel.addFacePanel(
                lower: tierThreeFoot, upper: tierThreeTop, face: face,
                inset: 0.32, from: 0.18, to: 0.76, proud: 0.06
            )
        }

        let core = StructureAssembly.entity(
            named: "core.gravemark",
            zones: [
                StructureZone("apron", rock, StructureMaterial.matte(SunfoldPalette.gravemarkRock, roughness: 0.97, surface: .rimStone)),
                StructureZone("plate", plate, StructureMaterial.matte(SunfoldPalette.gravemarkSurface, roughness: 0.78, surface: .platedSlate)),
                StructureZone("plateup", plateLit, StructureMaterial.matte(
                    StructureMaterial.shade(SunfoldPalette.gravemarkSurface, 1.24),
                    roughness: 0.70,
                    surface: .platedSlate
                )),
                StructureZone("copper", copper, MaterialLibrary.material(.oxidisedCopper)),
                StructureZone("panel", panel, MaterialLibrary.luminousSeam(SunfoldPalette.gravemarkMineral, intensity: 2.1)),
                StructureZone("seam", glow, StructureMaterial.glow(SunfoldPalette.gravemarkMineral, opacity: 0.85)),
            ]
        )
        core.addChild(
            hearthLight(
                named: "core.gravemark.hearth",
                color: StructureMaterial.blend(SunfoldPalette.gravemarkMineral, .white, 0.28),
                intensity: 58_000,
                radius: 13,
                height: 1.4
            )
        )
        return core
    }

    // MARK: - Local light

    /// A shadowless warm/cool pool at a Core's base.
    ///
    /// Intensity is in lumens, so illuminance falls as `intensity / (4π d²)`:
    /// 90 000 lm lands ~450 lux four metres out, which is a seventh of the key
    /// and reads as a pool rather than as a second sun. The entity carries no
    /// `ModelComponent`, so `LightingRigSystem` skips it entirely — it neither
    /// receives the IBL nor rasterises into the shadow map.
    private static func hearthLight(
        named name: String,
        color: UIColor,
        intensity: Float,
        radius: Float,
        height: Float
    ) -> Entity {
        let entity = Entity()
        entity.name = name
        entity.position = [0, height, 0]
        entity.components.set(
            PointLightComponent(
                color: color,
                intensity: intensity,
                attenuationRadius: radius,
                attenuationFalloffExponent: 2.0
            )
        )
        return entity
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
    private var flat: FlatMeshBuilder
    private(set) var triangleCount = 0

    /// Authored structures are boxy — plates, kerbs, decks, hulls — so the
    /// default is dominant-axis box mapping at the project's single texel
    /// density. Every existing `StructureBuilder()` call therefore starts
    /// emitting UVs and a tangent frame with no edit, which is what lets
    /// `MaterialLibrary`'s normal and roughness maps actually land. Pass a
    /// different projection where a part is round or strongly slanted.
    init(uv projection: MeshUVProjection = MaterialLibrary.structureUVProjection) {
        self.flat = FlatMeshBuilder(uv: projection)
    }

    /// See `FlatMeshBuilder.lift`. Set it to sit this builder's output on the
    /// terrain rather than on the datum plane.
    var lift: ((SIMD2<Float>) -> Float)? {
        get { flat.lift }
        set { flat.lift = newValue }
    }

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

    /// A flat horizontal annulus between two concentric rings — the tread of a
    /// plinth step, a walkway deck, the top of a cornice.
    ///
    /// Facing is stated rather than derived from a pivot: a tread is horizontal,
    /// so "away from the interior" is degenerate for it and any pivot-based
    /// reference would be decided by floating-point noise.
    mutating func addTread(
        outer: [SIMD3<Float>],
        inner: [SIMD3<Float>],
        up: Bool = true
    ) {
        guard outer.count == inner.count, outer.count >= 3 else { return }
        let facing = SIMD3<Float>(0, up ? 1 : -1, 0)
        for index in outer.indices {
            let next = (index + 1) % outer.count
            addQuad(outer[index], outer[next], inner[next], inner[index], facing: facing)
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

    /// A canopy petal: a wide root narrowing to a point, with concave sides and
    /// a raised centre fold. Returns the fold's root, so the caller can lay a
    /// batten along the same ridge without re-deriving it.
    ///
    /// This is the shape that makes a tented pavilion read as *fabric over a
    /// frame* rather than as a shell. A dome — however pleated — is one closed
    /// surface, so at any given height every facet takes the key at the same
    /// angle and the whole thing resolves toward one value. A ring of separate
    /// petals does not: each has its own fold catching the light on one side and
    /// turning away on the other, and the gaps between them let the tier behind
    /// show through, which is most of what makes concept 01's Core look open.
    ///
    /// The tip is an **edge**, not a point, and `bulge` pushes the side edges
    /// *outward*. Both were the other way round in CP-07's first two renders and
    /// both were wrong: a petal that converges to a single vertex with concave
    /// sides is a spike, and a ring of spikes reads as a sea urchin rather than
    /// as a roof. Concept 01's panels are blunt-ended and slightly barrelled, and
    /// they are **wider at the root than they are long** — that proportion is
    /// what makes them tile into a canopy instead of bristling out of one.
    @discardableResult
    mutating func addPetal(
        rootLeft: SIMD3<Float>,
        rootRight: SIMD3<Float>,
        tipLeft: SIMD3<Float>,
        tipRight: SIMD3<Float>,
        spine: Float,
        bulge: Float,
        axis: SIMD2<Float> = .zero
    ) -> SIMD3<Float> {
        let up = SIMD3<Float>(0, 1, 0)
        let rootMid = (rootLeft + rootRight) * 0.5
        let tipMid = (tipLeft + tipRight) * 0.5
        let spineRoot = rootMid + up * spine
        let midSpine = (spineRoot + tipMid) * 0.5 + up * spine * 0.42

        let across = StructureGeometry.direction(rootLeft - rootRight, fallback: [1, 0, 0])
        let midLeft = (rootLeft + tipLeft) * 0.5 + across * bulge
        let midRight = (rootRight + tipRight) * 0.5 - across * bulge

        // A petal is only ever seen from above at this camera pitch, so one
        // reference below the axis gives every facet an up-and-outward normal
        // without any per-face reasoning.
        let pivot = SIMD3<Float>(axis.x, min(rootMid.y, tipMid.y) - 3.0, axis.y)
        addQuad(rootLeft, spineRoot, midSpine, midLeft, pivot: pivot)
        addQuad(spineRoot, rootRight, midRight, midSpine, pivot: pivot)
        addQuad(midLeft, midSpine, tipMid, tipLeft, pivot: pivot)
        addQuad(midSpine, midRight, tipRight, tipMid, pivot: pivot)
        return spineRoot
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

    /// A closed horizontal polygon whose radius alternates between `radius` at
    /// even vertices and `radius * valley` at odd ones.
    ///
    /// Stacking these produces a *pleated* surface of the kind fabric makes when
    /// it is stretched over a radial frame: alternating gores lean opposite ways
    /// about their shared meridian, so neighbouring facets take the key light at
    /// visibly different angles. On a smooth dome every facet at one height has
    /// the same normal and the whole shell resolves to a single flat value —
    /// which is exactly the failure this exists to prevent.
    ///
    /// The side count is rounded down to an even number; an odd one would put
    /// two folds or two valleys next to each other and break the alternation.
    static func pleatedRing(
        sides: Int,
        radius: Float,
        valley: Float,
        y: Float,
        phase: Float = 0,
        center: SIMD2<Float> = .zero
    ) -> [SIMD3<Float>] {
        let count = max(sides, 4) / 2 * 2
        let radii = (0..<count).map { $0 % 2 == 0 ? radius : radius * valley }
        return ring(radii: radii, y: y, phase: phase, center: center)
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

    /// A lit structure surface at `color`.
    ///
    /// This used to be a flat tint plus a scalar roughness — the placeholder
    /// look. It now routes through `MaterialLibrary`, so the same call gets base
    /// colour, normal, roughness, AO and (where the surface has it) metallic,
    /// while the rendered hue stays exactly the palette colour asked for.
    ///
    /// The signature is unchanged so every existing call site is untouched.
    /// `surface` is optional because every tint in the project is a `shade` or
    /// `blend` of a locked palette colour, which `MaterialLibrary` can classify;
    /// pass it explicitly where a call site wants a specific surface class
    /// rather than the nearest palette match. `roughness` keeps its meaning as
    /// "how rough, relative to the others" — it now multiplies the recipe's
    /// roughness map instead of replacing it.
    static func matte(
        _ color: UIColor,
        roughness: Float = 0.92,
        surface: MaterialLibrary.Surface? = nil
    ) -> PhysicallyBasedMaterial {
        MaterialLibrary.material(
            surface ?? MaterialLibrary.surface(matching: color),
            tint: color,
            roughness: roughness,
            // Inference must never turn a matte call luminous; emissive is only
            // ever opt-in, through `MaterialLibrary.luminousSeam`.
            emissiveIntensity: 0
        )
    }

    /// Reserved for glow seams, lumen light and drive wash — nothing else.
    ///
    /// An alpha on the tint alone does not make an `UnlitMaterial` translucent —
    /// it renders fully opaque until `blending` is set. Measured in the rendered
    /// build: ground seams asked for 0.34 and came back solid gold. Anything
    /// wanting partial opacity must say so on `blending`.
    ///
    /// Routed through `LuminousMaterial` so a seam is authored at emitter
    /// brightness rather than at paint brightness. The hue is unchanged — only the
    /// level moves — and it is the level that decides whether the post-process
    /// bright pass can tell a glow seam apart from the lit ground behind it.
    ///
    /// `strength` is the one thing a call site must think about when it encodes
    /// meaning in *brightness*. At the default of 1 the lift normalises the
    /// brightest channel to full, which preserves the hue exactly but discards
    /// the input's value: `shade(sunwovenGold, 0.30)` and `sunwovenGold` both
    /// come back as the same colour. That is correct for a seam — a seam is a
    /// source and every source should read as one — but wrong wherever dim
    /// versus bright *is* the information, and there is one such place: an
    /// unwoven causeway must not look like a woven one. Pass `strength: 0,
    /// whiten: 0` there to render the authored colour untouched.
    static func glow(
        _ color: UIColor,
        opacity: CGFloat = 1.0,
        strength: Float = 1.0,
        whiten: Float = LuminousMaterial.defaultWhiten
    ) -> UnlitMaterial {
        LuminousMaterial.unlit(color, strength: strength, whiten: whiten, opacity: opacity)
    }

    /// Mixes two colours. Nothing built from this invents a hue that is not
    /// already in the locked identity — it only sits between two of them.
    nonisolated static func blend(_ from: UIColor, _ to: UIColor, _ amount: CGFloat) -> UIColor {
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
    nonisolated static func shade(_ color: UIColor, _ factor: CGFloat) -> UIColor {
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
