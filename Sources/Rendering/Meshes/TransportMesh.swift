import Foundation
import RealityKit
import UIKit
import simd

/// The light transport: ~11 m long, ~4 m in the beam, ~2.5 m tall, with its
/// unload ramp deployed.
///
/// Both hulls are lofted through cross-sections along the keel line rather than
/// assembled from blocks, which is what gives a craft a hull instead of a box.
/// The two profiles are what separate them at a glance:
///
/// - **Sunwoven** — a six-point chine section drawn to a fine point at the bow,
///   with a cambered deck, swept outrigger fins and a side ramp. It reads as a
///   *skiff*: fast, tapered, light on the void.
/// - **Gravemark** — an eight-point chamfered-slab section, blunt at both ends,
///   with flank sponsons, a stern bridge block and a broad bow ramp that drops
///   straight ahead. It reads as a *barge*: square, laden, deliberate.
///
/// The hull's lowest point sits at y = 0 and the origin is amidships, so the
/// dock point on a fragment rim positions the craft directly.
@MainActor
enum TransportMesh {

    static func lightTransport(faction: Faction, seed: UInt64) -> Entity {
        switch faction {
        case .sunwoven: sunwoven(seed: seed)
        case .gravemark: gravemark(seed: seed)
        }
    }

    /// One hull cross-section. `taper` shrinks the whole section toward the ends,
    /// which produces sheer and tumblehome from a single profile.
    private static func section(
        profile: [SIMD2<Float>],
        z: Float,
        taper: Float,
        beam: Float,
        rise: Float,
        lift: Float
    ) -> [SIMD3<Float>] {
        profile.map { point in
            SIMD3<Float>(point.x * beam * taper, point.y * rise * taper + lift, z)
        }
    }

    // MARK: - Sunwoven

    private static func sunwoven(seed: UInt64) -> Entity {
        var random = DeterministicRandom.stream(seed: seed, tag: "transport.sunwoven")

        var ivory = StructureBuilder()
        var deck = StructureBuilder()
        var gold = StructureBuilder()
        var glow = StructureBuilder()

        // Keel, chine, sheer, deck crown, and back down the port side.
        let profile: [SIMD2<Float>] = [
            [0.00, -0.55],
            [0.72, -0.20],
            [1.00, 0.28],
            [0.00, 0.52],
            [-1.00, 0.28],
            [-0.72, -0.20],
        ]
        let beam: Float = 2.00
        let rise: Float = 1.87
        let lift: Float = 1.03

        let stations: [(z: Float, taper: Float)] = [
            (5.20, 0.16),
            (2.60, 0.70),
            (-0.20, 1.00),
            (-2.90, 0.88),
            (-5.00, 0.52),
        ]
        ivory.addLoft(
            sections: stations.map {
                section(profile: profile, z: $0.z, taper: $0.taper, beam: beam, rise: rise, lift: lift)
            },
            nose: [0, lift + 0.06, random.float(in: 5.62...5.78)],
            tail: [0, lift + 0.30, -5.45]
        )

        // Low canopy cabin, set aft so the open deck forward reads as cargo space.
        ivory.addSolid(
            lower: StructureGeometry.rectangle(width: 2.10, depth: 2.40, y: 1.68, center: [0, -1.60]),
            upper: StructureGeometry.rectangle(width: 1.32, depth: 1.62, y: 2.52, center: [0, -1.60])
        )

        // Short starboard boarding step — not the long side ramp that used to
        // read as a dark slab sticking into the void.
        let stepTop: [SIMD3<Float>] = [
            [1.70, 1.18, -1.10],
            [1.70, 1.18, -0.20],
            [2.35, 0.55, -0.20],
            [2.35, 0.55, -1.10],
        ]
        ivory.addSolid(
            lower: stepTop.map { $0 - [0, 0.10, 0] },
            upper: stepTop
        )

        // Deck inlay. Outrigger fins stay close to the hull so they silhouette
        // as craft detail rather than a boom.
        deck.addQuad(
            [-0.86, 2.02, 2.10], [0.86, 2.02, 2.10],
            [0.86, 2.02, -0.60], [-0.86, 2.02, -0.60],
            facing: [0, 1, 0]
        )
        for side in [Float(-1), Float(1)] {
            deck.addFin(
                [side * 1.72, 0.78, -2.40],
                [side * 1.72, 0.78, -4.20],
                [side * 2.35, 0.52, -3.90],
                extrude: [0, 0.14, 0]
            )
        }

        // Gold rub-rails, cabin ribbing, bow ornament.
        for side in [Float(-1), Float(1)] {
            gold.addQuad(
                [side * 1.98, 1.42, 2.55], [side * 1.98, 1.42, -4.20],
                [side * 1.98, 1.62, -4.20], [side * 1.98, 1.62, 2.55],
                facing: [side, 0.2, 0]
            )
        }
        for index in 0..<3 {
            let z = -2.50 + Float(index) * 0.90
            gold.addQuad(
                [-0.80, 2.46, z - 0.07], [0.80, 2.46, z - 0.07],
                [0.80, 2.46, z + 0.07], [-0.80, 2.46, z + 0.07],
                facing: [0, 1, 0]
            )
        }
        gold.addSpire(
            base: StructureGeometry.rectangle(width: 0.30, depth: 0.30, y: 1.96, center: [0, 3.90]),
            apex: [0, random.float(in: 2.72...2.92), 4.62]
        )

        // Docked gold pier — the concept 01 landing: a lattice walk from midships
        // toward the rim. Bow faces the expansion void, so land is aft; the pier
        // steps off the port sheer toward -Z and a little -X so it reads as a
        // dock, not a spar into empty space.
        addDockPier(into: &gold)

        // Turquoise trim: hull strips and the drive wash at the transom.
        for side in [Float(-1), Float(1)] {
            glow.addQuad(
                [side * 2.00, 1.20, 2.10], [side * 2.00, 1.20, -3.80],
                [side * 2.00, 1.34, -3.80], [side * 2.00, 1.34, 2.10],
                facing: [side, 0, 0]
            )
            glow.addQuad(
                [side * 0.18, 1.06, -5.36], [side * 0.62, 1.06, -5.36],
                [side * 0.62, 1.44, -5.36], [side * 0.18, 1.44, -5.36],
                facing: [0, 0, -1]
            )
        }
        glow.addQuad(
            [1.72, 1.10, -1.05], [2.28, 0.58, -1.05],
            [2.28, 0.58, -0.85], [1.72, 1.10, -0.85],
            facing: [0, 1, 0]
        )

        return StructureAssembly.entity(
            named: "transport.sunwoven",
            zones: [
                StructureZone(
                    "hull",
                    ivory,
                    StructureMaterial.matte(
                        SunfoldPalette.sunwovenIvory,
                        roughness: 0.86,
                        surface: .transportHull
                    )
                ),
                StructureZone("deck", deck, StructureMaterial.matte(SunfoldPalette.sunwovenSurface)),
                StructureZone("gold", gold, StructureMaterial.matte(SunfoldPalette.sunwovenGold, roughness: 0.85)),
                StructureZone("trim", glow, StructureMaterial.glow(SunfoldPalette.sunwovenTurquoise, opacity: 0.85)),
            ]
        )
    }

    /// Lattice pier on the landward quarter — posts, deck boards, rail caps.
    private static func addDockPier(into gold: inout StructureBuilder) {
        // Deck plate from the port sheer toward the rim (aft-port).
        let pierDeck: [SIMD3<Float>] = [
            [-1.85, 1.05, -0.40],
            [-1.85, 1.05, -3.60],
            [-4.40, 0.12, -3.35],
            [-4.40, 0.12, -0.65],
        ]
        gold.addSolid(
            lower: pierDeck.map { $0 - [0, 0.12, 0] },
            upper: pierDeck
        )

        // Posts along both long edges.
        for (outer, z0, z1) in [
            (Float(-1.95), Float(-0.55), Float(-3.40)),
            (Float(-4.25), Float(-0.80), Float(-3.20)),
        ] {
            for t in [Float(0.12), 0.38, 0.62, 0.88] {
                let z = z0 + (z1 - z0) * t
                let yTop: Float = outer < -3 ? 1.05 : 1.85
                gold.addSolid(
                    lower: StructureGeometry.rectangle(
                        width: 0.14, depth: 0.14, y: 0.02, center: [outer, z]
                    ),
                    upper: StructureGeometry.rectangle(
                        width: 0.11, depth: 0.11, y: yTop, center: [outer, z]
                    )
                )
            }
        }

        // Handrail caps.
        gold.addQuad(
            [-2.00, 1.88, -0.50], [-2.00, 1.88, -3.45],
            [-1.78, 1.88, -3.45], [-1.78, 1.88, -0.50],
            facing: [0, 1, 0]
        )
        gold.addQuad(
            [-4.35, 1.08, -0.75], [-4.35, 1.08, -3.25],
            [-4.12, 1.08, -3.25], [-4.12, 1.08, -0.75],
            facing: [0, 1, 0]
        )

        // Cross-braces between the near and far post rows.
        for t in [Float(0.25), 0.55, 0.80] {
            let zNear = -0.55 + (-3.40 - -0.55) * t
            let zFar = -0.80 + (-3.20 - -0.80) * t
            gold.addQuad(
                [-2.00, 0.55, zNear], [-4.20, 0.35, zFar],
                [-4.20, 0.48, zFar], [-2.00, 0.68, zNear],
                facing: [0, 1, 0.15]
            )
        }
    }

    // MARK: - Gravemark

    private static func gravemark(seed: UInt64) -> Entity {
        var random = DeterministicRandom.stream(seed: seed, tag: "transport.gravemark")

        var plate = StructureBuilder()
        var rock = StructureBuilder()
        var copper = StructureBuilder()
        var glow = StructureBuilder()

        // Flat-bottomed and chamfered at every corner — a slab, not a boat.
        let profile: [SIMD2<Float>] = [
            [0.55, -0.50],
            [1.00, -0.18],
            [1.00, 0.34],
            [0.58, 0.52],
            [-0.58, 0.52],
            [-1.00, 0.34],
            [-1.00, -0.18],
            [-0.55, -0.50],
        ]
        let beam: Float = 2.00
        let rise: Float = 1.85
        let lift: Float = 0.93

        let stations: [(z: Float, taper: Float)] = [
            (4.90, 0.60),
            (2.20, 0.94),
            (-0.80, 1.00),
            (-4.85, 0.90),
        ]
        plate.addLoft(
            sections: stations.map {
                section(profile: profile, z: $0.z, taper: $0.taper, beam: beam, rise: rise, lift: lift)
            },
            nose: [0, lift + 0.02, random.float(in: 5.35...5.50)],
            tail: nil
        )
        // Square transom, capped flat rather than drawn to a point.
        let transom = section(profile: profile, z: -4.85, taper: 0.90, beam: beam, rise: rise, lift: lift)
        plate.addCap(ring: transom, pivot: [0, lift, -3.0])

        // Stern bridge block.
        plate.addSolid(
            lower: StructureGeometry.rectangle(width: 2.55, depth: 2.15, y: 1.62, center: [0, -3.10]),
            upper: StructureGeometry.rectangle(
                width: 2.15, depth: 1.75,
                y: random.float(in: 2.48...2.64), center: [0, -3.10]
            )
        )

        // Flank sponsons.
        for side in [Float(-1), Float(1)] {
            rock.addSolid(
                lower: StructureGeometry.rectangle(width: 0.74, depth: 4.00, y: 0.68, center: [side * 1.92, -0.60]),
                upper: StructureGeometry.rectangle(width: 0.58, depth: 3.70, y: 1.28, center: [side * 1.92, -0.60])
            )
        }

        // Bow ramp: drops straight ahead, wide enough to march a column down.
        let rampTop: [SIMD3<Float>] = [
            [-1.38, 1.30, 4.20],
            [1.38, 1.30, 4.20],
            [1.18, 0.05, 6.58],
            [-1.18, 0.05, 6.58],
        ]
        copper.addSolid(
            lower: rampTop.map { $0 - [0, 0.16, 0] },
            upper: rampTop
        )
        for index in 0..<3 {
            let t = 0.24 + Float(index) * 0.26
            let left = rampTop[0] + (rampTop[3] - rampTop[0]) * t
            let right = rampTop[1] + (rampTop[2] - rampTop[1]) * t
            copper.addQuad(
                left + [0, 0.05, -0.10], right + [0, 0.05, -0.10],
                right + [0, 0.05, 0.10], left + [0, 0.05, 0.10],
                facing: [0, 1, 0]
            )
        }

        // Copper seam rails and bridge antennae.
        for side in [Float(-1), Float(1)] {
            copper.addQuad(
                [side * 2.01, 1.24, 3.60], [side * 2.01, 1.24, -4.30],
                [side * 2.01, 1.44, -4.30], [side * 2.01, 1.44, 3.60],
                facing: [side, 0.2, 0]
            )
            copper.addSpire(
                base: StructureGeometry.rectangle(width: 0.20, depth: 0.20, y: 2.55, center: [side * 0.70, -3.55]),
                apex: [side * 0.70, random.float(in: 3.20...3.45), -3.75]
            )
        }

        for side in [Float(-1), Float(1)] {
            glow.addQuad(
                [side * 0.30, 1.02, -5.28], [side * 0.86, 1.02, -5.28],
                [side * 0.86, 1.46, -5.28], [side * 0.30, 1.46, -5.28],
                facing: [0, 0, -1]
            )
            glow.addQuad(
                [side * 1.99, 0.86, 1.60], [side * 1.99, 0.86, -2.60],
                [side * 1.99, 1.02, -2.60], [side * 1.99, 1.02, 1.60],
                facing: [side, 0, 0]
            )
        }
        glow.addQuad(
            [-0.78, 1.92, -2.06], [0.78, 1.92, -2.06],
            [0.78, 2.26, -2.06], [-0.78, 2.26, -2.06],
            facing: [0, 0, 1]
        )

        return StructureAssembly.entity(
            named: "transport.gravemark",
            zones: [
                StructureZone(
                    "hull",
                    plate,
                    StructureMaterial.matte(
                        SunfoldPalette.gravemarkSurface,
                        roughness: 0.90,
                        surface: .armouredHull
                    )
                ),
                StructureZone("sponson", rock, StructureMaterial.matte(SunfoldPalette.gravemarkRock, roughness: 0.96)),
                StructureZone("copper", copper, StructureMaterial.matte(SunfoldPalette.gravemarkCopper, roughness: 0.85)),
                StructureZone("drive", glow, StructureMaterial.glow(SunfoldPalette.gravemarkMineral, opacity: 0.85)),
            ]
        )
    }
}
