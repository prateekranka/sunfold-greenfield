import SwiftUI

struct ThreeJSRootView: View {
    private enum Phase { case menu, game }

    @StateObject private var bridge = ThreeJSBridge()
    @StateObject private var saves = ThreeJSSaveStore()
    @State private var phase: Phase = ProcessInfo.processInfo.arguments.contains("-sunfoldThreeJSStart") ? .game : .menu
    @State private var faction = "sunwoven"
    /// The document to resume from, or nil for a fresh match. Set only by the menu.
    @State private var resumeSnapshot: String?

    var body: some View {
        Group {
            switch phase {
            case .menu:
                ThreeJSMenuView(
                    savedSlot: saves.slot,
                    onNewGame: { selectedFaction in
                        faction = selectedFaction
                        resumeSnapshot = nil
                        phase = .game
                    },
                    onContinue: {
                        guard let slot = saves.slot else { return }
                        faction = slot.faction
                        resumeSnapshot = slot.snapshot
                        phase = .game
                    }
                )
            case .game:
                ThreeJSGameView(
                    bridge: bridge,
                    faction: faction,
                    resumeSnapshot: resumeSnapshot
                )
            }
        }
        .background(Color.black)
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onChange(of: bridge.lastSnapshot) { _, snapshot in
            // The runtime decided a save exists; Swift only files it. The
            // document is never inspected here — simulation truth stays on the
            // other side of the bridge.
            guard let snapshot else { return }
            saves.write(snapshot: snapshot, faction: faction)
        }
        .onChange(of: bridge.lastEvent) { _, event in
            guard event == "returnedToMenu" else { return }
            phase = .menu
            resumeSnapshot = nil
            bridge.resetForNewDocument()
        }
    }
}

private struct ThreeJSMenuView: View {
    let savedSlot: ThreeJSSaveStore.Slot?
    let onNewGame: (String) -> Void
    let onContinue: () -> Void

    var body: some View {
        ZStack {
            Color(red: 0.02, green: 0.03, blue: 0.07).ignoresSafeArea()
            VStack(spacing: 18) {
                Text("SUNFOLD")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .tracking(5)
                    .foregroundStyle(Color(red: 0.86, green: 0.66, blue: 0.28))
                Text("THREE.JS EXPERIMENT")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .tracking(2.5)
                    .foregroundStyle(.white)
                Text("Choose your civilization")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
                HStack(spacing: 14) {
                    factionButton("sunwoven", title: "SUNWOVEN", subtitle: "Shape the living current.", tint: Color(red: 0.29, green: 0.71, blue: 0.71))
                    factionButton("gravemark", title: "GRAVEMARK", subtitle: "Master the pull of stone.", tint: Color(red: 0.65, green: 0.40, blue: 0.22))
                }

                if let savedSlot {
                    Button(action: onContinue) {
                        Text("CONTINUE \(savedSlot.faction.uppercased())")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .tracking(1.6)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(.white.opacity(0.34), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("threejs-continue")
                    .accessibilityLabel("Continue saved match")
                }
            }
            .padding(28)
            .background(Color.black.opacity(0.36), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.16), lineWidth: 1))
            .frame(maxWidth: 680)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("New game. Choose your civilization.")
    }

    private func factionButton(_ faction: String, title: String, subtitle: String, tint: Color) -> some View {
        Button { onNewGame(faction) } label: {
            VStack(spacing: 9) {
                Circle().fill(tint).frame(width: 28, height: 28).shadow(color: tint.opacity(0.55), radius: 10)
                Text(title).font(.system(size: 15, weight: .bold, design: .rounded)).tracking(1.2).foregroundStyle(.white)
                Text(subtitle).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.62)).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 112)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(tint.opacity(0.7), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Play as \(title)")
    }
}

private struct ThreeJSGameView: View {
    @ObservedObject var bridge: ThreeJSBridge
    let faction: String
    let resumeSnapshot: String?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ThreeJSWebView(bridge: bridge).ignoresSafeArea()

            if !bridge.runtimeReady {
                ProgressView("WEAVING THE WORLD")
                    .tint(.white)
                    .foregroundStyle(.white.opacity(0.8))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .tracking(2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(red: 0.02, green: 0.03, blue: 0.07))
            }

            if let fatalErrorMessage = bridge.fatalErrorMessage {
                Text(fatalErrorMessage)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.86))
                    .multilineTextAlignment(.center)
                    .padding(20)
                    .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(24)
            }
        }
        .onChange(of: bridge.bridgeReady) { _, ready in
            guard ready else { return }
            if let resumeSnapshot {
                bridge.send(.loadGame, payload: ["snapshot": resumeSnapshot])
            } else {
                bridge.send(.startGame, payload: ["faction": faction, "seed": "20260726"])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sunfold Three.js gameplay")
    }
}
