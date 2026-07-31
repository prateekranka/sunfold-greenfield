import SwiftUI

/// The command card: what the current selection can be told to do.
///
/// Anchored bottom-trailing, opposite the map, because those are the two corners
/// a player's thumbs reach on a landscape iPad and these are the two surfaces
/// they touch most.
///
/// The grid is a fixed 3×3 whatever is selected. A card that reflows as the
/// selection changes forces the player to re-find every button, and muscle
/// memory for a command's *position* is most of what makes an RTS fast — so a
/// command that does not apply is dimmed in place rather than removed.
struct CommandGrid: View {
    let simulation: SkirmishSimulation
    let selection: SelectionModel
    var controller: WorldController?

    private let viewer: Faction = .sunwoven

    private var selectedUnits: [EntityID] { Array(selection.selectedUnits) }
    private var hasUnits: Bool { !selectedUnits.isEmpty }
    private var hasCitizens: Bool {
        selectedUnits.contains { simulation.unit($0)?.kind == .citizen }
    }
    private var hasSelection: Bool {
        hasUnits
            || selection.selectedBuilding != nil
            || selection.selectedDeposit != nil
    }

    private var selectedProductionBuilding: Building? {
        guard let id = selection.selectedBuilding,
              let building = simulation.building(id),
              building.faction == viewer,
              building.isComplete,
              !building.kind.trains.isEmpty
        else { return nil }
        return building
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 7) {
            Text(gridTitle).hudTitle()
            VStack(spacing: 5) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 5) {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            tile(for: cell)
                        }
                    }
                }
            }
        }
        .hudPanel(corners: [.topLeading, .topTrailing, .bottomLeading])
    }

    private var gridTitle: String {
        if selectedProductionBuilding != nil { return "Train" }
        if hasCitizens { return "Orders" }
        if hasSelection { return "Inspect" }
        return "No selection"
    }

    // MARK: - Layout

    private struct Cell {
        let glyph: HUDGlyph.Kind
        let name: String
        var isPrimary = false
        var badge: String?
        var isEnabled = false
        var action: (() -> Void)?
    }

    private var rows: [[Cell]] {
        if let building = selectedProductionBuilding {
            return productionRows(for: building)
        }
        if hasCitizens {
            return citizenRows()
        }
        return inspectRows()
    }

    // MARK: Production building

    private func productionRows(for building: Building) -> [[Cell]] {
        let trains = building.kind.trains
        var trainCells: [Cell] = trains.map { trainCell($0, buildingID: building.id) }
        while trainCells.count < 3 {
            trainCells.append(unavailableCell(glyph: .pin, label: "No training slot"))
        }

        let queue = simulation.productionQueue(for: building.id)
        let canCancel = !queue.isEmpty

        let commands: [Cell] = [
            unavailableCell(glyph: .rally, label: "Set rally point. Unavailable."),
            unavailableCell(glyph: .stop, label: "Stop. Unavailable for buildings."),
            Cell(
                glyph: .alert,
                name: canCancel
                    ? "Cancel front of queue. Refunds cost."
                    : "Cancel front of queue. Queue is empty.",
                isEnabled: canCancel,
                action: canCancel ? { self.selection.cancelProduction(at: building.id, in: self.simulation) } : nil
            )
        ]

        let spare: [Cell] = [
            unavailableCell(glyph: .move, label: "Not available."),
            unavailableCell(glyph: .guardStance, label: "Not available."),
            unavailableCell(glyph: .gather, label: "Not available.")
        ]

        return [Array(trainCells.prefix(3)), commands, spare]
    }

    private func trainCell(_ kind: UnitKind, buildingID: EntityID) -> Cell {
        let cost = simulation.tuning.cost(for: kind)
        let stock = simulation.stock(for: viewer)
        let pop = simulation.population(for: viewer)
        let queue = simulation.productionQueue(for: buildingID)

        let affordReason: String? = stock.covers(cost)
            ? nil
            : "Needs \(missingCostSummary(needed: cost, have: stock))."
        let popReason: String? = (pop.used + kind.populationCost <= pop.cap)
            ? nil
            : "Population \(pop.used + kind.populationCost)/\(pop.cap)."
        let queueReason: String? = queue.count < simulation.tuning.maxQueueLength
            ? nil
            : "Queue full."

        let blocker = affordReason ?? popReason ?? queueReason
        let canTrain = blocker == nil

        return Cell(
            glyph: kind.glyph,
            name: blocker.map { "\(kind.displayName). \($0)" }
                ?? "Train \(kind.displayName). Costs \(cost.costSummary).",
            isPrimary: canTrain,
            badge: primaryBadge(for: cost),
            isEnabled: canTrain,
            action: canTrain ? { _ = self.selection.enqueueUnit(kind, at: buildingID, in: self.simulation) } : nil
        )
    }

    // MARK: Citizen build menu

    private func citizenRows() -> [[Cell]] {
        let stopAction: (() -> Void)? = hasUnits ? { self.stop() } : nil
        let orders: [Cell] = [
            unavailableCell(glyph: .move, label: "Move. Unavailable."),
            Cell(
                glyph: .stop,
                name: hasUnits ? "Stop selected units." : "Stop. No units selected.",
                isEnabled: hasUnits,
                action: stopAction
            ),
            unavailableCell(glyph: .guardStance, label: "Guard. Unavailable.")
        ]
        let structures: [Cell] = [
            buildCell(.farm, glyph: .farm),
            buildCell(.matterExtractor, glyph: .extractor),
            buildCell(.dwelling, glyph: .dwelling),
            buildCell(.formationYard, glyph: .formationYard),
            buildCell(.expansionOutpost, glyph: .outpost),
            buildCell(.dawnLoom, glyph: .loom)
        ]
        return [orders, Array(structures.prefix(3)), Array(structures.dropFirst(3).prefix(3))]
    }

    // MARK: Inspect / non-production selection

    private func inspectRows() -> [[Cell]] {
        let stopAction: (() -> Void)? = hasUnits ? { self.stop() } : nil
        let orders: [Cell] = [
            unavailableCell(glyph: .move, label: "Move. Unavailable."),
            Cell(
                glyph: .stop,
                name: hasUnits ? "Stop selected units." : "Stop. No units selected.",
                isEnabled: hasUnits,
                action: stopAction
            ),
            unavailableCell(glyph: .guardStance, label: "Guard. Unavailable.")
        ]
        let stances: [Cell] = [
            unavailableCell(glyph: .gather, label: "Gather. Unavailable."),
            unavailableCell(glyph: .rally, label: "Set rally point. Unavailable."),
            unavailableCell(glyph: .outpost, label: "Build Outpost. Select a citizen.")
        ]
        let structures: [Cell] = [
            unavailableCell(glyph: .farm, label: "Build Farm. Select a citizen."),
            unavailableCell(glyph: .extractor, label: "Build Matter Extractor. Select a citizen."),
            unavailableCell(glyph: .dwelling, label: "Build Dwelling. Select a citizen.")
        ]
        return [orders, stances, structures]
    }

    private func buildCell(_ kind: BuildingKind, glyph: HUDGlyph.Kind) -> Cell {
        let cost = simulation.tuning.cost(for: kind)
        let stock = simulation.stock(for: viewer)
        let canAfford = stock.covers(cost)
        let blocker = canAfford
            ? nil
            : "Needs \(missingCostSummary(needed: cost, have: stock))."
        let canBuild = blocker == nil

        return Cell(
            glyph: glyph,
            name: blocker.map { "\(kind.displayName). \($0)" }
                ?? "\(kind.displayName). \(kind.purpose). Costs \(cost.costSummary).",
            isPrimary: canBuild,
            badge: primaryBadge(for: cost),
            isEnabled: canBuild,
            action: canBuild ? { self.controller?.beginBuildGhost(kind) } : nil
        )
    }

    private func unavailableCell(glyph: HUDGlyph.Kind, label: String) -> Cell {
        Cell(glyph: glyph, name: label, isEnabled: false, action: nil)
    }

    private func primaryBadge(for cost: ResourcePool) -> String? {
        if cost.provisions > 0 { return "\(Int(cost.provisions.rounded()))" }
        if cost.matter > 0 { return "\(Int(cost.matter.rounded()))" }
        if cost.lumen > 0 { return "\(Int(cost.lumen.rounded()))" }
        return nil
    }

    private func missingCostSummary(needed: ResourcePool, have: ResourcePool) -> String {
        ResourceKind.allCases.compactMap { kind in
            let shortfall = needed[kind] - have[kind]
            guard shortfall > 0.01 else { return nil }
            return "\(ResourcePool.displayAmount(shortfall)) \(kind.displayName)"
        }.joined(separator: " · ")
    }

    private func tile(for cell: Cell) -> some View {
        HUDIconTile(
            glyph: cell.glyph,
            size: HUDMetrics.commandTile,
            isEnabled: cell.isEnabled,
            isPrimary: cell.isPrimary,
            badge: cell.badge,
            name: cell.name,
            action: cell.action
        )
    }

    // MARK: - Orders

    private func stop() {
        for id in selectedUnits {
            guard let unit = simulation.unit(id) else { continue }
            simulation.order(id, moveTo: unit.position)
        }
    }
}
