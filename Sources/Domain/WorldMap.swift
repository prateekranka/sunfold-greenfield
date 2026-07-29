import Foundation
import simd

/// A point on the world plane. World space is metres on the XZ plane, Y up.
/// North is -Z, so a camera at yaw 0 looks north-up.
typealias WorldPoint = SIMD2<Float>

/// The named regions of the proof map. Every system — renderer, pathing, minimap,
/// AI, camera bounds, deposits, spawn points and selection — resolves position
/// through this contract, so a place that looks walkable is walkable.
enum RegionID: String, CaseIterable, Sendable {
    case sunwovenHome
    case gravemarkHome
    case dominion
    case sunwovenExpansion
    case gravemarkExpansion
    case neutralOutcropNorth
    case neutralOutcropSouth

    var isHome: Bool { self == .sunwovenHome || self == .gravemarkHome }

    /// Which side, if any, owns this region at match start.
    var startingOwner: Faction? {
        switch self {
        case .sunwovenHome: .sunwoven
        case .gravemarkHome: .gravemark
        default: nil
        }
    }
}

/// Selectable seed-locked layouts.
///
/// All three are **one continent cut by void water** (user direction, CP-14).
/// Space is this game's water: the maps are shaped the way an Age of Empires map
/// is shaped — an irregular coast, a river you ferry across, lakes and inlets
/// biting into the interior — rather than as a raft of overlapping discs. Each
/// variant leads with a different water form. None of them is a mirror of itself:
/// fairness here is the two Cores being equidistant from the Dominion, and nothing
/// more (user direction, 2026-07-28).
///
/// Select at launch with `-sunfoldMap riverlands` (default), `basin` or `fjords`.
enum WorldMapID: String, CaseIterable, Sendable {
    /// Default. A broad continent split by a great void river that forks around
    /// the Dominion, with a tributary cutting each home off from its expansion.
    case riverlands
    /// A ring of land around one great void basin, with two flanking lakes.
    case basin
    /// A ragged coast: long void inlets reach in from the outer void, leaving
    /// each home on its own peninsula.
    case fjords

    static var `default`: WorldMapID { .riverlands }

    /// Resolves a launch argument value; unknown strings fall back to the default.
    ///
    /// The CP-12/CP-13 names still resolve so older notes, scripts and QA
    /// commands keep working rather than silently loading the wrong map.
    static func fromLaunchArgument(_ raw: String?) -> WorldMapID {
        guard let raw else { return .default }
        let key = raw.lowercased()
        switch key {
        case "riverlands", "coastland", "continental", "river", "map1", "1":
            return .riverlands
        case "basin", "isthmus", "crescent", "lake", "lakes", "map2", "2":
            return .basin
        case "fjords", "fjord", "inlets", "coast", "map3", "3":
            return .fjords
        default:
            return WorldMapID(rawValue: key) ?? .default
        }
    }
}

/// One authored land plate.
///
/// A plate is no longer a disc. `radius` is its *nominal* size — still the scale
/// every other system reasons in — and `coast` bends that into an outline with
/// capes and bays. Water carved by ``WorldMap/voidBodies`` then removes parts of
/// it, which is how a plate can end up as a river bank or a lake shore.
struct Fragment: Sendable {
    let id: RegionID
    /// Centre on the world plane.
    let center: WorldPoint
    /// Nominal radius. The authored outline varies around this.
    let radius: Float
    /// How far the underside tapers below the surface.
    let depth: Float
    /// The authored coastline shape.
    let coast: CoastProfile

    init(
        id: RegionID,
        center: WorldPoint,
        radius: Float,
        depth: Float,
        coast: CoastProfile = .round
    ) {
        self.id = id
        self.center = center
        self.radius = radius
        self.depth = depth
        self.coast = coast
    }

    /// Bearing convention shared with the mesh grid and `RimProfile`:
    /// vertices sit at `x = cos(bearing) · r`, `z = sin(bearing) · r`.
    static func bearing(of offset: WorldPoint) -> Float {
        atan2(offset.y, offset.x)
    }

    /// The authored land radius at a bearing, before water is carved out.
    func radius(atBearing bearing: Float) -> Float {
        radius * coast.reach(atBearing: bearing, center: center, nominal: radius)
    }

    /// The authored land radius in the direction of `point`.
    func radius(toward point: WorldPoint) -> Float {
        radius(atBearing: Fragment.bearing(of: point - center))
    }

    /// The outline as a closed polygon, ignoring water.
    func outline(samples: Int) -> [WorldPoint] {
        let count = max(8, samples)
        return (0..<count).map { step in
            let bearing = Float(step) / Float(count) * 2 * .pi
            let reach = radius(atBearing: bearing)
            return center + WorldPoint(cos(bearing), sin(bearing)) * reach
        }
    }

    /// The largest distance the outline reaches from the centre. Used for camera
    /// and minimap fitting, where a nominal radius would clip the capes off.
    var maxReach: Float {
        var largest: Float = 0
        for step in 0..<64 {
            largest = max(largest, radius(atBearing: Float(step) / 64 * 2 * .pi))
        }
        return largest
    }
}

/// A void route usable only by transports. Land units may never enter one.
struct VoidLane: Sendable {
    let from: RegionID
    let to: RegionID
}

/// A luminous gravity causeway carrying land units between two fragments.
struct Causeway: Sendable {
    let from: RegionID
    let to: RegionID
    /// When set, the causeway stays dormant until this faction has established
    /// its expansion Outpost. This is what forces the first crossing to be made
    /// by transport while still leaving a complete land route for a later Strike.
    let wovenByOutpostOf: Faction?

    var isAlwaysOpen: Bool { wovenByOutpostOf == nil }
}

/// The authored, seed-locked map.
///
/// **Composition (user direction, CP-14): one continent, cut by void water.**
/// The land is a union of shaped plates; rivers, lakes and inlets are subtracted
/// from it. This supersedes CP-13's contiguous-plate maps, whose silhouette read
/// as what it was built from — overlapping circles.
///
/// **Fairness (user direction, 2026-07-28): the two Cores are equidistant from
/// the Dominion, and that is the entire rule.** These maps were previously exact
/// half-turns of themselves — every plate had a twin, and the coastal noise was
/// folded onto a half-plane so both sides frayed identically. That bought a
/// fairness nobody had asked for at the cost of the thing that matters most here:
/// a mirror-symmetric map reads as one shape printed twice, however irregular each
/// half is. The layouts are now free to differ side to side, and ``core(bearing:reach:)``
/// carries the one rule that is left.
struct WorldMap: Sendable {
    let id: WorldMapID
    let seed: UInt64
    let fragments: [RegionID: Fragment]
    /// Rivers, lakes and inlets carved out of the land. Space is the water.
    let voidBodies: [VoidBody]
    /// Perturbs the coastline of the assembled landmass. See ``LandErosion`` for
    /// why this belongs to the map rather than to each plate.
    let erosion: LandErosion
    let voidLanes: [VoidLane]
    let causeways: [Causeway]

    /// Half-extent of the playable area, used for camera bounds. Fitted to the
    /// land so dry ground covers most of the rectangle (75–80% target); see
    /// ``fittedPlayableBounds(retaining:rim:step:)``.
    let bounds: WorldPoint

    /// Default proof map — `WorldMapID.riverlands`.
    static func proofMap(seed: UInt64) -> WorldMap {
        map(.riverlands, seed: seed)
    }

    static func map(_ id: WorldMapID, seed: UInt64) -> WorldMap {
        switch id {
        case .riverlands: riverlands(seed: seed)
        case .basin: basin(seed: seed)
        case .fjords: fjords(seed: seed)
        }
    }

    // MARK: - Water authoring

    /// A channel laid along the territory boundary between two plates.
    ///
    /// Authoring rivers in absolute coordinates does not survive contact with a
    /// packed layout: a channel guessed onto the map cuts a corner off whichever
    /// plate it happens to clip, and that plate's land is then in two pieces with
    /// a rule saying both halves are the same region. A unit ordered across ends
    /// up walking on water or teleporting.
    ///
    /// Running the water down the *boundary* removes the whole class of problem.
    /// `region(at:)` picks the nearest centre relative to plate size, so on the
    /// line between two centres the boundary sits at `rA / (rA + rB)` — exactly
    /// where this puts the channel's spine. Neither plate is cut; the water
    /// separates them, which is what a river between two territories is for.
    /// - Parameters:
    ///   - inland: how far past the boundary the channel reaches into the
    ///     interior, where it tapers out.
    ///   - seaward: how far it runs the other way, into the outer void.
    ///   - head: half-width at the inland tip.
    ///   - mouth: half-width where it opens into the void.
    ///   - bow: sideways bend at mid-run, so the channel is not a ruled line.
    ///   - meander: amplitude of a second, faster sway laid over `bow`. One bend is
    ///     a curved line; it takes at least two to read as a river, because what the
    ///     eye is looking for is a course that changes its mind.
    ///   - meanderTurns: how many full sways `meander` makes over the run.
    private static func strait(
        between a: Fragment,
        and b: Fragment,
        head: Float,
        mouth: Float,
        inland: Float,
        seaward: Float,
        bow: Float = 0,
        meander: Float = 0,
        meanderTurns: Float = 1.5,
        wander: Float = 2.6,
        wanderScale: Float = 19,
        salt: UInt32
    ) -> VoidBody {
        let span = b.center - a.center
        let length = simd_length(span)
        let axis = length > 0.0001 ? span / length : WorldPoint(1, 0)
        let across = WorldPoint(-axis.y, axis.x)
        let spine = a.center + axis * (length * a.radius / max(a.radius + b.radius, 0.001))

        // Run the channel *outward* from the boundary, and let it die inland.
        //
        // A channel laid symmetrically along the boundary keeps going once it has
        // done its job and ploughs into whatever is on the other side of the map —
        // on the first cut of these layouts the home/expansion strait carried on
        // through the Dominion and out the far side, leaving the contested plate
        // in three pieces. Water that widens toward the void and tapers to nothing
        // inland is also simply what a river mouth looks like.
        let outward: WorldPoint = {
            let reference = simd_length(spine) > 0.0001 ? spine / simd_length(spine) : axis
            return simd_dot(across, reference) >= 0 ? across : -across
        }()

        let steps = 16
        var path: [WorldPoint] = []
        var widths: [Float] = []
        for step in 0...steps {
            let t = Float(step) / Float(steps)                  // 0 inland … 1 seaward
            let distance = -inland + (inland + seaward) * t
            let bend = axis * (bow * sin(t * .pi) + meander * sin(t * 2 * .pi * meanderTurns))
            path.append(spine + outward * distance + bend)
            widths.append(head + (mouth - head) * t * t)
        }
        return VoidBody.channel(
            path,
            halfWidths: widths,
            wander: wander,
            wanderScale: wanderScale,
            salt: salt
        )
    }

    /// A channel following a plate's own coastline, just off it.
    ///
    /// This is how a river forks: two arcs bowing opposite ways around the same
    /// plate leave it as an island in midstream. Because the path is taken from
    /// the plate's authored outline rather than from a circle, the water keeps a
    /// constant clearance from the shore instead of pinching where the coast
    /// bulges.
    ///
    /// A full ring is only half-turn symmetric if the plate it follows is, which
    /// is why every origin plate here is authored with even harmonics only.
    /// - Parameters:
    ///   - flow: bearing the river runs along. The channel pinches at the island's
    ///     upstream and downstream tips and swells on its flanks, which is what a
    ///     river splitting around an island does. A constant width instead draws a
    ///     perfect black annulus, which is what the first cut of `riverlands`
    ///     rendered and it read as a moat someone had dug, not as water finding a
    ///     way round.
    ///   - swell: how much of the half-width that redistribution moves, 0 ... 1.
    private static func moat(
        around plate: Fragment,
        clearance: Float,
        halfWidth: Float,
        flow: Float = 0,
        swell: Float = 0,
        wander: Float = 2.4,
        wanderScale: Float = 17,
        salt: UInt32
    ) -> VoidBody {
        let steps = 40
        var path: [WorldPoint] = []
        var widths: [Float] = []
        for step in 0...steps {
            let bearing = Float(step) / Float(steps) * 2 * .pi
            let reach = plate.radius(atBearing: bearing) + clearance
            path.append(plate.center + WorldPoint(cos(bearing), sin(bearing)) * reach)
            // Even harmonic only — an odd one here would make the two banks
            // different widths and quietly unfair.
            widths.append(halfWidth * (1 - swell * cos(2 * (bearing - flow))))
        }
        return VoidBody.channel(
            path,
            halfWidths: widths,
            wander: wander,
            wanderScale: wanderScale,
            salt: salt
        )
    }

    // MARK: - Layouts

    /// **Riverlands.** A broad continent carrying a great void river system.
    ///
    /// Two rivers reach in from opposite outer edges along the seam between each
    /// home and its expansion, each dying short of the middle so home plateaus
    /// stay open for fights. What they leave between them is the Dominion: a neck
    /// of land with water on both flanks, which is the one place an army can cross
    /// the map on foot. Two tarns sit toward the outer flanks — not inland of the
    /// Core fight grounds.
    ///
    /// An earlier cut ran the water all the way round the Dominion, making it an
    /// island in midstream. It was the better story and the worse picture — a
    /// closed ring of void around a central plate reads as a moat someone dug, not
    /// as a river, and no amount of width variation along it fixed that.
    private static func riverlands(seed: UInt64) -> WorldMap {
        // Fray is deliberately low on all three maps now. Roughening each plate's
        // own outline puts a different grain on either side of every seam, and the
        // kink where two of them meet is a tell that the coast is made of discs.
        // `LandErosion` does that job once, for the whole landmass. What is left
        // here is the plate's *character* — which way it is stretched, where its
        // capes are — and nothing else.
        //
        // Lobe amplitudes stay modest: deep scallops empty the playable AABB's
        // corners and were a large part of land covering only ~40% of the map.
        let homeCoast = CoastProfile(
            lobes: [.init(2, 0.10, 0.40), .init(3, 0.06, 2.10), .init(5, 0.03, 0.90)],
            fray: 0.01, frayScale: 24, salt: LandNoise.salt(0x51ED_2C17, seed: seed)
        )
        let expansionCoast = CoastProfile(
            lobes: [.init(2, 0.09, 1.80), .init(3, 0.06, 0.50), .init(5, 0.03, 2.40)],
            fray: 0.01, frayScale: 20, salt: LandNoise.salt(0x1A77_C3B9, seed: seed)
        )
        let outcropCoast = CoastProfile(
            lobes: [.init(2, 0.10, 1.10), .init(3, 0.07, 2.70)],
            fray: 0.012, frayScale: 15, salt: LandNoise.salt(0x66C1_20D3, seed: seed)
        )

        // Homes sit nearly east/west on the fairness ring so the continent fills
        // an axis-aligned theatre. Expansions take north/south; outcrops pin the
        // remaining corners. Radii are sized so the union reads as a rounded
        // rectangle (AoE land band) rather than a diagonal blob in a square.
        let plates = [
            Fragment(id: .sunwovenHome, center: core(bearing: 188, reach: 44), radius: 58, depth: 30, coast: homeCoast),
            Fragment(id: .gravemarkHome, center: core(bearing: 8, reach: 44), radius: 56, depth: 30, coast: homeCoast.halfTurned),
            Fragment(id: .dominion, center: [0, 0], radius: 52, depth: 22,
                     coast: CoastProfile(lobes: [.init(2, 0.07, 1.55), .init(3, 0.04, 0.40)], fray: 0.01, frayScale: 14, salt: LandNoise.salt(0x2B84_9E11, seed: seed))),
            Fragment(id: .sunwovenExpansion, center: [-8, 46], radius: 54, depth: 22, coast: expansionCoast),
            Fragment(id: .gravemarkExpansion, center: [12, -44], radius: 52, depth: 22, coast: expansionCoast.halfTurned),
            Fragment(id: .neutralOutcropNorth, center: [50, 44], radius: 46, depth: 18, coast: outcropCoast),
            Fragment(id: .neutralOutcropSouth, center: [-48, -42], radius: 48, depth: 18, coast: outcropCoast.halfTurned),
        ]
        let plate = table(plates)

        // Rivers on the home→expansion seams. Inland reach is kept short so each
        // home plateau keeps a contiguous fight ground near the Core; the
        // Dominion neck remains the dry crossing. One inland tarn (not three)
        // marks water without peppering the field with pocket voids.
        let sunRiver = strait(
            between: plate[.sunwovenHome]!, and: plate[.sunwovenExpansion]!,
            head: 2.6, mouth: 6.0, inland: 10, seaward: 40, bow: -5, meander: 3.0,
            wander: 1.4, wanderScale: 28, salt: LandNoise.salt(0x7A3C_11E5, seed: seed)
        )
        let graveRiver = strait(
            between: plate[.gravemarkHome]!, and: plate[.gravemarkExpansion]!,
            head: 2.8, mouth: 4.8, inland: 9, seaward: 36, bow: 4, meander: 1.8, meanderTurns: 2.0,
            wander: 1.5, wanderScale: 22, salt: LandNoise.salt(0x35C8_02BF, seed: seed)
        )
        let tarn = VoidBody.basin(
            at: [-42, 30], radius: 4.5,
            outline: CoastProfile(lobes: [.init(2, 0.18, 1.10), .init(3, 0.08, 2.40)], fray: 0.06, frayScale: 9, salt: LandNoise.salt(0x4A11_9C05, seed: seed)),
            wander: 0.9, wanderScale: 11, salt: LandNoise.salt(0x9B27_D410, seed: seed)
        )
        let pool = VoidBody.basin(
            at: [40, -18], radius: 5.0,
            outline: CoastProfile(lobes: [.init(2, 0.20, 2.70), .init(3, 0.08, 0.80)], fray: 0.06, frayScale: 8, salt: LandNoise.salt(0x2D5F_8B41, seed: seed)),
            wander: 0.9, wanderScale: 13, salt: LandNoise.salt(0x2E74_C1B8, seed: seed)
        )

        return assemble(
            id: .riverlands,
            seed: seed,
            authored: plates,
            water: [sunRiver, graveRiver, tarn, pool],
            erosion: LandErosion(amplitude: 2.6, scale: 44, octaves: 2, bias: 16.5, salt: LandNoise.salt(0x6D2B_79F5, seed: seed))
        )
    }

    /// **Basin.** Lake country: two great void basins either side of the Dominion.
    ///
    /// One lake on the origin is the shape this map wants and the one shape it
    /// cannot have — the fairness contract pins the Dominion there, and a basin
    /// centred on it leaves nothing to fight over. A mirrored pair keeps the read
    /// and the contract, and gives the Dominion a shoreline on both sides. Each
    /// lake reaches out along the seam between a home and its expansion, so every
    /// crossing on this map is a lake crossing.
    private static func basin(seed: UInt64) -> WorldMap {
        let homeCoast = CoastProfile(
            lobes: [.init(2, 0.10, 1.70), .init(3, 0.06, 0.40), .init(4, 0.04, 2.10)],
            fray: 0.01, frayScale: 23, salt: LandNoise.salt(0x40B2_7CD5, seed: seed)
        )
        let expansionCoast = CoastProfile(
            lobes: [.init(2, 0.09, 0.30), .init(3, 0.06, 1.50), .init(5, 0.03, 2.70)],
            fray: 0.01, frayScale: 19, salt: LandNoise.salt(0x77E3_1109, seed: seed)
        )
        let outcropCoast = CoastProfile(
            lobes: [.init(2, 0.10, 2.20), .init(3, 0.07, 0.70)],
            fray: 0.012, frayScale: 15, salt: LandNoise.salt(0x0CD9_5EA7, seed: seed)
        )

        // Same rectangular packing as riverlands, rotated bearings so the three
        // maps do not share one silhouette. Lakes sit inland of the fill.
        let plates = [
            Fragment(id: .sunwovenHome, center: core(bearing: 200, reach: 46), radius: 58, depth: 29, coast: homeCoast),
            Fragment(id: .gravemarkHome, center: core(bearing: 20, reach: 46), radius: 55, depth: 29, coast: homeCoast.halfTurned),
            Fragment(id: .dominion, center: [0, 0], radius: 50, depth: 22,
                     coast: CoastProfile(lobes: [.init(2, 0.05, 0.20), .init(3, 0.03, 2.10)], fray: 0.01, frayScale: 17, salt: LandNoise.salt(0x11C4_6BE8, seed: seed))),
            Fragment(id: .sunwovenExpansion, center: [-8, 48], radius: 54, depth: 22, coast: expansionCoast),
            Fragment(id: .gravemarkExpansion, center: [10, -46], radius: 56, depth: 22, coast: expansionCoast.halfTurned),
            Fragment(id: .neutralOutcropNorth, center: [48, 46], radius: 46, depth: 18, coast: outcropCoast),
            Fragment(id: .neutralOutcropSouth, center: [-46, -44], radius: 48, depth: 18, coast: outcropCoast.halfTurned),
        ]
        let plate = table(plates)

        let greatLake = VoidBody.basin(
            at: [-32, 12], radius: 9.0,
            outline: CoastProfile(
                lobes: [.init(2, 0.20, 0.65), .init(3, 0.10, 2.30), .init(5, 0.05, 1.10)],
                fray: 0.05, frayScale: 13, salt: LandNoise.salt(0x5C90_2E37, seed: seed)
            ),
            wander: 1.2, wanderScale: 22, salt: LandNoise.salt(0x6E22_A18D, seed: seed)
        )
        let farLake = VoidBody.basin(
            at: [30, -10], radius: 7.5,
            outline: CoastProfile(
                lobes: [.init(2, 0.22, 2.05), .init(3, 0.09, 0.70), .init(4, 0.06, 2.60)],
                fray: 0.06, frayScale: 11, salt: LandNoise.salt(0xA6F4_1D82, seed: seed)
            ),
            wander: 1.2, wanderScale: 19, salt: LandNoise.salt(0x0E83_66C1, seed: seed)
        )
        // Arms stay seaward-biased — short inland so home plateaus are not
        // sliced into fight corridors between lake and channel.
        let sunArm = strait(
            between: plate[.sunwovenHome]!, and: plate[.sunwovenExpansion]!,
            head: 3.2, mouth: 7.0, inland: 6, seaward: 36, bow: 5, meander: 2.6,
            wander: 1.4, wanderScale: 28, salt: LandNoise.salt(0x18AF_3C60, seed: seed)
        )
        let graveArm = strait(
            between: plate[.gravemarkHome]!, and: plate[.gravemarkExpansion]!,
            head: 3.0, mouth: 7.2, inland: 7, seaward: 34, bow: -6, meander: 2.0, meanderTurns: 2.0,
            wander: 1.4, wanderScale: 24, salt: LandNoise.salt(0x93D7_5A04, seed: seed)
        )

        return assemble(
            id: .basin,
            seed: seed,
            authored: plates,
            water: [greatLake, farLake, sunArm, graveArm],
            erosion: LandErosion(amplitude: 2.2, scale: 40, octaves: 2, bias: 16.8, salt: LandNoise.salt(0x3F19_C24B, seed: seed))
        )
    }

    /// **Fjords.** A ragged coast bitten into by long void sounds.
    ///
    /// Nothing here is a lake: every piece of water opens onto the outer void, so
    /// the read is all headland and sound. The plates carry the strongest coast
    /// profiles of the three and the sounds run narrow and deep, which makes this
    /// the most irregular silhouette — and the most defensible interior.
    private static func fjords(seed: UInt64) -> WorldMap {
        let homeCoast = CoastProfile(
            lobes: [.init(2, 0.10, 0.70), .init(3, 0.06, 2.40), .init(5, 0.03, 1.20)],
            fray: 0.01, frayScale: 19, salt: LandNoise.salt(0x2C6D_B913, seed: seed)
        )
        let expansionCoast = CoastProfile(
            lobes: [.init(2, 0.09, 2.00), .init(3, 0.06, 0.80), .init(5, 0.03, 2.60)],
            fray: 0.01, frayScale: 17, salt: LandNoise.salt(0x69F0_44C2, seed: seed)
        )
        let outcropCoast = CoastProfile(
            lobes: [.init(2, 0.10, 0.50), .init(3, 0.06, 1.80)],
            fray: 0.012, frayScale: 13, salt: LandNoise.salt(0x3E51_A8D6, seed: seed)
        )

        let plates = [
            Fragment(id: .sunwovenHome, center: core(bearing: 170, reach: 45), radius: 56, depth: 28, coast: homeCoast),
            Fragment(id: .gravemarkHome, center: core(bearing: -10, reach: 45), radius: 54, depth: 28, coast: homeCoast.halfTurned),
            Fragment(id: .dominion, center: [0, 0], radius: 50, depth: 22,
                     coast: CoastProfile(lobes: [.init(2, 0.05, 1.20), .init(3, 0.03, 0.30), .init(5, 0.02, 2.40)], fray: 0.01, frayScale: 15, salt: LandNoise.salt(0x59A2_D704, seed: seed))),
            Fragment(id: .sunwovenExpansion, center: [-14, -44], radius: 54, depth: 22, coast: expansionCoast),
            Fragment(id: .gravemarkExpansion, center: [16, 46], radius: 52, depth: 22, coast: expansionCoast.halfTurned),
            Fragment(id: .neutralOutcropNorth, center: [48, 48], radius: 46, depth: 18, coast: outcropCoast),
            Fragment(id: .neutralOutcropSouth, center: [-46, -46], radius: 48, depth: 18, coast: outcropCoast.halfTurned),
        ]
        let plate = table(plates)

        // Two primary sounds keep the fjord read; a third inland bite was
        // carving the Dominion approaches into peninsula corridors.
        let sunSound = strait(
            between: plate[.sunwovenHome]!, and: plate[.sunwovenExpansion]!,
            head: 2.4, mouth: 5.6, inland: 14, seaward: 40, bow: -6, meander: 2.4,
            wander: 1.1, wanderScale: 24, salt: LandNoise.salt(0x4477_1BE9, seed: seed)
        )
        let graveSound = strait(
            between: plate[.gravemarkHome]!, and: plate[.gravemarkExpansion]!,
            head: 2.5, mouth: 4.8, inland: 10, seaward: 34, bow: 5, meander: 1.8, meanderTurns: 1.0,
            wander: 1.2, wanderScale: 20, salt: LandNoise.salt(0xE60B_9317, seed: seed)
        )
        let outerBite = strait(
            between: plate[.sunwovenHome]!, and: plate[.neutralOutcropNorth]!,
            head: 1.6, mouth: 4.0, inland: 8, seaward: 24, bow: -4, meander: 1.8,
            wander: 0.9, wanderScale: 16, salt: LandNoise.salt(0x1D93_7F42, seed: seed)
        )

        return assemble(
            id: .fjords,
            seed: seed,
            authored: plates,
            water: [sunSound, graveSound, outerBite],
            erosion: LandErosion(amplitude: 3.2, scale: 32, octaves: 2, bias: 16.0, salt: LandNoise.salt(0x8C51_06AD, seed: seed))
        )
    }
    /// Where a home plate's centre goes, given a bearing.
    ///
    /// **The whole of this game's map fairness is this one function** (user
    /// direction, 2026-07-28): the two Cores must be the same distance from the
    /// Dominion, and nothing else has to match. Everything the older layouts held
    /// symmetric — plate sizes, expansion and outcrop placement, coastlines, where
    /// the rivers run — is now free to differ side to side, which is what lets
    /// these read as places rather than as a shape and its reflection.
    ///
    /// Placing both homes off one shared radius makes the rule structural. Typed
    /// as two coordinate pairs it is an invariant that holds by arithmetic nobody
    /// re-checks, and the failure — one player a few metres closer to the contested
    /// middle for the whole match — is invisible on screen.
    private static func core(bearing degrees: Float, reach: Float = 46.8) -> WorldPoint {
        let radians = degrees * .pi / 180
        return WorldPoint(cos(radians), sin(radians)) * reach
    }

    private static func table(_ plates: [Fragment]) -> [RegionID: Fragment] {
        var table: [RegionID: Fragment] = [:]
        for plate in plates { table[plate.id] = plate }
        return table
    }
    private static func assemble(
        id: WorldMapID,
        seed: UInt64,
        authored: [Fragment],
        water: [VoidBody],
        erosion: LandErosion
    ) -> WorldMap {
        let table = table(authored)

        // First pass: a generous camera box so a coarse land sample cannot clip
        // headlands. Bounds are then tightened to the measured land envelope —
        // authoring from plate reach + a large erosion pad left a ring of outer
        // void that kept land coverage near 40–50% of the playable map.
        var extent = WorldPoint.zero
        for fragment in authored {
            let reach = fragment.maxReach
            extent.x = max(extent.x, abs(fragment.center.x) + reach)
            extent.y = max(extent.y, abs(fragment.center.y) + reach)
        }
        extent += WorldPoint(repeating: max(erosion.bias + erosion.amplitude, 0) + 4)

        let draft = WorldMap(
            id: id,
            seed: seed,
            fragments: table,
            voidBodies: water,
            erosion: erosion,
            voidLanes: [],
            causeways: [],
            bounds: extent
        )
        // Fit the camera box so land fills 75–80% of it: shrink the land AABB
        // just enough to drop the empty corners while retaining most land cells.
        // Slightly larger rim than CP-14's 1.008: sparse inland water raised land
        // fraction; the extra void margin keeps the camera band in 75–80%.
        let bounds = draft.fittedPlayableBounds(retaining: 0.975, rim: 1.014, step: 2.5)

        // Transports own the first home→expansion crossing. On these maps that
        // is a river or a lake the player can see, not an abstract rule.
        let lanes: [VoidLane] = [
            VoidLane(from: .sunwovenHome, to: .sunwovenExpansion),
            VoidLane(from: .sunwovenHome, to: .neutralOutcropNorth),
            VoidLane(from: .gravemarkHome, to: .gravemarkExpansion),
            VoidLane(from: .gravemarkHome, to: .neutralOutcropSouth),
            VoidLane(from: .sunwovenExpansion, to: .dominion),
            VoidLane(from: .gravemarkExpansion, to: .dominion),
        ]

        let ways: [Causeway] = [
            Causeway(from: .sunwovenExpansion, to: .dominion, wovenByOutpostOf: nil),
            Causeway(from: .gravemarkExpansion, to: .dominion, wovenByOutpostOf: nil),
            Causeway(from: .sunwovenHome, to: .sunwovenExpansion, wovenByOutpostOf: .sunwoven),
            Causeway(from: .gravemarkHome, to: .gravemarkExpansion, wovenByOutpostOf: .gravemark),
        ]

        return WorldMap(
            id: id,
            seed: seed,
            fragments: table,
            voidBodies: water,
            erosion: erosion,
            voidLanes: lanes,
            causeways: ways,
            bounds: bounds
        )
    }

    func fragment(_ id: RegionID) -> Fragment {
        // Every RegionID is authored above; a miss is a programming error, not
        // a runtime condition to absorb silently.
        guard let fragment = fragments[id] else {
            preconditionFailure("WorldMap is missing authored fragment \(id.rawValue)")
        }
        return fragment
    }

    // MARK: - Land

    /// Metres of void water at `point` — positive in water, negative on dry land.
    /// Zero is the bank.
    func waterDepth(at point: WorldPoint) -> Float {
        var deepest = -Float.greatestFiniteMagnitude
        for body in voidBodies {
            deepest = max(deepest, body.depth(at: point))
        }
        return voidBodies.isEmpty ? -Float.greatestFiniteMagnitude : deepest
    }

    /// True where a void river, lake or inlet has taken the ground away.
    func isSubmerged(_ point: WorldPoint) -> Bool {
        for body in voidBodies where body.depth(at: point) > 0 { return true }
        return false
    }

    /// The signed land field: metres of dry ground at `point`, negative in void,
    /// zero at the shore.
    ///
    /// **This is the map's definition of land**, and everything else — the legality
    /// tests, the carved mesh, the bank walls, the minimap contour — is a reading of
    /// it. Three terms, in order of how much they matter:
    ///
    /// 1. The deepest plate. `reach - distance` is positive inside a plate's
    ///    authored outline, so the max over plates is the union of them.
    /// 2. ``erosion``, added to that union. Because the field is signed, adding to
    ///    it moves the *shoreline* rather than any particular plate's outline —
    ///    which is what makes seven overlapping plates stop reading as seven
    ///    overlapping circles. See ``LandErosion``.
    /// 3. Water, which wins outright: `-waterDepth` is negative wherever a river
    ///    or lake stands, and taking the min subtracts it from the land.
    ///
    /// Costs three noise evaluations and seven radial profiles, and is called per
    /// grid cell by the mesh factory and per step by the movement clamp. That is
    /// affordable at this map size and is the price of having exactly one answer to
    /// "is this land" in the whole engine.
    func landField(at point: WorldPoint) -> Float {
        var ground = -Float.greatestFiniteMagnitude
        for id in RegionID.allCases {
            let fragment = fragment(id)
            let offset = point - fragment.center
            let reach = fragment.radius(atBearing: Fragment.bearing(of: offset))
            ground = max(ground, reach - simd_length(offset))
        }
        // `waterDepth` is `-greatestFiniteMagnitude` on a map with no water, so
        // negating it leaves the min a no-op rather than a special case.
        return min(ground + erosion.displacement(at: point), -waterDepth(at: point))
    }

    /// True when `point` lies on solid land **owned by** `id`.
    ///
    /// Ownership is exclusive: where plates overlap exactly one of them contains a
    /// point, the one whose own outline it sits deepest inside. Letting both claim
    /// it was harmless when a plate was a disc and became a bug once erosion could
    /// hand a plate ground outside its nominal reach.
    func contains(_ point: WorldPoint, in id: RegionID) -> Bool {
        region(at: point) == id
    }

    /// The region containing `point`, if any. Void otherwise.
    ///
    /// Whether it is land at all is ``landField(at:)``'s answer, not this one's.
    /// This only decides *whose* it is, and the nearer centre wins *relative to its
    /// own size*, so boundaries fall midway between neighbours instead of at
    /// whichever region happens to come first in `RegionID.allCases`. A big home
    /// plate does not swallow a small outcrop it merely reaches over.
    ///
    /// Note there is no `distance <= reach` gate: erosion can push the coast a few
    /// metres past every plate's nominal outline, and that ground is real, walkable
    /// and has to belong to somebody. Gating here would have left a fringe of land
    /// the mesh draws and no unit may stand on.
    func region(at point: WorldPoint) -> RegionID? {
        guard landField(at: point) > 0 else { return nil }
        var best: RegionID?
        var bestScore = Float.greatestFiniteMagnitude
        for id in RegionID.allCases {
            let fragment = fragment(id)
            let offset = point - fragment.center
            let reach = fragment.radius(atBearing: Fragment.bearing(of: offset))
            let score = simd_length(offset) / max(reach, 0.001)
            if score < bestScore {
                bestScore = score
                best = id
            }
        }
        return best
    }

    /// True anywhere a land unit could legally stand.
    func isLand(_ point: WorldPoint) -> Bool {
        landField(at: point) > 0
    }

    /// Fraction of the playable rectangle (``bounds``) that is dry land.
    ///
    /// This is the coverage the layouts are tuned against: land should fill most
    /// of the camera map, with rivers/lakes/inlets remaining as readable void
    /// cuts rather than dominating the frame. Sampled on a uniform grid.
    func landCoverage(step: Float = 1.0) -> Float {
        precondition(step > 0)
        var land = 0
        var total = 0
        var y = -bounds.y
        while y <= bounds.y {
            var x = -bounds.x
            while x <= bounds.x {
                total += 1
                if isLand(WorldPoint(x, y)) { land += 1 }
                x += step
            }
            y += step
        }
        guard total > 0 else { return 0 }
        return Float(land) / Float(total)
    }

    /// Half-extent of an axis-aligned box that just covers dry land (plus a thin
    /// void margin). Used by the offline harness so coverage can also be reported
    /// against the land envelope rather than the wider camera ``bounds``.
    func landEnvelope(step: Float = 1.5, margin: Float = 1.04) -> WorldPoint {
        var extent = WorldPoint.zero
        var y = -bounds.y
        while y <= bounds.y {
            var x = -bounds.x
            while x <= bounds.x {
                if isLand(WorldPoint(x, y)) {
                    extent.x = max(extent.x, abs(x))
                    extent.y = max(extent.y, abs(y))
                }
                x += step
            }
            y += step
        }
        return extent * margin
    }

    /// Playable camera half-extent fitted so land covers most of the rectangle.
    ///
    /// A raw land AABB always wastes its corners on void — a circular continent
    /// can never beat π/4 ≈ 78% of its own box, and an irregular coast sits lower.
    /// Shrinking that box just enough to still keep `retaining` of the land cells
    /// (the soft tips that only touch the AABB corners) is what lets the layouts
    /// sit in the 75–80% land band without erasing rivers or lakes.
    func fittedPlayableBounds(
        retaining: Float = 0.98,
        rim: Float = 1.01,
        step: Float = 2.5
    ) -> WorldPoint {
        let envelope = landEnvelope(step: step, margin: 1.0)
        guard envelope.x > 0, envelope.y > 0 else { return bounds }

        var landPoints: [WorldPoint] = []
        var y = -bounds.y
        while y <= bounds.y {
            var x = -bounds.x
            while x <= bounds.x {
                let point = WorldPoint(x, y)
                if isLand(point) { landPoints.append(point) }
                x += step
            }
            y += step
        }
        let total = landPoints.count
        guard total > 0 else { return envelope * rim }

        var low: Float = 0.75
        var high: Float = 1.0
        for _ in 0..<18 {
            let mid = (low + high) * 0.5
            let kept = landPoints.reduce(into: 0) { count, point in
                if abs(point.x) <= envelope.x * mid, abs(point.y) <= envelope.y * mid {
                    count += 1
                }
            }
            if Float(kept) / Float(total) >= retaining { high = mid } else { low = mid }
        }
        return envelope * high * rim
    }

    /// Land fraction inside ``envelope`` — typically the land's own AABB — so the
    /// harness can separate "how much of the camera map is land" from "how solid
    /// is the continent silhouette".
    func landCoverage(within envelope: WorldPoint, step: Float = 1.0) -> Float {
        precondition(step > 0)
        precondition(envelope.x > 0 && envelope.y > 0)
        var land = 0
        var total = 0
        var y = -envelope.y
        while y <= envelope.y {
            var x = -envelope.x
            while x <= envelope.x {
                total += 1
                if isLand(WorldPoint(x, y)) { land += 1 }
                x += step
            }
            y += step
        }
        guard total > 0 else { return 0 }
        return Float(land) / Float(total)
    }

    /// Edge-to-edge gap between two fragments' nominal discs. Negative means the
    /// plates overlap. Water is not considered — this is a packing measure.
    func gap(between a: RegionID, and b: RegionID) -> Float {
        let left = fragment(a), right = fragment(b)
        return simd_distance(left.center, right.center) - (left.radius + right.radius)
    }

    /// True when the seven plates form one connected component under overlap
    /// (gap ≤ 0 counts as an edge), before water is carved out.
    var isContiguousLandmass: Bool {
        var visited: Set<RegionID> = []
        var queue: [RegionID] = [.sunwovenHome]
        visited.insert(.sunwovenHome)
        while let current = queue.first {
            queue.removeFirst()
            for other in RegionID.allCases where !visited.contains(other) {
                if gap(between: current, and: other) <= 0 {
                    visited.insert(other)
                    queue.append(other)
                }
            }
        }
        return visited.count == RegionID.allCases.count
    }

    // MARK: - Crossings

    /// The first void point on the way from `id` toward `target`, and the last
    /// land point before it.
    ///
    /// Marching outward from the centre replaces CP-13's angular sweep around the
    /// rim. The sweep assumed the only void was *outside* the plate, which stops
    /// being true the moment a river runs past one: it would happily pick a berth
    /// on the far shore. Walking the line the crossing actually takes finds the
    /// near bank of whatever water is in the way, which is where a hull belongs.
    private func crossing(from id: RegionID, toward target: RegionID) -> (shore: WorldPoint, water: WorldPoint) {
        let source = fragment(id)
        let destination = fragment(target)
        var heading = destination.center - source.center
        let length = simd_length(heading)
        heading = length > 0.0001 ? heading / length : WorldPoint(1, 0)

        let step: Float = 0.75
        let limit = simd_length(bounds) + source.radius
        var lastLand = source.center
        var travelled: Float = 0

        while travelled < limit {
            let point = source.center + heading * travelled
            if contains(point, in: id) {
                lastLand = point
            } else if region(at: point) == nil {
                // Push on across the water so the hull berths mid-channel rather
                // than nosing the bank it just left.
                var berth = point
                var probe = travelled
                while probe < travelled + 9 {
                    probe += step
                    let ahead = source.center + heading * probe
                    guard region(at: ahead) == nil else { break }
                    berth = ahead
                }
                return (lastLand, (point + berth) * 0.5)
            }
            travelled += step
        }
        // No water on the line at all: berth just past the authored outline.
        let bearing = Fragment.bearing(of: heading)
        let escape = source.center + heading * (source.radius(atBearing: bearing) + 4)
        return (lastLand, escape)
    }

    /// A land-side staging point on `id`'s shore, facing the crossing to `target`.
    func stagingPoint(on id: RegionID, facing target: RegionID) -> WorldPoint {
        let source = fragment(id)
        let shore = crossing(from: id, toward: target).shore
        var back = source.center - shore
        let length = simd_length(back)
        guard length > 0.0001 else { return source.center }
        back /= length
        // Step back off the waterline so a boarding unit stands on ground, not
        // on the last texel of it.
        var point = shore + back * 2.5
        var attempts = 0
        while !contains(point, in: id), attempts < 12 {
            point += back * 1.5
            attempts += 1
        }
        return contains(point, in: id) ? point : source.center
    }

    /// Where the hull waits: in the water on `id`'s side of the crossing.
    func dockPoint(on id: RegionID, facing target: RegionID) -> WorldPoint {
        crossing(from: id, toward: target).water
    }

    // MARK: - Legality

    /// The nearest point to `proposed` that a land unit in `region` may occupy,
    /// approached from `from`.
    ///
    /// Walking back along the attempted move rather than projecting toward the
    /// plate centre. Projection was fine for a disc, but with water in play it
    /// can jump a unit clean across a river: the point "radius − margin from the
    /// centre" may be on the far bank, or in the channel. Retreating along the
    /// segment can only ever land somewhere the unit could have walked.
    func clampToLand(
        _ proposed: WorldPoint,
        from: WorldPoint,
        in region: RegionID,
        margin: Float
    ) -> WorldPoint {
        if isStandable(proposed, in: region, margin: margin) { return proposed }

        // Binary search the segment for the last standable point. Eight halvings
        // resolve a 40 m order to under 20 cm, well inside `arrivalRadius`.
        var good = from
        var bad = proposed
        guard isStandable(good, in: region, margin: margin) else { return from }
        for _ in 0..<8 {
            let middle = (good + bad) * 0.5
            if isStandable(middle, in: region, margin: margin) { good = middle } else { bad = middle }
        }
        return good
    }

    /// Whether a unit of `margin` footprint fits at `point` inside `region`.
    ///
    /// The footprint is checked against the *water*, not against the outline: a
    /// citizen may stand on the very lip of the outer coast, which is where the
    /// dock and the shore band are, but must not have their feet in a river.
    func isStandable(_ point: WorldPoint, in region: RegionID, margin: Float) -> Bool {
        guard contains(point, in: region) else { return false }
        guard margin > 0 else { return true }
        return waterDepth(at: point) < -margin
    }
}
