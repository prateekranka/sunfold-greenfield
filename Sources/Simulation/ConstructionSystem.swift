import Foundation
import simd

/// Advances incomplete buildings when citizens are on site.
///
/// Progress is linear in builder count (#5): two citizens finish in half the
/// time of one. Pure and deterministic — same state + step → same result.
enum ConstructionSystem {

    /// How close a citizen must stand to contribute, measured from the building
    /// centre. Must reach past the approach kerb (`footprintRadius + 1.4`), or
    /// builders arrive, clear their destination, and never advance progress.
    static func workRadius(for kind: BuildingKind) -> Float {
        kind.footprintRadius + 2.0
    }

    static func step(
        units: inout [EntityID: Unit],
        buildings: inout [EntityID: Building],
        map: WorldMap,
        tuning: SkirmishTuning,
        deltaTime: Double
    ) {
        let incomplete = buildings.keys.sorted(by: { $0.raw < $1.raw }).filter {
            !(buildings[$0]?.isComplete ?? true)
        }
        guard !incomplete.isEmpty else { return }

        for buildingID in incomplete {
            guard var building = buildings[buildingID], !building.isComplete else { continue }
            let onSiteRadius = workRadius(for: building.kind)

            var buildersOnSite = 0
            for unitID in units.keys.sorted(by: { $0.raw < $1.raw }) {
                guard var unit = units[unitID] else { continue }
                guard case .constructing(buildingID) = unit.activity else { continue }
                guard unit.faction == building.faction, unit.kind.canGather else { continue }

                let distance = simd_distance(unit.position, building.position)
                if distance <= onSiteRadius {
                    unit.destination = nil
                    buildersOnSite += 1
                } else if unit.destination == nil {
                    // Walk to the kerb, not the centre, so they do not pile into
                    // the foundation disc.
                    let offset = approachOffset(from: unit.position, to: building)
                    if let dest = MovementSystem.resolveDestination(
                        building.position + offset, for: unit, map: map
                    ) {
                        unit.destination = dest
                    }
                }
                units[unitID] = unit
            }

            guard buildersOnSite > 0 else {
                buildings[buildingID] = building
                continue
            }

            let duration = max(tuning.buildTime(for: building.kind), 0.01)
            building.constructionProgress = min(
                1,
                building.constructionProgress + (Double(buildersOnSite) * deltaTime) / duration
            )
            buildings[buildingID] = building

            if building.isComplete {
                releaseBuilders(of: buildingID, units: &units)
            }
        }
    }

    private static func approachOffset(from unit: WorldPoint, to building: Building) -> WorldPoint {
        let delta = unit - building.position
        let length = simd_length(delta)
        // Stay inside workRadius so arrival actually counts as on-site.
        let radius = min(building.kind.footprintRadius + 1.4, workRadius(for: building.kind) * 0.85)
        if length < 0.01 {
            return WorldPoint(radius, 0)
        }
        return (delta / length) * radius
    }

    private static func releaseBuilders(of buildingID: EntityID, units: inout [EntityID: Unit]) {
        for id in units.keys.sorted(by: { $0.raw < $1.raw }) {
            guard var unit = units[id] else { continue }
            guard case .constructing(buildingID) = unit.activity else { continue }
            unit.activity = .idle
            unit.destination = nil
            units[id] = unit
        }
    }
}
