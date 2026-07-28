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
///
/// **Honesty about what is wired.** G2 gameplay — construction, production,
/// stances, rally points — is parked, so most of these have nothing to call yet
/// and are rendered disabled. That is the truthful state, and it is also the
/// correct one: an enabled button that silently does nothing is worse chrome
/// than a dimmed one. `stop` is wired, because cancelling a move is expressible
/// with the orders that do exist.
struct CommandGrid: View {
    let simulation: SkirmishSimulation
    let selection: SelectionModel

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

    /// One cell of the card. `action` is nil for everything G2 has not built.
    private struct Cell {
        let glyph: HUDGlyph.Kind
        let name: String
        var isPrimary = false
        var action: (() -> Void)?
    }

    /// Built a row at a time rather than as one nested literal: nine
    /// memberwise inits with defaulted arguments inside a `[[Cell]]` is more
    /// than the type checker will spend, and it fails with "failed to produce
    /// diagnostic for expression" rather than with anything about the card.
    private var rows: [[Cell]] {
        // Annotated and wrapped rather than `hasUnits ? stop : nil`: inferring
        // `(() -> Void)?` from a bare method reference against `nil` is the other
        // half of the same type-checker cliff.
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
            Cell(glyph: .farm, name: "Build Farm"),
            Cell(glyph: .extractor, name: "Build Matter Extractor"),
            Cell(glyph: .dwelling, name: "Build Dwelling")
        ]
        return [orders, stances, structures]
    }

    private func tile(for cell: Cell) -> some View {
        HUDIconTile(
            glyph: cell.glyph,
            size: HUDMetrics.commandTile,
            isEnabled: cell.action != nil,
            isPrimary: cell.isPrimary,
            name: cell.name,
            action: cell.action
        )
    }

    // MARK: - Orders

    /// Stop is a move to where the unit already stands. The simulation clears a
    /// destination on arrival, so ordering a unit to its own position is exactly
    /// "cancel what you were doing" without needing a second verb in the
    /// simulation's vocabulary.
    private func stop() {
        for id in selectedUnits {
            guard let unit = simulation.unit(id) else { continue }
            simulation.order(id, moveTo: unit.position)
        }
    }
}
