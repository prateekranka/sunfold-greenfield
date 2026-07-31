import Foundation
import simd

/// Advances unit positions. Pure and deterministic: same state plus same step
/// duration always yields the same result, with no dependence on frame timing.
///
/// Land units stay on land; light transports stay in navigable void (rivers,
/// lakes, open channel). Neither may cross into the other's domain.
enum MovementSystem {

    /// How close counts as arrived. Larger than a single step's travel so a unit
    /// cannot oscillate around its destination.
    static let arrivalRadius: Float = 0.35

    /// Advances every unit that has somewhere to be.
    static func step(
        units: inout [EntityID: Unit],
        map: WorldMap,
        deltaTime: Double
    ) {
        // Iterating a sorted key list keeps the update order stable across runs;
        // dictionary order is not guaranteed and would break replay.
        for id in units.keys.sorted(by: { $0.raw < $1.raw }) {
            guard var unit = units[id] else { continue }
            advance(&unit, map: map, deltaTime: deltaTime)
            units[id] = unit
        }
    }

    private static func advance(_ unit: inout Unit, map: WorldMap, deltaTime: Double) {
        // A unit riding a transport is carried, not walked.
        guard !unit.isAboard, let destination = unit.destination else { return }

        let toTarget = destination - unit.position
        let distance = simd_length(toTarget)

        guard distance > arrivalRadius else {
            unit.position = destination
            unit.region = map.region(at: destination)
            unit.destination = nil
            if case .moving = unit.activity { unit.activity = .idle }
            return
        }

        let heading = toTarget / distance
        let travel = min(unit.kind.speed * Float(deltaTime), distance)
        let proposed = unit.position + heading * travel

        unit.position = legalPosition(proposed, from: unit.position, for: unit, map: map)
        unit.region = map.region(at: unit.position)
        if case .idle = unit.activity { unit.activity = .moving }
    }

    /// Land units clamp to standable land anywhere; transports clamp to navigable void.
    private static func legalPosition(
        _ proposed: WorldPoint,
        from current: WorldPoint,
        for unit: Unit,
        map: WorldMap
    ) -> WorldPoint {
        if unit.kind.travelsVoid {
            return map.clampToVoid(proposed, from: current)
        }
        return map.clampToLand(
            proposed,
            from: current,
            margin: unit.kind.footprintRadius
        )
    }

    /// Clamps an ordered destination to somewhere the unit may legally stand.
    /// Called when an order is issued, so illegal taps resolve to the nearest
    /// legal point instead of being silently dropped.
    static func resolveDestination(
        _ requested: WorldPoint,
        for unit: Unit,
        map: WorldMap
    ) -> WorldPoint? {
        if unit.kind.travelsVoid {
            if map.isNavigableVoid(requested) { return requested }
            return map.clampToVoid(requested, from: unit.position)
        }
        guard !unit.isAboard else { return nil }

        let margin = unit.kind.footprintRadius
        if map.isStandable(requested, margin: margin) { return requested }

        // Resolve a tap in the void — or in a river — to the last legal point on
        // the way to it, so the order reads as "walk as far as you can toward
        // that" rather than being dropped or answered somewhere unrelated.
        return map.clampToLand(requested, from: unit.position, margin: margin)
    }
}
