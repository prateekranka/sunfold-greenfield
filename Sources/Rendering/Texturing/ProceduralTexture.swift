import CoreGraphics
import Foundation
import Metal
import RealityKit
import UIKit
import simd

// MARK: - Noise primitives

/// Tileable, allocation-free noise. Every function is a pure function of its
/// arguments, so it consumes no `DeterministicRandom` stream and cannot shift
/// another subsystem's numbers by existing.
///
/// All lattice lookups wrap modulo the cell count, which is what makes the
/// resulting images tile seamlessly: the sample at u = 0.999 and the sample at
/// u = 0.001 share the same lattice corner.
enum ProceduralNoise {

    /// One nearest-cell sample of a cellular (Worley) field.
    struct CellularSample {
        /// Distance to the nearest feature point, in cell units.
        var f1: Float
        /// Distance to the second nearest feature point, in cell units.
        var f2: Float
        /// A stable per-cell value in [0, 1) for the owning cell.
        var cell: Float
    }

    @inline(__always)
    static func wrap(_ value: Int, _ modulus: Int) -> Int {
        let r = value % modulus
        return r < 0 ? r + modulus : r
    }

    /// Integer hash. Deterministic, platform-independent, no RNG state.
    @inline(__always)
    static func hash(_ x: Int, _ y: Int, _ salt: UInt32) -> Float {
        var h = UInt32(truncatingIfNeeded: x &* 374_761_393)
            &+ UInt32(truncatingIfNeeded: y &* 668_265_263)
            &+ salt
        h ^= h >> 13
        h = h &* 1_274_126_177
        h ^= h >> 16
        return Float(h & 0x00FF_FFFF) / Float(0x00FF_FFFF)
    }

    /// Two decorrelated values from a single mix.
    ///
    /// Cellular noise needs a 2D jitter offset per cell and evaluates nine
    /// cells per texel; taking both components out of one hash halves the work
    /// in the hottest loop in the library. 12 bits per axis is 4096 distinct
    /// offsets — far more than a feature point can express visually.
    @inline(__always)
    static func hashPair(_ x: Int, _ y: Int, _ salt: UInt32) -> (Float, Float) {
        var h = UInt32(truncatingIfNeeded: x &* 374_761_393)
            &+ UInt32(truncatingIfNeeded: y &* 668_265_263)
            &+ salt
        h ^= h >> 13
        h = h &* 1_274_126_177
        h ^= h >> 16
        let scale = Float(1) / Float(0xFFF)
        return (Float(h & 0xFFF) * scale, Float((h >> 12) & 0xFFF) * scale)
    }

    @inline(__always)
    static func smootherStep(_ t: Float) -> Float {
        t * t * (3 - 2 * t)
    }

    @inline(__always)
    static func mix(_ a: Float, _ b: Float, _ t: Float) -> Float {
        a + (b - a) * t
    }

    @inline(__always)
    static func smoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
        guard edge1 > edge0 else { return x < edge0 ? 0 : 1 }
        let t = max(0, min(1, (x - edge0) / (edge1 - edge0)))
        return t * t * (3 - 2 * t)
    }

    /// Bilinear value noise on a wrapped lattice. `x`/`y` are tile coordinates
    /// in [0, 1); `cellsX`/`cellsY` may differ, which is how brushed-metal and
    /// woven-thread anisotropy is produced without a separate generator.
    static func value(
        _ x: Float,
        _ y: Float,
        cellsX: Int,
        cellsY: Int,
        salt: UInt32
    ) -> Float {
        let fx = x * Float(cellsX)
        let fy = y * Float(cellsY)
        let x0 = Int(fx.rounded(.down))
        let y0 = Int(fy.rounded(.down))
        let tx = smootherStep(fx - Float(x0))
        let ty = smootherStep(fy - Float(y0))

        // Wrapped lattice indices hoisted out: four `wrap` calls, not eight.
        // This is the single hottest function in the library, and none of the
        // `@inline(__always)` hints apply in a Debug build, so the call count
        // is what actually decides generation time there.
        let ix0 = wrap(x0, cellsX)
        let ix1 = ix0 + 1 == cellsX ? 0 : ix0 + 1
        let iy0 = wrap(y0, cellsY)
        let iy1 = iy0 + 1 == cellsY ? 0 : iy0 + 1

        let a = hash(ix0, iy0, salt)
        let b = hash(ix1, iy0, salt)
        let c = hash(ix0, iy1, salt)
        let d = hash(ix1, iy1, salt)
        return mix(mix(a, b, tx), mix(c, d, tx), ty)
    }

    /// Fractal sum of `value`. Cell counts double each octave, so every octave
    /// stays on an integer lattice and the whole stack tiles.
    static func fbm(
        _ x: Float,
        _ y: Float,
        octaves: Int = 4,
        cellsX: Int = 8,
        cellsY: Int = 8,
        gain: Float = 0.5,
        salt: UInt32
    ) -> Float {
        var sum: Float = 0
        var norm: Float = 0
        var amplitude: Float = 1
        var cx = cellsX
        var cy = cellsY
        // `while`, for the same measured reason as in `cellular`.
        var octave = 0
        let count = max(1, octaves)
        while octave < count {
            sum += value(x, y, cellsX: cx, cellsY: cy, salt: salt &+ UInt32(octave) &* 0x9E37) * amplitude
            norm += amplitude
            amplitude *= gain
            cx *= 2
            cy *= 2
            octave &+= 1
        }
        return norm > 0 ? sum / norm : 0
    }

    /// Ridged fractal noise — creases instead of blobs. Good for stone strata.
    static func ridged(
        _ x: Float,
        _ y: Float,
        octaves: Int = 4,
        cellsX: Int = 8,
        cellsY: Int = 8,
        salt: UInt32
    ) -> Float {
        var sum: Float = 0
        var norm: Float = 0
        var amplitude: Float = 1
        var cx = cellsX
        var cy = cellsY
        var octave = 0
        let count = max(1, octaves)
        while octave < count {
            let v = value(x, y, cellsX: cx, cellsY: cy, salt: salt &+ UInt32(octave) &* 0x85EB)
            sum += (1 - abs(v * 2 - 1)) * amplitude
            norm += amplitude
            amplitude *= 0.5
            cx *= 2
            cy *= 2
            octave &+= 1
        }
        return norm > 0 ? sum / norm : 0
    }

    /// Cellular / Worley noise over a wrapped cell grid.
    ///
    /// `f2 - f1` is the classic crack/seam mask: it goes to zero exactly on the
    /// boundary between two cells.
    static func cellular(
        _ x: Float,
        _ y: Float,
        cellsX: Int,
        cellsY: Int,
        jitter: Float = 1.0,
        salt: UInt32
    ) -> CellularSample {
        let fx = x * Float(cellsX)
        let fy = y * Float(cellsY)
        let cx = Int(fx.rounded(.down))
        let cy = Int(fy.rounded(.down))

        // Squared distances throughout: two square roots at the end instead of
        // nine, and the winning cell is hashed once rather than on every
        // improvement. Both matter in a Debug build, where nothing inlines.
        var f1sq: Float = 64
        var f2sq: Float = 64
        var ownerX = 0
        var ownerY = 0

        // Deliberately `while` and not `for dj in -1...1`. Measured at -Onone
        // (which is what a Debug build compiles this with), iterating a
        // ClosedRange costs ~145 ns per step against ~4 ns for a while loop,
        // and this 3x3 runs once per texel: it was 90% of the whole function.
        var dj = -1
        while dj <= 1 {
            let iy = cy + dj
            let wy = wrap(iy, cellsY)
            let baseY = Float(iy) - fy
            var di = -1
            while di <= 1 {
                let ix = cx + di
                let wx = wrap(ix, cellsX)
                let (rx, ry) = hashPair(wx, wy, salt)
                let jx = 0.5 + (rx - 0.5) * jitter
                let jy = 0.5 + (ry - 0.5) * jitter
                let dx = Float(ix) + jx - fx
                let dy = baseY + jy
                let squared = dx * dx + dy * dy
                if squared < f1sq {
                    f2sq = f1sq
                    f1sq = squared
                    ownerX = wx
                    ownerY = wy
                } else if squared < f2sq {
                    f2sq = squared
                }
                di &+= 1
            }
            dj &+= 1
        }
        return CellularSample(
            f1: sqrt(f1sq),
            f2: sqrt(f2sq),
            cell: hash(ownerX, ownerY, salt &+ 0x1B87_3593)
        )
    }
}

// MARK: - CGImage assembly

/// CPU image assembly. Nothing here touches RealityKit, so it stays usable from
/// any isolation domain; only the `TextureResource` step is main-actor bound.
enum ProceduralImage {

    @inline(__always)
    static func byte(_ value: Float) -> UInt8 {
        UInt8(max(0, min(255, (value * 255).rounded())))
    }

    /// Packs an RGBA8 buffer into a `CGImage`.
    ///
    /// `linear` selects the colour space: colour maps are authored in sRGB and
    /// decoded by the `.color` semantic; normal/scalar maps must NOT be decoded,
    /// so they go in `linearSRGB` and pair with `.normal` / `.scalar`.
    static func rgba(size: Int, linear: Bool, bytes: [UInt8]) -> CGImage? {
        let expected = size * size * 4
        guard bytes.count == expected else { return nil }
        let spaceName = linear ? CGColorSpace.linearSRGB : CGColorSpace.sRGB
        guard let space = CGColorSpace(name: spaceName),
              let provider = CGDataProvider(data: Data(bytes) as CFData)
        else { return nil }
        return CGImage(
            width: size,
            height: size,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: size * 4,
            space: space,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    /// A single scalar replicated across R/G/B. A one-channel image type-checks
    /// but is not a shape `TextureResource` is documented to accept, so scalar
    /// maps ship as RGBA with the value in every colour channel.
    static func scalar(size: Int, values: [Float]) -> CGImage? {
        guard values.count == size * size else { return nil }
        var bytes = [UInt8](repeating: 255, count: size * size * 4)
        for index in 0..<(size * size) {
            let v = byte(values[index])
            let base = index * 4
            bytes[base] = v
            bytes[base + 1] = v
            bytes[base + 2] = v
        }
        return rgba(size: size, linear: true, bytes: bytes)
    }

    /// Colour buffer -> sRGB image. Components are already display-encoded, the
    /// same space `UIColor` components live in, so no transfer curve is applied.
    static func color(size: Int, values: [SIMD3<Float>], linear: Bool = false) -> CGImage? {
        guard values.count == size * size else { return nil }
        var bytes = [UInt8](repeating: 255, count: size * size * 4)
        for index in 0..<(size * size) {
            let c = values[index]
            let base = index * 4
            bytes[base] = byte(c.x)
            bytes[base + 1] = byte(c.y)
            bytes[base + 2] = byte(c.z)
        }
        return rgba(size: size, linear: linear, bytes: bytes)
    }

    /// Sobel-style central-difference normal map from a wrapped height field.
    ///
    /// Sampling wraps in both axes so the normal map tiles as seamlessly as the
    /// height field it came from. `flipGreen` exists because the green-channel
    /// convention is not stated anywhere in the SDK — if relief reads inverted
    /// in the rendered frame, flip it here rather than at every call site.
    static func normalMap(
        size: Int,
        height: [Float],
        strength: Float,
        flipGreen: Bool = false
    ) -> CGImage? {
        guard height.count == size * size else { return nil }
        var bytes = [UInt8](repeating: 255, count: size * size * 4)

        // Wrapped neighbour indices, computed once instead of eight times per
        // texel. Same reasoning as `ProceduralNoise.value`: in a Debug build the
        // call count is the cost.
        var previous = [Int](repeating: 0, count: size)
        var following = [Int](repeating: 0, count: size)
        for i in 0..<size {
            previous[i] = i == 0 ? size - 1 : i - 1
            following[i] = i == size - 1 ? 0 : i + 1
        }

        for y in 0..<size {
            let rowAbove = previous[y] * size
            let rowHere = y * size
            let rowBelow = following[y] * size
            for x in 0..<size {
                let xl = previous[x]
                let xr = following[x]

                // 3x3 Sobel: less pixel-crawl than a bare central difference.
                let tl = height[rowAbove + xl], t = height[rowAbove + x], tr = height[rowAbove + xr]
                let l = height[rowHere + xl], r = height[rowHere + xr]
                let bl = height[rowBelow + xl], b = height[rowBelow + x], br = height[rowBelow + xr]

                let dx = (tr + 2 * r + br) - (tl + 2 * l + bl)
                let dy = (bl + 2 * b + br) - (tl + 2 * t + tr)

                var n = simd_normalize(SIMD3<Float>(-dx * strength, -dy * strength, 1))
                if flipGreen { n.y = -n.y }
                let encoded = n * 0.5 + SIMD3<Float>(repeating: 0.5)

                let base = (y * size + x) * 4
                bytes[base] = byte(encoded.x)
                bytes[base + 1] = byte(encoded.y)
                bytes[base + 2] = byte(encoded.z)
            }
        }
        return rgba(size: size, linear: true, bytes: bytes)
    }

    /// Cheap cavity-style ambient occlusion: how far a texel sits below the
    /// local mean height. Wrapped separable box blur, so it tiles.
    ///
    /// Both passes use a running sum, so cost is independent of `radius` — the
    /// naive form re-added `2r+1` samples per texel and was, by a wide margin,
    /// the most expensive thing in the library.
    static func occlusion(size: Int, height: [Float], radius: Int, strength: Float) -> [Float] {
        guard height.count == size * size, radius > 0 else {
            return [Float](repeating: 1, count: size * size)
        }
        // A window wider than the tile would wrap onto itself and average to a
        // constant, which is not occlusion.
        let r = min(radius, (size - 1) / 2)
        let window = Float(r * 2 + 1)

        var horizontal = [Float](repeating: 0, count: size * size)
        for y in 0..<size {
            let row = y * size
            var sum: Float = 0
            for k in -r...r {
                sum += height[row + ProceduralNoise.wrap(k, size)]
            }
            for x in 0..<size {
                horizontal[row + x] = sum / window
                // Slide the window one texel right: drop the trailing sample,
                // pick up the leading one.
                sum -= height[row + ProceduralNoise.wrap(x - r, size)]
                sum += height[row + ProceduralNoise.wrap(x + r + 1, size)]
            }
        }

        var blurred = [Float](repeating: 0, count: size * size)
        for x in 0..<size {
            var sum: Float = 0
            for k in -r...r {
                sum += horizontal[ProceduralNoise.wrap(k, size) * size + x]
            }
            for y in 0..<size {
                blurred[y * size + x] = sum / window
                sum -= horizontal[ProceduralNoise.wrap(y - r, size) * size + x]
                sum += horizontal[ProceduralNoise.wrap(y + r + 1, size) * size + x]
            }
        }

        var result = [Float](repeating: 1, count: size * size)
        for index in 0..<(size * size) {
            let cavity = max(0, blurred[index] - height[index])
            result[index] = max(0, min(1, 1 - cavity * strength))
        }
        return result
    }
}

// MARK: - Texture library

/// The project's procedural surface library.
///
/// Every recipe is a pure function of `(recipe, size, seed)`, so the same three
/// inputs always produce byte-identical images. Nothing here draws from a shared
/// `DeterministicRandom` stream at render time: the seed is expanded once into
/// per-recipe, per-layer integer salts via `DeterministicRandom.stream`, and all
/// pixel work is integer hashing from there. Adding a layer to one recipe cannot
/// shift the pixels of another, and adding textures cannot shift the simulation.
@MainActor
enum ProceduralTexture {

    // MARK: Recipes

    /// The named surfaces this game actually has. One case per real material —
    /// not a generic noise toolbox, so the look stays centralised.
    enum Recipe: String, CaseIterable, Sendable {
        /// Weathered pale regolith: the habitable fragment top.
        case regolith
        /// Cool fractured stone: fragment underside and rim rock.
        case fracturedStone
        /// Woven ivory fabric with fine warp/weft threads: Sunwoven structures.
        case wovenIvory
        /// Brushed, part-oxidised metal with copper seams: Gravemark structures.
        case oxidisedMetal
        /// Faceted crystalline mineral with luminous cell seams: Lumen/Aether.
        case crystalline
        /// Burnished gold trim: edges, banding and Core detail.
        case gildedTrim
    }

    /// The set of maps a recipe produces. Any field may be `nil` if generation
    /// failed; callers must degrade to a flat tint rather than render nothing.
    struct MapSet {
        var baseColor: TextureResource?
        var normal: TextureResource?
        var roughness: TextureResource?
        var metallic: TextureResource?
        var ambientOcclusion: TextureResource?
        /// Grayscale luminance mask. Tint it through `EmissiveColor.color`.
        var emissive: TextureResource?
        /// Fine-scale variation mask, for callers that want to drive something
        /// custom (dust, wear, opacity) from the same surface.
        var detail: TextureResource?
        /// Metallic value to use when `metallic` is `nil`.
        var fallbackMetallic: Float = 0
        /// Roughness value to use when `roughness` is `nil`.
        var fallbackRoughness: Float = 0.9
    }

    /// Default authoring resolution. 512 with a full mip chain is ~1.4 MB per
    /// map and is invisible in the frame budget once cached; 1024 is available
    /// for hero surfaces but should not be the default on an iPad.
    static let defaultSize = 512

    /// The texture-only seed. Textures live on their own seed so a change here
    /// can never perturb match simulation.
    static let defaultSeed: UInt64 = 0x5017_FEED_7E47_0000

    // MARK: Public entry points

    /// The maps for a recipe, generated once and cached forever.
    ///
    /// Safe to call from any main-actor code at any time; the first call for a
    /// given `(recipe, size, seed)` pays the CPU cost, every later call is a
    /// dictionary hit.
    @discardableResult
    static func maps(
        _ recipe: Recipe,
        size: Int = defaultSize,
        seed: UInt64 = defaultSeed
    ) -> MapSet {
        let resolved = clampSize(size)
        let key = Key(recipe: recipe, size: resolved, seed: seed)
        if let cached = cache[key] { return cached }
        let built = build(recipe, size: resolved, seed: seed)
        cache[key] = built
        return built
    }

    /// Generates several recipes up front, so the first frame that needs one
    /// does not pay for it. Call from scene setup, never from an update tick.
    ///
    /// This blocks the main actor. Measured at 512: ~37 ms per recipe in a
    /// Release build, ~570 ms in Debug (`-Onone` inlines nothing). Six recipes
    /// is therefore a ~3.5 s stall in a Debug build — prefer
    /// `preloadInBackground` if you are warming more than one or two.
    static func preload(
        _ recipes: [Recipe] = Recipe.allCases,
        size: Int = defaultSize,
        seed: UInt64 = defaultSeed
    ) {
        for recipe in recipes {
            maps(recipe, size: size, seed: seed)
        }
    }

    /// The same warm-up with the pixel work moved off the main actor.
    ///
    /// Only the `CGImage` -> `TextureResource` upload is main-actor bound, so
    /// everything expensive runs on a detached task and the first frame draws
    /// on time. Results land in the same cache, so a later `maps(_:)` is a hit.
    ///
    /// Determinism is unaffected: each recipe is an independent pure function
    /// of `(recipe, size, seed)`, so concurrency cannot reorder anything that
    /// matters.
    static func preloadInBackground(
        _ recipes: [Recipe] = Recipe.allCases,
        size: Int = defaultSize,
        seed: UInt64 = defaultSeed
    ) async {
        let resolved = clampSize(size)
        for recipe in recipes {
            let key = Key(recipe: recipe, size: resolved, seed: seed)
            if cache[key] != nil { continue }
            let built = await Task.detached(priority: .userInitiated) {
                surface(for: recipe, size: resolved, seed: seed)
            }.value
            cache[key] = resources(for: recipe, surface: built, size: resolved)
        }
    }

    /// Drops every cached map. Only useful when retuning a recipe live.
    static func clearCache() {
        cache.removeAll()
    }

    /// A repeating, mip-filtered, anisotropic sampler.
    ///
    /// The Metal default is `.clampToEdge`, so a texture bound without this
    /// smears its edge texel across every UV past 1.0 instead of tiling. Always
    /// bind through here or through `apply(_:to:)`.
    static var tilingSampler: MaterialParameters.Texture.Sampler {
        var sampler = MaterialParameters.Texture.Sampler()
        sampler.modify { descriptor in
            descriptor.sAddressMode = .repeat
            descriptor.tAddressMode = .repeat
            descriptor.minFilter = .linear
            descriptor.magFilter = .linear
            descriptor.mipFilter = .linear
            descriptor.maxAnisotropy = 8
        }
        return sampler
    }

    /// Binds a resource with the tiling sampler.
    static func bind(_ resource: TextureResource) -> MaterialParameters.Texture {
        MaterialParameters.Texture(resource, sampler: tilingSampler)
    }

    /// Wires a recipe's maps onto an existing material, leaving anything the
    /// recipe does not provide untouched.
    ///
    /// Fails open: if generation returned nothing, the material keeps whatever
    /// flat tint and scalar roughness it already had.
    static func apply(
        _ recipe: Recipe,
        to material: inout PhysicallyBasedMaterial,
        size: Int = defaultSize,
        seed: UInt64 = defaultSeed,
        includeBaseColor: Bool = true,
        roughnessScale: Float = 1.0,
        emissiveIntensity: Float = 0
    ) {
        let set = maps(recipe, size: size, seed: seed)

        if includeBaseColor, let baseColor = set.baseColor {
            material.baseColor = .init(tint: material.baseColor.tint, texture: bind(baseColor))
        }
        if let normal = set.normal {
            material.normal = .init(texture: bind(normal))
        }
        if let roughness = set.roughness {
            material.roughness = .init(scale: roughnessScale, texture: bind(roughness))
        } else {
            material.roughness = .init(floatLiteral: set.fallbackRoughness * roughnessScale)
        }
        if let metallic = set.metallic {
            material.metallic = .init(scale: 1, texture: bind(metallic))
        } else {
            material.metallic = .init(floatLiteral: set.fallbackMetallic)
        }
        if let occlusion = set.ambientOcclusion {
            material.ambientOcclusion = .init(texture: bind(occlusion))
        }
        if emissiveIntensity > 0, let emissive = set.emissive {
            material.emissiveColor = .init(color: .white, texture: bind(emissive))
            material.emissiveIntensity = emissiveIntensity
        }
    }

    /// A complete textured material for a recipe.
    ///
    /// `tint` multiplies the baked base colour, so a recipe such as
    /// `.crystalline` (authored near-neutral) can be pushed to Lumen gold or
    /// Aether teal without a second texture.
    static func material(
        _ recipe: Recipe,
        tint: UIColor = .white,
        size: Int = defaultSize,
        seed: UInt64 = defaultSeed,
        roughnessScale: Float = 1.0,
        emissiveIntensity: Float = 0
    ) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: tint)
        material.faceCulling = .none
        apply(
            recipe,
            to: &material,
            size: size,
            seed: seed,
            roughnessScale: roughnessScale,
            emissiveIntensity: emissiveIntensity
        )
        return material
    }

    // MARK: Cache

    private struct Key: Hashable {
        var recipe: Recipe
        var size: Int
        var seed: UInt64
    }

    private static var cache: [Key: MapSet] = [:]

    nonisolated private static func clampSize(_ size: Int) -> Int {
        // Powers of two only: mip generation and the wrapped lattice both
        // assume it, and anything above 1024 is wasted at this camera pitch.
        switch size {
        case ..<128: 128
        case ..<256: 256
        case ..<512: 512
        default: 1024
        }
    }

    /// One integer salt per (recipe, layer). Derived through
    /// `DeterministicRandom.stream` so the seed is expanded the same way the
    /// rest of the project expands seeds, but consumed exactly once at build
    /// time — no shared stream is advanced by drawing a texture.
    nonisolated private static func salt(_ recipe: Recipe, _ layer: String, seed: UInt64) -> UInt32 {
        var stream = DeterministicRandom.stream(seed: seed, tag: "texture.\(recipe.rawValue).\(layer)")
        return UInt32(truncatingIfNeeded: stream.next())
    }

    // MARK: Surface description

    /// The CPU-side result of a recipe, before it becomes GPU resources.
    ///
    /// `Sendable` and built by `nonisolated` code on purpose: the pixel work
    /// touches no RealityKit and no shared state, so it can run off the main
    /// actor and hand a finished value back for upload.
    private struct Surface: Sendable {
        var height: [Float]
        var albedo: [SIMD3<Float>]
        var roughness: [Float]
        var metallic: [Float]?
        var emissive: [Float]?
        var detail: [Float]?
        /// Sobel gain. Higher reads as deeper relief.
        var relief: Float
        /// Cavity-AO blur radius as a fraction of the tile.
        var occlusionRadius: Float
        var occlusionStrength: Float
        var fallbackMetallic: Float
        var fallbackRoughness: Float
    }

    private static func build(_ recipe: Recipe, size: Int, seed: UInt64) -> MapSet {
        resources(for: recipe, surface: surface(for: recipe, size: size, seed: seed), size: size)
    }

    /// The whole CPU half of a recipe. Pure, and free of any isolation.
    nonisolated private static func surface(for recipe: Recipe, size: Int, seed: UInt64) -> Surface {
        switch recipe {
        case .regolith: regolith(size: size, seed: seed)
        case .fracturedStone: fracturedStone(size: size, seed: seed)
        case .wovenIvory: wovenIvory(size: size, seed: seed)
        case .oxidisedMetal: oxidisedMetal(size: size, seed: seed)
        case .crystalline: crystalline(size: size, seed: seed)
        case .gildedTrim: gildedTrim(size: size, seed: seed)
        }
    }

    private static func resources(for recipe: Recipe, surface: Surface, size: Int) -> MapSet {
        var set = MapSet(
            fallbackMetallic: surface.fallbackMetallic,
            fallbackRoughness: surface.fallbackRoughness
        )
        let name = recipe.rawValue

        set.baseColor = make(
            ProceduralImage.color(size: size, values: surface.albedo),
            name: "\(name).albedo.\(size)",
            semantic: .color
        )
        set.normal = make(
            ProceduralImage.normalMap(size: size, height: surface.height, strength: surface.relief),
            name: "\(name).normal.\(size)",
            semantic: .normal
        )
        set.roughness = make(
            ProceduralImage.scalar(size: size, values: surface.roughness),
            name: "\(name).roughness.\(size)",
            semantic: .scalar
        )
        if let metallic = surface.metallic {
            set.metallic = make(
                ProceduralImage.scalar(size: size, values: metallic),
                name: "\(name).metallic.\(size)",
                semantic: .scalar
            )
        }
        if let emissive = surface.emissive {
            set.emissive = make(
                ProceduralImage.scalar(size: size, values: emissive),
                name: "\(name).emissive.\(size)",
                semantic: .color
            )
        }
        if let detail = surface.detail {
            set.detail = make(
                ProceduralImage.scalar(size: size, values: detail),
                name: "\(name).detail.\(size)",
                semantic: .scalar
            )
        }

        let radius = max(1, Int((Float(size) * surface.occlusionRadius).rounded()))
        let occlusion = ProceduralImage.occlusion(
            size: size,
            height: surface.height,
            radius: radius,
            strength: surface.occlusionStrength
        )
        set.ambientOcclusion = make(
            ProceduralImage.scalar(size: size, values: occlusion),
            name: "\(name).ao.\(size)",
            semantic: .scalar
        )
        return set
    }

    private static func make(
        _ image: CGImage?,
        name: String,
        semantic: TextureResource.Semantic
    ) -> TextureResource? {
        guard let image else {
            DebugLog.warn("Procedural texture \(name) produced no image; falling back to flat tint.")
            return nil
        }
        do {
            return try TextureResource(
                image: image,
                withName: name,
                options: .init(semantic: semantic, mipmapsMode: .allocateAndGenerateAll)
            )
        } catch {
            DebugLog.warn("Procedural texture \(name) failed to upload (\(error)); falling back to flat tint.")
            return nil
        }
    }

    // MARK: Colour helpers

    nonisolated private static func rgb(_ color: UIColor) -> SIMD3<Float> {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 1
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return SIMD3<Float>(repeating: 0.5)
        }
        return SIMD3<Float>(Float(red), Float(green), Float(blue))
    }

    @inline(__always)
    nonisolated private static func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ t: Float) -> SIMD3<Float> {
        a + (b - a) * max(0, min(1, t))
    }

    /// Allocates the per-pixel buffers a recipe fills.
    nonisolated private static func buffers(_ size: Int) -> (
        height: [Float], albedo: [SIMD3<Float>], roughness: [Float], detail: [Float]
    ) {
        let count = size * size
        return (
            [Float](repeating: 0, count: count),
            [SIMD3<Float>](repeating: .zero, count: count),
            [Float](repeating: 0, count: count),
            [Float](repeating: 0, count: count)
        )
    }

    // MARK: - Recipe: weathered pale regolith

    /// Wind-graded dust over a dune substrate, pocked with small impact pits.
    ///
    /// The read the frame needs from the habitable top is *relief*, not colour
    /// noise: the surface is one flat facet, so all of its shape has to come
    /// from the normal map. Colour variation stays narrow, between the palette's
    /// surface and rock, so the fragment never stops reading as one material.
    nonisolated private static func regolith(size: Int, seed: UInt64) -> Surface {
        var (height, albedo, roughness, detail) = buffers(size)
        let duneSalt = salt(.regolith, "dune", seed: seed)
        let grainSalt = salt(.regolith, "grain", seed: seed)
        let pitSalt = salt(.regolith, "pit", seed: seed)

        let pale = rgb(SunfoldPalette.sunwovenSurface)
        let shade = rgb(SunfoldPalette.sunwovenRock)
        /// Sun-bleached crest. Green pulled 0.895 → 0.880 at CP-06 so the bleach
        /// sits on the same 34° line as the stone family it lightens; left at
        /// 0.895 it was a 43° highlight painted over a 34° ground.
        let dust = SIMD3<Float>(0.925, 0.880, 0.820)

        let inverse = 1 / Float(size)
        for y in 0..<size {
            let v = (Float(y) + 0.5) * inverse
            for x in 0..<size {
                let u = (Float(x) + 0.5) * inverse

                // Broad dunes, then fine wind grain riding on top of them.
                let dune = ProceduralNoise.fbm(u, v, octaves: 4, cellsX: 4, cellsY: 4, salt: duneSalt)
                let grain = ProceduralNoise.fbm(u, v, octaves: 3, cellsX: 32, cellsY: 32, salt: grainSalt)

                // Impact pits: shallow bowls, sparse enough to read as events.
                //
                // They were not sparse. At 12 cells per 4 m tile a pit lands
                // every ~33 cm, which at this camera is a dark dot every ~11 px
                // — a regular polka-dot field, and the single thing that made
                // the ground read as a prototype next to concept 01's ground.
                // `0.62 → 0.76` on the cell gate keeps roughly the sparsest
                // quarter of them, so a pit is an event again rather than a
                // texture.
                let pits = ProceduralNoise.cellular(u, v, cellsX: 12, cellsY: 12, salt: pitSalt)
                let pitMask = 1 - ProceduralNoise.smoothstep(0.0, 0.30, pits.f1)
                let pitDepth = pitMask * ProceduralNoise.smoothstep(0.76, 1.0, pits.cell)

                let h = max(0, min(1, dune * 0.62 + grain * 0.30 - pitDepth * 0.22))

                // Higher ground is sun-bleached; hollows collect darker grit.
                //
                // Both speckle terms are halved from CP-05. Open ground in the
                // build carried a local luma σ of 7.0 against the concept's 5.5
                // at matched apparent scale, and all of the excess was high
                // frequency: fine grain lightening toward `dust`, pits darkening
                // toward `shade`. The *broad* variation — the dune term below —
                // is the part concept 01 actually has, and it is untouched.
                var color = mix(shade, pale, ProceduralNoise.smoothstep(0.15, 0.72, h))
                color = mix(color, dust, grain * 0.17)
                color = mix(color, shade, pitDepth * 0.26)

                let index = y * size + x
                height[index] = h
                albedo[index] = color
                // Powder is uniformly rough; only the pit glass polishes at all.
                roughness[index] = 0.99 - grain * 0.06 - pitDepth * 0.10
                detail[index] = grain
            }
        }

        return Surface(
            height: height,
            albedo: albedo,
            roughness: roughness,
            metallic: nil,
            emissive: nil,
            detail: detail,
            relief: 2.4,
            occlusionRadius: 0.020,
            occlusionStrength: 2.6,
            fallbackMetallic: 0,
            fallbackRoughness: 0.96
        )
    }

    // MARK: - Recipe: cool fractured stone

    /// The fragment's underside and rim: a ridged strata field broken by a
    /// cellular fracture network. Cracks are cut, not painted — they are real
    /// height, so the key light finds them and the AO map darkens inside them.
    nonisolated private static func fracturedStone(size: Int, seed: UInt64) -> Surface {
        var (height, albedo, roughness, detail) = buffers(size)
        let strataSalt = salt(.fracturedStone, "strata", seed: seed)
        let fractureSalt = salt(.fracturedStone, "fracture", seed: seed)
        let grainSalt = salt(.fracturedStone, "grain", seed: seed)

        let stone = rgb(SunfoldPalette.neutralRock)
        let cool = SIMD3<Float>(0.55, 0.575, 0.625)
        let deep = SIMD3<Float>(0.145, 0.160, 0.205)

        let inverse = 1 / Float(size)
        for y in 0..<size {
            let v = (Float(y) + 0.5) * inverse
            for x in 0..<size {
                let u = (Float(x) + 0.5) * inverse

                // Strata run flatter than they are tall — anisotropic on purpose.
                let strata = ProceduralNoise.ridged(u, v, octaves: 4, cellsX: 5, cellsY: 12, salt: strataSalt)
                let grain = ProceduralNoise.fbm(u, v, octaves: 3, cellsX: 26, cellsY: 26, salt: grainSalt)

                // f2 - f1 is zero exactly on a cell boundary: the crack line.
                let cells = ProceduralNoise.cellular(u, v, cellsX: 7, cellsY: 7, salt: fractureSalt)
                let seam = 1 - ProceduralNoise.smoothstep(0.015, 0.11, cells.f2 - cells.f1)
                // Each block sits at its own level, so faces step against each other.
                let block = (cells.cell - 0.5) * 0.20

                let h = max(0, min(1, 0.52 + strata * 0.30 + block + grain * 0.12 - seam * 0.52))

                var color = mix(stone, cool, 0.46)
                color = mix(color, color * 1.16, ProceduralNoise.smoothstep(0.45, 0.95, h))
                color = mix(color, deep, seam * 0.78)
                color = mix(color, color * (0.92 + cells.cell * 0.16), 0.5)

                let index = y * size + x
                height[index] = h
                albedo[index] = color
                roughness[index] = 0.97 - grain * 0.10 + seam * 0.03
                detail[index] = seam
            }
        }

        return Surface(
            height: height,
            albedo: albedo,
            roughness: roughness,
            metallic: nil,
            emissive: nil,
            detail: detail,
            relief: 3.4,
            occlusionRadius: 0.016,
            occlusionStrength: 3.4,
            fallbackMetallic: 0,
            fallbackRoughness: 0.97
        )
    }

    // MARK: - Recipe: woven ivory fabric

    /// Plain weave: warp over weft, weft over warp, alternating every cell.
    ///
    /// The thread is modelled as a cosine bulge across its own width, so the
    /// normal map produces a real over/under interlace rather than a printed
    /// checker. Per-thread tone variation keeps it from reading as a decal.
    nonisolated private static func wovenIvory(size: Int, seed: UInt64) -> Surface {
        var (height, albedo, roughness, detail) = buffers(size)
        let toneSalt = salt(.wovenIvory, "tone", seed: seed)
        let fibreSalt = salt(.wovenIvory, "fibre", seed: seed)
        let wearSalt = salt(.wovenIvory, "wear", seed: seed)

        // 48 threads per tile: fine enough to read as cloth at the game's
        // camera distance, coarse enough to survive mip level 2.
        let threads = 48
        let ivory = rgb(SunfoldPalette.sunwovenIvory)
        let shadowed = rgb(SunfoldPalette.sunwovenSurface)
        let gold = rgb(SunfoldPalette.sunwovenGold)

        let inverse = 1 / Float(size)
        for y in 0..<size {
            let v = (Float(y) + 0.5) * inverse
            for x in 0..<size {
                let u = (Float(x) + 0.5) * inverse

                let tu = u * Float(threads)
                let tv = v * Float(threads)
                let iu = Int(tu.rounded(.down))
                let iv = Int(tv.rounded(.down))
                let fu = tu - Float(iu)
                let fv = tv - Float(iv)

                // Cosine cross-section: 0 at the thread edge, 1 at its crown.
                let warpCrown = sin(.pi * fu)
                let weftCrown = sin(.pi * fv)
                let warpOver = (ProceduralNoise.wrap(iu, threads) + ProceduralNoise.wrap(iv, threads)) % 2 == 0

                var h = warpOver
                    ? 0.58 + warpCrown * 0.40
                    : 0.20 + weftCrown * 0.36

                // Kept below Nyquist at 512: the finest octave is ~5 px, so it
                // survives mipping instead of dissolving into grey.
                let fibre = ProceduralNoise.fbm(u, v, octaves: 2, cellsX: threads, cellsY: threads / 2, salt: fibreSalt)
                h += (fibre - 0.5) * 0.10
                h = max(0, min(1, h))

                // Every thread is dyed very slightly differently.
                let threadTone = warpOver
                    ? ProceduralNoise.hash(ProceduralNoise.wrap(iu, threads), 0, toneSalt)
                    : ProceduralNoise.hash(0, ProceduralNoise.wrap(iv, threads), toneSalt)

                var color = mix(ivory, shadowed, 0.10 + (1 - h) * 0.34)
                color = mix(color, color * (0.94 + threadTone * 0.12), 0.85)
                // A whisper of gold in the weave, not a stripe.
                let wear = ProceduralNoise.fbm(u, v, octaves: 3, cellsX: 5, cellsY: 5, salt: wearSalt)
                color = mix(color, gold, ProceduralNoise.smoothstep(0.72, 1.0, wear) * 0.16)
                color = mix(color, color * 0.86, (1 - fibre) * 0.10)

                let index = y * size + x
                height[index] = h
                albedo[index] = color
                // Thread crowns catch a soft sheen; the valleys stay matte.
                roughness[index] = 0.78 - max(warpCrown, weftCrown) * 0.20 + (1 - h) * 0.10
                detail[index] = fibre
            }
        }

        return Surface(
            height: height,
            albedo: albedo,
            roughness: roughness,
            metallic: nil,
            emissive: nil,
            detail: detail,
            relief: 1.6,
            occlusionRadius: 0.010,
            occlusionStrength: 3.0,
            fallbackMetallic: 0,
            fallbackRoughness: 0.70
        )
    }

    // MARK: - Recipe: brushed, oxidised metal with copper seams

    /// Gravemark plate: cold rolled steel, brushed along one axis, oxidising in
    /// patches, panelled by copper weld seams.
    ///
    /// Brushing is anisotropic noise — many cells across the streak direction,
    /// few along it. That single asymmetry is what separates brushed metal from
    /// noisy metal.
    nonisolated private static func oxidisedMetal(size: Int, seed: UInt64) -> Surface {
        var (height, albedo, roughness, detail) = buffers(size)
        var metallic = [Float](repeating: 0, count: size * size)
        let brushSalt = salt(.oxidisedMetal, "brush", seed: seed)
        let oxideSalt = salt(.oxidisedMetal, "oxide", seed: seed)
        let panelSalt = salt(.oxidisedMetal, "panel", seed: seed)
        let pitSalt = salt(.oxidisedMetal, "pit", seed: seed)

        let steel = rgb(SunfoldPalette.gravemarkSurface)
        let dark = rgb(SunfoldPalette.gravemarkRock)
        let copper = rgb(SunfoldPalette.gravemarkCopper)
        let oxide = SIMD3<Float>(0.235, 0.290, 0.300)

        let inverse = 1 / Float(size)
        for y in 0..<size {
            let v = (Float(y) + 0.5) * inverse
            for x in 0..<size {
                let u = (Float(x) + 0.5) * inverse

                // Streaks run along +U: dense across V, sparse across U. The
                // finest octave lands at ~3.5 px so the brush survives mipping.
                let brush = ProceduralNoise.fbm(u, v, octaves: 2, cellsX: 3, cellsY: 72, salt: brushSalt)
                let pits = ProceduralNoise.fbm(u, v, octaves: 2, cellsX: 40, cellsY: 40, salt: pitSalt)

                // Panel seams, with copper laid into the joint.
                let panels = ProceduralNoise.cellular(u, v, cellsX: 4, cellsY: 4, jitter: 0.55, salt: panelSalt)
                let seam = 1 - ProceduralNoise.smoothstep(0.010, 0.075, panels.f2 - panels.f1)

                // Oxidation creeps outward from the seams, as it does in life.
                let bloom = ProceduralNoise.fbm(u, v, octaves: 4, cellsX: 6, cellsY: 6, salt: oxideSalt)
                let oxidation = max(0, min(1, ProceduralNoise.smoothstep(0.44, 0.78, bloom) * 0.85 + seam * 0.45))

                let h = max(0, min(1, 0.62 + (brush - 0.5) * 0.16 + (pits - 0.5) * 0.10 - seam * 0.40))

                var color = mix(steel, dark, (1 - brush) * 0.34)
                color = mix(color, oxide, oxidation * 0.62)
                color = mix(color, copper, seam * 0.80)

                let index = y * size + x
                height[index] = h
                albedo[index] = color
                // Oxide is dielectric and rough; bare metal is neither.
                metallic[index] = max(0, min(1, (1 - oxidation) * 0.92 + seam * 0.45))
                roughness[index] = 0.30 + brush * 0.16 + oxidation * 0.46
                detail[index] = oxidation
            }
        }

        return Surface(
            height: height,
            albedo: albedo,
            roughness: roughness,
            metallic: metallic,
            emissive: nil,
            detail: detail,
            relief: 2.0,
            occlusionRadius: 0.014,
            occlusionStrength: 3.2,
            fallbackMetallic: 0.85,
            fallbackRoughness: 0.42
        )
    }

    // MARK: - Recipe: crystalline mineral

    /// Lumen and Aether deposits: a faceted cellular crystal whose cell
    /// boundaries glow.
    ///
    /// Authored near-neutral on purpose. One recipe serves both resources; the
    /// caller supplies the hue through `material(_:tint:)` and through
    /// `EmissiveColor.color`, so Lumen gold and Aether teal never drift apart
    /// from the same rock.
    nonisolated private static func crystalline(size: Int, seed: UInt64) -> Surface {
        var (height, albedo, roughness, detail) = buffers(size)
        var emissive = [Float](repeating: 0, count: size * size)
        let facetSalt = salt(.crystalline, "facet", seed: seed)
        let microSalt = salt(.crystalline, "micro", seed: seed)
        let veinSalt = salt(.crystalline, "vein", seed: seed)

        let pale = SIMD3<Float>(0.880, 0.895, 0.930)
        let core = SIMD3<Float>(0.640, 0.700, 0.790)

        let inverse = 1 / Float(size)
        for y in 0..<size {
            let v = (Float(y) + 0.5) * inverse
            for x in 0..<size {
                let u = (Float(x) + 0.5) * inverse

                // f1 rising away from the feature point makes a cone; cones
                // packed on a jittered grid read as a broken crystal face.
                let facets = ProceduralNoise.cellular(u, v, cellsX: 6, cellsY: 6, jitter: 0.9, salt: facetSalt)
                let micro = ProceduralNoise.cellular(u, v, cellsX: 18, cellsY: 18, jitter: 0.8, salt: microSalt)

                let facetHeight = 1 - min(1, facets.f1 * 1.35)
                let microHeight = 1 - min(1, micro.f1 * 1.30)
                let h = max(0, min(1, facetHeight * 0.72 + microHeight * 0.24 + facets.cell * 0.10))

                // Light pools in the fissures between crystals.
                let fissure = 1 - ProceduralNoise.smoothstep(0.0, 0.14, facets.f2 - facets.f1)
                let vein = ProceduralNoise.fbm(u, v, octaves: 3, cellsX: 9, cellsY: 9, salt: veinSalt)
                let glow = max(0, min(1, fissure * 0.9 + ProceduralNoise.smoothstep(0.70, 1.0, vein) * 0.55))

                var color = mix(core, pale, ProceduralNoise.smoothstep(0.20, 0.90, h))
                color = mix(color, color * (0.88 + facets.cell * 0.24), 0.7)
                color = mix(color, SIMD3<Float>(repeating: 1.0), glow * 0.35)

                let index = y * size + x
                height[index] = h
                albedo[index] = color
                emissive[index] = glow
                // Crystal is dielectric, but polished: low roughness on facets,
                // frosted where the micro-cells break the surface up.
                roughness[index] = 0.16 + (1 - facetHeight) * 0.34 + (1 - microHeight) * 0.12
                detail[index] = fissure
            }
        }

        return Surface(
            height: height,
            albedo: albedo,
            roughness: roughness,
            // Crystal is a dielectric everywhere, so a metallic map would be a
            // uniformly zero texture — the scalar fallback says the same thing.
            metallic: nil,
            emissive: emissive,
            detail: detail,
            relief: 4.2,
            occlusionRadius: 0.014,
            occlusionStrength: 2.4,
            fallbackMetallic: 0,
            fallbackRoughness: 0.30
        )
    }

    // MARK: - Recipe: burnished gold trim

    /// Hand-burnished gold: very fine unidirectional polish marks, a slow
    /// large-scale tarnish variation, and almost no relief.
    ///
    /// Trim reads as gold because of how it varies *specularly*, not because of
    /// its colour — so the roughness map does nearly all the work here and the
    /// height map is kept shallow on purpose.
    nonisolated private static func gildedTrim(size: Int, seed: UInt64) -> Surface {
        var (height, albedo, roughness, detail) = buffers(size)
        var metallic = [Float](repeating: 0, count: size * size)
        let polishSalt = salt(.gildedTrim, "polish", seed: seed)
        let tarnishSalt = salt(.gildedTrim, "tarnish", seed: seed)
        let dingSalt = salt(.gildedTrim, "ding", seed: seed)

        let gold = rgb(SunfoldPalette.sunwovenGold)
        let bright = SIMD3<Float>(0.980, 0.870, 0.560)
        let tarnished = SIMD3<Float>(0.470, 0.352, 0.158)

        let inverse = 1 / Float(size)
        for y in 0..<size {
            let v = (Float(y) + 0.5) * inverse
            for x in 0..<size {
                let u = (Float(x) + 0.5) * inverse

                // Polish marks: fine across V, near-constant along U. Capped at
                // ~4 px on the finest octave for the same anti-alias reason.
                let polish = ProceduralNoise.fbm(u, v, octaves: 2, cellsX: 2, cellsY: 64, salt: polishSalt)
                let tarnish = ProceduralNoise.fbm(u, v, octaves: 4, cellsX: 4, cellsY: 4, salt: tarnishSalt)
                let dings = ProceduralNoise.cellular(u, v, cellsX: 16, cellsY: 16, salt: dingSalt)
                let ding = (1 - ProceduralNoise.smoothstep(0.0, 0.16, dings.f1))
                    * ProceduralNoise.smoothstep(0.80, 1.0, dings.cell)

                let h = max(0, min(1, 0.70 + (polish - 0.5) * 0.10 - ding * 0.55))

                var color = mix(gold, bright, ProceduralNoise.smoothstep(0.40, 0.95, polish) * 0.55)
                color = mix(color, tarnished, ProceduralNoise.smoothstep(0.52, 0.92, tarnish) * 0.48)
                color = mix(color, tarnished, ding * 0.60)

                let index = y * size + x
                height[index] = h
                albedo[index] = color
                metallic[index] = max(0, min(1, 1.0 - ding * 0.35))
                roughness[index] = 0.14 + polish * 0.13 + tarnish * 0.22 + ding * 0.30
                detail[index] = tarnish
            }
        }

        return Surface(
            height: height,
            albedo: albedo,
            roughness: roughness,
            metallic: metallic,
            emissive: nil,
            detail: detail,
            relief: 1.1,
            occlusionRadius: 0.012,
            occlusionStrength: 2.0,
            fallbackMetallic: 1.0,
            fallbackRoughness: 0.24
        )
    }
}
