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
/// - **Sunwoven** — a tiered pavilion: stepped stone plinth, a gold colonnade
///   with backlit fabric panels between its piers, an ivory upper drum, a
///   pleated ribbed dome, and a finial spire, flanked by four banner masts. The
///   read is *pavilion*: tall, woven, lit from within.
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
        // The drum wraps, so it gets a cylindrical unwrap rather than box
        // mapping: the weave then runs continuously around it instead of
        // restarting at every facet.
        var drum = StructureBuilder(
            uv: .cylindrical(metersPerTile: MaterialLibrary.metersPerTile, tilesAround: 5.5)
        )
        // The dome is split into two builders on alternating gores. That split
        // is the fix for "the dome is blown to near-pure white with no shading
        // gradient": the two zones differ by ~19% in albedo, and the pleat below
        // gives their facets genuinely different normals, so neighbouring panels
        // can never resolve to one flat white shape.
        let domeUV = MeshUVProjection.spherical(
            tilesAround: 5,
            tilesOver: 1.2,
            center: [0, 8.6, 0]
        )
        var domeLight = StructureBuilder(uv: domeUV)
        var domeDeep = StructureBuilder(uv: domeUV)

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
        let kerbFoot = StructureGeometry.ring(sides: sides, radius: 4.22, y: 0.82, phase: phase)
        let kerbTop = StructureGeometry.ring(sides: sides, radius: 4.06, y: 1.14, phase: phase)
        let kerbTread = StructureGeometry.ring(sides: sides, radius: 3.38, y: 1.14, phase: phase)
        gold.addBand(lower: kerbFoot, upper: kerbTop, pivot: [0, 0.82, 0])
        gold.addTread(outer: kerbTop, inner: kerbTread)

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
        let cornice = StructureGeometry.ring(sides: sides, radius: 3.66, y: 5.18, phase: phase)
        gold.addBand(lower: architraveFoot, upper: architraveTop, pivot: [0, 4.62, 0])
        gold.addTread(outer: architraveTop, inner: cornice)
        // Closed from below as well: the cornice overhangs the colonnade by more
        // than half a metre and, at this camera pitch, its underside is visible
        // on the far side of the building.
        gold.addTread(outer: architraveFoot, inner: colonnadeTop, up: false)

        // MARK: Upper drum
        let upperFoot = StructureGeometry.ring(sides: sides, radius: 3.66, y: 5.18, phase: phase)
        let upperTop = StructureGeometry.ring(sides: sides, radius: 3.44, y: 8.36, phase: phase)
        drum.addSolid(lower: upperFoot, upper: upperTop, capTop: false)
        for index in 0..<sides {
            gold.addRib(
                from: upperFoot[index], to: upperTop[index],
                axis: .zero, halfWidth: 0.13, taper: 0.92, proud: 0.05
            )
        }
        for face in stride(from: 0, to: sides, by: 2) {
            panel.addFacePanel(
                lower: upperFoot, upper: upperTop, face: face,
                inset: 0.30, from: 0.12, to: 0.82, proud: 0.05
            )
        }

        // MARK: Flared eave
        let eaveFoot = StructureGeometry.ring(sides: sides, radius: 3.44, y: 8.36, phase: phase)
        let eaveTop = StructureGeometry.pleatedRing(sides: sides, radius: 3.98, valley: 0.90, y: 8.82, phase: phase)
        gold.addBand(lower: eaveFoot, upper: eaveTop, pivot: [0, 8.20, 0])

        // MARK: Pleated dome
        //
        // Fabric stretched over a frame, not a smooth shell: every odd meridian
        // is pulled in to 90% radius, so the surface alternates between a raised
        // fold and a sunken valley all the way to the crown. That pleat is what
        // gives neighbouring facets different normals — the geometric half of the
        // fix for a dome that used to resolve to one flat white blob.
        let crownY = random.float(in: 12.30...12.60)
        let domeRings = [
            eaveTop,
            StructureGeometry.pleatedRing(sides: sides, radius: 3.68, valley: 0.90, y: 9.96, phase: phase),
            StructureGeometry.pleatedRing(sides: sides, radius: 2.92, valley: 0.91, y: 11.06, phase: phase),
            StructureGeometry.pleatedRing(sides: sides, radius: 1.74, valley: 0.92, y: 11.96, phase: phase),
            StructureGeometry.ring(sides: sides, radius: 0.76, y: crownY, phase: phase),
        ]
        for level in 0..<(domeRings.count - 1) {
            let lower = domeRings[level]
            let upper = domeRings[level + 1]
            let pivot = SIMD3<Float>(0, (lower[0].y + upper[0].y) * 0.5 - 2.6, 0)
            for index in 0..<sides {
                let next = (index + 1) % sides
                // Gore parity picks the zone. Alternating gores therefore differ
                // in albedo as well as in normal.
                if index % 2 == 0 {
                    domeLight.addQuad(lower[index], lower[next], upper[next], upper[index], pivot: pivot)
                } else {
                    domeDeep.addQuad(lower[index], lower[next], upper[next], upper[index], pivot: pivot)
                }
            }
        }
        // Gold ribs capping every raised fold, eave to crown.
        for level in 0..<(domeRings.count - 1) {
            for index in stride(from: 0, to: sides, by: 2) {
                gold.addRib(
                    from: domeRings[level][index], to: domeRings[level + 1][index],
                    axis: .zero, halfWidth: 0.13, taper: 0.78, proud: 0.045
                )
            }
        }
        // The crown is capped. The previous Core left this ring open, and the
        // hole read as a hard-edged black polygonal void at the apex.
        gold.addCap(ring: domeRings[domeRings.count - 1], pivot: [0, crownY - 2, 0])

        // MARK: Finial
        let finialFoot = StructureGeometry.ring(sides: 6, radius: 0.70, y: crownY - 0.06)
        let finialNeck = StructureGeometry.ring(sides: 6, radius: 0.56, y: crownY + 0.86)
        let finialCollar = StructureGeometry.ring(sides: 6, radius: 0.30, y: crownY + 1.28)
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

        // MARK: Banner masts
        //
        // Four, outboard on the second plinth tread. They break the dome's
        // rotational symmetry — which is what stops it reading as a bare
        // hemisphere from directly above — and their pennants are the only
        // moving-looking silhouette on an otherwise rigid building.
        for index in 0..<4 {
            let angle = phase + (Float(index) + 0.5) * .pi / 2
            let base = SIMD2<Float>(cos(angle) * 4.76, sin(angle) * 4.76)
            let topY = random.float(in: 6.35...6.85)

            let poleFoot = StructureGeometry.ring(sides: 4, radius: 0.17, y: 0.54, phase: angle + .pi / 4, center: base)
            let poleTop = StructureGeometry.ring(sides: 4, radius: 0.11, y: topY, phase: angle + .pi / 4, center: base)
            gold.addSolid(lower: poleFoot, upper: poleTop, capTop: false)
            gold.addSpire(base: poleTop, apex: [base.x, topY + 0.62, base.y])

            let radial = StructureGeometry.direction([base.x, 0, base.y])
            let tangent = simd_cross([0, 1, 0], radial)
            let head = SIMD3<Float>(base.x, topY - 0.35, base.y)
            let drop = random.float(in: 2.05...2.55)
            // A crossarm, then a tapering pennant hanging off it.
            gold.addRib(
                from: head + [0, 0.10, 0], to: head + tangent * 1.22 + [0, 0.10, 0],
                axis: .zero, halfWidth: 0.075, taper: 0.7, proud: 0.0
            )
            lantern.addQuad(
                head,
                head + tangent * 1.22,
                head + tangent * 0.94 - [0, drop, 0],
                head - [0, drop * 0.86, 0],
                facing: radial
            )
        }

        let core = StructureAssembly.entity(
            named: "core.sunwoven",
            zones: [
                StructureZone("plinth", stone, plinthMaterial),
                StructureZone("shell", drum, shellMaterial),
                StructureZone("dome", domeLight, domePanelMaterial),
                StructureZone("domefold", domeDeep, domeFoldMaterial),
                StructureZone("gold", gold, MaterialLibrary.material(.goldTrim)),
                StructureZone("panel", panel, MaterialLibrary.luminousSeam(SunfoldPalette.sunwovenTurquoise, intensity: 1.9)),
                StructureZone("lantern", lantern, StructureMaterial.glow(SunfoldPalette.sunwovenTurquoise, opacity: 0.92)),
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
    // Every ivory surface on the Core is pulled well down from the palette's
    // near-white 0.96: at 3200 lux of key plus the IBL, a 0.96 albedo shell
    // clips before the tonemap ever sees it and the dome's form is destroyed.
    // 0.74 keeps every facet inside the shoulder, so the pleat actually shades.

    /// The dome's lit gores. ~0.72 luminance — the value the shell is authored
    /// around, and the reference the fold zone is measured against.
    private static var domePanelMaterial: PhysicallyBasedMaterial {
        StructureMaterial.matte(
            StructureMaterial.shade(SunfoldPalette.sunwovenIvory, 0.75),
            // A multiplier on the recipe's 0.58–0.88 roughness map, so the dome
            // lands near 0.35: a broad specular lobe that sweeps across the
            // facets instead of a matte surface with no highlight at all.
            roughness: 0.45,
            surface: .wovenIvory
        )
    }

    /// The dome's sunken gores, 20% darker than the lit ones. Alternating panels
    /// therefore separate by more than the 15% the frame needs to read the pleat.
    private static var domeFoldMaterial: PhysicallyBasedMaterial {
        StructureMaterial.matte(
            StructureMaterial.shade(SunfoldPalette.sunwovenIvory, 0.60),
            roughness: 0.52,
            surface: .wovenIvory
        )
    }

    /// The vertical drums. A shade brighter than the dome because a vertical
    /// face takes far less of an overhead key — the *rendered* values land
    /// close, which is what keeps the building one material.
    private static var shellMaterial: PhysicallyBasedMaterial {
        StructureMaterial.matte(
            StructureMaterial.shade(SunfoldPalette.sunwovenIvory, 0.82),
            roughness: 0.62,
            surface: .wovenIvory
        )
    }

    /// Fractured pale stone, deliberately darker than the regolith it stands on
    /// so the plinth separates from the ground by value rather than by outline.
    private static var plinthMaterial: PhysicallyBasedMaterial {
        StructureMaterial.matte(
            StructureMaterial.shade(SunfoldPalette.sunwovenSurface, 0.80),
            roughness: 0.95,
            surface: .rimStone
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
