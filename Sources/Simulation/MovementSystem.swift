import Foundation
import simd

/// Advances unit positions. Pure and deterministic: same state plus same step
/// duration always yields the same result, with no dependence on frame timing.
///
/// Land units and Light Transports follow deterministic obstacle routes.
enum MovementSystem {

    /// How close counts as arrived. Larger than a single step's travel so a unit
    /// cannot oscillate around its destination.
    static let arrivalRadius: Float = 0.35
    private static let destinationEpsilon: Float = 0.05

    /// Advances every unit that has somewhere to be.
    static func step(
        units: inout [EntityID: Unit],
        map: WorldMap,
        buildings: [EntityID: Building] = [:],
        deposits: [EntityID: Deposit] = [:],
        deltaTime: Double
    ) {
        // Iterating a sorted key list keeps the update order stable across runs;
        // dictionary order is not guaranteed and would break replay.
        for id in units.keys.sorted(by: { $0.raw < $1.raw }) {
            guard var unit = units[id] else { continue }
            advance(
                &unit,
                map: map,
                buildings: buildings,
                deposits: deposits,
                deltaTime: deltaTime
            )
            units[id] = unit
        }
    }

    private static func advance(
        _ unit: inout Unit,
        map: WorldMap,
        buildings: [EntityID: Building],
        deposits: [EntityID: Deposit],
        deltaTime: Double
    ) {
        // A unit riding a transport is carried, not walked.
        guard !unit.isAboard else { return }
        guard var destination = unit.destination else {
            unit.movementPath = []
            unit.movementPathTarget = nil
            return
        }

        if unit.kind.travelsVoid {
            advanceVoid(
                &unit,
                destination: destination,
                map: map,
                buildings: buildings,
                deposits: deposits,
                deltaTime: deltaTime
            )
            return
        }

        // FI-03 owns the grounded Citizen route. Keep combat-unit movement on
        // its existing terrain clamp so this ticket does not change chasing.
        guard unit.kind == .citizen else {
            advanceLegacyLand(&unit, destination: destination, map: map, deltaTime: deltaTime)
            return
        }

        guard case .moving = unit.activity else {
            advanceLegacyLand(&unit, destination: destination, map: map, deltaTime: deltaTime)
            return
        }

        // Only explicit player orders carry a stored route. Assignment-driven
        // destinations keep the original cheap movement path and must not invoke
        // the obstacle planner on every gathering or construction tick.
        guard unit.movementPathTarget != nil || !unit.movementPath.isEmpty else {
            advanceLegacyLand(&unit, destination: destination, map: map, deltaTime: deltaTime)
            return
        }

        // Gathering and construction rewrite the same destination every tick.
        // Preserve the stored route when that rewrite is within the arrival
        // epsilon, rather than treating float noise as a new order.
        if let target = unit.movementPathTarget,
           simd_distance(target, destination) <= destinationEpsilon {
            destination = target
            unit.destination = target
        }

        if simd_distance(unit.position, destination) <= 0.001 {
            unit.destination = nil
            unit.movementPath = []
            unit.movementPathTarget = nil
            unit.region = map.region(at: unit.position)
            if case .moving = unit.activity { unit.activity = .idle }
            return
        }

        let destinationChanged = unit.movementPathTarget.map {
            simd_distance($0, destination) > destinationEpsilon
        } ?? true
        if destinationChanged || unit.movementPath.isEmpty {
            guard let route = ObstacleNavigation.plan(
                from: unit.position,
                to: destination,
                for: unit,
                map: map,
                buildings: buildings,
                deposits: deposits
            ) else {
                stopAtLegalPoint(&unit, map: map)
                return
            }
            destination = route.destination
            unit.destination = destination
            unit.movementPath = route.waypoints
            unit.movementPathTarget = destination
        }

        while let waypoint = unit.movementPath.first,
              simd_distance(unit.position, waypoint) <= 0.01 {
            unit.movementPath.removeFirst()
        }

        guard let waypoint = unit.movementPath.first else {
            unit.destination = nil
            unit.movementPathTarget = nil
            if case .moving = unit.activity { unit.activity = .idle }
            return
        }

        let toWaypoint = waypoint - unit.position
        let distance = simd_length(toWaypoint)
        guard distance > 0.0001 else { return }

        let heading = toWaypoint / distance
        let travel = min(max(unit.kind.speed * Float(deltaTime), 0), distance)
        guard travel > 0 else { return }
        let proposed = unit.position + heading * travel

        guard ObstacleNavigation.isLegal(
            proposed,
            for: unit,
            map: map,
            buildings: buildings,
            deposits: deposits
        ) else {
            // A newly completed foundation or deposit change invalidates an old
            // path. Replan from the current legal point; never slide along the
            // blocker or cross it by clamping the point sideways.
            guard let route = ObstacleNavigation.plan(
                from: unit.position,
                to: destination,
                for: unit,
                map: map,
                buildings: buildings,
                deposits: deposits
            ), route.destination != unit.position || route.reachedRequestedDestination else {
                stopAtLegalPoint(&unit, map: map)
                return
            }
            unit.destination = route.destination
            unit.movementPath = route.waypoints
            unit.movementPathTarget = route.destination
            return
        }

        unit.position = proposed
        unit.region = map.region(at: unit.position)
        if case .idle = unit.activity { unit.activity = .moving }

        if travel >= distance - 0.0001 {
            unit.movementPath.removeFirst()
            if unit.movementPath.isEmpty {
                unit.destination = nil
                unit.movementPathTarget = nil
                if case .moving = unit.activity { unit.activity = .idle }
            }
        }
    }

    private static func advanceVoid(
        _ unit: inout Unit,
        destination: WorldPoint,
        map: WorldMap,
        buildings: [EntityID: Building],
        deposits: [EntityID: Deposit],
        deltaTime: Double
    ) {
        // An invalid start cannot be allowed to fall through to a straight-line
        // step. Reject the stale order and leave the hull where it is; a fresh
        // player order must start from legal void water.
        guard map.isNavigableVoid(
            unit.position,
            margin: ObstacleNavigation.voidClearance
        ) else {
            stopAtVoidPoint(&unit)
            return
        }

        if simd_distance(unit.position, destination) <= 0.001 {
            unit.destination = nil
            unit.movementPath = []
            unit.movementPathTarget = nil
            unit.region = nil
            if case .moving = unit.activity { unit.activity = .idle }
            return
        }

        let destinationChanged = unit.movementPathTarget.map {
            simd_distance($0, destination) > destinationEpsilon
        } ?? true
        if destinationChanged || unit.movementPath.isEmpty {
            guard let route = ObstacleNavigation.planVoid(
                from: unit.position,
                to: destination,
                for: unit,
                map: map,
                buildings: buildings,
                deposits: deposits
            ) else {
                stopAtVoidPoint(&unit)
                return
            }
            unit.destination = route.destination
            unit.movementPath = route.waypoints
            unit.movementPathTarget = route.destination
        }

        while let waypoint = unit.movementPath.first,
              simd_distance(unit.position, waypoint) <= 0.01 {
            unit.movementPath.removeFirst()
        }

        guard let waypoint = unit.movementPath.first else {
            stopAtVoidPoint(&unit)
            return
        }

        let toWaypoint = waypoint - unit.position
        let distance = simd_length(toWaypoint)
        guard distance > 0.0001 else { return }

        let heading = toWaypoint / distance
        let travel = min(max(unit.kind.speed * Float(deltaTime), 0), distance)
        guard travel > 0 else { return }
        let proposed = unit.position + heading * travel
        guard ObstacleNavigation.isVoidLegal(
            proposed,
            for: unit,
            map: map,
            buildings: buildings,
            deposits: deposits
        ) else {
            // A newly completed foundation or changed map-owned obstacle cannot
            // invalidate a route into an illegal shortcut. Replan from the
            // current legal water point, or stop there if no route remains.
            guard let route = ObstacleNavigation.planVoid(
                from: unit.position,
                to: destination,
                for: unit,
                map: map,
                buildings: buildings,
                deposits: deposits
            ) else {
                stopAtVoidPoint(&unit)
                return
            }
            unit.destination = route.destination
            unit.movementPath = route.waypoints
            unit.movementPathTarget = route.destination
            return
        }

        unit.position = proposed
        unit.region = nil
        if case .idle = unit.activity { unit.activity = .moving }

        if travel >= distance - 0.0001 {
            unit.movementPath.removeFirst()
            if unit.movementPath.isEmpty {
                unit.destination = nil
                unit.movementPathTarget = nil
                if case .moving = unit.activity { unit.activity = .idle }
            }
        }
    }

    private static func stopAtVoidPoint(_ unit: inout Unit) {
        unit.destination = nil
        unit.movementPath = []
        unit.movementPathTarget = nil
        unit.region = nil
        if case .moving = unit.activity { unit.activity = .idle }
    }

    private static func advanceLegacyLand(
        _ unit: inout Unit,
        destination: WorldPoint,
        map: WorldMap,
        deltaTime: Double
    ) {
        let toTarget = destination - unit.position
        let distance = simd_length(toTarget)
        guard distance > arrivalRadius else {
            unit.position = destination
            unit.destination = nil
            unit.region = map.region(at: destination)
            if case .moving = unit.activity { unit.activity = .idle }
            return
        }

        let heading = toTarget / distance
        let travel = min(max(unit.kind.speed * Float(deltaTime), 0), distance)
        guard travel > 0 else { return }
        let proposed = unit.position + heading * travel
        let legal = map.clampToLand(
            proposed,
            from: unit.position,
            margin: unit.kind.footprintRadius
        )
        unit.position = legal
        unit.region = map.region(at: legal)
        if case .idle = unit.activity { unit.activity = .moving }
    }

    private static func stopAtLegalPoint(_ unit: inout Unit, map: WorldMap) {
        unit.destination = nil
        unit.movementPath = []
        unit.movementPathTarget = nil
        unit.region = map.region(at: unit.position)
        if case .moving = unit.activity { unit.activity = .idle }
    }

    /// Resolves a destination through terrain and dynamic obstacle truth.
    static func resolveOrder(
        _ requested: WorldPoint,
        for unit: Unit,
        map: WorldMap,
        buildings: [EntityID: Building] = [:],
        deposits: [EntityID: Deposit] = [:]
    ) -> ObstacleNavigation.Route? {
        if unit.kind.travelsVoid {
            return ObstacleNavigation.planVoid(
                from: unit.position,
                to: requested,
                for: unit,
                map: map,
                buildings: buildings,
                deposits: deposits
            )
        }
        guard !unit.isAboard else { return nil }

        if unit.kind != .citizen {
            let destination = map.clampToLand(
                requested,
                from: unit.position,
                margin: unit.kind.footprintRadius
            )
            return ObstacleNavigation.Route(
                destination: destination,
                waypoints: [destination],
                reachedRequestedDestination: destination == requested
            )
        }

        let margin = unit.kind.footprintRadius
        let terrainDestination = map.isTraversable(requested, margin: margin)
            ? requested
            : map.clampToTraversable(requested, from: unit.position, margin: margin)
        return ObstacleNavigation.plan(
            from: unit.position,
            to: terrainDestination,
            for: unit,
            map: map,
            buildings: buildings,
            deposits: deposits
        )
    }

    /// Clamps an ordered destination to somewhere the unit may legally stand.
    /// Called when an order is issued, so illegal taps resolve to the nearest
    /// legal point instead of being silently dropped.
    static func resolveDestination(
        _ requested: WorldPoint,
        for unit: Unit,
        map: WorldMap,
        buildings: [EntityID: Building] = [:],
        deposits: [EntityID: Deposit] = [:]
    ) -> WorldPoint? {
        if unit.kind.travelsVoid {
            return resolveVoidDestination(requested, for: unit, map: map)
        }
        guard !unit.isAboard else { return nil }
        return map.clampToLand(
            requested,
            from: unit.position,
            margin: unit.kind.footprintRadius
        )
    }

    private static func resolveVoidDestination(
        _ requested: WorldPoint,
        for unit: Unit,
        map: WorldMap
    ) -> WorldPoint? {
        guard map.isNavigableVoid(
                  unit.position,
                  margin: ObstacleNavigation.voidClearance
              ),
              map.isNavigableVoid(
                  requested,
                  margin: ObstacleNavigation.voidClearance
              )
        else {
            return nil
        }
        return requested
    }
}
