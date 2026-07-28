import Foundation
import RealityKit
import UIKit
import simd

/// Builds the drifting-land silhouette: a relieved habitable top over a
/// stratified rocky flank, as established in concept 01.
///
/// # What changed and why
/// The first version of this file drew a 30-sided polygon with **one flat facet**
/// for the entire habitable top and a single untextured cone underneath. In the
/// rendered frame that read exactly as what it was — a beige paper disc with
/// visibly straight edges sitting on a uniform navy bevel. Three things fix that,
/// and all three live here because all three are geometry decisions:
///
/// 1. **Silhouette.** 96 rim samples instead of 30, and the rim radius comes from
///    layered wrapped noise rather than a per-vertex coin flip, so the outline is
///    irregular at three scales at once instead of faceted at one.
/// 2. **Relief.** The top is a radial height-field grid with smooth normals, so
///    the ground swells, dips and turns down into the cliff. `groundHeight` is a
///    *pure public function* — anything that needs to sit an object on the real
///    ground can sample it (see the note on the datum below).
/// 3. **Value separation.** Both meshes are emitted as several material parts.
///    The top is splatted between pale, mid, rim-dark and trodden-path layers;
///    the flank is banded into a lit lip, a warm bounce third, two cooling strata
///    and a base 55% down. RealityKit gives a `MeshResource` one part per
///    `MeshDescriptor`, and `ModelComponent.materials` indexes those parts — so
///    multi-material terrain costs nothing but a few draws and needs no custom
///    shader.
///
/// # The datum rule
/// Terrain relief **never goes above zero**. `groundHeight` returns values in
/// `-2.0 ... 0`, and it is pinned to exactly `0` across the compacted pan the
/// Core and the opening buildings stand on, so nothing the simulation places can
/// be buried by relief.
///
/// Everything that stands on the ground now samples that height rather than
/// assuming the datum plane:
///
/// - `EntityPresenter` places units, buildings, deposits and the order marker
///   through `TerrainSurface`, which resolves a world point to its fragment and
///   samples here. Units re-sample every frame, because they walk.
/// - `TerrainDressing` sets `FlatMeshBuilder.lift` on its builders: the ground
///   decals drape per vertex, and each scattered prop translates rigidly by the
///   height under its own footing.
///
/// Until CP-04 none of that was true — `groundHeight` had two callers, both in
/// this file — and the relief amplitude had to stay under half a metre to keep
/// the error invisible. That is why the terrain was flat.
///
/// # Determinism
/// The rim and the flank still draw from the fragment's own tagged
/// `DeterministicRandom` stream. Everything else — the height field, the splat
/// masks, the path network — is `ProceduralNoise`, which is a pure function of
/// its arguments and consumes no stream at all. Adding relief therefore cannot
/// shift a single number in any other subsystem.
enum FragmentMeshFactory {

    // MARK: - Tessellation

    /// Rim samples around the silhouette.
    ///
    /// 30 was the old value and it was the single most visible tell in the
    /// frame: a 12° facet at this camera distance is a straight edge tens of
    /// pixels long, and the eye reads the whole island as a polygon. At 96 the
    /// facet is 3.75°, which is under the width of the rim highlight, so what
    /// survives is the *noise* in the radius rather than the tessellation.
    static let sideCount = 96

    /// Concentric rings across the habitable top. With `sideCount` this is a
    /// 96 x 20 height-field grid — ~3.8 k triangles per fragment, which is
    /// nothing on the target device and is the resolution at which a 6 m swell
    /// and a 2 m trodden path both survive.
    ///
    /// Raised from 14 with the relief amplitude. At 14 the rings were 1.7 m
    /// apart on a home fragment against a 3.8 m micro-relief wavelength — barely
    /// over two samples per cycle, which was invisible while the amplitude was
    /// 7 cm and would have aliased into a visible crease pattern once it was not.
    private static let ringCount = 24

    /// How far the shipped triangles can sit above the height field they sample.
    ///
    /// The top is a grid: it samples `groundHeight` at its corners and stretches
    /// flat triangles between them. Across a dip the chord runs *above* the curve
    /// it approximates, so anything laid on the ground by sampling the continuous
    /// function — a seam, a tone patch, the shore band — is underneath the mesh
    /// and never drawn. This is that error, not a safety margin.
    ///
    /// For one sinusoid it is `A · (π · h / λ)² / 2`, summed over the field's two
    /// terms at the widest grid spacing on a home fragment (1.57 m, set by
    /// `sideCount` at the rim rather than by `ringCount`):
    ///
    /// - micro: `0.08 · (π · 1.57 / 3.77)² / 2` ≈ 0.068 m
    /// - swell: `2.1 · (π · 1.57 / 17.6)² / 2` ≈ 0.082 m
    ///
    /// `TerrainDressing.Height` clears this. Raise it if either amplitude grows
    /// or either cell count does, or ground decals start to vanish in patches.
    static let chordError: Float = 0.155

    /// One texture tile every 4 m of rock.
    ///
    /// This is the project's texel-density anchor: any other factory that adopts
    /// `MeshUVProjection` should quote the same `metersPerTile` so a 7 m farm and
    /// a 40 m fragment are grained alike rather than one looking like gravel
    /// beside the other's sand.
    static let fragmentUVProjection = MeshUVProjection.facePlanar(metersPerTile: 4)

    /// Metres of ground per texture tile on the habitable top. Same anchor as
    /// `fragmentUVProjection`, applied as a straight XZ planar projection
    /// because the top is a height field rather than a set of arbitrary facets.
    private static let groundMetersPerTile: Float = 4

    // MARK: - Material layers

    /// The material parts of the habitable top, in the order
    /// `ModelComponent.materials` must supply them.
    ///
    /// This is the splat. A per-triangle choice between four layers, with a
    /// stippled threshold at the boundaries, is a genuine terrain blend at this
    /// triangle density — and unlike a vertex-colour or splat-map approach it
    /// needs no custom material, which RealityKit would otherwise make us write
    /// a Metal shader for.
    enum TopLayer: Int, CaseIterable {
        /// Open, sun-bleached ground. The fragment's palette surface colour.
        case pale
        /// Slightly cooler, slightly darker soil. The mid tone that stops the
        /// pale reading as a single flat fill.
        case mid
        /// Rim-ward darkening and the deep macro patches. Carries most of the
        /// value falloff toward the edge.
        case rimDark
        /// Trodden ground: the compacted pan under the settlement and the paths
        /// worn out of it toward the rim.
        case path
    }

    /// The horizontal strata of the flank, top to bottom.
    ///
    /// The critic's read of the old flank — "a uniform dark navy with no
    /// gradient, so the disc has no readable thickness" — is a value problem,
    /// not a hue problem. Thickness is read from a *gradient*, so the flank is
    /// banded: a lit lip at the very edge, a warm third under it that picks up
    /// the sand albedo as bounce, two cooling strata, and a base 55% down.
    enum CliffBand: Int, CaseIterable {
        /// The thin band immediately under the rim. Warm, sand-tinted and
        /// faintly emissive: this is the rim/backlight that separates the
        /// plateau's silhouette from the black void instead of letting it read
        /// as a cut-out sticker.
        case lip
        /// Upper third. Sand bounce — light that has hit the habitable top and
        /// come back down onto the rock.
        case bounce
        /// Upper strata. Neutral cool stone.
        case upper
        /// Mid strata, cooler and a third down in value.
        case middle
        /// The base, 55% darker and coolest, so the mass falls away into the
        /// void rather than ending at a hard line.
        case base
        /// Pale crystalline spurs on the rim promontories. Own material slot so
        /// the geometry can take warm ivory crystal instead of cold rimStone —
        /// retinting a cold reference stays muted (CP-07).
        case crystal
        /// The floor of a river, lake or inlet.
        ///
        /// A plate's underside is a closed cone down to an apex, so cutting water
        /// out of the *top* opens a window onto the inside of that cone — and lit
        /// rock is what you then see at the bottom of every lake. The map's whole
        /// premise is that space is the water, so a lake showing rock is the one
        /// place the render contradicts the fiction outright.
        ///
        /// Capping each channel with an unlit void-coloured floor is what closes
        /// that. Cutting the hole through the cone as well would be the literal
        /// answer and is not worth it: the cone converges on a single point, so a
        /// through-hole is a genuine topology problem, and no camera angle this game
        /// allows can see the difference between a hole and a floor the colour of
        /// the thing behind it.
        case abyss
    }

    struct Built {
        /// One part per ``TopLayer``, indexed by its `rawValue`.
        let top: MeshResource
        /// One part per ``CliffBand``, indexed by its `rawValue`.
        let underside: MeshResource
        /// The jittered rim radii, so props and dressing can sit on the real edge
        /// rather than on the nominal circle. Sample `i` sits at angle
        /// `i / count · 2π`, matching `RimProfile`.
        let rimRadii: [Float]
    }

    // MARK: - Build

    @MainActor
    static func build(fragment: Fragment, map: WorldMap, seed: UInt64) -> Built {
        var random = DeterministicRandom.stream(seed: seed, tag: "fragment.\(fragment.id.rawValue)")

        let angles = (0..<sideCount).map { Float($0) / Float(sideCount) * 2 * .pi }
        let (rimRadii, isSpur) = makeRim(fragment: fragment, random: &random)
        let water = WaterMask(fragment: fragment, map: map, angles: angles, rimRadii: rimRadii)

        let top = buildTop(fragment: fragment, angles: angles, rimRadii: rimRadii, water: water)
        let underside = buildFlank(
            fragment: fragment,
            angles: angles,
            rimRadii: rimRadii,
            isSpur: isSpur,
            water: water,
            seed: seed,
            random: &random
        )

        return Built(top: top, underside: underside, rimRadii: rimRadii)
    }

    // MARK: - Water

    /// Which cells of the habitable grid a river, lake or inlet has taken away.
    ///
    /// The map's water is authored as a signed field, and the top is a polar grid,
    /// so carving is a matter of asking the field about each cell and dropping the
    /// ones that are under water. Everything else — the banks, the props that must
    /// not stand in the channel, the minimap's coastline — reads the same field, so
    /// the render cannot disagree with the rules about where the water is.
    ///
    /// Cells are classified by their **centroid**, not by their corners. Testing
    /// corners forces a choice between a channel a cell wider than the legal water
    /// (a unit standing on drawn void) and a cell narrower (a strip of drawn land
    /// nobody may walk on). The centroid splits the error either way at half a cell
    /// — about 0.7 m here, well inside the footprint margin `WorldMap.isStandable`
    /// already applies, so a unit's feet stay dry regardless.
    struct WaterMask {
        /// `true` where the quad between rings `ring` and `ring + 1` is drowned.
        private let drowned: [[Bool]]
        let isEmpty: Bool

        init(fragment: Fragment, map: WorldMap, angles: [Float], rimRadii: [Float]) {
            guard !map.voidBodies.isEmpty else {
                drowned = []
                isEmpty = true
                return
            }
            var table = [[Bool]](
                repeating: [Bool](repeating: false, count: sideCount),
                count: ringCount
            )
            var any = false
            for ring in 0..<ringCount {
                let inner = ringEase(ring), outer = ringEase(ring + 1)
                for index in 0..<sideCount {
                    let next = (index + 1) % sideCount
                    let midRadius = (rimRadii[index] + rimRadii[next]) * 0.5 * (inner + outer) * 0.5
                    let midAngle = angles[index] + (.pi / Float(sideCount))
                    let local = SIMD2<Float>(cos(midAngle), sin(midAngle)) * midRadius
                    if map.isSubmerged(fragment.center + local) {
                        table[ring][index] = true
                        any = true
                    }
                }
            }
            drowned = table
            isEmpty = !any
        }

        func isDrowned(ring: Int, index: Int) -> Bool {
            guard !drowned.isEmpty, ring >= 0, ring < drowned.count else { return false }
            return drowned[ring][((index % sideCount) + sideCount) % sideCount]
        }
    }

    /// Where ring `n` sits as a fraction of the rim radius. The ease pushes rings
    /// outward, concentrating resolution where the rim fall and shore happen.
    private static func ringEase(_ ring: Int) -> Float {
        pow(Float(ring) / Float(ringCount), 0.88)
    }

    /// The fragment's drawn outline on the world plane — same rim the mesh used.
    ///
    /// The minimap must show silhouettes, not circles. Re-running the fragment's
    /// own stream reproduces the radii without touching any other subsystem's
    /// draws: a fresh stream with the same seed and tag is a pure replay.
    static func rimOutline(fragment: Fragment, seed: UInt64, samples: Int = 32) -> [WorldPoint] {
        var random = DeterministicRandom.stream(seed: seed, tag: "fragment.\(fragment.id.rawValue)")
        let (rimRadii, _) = makeRim(fragment: fragment, random: &random)
        let count = max(8, min(samples, sideCount))
        return (0..<count).map { sample in
            let index = sample * sideCount / count
            let angle = Float(index) / Float(sideCount) * 2 * .pi
            let radius = rimRadii[index]
            return fragment.center + WorldPoint(cos(angle) * radius, sin(angle) * radius)
        }
    }

    // MARK: - Silhouette

    /// The rim radius at every sample, plus which samples throw a hanging spur.
    ///
    /// The base is the plate's **authored outline**, `Fragment.radius(atBearing:)`
    /// — the same function `WorldMap.contains` uses. Before CP-14 the base was a
    /// circle and everything interesting about the silhouette had to be smuggled
    /// in as noise on top of it, which is why seven plates read as seven circles:
    /// noise at a few per cent cannot make a bay, and the *legal* land was a disc
    /// regardless of what was drawn. Now the shape is in the contract and this
    /// only adds the erosion.
    ///
    /// Rim jitter stays strictly *outward*. A unit may stand anywhere inside the
    /// authored outline, so a rim drawn shorter than authored puts a citizen
    /// legally on ground that is not there. Growing outward keeps the drawn land a
    /// superset of the legal land, and the craggy read comes from spurs pushing
    /// past the outline rather than from bites taken out of it. Bites are water,
    /// and water is carved from both at once by ``WaterMask``.
    ///
    /// Three octaves of wrapped noise rather than a per-vertex random reach: a
    /// per-vertex value at 96 samples is white noise and reads as a serrated
    /// gear, whereas layered noise gives the outline broad bays, metre-scale
    /// crags and a fine chew all at once — which is what an eroded edge is.
    private static func makeRim(
        fragment: Fragment,
        random: inout DeterministicRandom
    ) -> (radii: [Float], isSpur: [Bool]) {
        // One extra draw so the noise phase differs per fragment without the
        // noise itself touching the stream on every sample.
        let phase = random.unitFloat()

        var radii: [Float] = []
        var isSpur = [Bool](repeating: false, count: sideCount)
        radii.reserveCapacity(sideCount)

        for index in 0..<sideCount {
            let angle = Float(index) / Float(sideCount) * 2 * .pi
            let turns = Float(index) / Float(sideCount) + phase
            let broad = wrappedNoise(turns, cells: 5, salt: Salt.rimBroad)
            let crag = wrappedNoise(turns, cells: 13, salt: Salt.rimCrag)
            let chew = wrappedNoise(turns, cells: 31, salt: Salt.rimChew)
            // Sums to at most 1.0, so `reach` lands in 1.00 ... 1.125 — outward
            // only.
            //
            // CP-12 ran this at 0.12/0.055/0.030 because the rim noise was the
            // *only* thing making a silhouette out of a circle, and it had to be
            // loud enough to read at 192 pt on the minimap. That cost 22% of drawn
            // land a player could see and never walk on. The outline is authored
            // now, so this is back to being erosion on top of a shape.
            let reach = 1 + 0.07 * broad + 0.035 * crag + 0.020 * chew
            radii.append(fragment.radius(atBearing: angle) * reach)
        }

        // Spurs are the *torn* detail: a handful of longer points, each spanning
        // three samples with a triangular profile so it is a promontory rather
        // than the one-vertex needle a single sample produces at 96 sides.
        var index = 3
        while index < sideCount {
            if random.unitFloat() < 0.68 {
                let extra = random.float(in: 0.08...0.16) * fragment.radius
                radii[index] += extra
                radii[(index + sideCount - 1) % sideCount] += extra * 0.45
                radii[(index + 1) % sideCount] += extra * 0.45
                isSpur[index] = true
            }
            index += 7
        }

        return (radii, isSpur)
    }

    // MARK: - Habitable top

    /// The habitable top as a radial height-field grid, split into material
    /// layers.
    ///
    /// Smooth (area-weighted) normals rather than the flat shading the flank
    /// uses: a 2.6 k-triangle swell shaded flat would read as noise, and the
    /// point of the relief is a soft gradient the key light can grade across.
    @MainActor
    private static func buildTop(
        fragment: Fragment,
        angles: [Float],
        rimRadii: [Float],
        water: WaterMask
    ) -> MeshResource {
        let radius = fragment.radius

        // Ring 0 is the centre point, repeated so the grid stays rectangular.
        // The ease pushes rings slightly outward, which concentrates resolution
        // where the rim fall and the shore darkening happen.
        var grid = [[SIMD3<Float>]](
            repeating: [SIMD3<Float>](repeating: .zero, count: sideCount),
            count: ringCount + 1
        )
        for ring in 0...ringCount {
            let t = ringEase(ring)
            for index in 0..<sideCount {
                let r = rimRadii[index] * t
                let x = cos(angles[index]) * r
                let z = sin(angles[index]) * r
                grid[ring][index] = [x, groundHeight(local: [x, z], radius: radius), z]
            }
        }

        // Area-weighted normals: accumulate every face normal into its three
        // corners, then normalise. Cheap, and exactly consistent with the
        // triangles that actually ship.
        var accumulated = [[SIMD3<Float>]](
            repeating: [SIMD3<Float>](repeating: .zero, count: sideCount),
            count: ringCount + 1
        )
        func accumulate(_ ringA: Int, _ indexA: Int,
                        _ ringB: Int, _ indexB: Int,
                        _ ringC: Int, _ indexC: Int) {
            let a = grid[ringA][indexA], b = grid[ringB][indexB], c = grid[ringC][indexC]
            // Unnormalised on purpose: its length is twice the triangle area,
            // which is the weighting we want.
            let normal = simd_cross(b - a, c - a)
            guard simd_length_squared(normal) > 1e-16 else { return }
            let up = normal.y < 0 ? -normal : normal
            accumulated[ringA][indexA] += up
            accumulated[ringB][indexB] += up
            accumulated[ringC][indexC] += up
        }

        for ring in 0..<ringCount {
            for index in 0..<sideCount {
                guard !water.isDrowned(ring: ring, index: index) else { continue }
                let next = (index + 1) % sideCount
                if ring == 0 {
                    accumulate(0, index, 1, index, 1, next)
                } else {
                    accumulate(ring, index, ring, next, ring + 1, next)
                    accumulate(ring, index, ring + 1, next, ring + 1, index)
                }
            }
        }

        // The centre is one physical vertex shared by every sector, so its
        // normal is the sum of all of them rather than any single sector's.
        var centreNormal = SIMD3<Float>.zero
        for index in 0..<sideCount { centreNormal += accumulated[0][index] }
        for index in 0..<sideCount { accumulated[0][index] = centreNormal }

        var normals = accumulated
        for ring in 0...ringCount {
            for index in 0..<sideCount {
                normals[ring][index] = MeshUV.direction(accumulated[ring][index], fallback: [0, 1, 0])
            }
        }

        var builders = [TopLayer: SmoothMeshBuilder]()
        for layer in TopLayer.allCases { builders[layer] = SmoothMeshBuilder() }

        func vertex(_ ring: Int, _ index: Int) -> SmoothMeshBuilder.Vertex {
            groundVertex(position: grid[ring][index], normal: normals[ring][index])
        }

        for ring in 0..<ringCount {
            for index in 0..<sideCount {
                // Water is a hole in the ground, so the ground simply is not built
                // here. `buildFlank` walls whatever edge this leaves open.
                guard !water.isDrowned(ring: ring, index: index) else { continue }
                let next = (index + 1) % sideCount

                if ring == 0 {
                    let a = vertex(0, index), b = vertex(1, index), c = vertex(1, next)
                    let layer = topLayer(
                        centroid: (a.position + b.position + c.position) / 3,
                        radius: radius,
                        rimRadius: rimRadii[index],
                        stipple: ProceduralNoise.hash(index, 0, Salt.splatStipple)
                    )
                    builders[layer]?.addTriangle(a, b, c)
                    continue
                }

                let a = vertex(ring, index)
                let b = vertex(ring, next)
                let c = vertex(ring + 1, next)
                let d = vertex(ring + 1, index)

                for (triangle, corners) in [(0, (a, b, c)), (1, (a, c, d))] {
                    let (p, q, r) = corners
                    let layer = topLayer(
                        centroid: (p.position + q.position + r.position) / 3,
                        radius: radius,
                        rimRadius: rimRadii[index],
                        stipple: ProceduralNoise.hash(index, ring * 2 + triangle, Salt.splatStipple)
                    )
                    builders[layer]?.addTriangle(p, q, r)
                }
            }
        }

        let parts = TopLayer.allCases.compactMap { layer -> MeshDescriptor? in
            builders[layer]?.makeDescriptor(
                named: "\(fragment.id.rawValue).top.\(layer)",
                materialIndex: UInt32(layer.rawValue)
            )
        }
        return assemble(parts, named: "\(fragment.id.rawValue).top")
    }

    /// One height-field vertex, with the planar XZ projection and the tangent
    /// frame that matches it.
    ///
    /// The tangent is world +X flattened onto the surface and the bitangent is
    /// `N x T`, which for level ground is -Z — exactly the basis the V
    /// coordinate below is measured along, so a normal map is lit with the frame
    /// it was authored for rather than a guess.
    private static func groundVertex(
        position: SIMD3<Float>,
        normal: SIMD3<Float>
    ) -> SmoothMeshBuilder.Vertex {
        let tangent = MeshUV.direction(
            SIMD3<Float>(1, 0, 0) - normal * normal.x,
            fallback: [1, 0, 0]
        )
        return SmoothMeshBuilder.Vertex(
            position: position,
            normal: normal,
            uv: SIMD2(position.x, -position.z) / groundMetersPerTile,
            tangent: tangent,
            bitangent: simd_cross(normal, tangent)
        )
    }

    // MARK: - Ground height field

    /// Fragment-local ground height at an XZ point, in metres. **Never
    /// positive.**
    ///
    /// Pure, deterministic and free of `DeterministicRandom`, so it can be
    /// sampled from anywhere — including the simulation-facing renderer code —
    /// without perturbing a stream.
    ///
    /// The contract other renderers should rely on:
    /// - the result is in `-2.0 ... 0`;
    /// - it is exactly `0` inside `panInner · radius` of the fragment centre, so
    ///   the Core and the opening buildings stand on true datum;
    /// - it falls off toward the rim, so ground meets the flank on a turn rather
    ///   than on a knife edge.
    ///
    /// Anything that wants to *sit* on the terrain — a decal, a prop, a unit —
    /// **must** offset its Y by this value. That is no longer advice: at this
    /// amplitude something that skips it hangs a metre or more over open ground.
    /// Work in world space through `TerrainSurface`; work in fragment-local space
    /// through `FlatMeshBuilder.lift` or by calling this directly.
    static func groundHeight(local point: SIMD2<Float>, radius: Float) -> Float {
        let safeRadius = max(radius, 0.001)
        let distance = simd_length(point)
        let t = distance / safeRadius

        // One noise tile spans the whole fragment, so a small outcrop and a big
        // home fragment swell at the same *relative* scale and read as the same
        // kind of land rather than as two different terrains.
        let span = safeRadius * 2.2
        let u = point.x / span + 0.5
        let v = point.y / span + 0.5

        let swell = ProceduralNoise.fbm(u, v, octaves: 3, cellsX: 3, cellsY: 3, salt: Salt.swell)
        let micro = ProceduralNoise.fbm(u, v, octaves: 2, cellsX: 14, cellsY: 14, salt: Salt.micro)

        var height = -(swellAmplitude * swell + microAmplitude * micro)

        // The compacted pan the settlement stands on: dead flat at datum out to
        // `panInner`, easing into the open field by `panOuter`. This is what lets
        // a Core, a farm and a citizen all sit exactly on the ground while the
        // rest of the fragment still has shape.
        let openness = ProceduralNoise.smoothstep(panInner, panOuter, t)
        height *= openness

        // A shallow trodden ring just outside the pan. Read from above the pan
        // then reads as *raised* worn ground, which is the correct story: it is
        // the part of the fragment that has been walked flat.
        let ringIn = ProceduralNoise.smoothstep(panInner, panMid, t)
        let ringOut = 1 - ProceduralNoise.smoothstep(panMid, panRingEnd, t)
        height -= dishDepth * ringIn * ringOut

        // The top turns down into the cliff rather than ending as a plane.
        height -= rimFall * ProceduralNoise.smoothstep(0.80, 1.02, t)

        return min(height, 0)
    }

    /// Amplitude of the broad ground swell.
    ///
    /// The whole relief block below was authored at roughly a quarter of these
    /// values, giving a total range of 0.55 m across a 24 m fragment — half a
    /// percent of the diameter, which rendered as one flat facet. The cap was
    /// not caution about the terrain; it was the datum rule, because nothing
    /// outside this file sampled `groundHeight` and anything larger would have
    /// floated every unit and prop over its own ground. `TerrainSurface` and
    /// `FlatMeshBuilder.lift` removed that constraint, so the amplitude is now
    /// set by what the land should look like.
    ///
    /// 3 noise cells across `radius * 2.2` puts the swell's wavelength near 18 m
    /// on a home fragment — broad dunes the key light can grade across, rather
    /// than a rumple.
    ///
    /// What matters to the frame is the *slope*, not the amplitude, and fbm is
    /// far gentler than its amplitude suggests: three octaves rarely approach the
    /// gradient a sinusoid of the same height would have. Rendered at 0.95 the
    /// relief measured a low-frequency luminance swing of only ±0.07 against the
    /// flat build — present, but not something you would call terrain. 2.1 is
    /// that measurement scaled to the swing the concept's ground carries, and it
    /// stays cheap for `chordError` because the error falls with the square of
    /// the wavelength and this is the longest one in the field.
    private static let swellAmplitude: Float = 2.1
    /// Amplitude of the fine relief riding on the swell.
    ///
    /// Deliberately much smaller than the swell, and bounded by `chordError`
    /// rather than by taste: this term has the shortest wavelength in the field,
    /// so it dominates the gap between the true surface and the triangles that
    /// approximate it, and that gap is what ground decals have to be lifted over.
    /// Tried at 0.16 first, which put the chord error at 0.18 m and swallowed
    /// most of the gold seam network into the terrain.
    ///
    /// Fine grain is the texture's job. This is here only to stop the swell
    /// reading as a smooth analytic surface.
    private static let microAmplitude: Float = 0.08
    /// Depth of the worn ring around the settlement pan.
    private static let dishDepth: Float = 0.30
    /// How far the ground falls as it turns into the flank.
    private static let rimFall: Float = 0.55
    /// Fraction of the nominal radius that is dead-flat datum.
    private static let panInner: Float = 0.17
    /// Where the worn ring is deepest.
    private static let panMid: Float = 0.29
    /// Where the pan has fully eased into the open field.
    private static let panOuter: Float = 0.36
    /// Where the worn ring has faded out.
    private static let panRingEnd: Float = 0.46

    // MARK: - Ground splat

    /// Which material layer a patch of the habitable top belongs to.
    ///
    /// Three masks, composited:
    /// - a **path** network — the compacted pan plus wandering spokes worn out
    ///   of it toward the rim, which is the single strongest cue that the ground
    ///   is *lived on* rather than generated;
    /// - **macro noise**, which breaks up the tiling the critic could see
    ///   directly ("a single tiled beige texture over the entire disc");
    /// - a **rim ramp**, which darkens and desaturates the outer third.
    ///
    /// `stipple` is a stable per-triangle hash. It dithers the thresholds, so
    /// the boundary between two layers is a stippled interlock a few triangles
    /// wide rather than a hard polygon edge — which at this triangle density is
    /// what makes four discrete layers read as a continuous blend.
    private static func topLayer(
        centroid: SIMD3<Float>,
        radius: Float,
        rimRadius: Float,
        stipple: Float
    ) -> TopLayer {
        let point = SIMD2<Float>(centroid.x, centroid.z)
        let distance = simd_length(point)
        let edge = distance / max(rimRadius, 0.001)
        let field = distance / max(radius, 0.001)

        // Trodden ground.
        if field < panInner * 1.06 { return .path }
        if edge < 0.93 {
            let turns = atan2(point.y, point.x) / (2 * .pi) + 0.5
            // The spokes wander instead of being spokes of a wheel: without the
            // bend they read as a compass rose stamped on the ground.
            let bend = (wrappedNoise(turns, cells: 6, salt: Salt.pathBend) - 0.5) * 0.22
            let phase = (turns + bend) * pathSpokes
            let along = abs(phase - phase.rounded())
            // A path is broadest where it leaves the settlement and thins as it
            // runs out, the way real desire lines do.
            let width = 0.085 * (1 - ProceduralNoise.smoothstep(0.2, 0.95, field) * 0.62)
            if along < width + (stipple - 0.5) * 0.018 { return .path }
        }

        let span = max(radius, 0.001) * 2.2
        let macro = ProceduralNoise.fbm(
            point.x / span + 0.5,
            point.y / span + 0.5,
            octaves: 3,
            cellsX: 4,
            cellsY: 4,
            salt: Salt.splat
        )

        // The rim ramp is deliberately steep and deliberately late: nothing
        // happens until 55% out, and by the edge it alone is enough to force the
        // dark layer. That is the "darkening toward the rim" the flat disc had
        // none of.
        let ramp = ProceduralNoise.smoothstep(0.55, 1.0, edge)
        let darkness = macro * 0.60 + ramp * 0.90 + (stipple - 0.5) * 0.24

        if darkness > 0.72 { return .rimDark }
        if darkness > 0.44 { return .mid }
        return .pale
    }

    /// How many trodden paths leave the settlement.
    private static let pathSpokes: Float = 5

    // MARK: - Flank

    /// One stratum of the flank: how far in it pulls, and how far down it sits.
    private struct Stratum {
        var scale: ClosedRange<Float>
        var depth: ClosedRange<Float>
    }

    /// The flank's profile, rim to apex.
    ///
    /// Five rings instead of the old two. The old shape — rim, one shelf, one
    /// mid, apex — had a single horizontal break in it, which is why it read as
    /// a bevelled disc: one break is a chamfer, four are strata. Every ring
    /// jitters in *both* radius and height per sample, so adjacent facets get
    /// genuinely different normals and the rock has facet-to-facet contrast
    /// instead of grading smoothly around the circle like machined metal.
    private static let strata: [Stratum] = [
        Stratum(scale: 0.972...0.996, depth: 0.045...0.080),
        Stratum(scale: 0.900...0.968, depth: 0.170...0.265),
        Stratum(scale: 0.808...0.898, depth: 0.360...0.470),
        Stratum(scale: 0.650...0.788, depth: 0.560...0.680),
        Stratum(scale: 0.400...0.580, depth: 0.780...0.885),
    ]

    /// Which band each quad strip belongs to, rim-to-apex. The last entry covers
    /// the taper into the apex.
    private static let strataBands: [CliffBand] = [.lip, .bounce, .upper, .middle, .base, .base]

    @MainActor
    private static func buildFlank(
        fragment: Fragment,
        angles: [Float],
        rimRadii: [Float],
        isSpur: [Bool],
        water: WaterMask,
        seed: UInt64,
        random: inout DeterministicRandom
    ) -> MeshResource {
        // The flank's top ring is the top surface's outer ring, sampled from the
        // same height field. Anything else leaves a visible slot of void between
        // the ground and the rock it is supposed to be sitting on.
        let rim: [SIMD3<Float>] = (0..<sideCount).map { index in
            let x = cos(angles[index]) * rimRadii[index]
            let z = sin(angles[index]) * rimRadii[index]
            return [x, groundHeight(local: [x, z], radius: fragment.radius), z]
        }

        var rings: [[SIMD3<Float>]] = []
        for stratum in strata {
            var ring: [SIMD3<Float>] = []
            ring.reserveCapacity(sideCount)
            for index in 0..<sideCount {
                let scale = random.float(in: stratum.scale)
                let depth = -fragment.depth * random.float(in: stratum.depth)
                let r = rimRadii[index] * scale
                ring.append([cos(angles[index]) * r, depth, sin(angles[index]) * r])
            }
            rings.append(ring)
        }

        let apex = SIMD3<Float>(
            random.float(in: -0.12...0.12) * fragment.radius,
            -fragment.depth,
            random.float(in: -0.12...0.12) * fragment.radius
        )

        // Face-plane projection rather than box mapping: the flanks, the strata
        // and the hanging spurs are all arbitrarily slanted, and box mapping
        // stretches a slanted face by 1/cos θ against its dominant axis. On the
        // face's own plane there is no stretch at any angle — the stretch-free
        // result triplanar mapping exists to get — and the UV break at each facet
        // lands exactly where the normal already breaks, so it reads as a
        // different rock face rather than as an error.
        var builders = [CliffBand: FlatMeshBuilder]()
        for band in CliffBand.allCases {
            builders[band] = FlatMeshBuilder(uv: fragmentUVProjection)
        }

        // Rim -> strata -> apex, one quad strip per gap.
        var levels: [[SIMD3<Float>]] = [rim]
        levels.append(contentsOf: rings)

        for level in 0..<(levels.count - 1) {
            let band = strataBands[min(level, strataBands.count - 1)]
            let upper = levels[level]
            let lower = levels[level + 1]
            for index in 0..<sideCount {
                let next = (index + 1) % sideCount
                let outward = simd_normalize(SIMD3<Float>(upper[index].x, 0, upper[index].z))
                builders[band]?.addTriangle(upper[index], lower[index], lower[next], facing: outward)
                builders[band]?.addTriangle(upper[index], lower[next], upper[next], facing: outward)
            }
        }

        // The taper into the apex.
        if let last = levels.last {
            let band = strataBands[strataBands.count - 1]
            for index in 0..<sideCount {
                let next = (index + 1) % sideCount
                let outward = simd_normalize(SIMD3<Float>(last[index].x, 0, last[index].z))
                builders[band]?.addTriangle(last[index], apex, last[next], facing: outward - [0, 1, 0])
            }
        }

        if var spurBuilder = builders[.middle] {
            addHangingSpurs(
                into: &spurBuilder,
                shelf: rings[1],
                isSpur: isSpur,
                depth: fragment.depth,
                random: &random
            )
            builders[.middle] = spurBuilder
        }

        // Pale crystalline accents on the rim promontories — concept 01's edge
        // detail. Own stream so the flank's existing draws (and the island
        // silhouette they define) stay put.
        if shouldCrystalSpur(fragment), var crystalBuilder = builders[.crystal] {
            var crystalRandom = DeterministicRandom.stream(
                seed: seed,
                tag: "fragment.\(fragment.id.rawValue).crystalSpurs"
            )
            addCrystalSpurs(
                into: &crystalBuilder,
                rim: rim,
                angles: angles,
                isSpur: isSpur,
                radius: fragment.radius,
                random: &crystalRandom
            )
            builders[.crystal] = crystalBuilder
        }

        // Banks. Without these a river is a hole you can see the starfield through
        // from directly above and *nothing at all* from a low angle — the ground
        // just stops, one triangle thick, and the plate looks torn rather than
        // cut. The wall is what makes a channel read as having a near bank and a
        // far one.
        if !water.isEmpty, var bankBuilder = builders[.lip], var floorBuilder = builders[.abyss] {
            addBanks(
                into: &bankBuilder,
                floor: &floorBuilder,
                fragment: fragment,
                angles: angles,
                rimRadii: rimRadii,
                water: water
            )
            builders[.lip] = bankBuilder
            builders[.abyss] = floorBuilder
        }

        let parts = CliffBand.allCases.compactMap { band -> MeshDescriptor? in
            builders[band]?.makeDescriptor(
                named: "\(fragment.id.rawValue).under.\(band)",
                materialIndex: UInt32(band.rawValue)
            )
        }
        return assemble(parts, named: "\(fragment.id.rawValue).under")
    }

    /// How far a shoreline drops before the void takes over.
    ///
    /// Deep enough that the camera never sees under the lip at the shallowest
    /// pitch the rig allows, shallow enough that a narrow channel does not read as
    /// a slot canyon.
    private static let bankDrop: Float = 4.5

    /// Vertical walls around every drowned cell that borders dry ground.
    ///
    /// Each drowned cell offers its four edges; an edge is walled only where the
    /// neighbour across it survived, which is exactly the waterline. Working from
    /// the drowned side rather than the dry side means each boundary edge is
    /// considered once, so no wall is ever built twice and z-fights itself.
    private static func addBanks(
        into builder: inout FlatMeshBuilder,
        floor floorBuilder: inout FlatMeshBuilder,
        fragment: Fragment,
        angles: [Float],
        rimRadii: [Float],
        water: WaterMask
    ) {
        func vertex(ring: Int, index: Int) -> SIMD3<Float> {
            let wrapped = ((index % sideCount) + sideCount) % sideCount
            let r = rimRadii[wrapped] * ringEase(ring)
            let x = cos(angles[wrapped]) * r
            let z = sin(angles[wrapped]) * r
            return [x, groundHeight(local: [x, z], radius: fragment.radius), z]
        }

        func wall(_ a: SIMD3<Float>, _ b: SIMD3<Float>) {
            let lowerA = a - SIMD3<Float>(0, bankDrop, 0)
            let lowerB = b - SIMD3<Float>(0, bankDrop, 0)
            // Face the wall away from the water it encloses, which for a bank is
            // the horizontal normal of the edge pointing at the dry side.
            let along = b - a
            var facing = SIMD3<Float>(along.z, 0, -along.x)
            if simd_length_squared(facing) < 1e-8 { facing = [0, 0, 1] }
            builder.addTriangle(a, lowerA, lowerB, facing: facing)
            builder.addTriangle(a, lowerB, b, facing: facing)
        }

        /// How far below the surface the flank cone's own roof sits, at a radius
        /// `t` of the rim — the shallowest the rock under the plate ever is there.
        ///
        /// The floor has to stay above this or the cone pokes through it. Near the
        /// rim that roof is barely a metre down (`strata`'s first entry is 4.5% of
        /// the plate depth at 97% of the radius), which is why a floor at a single
        /// fixed drop worked in the middle of a lake and showed cracked rock at the
        /// mouth of a channel — the one place a player is always looking, because
        /// that is where the transports berth.
        func coneRoof(_ t: Float) -> Float {
            var upper = (scale: Float(1), depth: Float(0))
            for stratum in strata {
                let lower = (scale: stratum.scale.lowerBound, depth: stratum.depth.lowerBound)
                if t >= lower.scale {
                    let span = max(upper.scale - lower.scale, 0.0001)
                    let blend = (upper.scale - t) / span
                    return fragment.depth * (upper.depth + (lower.depth - upper.depth) * blend)
                }
                upper = lower
            }
            return fragment.depth
        }

        /// Caps a drowned cell with the void floor, as deep as the bank wall wants
        /// and no deeper than the rock beneath allows.
        func floor(_ ring: Int, _ index: Int) {
            let t = ringEase(ring + 1)
            let clearance: Float = 0.3
            let drop = SIMD3<Float>(0, min(bankDrop + 0.35, max(coneRoof(t) - clearance, 0.8)), 0)
            let a = vertex(ring: ring, index: index) - drop
            let b = vertex(ring: ring, index: index + 1) - drop
            let c = vertex(ring: ring + 1, index: index + 1) - drop
            let d = vertex(ring: ring + 1, index: index) - drop
            floorBuilder.addTriangle(a, c, b, facing: [0, 1, 0])
            floorBuilder.addTriangle(a, d, c, facing: [0, 1, 0])
        }

        for ring in 0..<ringCount {
            for index in 0..<sideCount {
                guard water.isDrowned(ring: ring, index: index) else { continue }
                let next = index + 1
                floor(ring, index)

                // Inward edge — the neighbour one ring closer to the centre.
                if ring > 0, !water.isDrowned(ring: ring - 1, index: index) {
                    wall(vertex(ring: ring, index: next), vertex(ring: ring, index: index))
                }
                // Outward edge.
                if ring + 1 < ringCount, !water.isDrowned(ring: ring + 1, index: index) {
                    wall(vertex(ring: ring + 1, index: index), vertex(ring: ring + 1, index: next))
                }
                // The two radial edges.
                if !water.isDrowned(ring: ring, index: index - 1) {
                    wall(vertex(ring: ring, index: index), vertex(ring: ring + 1, index: index))
                }
                if !water.isDrowned(ring: ring, index: next) {
                    wall(vertex(ring: ring + 1, index: next), vertex(ring: ring, index: next))
                }
            }
        }
    }

    /// Sharp rock hanging below the flank at the spur samples.
    ///
    /// This is the detail that says *torn loose* rather than *carved*. They hang
    /// from a stratum rather than from the rim, so they read as rock still
    /// attached to the underside instead of fins bolted to the edge.
    private static func addHangingSpurs(
        into builder: inout FlatMeshBuilder,
        shelf: [SIMD3<Float>],
        isSpur: [Bool],
        depth: Float,
        random: inout DeterministicRandom
    ) {
        let count = shelf.count
        guard count >= 3, isSpur.count == count else { return }

        func inset(_ point: SIMD3<Float>, _ factor: Float) -> SIMD3<Float> {
            [point.x * factor, point.y, point.z * factor]
        }

        for index in 0..<count where isSpur[index] {
            let previous = (index + count - 1) % count
            let next = (index + 1) % count

            // The base is a narrow sliver hugging one sample. Spanning the full
            // arc to both neighbours produced flat sheets the size of the island
            // rather than rock.
            func toward(_ other: SIMD3<Float>, _ amount: Float) -> SIMD3<Float> {
                shelf[index] + (other - shelf[index]) * amount
            }
            let a = inset(toward(shelf[previous], 0.55), 0.99)
            let b = inset(shelf[index], 0.74)
            let c = inset(toward(shelf[next], 0.55), 0.99)
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

    /// Pale crystalline spurs grow from the rim promontories, outward and up.
    ///
    /// The hanging stone spikes below already say *torn*; these say *mineral*.
    /// They sit on the lip so a 57° camera sees them as light accents along the
    /// rocky edge rather than as underside detail.
    private static func shouldCrystalSpur(_ fragment: Fragment) -> Bool {
        switch fragment.id {
        case .sunwovenHome, .sunwovenExpansion, .dominion, .neutralOutcropNorth, .neutralOutcropSouth:
            return true
        case .gravemarkHome, .gravemarkExpansion:
            return false
        }
    }

    private static func addCrystalSpurs(
        into builder: inout FlatMeshBuilder,
        rim: [SIMD3<Float>],
        angles: [Float],
        isSpur: [Bool],
        radius: Float,
        random: inout DeterministicRandom
    ) {
        let count = rim.count
        guard count >= 3, isSpur.count == count, angles.count == count else { return }

        for index in 0..<count where isSpur[index] {
            // Not every promontory: a full ring of identical crystals would read
            // as decoration bolted on. About two thirds keep the edge irregular.
            guard random.unitFloat() < 0.68 else { continue }

            let origin = rim[index]
            let outward = SIMD3<Float>(cos(angles[index]), 0, sin(angles[index]))
            let up = SIMD3<Float>(0, 1, 0)
            // Outward and slightly up — readable from above without becoming a
            // vertical fence along the rim.
            let axis = simd_normalize(outward * 0.78 + up * random.float(in: 0.42...0.72))
            let length = radius * random.float(in: 0.055...0.110)
            let crystalRadius = radius * random.float(in: 0.008...0.016)
            let sides = random.unitFloat() < 0.55 ? 5 : 4

            addCrystalPrism(
                into: &builder,
                base: origin + outward * (crystalRadius * 0.4) + up * 0.04,
                axis: axis,
                length: length,
                radius: crystalRadius,
                sides: sides,
                random: &random
            )

            // Occasional companion shard, shorter and more splayed.
            if random.unitFloat() < 0.45 {
                let yaw = angles[index] + random.float(in: -0.55...0.55)
                let sideOut = SIMD3<Float>(cos(yaw), 0, sin(yaw))
                let sideAxis = simd_normalize(sideOut * 0.70 + up * random.float(in: 0.30...0.60))
                addCrystalPrism(
                    into: &builder,
                    base: origin + sideOut * (crystalRadius * 0.8) + up * 0.02,
                    axis: sideAxis,
                    length: length * random.float(in: 0.45...0.75),
                    radius: crystalRadius * random.float(in: 0.55...0.80),
                    sides: 4,
                    random: &random
                )
            }
        }
    }

    /// A tapered prism along an arbitrary axis — same construction DepositMeshes
    /// uses for resource crystals, local so the flank does not import that file.
    private static func addCrystalPrism(
        into builder: inout FlatMeshBuilder,
        base: SIMD3<Float>,
        axis: SIMD3<Float>,
        length: Float,
        radius: Float,
        sides: Int,
        random: inout DeterministicRandom
    ) {
        let dir = simd_normalize(axis)
        // Build a stable orthonormal frame around the axis.
        let helper: SIMD3<Float> = abs(dir.y) < 0.9 ? [0, 1, 0] : [1, 0, 0]
        let tangent = simd_normalize(simd_cross(dir, helper))
        let bitangent = simd_normalize(simd_cross(dir, tangent))
        let phase = random.float(in: 0...(2 * .pi))

        func ring(at t: Float, scale: Float) -> [SIMD3<Float>] {
            let center = base + dir * (length * t)
            return (0..<sides).map { index in
                let angle = phase + Float(index) / Float(sides) * 2 * .pi
                let offset = (tangent * cos(angle) + bitangent * sin(angle)) * (radius * scale)
                return center + offset
            }
        }

        // Foot / belly / shoulder / tip — the belly is the widest so the prism
        // reads as a crystal rather than as a cone.
        let foot = ring(at: 0, scale: 0.72)
        let belly = ring(at: 0.28, scale: 1.00)
        let shoulder = ring(at: 0.72, scale: 0.55)
        let tip = base + dir * length

        func loft(_ lower: [SIMD3<Float>], _ upper: [SIMD3<Float>]) {
            for index in 0..<sides {
                let next = (index + 1) % sides
                let outward = simd_normalize(
                    (lower[index] + lower[next] + upper[index] + upper[next]) * 0.25 - (base + dir * length * 0.4)
                )
                builder.addTriangle(lower[index], upper[index], upper[next], facing: outward)
                builder.addTriangle(lower[index], upper[next], lower[next], facing: outward)
            }
        }

        loft(foot, belly)
        loft(belly, shoulder)
        for index in 0..<sides {
            let next = (index + 1) % sides
            let outward = simd_normalize((shoulder[index] + shoulder[next] + tip) / 3 - base)
            builder.addTriangle(shoulder[index], tip, shoulder[next], facing: outward)
        }
    }

    // MARK: - Materials

    /// The habitable top's material parts, in ``TopLayer`` order.
    ///
    /// Every tint here is a `shade` or a `blend` of the fragment's own locked
    /// palette pair. Nothing invents a hue: this is value and temperature
    /// separation on a palette that stays exactly where the bible put it.
    @MainActor
    static func topMaterials(surface: UIColor, rock: UIColor) -> [any RealityKit.Material] {
        // Cool toward the fragment's own rock so value falls stay inside one
        // shared land palette (civilization-independent since CP-12).
        let cool = StructureMaterial.blend(surface, rock, 0.30)

        // The array index is the material index emitted by the mesh descriptor;
        // keep both tied to this enum's rawValue/declaration order.
        return TopLayer.allCases.map { layer -> any RealityKit.Material in
            switch layer {
            case .pale:
                MaterialLibrary.material(.regolithGround, tint: surface, roughness: 0.94)
            case .mid:
                MaterialLibrary.material(
                    .regolithGround,
                    tint: StructureMaterial.shade(StructureMaterial.blend(surface, cool, 0.34), 0.94),
                    roughness: 0.96
                )
            case .rimDark:
                // The outer third. Darker *and* pulled toward the rock, so the
                // ground reads as running out of sun rather than as a grey wash
                // laid over it.
                MaterialLibrary.material(
                    .regolithGround,
                    tint: StructureMaterial.shade(StructureMaterial.blend(surface, rock, 0.42), 0.80),
                    roughness: 0.98
                )
            case .path:
                // Trodden ground is compacted, so it is *smoother* as well as
                // darker. The roughness drop is what makes a path catch the key
                // light along its length and read as a route.
                MaterialLibrary.material(
                    .regolithGround,
                    tint: StructureMaterial.shade(StructureMaterial.blend(surface, rock, 0.24), 0.88),
                    roughness: 0.70
                )
            }
        }
    }

    /// The flank's material parts, in ``CliffBand`` order.
    ///
    /// The gradient, top to bottom: a faintly lit sand-toned lip, a warm bounce
    /// third, neutral stone, a cooled and darkened mid, and a base at 45% of the
    /// stone's value — a 55% fall from lip to base, which is what gives the disc
    /// a readable thickness.
    @MainActor
    static func cliffMaterials(surface: UIColor, rock: UIColor) -> [any RealityKit.Material] {
        // Darkening the flank was tried first and was the wrong variable: in
        // concept 01 the rim rock is close to the habitable top in *value*, and
        // the read comes from it being cooler and from having real mass. Pulling
        // the palette rock toward a neutral cool grey separates it from the sand
        // without inventing a hue or fighting the key light. The blend is kept
        // here rather than in the recipe so the flank's hue still tracks
        // whichever fragment it belongs to.
        let stone = StructureMaterial.blend(rock, MaterialLibrary.coolStone, 0.46)

        // The array index is the material index emitted by the mesh descriptor;
        // keep both tied to this enum's rawValue/declaration order.
        return CliffBand.allCases.map { band -> any RealityKit.Material in
            switch band {
            case .lip:
                // The one emissive surface on the terrain, and it is doing a
                // specific job: against a black void an unlit silhouette reads as
                // a cut-out sticker, because there is nothing behind the island
                // to backlight it. A low emissive on the topmost centimetres of
                // rock draws that contour unconditionally — including on the far
                // side, where the key light never reaches — and sits just under
                // the post-process bright threshold, so it lifts rather than
                // blooms.
                MaterialLibrary.material(
                    .rimStone,
                    tint: StructureMaterial.shade(StructureMaterial.blend(stone, surface, 0.66), 1.04),
                    roughness: 0.86,
                    emissiveIntensity: 0.30
                )
            case .bounce:
                // Upper third: light that hit the sand and came back down. Warm
                // albedo plus a whisper of emissive, because the real bounce
                // this fakes has no light source the renderer can be given.
                MaterialLibrary.material(
                    .rimStone,
                    tint: StructureMaterial.blend(stone, surface, 0.36),
                    roughness: 0.94,
                    emissiveIntensity: 0.07
                )
            case .upper:
                MaterialLibrary.material(.rimStone, tint: stone, roughness: 0.98)
            case .middle:
                MaterialLibrary.material(
                    .rimStone,
                    tint: StructureMaterial.shade(
                        StructureMaterial.blend(stone, MaterialLibrary.coolStone, 0.18),
                        0.72
                    ),
                    roughness: 1.0
                )
            case .base:
                MaterialLibrary.material(
                    .rimStone,
                    tint: StructureMaterial.shade(
                        StructureMaterial.blend(stone, MaterialLibrary.coolStone, 0.30),
                        0.45
                    ),
                    roughness: 1.0
                )
            case .crystal:
                // Warm ivory on a warm crystalline surface — not a retint of
                // `.rimStone`, whose cold reference would mute any pale tint.
                MaterialLibrary.material(
                    .crystallineLumen,
                    tint: SunfoldPalette.sunwovenIvory,
                    roughness: 0.32,
                    emissiveIntensity: 1.1
                )
            case .abyss:
                // Unlit, and the backdrop's own colour. Lit would defeat the whole
                // purpose — a shaded floor picks up the key light and reads as a
                // dry basin, which is exactly the rock the floor was added to hide.
                // Unlit at `voidDeep` matches the space beyond the coast, so the
                // eye reads a channel and the open void as the same substance.
                UnlitMaterial(color: SunfoldPalette.voidDeep)
            }
        }
    }

    // MARK: - Assembly

    /// Combines material parts into one `MeshResource`.
    ///
    /// RealityKit gives the generated resource one part per descriptor, and each
    /// part carries the material index its descriptor declared — so
    /// `ModelComponent.materials[i]` lands on the layer that asked for `i`. Fails
    /// closed: a readable primitive and a loud warning, never a crash and never
    /// an invisible entity.
    @MainActor
    private static func assemble(_ parts: [MeshDescriptor], named name: String) -> MeshResource {
        guard !parts.isEmpty else {
            DebugLog.warn("Mesh '\(name)' had no parts; using fallback box.")
            return MeshResource.generateBox(size: 1)
        }
        do {
            return try MeshResource.generate(from: parts)
        } catch {
            DebugLog.warn("Mesh '\(name)' failed to generate (\(error)); using fallback box.")
            return MeshResource.generateBox(size: 1)
        }
    }

    // MARK: - Noise helpers

    /// Value noise around a circle. `turns` is in revolutions and wraps, so the
    /// outline it drives closes on itself with no seam at angle zero.
    private static func wrappedNoise(_ turns: Float, cells: Int, salt: UInt32) -> Float {
        var wrapped = turns.truncatingRemainder(dividingBy: 1)
        if wrapped < 0 { wrapped += 1 }
        return ProceduralNoise.value(wrapped, 0.5, cellsX: cells, cellsY: 1, salt: salt)
    }

    /// Fixed salts, so terrain is a pure function of position and never of call
    /// order. Distinct values keep the masks decorrelated — a swell crest must
    /// not coincide with a splat boundary just because both were seeded 0.
    private enum Salt {
        static let rimBroad: UInt32 = 0x5EED_0101
        static let rimCrag: UInt32 = 0x5EED_0202
        static let rimChew: UInt32 = 0x5EED_0303
        static let swell: UInt32 = 0x5EED_0404
        static let micro: UInt32 = 0x5EED_0505
        static let splat: UInt32 = 0x5EED_0606
        static let splatStipple: UInt32 = 0x5EED_0707
        static let pathBend: UInt32 = 0x5EED_0808
    }
}

/// Accumulates flat-shaded triangles: each face gets its own three vertices and
/// one normal, which is what produces the faceted low-poly read.
///
/// Optionally emits texture coordinates and a tangent frame. Because each face
/// already owns its three vertices, a per-face projection costs nothing extra —
/// there are no shared vertices to split at a UV seam. Pass a projection to
/// `init(uv:)` to turn it on; the default stays `.none`, so a factory that has
/// not adopted texturing yet produces exactly the mesh it produced before.
struct FlatMeshBuilder {
    private var positions: [SIMD3<Float>] = []
    private var normals: [SIMD3<Float>] = []
    private var textureCoordinates: [SIMD2<Float>] = []
    private var tangents: [SIMD3<Float>] = []
    private var bitangents: [SIMD3<Float>] = []
    private var indices: [UInt32] = []

    /// How surface points become UVs. See `MeshUVProjection`.
    let uvProjection: MeshUVProjection

    /// Vertical displacement applied to every position as it is added, keyed on
    /// that position's XZ. `nil` leaves geometry exactly where the caller put it.
    ///
    /// This is how anything built in fragment-local space comes to sit on the
    /// terrain instead of on the datum plane, and it deliberately supports both
    /// of the two answers that question has:
    ///
    /// - **Drape** — return the ground height at the sampled point, and a flat
    ///   decal follows the swell it lies on. Correct for seams, tone patches and
    ///   the shore band, which are ground.
    /// - **Rigid** — ignore the argument and return one constant for the whole
    ///   object, and it translates without shearing. Correct for a tree or a
    ///   boulder, which stands *on* the ground; draping those would bend the
    ///   trunk.
    ///
    /// Normals are computed after the displacement, from the positions that
    /// actually ship, so a draped decal is lit by the slope it lies on.
    var lift: ((SIMD2<Float>) -> Float)?

    init(uv projection: MeshUVProjection = .none) {
        self.uvProjection = projection
    }

    /// Whether anything survived the degeneracy check.
    var isEmpty: Bool { indices.isEmpty }

    private func displaced(_ point: SIMD3<Float>) -> SIMD3<Float> {
        guard let lift else { return point }
        return SIMD3<Float>(point.x, point.y + lift(SIMD2(point.x, point.z)), point.z)
    }

    /// Adds a triangle, correcting winding so the face points along `facing`.
    /// This removes any need to reason about vertex order at each call site.
    mutating func addTriangle(
        _ a: SIMD3<Float>,
        _ b: SIMD3<Float>,
        _ c: SIMD3<Float>,
        facing reference: SIMD3<Float>
    ) {
        // Displace before anything else reads these points: the winding fix, the
        // degeneracy check, the normal and the tangent frame must all describe
        // the triangle that actually ships, not the one on the datum plane.
        let a = displaced(a), b = displaced(b), c = displaced(c)

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

        // Projected after the winding fix, so the tangent frame agrees with the
        // normal the face actually shipped with.
        if let face = MeshUV.face(a, first, second, normal: normal, projection: uvProjection) {
            textureCoordinates.append(contentsOf: [face.a, face.b, face.c])
            tangents.append(contentsOf: [face.tangent, face.tangent, face.tangent])
            bitangents.append(contentsOf: [face.bitangent, face.bitangent, face.bitangent])
        }
    }

    /// The descriptor for these triangles, tagged with a material index.
    ///
    /// Returns `nil` when nothing was added, so a caller assembling several
    /// material parts can drop empty ones instead of handing RealityKit an empty
    /// buffer. `nil` is not an error: a fragment whose splat never chose a given
    /// layer legitimately has no geometry for it.
    func makeDescriptor(named name: String, materialIndex: UInt32) -> MeshDescriptor? {
        guard !indices.isEmpty else { return nil }
        var descriptor = MeshDescriptor(name: name)
        descriptor.positions = MeshBuffer(positions)
        descriptor.normals = MeshBuffer(normals)
        // Vertex-rate buffers must match `positions` exactly or the descriptor is
        // rejected, so they are attached only when the projection filled them.
        if textureCoordinates.count == positions.count {
            descriptor.textureCoordinates = MeshBuffer(textureCoordinates)
            // iOS 26.5 has no public tangent generation: `MeshResource.generate`
            // takes no options and `__MeshCompileOptions.repairTangents` is SPI
            // it gives no way to reach. A normal map is lit with a garbage basis
            // unless these two buffers are supplied here.
            descriptor.tangents = MeshBuffer(tangents)
            descriptor.bitangents = MeshBuffer(bitangents)
        }
        descriptor.primitives = .triangles(indices)
        descriptor.materials = .allFaces(materialIndex)
        return descriptor
    }

    /// `MeshResource` generation is main-actor isolated in RealityKit, so mesh
    /// assembly stays on the main actor with the rest of the scene build.
    @MainActor
    func makeMesh(named name: String) -> MeshResource {
        guard let descriptor = makeDescriptor(named: name, materialIndex: 0) else {
            DebugLog.warn("Mesh '\(name)' had no triangles; using fallback box.")
            return MeshResource.generateBox(size: 1)
        }
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

/// Accumulates triangles whose vertices carry their **own** normals, so a
/// generated surface can be smooth-shaded.
///
/// `FlatMeshBuilder` is right for authored rock, where every facet should read
/// as its own plane. It is exactly wrong for a height field: a 2.6 k-triangle
/// ground swell shaded per-face is visual noise, and the whole point of terrain
/// relief is a gradient soft enough for the key light to grade across. This
/// builder is the other half of that pair — the caller supplies the normal, the
/// UV and the tangent frame it already computed from the height field, and this
/// type only assembles buffers.
///
/// Vertices are not welded. At this density the memory is irrelevant, and
/// duplicating them means a surface can be split across several material parts
/// without a shared-vertex ownership problem at every boundary.
struct SmoothMeshBuilder {
    /// One fully-specified surface vertex.
    struct Vertex {
        var position: SIMD3<Float>
        var normal: SIMD3<Float>
        var uv: SIMD2<Float>
        var tangent: SIMD3<Float>
        var bitangent: SIMD3<Float>
    }

    private var positions: [SIMD3<Float>] = []
    private var normals: [SIMD3<Float>] = []
    private var textureCoordinates: [SIMD2<Float>] = []
    private var tangents: [SIMD3<Float>] = []
    private var bitangents: [SIMD3<Float>] = []
    private var indices: [UInt32] = []

    var isEmpty: Bool { indices.isEmpty }

    /// Adds a triangle, correcting winding so the geometric face agrees with the
    /// normals its vertices carry.
    mutating func addTriangle(_ a: Vertex, _ b: Vertex, _ c: Vertex) {
        let geometric = simd_cross(b.position - a.position, c.position - a.position)
        guard simd_length_squared(geometric) > 1e-14 else { return }

        var first = b, second = c
        if simd_dot(geometric, a.normal + b.normal + c.normal) < 0 {
            swap(&first, &second)
        }

        let base = UInt32(positions.count)
        for vertex in [a, first, second] {
            positions.append(vertex.position)
            normals.append(vertex.normal)
            textureCoordinates.append(vertex.uv)
            tangents.append(vertex.tangent)
            bitangents.append(vertex.bitangent)
        }
        indices.append(contentsOf: [base, base + 1, base + 2])
    }

    /// The descriptor for these triangles, tagged with a material index, or
    /// `nil` when nothing was added.
    func makeDescriptor(named name: String, materialIndex: UInt32) -> MeshDescriptor? {
        guard !indices.isEmpty else { return nil }
        var descriptor = MeshDescriptor(name: name)
        descriptor.positions = MeshBuffer(positions)
        descriptor.normals = MeshBuffer(normals)
        descriptor.textureCoordinates = MeshBuffer(textureCoordinates)
        descriptor.tangents = MeshBuffer(tangents)
        descriptor.bitangents = MeshBuffer(bitangents)
        descriptor.primitives = .triangles(indices)
        descriptor.materials = .allFaces(materialIndex)
        return descriptor
    }
}
