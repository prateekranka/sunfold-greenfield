import SwiftUI

/// The always-visible economy readout: four resources, population and age.
///
/// Anchored flush to the top edge with only its lower corners cut, so it reads
/// as hanging from the bezel rather than floating over the diorama. Nothing in
/// here is interactive — it is a statement of state, and every pixel of the
/// world below it stays tappable.
struct ResourceRail: View {
    let stock: ResourcePool
    let population: (used: Int, cap: Int)
    let age: Age

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ResourceKind.allCases, id: \.self) { kind in
                ResourceChip(kind: kind, value: stock[kind])
                separator
            }
            populationChip
            separator
            ageChip
        }
        .hudPanel(
            cut: 13,
            corners: .bottom,
            padding: EdgeInsets(top: 8, leading: 4, bottom: 9, trailing: 4)
        )
    }

    private var separator: some View {
        Rectangle()
            .fill(SunfoldPalette.hudEdge)
            .frame(width: 1, height: 17)
            .opacity(0.55)
    }

    /// Turns amber once the cap is reached: the player's next problem is always
    /// housing, and this is the only place the game can say so before they queue
    /// something they cannot afford to house.
    private var populationChip: some View {
        let isCapped = population.used >= population.cap
        return HStack(spacing: 6) {
            Text("POP").hudLabel()
            Text("\(population.used)/\(population.cap)")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(isCapped ? SunfoldPalette.hudAccent : SunfoldPalette.hudText)
        }
        .padding(.horizontal, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Population \(population.used) of \(population.cap)")
    }

    private var ageChip: some View {
        Text(age.displayName.uppercased())
            .font(.system(size: 10, weight: .bold))
            .tracking(1.6)
            .foregroundStyle(SunfoldPalette.hudAccent)
            .padding(.horizontal, 12)
            .accessibilityLabel("\(age.displayName) age")
    }
}

/// One resource: glyph, running total, and a pulse when a load lands.
///
/// The pulse only fires on a jump of two or more. The Core trickles a fraction
/// of a unit every second, so flashing on every change would make the rail
/// twitch permanently and teach the player nothing. A delivery arrives as a
/// whole load at once, which is exactly the event worth pointing at.
struct ResourceChip: View {
    let kind: ResourceKind
    let value: Double

    @State private var flash: Double = 0
    @State private var delta: Int = 0

    private var tint: Color { Color(SunfoldPalette.resourceTint(kind)) }
    private var shown: Int { Int(value.rounded(.down)) }

    var body: some View {
        HStack(spacing: 7) {
            ResourceGlyph(kind: kind)
                .fill(tint)
                .frame(width: 15, height: 15)
                .scaleEffect(1 + flash * 0.28)
                .shadow(color: tint.opacity(flash), radius: 7)

            Text("\(shown)")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(SunfoldPalette.hudText)
        }
        .padding(.horizontal, 12)
        .overlay(alignment: .top) { gainLabel }
        .onChange(of: shown) { previous, current in
            guard current - previous >= 2 else { return }
            delta = current - previous
            flash = 1
            withAnimation(.easeOut(duration: 1.0)) { flash = 0 }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(kind.displayName) \(shown)")
    }

    /// Rises and fades out of the chip. Drawn in an overlay with no layout
    /// footprint so the rail never reflows when a delivery lands.
    private var gainLabel: some View {
        Text("+\(delta)")
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(tint)
            .opacity(flash)
            .offset(y: -6 - 13 * (1 - flash))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
