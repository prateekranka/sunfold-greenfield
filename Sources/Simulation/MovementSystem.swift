import Foundation
import simd

/// Advances unit positions. Pure and deterministic: same state plus same step
/// duration always yields the same result, with no dependence on frame timing.
///
/// Land legality lives here rather than in the renderer, so a unit can never be
/// shown standing somewhere the rules consider void.
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
            unit.destination = nil
            if case .moving = unit.activity { unit.activity = .idle }
            return
        }

        let heading = toTarget / distance
        let travel = min(unit.kind.speed * Float(deltaTime), distance)
        let proposed = unit.position + heading * travel

        unit.position = legalPosition(proposed, for: unit, map: map)
        if case .idle = unit.activity { unit.activity = .moving }
    }

    /// Keeps land units on land. A transport is free to sit in the void.
    private static func legalPosition(
        _ proposed: WorldPoint,
        for unit: Unit,
        map: WorldMap
    ) -> WorldPoint {
        guard !unit.kind.travelsVoid, let region = unit.region else { return proposed }
        guard !map.contains(proposed, in: region) else { return proposed }

        // Project back onto the rim rather than refusing to move, so a unit
        // ordered past the edge slides along it instead of freezing.
        let fragment = map.fragment(region)
        let outward = proposed - fragment.center
        let length = simd_length(outward)
        guard length > 0.0001 else { return proposed }
        let margin = unit.kind.footprintRadius
        return fragment.center + (outward / length) * max(fragment.radius - margin, 0)
    }

    /// Clamps an ordered destination to somewhere the unit may legally stand.
    /// Called when an order is issued, so illegal taps resolve to the nearest
    /// legal point instead of being silently dropped.
    static func resolveDestination(
        _ requested: WorldPoint,
        for unit: Unit,
        map: WorldMap
    ) -> WorldPoint? {
        if unit.kind.travelsVoid { return requested }
        guard let region = unit.region else { return nil }

        if map.contains(requested, in: region) { return requested }

        let fragment = map.fragment(region)
        let outward = requested - fragment.center
        let length = simd_length(outward)
        guard length > 0.0001 else { return fragment.center }
        let margin = unit.kind.footprintRadius
        return fragment.center + (outward / length) * max(fragment.radius - margin, 0)
    }
}
