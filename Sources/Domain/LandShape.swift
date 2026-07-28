import Foundation
import simd

/// Deterministic scalar noise for shaping coastlines and water edges.
///
/// `Sources/Domain` may not reach into `Sources/Rendering`, so this cannot be
/// `ProceduralNoise`. More importantly it must not be `DeterministicRandom`:
/// that is a *stream*, and a stream's answer depends on how many draws preceded
/// it. The coastline is asked "is this point land?" by the mesh factory, the
/// minimap, the movement rules and the deposit placer, in different orders on
/// different frames, and every one of them must get the same answer. So this is
/// a pure function of position — no state, no draw order, no stream to perturb.
enum LandNoise {

    /// A well-mixed hash of two integer lattice coordinates, in `0 ..< 1`.
    static func hash(_ x: Int32, _ y: Int32, _ salt: UInt32) -> Float {
        var h = UInt32(bitPattern: x) &* 0x27d4_eb2d
        h ^= UInt32(bitPattern: y) &* 0x1656_67b1
        h ^= salt &* 0x9e37_79b9
        h ^= h >> 15
        h = h &* 0x85eb_ca6b
        h ^= h >> 13
        h = h &* 0xc2b2_ae35
        h ^= h >> 16
        return Float(h) / Float(UInt32.max)
    }

    /// Smooth value noise in `-1 ... 1`. `cell` is the lattice spacing in metres,
    /// so callers think in "how long is a wobble" rather than in cell counts.
    static func value(_ point: WorldPoint, cell: Float, salt: UInt32) -> Float {
        let scaled = point / max(cell, 0.001)
        let base = SIMD2<Float>(scaled.x.rounded(.down), scaled.y.rounded(.down))
        let frac = scaled - base
        let ix = Int32(base.x), iy = Int32(base.y)

        // Smoothstep the interpolant, not the samples: bilinear alone leaves
        // visible lattice creases along every cell boundary, which on a coastline
        // reads as a grid rather than as erosion.
        let ease = frac * frac * (3 - 2 * frac)

        let a = hash(ix, iy, salt), b = hash(ix &+ 1, iy, salt)
        let c = hash(ix, iy &+ 1, salt), d = hash(ix &+ 1, iy &+ 1, salt)
        let top = a + (b - a) * ease.x
        let bottom = c + (d - c) * ease.x
        return (top + (bottom - top) * ease.y) * 2 - 1
    }

    /// Layered ``value`` noise. Two or three octaves is enough here — the shapes
    /// are authored, and this only has to stop their edges reading as analytic.
    static func fbm(_ point: WorldPoint, cell: Float, octaves: Int, salt: UInt32) -> Float {
        var total: Float = 0
        var amplitude: Float = 1
        var normalizer: Float = 0
        var spacing = cell
        for octave in 0..<max(octaves, 1) {
            total += value(point, cell: spacing, salt: salt &+ UInt32(octave) &* 7919) * amplitude
            normalizer += amplitude
            amplitude *= 0.5
            spacing *= 0.5
        }
        return total / max(normalizer, 0.001)
    }

    /// Mixes a map seed into an authored salt.
    ///
    /// The authored constant says *which* feature this is — this plate's fray,
    /// that river's wander — and the seed says which world we are in. Combining
    /// them means one seed change re-rolls every coastline on the map at once
    /// while the layout's intent survives, which is what "randomized" has to mean
    /// for a game whose replays are seed-locked.
    static func salt(_ authored: UInt32, seed: UInt64) -> UInt32 {
        var mixed = authored ^ UInt32(truncatingIfNeeded: seed)
        mixed ^= UInt32(truncatingIfNeeded: seed >> 32) &* 0x9e37_79b9
        mixed ^= mixed >> 16
        return mixed &* 0x7feb_352d
    }
}

/// The authored outline of one land plate, as a radial profile.
///
/// A plate used to be a circle with the mesh factory adding outward-only jitter.
/// That could never produce a bay: jitter that only grows cannot cut into the
/// disc, so every silhouette stayed convex and seven of them overlapping read as
/// exactly what they were — overlapping circles. A short sum of angular
/// harmonics fixes that at the source. Harmonic 2 makes a plate oval, 3 makes it
/// a rounded triangle with three capes, 5 makes a starfish of headlands, and the
/// combination gives the lopsided, bay-and-promontory outline a coast has.
///
/// Kept star-shaped on purpose (`reach` is a single radius per bearing). It is
/// what lets the rest of the engine stay radial — the mesh grid, `RimProfile`,
/// the rim walk in `dockPoint` — while the *silhouette* stops being a circle.
/// Concavity that a star shape cannot express is exactly the job of ``VoidBody``.
struct CoastProfile: Sendable, Equatable {

    /// One angular harmonic of the outline.
    struct Lobe: Sendable, Equatable {
        /// How many bulges the term puts around the full turn.
        let harmonic: Float
        /// Reach as a fraction of the nominal radius.
        let amplitude: Float
        /// Where the first bulge points, in radians.
        let phase: Float

        init(_ harmonic: Float, _ amplitude: Float, _ phase: Float) {
            self.harmonic = harmonic
            self.amplitude = amplitude
            self.phase = phase
        }
    }

    var lobes: [Lobe]
    /// How much the coastline frays between the authored lobes, as a fraction of
    /// the nominal radius.
    var fray: Float
    /// Wavelength of that fraying, in metres.
    var frayScale: Float
    var salt: UInt32

    init(
        lobes: [Lobe] = [],
        fray: Float = 0.05,
        frayScale: Float = 26,
        salt: UInt32 = 0x51ED_2C17
    ) {
        self.lobes = lobes
        self.fray = fray
        self.frayScale = frayScale
        self.salt = salt
    }

    /// A plain disc. Only used where a plate genuinely wants no character.
    static let round = CoastProfile(lobes: [], fray: 0.03)

    /// The same outline rotated by 180°.
    ///
    /// Rotating `cos(h·θ + φ)` by π gives `cos(h·θ + φ + h·π)`, which is a phase
    /// shift for odd harmonics and a no-op for even ones. Mirrored pairs are
    /// authored through this rather than by eye — the two sides no longer have to
    /// be identical, but a plate and its opposite number should still be the same
    /// *size and character*, and this is how that stays true when one is edited.
    var halfTurned: CoastProfile {
        CoastProfile(
            lobes: lobes.map { Lobe($0.harmonic, $0.amplitude, $0.phase + $0.harmonic * .pi) },
            fray: fray,
            frayScale: frayScale,
            salt: salt
        )
    }

    /// The sum of every lobe's reach. Under 1 the outline stays star-shaped and
    /// strictly positive, which the whole radial pipeline depends on.
    var totalAmplitude: Float { lobes.reduce(0) { $0 + abs($1.amplitude) } + abs(fray) }

    /// Radius multiplier at a bearing, measured as `atan2(offset.y, offset.x)` —
    /// the same convention the mesh lays its vertices on and `RimProfile` reads.
    ///
    /// `center` and `nominal` are only needed to place the fray in world space so
    /// that folding it can keep the map fair.
    func reach(atBearing bearing: Float, center: WorldPoint, nominal: Float) -> Float {
        var reach: Float = 1
        for lobe in lobes {
            reach += lobe.amplitude * cos(lobe.harmonic * bearing + lobe.phase)
        }
        if fray != 0 {
            let rim = center + WorldPoint(cos(bearing), sin(bearing)) * nominal
            reach += fray * LandNoise.fbm(
                rim,
                cell: frayScale,
                octaves: 2,
                salt: salt
            )
        }
        // Never let an authored mistake collapse a plate to a point or invert it.
        return min(max(reach, 0.25), 1.9)
    }
}

/// A perturbation applied to the **whole** land field rather than to one plate.
///
/// This is what stops a map reading as overlapping circles, and it is worth being
/// precise about why the per-plate ``CoastProfile/fray`` could not do it. Land is
/// the union of seven star-shaped plates. A star profile is authored around one
/// centre, so however far its lobes and fray bend it, its boundary is still a
/// single radius per bearing *about that centre* — a closed, convex-ish blob. Union
/// seven blobs and the silhouette is seven blobs, because the only places their
/// outlines meet are the notches where two of them cross. The eye reads those
/// notches as exactly what they are: circles overlapping.
///
/// Erosion works on the union instead. The land field is signed — metres inside
/// the coast — so adding a noise field to it moves the shoreline in and out by
/// metres *wherever the shoreline happens to be*, with no knowledge of which plate
/// put it there. Inland the field is tens of metres deep and nothing changes; only
/// the coast moves. That does three things a per-plate profile cannot: it carries
/// one continuous grain across a plate seam instead of two profiles meeting at a
/// kink, it can cut a genuinely **concave** bay into a star shape, and it can span
/// a shallow waist so two plates fuse into one headland rather than reading as a
/// figure-eight.
struct LandErosion: Sendable, Equatable {
    /// How far the shoreline moves, in metres. This is a real displacement, so it
    /// should be read against plate radius: 6 m on a 42 m plate is a coast that
    /// wanders by about a seventh of the way in.
    var amplitude: Float
    /// Wavelength of the coarsest octave, in metres — the size of the biggest
    /// bay or headland this adds.
    var scale: Float
    /// Each octave halves the wavelength and the amplitude, so three octaves at
    /// `scale: 40` puts detail at 40 m, 20 m and 10 m. Coastlines want more than
    /// one scale of detail; that is most of what separates a drawn coast from a
    /// procedural one.
    var octaves: Int
    /// A constant added alongside the noise. Negative shrinks every coast evenly,
    /// which is how a layout buys back the area the amplitude adds.
    var bias: Float
    var salt: UInt32

    init(
        amplitude: Float,
        scale: Float = 40,
        octaves: Int = 3,
        bias: Float = 0,
        salt: UInt32 = 0x6D2B_79F5
    ) {
        self.amplitude = amplitude
        self.scale = scale
        self.octaves = octaves
        self.bias = bias
        self.salt = salt
    }

    /// No erosion. The land is exactly the union of the authored plates.
    static let none = LandErosion(amplitude: 0)

    /// Metres to add to the signed land field at `point`. Folded, so a map built
    /// on it is exactly fair under a half-turn.
    func displacement(at point: WorldPoint) -> Float {
        guard amplitude != 0 else { return bias }
        return bias + amplitude * LandNoise.fbm(
            point,
            cell: scale,
            octaves: octaves,
            salt: salt
        )
    }
}

/// A body of void carved out of the land: a river, a lake, a sea inlet.
///
/// This is the piece the old map had no way to express. Space is this game's
/// water, and water in an Age-of-Empires-shaped map is not only the ocean around
/// the edge — it is the river you ferry across, the lake you build around, the
/// fjord that makes a peninsula defensible. Those are all *subtractions* from a
/// landmass, and a union of discs has no subtraction in it.
///
/// A body reports a signed depth, so the same authored shape serves the legality
/// test, the carved mesh, the bank geometry and the minimap contour. One shape,
/// one answer, no chance of the render disagreeing with the rules.
struct VoidBody: Sendable {

    enum Form: Sendable {
        /// A lake or an open basin. `outline` shapes it the same way a
        /// ``CoastProfile`` shapes a plate — a lake authored as a bare radius is a
        /// perfect circle punched in the ground, which is the same complaint as
        /// circular islands with the sign flipped.
        case basin(center: WorldPoint, radius: Float, outline: CoastProfile)
        /// A river, strait or inlet: a polyline with a half-width at each node,
        /// interpolated along the run so a channel can widen into a mouth.
        case channel(path: [WorldPoint], halfWidths: [Float])
    }

    let form: Form
    /// How far the water's edge wanders off the authored shape, in metres.
    let wander: Float
    /// Wavelength of that wander, in metres.
    let wanderScale: Float
    let salt: UInt32

    init(form: Form, wander: Float = 3.4, wanderScale: Float = 22, salt: UInt32 = 0x2F1B_9D07) {
        self.form = form
        self.wander = wander
        self.wanderScale = wanderScale
        self.salt = salt
    }

    static func basin(
        at center: WorldPoint,
        radius: Float,
        outline: CoastProfile = CoastProfile(lobes: [], fray: 0),
        wander: Float = 4.5,
        wanderScale: Float = 30,
        salt: UInt32 = 0x2F1B_9D07
    ) -> VoidBody {
        VoidBody(
            form: .basin(center: center, radius: radius, outline: outline),
            wander: wander,
            wanderScale: wanderScale,
            salt: salt
        )
    }

    static func channel(
        _ path: [WorldPoint],
        halfWidths: [Float],
        wander: Float = 3.0,
        wanderScale: Float = 20,
        salt: UInt32 = 0x7A3C_11E5
    ) -> VoidBody {
        precondition(
            path.count == halfWidths.count && path.count >= 2,
            "A channel needs at least two nodes and one half-width each."
        )
        return VoidBody(
            form: .channel(path: path, halfWidths: halfWidths),
            wander: wander,
            wanderScale: wanderScale,
            salt: salt
        )
    }

    /// The same body rotated by 180°, for authoring mirrored pairs.
    var halfTurned: VoidBody {
        let turned: Form
        switch form {
        case let .basin(center, radius, outline):
            turned = .basin(center: -center, radius: radius, outline: outline.halfTurned)
        case let .channel(path, halfWidths):
            turned = .channel(path: path.map { -$0 }, halfWidths: halfWidths)
        }
        return VoidBody(form: turned, wander: wander, wanderScale: wanderScale, salt: salt)
    }

    /// Metres of water at `point`: positive inside the body, zero at the bank,
    /// negative on dry land. Magnitude is a distance, so callers can ask for a
    /// margin ("10 m clear of any water") in the units they already think in.
    func depth(at point: WorldPoint) -> Float {
        let raw: Float
        switch form {
        case let .basin(center, radius, outline):
            let offset = point - center
            let reach = outline.reach(
                atBearing: atan2(offset.y, offset.x),
                center: center,
                nominal: radius
            )
            raw = radius * reach - simd_length(offset)
        case let .channel(path, halfWidths):
            var best = -Float.greatestFiniteMagnitude
            for index in 0..<(path.count - 1) {
                let a = path[index], b = path[index + 1]
                let span = b - a
                let lengthSquared = simd_length_squared(span)
                let t: Float = lengthSquared < 1e-6
                    ? 0
                    : min(max(simd_dot(point - a, span) / lengthSquared, 0), 1)
                let closest = a + span * t
                let halfWidth = halfWidths[index] + (halfWidths[index + 1] - halfWidths[index]) * t
                best = max(best, halfWidth - simd_distance(point, closest))
            }
            raw = best
        }

        guard wander != 0 else { return raw }
        return raw + wander * LandNoise.fbm(
            point,
            cell: wanderScale,
            octaves: 2,
            salt: salt
        )
    }
}
