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
    private let restingReason = "Select a dimmed tile for details."
    private let unavailableContentReason = "Not available in this build."
    private let emptyProductionReason = "No additional unit is trained here."

    @State private var citizenPage: CitizenPage = .economy
    @State private var visibleReason = "Select a dimmed tile for details."

    private var selectedUnits: [EntityID] {
        selection.selectedUnits.sorted { $0.raw < $1.raw }
    }

    private var hasUnits: Bool { !selectedUnits.isEmpty }

    private var hasCitizens: Bool {
        selectedUnits.contains { simulation.unit($0)?.kind == .citizen }
    }

    private var hasSelection: Bool {
        hasUnits
            || selection.selectedBuilding != nil
            || selection.selectedDeposit != nil
    }

    private var selectionKey: SelectionKey {
        SelectionKey(
            units: selectedUnits,
            building: selection.selectedBuilding,
            deposit: selection.selectedDeposit
        )
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
        let currentRows: [[Cell]] = rows
        let currentReason: String = reasonLine(for: currentRows)

        return VStack(alignment: .trailing, spacing: 7) {
            Text(gridTitle).hudTitle()
            Text(currentReason)
                .hudLabel()
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .frame(width: gridWidth, height: 26, alignment: .trailing)

            VStack(spacing: 5) {
                ForEach(Array(currentRows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 5) {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            tile(for: cell)
                        }
                    }
                }
            }
        }
        .hudPanel(corners: [.topLeading, .topTrailing, .bottomLeading])
        .onChange(of: selectionKey) { _, _ in
            resetForNewSelection()
        }
        .onChange(of: citizenPage) { _, _ in
            visibleReason = restingReason
        }
    }

    private var gridWidth: CGFloat {
        HUDMetrics.commandTile * 3 + 10
    }

    private var gridTitle: String {
        if selectedProductionBuilding != nil { return "Train" }
        if hasCitizens { return "Build · \(citizenPage.title)" }
        if hasSelection { return "Inspect" }
        return "No selection"
    }

    // MARK: - Layout

    private enum CitizenPage: Equatable {
        case economy
        case military

        var title: String {
            switch self {
            case .economy: "Economy"
            case .military: "Military"
            }
        }
    }

    private struct SelectionKey: Equatable {
        let units: [EntityID]
        let building: EntityID?
        let deposit: EntityID?
    }

    private struct Cell {
        let glyph: HUDGlyph.Kind
        let name: String
        var reason: String? = nil
        var surfacesReasonAutomatically: Bool = false
        var isPrimary = false
        var badge: String?
        var isEnabled = false
        var action: (() -> Void)?
    }

    private var rows: [[Cell]] {
        let result: [[Cell]]
        if let building = selectedProductionBuilding {
            result = productionRows(for: building)
        } else if hasCitizens {
            result = citizenRows()
        } else {
            result = inspectRows()
        }
        return result
    }

    private func reasonLine(for rows: [[Cell]]) -> String {
        guard visibleReason == restingReason else { return visibleReason }

        let cells: [Cell] = rows.flatMap { $0 }
        if let automaticCell: Cell = cells.first(where: { $0.surfacesReasonAutomatically }),
           let reason: String = automaticCell.reason {
            return reason
        }
        return restingReason
    }

    private func resetForNewSelection() {
        citizenPage = .economy
        visibleReason = restingReason
    }

    private func showReason(_ reason: String) {
        visibleReason = reason
    }

    private func clearReason() {
        visibleReason = restingReason
    }

    // MARK: Production building

    private func productionRows(for building: Building) -> [[Cell]] {
        let trains: [UnitKind] = building.kind.trains
        var trainCells: [Cell] = trains.map { trainCell($0, buildingID: building.id) }
        while trainCells.count < 3 {
            let emptyCell: Cell = unavailableCell(glyph: .pin, label: emptyProductionReason)
            trainCells.append(emptyCell)
        }

        let queue: ProductionQueue = simulation.productionQueue(for: building.id)
        let canCancel: Bool = !queue.isEmpty

        let cancelCell: Cell
        if canCancel {
            cancelCell = Cell(
                glyph: .alert,
                name: "Cancel front of queue. Refunds cost.",
                isEnabled: true,
                action: {
                    if self.selection.cancelProduction(at: building.id, in: self.simulation) {
                        self.clearReason()
                    }
                }
            )
        } else {
            cancelCell = unavailableCell(
                glyph: .alert,
                label: "Cancel front of queue. Queue is empty."
            )
        }

        let commands: [Cell] = [
            unavailableCell(glyph: .rally, label: "Set rally point. Unavailable."),
            unavailableCell(glyph: .stop, label: "Stop. Unavailable for buildings."),
            cancelCell,
        ]

        let spare: [Cell] = [
            unavailableCell(glyph: .move, label: "Not available."),
            unavailableCell(glyph: .guardStance, label: "Not available."),
            unavailableCell(glyph: .gather, label: "Not available."),
        ]

        let trainRow: [Cell] = Array(trainCells.prefix(3))
        return [trainRow, commands, spare]
    }

    private func trainCell(_ kind: UnitKind, buildingID: EntityID) -> Cell {
        let cost: ResourcePool = simulation.tuning.cost(for: kind)
        let stock: ResourcePool = simulation.stock(for: viewer)
        let population: (used: Int, cap: Int) = simulation.population(for: viewer)
        let queue: ProductionQueue = simulation.productionQueue(for: buildingID)

        let holdReason: String? = queue.front?.kind == kind
            ? productionHoldReasonText(queue.heldReason)
            : nil
        let affordReason: String? = stock.covers(cost)
            ? nil
            : "Needs \(missingCostSummary(needed: cost, have: stock))."
        let populationReason: String? = population.used + kind.populationCost <= population.cap
            ? nil
            : "Population \(population.used + kind.populationCost)/\(population.cap)."
        let queueReason: String? = queue.count < simulation.tuning.maxQueueLength
            ? nil
            : "Queue full."

        let blocker: String? = holdReason ?? affordReason ?? populationReason ?? queueReason
        let canTrain: Bool = blocker == nil
        let label: String = blocker ?? "Train \(kind.displayName). Costs \(cost.costSummary)."

        let action: (() -> Void)?
        if let blocker {
            action = { self.showReason(blocker) }
        } else {
            action = {
                let result: Result<Void, ProductionEnqueueFailure> = self.selection.enqueueUnit(
                    kind,
                    at: buildingID,
                    in: self.simulation
                )
                switch result {
                case .success:
                    self.clearReason()
                case .failure(let failure):
                    self.showReason(self.productionFailureText(failure, kind: kind))
                }
            }
        }

        return Cell(
            glyph: kind.glyph,
            name: label,
            reason: blocker,
            surfacesReasonAutomatically: blocker != nil,
            isPrimary: canTrain,
            badge: primaryBadge(for: cost),
            isEnabled: canTrain,
            action: action
        )
    }

    private func productionHoldReasonText(_ reason: ProductionHoldReason?) -> String? {
        guard let reason else { return nil }
        switch reason {
        case .populationCap: return "Waiting for population."
        case .noSpawnPosition: return "Waiting for space to spawn."
        }
    }

    private func productionFailureText(
        _ failure: ProductionEnqueueFailure,
        kind: UnitKind
    ) -> String {
        switch failure {
        case .notTrainable: return "Cannot train \(kind.displayName)."
        case .buildingIncomplete: return "Building is incomplete."
        case .queueFull: return "Queue full."
        case .cannotAfford(let missing): return "Needs \(missing)."
        case .populationCap(let used, let cap): return "Population \(used)/\(cap)."
        }
    }

    // MARK: Citizen build menu

    private func citizenRows() -> [[Cell]] {
        let stop: Cell = stopCell()
        let guardCell: Cell = unavailableCell(glyph: .guardStance, label: "Guard. Unavailable.")
        let toggle: Cell = pageToggleCell()

        switch citizenPage {
        case .economy:
            let top: [Cell] = [
                buildCell(.farm),
                buildCell(.matterExtractor),
                unavailableCell(glyph: .pin, label: unavailableContentReason),
            ]
            let middle: [Cell] = [
                buildCell(.dwelling),
                unavailableCell(glyph: .pin, label: unavailableContentReason),
                buildCell(.expansionOutpost),
            ]
            let bottom: [Cell] = [stop, guardCell, toggle]
            return [top, middle, bottom]

        case .military:
            let top: [Cell] = [
                buildCell(.formationYard),
                buildCell(.lumenSpire),
                unavailableCell(glyph: .pin, label: unavailableContentReason),
            ]
            let middle: [Cell] = [
                unavailableCell(glyph: .pin, label: unavailableContentReason),
                unavailableCell(glyph: .pin, label: unavailableContentReason),
                unavailableCell(glyph: .pin, label: unavailableContentReason),
            ]
            let bottom: [Cell] = [buildCell(.dawnLoom), guardCell, toggle]
            return [top, middle, bottom]
        }
    }

    private func stopCell() -> Cell {
        if hasUnits {
            return Cell(
                glyph: .stop,
                name: "Stop selected units.",
                isEnabled: true,
                action: {
                    self.stop()
                    self.clearReason()
                }
            )
        }
        return unavailableCell(glyph: .stop, label: "Stop. No units selected.")
    }

    private func pageToggleCell() -> Cell {
        switch citizenPage {
        case .economy:
            return Cell(
                glyph: .pageForward,
                name: "▸ Military",
                isPrimary: true,
                isEnabled: true,
                action: { self.toggleCitizenPage() }
            )
        case .military:
            return Cell(
                glyph: .pageBack,
                name: "◂ Economy",
                isPrimary: true,
                isEnabled: true,
                action: { self.toggleCitizenPage() }
            )
        }
    }

    private func toggleCitizenPage() {
        switch citizenPage {
        case .economy: citizenPage = .military
        case .military: citizenPage = .economy
        }
        clearReason()
    }

    // MARK: Inspect / non-production selection

    private func inspectRows() -> [[Cell]] {
        let orders: [Cell] = [
            unavailableCell(glyph: .move, label: "Move. Unavailable."),
            stopCell(),
            unavailableCell(glyph: .guardStance, label: "Guard. Unavailable."),
        ]
        let stances: [Cell] = [
            unavailableCell(glyph: .gather, label: "Gather. Unavailable."),
            unavailableCell(glyph: .rally, label: "Set rally point. Unavailable."),
            unavailableCell(glyph: .outpost, label: "Build Outpost. Select a citizen."),
        ]
        let structures: [Cell] = [
            unavailableCell(glyph: .farm, label: "Build Farm. Select a citizen."),
            unavailableCell(glyph: .extractor, label: "Build Matter Extractor. Select a citizen."),
            unavailableCell(glyph: .dwelling, label: "Build Dwelling. Select a citizen."),
        ]
        return [orders, stances, structures]
    }

    private func buildCell(_ kind: BuildingKind) -> Cell {
        let cost: ResourcePool = simulation.tuning.cost(for: kind)
        let blocker: BuildBlocker? = simulation.buildBlocker(for: kind, faction: viewer)
        let reason: String? = blocker.map { self.buildBlockerText($0) }
        let canBuild: Bool = reason == nil
        let label: String = reason
            ?? "\(kind.displayName). \(kind.purpose). Costs \(cost.costSummary)."

        let action: (() -> Void)?
        if let reason {
            action = { self.showReason(reason) }
        } else {
            action = {
                self.clearReason()
                self.controller?.beginBuildGhost(kind)
            }
        }

        return Cell(
            glyph: kind.glyph,
            name: label,
            reason: reason,
            surfacesReasonAutomatically: reason != nil,
            isPrimary: canBuild,
            badge: primaryBadge(for: cost),
            isEnabled: canBuild,
            action: action
        )
    }

    private func buildBlockerText(_ blocker: BuildBlocker) -> String {
        switch blocker {
        case .unaffordable(let missing):
            return "Needs \(missingCostSummary(needed: missing, have: .zero))."
        case .missingPrerequisite(.formationYard):
            return "Requires a completed Formation Yard."
        case .missingPrerequisite(let prerequisite):
            return "Requires a completed \(prerequisite.displayName)."
        case .illegalSite:
            return "Cannot build on this site."
        }
    }

    private func unavailableCell(glyph: HUDGlyph.Kind, label: String) -> Cell {
        Cell(
            glyph: glyph,
            name: label,
            reason: label,
            action: { self.showReason(label) }
        )
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
