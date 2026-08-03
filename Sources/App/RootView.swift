import Foundation
import SwiftUI

/// The app shell: the diorama, the tactical HUD over it, and the debug surface.
///
/// The HUD deliberately occupies only the top strip and the lower-left corner.
/// The centre of a landscape iPad is where the player's hands are not, and where
/// the game lives — nothing permanent is allowed to sit there.
struct RootView: View {
    private struct MatchSession: Identifiable {
        let id = UUID()
        let controller: WorldController
    }

    @State private var session: MatchSession?
    @State private var isDebugExpanded = true

    /// The debug surface is developer tooling, not chrome, and a visible telemetry
    /// panel is the single loudest "this is a dev build" signal in a captured
    /// frame. It is opt-in: pass `-sunfoldDebug` as a launch argument (Xcode
    /// scheme → Arguments) to bring it back.
    private static let showsDebugOverlay =
        ProcessInfo.processInfo.arguments.contains("-sunfoldDebug")

    private static let showsPerfOverlay =
        PerfLaunchFlags.isEnabled && PerfLaunchFlags.showsOverlay

    /// The Gravemark adversary runs by default — without it there is nobody on
    /// the other side of the map. Pass `-sunfoldNoAdversary` to freeze it, which
    /// is what a perf capture wants: a still opponent makes the frame times
    /// comparable between runs.
    private static let adversaryEnabled =
        !ProcessInfo.processInfo.arguments.contains("-sunfoldNoAdversary")

    /// Perf launches must enter the match without a human tap. Ordinary launches
    /// open on the compact civilization choice screen.
    private static let startsInMatch =
        PerfLaunchFlags.isEnabled
        || ProcessInfo.processInfo.arguments.contains("-sunfoldNoAdversary")

    init(seed: UInt64, mapID: WorldMapID = .default, perfDensity: Int? = nil) {
        self.seed = seed
        self.mapID = mapID
        self.perfDensity = perfDensity
        _session = State(
            initialValue: Self.startsInMatch
                ? MatchSession(
                    controller: WorldController(
                        simulation: SkirmishSimulation(
                            seed: seed,
                            mapID: mapID,
                            perfDensity: perfDensity,
                            playerFaction: .sunwoven,
                            adversaryEnabled: Self.adversaryEnabled
                        )
                    )
                )
                : nil
        )
    }

    private var controller: WorldController { session!.controller }
    private var simulation: SkirmishSimulation { controller.simulation }

    var body: some View {
        Group {
            if let session {
                matchView(session)
            } else {
                NewGameView(onChoose: startGame(as:))
            }
        }
        .background(Color(SunfoldPalette.voidDeep))
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
    }

    @ViewBuilder
    private func matchView(_ session: MatchSession) -> some View {
        let controller = session.controller
        ZStack(alignment: .topLeading) {
            SunfoldRealityView(controller: controller)
                .ignoresSafeArea()
                .id(session.id)

            if !controller.isSceneReady {
                MatchLoadingView(faction: controller.playerFaction)
            }

            if Self.showsPerfOverlay {
                PerfOverlay(harness: PerfHarness.shared, controller: controller)
                    .padding(.top, 8)
                    .padding(.trailing, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }

            VStack(spacing: 0) {
                topStrip
                HStack(alignment: .top, spacing: 0) {
                    GroupRail()
                        .padding(.leading, 12)
                        .padding(.top, 10)
                    Spacer(minLength: 0)
                    if let ghost = controller.buildGhost {
                        PlacementPanel(
                            simulation: simulation,
                            session: ghost,
                            onCancel: { controller.cancelBuildGhost() }
                        )
                        .padding(.trailing, 16)
                        .padding(.top, 8)
                        .transition(.opacity.combined(with: .offset(y: -6)))
                    }
                }
                .animation(.easeOut(duration: 0.18), value: controller.buildGhost != nil)
                Spacer(minLength: 0)
                bottomStrip
            }

            if let outcome = simulation.outcome {
                MatchOverlay(
                    outcome: outcome,
                    viewer: controller.playerFaction,
                    onPlayAgain: { controller.restartMatch() },
                    onNewGame: showNewGame
                )
            }
        }
        .animation(.easeOut(duration: 0.25), value: simulation.outcome)
    }

    private func startGame(as faction: Faction) {
        guard session == nil else { return }
        session = MatchSession(
            controller: WorldController(
                simulation: SkirmishSimulation(
                    seed: seed,
                    mapID: mapID,
                    perfDensity: perfDensity,
                    playerFaction: faction,
                    adversaryEnabled: Self.adversaryEnabled
                )
            )
        )
    }

    private func showNewGame() {
        session?.controller.dispose()
        session = nil
    }

    private let seed: UInt64
    private let mapID: WorldMapID
    private let perfDensity: Int?

    /// Emblem and speed join the resource rail so the top edge matches concept 01.
    /// Debug stays inset and opt-in so it never contaminates a capture.
    private var topStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 12) {
                TopBar(simulation: simulation, controller: controller)
                if Self.showsDebugOverlay {
                    DebugOverlay(controller: controller, isExpanded: $isDebugExpanded)
                        .padding(.top, 4)
                }
            }
            ObjectiveRail(
                simulation: simulation,
                viewer: simulation.playerFaction,
                onNewGame: showNewGame
            )
                .padding(.leading, 4)
        }
        .padding(.horizontal, 16)
    }

    /// Map at one thumb, commands at the other, and the selection between them.
    private var bottomStrip: some View {
        HStack(alignment: .bottom, spacing: 14) {
            Minimap(
                simulation: simulation,
                rig: controller.rig,
                viewer: simulation.playerFaction
            )
            Spacer(minLength: 0)
            SelectionPanel(
                simulation: simulation,
                selection: controller.selection,
                controller: controller
            )
            Spacer(minLength: 0)
            CommandGrid(
                simulation: simulation,
                selection: controller.selection,
                controller: controller
            )
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .animation(.easeOut(duration: 0.18), value: controller.selection.selectedUnits)
        .animation(.easeOut(duration: 0.18), value: controller.selection.selectedBuilding)
    }
}
