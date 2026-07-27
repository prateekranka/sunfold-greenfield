import Foundation
import simd

/// Texture-coordinate generation for the project's hand-built meshes.
///
/// Every mesh in Sunfold is authored in code and, until this file existed, none
/// of them carried texture coordinates — so no material could sample a texture,
/// and a normal map had nothing to align to. This is the shared vocabulary the
/// mesh factories adopt to fix that.
///
/// # Why projection rather than an unwrap
/// Nothing here is UV-unwrapped by an artist; the geometry is generated. A
/// *projection* is therefore the only honest option: a pure function from an
/// object-space point to a UV. That also means it consumes no randomness and
/// cannot perturb any `DeterministicRandom` stream (architecture rule 5).
///
/// # Object space, metres, and consistent texel density
/// Every projection is measured in the mesh's own object space, in metres, and
/// tiling is expressed as `metersPerTile`. A 7 m farm and a 40 m fragment
/// sharing one `metersPerTile` therefore get the *same* texel density, which is
/// what stops a small prop looking like coarse gravel next to fine sand.
///
/// # Pure Swift on purpose
/// Only Foundation and simd. No RealityKit, so the maths is trivially testable
/// and the file could move under `Sources/Simulation` unchanged if it ever
/// needed to (it does not — it is renderer-only by intent).
struct MeshUVProjection: Equatable, Sendable {

    /// The rule that maps a surface point to a UV.
    enum Mode: Equatable, Sendable {
        /// No coordinates emitted — the pre-texturing behaviour, and the default
        /// so adopting this type is opt-in per factory.
        case none
        /// Per-face planar projection onto the plane of the face normal's
        /// **dominant axis** (classic box / triplanar-without-the-blend mapping).
        /// Faces sharing a dominant axis share a basis *and* an origin, so the
        /// pattern is continuous across them.
        case box
        /// Per-face planar projection onto the face's **own** plane. Zero texel
        /// stretch on any slant, at the cost of a UV break at each facet — which
        /// on this project's deliberately faceted rock reads as a different rock
        /// face rather than as an error.
        case facePlanar
        /// U wraps around `axis`, V runs along it. For masts, stacks, spindles,
        /// pylons and hull barrels.
        case cylindrical
        /// U is the azimuth about `axis`, V the polar angle. For domes, bell
        /// roofs, motes and boulders.
        case spherical
    }

    private(set) var mode: Mode
    /// Metres of surface per texture tile along a linear axis.
    private(set) var metersPerTile: Float
    /// Pole axis for `.cylindrical` / `.spherical`, unit length.
    private(set) var axis: SIMD3<Float>
    /// Object-space origin the projection is measured from.
    private(set) var center: SIMD3<Float>
    /// Texture tiles per full turn about `axis` (`.cylindrical` / `.spherical` U).
    private(set) var tilesAround: Float
    /// Texture tiles from pole to pole (`.spherical` V).
    private(set) var tilesOver: Float

    private init(
        mode: Mode,
        metersPerTile: Float,
        axis: SIMD3<Float>,
        center: SIMD3<Float>,
        tilesAround: Float,
        tilesOver: Float
    ) {
        self.mode = mode
        self.metersPerTile = max(metersPerTile, 1e-4)
        self.axis = MeshUV.direction(axis, fallback: [0, 1, 0])
        self.center = center
        self.tilesAround = tilesAround
        self.tilesOver = tilesOver
    }

    /// Emits nothing. Meshes built with this are byte-for-byte what they were
    /// before texturing existed.
    static let none = MeshUVProjection(
        mode: .none, metersPerTile: 1, axis: [0, 1, 0],
        center: .zero, tilesAround: 1, tilesOver: 1
    )

    /// Per-face planar projection onto the dominant axis of the face normal.
    ///
    /// The safe default for boxy, axis-aligned structure geometry: plates,
    /// kerbs, slabs, decks. Slanted faces are stretched by `1 / cos θ` against
    /// their dominant axis — use ``facePlanar(metersPerTile:)`` where that shows.
    static func box(metersPerTile: Float) -> MeshUVProjection {
        MeshUVProjection(
            mode: .box, metersPerTile: metersPerTile, axis: [0, 1, 0],
            center: .zero, tilesAround: 1, tilesOver: 1
        )
    }

    /// Per-face planar projection onto the face's own plane. No stretch at any
    /// angle. The right choice for craggy, arbitrarily-angled rock.
    static func facePlanar(metersPerTile: Float) -> MeshUVProjection {
        MeshUVProjection(
            mode: .facePlanar, metersPerTile: metersPerTile, axis: [0, 1, 0],
            center: .zero, tilesAround: 1, tilesOver: 1
        )
    }

    /// U wraps `tilesAround` tiles around `axis`; V advances one tile every
    /// `metersPerTile` along it.
    static func cylindrical(
        metersPerTile: Float,
        tilesAround: Float = 4,
        axis: SIMD3<Float> = [0, 1, 0],
        center: SIMD3<Float> = .zero
    ) -> MeshUVProjection {
        MeshUVProjection(
            mode: .cylindrical, metersPerTile: metersPerTile, axis: axis,
            center: center, tilesAround: max(tilesAround, 1e-4), tilesOver: 1
        )
    }

    /// U wraps `tilesAround` tiles about `axis`; V runs `tilesOver` tiles from
    /// pole to pole. Independent of radius, so a dome and a mote tile alike.
    static func spherical(
        tilesAround: Float = 4,
        tilesOver: Float = 2,
        axis: SIMD3<Float> = [0, 1, 0],
        center: SIMD3<Float> = .zero
    ) -> MeshUVProjection {
        MeshUVProjection(
            mode: .spherical, metersPerTile: 1, axis: axis,
            center: center, tilesAround: max(tilesAround, 1e-4),
            tilesOver: max(tilesOver, 1e-4)
        )
    }

    /// Whether this projection produces coordinates at all.
    var isEnabled: Bool { mode != .none }

    /// The same projection re-anchored, for a sub-part built away from the
    /// object origin (a stack at `[-0.92, 3.1, -0.85]`, a claw arm, a mast).
    func centered(at center: SIMD3<Float>) -> MeshUVProjection {
        var copy = self
        copy.center = center
        return copy
    }

    /// The same projection about a different pole, for a cylinder that is not
    /// vertical — a drill boom, a stay line, a lofted hull.
    func aligned(to axis: SIMD3<Float>) -> MeshUVProjection {
        var copy = self
        copy.axis = MeshUV.direction(axis, fallback: [0, 1, 0])
        return copy
    }
}

// MARK: - Generation

/// The UV and tangent-frame maths. Stateless and deterministic.
///
/// # Tangents are not optional — verified, not assumed
/// The iOS 26.5 RealityKit SDK exposes **no** tangent generation.
/// `MeshResource.generate(from: [MeshDescriptor])` takes no options
/// (`RealityFoundation.swiftinterface:7996`), and the only tangent knob in the
/// whole interface is `__MeshCompileOptions.repairTangents` (`:13952`), a
/// double-underscore SPI class that `generate(from:)` gives no way to reach.
/// `MeshDescriptor.tangents` / `.bitangents` (`:6878`, `:6882`) are therefore the
/// only path, and any material with a `normal` map must be fed a tangent frame
/// built here or it will be lit with a garbage basis.
///
/// Because every projection defines its own surface basis, the tangent frame is
/// *free* at generation time — ``face(_:_:_:normal:projection:)`` returns it
/// alongside the coordinates. ``tangentBasis(positions:normals:textureCoordinates:indices:)``
/// exists for the other case: UVs that already exist and whose basis is unknown.
enum MeshUV {

    // MARK: Per-face generation

    /// One triangle's coordinates plus the surface basis they were built on.
    ///
    /// `tangent` points along +U and `bitangent` along +V, so
    /// `(tangent, bitangent, normal)` is the right-handed frame a tangent-space
    /// normal map expects.
    struct Face: Equatable, Sendable {
        var a: SIMD2<Float>
        var b: SIMD2<Float>
        var c: SIMD2<Float>
        var tangent: SIMD3<Float>
        var bitangent: SIMD3<Float>
    }

    /// Projects one triangle. Returns `nil` for `.none`, which is what lets a
    /// builder skip the whole UV path with no branching at the call site.
    ///
    /// `normal` is the face normal the builder already computed; if it is
    /// degenerate the geometric normal of `a, b, c` is used instead.
    static func face(
        _ a: SIMD3<Float>,
        _ b: SIMD3<Float>,
        _ c: SIMD3<Float>,
        normal: SIMD3<Float>,
        projection: MeshUVProjection
    ) -> Face? {
        guard projection.isEnabled else { return nil }

        switch projection.mode {
        case .none:
            return nil

        case .box, .facePlanar:
            let resolved = direction(normal, fallback: direction(simd_cross(b - a, c - a)))
            let frame = projection.mode == .box
                ? boxFrame(for: resolved)
                : faceFrame(for: resolved)
            func uv(_ point: SIMD3<Float>) -> SIMD2<Float> {
                let local = point - projection.center
                return SIMD2(
                    simd_dot(local, frame.tangent),
                    simd_dot(local, frame.bitangent)
                ) / projection.metersPerTile
            }
            return Face(
                a: uv(a), b: uv(b), c: uv(c),
                tangent: frame.tangent, bitangent: frame.bitangent
            )

        case .cylindrical, .spherical:
            let centroid = (a + b + c) / 3
            let frame = projection.mode == .cylindrical
                ? cylindricalFrame(at: centroid, projection: projection)
                : sphericalFrame(at: centroid, projection: projection)
            var us = SIMD3<Float>(
                angularU(a, projection),
                angularU(b, projection),
                angularU(c, projection)
            )
            // A triangle straddling the wrap seam has one vertex at ~0 turns and
            // two at ~`tilesAround`. Left alone it smears the entire texture
            // backwards across that one face; lifting the low vertices by a full
            // period makes the face continuous with its neighbour instead.
            unwrapSeam(&us, period: projection.tilesAround)
            let vs = SIMD3<Float>(
                axialV(a, projection),
                axialV(b, projection),
                axialV(c, projection)
            )
            return Face(
                a: SIMD2(us.x, vs.x),
                b: SIMD2(us.y, vs.y),
                c: SIMD2(us.z, vs.z),
                tangent: frame.tangent, bitangent: frame.bitangent
            )
        }
    }

    // MARK: Buffer-level generation

    /// Coordinates for an existing `positions` / `normals` / `indices` triple,
    /// in the same order and of the same length as `positions`.
    ///
    /// Designed for **flat-shaded** meshes — the kind `FlatMeshBuilder` produces,
    /// where every triangle owns its three vertices. On a mesh with shared
    /// vertices the planar modes are per-face and so the last triangle touching
    /// a vertex wins; use `.cylindrical` or `.spherical` there, which are
    /// per-vertex functions and therefore unambiguous.
    ///
    /// `normals` may be empty, in which case each face normal is derived from
    /// its geometry.
    static func coordinates(
        positions: [SIMD3<Float>],
        normals: [SIMD3<Float>],
        indices: [UInt32],
        projection: MeshUVProjection
    ) -> [SIMD2<Float>] {
        guard projection.isEnabled, !positions.isEmpty else { return [] }
        var uvs = [SIMD2<Float>](repeating: .zero, count: positions.count)

        var triangle = 0
        while triangle + 2 < indices.count {
            let i0 = Int(indices[triangle])
            let i1 = Int(indices[triangle + 1])
            let i2 = Int(indices[triangle + 2])
            triangle += 3
            guard i0 < positions.count, i1 < positions.count, i2 < positions.count else { continue }

            let a = positions[i0], b = positions[i1], c = positions[i2]
            let normal: SIMD3<Float>
            if normals.count == positions.count {
                normal = direction(normals[i0] + normals[i1] + normals[i2])
            } else {
                normal = direction(simd_cross(b - a, c - a))
            }
            guard let face = face(a, b, c, normal: normal, projection: projection) else { continue }
            uvs[i0] = face.a
            uvs[i1] = face.b
            uvs[i2] = face.c
        }
        return uvs
    }

    /// Tangent and bitangent buffers derived from coordinates that already
    /// exist, for meshes whose UVs did not come from a `MeshUVProjection`.
    ///
    /// Standard per-triangle UV-gradient accumulation, then Gram-Schmidt against
    /// the vertex normal so the frame is orthonormal and the handedness matches
    /// the winding. Prefer the frame handed back by
    /// ``face(_:_:_:normal:projection:)`` when you are generating the UVs
    /// yourself — it is exact rather than reconstructed.
    static func tangentBasis(
        positions: [SIMD3<Float>],
        normals: [SIMD3<Float>],
        textureCoordinates: [SIMD2<Float>],
        indices: [UInt32]
    ) -> (tangents: [SIMD3<Float>], bitangents: [SIMD3<Float>]) {
        let count = positions.count
        guard count > 0, textureCoordinates.count == count else { return ([], []) }

        var accumulatedTangents = [SIMD3<Float>](repeating: .zero, count: count)
        var accumulatedBitangents = [SIMD3<Float>](repeating: .zero, count: count)

        var triangle = 0
        while triangle + 2 < indices.count {
            let i0 = Int(indices[triangle])
            let i1 = Int(indices[triangle + 1])
            let i2 = Int(indices[triangle + 2])
            triangle += 3
            guard i0 < count, i1 < count, i2 < count else { continue }

            let edge1 = positions[i1] - positions[i0]
            let edge2 = positions[i2] - positions[i0]
            let delta1 = textureCoordinates[i1] - textureCoordinates[i0]
            let delta2 = textureCoordinates[i2] - textureCoordinates[i0]

            let determinant = delta1.x * delta2.y - delta2.x * delta1.y
            guard abs(determinant) > 1e-12 else { continue }
            let inverse = 1 / determinant

            let tangent = (edge1 * delta2.y - edge2 * delta1.y) * inverse
            let bitangent = (edge2 * delta1.x - edge1 * delta2.x) * inverse

            for index in [i0, i1, i2] {
                accumulatedTangents[index] += tangent
                accumulatedBitangents[index] += bitangent
            }
        }

        var tangents = [SIMD3<Float>](repeating: [1, 0, 0], count: count)
        var bitangents = [SIMD3<Float>](repeating: [0, 0, 1], count: count)
        for index in 0..<count {
            let normal = normals.count == count ? direction(normals[index]) : SIMD3<Float>(0, 1, 0)
            // Gram-Schmidt: drop whatever part of the accumulated tangent leans
            // out of the surface, so the frame is orthonormal.
            var tangent = accumulatedTangents[index] - normal * simd_dot(normal, accumulatedTangents[index])
            if simd_length_squared(tangent) <= 1e-12 {
                tangent = faceFrame(for: normal).tangent
            } else {
                tangent = simd_normalize(tangent)
            }
            // Mirrored UVs flip handedness; recover it from the accumulated
            // bitangent rather than assuming right-handed everywhere.
            let handedness: Float =
                simd_dot(simd_cross(normal, tangent), accumulatedBitangents[index]) < 0 ? -1 : 1
            tangents[index] = tangent
            bitangents[index] = simd_cross(normal, tangent) * handedness
        }
        return (tangents, bitangents)
    }

    // MARK: Surface bases

    /// `(tangent, bitangent)` for the dominant axis of `normal`. Faces sharing a
    /// dominant axis get the *same* basis, which is what makes box mapping
    /// continuous across a wall.
    static func boxFrame(for normal: SIMD3<Float>) -> (tangent: SIMD3<Float>, bitangent: SIMD3<Float>) {
        let n = direction(normal)
        let magnitude = abs(n)
        let axis: SIMD3<Float>
        if magnitude.y >= magnitude.x && magnitude.y >= magnitude.z {
            axis = [0, n.y < 0 ? -1 : 1, 0]
        } else if magnitude.x >= magnitude.z {
            axis = [n.x < 0 ? -1 : 1, 0, 0]
        } else {
            axis = [0, 0, n.z < 0 ? -1 : 1]
        }
        // A vertical dominant axis has no meaningful "up" to cross against, so
        // it takes world +X directly; everything else derives from world up.
        let tangent = abs(axis.y) > 0.5
            ? SIMD3<Float>(1, 0, 0)
            : direction(simd_cross([0, 1, 0], axis), fallback: [1, 0, 0])
        return (tangent, simd_cross(axis, tangent))
    }

    /// `(tangent, bitangent)` on the face's own plane. Zero stretch at any slant.
    static func faceFrame(for normal: SIMD3<Float>) -> (tangent: SIMD3<Float>, bitangent: SIMD3<Float>) {
        let n = direction(normal)
        // Swap the reference away from the pole so the cross product never
        // degenerates on a horizontal face.
        let reference: SIMD3<Float> = abs(n.y) > 0.9 ? [0, 0, 1] : [0, 1, 0]
        let tangent = direction(simd_cross(reference, n), fallback: [1, 0, 0])
        return (tangent, simd_cross(n, tangent))
    }

    /// `(tangent, bitangent)` for the cylindrical projection at `point`:
    /// tangent circumferential, bitangent along the pole axis.
    static func cylindricalFrame(
        at point: SIMD3<Float>,
        projection: MeshUVProjection
    ) -> (tangent: SIMD3<Float>, bitangent: SIMD3<Float>) {
        let axis = projection.axis
        let local = point - projection.center
        let radial = local - axis * simd_dot(local, axis)
        let tangent = direction(simd_cross(axis, radial), fallback: faceFrame(for: axis).tangent)
        return (tangent, axis)
    }

    /// `(tangent, bitangent)` for the spherical projection at `point`: tangent
    /// along increasing azimuth, bitangent along increasing polar angle — i.e.
    /// pointing away from the `axis` pole, which is the direction V grows.
    static func sphericalFrame(
        at point: SIMD3<Float>,
        projection: MeshUVProjection
    ) -> (tangent: SIMD3<Float>, bitangent: SIMD3<Float>) {
        let axis = projection.axis
        let local = point - projection.center
        let outward = direction(local, fallback: axis)
        let tangent = direction(simd_cross(axis, local), fallback: faceFrame(for: axis).tangent)
        // V grows as the polar angle grows, so the bitangent runs "downhill"
        // from the pole along the meridian.
        return (tangent, simd_cross(tangent, outward))
    }

    // MARK: Internals

    /// Normalises, or returns `fallback` rather than a NaN vector. Mirrors
    /// `StructureGeometry.direction`, kept local so this file stays importable
    /// on its own.
    static func direction(
        _ vector: SIMD3<Float>,
        fallback: SIMD3<Float> = [0, 1, 0]
    ) -> SIMD3<Float> {
        let lengthSquared = simd_length_squared(vector)
        return lengthSquared > 1e-12 ? vector / sqrt(lengthSquared) : fallback
    }

    /// Azimuth about `projection.axis`, in tiles.
    private static func angularU(_ point: SIMD3<Float>, _ projection: MeshUVProjection) -> Float {
        let axis = projection.axis
        let frame = faceFrame(for: axis)
        let local = point - projection.center
        let angle = atan2(simd_dot(local, frame.bitangent), simd_dot(local, frame.tangent))
        return angle / (2 * .pi) * projection.tilesAround
    }

    /// Distance along `projection.axis` (cylindrical) or polar angle from it
    /// (spherical), in tiles.
    private static func axialV(_ point: SIMD3<Float>, _ projection: MeshUVProjection) -> Float {
        let local = point - projection.center
        switch projection.mode {
        case .spherical:
            let outward = direction(local, fallback: projection.axis)
            let polar = acos(max(-1, min(1, simd_dot(outward, projection.axis))))
            return polar / .pi * projection.tilesOver
        default:
            return simd_dot(local, projection.axis) / projection.metersPerTile
        }
    }

    /// Lifts the vertices on the far side of a wrap seam by one full period, so
    /// a triangle spanning the seam interpolates the short way round.
    private static func unwrapSeam(_ values: inout SIMD3<Float>, period: Float) {
        guard period > 1e-4 else { return }
        let highest = max(values.x, max(values.y, values.z))
        let threshold = highest - period * 0.5
        for lane in 0..<3 where values[lane] < threshold {
            values[lane] += period
        }
    }
}
