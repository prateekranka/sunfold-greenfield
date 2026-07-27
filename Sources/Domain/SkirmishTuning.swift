import Foundation

/// Every cost, rate, timing and radius in the skirmish lives here.
///
/// Nothing in this file may be duplicated as a literal elsewhere. Values are the
/// documented baseline for the first playable seed and may only be changed from
/// recorded natural playthrough timing (gate G6), never from intuition.
struct SkirmishTuning: Sendable {
    static let baseline = SkirmishTuning()

    // MARK: - Starting state

    var startingResources = ResourcePool(provisions: 180, matter: 160, lumen: 40, aether: 0)
    var startingCitizens: Int = 4
    var startingPopulationCap: Int = 8

    // MARK: - Simulation

    /// Fixed simulation rate. Presentation interpolates between steps; gathering,
    /// combat and AI never read display frame timing.
    var simulationHz: Double = 20
    var stepDuration: Double { 1.0 / simulationHz }
    /// Upper bound on steps consumed per frame, so a stall cannot spiral.
    var maxStepsPerFrame: Int = 5

    // MARK: - Gathering (units per second while actively working)

    var gatherRates = ResourcePool(provisions: 1.6, matter: 1.4, lumen: 1.1, aether: 0.9)

    /// How much a citizen carries before walking a load home. Sets the rhythm of
    /// the whole early game: too small and the fragment is a conveyor belt of
    /// walking, too large and a node is worked in one uninterrupted stand.
    var carryCapacity: Double = 10

    /// Quiet Core trickle so one early mistake cannot hard-lock a first match.
    /// The AI receives the identical rule — this is not a player handicap.
    var coreTrickle = ResourcePool(provisions: 0.25, matter: 0.20, lumen: 0.10, aether: 0)

    // MARK: - Units

    var citizenCost = ResourcePool(provisions: 50)
    var citizenBuildTime: Double = 14
    var citizenPopulation: Int = 1

    var pathfinderCost = ResourcePool(provisions: 60, lumen: 25)
    var pathfinderBuildTime: Double = 18
    var pathfinderPopulation: Int = 1

    var vanguardCost = ResourcePool(provisions: 70, matter: 45)
    var vanguardBuildTime: Double = 22
    var vanguardPopulation: Int = 2

    var rangedCost = ResourcePool(provisions: 65, lumen: 35)
    var rangedBuildTime: Double = 22
    var rangedPopulation: Int = 2

    var transportCapacity: Int = 4

    // MARK: - Buildings

    var farmCost = ResourcePool(matter: 70)
    var farmBuildTime: Double = 12

    var matterExtractorCost = ResourcePool(matter: 60)
    var matterExtractorBuildTime: Double = 14

    var dwellingCost = ResourcePool(matter: 80)
    var dwellingBuildTime: Double = 15
    var dwellingPopulationGrant: Int = 4

    var formationYardCost = ResourcePool(matter: 110, lumen: 40)
    var formationYardBuildTime: Double = 18

    var expansionOutpostCost = ResourcePool(matter: 100, lumen: 30)
    var expansionOutpostBuildTime: Double = 20
    var expansionOutpostPopulationGrant: Int = 2

    // MARK: - Age up

    var voyagerCost = ResourcePool(provisions: 180, matter: 180, lumen: 100, aether: 80)
    /// Readable channel with world construction feedback, not an instant unlock.
    var voyagerChannelDuration: Double = 20

    // MARK: - Production

    var maxQueueLength: Int = 10
    /// Fraction of cost returned when a queued item is cancelled.
    var cancelRefundFraction: Double = 0.75

    // MARK: - Victory

    var dominionHoldDuration: Double = 45
    var dominionMilestones: [Double] = [15, 30]
    var enemyCoreLife: Double = 600
    var corePressureThresholds: [Double] = [0.75, 0.50, 0.25]

    // MARK: - Gravemark AI (First Timer)

    /// Earliest wall-clock seconds at which the AI may commit to each behaviour.
    /// These are floors, not schedules — the AI still needs the economy to act.
    var aiEarliestExpansion: Double = 120
    var aiEarliestVoyagerComplete: Double = 255
    var aiEarliestDominionContest: Double = 315
    var aiEarliestHomeRaid: Double = 390

    // MARK: - Teaching and hints

    var hintFirstDelay: Double = 30
    var hintPulseDelay: Double = 60
    var hintFocusOfferDelay: Double = 90
    var hintRepeatInterval: Double = 60

    // MARK: - Camera

    /// Degrees below horizontal. The visual bible locks this to a 55–60° band.
    var cameraPitchDegrees: Float = 57
    /// Full vertical world extent visible at default zoom, in world units.
    ///
    /// Measured against concept 01 rather than reasoned from a percentage: in the
    /// approved frame the home fragment spans about 71% of the viewport width. At
    /// 82 it spanned 41% — the diorama read as a distant model and citizens read
    /// as specks. A 48 m fragment at 71% of a 4:3 viewport needs a 68 m horizontal
    /// extent, so 51 vertical; 58 keeps a little breathing room around the rim.
    var cameraDefaultZoom: Float = 58
    /// Close enough to read a single citizen's silhouette and gait.
    var cameraMinZoom: Float = 34
    var cameraMaxZoom: Float = 165
    /// Distance from focus to camera. Orthographic, so this affects clipping only.
    var cameraDistance: Float = 260
    /// Must clear the star shell and the celestial body, which sit far behind the map.
    var cameraFarPlane: Float = 1600
    /// How far behind the focus the void card sits. Comfortably behind every
    /// fragment, comfortably inside the far plane.
    var voidBackdropDistance: Float = 420

    // MARK: - Presentation scale

    /// How much larger a unit is drawn than its true height.
    ///
    /// Unit meshes are authored to a real human contract — a citizen is 1.80 m —
    /// which is the right thing for the mesh factory to own. But an RTS reads its
    /// people at a glance, and concept 01 draws them noticeably heavier than
    /// life. This is the one place that exaggeration lives, and `footprintRadius`
    /// carries the same factor so hit-testing, formation spacing and the rim
    /// margin never disagree with what the player can see.
    var unitVisualScale: Float = 1.25
}
