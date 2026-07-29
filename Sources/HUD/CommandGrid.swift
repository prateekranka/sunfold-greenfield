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

    private var selectedUnits: [EntityID] { Array(selection.selectedUnits) }
    private var hasUnits: Bool { !selectedUnits.isEmpty }
    private var hasSelection: Bool {
        hasUnits
            || selection.selectedBuilding != nil
            || selection.selectedDeposit != nil
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 7) {
            Text(hasUnits ? "Orders" : (hasSelection ? "Inspect" : "No selection")).hudTitle()
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

    // MARK: - Layout

    private struct Cell {
        let glyph: HUDGlyph.Kind
        let name: String
        var isPrimary = false
        var badge: String?
        var action: (() -> Void)?
    }

    private var rows: [[Cell]] {
        let stopAction: (() -> Void)? = hasUnits ? { self.stop() } : nil
        let orders: [Cell] = [
            Cell(glyph: .move, name: "Move", isPrimary: hasUnits),
            Cell(glyph: .stop, name: "Stop", action: stopAction),
            Cell(glyph: .guardStance, name: "Guard")
        ]
        let stances: [Cell] = [
            Cell(glyph: .gather, name: "Gather"),
            Cell(glyph: .rally, name: "Set rally point"),
            Cell(glyph: .outpost, name: "Build Outpost")
        ]
        let structures: [Cell] = [
            buildCell(.farm, glyph: .farm),
            buildCell(.matterExtractor, glyph: .extractor),
            buildCell(.dwelling, glyph: .dwelling)
        ]
        return [orders, stances, structures]
    }

    private func buildCell(_ kind: BuildingKind, glyph: HUDGlyph.Kind) -> Cell {
        let cost = simulation.tuning.cost(for: kind)
        let canAfford = simulation.stock(for: .sunwoven).covers(cost)
        let badge = cost.matter > 0 ? "\(Int(cost.matter.rounded()))" : nil
        return Cell(
            glyph: glyph,
            name: "\(kind.displayName). \(kind.purpose). Costs \(cost.costSummary).",
            isPrimary: canAfford && hasUnits,
            badge: badge,
            action: { self.controller?.beginBuildGhost(kind) }
        )
    }

    private func tile(for cell: Cell) -> some View {
        HUDIconTile(
            glyph: cell.glyph,
            size: HUDMetrics.commandTile,
            isEnabled: cell.action != nil,
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
