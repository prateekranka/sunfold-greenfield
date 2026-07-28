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

        unit.position = legalPosition(proposed, from: unit.position, for: unit, map: map)
        if case .idle = unit.activity { unit.activity = .moving }
    }

    /// Keeps land units on land. A transport is free to sit in the void.
    ///
    /// The clamp walks back along the move rather than projecting toward the plate
    /// centre. Projection was correct while a plate was a disc and the only void
    /// was outside it; with rivers on the map the point "radius − margin from the
    /// centre" can be in the channel, or on its far bank — so a unit ordered into
    /// the water would have been teleported across it.
    private static func legalPosition(
        _ proposed: WorldPoint,
        from current: WorldPoint,
        for unit: Unit,
        map: WorldMap
    ) -> WorldPoint {
        guard !unit.kind.travelsVoid, let region = unit.region else { return proposed }
        return map.clampToLand(
            proposed,
            from: current,
            in: region,
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
        if unit.kind.travelsVoid { return requested }
        guard let region = unit.region else { return nil }

        let margin = unit.kind.footprintRadius
        if map.isStandable(requested, in: region, margin: margin) { return requested }

        // Resolve a tap in the void — or in a river — to the last legal point on
        // the way to it, so the order reads as "walk as far as you can toward
        // that" rather than being dropped or answered somewhere unrelated.
        return map.clampToLand(requested, from: unit.position, in: region, margin: margin)
    }
}
