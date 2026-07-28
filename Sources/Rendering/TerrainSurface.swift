import Foundation
import simd

/// Where the ground actually is, in world space.
///
/// The simulation is planar: `WorldPoint` is an XZ pair and nothing in
/// `Sources/Simulation` or `Sources/Domain` has a notion of height. Terrain
/// relief is therefore **entirely presentational** — it changes where things are
/// drawn and never where they are, so it cannot affect pathing, range, selection
/// or any other rule. This is the one place that projects the flat truth onto the
/// rendered surface, and everything that needs to stand on the ground asks here.
///
/// Before this existed, `FragmentMeshFactory.groundHeight` had exactly two
/// callers, both inside the mesh factory itself. Nothing else sampled it, which
/// is why the relief amplitude had to stay under half a metre — see the datum
/// rule in `FragmentMeshFactory`. Anything larger and every unit, deposit and
/// building would have floated over its own ground.
enum TerrainSurface {

    /// Ground height at a world point, in metres, or `0` over the void.
    ///
    /// Fragments are placed at their centre with an identity rotation, so a
    /// fragment's local Y *is* world Y and no transform is needed on the result.
    static func groundY(at point: WorldPoint, in map: WorldMap) -> Float {
        guard let region = map.region(at: point) else { return 0 }
        let fragment = map.fragment(region)
        return FragmentMeshFactory.groundHeight(
            local: point - fragment.center,
            radius: fragment.radius
        )
    }

    /// The world position for something standing on the ground at `point`,
    /// raised by `lift` above the surface.
    static func standing(at point: WorldPoint, in map: WorldMap, lift: Float = 0) -> SIMD3<Float> {
        SIMD3<Float>(point.x, groundY(at: point, in: map) + lift, point.y)
    }
}
