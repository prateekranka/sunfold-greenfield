import Foundation
import RealityKit
import simd

/// Builds one continuous surface for every authored void-water body.
///
/// Water used to be capped independently inside each fragment's polar mesh.
/// That made one channel into many unrelated black polygons, with seams where
/// the fragment grids met. This surface samples the same signed `WorldMap`
/// water field in world space, so a channel has one topology and one shoreline.
@MainActor
enum VoidWaterMeshFactory {

    /// The water sits below the terrain lip and above the fragment cone.
    /// It is a presentation datum; transport legality remains in `WorldMap`.
    static let waterLevel: Float = -1.35

    /// The grid is only a sampling lattice. Shoreline vertices are interpolated
    /// on its edges, so the rendered coast does not inherit the lattice shape.
    private static let cellSize: Float = 1.0
    private static let shallowDepth: Float = 4.0
    private static let shorelineWidth: Float = 0.65

    private struct Sample {
        let point: SIMD3<Float>
        let depth: Float
    }

    private struct ShorelineSegment {
        let a: WorldPoint
        let b: WorldPoint
    }

    static func build(map: WorldMap) -> Entity? {
        var deepSurface = FlatMeshBuilder()
        var shallowSurface = FlatMeshBuilder()
        var shoreline = FlatMeshBuilder()
        var banks = FlatMeshBuilder()

        let minX = Int(floor(-map.bounds.x / cellSize)) - 1
        let maxX = Int(ceil(map.bounds.x / cellSize)) + 1
        let minY = Int(floor(-map.bounds.y / cellSize)) - 1
        let maxY = Int(ceil(map.bounds.y / cellSize)) + 1

        // The nested integer loops are deliberately ordered. Boundary extraction
        // must not depend on Set or dictionary iteration order.
        for row in minY..<maxY {
            for column in minX..<maxX {
                let cornerSamples = samples(column: column, row: row, map: map)
                let x = Float(column) * cellSize
                let z = Float(row) * cellSize
                let centerPoint = WorldPoint(x + cellSize * 0.5, z + cellSize * 0.5)
                let centerSample = Sample(
                    point: [centerPoint.x, waterLevel, centerPoint.y],
                    depth: map.waterDepth(at: centerPoint)
                )

                // Splitting at the sampled centre resolves diagonal saddle cases
                // without inventing a bridge across a dry pocket.
                for index in 0..<cornerSamples.count {
                    let triangle = [
                        centerSample,
                        cornerSamples[index],
                        cornerSamples[(index + 1) % cornerSamples.count]
                    ]
                    let polygon = clippedWaterPolygon(triangle)
                    if polygon.count >= 3 {
                        let polygonCenter = polygon.reduce(SIMD3<Float>.zero, +) / Float(polygon.count)
                        if map.waterDepth(at: [polygonCenter.x, polygonCenter.z]) < shallowDepth {
                            addPolygon(polygon, to: &shallowSurface)
                        } else {
                            addPolygon(polygon, to: &deepSurface)
                        }
                    }
                }

                for segment in shorelineSegments(samples: cornerSamples, map: map) {
                    addShoreline(
                        segment,
                        shoreline: &shoreline,
                        banks: &banks,
                        map: map
                    )
                }
            }
        }

        let waterEntity = Entity()
        waterEntity.name = "void.water"
        var hasGeometry = false

        if let descriptor = deepSurface.makeDescriptor(
            named: "void.water.deep",
            materialIndex: 0
        ) {
            waterEntity.addChild(
                model(
                    named: "void.water.deep",
                    descriptors: [descriptor],
                    material: UnlitMaterial(color: SunfoldPalette.voidWaterDeep)
                )
            )
            hasGeometry = true
        }

        if let descriptor = shallowSurface.makeDescriptor(
            named: "void.water.shallow",
            materialIndex: 0
        ) {
            waterEntity.addChild(
                model(
                    named: "void.water.shallow",
                    descriptors: [descriptor],
                    material: UnlitMaterial(color: SunfoldPalette.voidWaterShallow)
                )
            )
            hasGeometry = true
        }

        if let descriptor = shoreline.makeDescriptor(
            named: "void.water.shoreline",
            materialIndex: 0
        ) {
            waterEntity.addChild(
                model(
                    named: "void.water.shoreline",
                    descriptors: [descriptor],
                    material: UnlitMaterial(color: SunfoldPalette.voidWaterShore)
                )
            )
            hasGeometry = true
        }

        if let descriptor = banks.makeDescriptor(
            named: "void.water.banks",
            materialIndex: 0
        ) {
            waterEntity.addChild(
                model(
                    named: "void.water.banks",
                    descriptors: [descriptor],
                    material: StructureMaterial.matte(
                        SunfoldPalette.landRock,
                        surface: .regolithGround
                    )
                )
            )
            hasGeometry = true
        }

        return hasGeometry ? waterEntity : nil
    }

    private static func samples(column: Int, row: Int, map: WorldMap) -> [Sample] {
        let x = Float(column) * cellSize
        let z = Float(row) * cellSize
        let points = [
            WorldPoint(x, z),
            WorldPoint(x + cellSize, z),
            WorldPoint(x + cellSize, z + cellSize),
            WorldPoint(x, z + cellSize)
        ]
        return points.map { point in
            Sample(
                point: [point.x, waterLevel, point.y],
                depth: map.waterDepth(at: point)
            )
        }
    }

    /// Clips a grid square against the signed water field.
    ///
    /// The crossing position is linearly interpolated from the two signed
    /// samples. This keeps the shared field as the authority while removing the
    /// old axis-aligned cell staircase from the visible coastline.
    private static func clippedWaterPolygon(_ samples: [Sample]) -> [SIMD3<Float>] {
        guard samples.count >= 3 else { return [] }
        var polygon: [SIMD3<Float>] = []

        func appendUnique(_ point: SIMD3<Float>) {
            if let last = polygon.last, simd_length_squared(last - point) < 1e-8 {
                return
            }
            polygon.append(point)
        }

        for index in 0..<samples.count {
            let current = samples[index]
            let next = samples[(index + 1) % samples.count]
            let currentWet = current.depth > 0
            let nextWet = next.depth > 0

            if currentWet && nextWet {
                appendUnique(next.point)
            } else if currentWet != nextWet {
                let denominator = current.depth - next.depth
                let fraction = abs(denominator) > 1e-6 ? current.depth / denominator : 0.5
                appendUnique(current.point + (next.point - current.point) * fraction)
                if nextWet { appendUnique(next.point) }
            }
        }

        if polygon.count > 1,
           let first = polygon.first,
           let last = polygon.last,
           simd_length_squared(first - last) < 1e-8 {
            polygon.removeLast()
        }
        return polygon
    }

    /// Returns the zero-field contour segments inside one grid cell.
    private static func shorelineSegments(
        samples: [Sample],
        map: WorldMap
    ) -> [ShorelineSegment] {
        guard samples.count == 4 else { return [] }
        var crossings = [WorldPoint?](repeating: nil, count: 4)

        for edge in 0..<4 {
            let a = samples[edge]
            let b = samples[(edge + 1) % 4]
            guard (a.depth > 0) != (b.depth > 0) else { continue }
            let denominator = a.depth - b.depth
            let fraction = abs(denominator) > 1e-6 ? a.depth / denominator : 0.5
            let point = a.point + (b.point - a.point) * fraction
            crossings[edge] = [point.x, point.z]
        }

        let present = crossings.indices.filter { crossings[$0] != nil }
        guard present.count >= 2 else { return [] }
        if present.count == 2 {
            return [ShorelineSegment(a: crossings[present[0]]!, b: crossings[present[1]]!)]
        }

        // Four crossings are the marching-squares saddle. The centre sample
        // chooses whether water connects through the centre or remains in two
        // diagonal pockets, using the same field rather than an arbitrary case.
        let center = WorldPoint(
            (samples[0].point.x + samples[2].point.x) * 0.5,
            (samples[0].point.z + samples[2].point.z) * 0.5
        )
        let centerWet = map.waterDepth(at: center) > 0
        var segments: [ShorelineSegment] = []
        for corner in 0..<4 {
            let cornerWet = samples[corner].depth > 0
            let isContourCorner = centerWet ? !cornerWet : cornerWet
            guard isContourCorner else { continue }
            let before = crossings[(corner + 3) % 4]
            let after = crossings[corner]
            if let before, let after {
                segments.append(ShorelineSegment(a: before, b: after))
            }
        }
        return segments
    }

    private static func addPolygon(
        _ polygon: [SIMD3<Float>],
        to builder: inout FlatMeshBuilder
    ) {
        let center = polygon.reduce(SIMD3<Float>.zero, +) / Float(polygon.count)
        for index in 0..<polygon.count {
            builder.addTriangle(
                center,
                polygon[index],
                polygon[(index + 1) % polygon.count],
                facing: [0, 1, 0]
            )
        }
    }

    /// Adds the visible water-edge transition and the land-facing bank wall.
    ///
    /// The shoreline treatment is split across both surfaces: the water-side
    /// strip gives the dark body a readable edge, while the bank wall gives the
    /// coast an intentional vertical face without changing movement truth.
    private static func addShoreline(
        _ segment: ShorelineSegment,
        shoreline: inout FlatMeshBuilder,
        banks: inout FlatMeshBuilder,
        map: WorldMap
    ) {
        let span = segment.b - segment.a
        let length = simd_length(span)
        guard length > 0.01 else { return }

        let normal = WorldPoint(-span.y, span.x) / length
        let midpoint = (segment.a + segment.b) * 0.5
        let positiveProbe = midpoint + normal * 0.45
        let negativeProbe = midpoint - normal * 0.45
        let waterNormal: WorldPoint
        if map.waterDepth(at: positiveProbe) > 0 {
            waterNormal = normal
        } else if map.waterDepth(at: negativeProbe) > 0 {
            waterNormal = -normal
        } else {
            return
        }

        let dryNormal = -waterNormal
        let dryA = segment.a + dryNormal * 0.60
        let dryB = segment.b + dryNormal * 0.60
        guard map.isLand(dryA), map.isLand(dryB) else { return }

        let edgeA = SIMD3<Float>(segment.a.x, waterLevel + 0.02, segment.a.y)
        let edgeB = SIMD3<Float>(segment.b.x, waterLevel + 0.02, segment.b.y)
        let waterOffset = SIMD3<Float>(waterNormal.x * shorelineWidth, 0, waterNormal.y * shorelineWidth)
        let innerA = edgeA + waterOffset
        let innerB = edgeB + waterOffset
        shoreline.addTriangle(edgeA, innerA, innerB, facing: [0, 1, 0])
        shoreline.addTriangle(edgeA, innerB, edgeB, facing: [0, 1, 0])

        let topA = SIMD3<Float>(
            segment.a.x,
            TerrainSurface.groundY(at: dryA, in: map),
            segment.a.y
        )
        let topB = SIMD3<Float>(
            segment.b.x,
            TerrainSurface.groundY(at: dryB, in: map),
            segment.b.y
        )
        let lowerA = SIMD3<Float>(segment.a.x, waterLevel, segment.a.y)
        let lowerB = SIMD3<Float>(segment.b.x, waterLevel, segment.b.y)
        let facing = SIMD3<Float>(dryNormal.x, 0, dryNormal.y)
        banks.addTriangle(topA, lowerA, lowerB, facing: facing)
        banks.addTriangle(topA, lowerB, topB, facing: facing)
    }

    @MainActor
    private static func model(
        named name: String,
        descriptors: [MeshDescriptor],
        material: any Material
    ) -> Entity {
        let entity = Entity()
        entity.name = name
        entity.components.set(
            ModelComponent(
                mesh: makeMesh(descriptors, named: name),
                materials: [material]
            )
        )
        return entity
    }

    @MainActor
    private static func makeMesh(
        _ descriptors: [MeshDescriptor],
        named name: String
    ) -> MeshResource {
        do {
            return try MeshResource.generate(from: descriptors)
        } catch {
            DebugLog.warn("Mesh '\(name)' failed to generate (\(error)); using fallback plane.")
            return MeshResource.generatePlane(width: 0.001, height: 0.001)
        }
    }
}
