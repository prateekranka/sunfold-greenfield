import Foundation
import Observation
import simd

/// What the player currently has selected, and what a tap on the world should do.
///
/// Selection is a player-side view concern, not game truth — the Gravemark AI has
/// no selection — so it lives here rather than in the simulation. Orders it issues
/// go through the simulation, which remains the only thing that decides legality.
@MainActor
@Observable
final class SelectionModel {

    /// Durable IDs, never indices, so selection survives anything spawning or dying.
    private(set) var selectedUnits: Set<EntityID> = []
    private(set) var selectedBuilding: EntityID?
    /// A node the player is inspecting. Tapping a deposit with citizens selected
    /// is an order; tapping one with nothing selected is a question, and this is
    /// where the answer comes from.
    private(set) var selectedDeposit: EntityID?

    /// The most recent confirmed move order, for destination feedback.
    private(set) var lastOrderMarker: OrderMarker?

    struct OrderMarker: Equatable {
        let position: WorldPoint
        /// Simulation time the order was issued, so the pulse can fade out.
        let issuedAt: Double
    }

    var hasSelection: Bool {
        !selectedUnits.isEmpty || selectedBuilding != nil || selectedDeposit != nil
    }

    // MARK: - Selection

    func selectUnit(_ id: EntityID) {
        selectedUnits = [id]
        selectedBuilding = nil
        selectedDeposit = nil
    }

    func selectUnits(_ ids: some Sequence<EntityID>) {
        selectedUnits = Set(ids)
        if !selectedUnits.isEmpty {
            selectedBuilding = nil
            selectedDeposit = nil
        }
    }

    func selectBuilding(_ id: EntityID) {
        selectedBuilding = id
        selectedUnits = []
        selectedDeposit = nil
    }

    func selectDeposit(_ id: EntityID) {
        selectedDeposit = id
        selectedUnits = []
        selectedBuilding = nil
    }

    func clear() {
        selectedUnits = []
        selectedBuilding = nil
        selectedDeposit = nil
    }

    /// Drops anything that no longer exists. Called after the simulation steps so
    /// a destroyed unit cannot linger in the selection panel.
    func prune(against simulation: SkirmishSimulation) {
        selectedUnits = selectedUnits.filter { simulation.unit($0) != nil }
        if let building = selectedBuilding, simulation.building(building) == nil {
            selectedBuilding = nil
        }
        if let deposit = selectedDeposit, simulation.deposit(deposit) == nil {
            selectedDeposit = nil
        }
    }

    // MARK: - Orders

    /// Issues a move order to the current selection and records the marker that
    /// gives the player confirmation something was heard.
    func orderMove(to point: WorldPoint, in simulation: SkirmishSimulation) {
        let movable = selectedUnits
            .compactMap { simulation.unit($0) }
            .filter { $0.faction == simulation.playerFaction }
            .map(\.id)
        guard !movable.isEmpty else { return }

        let destinations = simulation.orderMove(movable, to: point)
        if let destination = destinations.first {
            // Accepted orders use the simulation's resolved endpoint.
            lastOrderMarker = OrderMarker(
                position: destination,
                issuedAt: simulation.elapsed
            )
        } else {
            // A rejected order still leaves a short-lived marker at the point
            // the player tapped, so denial is visible as well as audible.
            lastOrderMarker = OrderMarker(
                position: point,
                issuedAt: simulation.elapsed
            )
        }
    }

    /// Puts the selection to work on a deposit.
    func orderGather(from depositID: EntityID, in simulation: SkirmishSimulation) {
        guard let deposit = simulation.deposit(depositID) else { return }
        let mine = selectedUnits
            .compactMap { simulation.unit($0) }
            .filter { $0.faction == simulation.playerFaction }
            .map(\.id)
        guard !mine.isEmpty else { return }

        simulation.orderGather(mine, from: depositID)
        lastOrderMarker = OrderMarker(position: deposit.position, issuedAt: simulation.elapsed)
    }

    /// Incomplete friendly foundation tap: assign only when the selection has
    /// citizens eligible for construction; otherwise inspect the foundation.
    /// Never silent-no-op when the selection cannot build.
    func respondToIncompleteFoundation(_ buildingID: EntityID, in simulation: SkirmishSimulation) {
        let hasEligibleBuilder = selectedUnits.contains {
            simulation.unit($0)?.canBeAssignedToConstruction == true
        }
        if hasEligibleBuilder {
            orderConstruct(on: buildingID, in: simulation)
        } else {
            selectBuilding(buildingID)
        }
    }

    /// Sends eligible selected citizens to finish an incomplete foundation.
    /// Order-marker feedback is only shown when at least one builder was assigned.
    func orderConstruct(on buildingID: EntityID, in simulation: SkirmishSimulation) {
        guard let building = simulation.building(buildingID), !building.isComplete else { return }
        let mine = selectedUnits
            .compactMap { simulation.unit($0) }
            .filter { $0.faction == simulation.playerFaction }
            .map(\.id)
        guard !mine.isEmpty else { return }

        let assigned = simulation.orderConstruct(mine, on: buildingID)
        if assigned > 0 {
            lastOrderMarker = OrderMarker(position: building.position, issuedAt: simulation.elapsed)
        }
    }

    /// Sends selected citizens to board a light transport.
    func orderBoard(onto transportID: EntityID, in simulation: SkirmishSimulation) {
        guard let transport = simulation.unit(transportID),
              transport.kind == .lightTransport,
              transport.faction == simulation.playerFaction
        else { return }
        let boarders = selectedUnits
            .compactMap { simulation.unit($0) }
            .filter { $0.faction == simulation.playerFaction && $0.kind.canGather }
            .map(\.id)
        guard !boarders.isEmpty else { return }

        simulation.orderBoard(boarders, onto: transportID)
        lastOrderMarker = OrderMarker(position: transport.position, issuedAt: simulation.elapsed)
    }

    func expireOrderMarker(after lifetime: Double, now: Double) {
        guard let marker = lastOrderMarker else { return }
        if now - marker.issuedAt > lifetime { lastOrderMarker = nil }
    }

    // MARK: - Production

    @discardableResult
    func enqueueUnit(
        _ kind: UnitKind,
        at buildingID: EntityID,
        in simulation: SkirmishSimulation
    ) -> Result<Void, ProductionEnqueueFailure> {
        guard let building = simulation.building(buildingID),
              building.faction == simulation.playerFaction
        else { return .failure(.notTrainable) }
        return simulation.enqueueUnit(kind, at: buildingID)
    }

    @discardableResult
    func cancelProduction(at buildingID: EntityID, in simulation: SkirmishSimulation) -> Bool {
        guard let building = simulation.building(buildingID),
              building.faction == simulation.playerFaction
        else { return false }
        return simulation.cancelProduction(at: buildingID)
    }

    /// Issues an attack order when friendly units that can fight are selected.
    func orderAttack(target: EntityID, in simulation: SkirmishSimulation) {
        let attackers = selectedUnits
            .compactMap { simulation.unit($0) }
            .filter {
                $0.faction == simulation.playerFaction && $0.kind.canAttack && !$0.isAboard
            }
            .map(\.id)
        guard !attackers.isEmpty else { return }

        simulation.orderAttack(attackers, target: target)
        if let point = attackTargetPosition(target, in: simulation) {
            lastOrderMarker = OrderMarker(position: point, issuedAt: simulation.elapsed)
        }
    }

    private func attackTargetPosition(_ target: EntityID, in simulation: SkirmishSimulation) -> WorldPoint? {
        simulation.unit(target)?.position ?? simulation.building(target)?.position
    }
}

/// Resolves a world-space tap to whatever the player most plausibly meant.
///
/// Picking is done in world space against footprint radii rather than by
/// RealityKit entity hit-testing, so selection agrees exactly with the simulation's
/// idea of where things are — the renderer can never disagree with the rules.
@MainActor
enum WorldPicker {

    /// Extra forgiveness around a footprint, in metres, so small units stay
    /// tappable at gameplay zoom without demanding pixel accuracy.
    static let touchSlop: Float = 1.6

    enum Hit: Equatable {
        case unit(EntityID)
        case building(EntityID)
        case deposit(EntityID)
        case ground(WorldPoint)
    }

    static func pick(at point: WorldPoint, in simulation: SkirmishSimulation) -> Hit {
        // Units first: they are smaller, sit on top of everything, and are what a
        // player is most often reaching for.
        var best: (id: EntityID, distance: Float)?
        for unit in simulation.units.values {
            let reach = unit.kind.footprintRadius + touchSlop
            let distance = simd_distance(unit.position, point)
            if distance <= reach, distance < (best?.distance ?? .greatestFiniteMagnitude) {
                best = (unit.id, distance)
            }
        }
        if let best { return .unit(best.id) }

        for building in simulation.buildings.values {
            if simd_distance(building.position, point) <= building.kind.footprintRadius + touchSlop {
                return .building(building.id)
            }
        }

        for deposit in simulation.deposits.values {
            if simd_distance(deposit.position, point) <= Deposit.workRadius + touchSlop {
                return .deposit(deposit.id)
            }
        }

        return .ground(point)
    }
}
