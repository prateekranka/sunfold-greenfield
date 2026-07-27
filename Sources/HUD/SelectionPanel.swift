import SwiftUI

/// What the player currently has selected, and what it is doing right now.
///
/// The panel is absent when nothing is selected rather than showing an empty
/// frame. Chrome that is permanently on screen with nothing in it trains the
/// player to stop looking at it, and this is the surface that has to carry the
/// answer to "did my order land?".
struct SelectionPanel: View {
    let simulation: SkirmishSimulation
    let selection: SelectionModel

    var body: some View {
        Group {
            if let unit = singleUnit {
                unitCard(unit)
            } else if selectedUnits.count > 1 {
                groupCard(selectedUnits)
            } else if let building = selection.selectedBuilding.flatMap(simulation.building) {
                buildingCard(building)
            } else if let deposit = selection.selectedDeposit.flatMap(simulation.deposit) {
                depositCard(deposit)
            }
        }
        .transition(.opacity.combined(with: .offset(y: 8)))
    }

    // MARK: - Reading the selection

    private var selectedUnits: [Unit] {
        selection.selectedUnits
            .compactMap(simulation.unit)
            .sorted { $0.id.raw < $1.id.raw }
    }

    private var singleUnit: Unit? {
        let units = selectedUnits
        return units.count == 1 ? units[0] : nil
    }

    // MARK: - Cards

    private func unitCard(_ unit: Unit) -> some View {
        card {
            title(unit.kind.displayName, trailing: unit.faction.displayName)
            activityRow(unit)
            if let cargo = unit.cargo { cargoRow(cargo) }
            if unit.life < unit.kind.maxLife {
                lifeRow(current: unit.life, maximum: unit.kind.maxLife)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(unit.kind.displayName) selected. \(activityText(unit)).")
    }

    private func groupCard(_ units: [Unit]) -> some View {
        // Counting by kind rather than listing every unit: a player reading a
        // group cares about composition, not about which individuals are in it.
        let counts = UnitKind.allCases.compactMap { kind -> (UnitKind, Int)? in
            let count = units.filter { $0.kind == kind }.count
            return count > 0 ? (kind, count) : nil
        }
        let carried = units.compactMap(\.cargo).reduce(into: [ResourceKind: Double]()) {
            $0[$1.kind, default: 0] += $1.amount
        }

        // A group of one kind names itself in the title — "4 Citizens" says
        // everything, and repeating it underneath as a breakdown line was pure
        // redundancy on the most common selection in the game.
        let isUniform = counts.count == 1
        let heading = isUniform
            ? "\(units.count) \(counts[0].0.pluralName)"
            : "\(units.count) Selected"

        return card {
            title(heading, trailing: units[0].faction.displayName)
            if !isUniform {
                Text(counts.map { "\($0.1) \($0.0.pluralName)" }.joined(separator: " · "))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(SunfoldPalette.hudText)
            }
            if !carried.isEmpty {
                let summary = carried
                    .sorted { $0.key.rawValue < $1.key.rawValue }
                    .map { "\(Int($0.value.rounded())) \($0.key.displayName)" }
                    .joined(separator: " · ")
                Text("Carrying \(summary)").hudLabel()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(units.count) units selected")
    }

    private func buildingCard(_ building: Building) -> some View {
        card {
            title(building.kind.displayName, trailing: building.faction.displayName)
            if building.isComplete {
                if building.kind.acceptsDropOff {
                    Text("Accepts deliveries").hudLabel()
                } else {
                    Text("Complete").hudLabel()
                }
            } else {
                Text("Building \(Int(building.constructionProgress * 100))%").hudLabel()
                HUDMeter(fraction: building.constructionProgress, tint: SunfoldPalette.hudAccent)
            }
            if building.life < building.kind.maxLife {
                lifeRow(current: building.life, maximum: building.kind.maxLife)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(building.kind.displayName) selected")
    }

    /// A node the player tapped with nothing selected. Answers the two questions
    /// that decide whether to send anyone: what is in it, and who is already on
    /// it. Renewable nodes report no total, because they have none.
    private func depositCard(_ deposit: Deposit) -> some View {
        let tint = Color(SunfoldPalette.resourceTint(deposit.kind))
        let workers = simulation.units.values.count {
            $0.faction == .sunwoven && $0.assignment == deposit.id
        }

        return card {
            title(deposit.kind.displayName, trailing: "Node")
            HStack(spacing: 6) {
                ResourceGlyph(kind: deposit.kind)
                    .fill(tint)
                    .frame(width: 12, height: 12)
                Text(deposit.kind.isRenewable
                     ? "Renewable"
                     : "\(Int(deposit.remaining.rounded())) remaining")
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(SunfoldPalette.hudText)
            }
            Text(workers == 0
                 ? "No one working it"
                 : "\(workers) working · \(max(0, GatheringSystem.stationCount - workers)) stations free")
                .hudLabel()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(deposit.kind.displayName) node, \(workers) citizens working")
    }

    // MARK: - Rows

    private func activityRow(_ unit: Unit) -> some View {
        Text(activityText(unit))
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(SunfoldPalette.hudText)
    }

    /// The load meter is the readout that makes gathering legible: without it a
    /// citizen walking home looks identical to a citizen wandering off.
    private func cargoRow(_ cargo: Cargo) -> some View {
        let tint = Color(SunfoldPalette.resourceTint(cargo.kind))
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                ResourceGlyph(kind: cargo.kind)
                    .fill(tint)
                    .frame(width: 11, height: 11)
                Text("\(Int(cargo.amount.rounded())) / \(Int(simulation.tuning.carryCapacity))")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(SunfoldPalette.hudTextDim)
            }
            HUDMeter(
                fraction: cargo.amount / simulation.tuning.carryCapacity,
                tint: tint
            )
        }
    }

    private func lifeRow(current: Double, maximum: Double) -> some View {
        HUDMeter(fraction: current / maximum, tint: Color(SunfoldPalette.sunwovenTurquoise))
    }

    // MARK: - Wording

    /// Derived from cargo and destination rather than from a stored phase, for
    /// the same reason `GatheringSystem` derives its legs that way: a label that
    /// can disagree with the state it describes is worse than no label.
    private func activityText(_ unit: Unit) -> String {
        switch unit.activity {
        case .idle:
            unit.cargo == nil ? "Idle" : "Holding a load — no drop-off"
        case .moving:
            "Moving"
        case .gathering(let depositID):
            gatherText(unit, depositID: depositID)
        case .boarding:
            "Boarding"
        case .aboard:
            "Aboard"
        case .constructing:
            "Building"
        case .attacking:
            "Attacking"
        }
    }

    private func gatherText(_ unit: Unit, depositID: EntityID) -> String {
        let name = simulation.deposit(depositID)?.kind.displayName ?? "resources"
        if GatheringSystem.isFull(unit, tuning: simulation.tuning) {
            return "Delivering \(name)"
        }
        return unit.destination == nil ? "Gathering \(name)" : "Walking to \(name)"
    }

    // MARK: - Chrome

    /// Fixed width, not hugging. A panel that resizes as its own text changes —
    /// "Idle" to "Walking to Matter" to "Delivering Matter" — jitters on every
    /// leg of the gather loop, which is the exact moment the player is reading
    /// it. Holding the width still costs a little empty space and buys a surface
    /// that never moves.
    private static let cardWidth: CGFloat = 214

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            content()
        }
        .frame(width: Self.cardWidth, alignment: .leading)
        .hudPanel(cut: 12, corners: [.topLeading, .topTrailing, .bottomTrailing])
    }

    private func title(_ text: String, trailing: String) -> some View {
        HStack(spacing: 12) {
            Text(text)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(SunfoldPalette.hudAccent)
            Spacer(minLength: 0)
            Text(trailing.uppercased()).hudLabel()
        }
    }
}
