import Foundation
import simd

/// Resolves attacks on the fixed 20 Hz tick. No wall-clock timing and no
/// randomness — tie-breaks use ascending `EntityID`.
enum CombatSystem {

    /// Maximum chase distance from `guardAnchor` for Guard stance.
    static let guardLeashRadius: Float = 6

    struct TickResult: Sendable {
        var deadUnits: [EntityID] = []
        var deadBuildings: [EntityID] = []
    }

    // MARK: - Stepping

    static func step(
        units: inout [EntityID: Unit],
        buildings: inout [EntityID: Building],
        map: WorldMap
    ) -> TickResult {
        var result = TickResult()
        clearTickAttackers(units: &units)

        let armedUnitIDs = units.keys
            .filter { id in
                guard let unit = units[id] else { return false }
                return unit.kind.attackProfile != nil && !unit.isDead && !unit.isAboard
            }
            .sorted { $0.raw < $1.raw }

        let armedBuildingIDs = buildings.keys
            .filter { id in
                guard let building = buildings[id], building.isComplete else { return false }
                return building.kind.attackProfile != nil && !building.isDead
            }
            .sorted { $0.raw < $1.raw }

        var deadUnits: Set<EntityID> = []
        var deadBuildings: Set<EntityID> = []

        for id in armedUnitIDs {
            guard !deadUnits.contains(id) else { continue }
            guard var attacker = units[id], !attacker.isDead else { continue }
            guard let profile = attacker.kind.attackProfile else { continue }

            if attacker.attackCooldownRemaining > 0 {
                attacker.attackCooldownRemaining -= 1
                units[id] = attacker
                continue
            }

            resolveTarget(for: &attacker, units: units, buildings: buildings, deadUnits: deadUnits, deadBuildings: deadBuildings)

            guard let targetID = attacker.attackTarget else {
                units[id] = attacker
                continue
            }

            guard let targetPos = targetPosition(
                targetID,
                units: units,
                buildings: buildings,
                deadUnits: deadUnits,
                deadBuildings: deadBuildings
            ) else {
                clearAttackState(&attacker)
                units[id] = attacker
                continue
            }

            if !isHostile(attacker.faction, to: targetID, units: units, buildings: buildings) {
                clearAttackState(&attacker)
                units[id] = attacker
                continue
            }

            if !canEngage(attacker: attacker, targetID: targetID, units: units, buildings: buildings) {
                clearAttackState(&attacker)
                units[id] = attacker
                continue
            }

            let edgeDistance = footprintDistance(
                from: attacker.position,
                attackerRadius: attacker.kind.footprintRadius,
                to: targetPos.position,
                targetRadius: targetPos.radius
            )

            if edgeDistance > profile.range {
                if shouldChase(attacker: attacker, targetPosition: targetPos.position, map: map) {
                    issueChase(&attacker, toward: targetPos.position, map: map)
                }
                units[id] = attacker
                continue
            }

            let damage = damage(
                profile: profile,
                against: targetID,
                units: units,
                buildings: buildings
            )

            applyDamage(
                damage,
                to: targetID,
                from: id,
                units: &units,
                buildings: &buildings,
                deadUnits: &deadUnits,
                deadBuildings: &deadBuildings
            )

            attacker.attackCooldownRemaining = profile.cooldownTicks
            attacker.activity = .attacking(targetID: targetID)
            attacker.destination = nil
            units[id] = attacker
        }

        for id in armedBuildingIDs {
            guard !deadBuildings.contains(id) else { continue }
            guard var building = buildings[id], !building.isDead, building.isComplete else { continue }
            // Only an owned building shoots. A neutral objective has no side to
            // shoot for, so it never acquires a target.
            guard let owner = building.faction else { continue }
            guard let profile = building.kind.attackProfile else { continue }

            if building.attackCooldownRemaining > 0 {
                building.attackCooldownRemaining -= 1
                buildings[id] = building
                continue
            }

            if building.attackTarget == nil || !isValidTarget(
                building.attackTarget!,
                for: owner,
                sight: buildingSight(building),
                from: building.position,
                units: units,
                buildings: buildings,
                deadUnits: deadUnits,
                deadBuildings: deadBuildings
            ) {
                building.attackTarget = acquireNearestHostile(
                    for: owner,
                    sight: buildingSight(building),
                    from: building.position,
                    units: units,
                    buildings: buildings,
                    deadUnits: deadUnits,
                    deadBuildings: deadBuildings
                )
            }

            guard let targetID = building.attackTarget,
                  let targetPos = targetPosition(
                      targetID,
                      units: units,
                      buildings: buildings,
                      deadUnits: deadUnits,
                      deadBuildings: deadBuildings
                  )
            else {
                buildings[id] = building
                continue
            }

            let edgeDistance = footprintDistance(
                from: building.position,
                attackerRadius: building.kind.footprintRadius,
                to: targetPos.position,
                targetRadius: targetPos.radius
            )

            guard edgeDistance <= profile.range else {
                buildings[id] = building
                continue
            }

            let damage = damage(
                profile: profile,
                against: targetID,
                units: units,
                buildings: buildings
            )

            applyDamage(
                damage,
                to: targetID,
                from: id,
                units: &units,
                buildings: &buildings,
                deadUnits: &deadUnits,
                deadBuildings: &deadBuildings
            )

            building.attackCooldownRemaining = profile.cooldownTicks
            buildings[id] = building
        }

        for id in deadUnits.sorted(by: { $0.raw < $1.raw }) {
            result.deadUnits.append(id)
        }
        for id in deadBuildings.sorted(by: { $0.raw < $1.raw }) {
            result.deadBuildings.append(id)
        }
        return result
    }

    // MARK: - Orders

    static func orderAttack(
        _ attackerIDs: [EntityID],
        target: EntityID,
        units: inout [EntityID: Unit]
    ) {
        for id in attackerIDs.sorted(by: { $0.raw < $1.raw }) {
            guard var unit = units[id], unit.kind.canAttack, !unit.isAboard else { continue }
            unit.attackOrderTarget = target
            unit.attackTarget = target
            unit.activity = .attacking(targetID: target)
            unit.assignment = nil
            units[id] = unit
        }
    }

    // MARK: - Damage

    static func damage(
        profile: AttackProfile,
        against targetID: EntityID,
        units: [EntityID: Unit],
        buildings: [EntityID: Building]
    ) -> Int {
        if let unit = units[targetID] {
            return CombatDamage.effective(
                attacker: profile,
                targetMeleeArmor: unit.kind.meleeArmor,
                targetRangedArmor: unit.kind.rangedArmor,
                targetArmorClass: unit.kind.armorClass
            )
        }
        if let building = buildings[targetID] {
            return CombatDamage.effective(
                attacker: profile,
                targetMeleeArmor: building.kind.meleeArmor,
                targetRangedArmor: building.kind.rangedArmor,
                targetArmorClass: building.kind.armorClass
            )
        }
        return 1
    }

    // MARK: - Targeting

    private struct TargetPosition {
        var position: WorldPoint
        var radius: Float
    }

    private static func resolveTarget(
        for attacker: inout Unit,
        units: [EntityID: Unit],
        buildings: [EntityID: Building],
        deadUnits: Set<EntityID>,
        deadBuildings: Set<EntityID>
    ) {
        if let ordered = attacker.attackOrderTarget {
            if isValidTarget(
                ordered,
                for: attacker.faction,
                sight: attacker.kind.sightRange,
                from: attacker.position,
                units: units,
                buildings: buildings,
                deadUnits: deadUnits,
                deadBuildings: deadBuildings
            ) {
                attacker.attackTarget = ordered
                return
            }
            attacker.attackOrderTarget = nil
        }

        if let current = attacker.attackTarget,
           isValidTarget(
               current,
               for: attacker.faction,
               sight: attacker.kind.sightRange,
               from: attacker.position,
               units: units,
               buildings: buildings,
               deadUnits: deadUnits,
               deadBuildings: deadBuildings
           ) {
            return
        }

        attacker.attackTarget = nil

        if attacker.kind == .citizen { return }

        if let retaliate = [attacker.lastDamagedBy]
            .compactMap({ $0 })
            .filter({
                isValidTarget(
                    $0,
                    for: attacker.faction,
                    sight: attacker.kind.sightRange,
                    from: attacker.position,
                    units: units,
                    buildings: buildings,
                    deadUnits: deadUnits,
                    deadBuildings: deadBuildings
                )
            })
            .sorted(by: { $0.raw < $1.raw })
            .first
        {
            attacker.attackTarget = retaliate
            attacker.guardAnchor = attacker.guardAnchor ?? attacker.position
            return
        }

        if let retaliate = attacker.attackersThisTick
            .filter({
                isValidTarget(
                    $0,
                    for: attacker.faction,
                    sight: attacker.kind.sightRange,
                    from: attacker.position,
                    units: units,
                    buildings: buildings,
                    deadUnits: deadUnits,
                    deadBuildings: deadBuildings
                )
            })
            .sorted(by: { $0.raw < $1.raw })
            .first
        {
            attacker.attackTarget = retaliate
            attacker.guardAnchor = attacker.guardAnchor ?? attacker.position
            return
        }

        if let acquired = acquireNearestHostile(
            for: attacker.faction,
            sight: attacker.kind.sightRange,
            from: attacker.position,
            units: units,
            buildings: buildings,
            deadUnits: deadUnits,
            deadBuildings: deadBuildings
        ) {
            if attacker.guardAnchor == nil {
                attacker.guardAnchor = attacker.position
            }
            attacker.attackTarget = acquired
        }
    }

    private static func acquireNearestHostile(
        for faction: Faction,
        sight: Float,
        from origin: WorldPoint,
        units: [EntityID: Unit],
        buildings: [EntityID: Building],
        deadUnits: Set<EntityID>,
        deadBuildings: Set<EntityID>
    ) -> EntityID? {
        var best: (id: EntityID, distance: Float)?

        for (id, unit) in units where unit.faction != faction && !unit.isDead && !unit.isAboard {
            guard !deadUnits.contains(id) else { continue }
            let distance = footprintDistance(
                from: origin,
                attackerRadius: 0,
                to: unit.position,
                targetRadius: unit.kind.footprintRadius
            )
            guard distance <= sight else { continue }
            if let current = best {
                if distance < current.distance || (distance == current.distance && id.raw < current.id.raw) {
                    best = (id, distance)
                }
            } else {
                best = (id, distance)
            }
        }

        // `building.faction != faction` is not enough now that a building can be
        // neutral: `nil != .sunwoven` is true, and the Dominion Spire would be
        // acquired as a target by both sides. Ownership has to be asserted, not
        // assumed to exist.
        for (id, building) in buildings
        where isHostileOwner(building.faction, to: faction) && !building.isDead && building.isComplete {
            guard !deadBuildings.contains(id) else { continue }
            let distance = footprintDistance(
                from: origin,
                attackerRadius: 0,
                to: building.position,
                targetRadius: building.kind.footprintRadius
            )
            guard distance <= sight else { continue }
            if let current = best {
                if distance < current.distance || (distance == current.distance && id.raw < current.id.raw) {
                    best = (id, distance)
                }
            } else {
                best = (id, distance)
            }
        }

        return best?.id
    }

    private static func isValidTarget(
        _ targetID: EntityID,
        for faction: Faction,
        sight: Float,
        from origin: WorldPoint,
        units: [EntityID: Unit],
        buildings: [EntityID: Building],
        deadUnits: Set<EntityID>,
        deadBuildings: Set<EntityID>
    ) -> Bool {
        guard isHostile(faction, to: targetID, units: units, buildings: buildings) else { return false }
        guard let pos = targetPosition(
            targetID,
            units: units,
            buildings: buildings,
            deadUnits: deadUnits,
            deadBuildings: deadBuildings
        ) else { return false }
        let distance = footprintDistance(
            from: origin,
            attackerRadius: 0,
            to: pos.position,
            targetRadius: pos.radius
        )
        return distance <= sight
    }

    private static func isHostile(
        _ faction: Faction,
        to targetID: EntityID,
        units: [EntityID: Unit],
        buildings: [EntityID: Building]
    ) -> Bool {
        if let unit = units[targetID] {
            return unit.faction != faction && !unit.isDead
        }
        if let building = buildings[targetID] {
            return isHostileOwner(building.faction, to: faction)
                && !building.isDead
                && building.isComplete
        }
        return false
    }

    /// A neutral objective is nobody's enemy. Only a building owned by the other
    /// side is hostile.
    private static func isHostileOwner(_ owner: Faction?, to faction: Faction) -> Bool {
        guard let owner else { return false }
        return owner != faction
    }

    private static func canEngage(
        attacker: Unit,
        targetID: EntityID,
        units: [EntityID: Unit],
        buildings: [EntityID: Building]
    ) -> Bool {
        guard let profile = attacker.kind.attackProfile else { return false }
        guard let targetUnit = units[targetID] else { return true }

        if targetUnit.kind.armorClass == .hull {
            switch profile.damageType {
            case .melee: return false
            case .ranged, .siege: return true
            }
        }
        return true
    }

    private static func targetPosition(
        _ targetID: EntityID,
        units: [EntityID: Unit],
        buildings: [EntityID: Building],
        deadUnits: Set<EntityID>,
        deadBuildings: Set<EntityID>
    ) -> TargetPosition? {
        if let unit = units[targetID], !unit.isDead, !deadUnits.contains(targetID), !unit.isAboard {
            return TargetPosition(position: unit.position, radius: unit.kind.footprintRadius)
        }
        if let building = buildings[targetID], !building.isDead, !deadBuildings.contains(targetID), building.isComplete {
            return TargetPosition(position: building.position, radius: building.kind.footprintRadius)
        }
        return nil
    }

    private static func shouldChase(
        attacker: Unit,
        targetPosition: WorldPoint,
        map: WorldMap
    ) -> Bool {
        switch attacker.stance {
        case .hold:
            return false
        case .aggressive:
            return true
        case .guardStance:
            let anchor = attacker.guardAnchor ?? attacker.position
            let leashTarget = footprintDistance(
                from: anchor,
                attackerRadius: 0,
                to: targetPosition,
                targetRadius: 0
            )
            return leashTarget <= guardLeashRadius
        }
    }

    private static func issueChase(
        _ attacker: inout Unit,
        toward target: WorldPoint,
        map: WorldMap
    ) {
        guard let destination = MovementSystem.resolveDestination(target, for: attacker, map: map) else { return }
        attacker.destination = destination
        if let targetID = attacker.attackTarget {
            attacker.activity = .attacking(targetID: targetID)
        }
    }

    private static func clearAttackState(_ unit: inout Unit) {
        if unit.attackOrderTarget == nil {
            unit.attackTarget = nil
            unit.guardAnchor = nil
            if case .attacking = unit.activity {
                unit.activity = .idle
            }
        } else {
            unit.attackTarget = unit.attackOrderTarget
        }
        unit.destination = nil
    }

    private static func clearTickAttackers(units: inout [EntityID: Unit]) {
        for id in units.keys.sorted(by: { $0.raw < $1.raw }) {
            guard var unit = units[id] else { continue }
            unit.attackersThisTick = []
            units[id] = unit
        }
    }

    private static func buildingSight(_ building: Building) -> Float {
        switch building.kind {
        case .civilizationCore: 18
        case .expansionOutpost: 14
        default: 9
        }
    }

    // MARK: - Apply

    private static func applyDamage(
        _ amount: Int,
        to targetID: EntityID,
        from attackerID: EntityID,
        units: inout [EntityID: Unit],
        buildings: inout [EntityID: Building],
        deadUnits: inout Set<EntityID>,
        deadBuildings: inout Set<EntityID>
    ) {
        if var unit = units[targetID], !unit.isDead {
            unit.life -= Double(amount)
            unit.attackersThisTick.append(attackerID)
            unit.lastDamagedBy = attackerID
            if unit.life <= 0 {
                unit.life = 0
                unit.isDead = true
                deadUnits.insert(targetID)
            }
            units[targetID] = unit
            return
        }

        if var building = buildings[targetID], !building.isDead {
            // Indestructible by rule, per R1 §3 (B10.1): the Dominion Spire is an
            // objective, not a target. Nothing can acquire it — this guard makes
            // that true by construction rather than by inference from the
            // targeting code, so a future attack path cannot quietly break it.
            guard !building.kind.isNeutralObjective else { return }
            building.life -= Double(amount)
            if building.life <= 0 {
                building.life = 0
                building.isDead = true
                deadBuildings.insert(targetID)
            }
            buildings[targetID] = building
        }
    }

    // MARK: - Geometry

    static func footprintDistance(
        from origin: WorldPoint,
        attackerRadius: Float,
        to target: WorldPoint,
        targetRadius: Float
    ) -> Float {
        max(0, simd_distance(origin, target) - attackerRadius - targetRadius)
    }
}
