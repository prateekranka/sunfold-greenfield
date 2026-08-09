import Foundation
import RealityKit
import UIKit
import simd

/// The Dominion Spire: the objective at the centre of the map.
///
/// The only structure with no faction, so it is authored to look like neither.
/// Every other building separates on silhouette *within* a civilization's
/// language — woven light or plated iron. This one is older than both: bare
/// dominion stone, an eight-sided plinth echoing the Civilization Core's
/// octagon, and a tapering monolith with a single cold seam running its full
/// height and a mote floating clear above the crown.
///
/// Tall on purpose — roughly 12 m against a Core's 5 m. At the default zoom the
/// Dominion is off-screen from either home, and the first thing a player should
/// learn about the map is that there is something in the middle worth walking
/// to. A short objective reads as scenery.
@MainActor
enum DominionSpireMesh {

    static func make(seed: UInt64) -> Entity {
        var random = DeterministicRandom.stream(seed: seed, tag: "spire.dominion")

        var plinth = StructureBuilder()
        var shaft = StructureBuilder()
        var seam = StructureBuilder()

        // Two stepped octagonal courses. Wide enough that a squad standing on
        // the objective reads as standing *on* something.
        plinth.addSolid(
            lower: StructureGeometry.ring(sides: 8, radius: 3.95, y: 0, phase: .pi / 8),
            upper: StructureGeometry.ring(sides: 8, radius: 3.70, y: 0.42, phase: .pi / 8)
        )
        plinth.addSolid(
            lower: StructureGeometry.ring(sides: 8, radius: 2.90, y: 0.42, phase: .pi / 8),
            upper: StructureGeometry.ring(sides: 8, radius: 2.62, y: 0.98, phase: .pi / 8)
        )

        // Four buttresses on the diagonals, so the silhouette is not a plain
        // pillar from any bearing the camera can reach.
        for quadrant in 0..<4 {
            let angle = Float(quadrant) * .pi / 2 + .pi / 4
            let outward = SIMD2<Float>(cos(angle), sin(angle))
            plinth.addQuad(
                SIMD3(outward.x * 2.70, 0.98, outward.y * 2.70),
                SIMD3(outward.x * 2.70, 0.98, outward.y * 2.70) + SIMD3(-outward.y * 0.44, 0, outward.x * 0.44),
                SIMD3(outward.x * 1.05, 4.30, outward.y * 1.05) + SIMD3(-outward.y * 0.30, 0, outward.x * 0.30),
                SIMD3(outward.x * 1.05, 4.30, outward.y * 1.05),
                facing: SIMD3(outward.x, 0.35, outward.y)
            )
        }

        // The monolith: a long taper from the plinth to a narrow crown.
        let crownY = random.float(in: 11.6...12.1)
        shaft.addSolid(
            lower: StructureGeometry.ring(sides: 8, radius: 1.62, y: 0.98, phase: .pi / 8),
            upper: StructureGeometry.ring(sides: 8, radius: 1.18, y: 5.60, phase: .pi / 8),
            capTop: false
        )
        shaft.addSolid(
            lower: StructureGeometry.ring(sides: 8, radius: 1.18, y: 5.60, phase: .pi / 8),
            upper: StructureGeometry.ring(sides: 8, radius: 0.46, y: crownY, phase: .pi / 8)
        )

        // One seam, full height, on the +Z face the north-up camera looks at.
        seam.addQuad(
            [-0.16, 1.10, 1.55],
            [0.16, 1.10, 1.55],
            [0.16, crownY - 0.55, 0.50],
            [-0.16, crownY - 0.55, 0.50],
            facing: [0, 0, 1]
        )

        // A mote hanging clear above the crown — the part that is visible from
        // across the map when the stone itself is a grey sliver.
        let moteY = crownY + 1.15
        seam.addShard(
            ring: StructureGeometry.ring(sides: 4, radius: 0.52, y: moteY, phase: .pi / 4),
            top: [0, moteY + 0.86, 0],
            bottom: [0, moteY - 0.86, 0]
        )

        return StructureAssembly.entity(
            named: "spire.dominion",
            zones: [
                StructureZone(
                    "plinth",
                    plinth,
                    StructureMaterial.matte(SunfoldPalette.neutralRock, roughness: 0.94)
                ),
                StructureZone(
                    "monolith",
                    shaft,
                    StructureMaterial.matte(SunfoldPalette.dominionStone, roughness: 0.90)
                ),
                // Cold, and neither faction's colour: gold would read Sunwoven,
                // copper would read Gravemark, and the objective belongs to
                // whoever is standing on it.
                StructureZone(
                    "seam",
                    seam,
                    StructureMaterial.glow(SunfoldPalette.starCool, opacity: 0.85)
                ),
            ]
        )
    }
}
