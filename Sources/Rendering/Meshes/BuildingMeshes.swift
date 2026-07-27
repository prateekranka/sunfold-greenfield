import Foundation
import RealityKit
import UIKit
import simd

/// The five buildable structures of the Foundation slice.
///
/// Every pair is authored so the Sunwoven and Gravemark versions separate on
/// **silhouette**, not on tint — the black-and-white thumbnail test:
///
/// | Building | Sunwoven | Gravemark |
/// |---|---|---|
/// | Farm | open bed, crop blades, pennant marker | closed tray, heavy transverse ribs, bollards |
/// | Matter Extractor | airy splayed-leg derrick | squat plated housing with a diagonal drill boom |
/// | Dwelling | conical fabric yurt with a porch | mono-pitch bunker with a vent stack |
/// | Formation Yard | open canopy on four masts | long armoured hall between two gate towers |
/// | Expansion Outpost | standing woven-light ring | tapered anchor pylon with three claws |
///
/// Origins are the footprint centre, bases sit at y = 0, and every asymmetric
/// detail — porch, ramp, gate, drill boom — faces +Z, which is the face the
/// north-up camera looks straight at.
@MainActor
enum BuildingMeshes {

    static func farm(faction: Faction, seed: UInt64) -> Entity {
        switch faction {
        case .sunwoven: sunwovenFarm(seed: seed)
        case .gravemark: gravemarkFarm(seed: seed)
        }
    }

    static func matterExtractor(faction: Faction, seed: UInt64) -> Entity {
        switch faction {
        case .sunwoven: sunwovenExtractor(seed: seed)
        case .gravemark: gravemarkExtractor(seed: seed)
        }
    }

    static func dwelling(faction: Faction, seed: UInt64) -> Entity {
        switch faction {
        case .sunwoven: sunwovenDwelling(seed: seed)
        case .gravemark: gravemarkDwelling(seed: seed)
        }
    }

    static func formationYard(faction: Faction, seed: UInt64) -> Entity {
        switch faction {
        case .sunwoven: sunwovenYard(seed: seed)
        case .gravemark: gravemarkYard(seed: seed)
        }
    }

    static func expansionOutpost(faction: Faction, seed: UInt64) -> Entity {
        switch faction {
        case .sunwoven: sunwovenOutpost(seed: seed)
        case .gravemark: gravemarkOutpost(seed: seed)
        }
    }

    // MARK: - Farm

    /// 7 × 7 m, 1.3 m tall. An open soil bed inside a woven-gold kerb, with
    /// three furrows of saffron crop and a pennant marker at one corner.
    private static func sunwovenFarm(seed: UInt64) -> Entity {
        var random = DeterministicRandom.stream(seed: seed, tag: "farm.sunwoven")

        var gold = StructureBuilder()
        var soil = StructureBuilder()
        var crop = StructureBuilder()
        var glow = StructureBuilder()

        let kerbFoot = StructureGeometry.rectangle(width: 7.0, depth: 7.0, y: 0)
        let kerbTop = StructureGeometry.rectangle(width: 7.0, depth: 7.0, y: 0.55)
        let bedRim = StructureGeometry.rectangle(width: 6.1, depth: 6.1, y: 0.55)
        let bedTop = StructureGeometry.rectangle(width: 6.1, depth: 6.1, y: 0.30)

        gold.addBand(lower: kerbFoot, upper: kerbTop, pivot: [0, 0.28, 0])
        gold.addBand(lower: kerbTop, upper: bedRim, pivot: [0, 0, 0])
        gold.addBand(lower: bedTop, upper: bedRim, pivot: [0, 0.42, 0], outward: false)

        soil.addSolid(
            lower: StructureGeometry.rectangle(width: 6.1, depth: 6.1, y: 0),
            upper: bedTop
        )

        for index in 0..<3 {
            let x = -1.85 + Float(index) * 1.85
            let crest = 0.30 + random.float(in: 0.24...0.34)
            soil.addFin(
                [x - 0.62, 0.30, -2.65],
                [x + 0.62, 0.30, -2.65],
                [x, crest, -2.65],
                extrude: [0, 0, 5.30]
            )

            for step in 0..<5 {
                let z = -2.10 + Float(step) * 1.05 + random.float(in: -0.16...0.16)
                let base = SIMD3<Float>(x + random.float(in: -0.20...0.20), crest - 0.04, z)
                let tip = base + [
                    random.float(in: -0.26...0.26),
                    random.float(in: 0.46...0.70),
                    random.float(in: -0.26...0.26),
                ]
                crop.addBlade(base: base, tip: tip, side: [0.15, 0, 0], lift: 0.10)
            }
        }

        // Pennant marker: the one vertical on an otherwise flat plot, and the
        // cue that separates a Sunwoven farm from bare ground at mid zoom.
        let post = SIMD2<Float>(2.86, 2.86)
        let postFoot = StructureGeometry.ring(sides: 4, radius: 0.11, y: 0.55, phase: .pi / 4, center: post)
        let postTop = StructureGeometry.ring(sides: 4, radius: 0.08, y: 1.08, phase: .pi / 4, center: post)
        gold.addSolid(lower: postFoot, upper: postTop, capTop: false)
        gold.addSpire(base: postTop, apex: [post.x, 1.30, post.y])
        glow.addQuad(
            [post.x, 1.00, post.y],
            [post.x - 0.62, 0.90, post.y],
            [post.x - 0.62, 0.58, post.y],
            [post.x, 0.64, post.y],
            facing: [0, 0, 1]
        )

        return StructureAssembly.entity(
            named: "farm.sunwoven",
            zones: [
                StructureZone("soil", soil, StructureMaterial.matte(StructureMaterial.shade(SunfoldPalette.sunwovenRock, 0.72), roughness: 0.98)),
                StructureZone("kerb", gold, StructureMaterial.matte(SunfoldPalette.sunwovenGold, roughness: 0.88)),
                StructureZone("crop", crop, StructureMaterial.matte(StructureMaterial.shade(SunfoldPalette.sunwovenGold, 1.14), roughness: 0.95)),
                StructureZone("pennant", glow, StructureMaterial.glow(SunfoldPalette.sunwovenTurquoise, opacity: 0.85)),
            ]
        )
    }

    /// 7 × 7 m, 1.3 m tall. A sealed plated grow trough: heavy kerb, transverse
    /// ribs, a copper feed spine, and mineral glow in the trenches.
    private static func gravemarkFarm(seed: UInt64) -> Entity {
        var random = DeterministicRandom.stream(seed: seed, tag: "farm.gravemark")

        var plate = StructureBuilder()
        var rock = StructureBuilder()
        var copper = StructureBuilder()
        var glow = StructureBuilder()

        let kerbFoot = StructureGeometry.rectangle(width: 7.0, depth: 7.0, y: 0)
        let kerbTop = StructureGeometry.rectangle(width: 6.8, depth: 6.8, y: 0.62)
        let trayRim = StructureGeometry.rectangle(width: 5.5, depth: 5.5, y: 0.62)
        let trayFloor = StructureGeometry.rectangle(width: 5.5, depth: 5.5, y: 0.20)

        plate.addBand(lower: kerbFoot, upper: kerbTop, pivot: [0, 0.31, 0])
        plate.addBand(lower: kerbTop, upper: trayRim, pivot: [0, 0, 0])
        plate.addBand(lower: trayFloor, upper: trayRim, pivot: [0, 0.41, 0], outward: false)

        rock.addSolid(
            lower: StructureGeometry.rectangle(width: 5.5, depth: 5.5, y: 0),
            upper: trayFloor
        )

        for index in 0..<3 {
            let z = -1.6 + Float(index) * 1.6
            plate.addSolid(
                lower: StructureGeometry.rectangle(width: 5.4, depth: 0.46, y: 0.20, center: [0, z]),
                upper: StructureGeometry.rectangle(
                    width: 5.1, depth: 0.34,
                    y: random.float(in: 0.50...0.60), center: [0, z]
                )
            )
        }

        copper.addSolid(
            lower: StructureGeometry.rectangle(width: 0.52, depth: 5.6, y: 0.55),
            upper: StructureGeometry.rectangle(width: 0.38, depth: 5.6, y: 0.82)
        )
        copper.addBand(
            lower: StructureGeometry.rectangle(width: 7.06, depth: 7.06, y: 0.22),
            upper: StructureGeometry.rectangle(width: 7.02, depth: 7.02, y: 0.40),
            pivot: [0, 0.31, 0]
        )

        for side in [Float(-1), Float(1)] {
            let base = SIMD2<Float>(side * 2.92, 2.92)
            let foot = StructureGeometry.ring(sides: 4, radius: 0.32, y: 0.62, phase: .pi / 4, center: base)
            let top = StructureGeometry.ring(sides: 4, radius: 0.24, y: 1.04, phase: .pi / 4, center: base)
            rock.addSolid(lower: foot, upper: top, capTop: false)
            copper.addSpire(base: top, apex: [base.x, 1.28, base.y])
        }

        for index in 0..<2 {
            let z = -0.8 + Float(index) * 1.6
            glow.addQuad(
                [-2.5, 0.24, z - 0.42], [2.5, 0.24, z - 0.42],
                [2.5, 0.24, z + 0.42], [-2.5, 0.24, z + 0.42],
                facing: [0, 1, 0]
            )
        }

        return StructureAssembly.entity(
            named: "farm.gravemark",
            zones: [
                StructureZone("tray", rock, StructureMaterial.matte(SunfoldPalette.gravemarkRock, roughness: 0.97)),
                StructureZone("plate", plate, StructureMaterial.matte(SunfoldPalette.gravemarkSurface)),
                StructureZone("copper", copper, StructureMaterial.matte(SunfoldPalette.gravemarkCopper, roughness: 0.85)),
                StructureZone("growth", glow, StructureMaterial.glow(SunfoldPalette.gravemarkMineral, opacity: 0.60)),
            ]
        )
    }

    // MARK: - Matter Extractor

    /// ~5 m wide, ~4.1 m tall. Four splayed lattice legs over a collection
    /// basin, an ivory head with a fabric awning, and a spindle driven into the
    /// ground. Open underneath — you can see the fragment through it.
    private static func sunwovenExtractor(seed: UInt64) -> Entity {
        var random = DeterministicRandom.stream(seed: seed, tag: "extractor.sunwoven")

        var stone = StructureBuilder()
        var gold = StructureBuilder()
        var ivory = StructureBuilder()
        var glow = StructureBuilder()

        stone.addSolid(
            lower: StructureGeometry.ring(sides: 6, radius: 2.40, y: 0),
            upper: StructureGeometry.ring(sides: 6, radius: 2.20, y: 0.42)
        )

        // Splayed legs. Each foot is jittered so the derrick reads as tied down
        // to uneven rock rather than machined onto a pad.
        // Brace points are sampled on the real leg line, not on the footprint
        // circle, so the lattice actually touches the legs at every jitter.
        var braces: [SIMD3<Float>] = []
        for index in 0..<4 {
            let angle = (Float(index) + 0.5) * .pi / 2
            let spread = random.float(in: 1.48...1.68)
            let foot = SIMD2<Float>(cos(angle) * spread, sin(angle) * spread)
            let shoulder = SIMD2<Float>(cos(angle) * 0.44, sin(angle) * 0.44)
            gold.addSolid(
                lower: StructureGeometry.ring(sides: 3, radius: 0.17, y: 0.42, phase: angle, center: foot),
                upper: StructureGeometry.ring(sides: 3, radius: 0.11, y: 3.20, phase: angle, center: shoulder),
                capTop: false
            )

            let low = SIMD3<Float>(foot.x, 0.42, foot.y)
            let high = SIMD3<Float>(shoulder.x, 3.20, shoulder.y)
            braces.append(low + (high - low) * 0.42)
        }

        // Cross bracing at mid height — the lattice read.
        for index in 0..<4 {
            let next = (index + 1) % 4
            let a = braces[index]
            let b = braces[next]
            gold.addQuad(
                a - [0, 0.07, 0], b - [0, 0.07, 0],
                b + [0, 0.07, 0], a + [0, 0.07, 0],
                facing: StructureGeometry.direction([(a.x + b.x) * 0.5, 0, (a.z + b.z) * 0.5])
            )
        }

        // Spindle: a column into the basin, tapering to a point below the rim.
        let spindleTop = StructureGeometry.ring(sides: 4, radius: 0.21, y: 3.20, phase: .pi / 4)
        let spindleFoot = StructureGeometry.ring(sides: 4, radius: 0.27, y: 0.62, phase: .pi / 4)
        gold.addSolid(lower: spindleFoot, upper: spindleTop, capTop: false)
        gold.addFan(ring: spindleFoot, apex: [0, 0.08, 0], pivot: [0, 1.0, 0])

        // Head housing and awning.
        ivory.addSolid(
            lower: StructureGeometry.ring(sides: 4, radius: 0.94, y: 3.20, phase: .pi / 4),
            upper: StructureGeometry.ring(sides: 4, radius: 0.72, y: 4.05, phase: .pi / 4)
        )
        let awningPost = SIMD2<Float>(0, 2.05)
        ivory.addSolid(
            lower: StructureGeometry.ring(sides: 3, radius: 0.10, y: 0.42, center: awningPost),
            upper: StructureGeometry.ring(sides: 3, radius: 0.08, y: 2.30, center: awningPost),
            capTop: false
        )
        ivory.addQuad(
            [-0.80, 3.30, 0.55], [0.80, 3.30, 0.55],
            [0.72, 2.32, 2.20], [-0.72, 2.32, 2.20],
            facing: [0, 0.9, 0.4]
        )

        glow.addBand(
            lower: StructureGeometry.ring(sides: 4, radius: 1.00, y: 3.34, phase: .pi / 4),
            upper: StructureGeometry.ring(sides: 4, radius: 1.00, y: 3.62, phase: .pi / 4),
            pivot: [0, 3.48, 0]
        )
        glow.addQuad(
            [-0.55, 0.46, -0.55], [0.55, 0.46, -0.55],
            [0.55, 0.46, 0.55], [-0.55, 0.46, 0.55],
            facing: [0, 1, 0]
        )

        return StructureAssembly.entity(
            named: "extractor.sunwoven",
            zones: [
                StructureZone("basin", stone, StructureMaterial.matte(SunfoldPalette.sunwovenSurface)),
                StructureZone("lattice", gold, StructureMaterial.matte(SunfoldPalette.sunwovenGold, roughness: 0.86)),
                StructureZone("shell", ivory, StructureMaterial.matte(SunfoldPalette.sunwovenIvory, roughness: 0.88)),
                StructureZone("seam", glow, StructureMaterial.glow(SunfoldPalette.sunwovenTurquoise, opacity: 0.80)),
            ]
        )
    }

    /// ~5 m wide, ~4.3 m tall. A battered plated housing with a shoulder cowl,
    /// a diagonal drill boom driven into the ground ahead of it, an ore hopper
    /// on one flank, and twin exhaust stacks. Dense where the Sunwoven rig is open.
    private static func gravemarkExtractor(seed: UInt64) -> Entity {
        var random = DeterministicRandom.stream(seed: seed, tag: "extractor.gravemark")

        var rock = StructureBuilder()
        var plate = StructureBuilder()
        var copper = StructureBuilder()
        var glow = StructureBuilder()

        rock.addSolid(
            lower: StructureGeometry.ring(sides: 6, radius: 2.50, y: 0),
            upper: StructureGeometry.ring(sides: 6, radius: 2.30, y: 0.50)
        )

        let housingFoot = StructureGeometry.rectangle(width: 3.50, depth: 2.90, y: 0.50, center: [-0.20, 0])
        let housingTop = StructureGeometry.rectangle(width: 2.85, depth: 2.35, y: 2.60, center: [-0.20, 0])
        plate.addSolid(lower: housingFoot, upper: housingTop, capTop: false)
        plate.addSolid(
            lower: StructureGeometry.rectangle(width: 2.95, depth: 2.45, y: 2.60, center: [-0.20, 0]),
            upper: StructureGeometry.rectangle(
                width: 1.70, depth: 1.45,
                y: random.float(in: 3.35...3.55), center: [-0.20, -0.38]
            )
        )

        // Inverted-taper ore hopper: wide mouth, narrow throat.
        rock.addSolid(
            lower: StructureGeometry.rectangle(width: 1.45, depth: 1.25, y: 0.50, center: [1.75, 0.10]),
            upper: StructureGeometry.rectangle(width: 2.00, depth: 1.70, y: 1.95, center: [1.75, 0.10])
        )

        // Drill boom, angled forward and down out of the cowl.
        copper.addSolid(
            lower: StructureGeometry.rectangle(width: 0.78, depth: 0.78, y: 3.05, center: [-0.20, 0.55]),
            upper: StructureGeometry.rectangle(width: 0.46, depth: 0.46, y: 1.10, center: [-0.20, 2.30]),
            capTop: false
        )
        copper.addFan(
            ring: StructureGeometry.rectangle(width: 0.46, depth: 0.46, y: 1.10, center: [-0.20, 2.30]),
            apex: [-0.20, 0.20, 2.72],
            pivot: [-0.20, 1.30, 2.10]
        )
        copper.addBand(
            lower: StructureGeometry.rectangle(width: 3.30, depth: 2.72, y: 1.50, center: [-0.20, 0]),
            upper: StructureGeometry.rectangle(width: 3.22, depth: 2.64, y: 1.82, center: [-0.20, 0]),
            pivot: [-0.20, 1.66, 0]
        )

        for side in [Float(-1), Float(1)] {
            let stack = SIMD2<Float>(-0.20 + side * 0.52, -0.60)
            copper.addSolid(
                lower: StructureGeometry.ring(sides: 4, radius: 0.22, y: 3.40, phase: .pi / 4, center: stack),
                upper: StructureGeometry.ring(
                    sides: 4, radius: 0.17,
                    y: random.float(in: 4.10...4.35), phase: .pi / 4, center: stack
                ),
                capTop: false
            )
        }

        for face in [0, 2] {
            glow.addFacePanel(
                lower: housingFoot, upper: housingTop, face: face,
                inset: 0.34, from: 0.24, to: 0.72, proud: 0.06,
                axis: [-0.20, 0]
            )
        }
        glow.addQuad(
            [-0.62, 0.24, 2.32], [0.22, 0.24, 2.32],
            [0.22, 0.24, 2.96], [-0.62, 0.24, 2.96],
            facing: [0, 1, 0]
        )

        return StructureAssembly.entity(
            named: "extractor.gravemark",
            zones: [
                StructureZone("plinth", rock, StructureMaterial.matte(SunfoldPalette.gravemarkRock, roughness: 0.97)),
                StructureZone("plate", plate, StructureMaterial.matte(SunfoldPalette.gravemarkSurface)),
                StructureZone("copper", copper, StructureMaterial.matte(SunfoldPalette.gravemarkCopper, roughness: 0.85)),
                StructureZone("seam", glow, StructureMaterial.glow(SunfoldPalette.gravemarkMineral, opacity: 0.85)),
            ]
        )
    }

    // MARK: - Dwelling

    /// ~5 m wide, ~4.6 m tall. A heptagonal fabric yurt: low ivory wall, gold
    /// hoop, bell-curved roof with ribbed folds, and a two-post porch on +Z.
    private static func sunwovenDwelling(seed: UInt64) -> Entity {
        var random = DeterministicRandom.stream(seed: seed, tag: "dwelling.sunwoven")

        var stone = StructureBuilder()
        var ivory = StructureBuilder()
        var gold = StructureBuilder()
        var glow = StructureBuilder()

        let sides = 7
        let phase = Float.pi / Float(sides) * 0.5

        stone.addSolid(
            lower: StructureGeometry.ring(sides: sides, radius: 2.46, y: 0, phase: phase),
            upper: StructureGeometry.ring(sides: sides, radius: 2.34, y: 0.22, phase: phase),
            capTop: false
        )

        let wallFoot = StructureGeometry.ring(sides: sides, radius: 2.30, y: 0.22, phase: phase)
        let wallTop = StructureGeometry.ring(sides: sides, radius: 2.26, y: 1.42, phase: phase)
        ivory.addSolid(lower: wallFoot, upper: wallTop, capTop: false)

        gold.addBand(
            lower: StructureGeometry.ring(sides: sides, radius: 2.36, y: 1.18, phase: phase),
            upper: StructureGeometry.ring(sides: sides, radius: 2.36, y: 1.44, phase: phase),
            pivot: [0, 1.31, 0]
        )

        // Bell roof: overhanging eaves, a slack mid ring, then the peak.
        let eaves = StructureGeometry.ring(sides: sides, radius: 2.74, y: 1.58, phase: phase)
        let slack = StructureGeometry.ring(sides: sides, radius: 1.52, y: random.float(in: 2.95...3.15), phase: phase)
        let peak = SIMD3<Float>(0, random.float(in: 4.00...4.22), 0)
        ivory.addBand(lower: wallTop, upper: eaves, pivot: [0, 1.44, 0])
        ivory.addBand(lower: eaves, upper: slack, pivot: [0, 2.20, 0])
        ivory.addFan(ring: slack, apex: peak, pivot: [0, 2.60, 0])

        for index in 0..<sides {
            gold.addRib(from: eaves[index], to: slack[index], axis: .zero, halfWidth: 0.09, taper: 0.6, proud: 0.05)
        }
        gold.addSpire(
            base: StructureGeometry.ring(sides: 4, radius: 0.18, y: peak.y - 0.10, phase: .pi / 4),
            apex: [0, peak.y + 0.42, 0]
        )

        // Porch: an awning slung from the wall onto two slim posts.
        for side in [Float(-1), Float(1)] {
            let post = SIMD2<Float>(side * 0.78, 3.05)
            gold.addSolid(
                lower: StructureGeometry.ring(sides: 3, radius: 0.09, y: 0.22, center: post),
                upper: StructureGeometry.ring(sides: 3, radius: 0.07, y: 1.78, center: post),
                capTop: false
            )
        }
        ivory.addQuad(
            [-0.92, 2.10, 1.95], [0.92, 2.10, 1.95],
            [0.86, 1.80, 3.18], [-0.86, 1.80, 3.18],
            facing: [0, 0.92, 0.35]
        )

        glow.addQuad(
            [-0.42, 0.28, 2.28], [0.42, 0.28, 2.28],
            [0.42, 1.24, 2.28], [-0.42, 1.24, 2.28],
            facing: [0, 0, 1]
        )

        return StructureAssembly.entity(
            named: "dwelling.sunwoven",
            zones: [
                StructureZone("footing", stone, StructureMaterial.matte(SunfoldPalette.sunwovenSurface)),
                StructureZone("shell", ivory, StructureMaterial.matte(SunfoldPalette.sunwovenIvory, roughness: 0.88)),
                StructureZone("gold", gold, StructureMaterial.matte(SunfoldPalette.sunwovenGold, roughness: 0.86)),
                StructureZone("door", glow, StructureMaterial.glow(SunfoldPalette.sunwovenTurquoise, opacity: 0.72)),
            ]
        )
    }

    /// ~5 m wide, ~4.6 m tall. A mono-pitch bunker hab: battered slab body,
    /// a sloped armoured roof with a parapet lip, flank buttresses, and a
    /// copper vent stack under a flared cowl.
    private static func gravemarkDwelling(seed: UInt64) -> Entity {
        var random = DeterministicRandom.stream(seed: seed, tag: "dwelling.gravemark")

        var rock = StructureBuilder()
        var plate = StructureBuilder()
        var copper = StructureBuilder()
        var glow = StructureBuilder()

        rock.addSolid(
            lower: StructureGeometry.rectangle(width: 4.70, depth: 4.30, y: 0),
            upper: StructureGeometry.rectangle(width: 4.50, depth: 4.10, y: 0.30),
            capTop: false
        )

        let bodyFoot = StructureGeometry.rectangle(width: 4.05, depth: 3.65, y: 0.30)
        let bodyTop = StructureGeometry.rectangle(width: 3.55, depth: 3.15, y: 2.40)
        plate.addSolid(lower: bodyFoot, upper: bodyTop, capTop: false)

        // Mono-pitch roof: the upper face is both narrower and shifted, so the
        // slab leans. A symmetric taper would read as a hip roof instead.
        let roofFoot = StructureGeometry.rectangle(width: 3.78, depth: 3.38, y: 2.40)
        let roofTop = StructureGeometry.rectangle(
            width: 2.10, depth: 3.30,
            y: random.float(in: 3.48...3.68), center: [0.78, 0]
        )
        plate.addSolid(lower: roofFoot, upper: roofTop)
        rock.addBand(
            lower: StructureGeometry.rectangle(width: 3.90, depth: 3.50, y: 2.28),
            upper: StructureGeometry.rectangle(width: 3.84, depth: 3.44, y: 2.52),
            pivot: [0, 2.40, 0]
        )

        for side in [Float(-1), Float(1)] {
            rock.addFin(
                [side * 1.82, 0.30, -1.35],
                [side * 1.82, 0.30, -0.25],
                [side * 1.82, 2.10, -1.35],
                extrude: [side * 0.42, 0, 0]
            )
        }

        let stack = SIMD2<Float>(-0.92, -0.85)
        copper.addSolid(
            lower: StructureGeometry.ring(sides: 4, radius: 0.38, y: 3.10, phase: .pi / 4, center: stack),
            upper: StructureGeometry.ring(sides: 4, radius: 0.30, y: 4.28, phase: .pi / 4, center: stack),
            capTop: false
        )
        copper.addSolid(
            lower: StructureGeometry.ring(sides: 4, radius: 0.30, y: 4.28, phase: .pi / 4, center: stack),
            upper: StructureGeometry.ring(sides: 4, radius: 0.56, y: 4.52, phase: .pi / 4, center: stack)
        )

        // Copper door surround on +Z, framed as four flat jambs.
        let frame: [(SIMD3<Float>, SIMD3<Float>)] = [
            ([-0.78, 0.30, 1.86], [-0.54, 1.98, 1.86]),
            ([0.54, 0.30, 1.86], [0.78, 1.98, 1.86]),
            ([-0.78, 1.80, 1.86], [0.78, 1.98, 1.86]),
            ([-0.78, 0.30, 1.86], [0.78, 0.44, 1.86]),
        ]
        for (low, high) in frame {
            copper.addQuad(
                low, [high.x, low.y, low.z],
                high, [low.x, high.y, high.z],
                facing: [0, 0, 1]
            )
        }

        glow.addQuad(
            [-0.54, 0.44, 1.84], [0.54, 0.44, 1.84],
            [0.54, 1.80, 1.84], [-0.54, 1.80, 1.84],
            facing: [0, 0, 1]
        )
        for face in [1, 3] {
            glow.addFacePanel(
                lower: bodyFoot, upper: bodyTop, face: face,
                inset: 0.36, from: 0.52, to: 0.78, proud: 0.05
            )
        }

        return StructureAssembly.entity(
            named: "dwelling.gravemark",
            zones: [
                StructureZone("pad", rock, StructureMaterial.matte(SunfoldPalette.gravemarkRock, roughness: 0.97)),
                StructureZone("plate", plate, StructureMaterial.matte(SunfoldPalette.gravemarkSurface)),
                StructureZone("copper", copper, StructureMaterial.matte(SunfoldPalette.gravemarkCopper, roughness: 0.85)),
                StructureZone("seam", glow, StructureMaterial.glow(SunfoldPalette.gravemarkMineral, opacity: 0.78)),
            ]
        )
    }

    // MARK: - Formation Yard

    /// ~8 m wide, ~5.1 m tall. An open muster pavilion: a broad hipped canopy
    /// on four splayed masts over a raised deck, pennants at the mast heads and
    /// a weapon rack under the eaves. Its defining trait is being *see-through*.
    private static func sunwovenYard(seed: UInt64) -> Entity {
        var random = DeterministicRandom.stream(seed: seed, tag: "yard.sunwoven")

        var stone = StructureBuilder()
        var gold = StructureBuilder()
        var ivory = StructureBuilder()
        var glow = StructureBuilder()

        let sides = 8
        let phase = Float.pi / Float(sides)

        let deckFoot = StructureGeometry.ring(sides: sides, radius: 4.00, y: 0, phase: phase)
        let deckTop = StructureGeometry.ring(sides: sides, radius: 3.82, y: 0.35, phase: phase)
        stone.addSolid(lower: deckFoot, upper: deckTop)

        for index in 0..<4 {
            let angle = (Float(index) + 0.5) * .pi / 2
            let foot = SIMD2<Float>(cos(angle) * 2.80, sin(angle) * 2.80)
            let head = SIMD2<Float>(cos(angle) * 3.16, sin(angle) * 3.16)
            let headY = random.float(in: 3.30...3.46)
            gold.addSolid(
                lower: StructureGeometry.ring(sides: 4, radius: 0.26, y: 0.35, phase: angle, center: foot),
                upper: StructureGeometry.ring(sides: 4, radius: 0.17, y: headY, phase: angle, center: head),
                capTop: false
            )

            let radial = StructureGeometry.direction([head.x, 0, head.y])
            let tangent = simd_cross([0, 1, 0], radial)
            let anchor = SIMD3<Float>(head.x, headY - 0.05, head.y)
            glow.addQuad(
                anchor,
                anchor + tangent * 0.66 - [0, 0.18, 0],
                anchor + tangent * 0.66 - [0, 0.72, 0],
                anchor - [0, 0.60, 0],
                facing: radial
            )
        }

        // Hipped canopy with a deep brim.
        let brim = StructureGeometry.ring(sides: sides, radius: 3.95, y: 3.16, phase: phase)
        let eaves = StructureGeometry.ring(sides: sides, radius: 4.62, y: 3.42, phase: phase)
        let crown = StructureGeometry.ring(sides: sides, radius: 1.60, y: 4.44, phase: phase)
        ivory.addBand(lower: brim, upper: eaves, pivot: [0, 3.28, 0])
        ivory.addBand(lower: eaves, upper: crown, pivot: [0, 3.90, 0])
        ivory.addFan(ring: crown, apex: [0, random.float(in: 4.95...5.12), 0], pivot: [0, 4.20, 0])

        for index in 0..<sides {
            gold.addRib(from: eaves[index], to: crown[index], axis: .zero, halfWidth: 0.10, taper: 0.55, proud: 0.05)
        }

        // Weapon rack under the eaves — the cue that this yard makes soldiers.
        gold.addSolid(
            lower: StructureGeometry.rectangle(width: 0.24, depth: 3.20, y: 0.86, center: [-2.05, 0]),
            upper: StructureGeometry.rectangle(width: 0.18, depth: 3.14, y: 1.12, center: [-2.05, 0])
        )
        for side in [Float(-1), Float(1)] {
            gold.addSolid(
                lower: StructureGeometry.ring(sides: 3, radius: 0.10, y: 0.35, center: [-2.05, side * 1.42]),
                upper: StructureGeometry.ring(sides: 3, radius: 0.08, y: 0.92, center: [-2.05, side * 1.42]),
                capTop: false
            )
        }
        for index in 0..<3 {
            let z = -1.05 + Float(index) * 1.05
            gold.addBlade(
                base: [-2.05, 1.06, z],
                tip: [-2.05 + random.float(in: -0.24...0.24), 2.20, z + random.float(in: -0.18...0.18)],
                side: [0, 0, 0.11],
                lift: 0.08
            )
        }

        return StructureAssembly.entity(
            named: "yard.sunwoven",
            zones: [
                StructureZone("deck", stone, StructureMaterial.matte(SunfoldPalette.sunwovenSurface)),
                StructureZone("canopy", ivory, StructureMaterial.matte(SunfoldPalette.sunwovenIvory, roughness: 0.88)),
                StructureZone("gold", gold, StructureMaterial.matte(SunfoldPalette.sunwovenGold, roughness: 0.86)),
                StructureZone("pennant", glow, StructureMaterial.glow(SunfoldPalette.sunwovenTurquoise, opacity: 0.88)),
            ]
        )
    }

    /// ~8 m wide, ~5.1 m tall. A long armoured hall clamped between two square
    /// gate towers, with a ridged roof, wall buttresses, a copper gate surround
    /// and ridge vents. Closed and territorial where the Sunwoven yard is open.
    private static func gravemarkYard(seed: UInt64) -> Entity {
        var random = DeterministicRandom.stream(seed: seed, tag: "yard.gravemark")

        var rock = StructureBuilder()
        var plate = StructureBuilder()
        var copper = StructureBuilder()
        var glow = StructureBuilder()

        rock.addSolid(
            lower: StructureGeometry.rectangle(width: 8.00, depth: 6.00, y: 0),
            upper: StructureGeometry.rectangle(width: 7.80, depth: 5.80, y: 0.40),
            capTop: false
        )

        let hallFoot = StructureGeometry.rectangle(width: 6.60, depth: 4.90, y: 0.40)
        let hallTop = StructureGeometry.rectangle(width: 6.25, depth: 4.55, y: 2.75)
        plate.addSolid(lower: hallFoot, upper: hallTop, capTop: false)
        plate.addSolid(
            lower: StructureGeometry.rectangle(width: 6.45, depth: 4.78, y: 2.75),
            upper: StructureGeometry.rectangle(width: 6.05, depth: 1.10, y: random.float(in: 4.05...4.25))
        )

        for side in [Float(-1), Float(1)] {
            let tower = SIMD2<Float>(side * 3.30, 0)
            plate.addSolid(
                lower: StructureGeometry.rectangle(width: 1.85, depth: 1.85, y: 0.40, center: tower),
                upper: StructureGeometry.rectangle(width: 1.60, depth: 1.60, y: 4.05, center: tower),
                capTop: false
            )
            plate.addSolid(
                lower: StructureGeometry.rectangle(width: 1.96, depth: 1.96, y: 4.05, center: tower),
                upper: StructureGeometry.rectangle(
                    width: 1.74, depth: 1.74,
                    y: random.float(in: 4.85...5.05), center: tower
                )
            )
        }

        for index in 0..<4 {
            let x = -2.10 + Float(index) * 1.40
            rock.addFin(
                [x - 0.30, 0.40, 2.32],
                [x + 0.30, 0.40, 2.32],
                [x, 2.05, 2.32],
                extrude: [0, 0, 0.36]
            )
        }

        copper.addBand(
            lower: StructureGeometry.rectangle(width: 6.72, depth: 5.02, y: 2.42, center: [0, 0]),
            upper: StructureGeometry.rectangle(width: 6.64, depth: 4.94, y: 2.76, center: [0, 0]),
            pivot: [0, 2.59, 0]
        )
        let gate: [(SIMD3<Float>, SIMD3<Float>)] = [
            ([-1.32, 0.40, 2.50], [-1.00, 2.44, 2.50]),
            ([1.00, 0.40, 2.50], [1.32, 2.44, 2.50]),
            ([-1.32, 2.22, 2.50], [1.32, 2.44, 2.50]),
            ([-1.32, 0.40, 2.50], [1.32, 0.56, 2.50]),
        ]
        for (low, high) in gate {
            copper.addQuad(
                low, [high.x, low.y, low.z],
                high, [low.x, high.y, high.z],
                facing: [0, 0, 1]
            )
        }
        for index in 0..<3 {
            let x = -1.90 + Float(index) * 1.90
            copper.addSpire(
                base: StructureGeometry.rectangle(width: 0.44, depth: 0.44, y: 4.10, center: [x, 0]),
                apex: [x, 4.66, 0]
            )
        }

        glow.addQuad(
            [-1.00, 0.56, 2.48], [1.00, 0.56, 2.48],
            [1.00, 2.22, 2.48], [-1.00, 2.22, 2.48],
            facing: [0, 0, 1]
        )
        for face in [1, 3] {
            glow.addFacePanel(
                lower: hallFoot, upper: hallTop, face: face,
                inset: 0.30, from: 0.60, to: 0.80, proud: 0.05
            )
        }
        for side in [Float(-1), Float(1)] {
            glow.addQuad(
                [side * 3.30 - 0.34, 3.30, 0.94], [side * 3.30 + 0.34, 3.30, 0.94],
                [side * 3.30 + 0.34, 3.78, 0.94], [side * 3.30 - 0.34, 3.78, 0.94],
                facing: [0, 0, 1]
            )
        }

        return StructureAssembly.entity(
            named: "yard.gravemark",
            zones: [
                StructureZone("base", rock, StructureMaterial.matte(SunfoldPalette.gravemarkRock, roughness: 0.97)),
                StructureZone("plate", plate, StructureMaterial.matte(SunfoldPalette.gravemarkSurface)),
                StructureZone("copper", copper, StructureMaterial.matte(SunfoldPalette.gravemarkCopper, roughness: 0.85)),
                StructureZone("seam", glow, StructureMaterial.glow(SunfoldPalette.gravemarkMineral, opacity: 0.85)),
            ]
        )
    }

    // MARK: - Expansion Outpost

    /// ~6 m wide, ~5.1 m tall. A standing woven-light ring carried on two
    /// pylons, with a suspended lumen mote at its centre. This is the building
    /// that weaves a causeway, so the silhouette is literally a gateway — and it
    /// is the one shape nothing else on the map shares.
    private static func sunwovenOutpost(seed: UInt64) -> Entity {
        var random = DeterministicRandom.stream(seed: seed, tag: "outpost.sunwoven")

        var stone = StructureBuilder()
        var gold = StructureBuilder()
        var ivory = StructureBuilder()
        var glow = StructureBuilder()

        stone.addSolid(
            lower: StructureGeometry.ring(sides: 6, radius: 2.85, y: 0, phase: .pi / 6),
            upper: StructureGeometry.ring(sides: 6, radius: 2.65, y: 0.45, phase: .pi / 6)
        )

        for side in [Float(-1), Float(1)] {
            let foot = SIMD2<Float>(side * 1.42, 0)
            let head = SIMD2<Float>(side * 1.06, 0)
            gold.addSolid(
                lower: StructureGeometry.ring(sides: 4, radius: 0.34, y: 0.45, phase: .pi / 4, center: foot),
                upper: StructureGeometry.ring(sides: 4, radius: 0.23, y: 2.40, phase: .pi / 4, center: head),
                capTop: false
            )
            ivory.addBand(
                lower: StructureGeometry.ring(sides: 4, radius: 0.42, y: 1.16, phase: .pi / 4, center: [side * 1.28, 0]),
                upper: StructureGeometry.ring(sides: 4, radius: 0.42, y: 1.50, phase: .pi / 4, center: [side * 1.28, 0]),
                pivot: [side * 1.28, 1.33, 0]
            )

            // Stay lines from the plinth rim up to the pylon shoulder.
            for depth in [Float(-1), Float(1)] {
                gold.addQuad(
                    [side * 2.42, 0.47, depth * 0.30],
                    [side * 2.42, 0.47, depth * 0.10],
                    [side * 1.12, 2.20, depth * 0.10],
                    [side * 1.12, 2.20, depth * 0.30],
                    facing: [0, 0.4, depth]
                )
            }
        }

        let ringCenterY = random.float(in: 3.28...3.42)
        gold.addStandingRing(
            center: [0, ringCenterY, 0],
            outerRadius: 1.72,
            innerRadius: 1.28,
            halfThickness: 0.17,
            segments: 8
        )

        glow.addShard(
            ring: StructureGeometry.ring(sides: 4, radius: 0.34, y: ringCenterY, phase: .pi / 4),
            top: [0, ringCenterY + 0.52, 0],
            bottom: [0, ringCenterY - 0.52, 0]
        )
        glow.addCap(
            ring: StructureGeometry.ring(sides: 6, radius: 1.92, y: 0.47, phase: .pi / 6),
            pivot: [0, 0.20, 0]
        )

        return StructureAssembly.entity(
            named: "outpost.sunwoven",
            zones: [
                StructureZone("plinth", stone, StructureMaterial.matte(SunfoldPalette.sunwovenSurface)),
                StructureZone("loom", gold, StructureMaterial.matte(SunfoldPalette.sunwovenGold, roughness: 0.86)),
                StructureZone("collar", ivory, StructureMaterial.matte(SunfoldPalette.sunwovenIvory, roughness: 0.88)),
                StructureZone("mote", glow, StructureMaterial.glow(SunfoldPalette.sunwovenGold, opacity: 0.80)),
            ]
        )
    }

    /// ~6 m wide, ~5.1 m tall. A gravity-anchor pylon: a battered hexagonal
    /// mast on three buttresses, a copper collar, three claw arms reaching up
    /// and out, and a mineral spike hanging under the crown.
    private static func gravemarkOutpost(seed: UInt64) -> Entity {
        var random = DeterministicRandom.stream(seed: seed, tag: "outpost.gravemark")

        var rock = StructureBuilder()
        var plate = StructureBuilder()
        var copper = StructureBuilder()
        var glow = StructureBuilder()

        rock.addSolid(
            lower: StructureGeometry.ring(sides: 6, radius: 2.95, y: 0),
            upper: StructureGeometry.ring(sides: 6, radius: 2.75, y: 0.50)
        )

        let mastFoot = StructureGeometry.ring(sides: 6, radius: 1.28, y: 0.50)
        let mastTop = StructureGeometry.ring(sides: 6, radius: 0.80, y: 3.40)
        plate.addSolid(lower: mastFoot, upper: mastTop, capTop: false)
        plate.addSolid(
            lower: StructureGeometry.ring(sides: 6, radius: 0.96, y: 3.40),
            upper: StructureGeometry.ring(sides: 6, radius: 0.58, y: random.float(in: 4.10...4.28))
        )

        for index in 0..<3 {
            let angle = Float(index) / 3 * 2 * .pi + .pi / 6
            let radial = SIMD3<Float>(cos(angle), 0, sin(angle))
            let tangent = simd_cross([0, 1, 0], radial)
            rock.addFin(
                radial * 1.10 + [0, 0.50, 0] - tangent * 0.22,
                radial * 2.60 + [0, 0.50, 0] - tangent * 0.22,
                radial * 1.10 + [0, 2.55, 0] - tangent * 0.22,
                extrude: tangent * 0.44
            )
        }

        copper.addBand(
            lower: StructureGeometry.ring(sides: 6, radius: 1.12, y: 2.86),
            upper: StructureGeometry.ring(sides: 6, radius: 1.12, y: 3.28),
            pivot: [0, 3.07, 0]
        )

        for index in 0..<3 {
            let angle = Float(index) / 3 * 2 * .pi
            let inner = SIMD2<Float>(cos(angle) * 0.78, sin(angle) * 0.78)
            let outer = SIMD2<Float>(cos(angle) * 2.05, sin(angle) * 2.05)
            let reach = random.float(in: 4.60...4.80)
            copper.addSolid(
                lower: StructureGeometry.ring(sides: 4, radius: 0.30, y: 3.85, phase: angle, center: inner),
                upper: StructureGeometry.ring(sides: 4, radius: 0.19, y: reach, phase: angle, center: outer),
                capTop: false
            )
            copper.addSpire(
                base: StructureGeometry.ring(sides: 4, radius: 0.19, y: reach, phase: angle, center: outer),
                apex: [cos(angle) * 2.55, reach + 0.35, sin(angle) * 2.55]
            )
        }

        // The anchor spike: a mineral point hanging under the crown, which is
        // what makes the pylon read as pulling on the void beneath the fragment.
        glow.addFan(
            ring: StructureGeometry.ring(sides: 4, radius: 0.46, y: 3.52, phase: .pi / 4),
            apex: [0, 2.05, 0],
            pivot: [0, 3.10, 0]
        )
        glow.addSpire(
            base: StructureGeometry.ring(sides: 4, radius: 0.30, y: 4.16, phase: .pi / 4),
            apex: [0, 5.05, 0]
        )
        for face in [0, 2, 4] {
            glow.addFacePanel(
                lower: mastFoot, upper: mastTop, face: face,
                inset: 0.38, from: 0.24, to: 0.66, proud: 0.06
            )
        }

        return StructureAssembly.entity(
            named: "outpost.gravemark",
            zones: [
                StructureZone("plinth", rock, StructureMaterial.matte(SunfoldPalette.gravemarkRock, roughness: 0.97)),
                StructureZone("plate", plate, StructureMaterial.matte(SunfoldPalette.gravemarkSurface)),
                StructureZone("copper", copper, StructureMaterial.matte(SunfoldPalette.gravemarkCopper, roughness: 0.85)),
                StructureZone("anchor", glow, StructureMaterial.glow(SunfoldPalette.gravemarkMineral, opacity: 0.85)),
            ]
        )
    }
}
