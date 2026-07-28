import Foundation
import simd

/// The coastline of a map, as closed loops on the world plane.
///
/// The minimap used to draw one jittered outline per plate and stroke each of
/// them. That is a faithful picture of how the land is *built* and a misleading
/// picture of what it *is*: seven overlapping discs, each with its own edge drawn
/// across the middle of the landmass, which is exactly why the theatre read as a
/// pile of circles no matter how irregular the individual outlines got. It also
/// had no way at all to show a lake, because a lake is a hole and a per-plate
/// outline has no holes in it.
///
/// Contouring the land field instead gives the thing itself: one loop around the
/// coast, one more around every lake, and channels appearing as the gaps they
/// are. Marching squares is enough — the field is cheap to sample and the result
/// is cached per map, so this runs once and is then just a path.
enum LandContour {

    /// Closed loops in world space. Outer coasts wind one way and holes the
    /// other, so filling the whole set with the non-zero rule leaves lakes empty
    /// without anyone having to identify which loop is which.
    struct Result: Sendable {
        var loops: [[WorldPoint]]
        /// The land's own half-extent, for fitting. Not `WorldMap.bounds`, which
        /// is a camera limit and deliberately wider than the rock.
        var extent: WorldPoint
    }

    /// Traces `map`'s coastline.
    ///
    /// - Parameter resolution: samples across the longer axis. 220 puts a cell at
    ///   roughly one metre on these maps, which is finer than a 192 pt minimap can
    ///   show and cheap enough to run on a background pass at scene build.
    static func trace(_ map: WorldMap, resolution: Int = 220) -> Result {
        var extent = WorldPoint.zero
        for id in RegionID.allCases {
            let fragment = map.fragment(id)
            let reach = fragment.maxReach
            extent.x = max(extent.x, abs(fragment.center.x) + reach)
            extent.y = max(extent.y, abs(fragment.center.y) + reach)
        }
        // Erosion can push the coast past every plate's nominal reach, and here —
        // unlike the camera bounds, which only want a sensible margin — the figure
        // has to be the field's true maximum. Land that reaches the edge of this
        // grid leaves a contour that never closes, and an unclosed loop gets shut
        // by a chord straight across the map: a black slash through the minimap.
        extent += WorldPoint(repeating: max(map.erosion.amplitude + map.erosion.bias, 0))
        // A margin of one cell all round guarantees the border samples are void,
        // so every loop closes instead of running off the edge of the grid.
        extent *= 1.02

        let longest = max(extent.x, extent.y)
        let cell = longest * 2 / Float(max(resolution, 16))
        let columns = Int((extent.x * 2 / cell).rounded(.up)) + 2
        let rows = Int((extent.y * 2 / cell).rounded(.up)) + 2
        let origin = WorldPoint(-extent.x - cell, -extent.y - cell)

        var land = [Bool](repeating: false, count: (columns + 1) * (rows + 1))
        func point(_ column: Int, _ row: Int) -> WorldPoint {
            origin + WorldPoint(Float(column) * cell, Float(row) * cell)
        }
        for row in 0...rows {
            for column in 0...columns {
                land[row * (columns + 1) + column] = map.isLand(point(column, row))
            }
        }
        func isLand(_ column: Int, _ row: Int) -> Bool {
            guard column >= 0, column <= columns, row >= 0, row <= rows else { return false }
            return land[row * (columns + 1) + column]
        }
        /// Only the saddle cells need this, so it is sampled on demand rather than
        /// doubling the size of the lattice above.
        func isLandAt(_ point: WorldPoint) -> Bool { map.isLand(point) }

        // Every boundary edge, keyed by its start so loops can be walked. The
        // segments are emitted with land on the left, which is what makes outer
        // coasts and lake holes wind opposite ways.
        var edges: [Edge: Edge] = [:]
        func add(_ from: WorldPoint, _ to: WorldPoint) {
            edges[Edge(from, cell: cell)] = Edge(to, cell: cell)
        }

        for row in 0..<rows {
            for column in 0..<columns {
                let corners =
                    (isLand(column, row) ? 1 : 0)
                    | (isLand(column + 1, row) ? 2 : 0)
                    | (isLand(column + 1, row + 1) ? 4 : 0)
                    | (isLand(column, row + 1) ? 8 : 0)
                guard corners != 0, corners != 15 else { continue }

                let base = point(column, row)
                let south = base + WorldPoint(cell / 2, 0)
                let east = base + WorldPoint(cell, cell / 2)
                let north = base + WorldPoint(cell / 2, cell)
                let west = base + WorldPoint(0, cell / 2)

                switch corners {
                case 1: add(west, south)
                case 2: add(south, east)
                case 3: add(west, east)
                case 4: add(east, north)
                // Saddles. Two diagonally opposite land corners can be joined
                // through the middle of the cell or pinched apart, and the corner
                // samples alone cannot say which — pick wrong and the two segments
                // are threaded into the wrong loops, which breaks the chain and
                // leaves an open contour. Sampling the centre settles it.
                case 5:
                    if isLandAt(base + WorldPoint(cell / 2, cell / 2)) {
                        add(west, north); add(east, south)
                    } else {
                        add(west, south); add(east, north)
                    }
                case 6: add(south, north)
                case 7: add(west, north)
                case 8: add(north, west)
                case 9: add(north, south)
                case 10:
                    if isLandAt(base + WorldPoint(cell / 2, cell / 2)) {
                        add(north, east); add(south, west)
                    } else {
                        add(north, west); add(south, east)
                    }
                case 11: add(north, east)
                case 12: add(east, west)
                case 13: add(east, south)
                case 14: add(south, west)
                default: break
                }
            }
        }

        var loops: [[WorldPoint]] = []
        while let start = edges.keys.first {
            var loop: [WorldPoint] = []
            var cursor = start
            while let next = edges[cursor] {
                edges.removeValue(forKey: cursor)
                loop.append(cursor.point(cell: cell))
                cursor = next
            }
            // Two cells is smaller than anything the minimap can show, and at this
            // resolution a stray one is a rounding artefact rather than an islet.
            if loop.count > 3 { loops.append(smooth(loop, passes: 2)) }
        }

        return Result(loops: loops, extent: extent)
    }

    /// A lattice half-point, quantised so the two cells that share an edge agree
    /// on its identity. Comparing floats here loses loops to rounding.
    private struct Edge: Hashable {
        let x: Int32
        let y: Int32

        init(_ point: WorldPoint, cell: Float) {
            x = Int32((point.x / (cell / 2)).rounded())
            y = Int32((point.y / (cell / 2)).rounded())
        }

        func point(cell: Float) -> WorldPoint {
            WorldPoint(Float(x) * cell / 2, Float(y) * cell / 2)
        }
    }

    /// Rounds off the lattice staircase, by Chaikin corner-cutting.
    ///
    /// Marching squares can only ever emit segments between cell-edge midpoints,
    /// so a raw loop is a run of 45° and 90° steps. It needs *smoothing*, not
    /// decimation — the first version of this decimated instead, and a coastline
    /// with every low-amplitude vertex thrown away is a cut-out polygon. That
    /// deleted exactly the fray and lobe detail the whole checkpoint is about.
    ///
    /// Two passes take the step out while leaving anything a cell or more across
    /// intact, and cost four times the vertices — which is nothing for a path
    /// traced once per map and then only stroked.
    private static func smooth(_ loop: [WorldPoint], passes: Int) -> [WorldPoint] {
        var current = loop
        for _ in 0..<passes {
            guard current.count > 6 else { break }
            var next: [WorldPoint] = []
            next.reserveCapacity(current.count * 2)
            for index in 0..<current.count {
                let a = current[index]
                let b = current[(index + 1) % current.count]
                next.append(a + (b - a) * 0.25)
                next.append(a + (b - a) * 0.75)
            }
            current = next
        }
        return current
    }
}
