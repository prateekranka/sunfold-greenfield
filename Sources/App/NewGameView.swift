import SwiftUI

/// The compact pre-match choice. It chooses the player's simulation perspective;
/// the other faction is created as the adversary for the same deterministic map.
struct NewGameView: View {
    let onChoose: (Faction) -> Void

    var body: some View {
        ZStack {
            Color(SunfoldPalette.voidDeep)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                VStack(spacing: 5) {
                    Text("SUNFOLD")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .tracking(5)
                        .foregroundStyle(HUDInk.accent)
                    Text("NEW GAME")
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .tracking(3)
                        .foregroundStyle(HUDInk.text)
                    Text("Choose your civilization")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(HUDInk.textDim)
                }

                HStack(spacing: 14) {
                    factionCard(.sunwoven)
                    factionCard(.gravemark)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
            .hudSurface(cut: 16)
            .frame(maxWidth: 620)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("New game. Choose your civilization.")
        }
        .preferredColorScheme(.dark)
    }

    private func factionCard(_ faction: Faction) -> some View {
        Button {
            onChoose(faction)
        } label: {
            VStack(spacing: 9) {
                HUDGlyph(faction == .sunwoven ? .sunburst : .coreMark)
                    .fill(HUDInk.friendly(for: faction), style: HUDGlyph.Kind.sunburst.fillStyle)
                    .frame(width: 32, height: 32)
                    .shadow(color: HUDInk.friendly(for: faction).opacity(0.45), radius: 8)

                Text(faction.displayName.uppercased())
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(HUDInk.text)

                Text(faction == .sunwoven
                    ? "Shape the living current."
                    : "Master the pull of stone.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(HUDInk.textDim)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 116)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(HUDInk.well, in: ChamferedRect(cut: 10))
            .overlay {
                ChamferedRect(cut: 10)
                    .stroke(HUDInk.friendly(for: faction).opacity(0.72), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Play as \(faction.displayName)")
        .accessibilityHint("Starts a new match as \(faction.displayName).")
    }
}
