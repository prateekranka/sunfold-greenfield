import Foundation
import RealityKit
import simd

/// Builds the low-poly drifting-land silhouette: a flat habitable top over a
/// tapering rocky underside, as established in concept 01.
///
/// Deliberately faceted. This is an authored placeholder form, not a generic
/// cube and not final art.
enum FragmentMeshFactory {

    /// Number of sides in the silhouette. Enough to carry a broken outline while
    /// staying readably faceted.
    private static let sideCount = 30

    struct Built {
        let top: MeshResource
        let underside: MeshResource
        /// The jittered rim radii, so props and dressing can sit on the real edge
        /// rather than on the nominal circle. Sample `i` sits at angle
        /// `i / count · 2π`, matching `RimProfile`.
        let rimRadii: [Float]
    }

    @MainActor
    static func build(fragment: Fragment, seed: UInt64) -> Built {
        var random = DeterministicRandom.stream(seed: seed, tag: "fragment.\(fragment.id.rawValue)")

        // Rim jitter is strictly *outward*. `WorldMap.contains` treats the nominal
        // circle as land and `MovementSystem` lets a unit stand anywhere inside it,
        // so a rim drawn shorter than nominal — as it was, down to 0.90 — puts a
        // citizen legally on ground that is not there. Growing outward keeps the
        // drawn land a superset of the legal land, and the craggy read comes from
        // spurs pushing past the circle rather than bites taken out of it.
        var rimRadii: [Float] = []
        var isSpur: [Bool] = []
        rimRadii.reserveCapacity(sideCount)
        for index in 0..<sideCount {
            // Every third vertex or so throws a longer point, which is what turns
            // a rounded polygon into broken rock.
            let spur = index % 3 == 1 && random.unitFloat() < 0.72
            // Measured in the build: at 1.26 a spur vertex between two ordinary
            // ones stretched into a long thin horn pointing out of the island.
            // The outline wants a break, not a star.
            let reach = spur ? random.float(in: 1.05...1.12) : random.float(in: 1.00...1.045)
            rimRadii.append(fragment.radius * reach)
            isSpur.append(spur)
        }

        let angles = (0..<sideCount).map { Float($0) / Float(sideCount) * 2 * .pi }

        func ring(scale: (Int) -> Float, y: (Int) -> Float) -> [SIMD3<Float>] {
            (0..<sideCount).map { index in
                let radius = rimRadii[index] * scale(index)
                return [cos(angles[index]) * radius, y(index), sin(angles[index]) * radius]
            }
        }

        let rim = ring(scale: { _ in 1 }, y: { _ in 0 })

        // Three stages down the flank instead of one. A single band read as a
        // bevelled disc; the shelf gives the rock a horizontal break to catch the
        // key light, and only then does the mass taper away.
        //
        // Both rings jitter in height as well as radius. With a fixed height the
        // flank facets all tilted the same way, so the lit rock graded smoothly
        // around the circle and read as a machined bevel; varying the height is
        // what gives adjacent faces genuinely different normals and therefore the
        // facet-to-facet contrast that reads as stone.
        var shelfScale: [Float] = []
        var shelfHeight: [Float] = []
        var midScale: [Float] = []
        var midHeight: [Float] = []
        for _ in 0..<sideCount {
            shelfScale.append(random.float(in: 0.88...0.99))
            shelfHeight.append(-fragment.depth * random.float(in: 0.13...0.29))
            midScale.append(random.float(in: 0.56...0.78))
            midHeight.append(-fragment.depth * random.float(in: 0.44...0.63))
        }
        let shelf = ring(scale: { shelfScale[$0] }, y: { shelfHeight[$0] })
        let mid = ring(scale: { midScale[$0] }, y: { midHeight[$0] })

        let apex = SIMD3<Float>(
            random.float(in: -0.12...0.12) * fragment.radius,
            -fragment.depth,
            random.float(in: -0.12...0.12) * fragment.radius
        )
        let center = SIMD3<Float>(0, 0, 0)

        var topBuilder = FlatMeshBuilder()
        var underBuilder = FlatMeshBuilder()

        for index in 0..<sideCount {
            let next = (index + 1) % sideCount
            let outward = simd_normalize(SIMD3<Float>(rim[index].x, 0, rim[index].z))

            topBuilder.addTriangle(center, rim[index], rim[next], facing: [0, 1, 0])

            underBuilder.addTriangle(rim[index], shelf[index], shelf[next], facing: outward)
            underBuilder.addTriangle(rim[index], shelf[next], rim[next], facing: outward)

            underBuilder.addTriangle(shelf[index], mid[index], mid[next], facing: outward)
            underBuilder.addTriangle(shelf[index], mid[next], shelf[next], facing: outward)

            underBuilder.addTriangle(mid[index], apex, mid[next], facing: outward - [0, 1, 0])
        }

        addHangingSpurs(
            into: &underBuilder,
            shelf: shelf,
            isSpur: isSpur,
            depth: fragment.depth,
            random: &random
        )

        return Built(
            top: topBuilder.makeMesh(named: "\(fragment.id.rawValue).top"),
            underside: underBuilder.makeMesh(named: "\(fragment.id.rawValue).under"),
            rimRadii: rimRadii
        )
    }

    /// Sharp rock hanging below the underside at the spur vertices.
    ///
    /// This is the detail that says *torn loose* rather than *carved*. They hang
    /// from the shelf rather than from the rim, so they read as rock still
    /// attached to the underside instead of fins bolted to the edge.
    private static func addHangingSpurs(
        into builder: inout FlatMeshBuilder,
        shelf: [SIMD3<Float>],
        isSpur: [Bool],
        depth: Float,
        random: inout DeterministicRandom
    ) {
        let count = shelf.count
        guard count >= 3 else { return }

        func inset(_ point: SIMD3<Float>, _ factor: Float) -> SIMD3<Float> {
            [point.x * factor, point.y, point.z * factor]
        }

        for index in 0..<count where isSpur[index] {
            let previous = (index + count - 1) % count
            let next = (index + 1) % count

            // The base is a narrow sliver hugging one vertex. Spanning the full
            // arc to both neighbours — a twelfth of the circumference — produced
            // flat sheets the size of the island rather than rock.
            func toward(_ other: SIMD3<Float>, _ amount: Float) -> SIMD3<Float> {
                shelf[index] + (other - shelf[index]) * amount
            }
            let a = inset(toward(shelf[previous], 0.26), 0.99)
            let b = inset(shelf[index], 0.74)
            let c = inset(toward(shelf[next], 0.26), 0.99)
            let tip = SIMD3<Float>(
                shelf[index].x * random.float(in: 0.86...1.00),
                -depth * random.float(in: 0.50...0.92),
                shelf[index].z * random.float(in: 0.86...1.00)
            )

            // A closed spike: three faces, each turned away from the spike's own
            // centre, so no face needs its winding reasoned about individually.
            let pivot = (a + b + c + tip) * 0.25
            builder.addTriangle(a, b, tip, facing: (a + b + tip) / 3 - pivot)
            builder.addTriangle(b, c, tip, facing: (b + c + tip) / 3 - pivot)
            builder.addTriangle(c, a, tip, facing: (c + a + tip) / 3 - pivot)
        }
    }
}

/// Accumulates flat-shaded triangles: each face gets its own three vertices and
/// one normal, which is what produces the faceted low-poly read.
struct FlatMeshBuilder {
    private var positions: [SIMD3<Float>] = []
    private var normals: [SIMD3<Float>] = []
    private var indices: [UInt32] = []

    /// Adds a triangle, correcting winding so the face points along `facing`.
    /// This removes any need to reason about vertex order at each call site.
    mutating func addTriangle(
        _ a: SIMD3<Float>,
        _ b: SIMD3<Float>,
        _ c: SIMD3<Float>,
        facing reference: SIMD3<Float>
    ) {
        var first = b, second = c
        var normal = simd_cross(first - a, second - a)
        let lengthSquared = simd_length_squared(normal)
        guard lengthSquared > 1e-12 else { return }  // Degenerate; contributes nothing.
        normal /= sqrt(lengthSquared)

        if simd_dot(normal, reference) < 0 {
            swap(&first, &second)
            normal = -normal
        }

        let base = UInt32(positions.count)
        positions.append(contentsOf: [a, first, second])
        normals.append(contentsOf: [normal, normal, normal])
        indices.append(contentsOf: [base, base + 1, base + 2])
    }

    /// `MeshResource` generation is main-actor isolated in RealityKit, so mesh
    /// assembly stays on the main actor with the rest of the scene build.
    @MainActor
    func makeMesh(named name: String) -> MeshResource {
        var descriptor = MeshDescriptor(name: name)
        descriptor.positions = MeshBuffer(positions)
        descriptor.normals = MeshBuffer(normals)
        descriptor.primitives = .triangles(indices)
        do {
            return try MeshResource.generate(from: [descriptor])
        } catch {
            // Fail closed: a readable primitive plus a loud warning, never a crash
            // and never an invisible entity.
            DebugLog.warn("Mesh '\(name)' failed to generate (\(error)); using fallback box.")
            return MeshResource.generateBox(size: 1)
        }
    }
}
