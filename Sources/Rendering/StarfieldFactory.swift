import Foundation
import RealityKit
import UIKit
import simd

/// The deep black-indigo void: backdrop, sparse stars and one distant body.
///
/// All of it is built as a single card that rides the camera rig rather than a
/// world-space shell. An orthographic camera has no perspective convergence, so
/// a distant sky placed in world space would project almost entirely outside the
/// view rectangle and simply never be seen. Parenting the sky to the rig is the
/// correct construction for this projection, not a shortcut.
///
/// The card is counter-scaled with zoom so stars keep a constant apparent size.
@MainActor
enum StarfieldFactory {

    /// Card extent in world units at default zoom. Generous enough that the card
    /// still covers the frustum when zoomed all the way out.
    static let baseExtent: Float = 300
    private static let starCount = 650

    /// Local depths within the card, back to front.
    private static let backdropDepth: Float = 0
    private static let starDepth: Float = 6
    private static let celestialDepth: Float = 12

    static func makeSky(seed: UInt64, tuning: SkirmishTuning) -> Entity {
        let sky = Entity()
        sky.name = "void.sky"
        // Sits far behind the playfield, inside the far plane.
        sky.position = [0, 0, -tuning.voidBackdropDistance]

        sky.addChild(makeBackdrop())
        sky.addChild(makeStars(seed: seed))
        sky.addChild(makeCelestialBody(seed: seed))
        return sky
    }

    // MARK: - Backdrop

    private static func makeBackdrop() -> Entity {
        let entity = Entity()
        entity.name = "void.backdrop"
        var material = UnlitMaterial(color: SunfoldPalette.voidDeep)
        material.faceCulling = .none
        entity.components.set(
            ModelComponent(
                mesh: .generatePlane(width: baseExtent, height: baseExtent),
                materials: [material]
            )
        )
        entity.position = [0, 0, backdropDepth]
        return entity
    }

    // MARK: - Stars

    private static func makeStars(seed: UInt64) -> Entity {
        var random = DeterministicRandom.stream(seed: seed, tag: "starfield")
        let entity = Entity()
        entity.name = "void.stars"

        var warm = FlatMeshBuilder()
        var cool = FlatMeshBuilder()
        let half = baseExtent / 2
        let facing = SIMD3<Float>(0, 0, 1)

        for index in 0..<starCount {
            let center = SIMD3<Float>(
                random.float(in: -half...half),
                random.float(in: -half...half),
                0
            )
            // Sized so a star reads as a 2–7 point speck at default zoom.
            let size = random.float(in: 0.10...0.32)
            let a = center + [-size, -size, 0]
            let b = center + [size, -size, 0]
            let c = center + [size, size, 0]
            let d = center + [-size, size, 0]

            // A cool minority keeps the field from reading as a single flat tint.
            if index % 4 == 0 {
                cool.addTriangle(a, b, c, facing: facing)
                cool.addTriangle(a, c, d, facing: facing)
            } else {
                warm.addTriangle(a, b, c, facing: facing)
                warm.addTriangle(a, c, d, facing: facing)
            }
        }

        entity.addChild(makeStarLayer(builder: warm, color: SunfoldPalette.starWarm, name: "stars.warm"))
        entity.addChild(makeStarLayer(builder: cool, color: SunfoldPalette.starCool, name: "stars.cool"))
        entity.position = [0, 0, starDepth]
        return entity
    }

    private static func makeStarLayer(builder: FlatMeshBuilder, color: UIColor, name: String) -> Entity {
        let entity = Entity()
        entity.name = name
        var material = UnlitMaterial(color: color)
        material.faceCulling = .none
        entity.components.set(
            ModelComponent(mesh: builder.makeMesh(named: name), materials: [material])
        )
        return entity
    }

    // MARK: - Celestial body

    /// One distant body, parked upper-right as framed in concept 01. The bible
    /// caps this at one or two; a second would crowd the playfield.
    private static func makeCelestialBody(seed: UInt64) -> Entity {
        var random = DeterministicRandom.stream(seed: seed, tag: "celestial")
        let entity = Entity()
        entity.name = "void.celestial"

        // Sized to ~15% of viewport height at default zoom, matching concept 01.
        // Larger reads as a nearby moon competing with the playfield.
        let radius = random.float(in: 5.5...7.0)
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: UIColor(red: 0.46, green: 0.42, blue: 0.47, alpha: 1))
        material.roughness = .init(floatLiteral: 1.0)
        material.metallic = .init(floatLiteral: 0.0)

        entity.components.set(
            ModelComponent(mesh: .generateSphere(radius: radius), materials: [material])
        )
        entity.position = [46, 29, celestialDepth]
        return entity
    }
}
