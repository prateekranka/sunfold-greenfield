import Foundation
import RealityKit
import UIKit
import simd

/// The deep black-indigo void: backdrop, nebula wash, sparse stars, debris and
/// one distant body.
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
    private static let debrisCount = 14

    /// Local depths within the card, back to front.
    private static let backdropDepth: Float = 0
    private static let nebulaDepth: Float = 2
    private static let starDepth: Float = 6
    private static let debrisDepth: Float = 9
    private static let celestialDepth: Float = 12

    static func makeSky(seed: UInt64, tuning: SkirmishTuning) -> Entity {
        let sky = Entity()
        sky.name = "void.sky"
        // Sits far behind the playfield, inside the far plane.
        sky.position = [0, 0, -tuning.voidBackdropDistance]

        sky.addChild(makeBackdrop())
        sky.addChild(makeNebula(seed: seed))
        sky.addChild(makeStars(seed: seed))
        sky.addChild(makeDebris(seed: seed))
        sky.addChild(makeCelestialBody(seed: seed))
        return sky
    }

    // MARK: - Backdrop

    private static func makeBackdrop() -> Entity {
        let entity = Entity()
        entity.name = "void.backdrop"
        // Flat voidDeep read as a cutout. Concept 01's floor sits at luma ~0.033
        // with warm/cool mottling; an opaque procedural tint on the card itself is
        // the only way that floor moves when a transparent wash is too shy.
        var material = UnlitMaterial(color: SunfoldPalette.voidDeep)
        material.faceCulling = .none
        if let texture = backdropTexture() {
            material.color = .init(tint: .white, texture: ProceduralTexture.bind(texture))
        }
        entity.components.set(
            ModelComponent(
                mesh: .generatePlane(width: baseExtent, height: baseExtent),
                materials: [material]
            )
        )
        entity.position = [0, 0, backdropDepth]
        return entity
    }

    private static var cachedBackdrop: TextureResource?

    /// Opaque void floor — deep indigo with a slow warm lift, never bright.
    private static func backdropTexture() -> TextureResource? {
        if let cachedBackdrop { return cachedBackdrop }

        let size = 128
        var colors = [SIMD3<Float>](repeating: .zero, count: size * size)
        let deep = SIMD3<Float>(0.039, 0.045, 0.105)
        let warm = SIMD3<Float>(0.085, 0.070, 0.055)
        let cool = SIMD3<Float>(0.055, 0.062, 0.130)

        for y in 0..<size {
            for x in 0..<size {
                let u = (Float(x) + 0.5) / Float(size)
                let v = (Float(y) + 0.5) / Float(size)
                let broad = ProceduralNoise.fbm(u, v, octaves: 3, cellsX: 3, cellsY: 3, gain: 0.55, salt: 0xB4C4_0001)
                let lift = ProceduralNoise.smoothstep(0.25, 0.75, broad)
                let warmMix = ProceduralNoise.smoothstep(0.35, 0.80, broad)
                let tint = cool * (1 - warmMix) + warm * warmMix
                colors[y * size + x] = deep * (1 - 0.55 * lift) + tint * (0.55 * lift)
            }
        }

        guard let image = ProceduralImage.color(size: size, values: colors) else { return nil }
        do {
            let resource = try TextureResource(
                image: image,
                withName: "sunfold.void.backdrop",
                options: .init(semantic: .color, mipmapsMode: .allocateAndGenerateAll)
            )
            cachedBackdrop = resource
            return resource
        } catch {
            DebugLog.warn("Void backdrop texture failed (\(error)); flat tint used.")
            return nil
        }
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

    // MARK: - Nebula wash

    /// A soft colour wash between the backdrop and the stars.
    ///
    /// Concept 01's void is not flat black — measured soft-void (0.02 < L < 0.18)
    /// covers a third of the mid-frame at sat 0.58. The bible forbids busy
    /// nebulae over the playfield, so this is one low-frequency mottled plane at
    /// low opacity, not a stack of clouds. Unlit, and deliberately ordinary so
    /// it never enters the bloom bright pass the way the stars do.
    private static func makeNebula(seed: UInt64) -> Entity {
        let entity = Entity()
        entity.name = "void.nebula"

        var material = UnlitMaterial(color: .white)
        material.faceCulling = .none
        if let maps = nebulaMaps(seed: seed) {
            material.color = .init(tint: .white, texture: ProceduralTexture.bind(maps.color))
            material.blending = .transparent(
                opacity: .init(scale: 1, texture: ProceduralTexture.bind(maps.opacity))
            )
        } else {
            material = LuminousMaterial.unlit(
                SunfoldPalette.voidNebulaCool,
                strength: 0.35,
                whiten: 0,
                opacity: 0.22
            )
        }

        entity.components.set(
            ModelComponent(
                mesh: .generatePlane(width: baseExtent, height: baseExtent),
                materials: [material]
            )
        )
        entity.position = [0, 0, nebulaDepth]
        return entity
    }

    private static var cachedNebulaColor: TextureResource?
    private static var cachedNebulaOpacity: TextureResource?

    /// Colour and coverage as separate maps — opacity must be `.scalar` so it
    /// is not sRGB-decoded into a different falloff than the one authored.
    private static func nebulaMaps(seed: UInt64) -> (color: TextureResource, opacity: TextureResource)? {
        if let cachedNebulaColor, let cachedNebulaOpacity {
            return (cachedNebulaColor, cachedNebulaOpacity)
        }

        var random = DeterministicRandom.stream(seed: seed, tag: "nebula")
        let saltA = UInt32(truncatingIfNeeded: random.next()) | 1
        let saltB = UInt32(truncatingIfNeeded: random.next()) | 1
        let saltC = UInt32(truncatingIfNeeded: random.next()) | 1

        let size = 256
        var colors = [SIMD3<Float>](repeating: .zero, count: size * size)
        var alpha = [Float](repeating: 0, count: size * size)

        let warm = SIMD3<Float>(0.310, 0.248, 0.188)
        let cool = SIMD3<Float>(0.110, 0.125, 0.220)
        let deep = SIMD3<Float>(0.039, 0.045, 0.105)

        for y in 0..<size {
            for x in 0..<size {
                let u = (Float(x) + 0.5) / Float(size)
                let v = (Float(y) + 0.5) / Float(size)
                let broad = ProceduralNoise.fbm(u, v, octaves: 3, cellsX: 3, cellsY: 3, gain: 0.55, salt: saltA)
                let vein = ProceduralNoise.fbm(
                    u * 1.4 + 0.17, v * 1.1 - 0.09,
                    octaves: 2, cellsX: 5, cellsY: 4, gain: 0.5, salt: saltB
                )
                let gate = ProceduralNoise.smoothstep(0.18, 0.62, broad * 0.70 + vein * 0.30)

                // Broad coverage across the upper two thirds; the playfield still
                // sits over deep void because the island occludes the card.
                let vertical = ProceduralNoise.smoothstep(0.08, 0.70, v)
                let coverage = max(gate * (0.45 + 0.55 * vertical), vertical * 0.25)

                let warmMix = ProceduralNoise.smoothstep(
                    0.30, 0.75,
                    broad + 0.25 * ProceduralNoise.value(u, v, cellsX: 2, cellsY: 2, salt: saltC)
                )
                let tint = cool * (1 - warmMix) + warm * warmMix
                // Authored brighter than the floor so even modest opacity lifts luma.
                let color = simd_min(tint * 1.35 + deep * 0.15, SIMD3<Float>(1, 1, 1))

                let index = y * size + x
                colors[index] = color
                // Peak ~0.70 — try1 measured soft-void at 0.049 against concept
                // 0.338; 0.40 was not enough once ACES and the black plate ate it.
                alpha[index] = min(coverage * 0.70, 0.72)
            }
        }

        guard
            let colorImage = ProceduralImage.color(size: size, values: colors),
            let opacityImage = ProceduralImage.scalar(size: size, values: alpha)
        else {
            DebugLog.warn("Nebula texture could not be built; wash omitted.")
            return nil
        }
        do {
            let color = try TextureResource(
                image: colorImage,
                withName: "sunfold.void.nebula.color",
                options: .init(semantic: .color, mipmapsMode: .allocateAndGenerateAll)
            )
            let opacity = try TextureResource(
                image: opacityImage,
                withName: "sunfold.void.nebula.opacity",
                options: .init(semantic: .scalar, mipmapsMode: .allocateAndGenerateAll)
            )
            cachedNebulaColor = color
            cachedNebulaOpacity = opacity
            return (color, opacity)
        } catch {
            DebugLog.warn("Nebula texture failed to upload (\(error)); wash omitted.")
            return nil
        }
    }

    // MARK: - Debris

    /// A handful of dim rock shards on the card — concept 01's drifting asteroids.
    ///
    /// Kept unlit and small so they read as depth cues rather than as a second
    /// playfield. Merged into one mesh; one `"debris"` stream, never touching
    /// `"starfield"` or `"celestial"`.
    private static func makeDebris(seed: UInt64) -> Entity {
        var random = DeterministicRandom.stream(seed: seed, tag: "debris")
        let entity = Entity()
        entity.name = "void.debris"

        // Angular shards, not quads — a dark square against black void vanishes.
        // Sized and lit for the visible card: at default zoom halfW≈38.7, so a
        // shard must sit inside roughly ±35 and read mid-grey or ACES eats it.
        var builder = FlatMeshBuilder()
        for index in 0..<debrisCount {
            let side = index % 3
            let x: Float
            let y: Float
            switch side {
            case 0:
                x = random.float(in: -34...(-14))
                y = random.float(in: -8...22)
            case 1:
                x = random.float(in: 14...34)
                y = random.float(in: -6...24)
            default:
                x = random.float(in: -22...22)
                y = random.float(in: 16...28)
            }
            let half = random.float(in: 1.8...4.2)
            let depth = random.float(in: 0.5...1.4)
            let yaw = random.float(in: 0...(2 * .pi))
            let cosY = cos(yaw)
            let sinY = sin(yaw)

            // Irregular tetrahedron facing the camera, plus a second facet so the
            // silhouette breaks rather than reading as one flat kite.
            let tip = SIMD3<Float>(x, y + half * 0.85, depth * 0.2)
            let a = SIMD3<Float>(x + cosY * half, y - half * 0.35, 0)
            let b = SIMD3<Float>(x - sinY * half * 0.7, y - half * 0.15, depth * 0.5)
            let c = SIMD3<Float>(x - cosY * half * 0.55 + sinY * half * 0.4, y + half * 0.1, 0)
            let d = SIMD3<Float>(
                x + sinY * half * 0.45,
                y - half * 0.55,
                depth * 0.15
            )
            let facing = SIMD3<Float>(0, 0, 1)
            builder.addTriangle(a, b, tip, facing: facing)
            builder.addTriangle(b, c, tip, facing: facing)
            builder.addTriangle(c, a, tip, facing: facing)
            builder.addTriangle(a, d, b, facing: facing)
        }

        // Mid tone — brighter than try2 charcoal, quieter than try3's near-ivory.
        var material = UnlitMaterial(
            color: UIColor(red: 0.44, green: 0.40, blue: 0.37, alpha: 1)
        )
        material.faceCulling = .none
        entity.components.set(
            ModelComponent(mesh: builder.makeMesh(named: "debris"), materials: [material])
        )
        entity.position = [0, 0, debrisDepth]
        return entity
    }

    // MARK: - Celestial body

    /// One distant body, parked upper-right as framed in concept 01. The bible
    /// caps this at one or two; a second would crowd the playfield.
    ///
    /// CP-08 finding: the earlier body sat at `[46, 29]` with radius ~6. At
    /// default zoom the orthographic half-width is ~38.7, so X=46 was outside
    /// the frustum — that is why the frame had no planet. Repositioned inside
    /// the visible card, enlarged, and retinted to the warm gas-giant midtone
    /// measured off concept 01.
    private static func makeCelestialBody(seed: UInt64) -> Entity {
        var random = DeterministicRandom.stream(seed: seed, tag: "celestial")
        let entity = Entity()
        entity.name = "void.celestial"

        // ~14 m at default zoom is roughly a quarter of the half-height — large
        // enough to read as a body, small enough not to compete with the Core.
        let radius = random.float(in: 13.0...15.5)

        // Unlit + soft banding: a lit PBR sphere under this IBL picks up the
        // warm ground bounce on its lower half and reads as a rock sitting in
        // the scene rather than as a distant planet. The banded texture is what
        // sells the gas-giant read once the silhouette is the right size.
        var material = UnlitMaterial(color: SunfoldPalette.celestialBody)
        material.faceCulling = .none
        if let texture = celestialTexture(seed: seed) {
            material.color = .init(tint: .white, texture: ProceduralTexture.bind(texture))
        }

        entity.components.set(
            ModelComponent(mesh: .generateSphere(radius: radius), materials: [material])
        )
        // Upper-right, fully on-screen at default zoom (halfW≈38.7, halfH=29).
        entity.position = [18, 14, celestialDepth]
        // Slight tilt so the banding is not axis-aligned with the frame.
        entity.orientation = simd_quatf(angle: 0.35, axis: SIMD3<Float>(0.2, 0.0, 1.0))
        return entity
    }

    private static var cachedCelestial: TextureResource?

    /// Soft latitudinal banding + low-frequency mottling in the warm family.
    private static func celestialTexture(seed: UInt64) -> TextureResource? {
        if let cachedCelestial { return cachedCelestial }

        var random = DeterministicRandom.stream(seed: seed, tag: "celestial.bands")
        let salt = UInt32(truncatingIfNeeded: random.next()) | 1
        let size = 256
        var colors = [SIMD3<Float>](repeating: .zero, count: size * size)

        let base = SIMD3<Float>(0.780, 0.695, 0.575)
        let dark = SIMD3<Float>(0.520, 0.430, 0.335)
        let light = SIMD3<Float>(0.880, 0.800, 0.680)
        let cool = SIMD3<Float>(0.620, 0.580, 0.560)

        for y in 0..<size {
            for x in 0..<size {
                let u = (Float(x) + 0.5) / Float(size)
                let v = (Float(y) + 0.5) / Float(size)
                // Latitude bands along v, with a slow longitudinal warp.
                let warp = ProceduralNoise.fbm(u, v * 0.35, octaves: 2, cellsX: 3, cellsY: 2, gain: 0.5, salt: salt)
                let bands = 0.5 + 0.5 * sin((v + warp * 0.08) * .pi * 7)
                let mottle = ProceduralNoise.fbm(u, v, octaves: 3, cellsX: 6, cellsY: 4, gain: 0.55, salt: salt &+ 17)
                let polar = ProceduralNoise.smoothstep(0.78, 0.95, abs(v - 0.5) * 2)

                var color = base
                color = color * (1 - 0.35) + dark * (bands * 0.35)
                color = color * (1 - 0.20) + light * ((1 - bands) * 0.20)
                color = color * (1 - 0.12) + cool * (mottle * 0.12)
                color = color * (1 - 0.25 * polar) + light * (0.25 * polar)

                colors[y * size + x] = color
            }
        }

        guard let image = ProceduralImage.color(size: size, values: colors) else {
            DebugLog.warn("Celestial texture could not be built; flat tint used.")
            return nil
        }
        do {
            let resource = try TextureResource(
                image: image,
                withName: "sunfold.void.celestial",
                options: .init(semantic: .color, mipmapsMode: .allocateAndGenerateAll)
            )
            cachedCelestial = resource
            return resource
        } catch {
            DebugLog.warn("Celestial texture failed to upload (\(error)); flat tint used.")
            return nil
        }
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
