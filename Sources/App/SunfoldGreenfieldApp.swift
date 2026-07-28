import SwiftUI

@main
struct SunfoldGreenfieldApp: App {
    /// The authored, locked seed for the first playable map. Procedural variation
    /// is a later checkpoint; every G0–G6 run must be reproducible from this value.
    static let lockedSeed: UInt64 = 20_260_726

    /// Layout selection. Pass `-sunfoldMap riverlands`, `basin` or `fjords` as a
    /// launch argument; default is `riverlands`.
    ///
    /// The CP-12/CP-13 names (`coastland`, `isthmus`, `continental`, `crescent`)
    /// still resolve — see `WorldMapID.fromLaunchArgument`.
    private static let selectedMapID: WorldMapID = {
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "-sunfoldMap"),
           args.index(after: index) < args.endIndex {
            return WorldMapID.fromLaunchArgument(args[args.index(after: index)])
        }
        return .default
    }()

    var body: some Scene {
        WindowGroup {
            RootView(seed: Self.lockedSeed, mapID: Self.selectedMapID)
        }
    }
}
