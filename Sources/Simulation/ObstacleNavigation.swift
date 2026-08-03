import Foundation
import simd

/// A deterministic single-unit route over the authored ground and void fields.
///
/// This is deliberately not a crowd solver. It answers one question: which
/// points can one unit traverse when the map and occupied structures claim
/// space? Land and void use the same grid, tie-breaking, corner protection and
/// line-of-sight smoothing. The renderer receives the resulting planar
/// positions and remains a projection of simulation truth.
enum ObstacleNavigation {

    struct Route: Sendable, Equatable {
        let destination: WorldPoint
        let waypoints: [WorldPoint]
        let reachedRequestedDestination: Bool
    }

    private struct CircleObstacle: Sendable {
        let center: WorldPoint
        let radius: Float
    }

    private struct OpenNode {
        let index: Int
        let score: Float
        let heuristic: Float
    }

    private struct MinHeap {
        var storage: [OpenNode] = []

        mutating func push(_ item: OpenNode) {
            storage.append(item)
            var child = storage.count - 1
            while child > 0 {
                let parent = (child - 1) / 2
                guard ordered(storage[child], before: storage[parent]) else { break }
                storage.swapAt(child, parent)
                child = parent
            }
        }

        mutating func pop() -> OpenNode? {
            guard !storage.isEmpty else { return nil }
            if storage.count == 1 { return storage.removeLast() }

            let result = storage[0]
            storage[0] = storage.removeLast()
            var parent = 0
            while true {
                let left = parent * 2 + 1
                guard left < storage.count else { break }
                let right = left + 1
                var child = left
                if right < storage.count,
                   ordered(storage[right], before: storage[left]) {
                    child = right
                }
                guard ordered(storage[child], before: storage[parent]) else { break }
                storage.swapAt(parent, child)
                parent = child
            }
            return result
        }

        private func ordered(_ lhs: OpenNode, before rhs: OpenNode) -> Bool {
            if lhs.score != rhs.score { return lhs.score < rhs.score }
            if lhs.heuristic != rhs.heuristic { return lhs.heuristic < rhs.heuristic }
            return lhs.index < rhs.index
        }
    }

    private static let gridSpacing: Float = 1.0
    private static let lineSampleSpacing: Float = 0.30
    private static let obstaclePadding: Float = 0.25
    private static let depositBlockerRadius: Float = Deposit.workRadius - 0.15
    /// The transport footprint is visual and selectable size. Water legality
    /// follows the authored navigable fringe so narrow river mouths remain usable.
    static let voidClearance: Float = WorldMap.transportVoidClearance
    private static let maxGridCells = 16_384
    private static let maxVoidGridCells = 32_768

    #if DEBUG
    nonisolated(unsafe) static var planInvocationCount = 0

    static func resetPlanInvocationCount() {
        planInvocationCount = 0
    }
    #endif

    static func isLegal(
        _ point: WorldPoint,
        for unit: Unit,
        map: WorldMap,
        buildings: [EntityID: Building],
        deposits: [EntityID: Deposit]
    ) -> Bool {
        guard map.isTraversable(point, margin: unit.kind.footprintRadius) else {
            return false
        }
        return obstacles(
            for: unit,
            buildings: buildings,
            deposits: deposits
        ).allSatisfy { obstacle in
            simd_distance(point, obstacle.center) >= obstacle.radius
        }
    }

    static func isVoidLegal(
        _ point: WorldPoint,
        for unit: Unit,
        map: WorldMap,
        buildings: [EntityID: Building],
        deposits: [EntityID: Deposit]
    ) -> Bool {
        guard map.isNavigableVoid(point, margin: voidClearance) else {
            return false
        }
        return obstacles(
            for: unit,
            buildings: buildings,
            deposits: deposits
        ).allSatisfy { obstacle in
            simd_distance(point, obstacle.center) >= obstacle.radius
        }
    }

    /// Plans a route and returns the closest reachable legal endpoint when the
    /// requested point is blocked or disconnected. The endpoint is always a
    /// truthful movement destination, never the requested point by assertion.
    static func plan(
        from start: WorldPoint,
        to requested: WorldPoint,
        for unit: Unit,
        map: WorldMap,
        buildings: [EntityID: Building],
        deposits: [EntityID: Deposit]
    ) -> Route? {
        #if DEBUG
        planInvocationCount += 1
        #endif

        let obstacles = obstacles(
            for: unit,
            buildings: buildings,
            deposits: deposits
        )

        guard map.isTraversable(start, margin: unit.kind.footprintRadius) else {
            return nil
        }

        return planGrid(
            from: start,
            to: requested,
            searchBounds: map.bounds,
            padding: max(
                8,
                (obstacles.map(\.radius).max() ?? 0) + 3
            ),
            maxCells: maxGridCells,
            passable: { point in
                map.isTraversable(point, margin: unit.kind.footprintRadius)
                    && obstacles.allSatisfy { obstacle in
                        simd_distance(point, obstacle.center) >= obstacle.radius
                    }
            },
            fallback: {
                map.clampToTraversable(
                    requested,
                    from: start,
                    margin: unit.kind.footprintRadius
                )
            }
        )
    }

    /// Plans a route through connected navigable void. Unlike land orders, a
    /// transport never falls back to a nearest point on a different water body:
    /// an unreachable water target returns nil so the caller can reject it.
    static func planVoid(
        from start: WorldPoint,
        to requested: WorldPoint,
        for unit: Unit,
        map: WorldMap,
        buildings: [EntityID: Building] = [:],
        deposits: [EntityID: Deposit] = [:]
    ) -> Route? {
        #if DEBUG
        planInvocationCount += 1
        #endif

        let obstacles = obstacles(
            for: unit,
            buildings: buildings,
            deposits: deposits
        )
        let margin = voidClearance
        guard isVoidLegal(
                  start,
                  for: unit,
                  map: map,
                  buildings: buildings,
                  deposits: deposits
              ),
              isVoidLegal(
                  requested,
                  for: unit,
                  map: map,
                  buildings: buildings,
                  deposits: deposits
              )
        else { return nil }

        // A local box is enough for the common case. If the water body needs to
        // leave that box to reach an exterior-connected channel, grow the box in
        // deterministic powers of two. The final cap is the playable map plus a
        // small outer-water band, not an unbounded search.
        let maximumPadding = max(map.bounds.x, map.bounds.y)
        var padding = max(
            10,
            max(
                (obstacles.map(\.radius).max() ?? 0) + 3,
                margin + 2
            )
        )
        while true {
            guard let route = planGrid(
                from: start,
                to: requested,
                searchBounds: map.bounds + WorldPoint(repeating: 12),
                padding: padding,
                maxCells: maxVoidGridCells,
                passable: { point in
                    map.isNavigableVoid(point, margin: margin)
                        && obstacles.allSatisfy { obstacle in
                            simd_distance(point, obstacle.center) >= obstacle.radius
                        }
                },
                fallback: { start }
            ) else {
                return nil
            }

            let routeIsLegal = isVoidLegal(
                route.destination,
                for: unit,
                map: map,
                buildings: buildings,
                deposits: deposits
            ) && route.waypoints.allSatisfy {
                isVoidLegal(
                    $0,
                    for: unit,
                    map: map,
                    buildings: buildings,
                    deposits: deposits
                )
            }
            guard routeIsLegal else {
                guard padding < maximumPadding else { return nil }
                padding = min(padding * 2, maximumPadding)
                continue
            }

            if route.reachedRequestedDestination {
                return route
            }
            guard padding < maximumPadding else { return nil }
            padding = min(padding * 2, maximumPadding)
        }
    }

    private static func planGrid(
        from start: WorldPoint,
        to requested: WorldPoint,
        searchBounds: WorldPoint,
        padding: Float,
        maxCells: Int,
        passable: (WorldPoint) -> Bool,
        fallback: () -> WorldPoint
    ) -> Route? {
        let minX = max(
            -searchBounds.x,
            floor((min(start.x, requested.x) - padding) / gridSpacing) * gridSpacing
        )
        let maxX = min(
            searchBounds.x,
            ceil((max(start.x, requested.x) + padding) / gridSpacing) * gridSpacing
        )
        let minY = max(
            -searchBounds.y,
            floor((min(start.y, requested.y) - padding) / gridSpacing) * gridSpacing
        )
        let maxY = min(
            searchBounds.y,
            ceil((max(start.y, requested.y) + padding) / gridSpacing) * gridSpacing
        )

        let columns = max(Int(((maxX - minX) / gridSpacing).rounded(.up)) + 1, 2)
        let rows = max(Int(((maxY - minY) / gridSpacing).rounded(.up)) + 1, 2)
        let count = columns * rows
        guard count > 0 else { return nil }

        guard count <= maxCells else {
            let destination = fallback()
            return Route(
                destination: destination,
                waypoints: [destination],
                reachedRequestedDestination: destination == requested
            )
        }

        func point(for index: Int) -> WorldPoint {
            let row = index / columns
            let column = index % columns
            return WorldPoint(
                minX + Float(column) * gridSpacing,
                minY + Float(row) * gridSpacing
            )
        }

        func nearestIndex(to point: WorldPoint) -> Int {
            let column = min(
                max(Int(((point.x - minX) / gridSpacing).rounded()), 0),
                columns - 1
            )
            let row = min(
                max(Int(((point.y - minY) / gridSpacing).rounded()), 0),
                rows - 1
            )
            return row * columns + column
        }

        let startIndex = nearestIndex(to: start)
        let goalIndex = nearestIndex(to: requested)
        let startAndGoalShareCell = startIndex == goalIndex
        var points = (0..<count).map(point)
        // Preserve exact order and arrival positions. The rest of the graph is
        // still a fixed lattice, so this does not depend on dictionary order.
        points[startIndex] = start
        if !startAndGoalShareCell {
            points[goalIndex] = requested
        }

        let walkable = points.map(passable)
        guard walkable[startIndex] else { return nil }

        let directions: [(column: Int, row: Int, cost: Float)] = [
            (-1, 0, 1), (1, 0, 1), (0, -1, 1), (0, 1, 1),
            (-1, -1, 1.4142135), (1, -1, 1.4142135),
            (-1, 1, 1.4142135), (1, 1, 1.4142135),
        ]

        func lineIsClear(from: WorldPoint, to: WorldPoint) -> Bool {
            let distance = simd_distance(from, to)
            let samples = max(Int(ceil(distance / lineSampleSpacing)), 1)
            for sample in 1...samples {
                let fraction = Float(sample) / Float(samples)
                let point = from + (to - from) * fraction
                guard passable(point) else { return false }
            }
            return true
        }

        if startAndGoalShareCell {
            let canReach = passable(requested) && lineIsClear(from: start, to: requested)
            let destination = canReach ? requested : start
            return Route(
                destination: destination,
                waypoints: [destination],
                reachedRequestedDestination: canReach
            )
        }

        let heuristic = { (index: Int) -> Float in
            simd_distance(points[index], requested)
        }

        var gScore = Array(repeating: Float.greatestFiniteMagnitude, count: count)
        var cameFrom = Array(repeating: -1, count: count)
        var closed = Array(repeating: false, count: count)
        var open = MinHeap()
        gScore[startIndex] = 0
        open.push(OpenNode(
            index: startIndex,
            score: heuristic(startIndex),
            heuristic: heuristic(startIndex)
        ))

        var bestIndex = startIndex
        var bestDistance = heuristic(startIndex)
        var reachedRequestedDestination = false

        while let current = open.pop() {
            guard !closed[current.index] else { continue }
            closed[current.index] = true

            let distanceToGoal = heuristic(current.index)
            if distanceToGoal < bestDistance
                || (distanceToGoal == bestDistance && current.index < bestIndex) {
                bestDistance = distanceToGoal
                bestIndex = current.index
            }

            if current.index == goalIndex, walkable[goalIndex] {
                reachedRequestedDestination = true
                bestIndex = goalIndex
                break
            }

            let currentRow = current.index / columns
            let currentColumn = current.index % columns
            for direction in directions {
                let nextColumn = currentColumn + direction.column
                let nextRow = currentRow + direction.row
                guard nextColumn >= 0, nextColumn < columns,
                      nextRow >= 0, nextRow < rows
                else { continue }

                let next = nextRow * columns + nextColumn
                guard walkable[next], !closed[next] else { continue }

                // Do not cut a diagonal corner between two blocked cells.
                if direction.column != 0, direction.row != 0 {
                    let horizontal = currentRow * columns + nextColumn
                    let vertical = nextRow * columns + currentColumn
                    guard walkable[horizontal], walkable[vertical] else { continue }
                }

                guard lineIsClear(from: points[current.index], to: points[next]) else {
                    continue
                }

                let candidate = gScore[current.index] + direction.cost
                guard candidate < gScore[next] else { continue }
                gScore[next] = candidate
                cameFrom[next] = current.index
                let nextHeuristic = heuristic(next)
                open.push(OpenNode(
                    index: next,
                    score: candidate + nextHeuristic,
                    heuristic: nextHeuristic
                ))
            }
        }

        guard closed[bestIndex] else { return nil }
        var indices = [bestIndex]
        var cursor = bestIndex
        while cursor != startIndex {
            let parent = cameFrom[cursor]
            guard parent >= 0 else { break }
            indices.append(parent)
            cursor = parent
        }
        indices.reverse()

        let routePoints = indices.map { points[$0] }
        var waypoints: [WorldPoint] = []
        var anchor = start
        var routeIndex = 0
        while routeIndex < routePoints.count {
            var furthest = routeIndex
            for candidate in routeIndex..<routePoints.count
                where lineIsClear(from: anchor, to: routePoints[candidate]) {
                furthest = candidate
            }

            let point = routePoints[furthest]
            if simd_distance(anchor, point) > 0.01 {
                waypoints.append(point)
                anchor = point
            }
            routeIndex = furthest + 1
        }

        let destination = waypoints.last ?? start
        if simd_distance(destination, start) <= 0.01 {
            waypoints = [start]
        }
        return Route(
            destination: destination,
            waypoints: waypoints,
            reachedRequestedDestination: reachedRequestedDestination
        )
    }

    private static func obstacles(
        for unit: Unit,
        buildings: [EntityID: Building],
        deposits: [EntityID: Deposit]
    ) -> [CircleObstacle] {
        let unitRadius = unit.kind.footprintRadius
        let structures = buildings.values.sorted { $0.id.raw < $1.id.raw }.map { building in
            CircleObstacle(
                center: building.position,
                radius: building.kind.footprintRadius + unitRadius + obstaclePadding
            )
        }
        let nodes = deposits.values.sorted { $0.id.raw < $1.id.raw }.map { deposit in
            // WorkRadius is already a centre-to-centre clearance for a Citizen.
            // Keep the small visual skirt inside it so work stations remain legal,
            // while the cluster itself remains a hard route obstacle.
            CircleObstacle(center: deposit.position, radius: depositBlockerRadius)
        }
        return structures + nodes
    }
}
