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

    /// How much larger a star's quad is than the speck it draws.
    ///
    /// The quad is no longer the star — it is the canvas the falloff is painted
    /// on, and the visible core covers only its middle fifth. Keeping the drawn
    /// core the size the hard quads used to be therefore means growing the quad,
    /// not the star. Applied only when the sprite exists: without it the quad is
    /// the star again, and enlarging it would just make the old defect bigger.
    private static let softPointScale: Float = 2.25

    private static func makeStars(seed: UInt64) -> Entity {
        var random = DeterministicRandom.stream(seed: seed, tag: "starfield")
        let entity = Entity()
        entity.name = "void.stars"

        // Each quad carries its own 0…1 UV pair so one shared radial sprite can
        // be stamped on all 650 of them. `FlatMeshBuilder` cannot express that —
        // its projections derive UVs from world position, which would smear a
        // single sprite across the whole card — so the star quads are assembled
        // directly. The backdrop behind them stays a bare `generatePlane`.
        let sprite = softPointSprite()
        let spread = sprite == nil ? Float(1) : softPointScale
        var warm = StarSpriteBuilder()
        var cool = StarSpriteBuilder()
        let half = baseExtent / 2

        for index in 0..<starCount {
            // Draw order is load-bearing: three draws per star, x then y then
            // size, unchanged from the hard-quad build so the same seed lays out
            // the same sky.
            let center = SIMD3<Float>(
                random.float(in: -half...half),
                random.float(in: -half...half),
                0
            )
            // Sized so a star's *core* reads as a 2–7 point speck at default
            // zoom, as before; the halo extends past it.
            let size = random.float(in: 0.10...0.32) * spread

            // A cool minority keeps the field from reading as a single flat tint.
            if index % 4 == 0 {
                cool.addQuad(center: center, half: size)
            } else {
                warm.addQuad(center: center, half: size)
            }
        }

        entity.addChild(
            makeStarLayer(builder: warm, color: SunfoldPalette.starWarm, sprite: sprite, name: "stars.warm")
        )
        entity.addChild(
            makeStarLayer(builder: cool, color: SunfoldPalette.starCool, sprite: sprite, name: "stars.cool")
        )
        entity.position = [0, 0, starDepth]
        return entity
    }

    private static func makeStarLayer(
        builder: StarSpriteBuilder,
        color: UIColor,
        sprite: TextureResource?,
        name: String
    ) -> Entity {
        let entity = Entity()
        entity.name = name
        // Stars are the one thing in frame that is unambiguously a light source,
        // so they are authored at full emitter level and are the strongest thing
        // the post-process bright pass picks up. The backdrop card deliberately
        // stays an ordinary UnlitMaterial — it must never bloom.
        var material = UnlitMaterial(
            color: LuminousMaterial.luminous(color, whiten: 0.35),
            applyPostProcessToneMap: false
        )
        material.faceCulling = .none
        // The sprite is an opacity mask, not a tint: the colour above stays the
        // authored emitter colour at every texel, and the mask decides how much
        // of it survives. Tinting instead would darken the halo toward grey,
        // which is what a dimming star does, not what a distant one looks like.
        if let sprite {
            material.blending = .transparent(
                opacity: .init(scale: 1, texture: ProceduralTexture.bind(sprite))
            )
        }
        entity.components.set(
            ModelComponent(mesh: builder.makeMesh(named: name), materials: [material])
        )
        return entity
    }

    // MARK: - Soft point sprite

    /// Cached across rebuilds: one 64×64 mask serves every star in the sky.
    private static var cachedSprite: TextureResource?

    /// The radial falloff that turns a quad into a point of light.
    ///
    /// Hard-edged quads were the single most obviously synthetic thing in the
    /// rendered frame — measured as a 2-pixel cliff from the void floor to full
    /// brightness, with no tail at all. Bloom cannot fix that: a star covers so
    /// few pixels that spreading its energy across a wide Gaussian leaves a halo
    /// three orders of magnitude below the threshold of visibility. The softness
    /// has to be in the star itself.
    ///
    /// Profile: a tight Gaussian core plus a wider, weaker one for the halo, and
    /// a window that forces the mask to exactly zero before the quad's edge — a
    /// star that did not reach zero would put back the straight edge this is here
    /// to remove.
    private static func softPointSprite() -> TextureResource? {
        if let cachedSprite { return cachedSprite }

        let size = 64
        var values = [Float](repeating: 0, count: size * size)
        for y in 0..<size {
            for x in 0..<size {
                // Texel centres, so the profile is symmetric about the quad's
                // centre rather than biased half a texel toward the origin.
                let u = (Float(x) + 0.5) / Float(size) - 0.5
                let v = (Float(y) + 0.5) / Float(size) - 0.5
                // 0 at the centre, 1 at the edge midpoints, √2 at the corners.
                let d = 2 * sqrt(u * u + v * v)
                guard d < 1 else { continue }

                let core = exp(-pow(d / 0.22, 2))
                let halo = 0.45 * exp(-pow(d / 0.55, 2))
                // Smoothstep run down rather than up: 1 inside 0.75, 0 at 1.
                let t = min(max((d - 0.75) / 0.25, 0), 1)
                let window = 1 - t * t * (3 - 2 * t)
                values[y * size + x] = min(core + halo, 1) * window
            }
        }

        guard let image = ProceduralImage.scalar(size: size, values: values) else {
            DebugLog.warn("Star sprite could not be built; stars fall back to hard quads.")
            return nil
        }
        do {
            // `.scalar`, not `.color`: an opacity mask must not be run through an
            // sRGB decode on the way in, or the falloff is not the curve authored.
            let resource = try TextureResource(
                image: image,
                withName: "sunfold.star.point",
                options: .init(semantic: .scalar, mipmapsMode: .allocateAndGenerateAll)
            )
            cachedSprite = resource
            return resource
        } catch {
            DebugLog.warn("Star sprite failed to upload (\(error)); stars fall back to hard quads.")
            return nil
        }
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

        // The last flat-tint material in the scene. It is a distant rock, so it
        // takes the same fractured-stone class the fragment undersides take,
        // at the same violet-grey it has always been — the tint is what it
        // reads as, not a multiplier, so the colour is unchanged.
        //
        // `.rimStone` tiles once per `metersPerTile`, and `generateSphere`'s UVs
        // run 0...1 over the whole body, so a ~6 m moon gets a single tile of
        // very low-frequency mottling rather than gravel. That is the correct
        // read for something this far away.
        let material = MaterialLibrary.material(
            .rimStone,
            tint: UIColor(red: 0.46, green: 0.42, blue: 0.47, alpha: 1),
            roughness: 1.0
        )

        entity.components.set(
            ModelComponent(mesh: .generateSphere(radius: radius), materials: [material])
        )
        entity.position = [46, 29, celestialDepth]
        return entity
    }
}

/// Two-triangle quads that each carry a full 0…1 UV square, so one sprite can be
/// stamped on every one of them.
private struct StarSpriteBuilder {
    private var positions: [SIMD3<Float>] = []
    private var normals: [SIMD3<Float>] = []
    private var textureCoordinates: [SIMD2<Float>] = []
    private var indices: [UInt32] = []

    /// The card faces the camera down +Z, so every star shares one normal and
    /// the winding below is already counter-clockwise seen from the front.
    private static let facing = SIMD3<Float>(0, 0, 1)

    mutating func addQuad(center: SIMD3<Float>, half: Float) {
        let base = UInt32(positions.count)
        // Spelled out with explicit `SIMD3<Float>`: as an array literal of
        // `center + [...]` the corners cost more than the type checker will
        // spend, and the build fails with an "unable to type-check in reasonable
        // time" error rather than anything about the geometry.
        let corners: [SIMD3<Float>] = [
            SIMD3<Float>(center.x - half, center.y - half, center.z),
            SIMD3<Float>(center.x + half, center.y - half, center.z),
            SIMD3<Float>(center.x + half, center.y + half, center.z),
            SIMD3<Float>(center.x - half, center.y + half, center.z)
        ]
        positions.append(contentsOf: corners)
        normals.append(contentsOf: [Self.facing, Self.facing, Self.facing, Self.facing])
        // v runs down: `CGImage` rows start at the top, so this puts the sprite's
        // first row at the quad's top edge. The mask is radially symmetric, so
        // this is a correctness point rather than a visible one.
        textureCoordinates.append(contentsOf: [
            SIMD2<Float>(0, 1), SIMD2<Float>(1, 1), SIMD2<Float>(1, 0), SIMD2<Float>(0, 0)
        ])
        indices.append(contentsOf: [base, base + 1, base + 2, base, base + 2, base + 3])
    }

    /// `MeshResource` generation is main-actor isolated in RealityKit, so mesh
    /// assembly stays on the main actor with the rest of the scene build.
    @MainActor
    func makeMesh(named name: String) -> MeshResource {
        var descriptor = MeshDescriptor(name: name)
        descriptor.positions = MeshBuffer(positions)
        descriptor.normals = MeshBuffer(normals)
        descriptor.textureCoordinates = MeshBuffer(textureCoordinates)
        descriptor.primitives = .triangles(indices)
        do {
            return try MeshResource.generate(from: [descriptor])
        } catch {
            // A starfield that fails to generate must not take the sky with it.
            DebugLog.warn("Star mesh \(name) failed to generate (\(error)); layer omitted.")
            return .generatePlane(width: 0.001, height: 0.001)
        }
    }
}
