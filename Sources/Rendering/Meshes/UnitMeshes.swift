import Foundation
import RealityKit
import UIKit
import simd

/// Unit bodies, built as animatable rigs rather than single meshes.
///
/// Authored in the same faceted idiom as `FragmentMeshFactory` — flat-shaded
/// triangles, no unmodified primitives — but the reading job is different from a
/// building's. A building only has to be recognisable; a unit has to be *found*,
/// on a cream fragment, at the default 58 m zoom, in a tenth of a second. Three
/// things do that work here, and they are the three things the first render
/// lacked:
///
/// 1. **Value structure, top to bottom.** Bright hood, faction-coloured mantle,
///    light robe, faction-coloured skirt hem, dark boots. A unit that is one
///    value all the way down is a smudge; a unit that ramps from near-white at
///    the crown to near-black at the ground reads as a figure standing on
///    something. The dark base is what stops a citizen reading as a pebble.
/// 2. **Faction colour on an area the camera can actually see.** This camera
///    looks down at 57°, so a chest sash is nearly edge-on and a *shoulder
///    mantle* is nearly face-on. The mantle is therefore the primary team-colour
///    surface, and it is a flared ring — the same block of colour under any yaw.
///    The skirt hem repeats it for the side profile.
/// 3. **A contact patch.** Two flat unlit discs under the feet. Without them a
///    unit floats: the key light's cast shadow falls to one side and nothing
///    joins the body to the ground directly beneath it.
///
/// # World conventions
/// Metres, Y up. A unit's origin is at its feet (`y = 0`) and it faces −Z
/// (north) by default, matching `WorldMap`'s north-up contract and the zero yaw
/// of `LocomotionState.facing`.
///
/// # Scale
/// Heights here are *presentation* heights, not anatomical ones, and they are
/// deliberately heroic: a citizen is 2.40 m before `SkirmishTuning.unitVisualScale`
/// and 3.0 m after it. The visual bible fixes a citizen at a quarter to a third
/// of a building's height, and the Civilization Core is ~8 m tall and ~10 m
/// across — which at a 57° pitch presents ~12.7 m of screen height, not 8. The
/// earlier 1.80 m contract sat at a *ninth* of that presented mass and rendered
/// about forty pixels tall on an iPad Air; measured against concept 01, where a
/// citizen occupies nearly 6% of frame height, that was the single largest
/// readability failure in the frame. Proportions are heroic to match: roughly
/// five heads tall, wide shoulders, a robe that flares to the hem.
///
/// If a later change also raises `SkirmishTuning.unitVisualScale`, the two
/// multiply — re-measure before doing both.
///
/// # Rig contract
/// Every unit returns a root whose children carry these exact names:
///
/// ```
/// root                      origin at the feet, facing −Z
/// ├── "contact"             flat shadow pool; never posed
/// ├── "legL"                pivot at the hip; mesh hangs down to y = 0
/// ├── "legR"                mirrored across X
/// ├── "legLRear" (walker)   rear pair, same pivot rule
/// ├── "legRRear" (walker)
/// └── "torso"               pivot at the hip/waist; mesh rises from there
///     ├── "head"            hood or helm, with its own band and shadowed face
///     ├── "skirt"           faction-coloured lower robe
///     ├── "mantle"          faction-coloured shoulder ring
///     ├── "belt"            accent band at the waist
///     ├── "armL" / "armR"   pivot at the shoulder; mesh hangs down (bipeds)
///     └── equipment
/// ```
///
/// Each rigged part is placed so that rotating it about **its own local X axis**
/// swings it naturally from its joint. Because a positive rotation about +X
/// carries local −Z upward, a positive angle swings a hanging part (leg, arm)
/// forward, and leans a rising part (torso) backward. `LimbPose` already carries
/// the correct sign for every field, so the animator applies each angle as-is:
///
/// ```swift
/// let pose = locomotion.pose
/// unit.findEntity(named: UnitMeshes.Part.legL)?.orientation =
///     simd_quatf(angle: pose.legLeftPitch, axis: [1, 0, 0])
/// ```
///
/// `LimbPose.bob` is a rise in metres to add to the torso's authored local `y`;
/// read that rest value once from `torso.position.y` and offset from it, so the
/// feet stay planted on the ground. The contact pool is a child of the *root*,
/// not the torso, so it stays welded to the ground through the whole gait.
@MainActor
enum UnitMeshes {

    /// Rig part names. The single source of truth shared by this factory and
    /// whatever applies `LimbPose`, so neither side hard-codes a string.
    enum Part {
        static let torso = "torso"
        static let head = "head"
        static let legL = "legL"
        static let legR = "legR"
        static let legLRear = "legLRear"
        static let legRRear = "legRRear"
        static let armL = "armL"
        static let armR = "armR"
        /// The ground pool. Named so a presenter can dim or hide it (a unit on a
        /// transport deck has no ground beneath it) without guessing.
        static let contact = "contact"
    }

    // MARK: - Units

    /// The worker biped. Hooded robe with a flared hem, faction mantle over the
    /// shoulders, dark boots, and a long gather haft carried across the body.
    ///
    /// Its silhouette read is a **bell with a diagonal through it**: the widest
    /// hem of any unit, the roundest crown, and the only unit whose equipment
    /// crosses outside its own footprint. 2.40 m, ~200 triangles.
    static func citizen(faction: Faction, seed: UInt64) -> Entity {
        var random = DeterministicRandom.stream(seed: seed, tag: "unit.citizen.\(faction.rawValue)")
        let livery = Livery.of(faction)

        let spec = BipedSpec(
            qualifier: "citizen.\(faction.rawValue)",
            height: 2.40,
            crownHeight: 2.40,
            hipHeight: 0.92,
            hipSpread: 0.180,
            legWidth: 0.26,
            legDepth: 0.28,
            footDepth: 0.38,
            waistWidth: 0.46,
            shoulderWidth: 0.64,
            bodyDepth: 0.36,
            shoulderHeight: 1.04,
            hemDrop: 0.30,
            armLength: 0.62,
            armWidth: 0.155,
            mantleFlare: 1.40,
            contactRadius: 0.70
        )

        let biped = makeBiped(spec: spec, livery: livery, random: &random)

        // Gather haft, angled forward out of the working hand and long enough to
        // break the body's outline. The one piece of equipment a citizen carries,
        // and the thing that separates its silhouette from a soldier's at zoom.
        var haft = FlatMeshBuilder(uv: partUV)
        let reach = random.float(in: 0.54...0.64)
        addPrism(
            &haft,
            from: Section([0, -0.30, -reach], 0.060, 0.060),
            to: Section([0, 0.32, 0.18], 0.066, 0.066),
            capBottom: false,
            capTop: false
        )
        let tool = makePart(
            "tool",
            mesh: "\(spec.qualifier).tool",
            haft,
            accent(livery, roughness: 0.52)
        )
        tool.position = [0, -biped.spec.armLength * 0.88, 0.03]
        biped.armRight.addChild(tool)

        // A dark head on the haft: the tip is what the eye lands on, and gold on
        // gold has nothing to land on.
        var blade = FlatMeshBuilder(uv: partUV)
        addPyramid(
            &blade,
            base: Section([0, -0.28, -reach], 0.19, 0.16),
            apex: [0, -0.46, -reach - 0.13],
            capBase: true
        )
        tool.addChild(
            makePart("toolHead", mesh: "\(spec.qualifier).toolHead", blade, dark(livery, roughness: 0.86))
        )

        return biped.root
    }

    /// The scout. Slim, short tunic, a back rack carrying two swept faction
    /// vanes and a mast that tops the silhouette out with a luminous tip.
    ///
    /// Deliberately the inverse of the citizen in every readable axis: taller,
    /// narrower, no hem flare, mass carried *behind* rather than around, and the
    /// only unit whose highest point is a bright mote rather than cloth. From
    /// directly above, a citizen is a disc and a pathfinder is an arrowhead.
    /// 2.85 m to the mast tip, ~220 triangles.
    static func pathfinder(faction: Faction, seed: UInt64) -> Entity {
        var random = DeterministicRandom.stream(seed: seed, tag: "unit.pathfinder.\(faction.rawValue)")
        let livery = Livery.of(faction)

        let spec = BipedSpec(
            qualifier: "pathfinder.\(faction.rawValue)",
            height: 2.85,
            // The head sits low; the mast above it carries the height contract.
            crownHeight: 2.42,
            hipHeight: 1.06,
            hipSpread: 0.155,
            legWidth: 0.21,
            legDepth: 0.24,
            footDepth: 0.33,
            waistWidth: 0.38,
            shoulderWidth: 0.50,
            bodyDepth: 0.30,
            shoulderHeight: 0.98,
            hemDrop: 0.10,
            armLength: 0.62,
            armWidth: 0.125,
            mantleFlare: 1.14,
            contactRadius: 0.56
        )

        let biped = makeBiped(spec: spec, livery: livery, random: &random)
        let mastTop = spec.height - spec.hipHeight  // torso-local

        var pack = FlatMeshBuilder(uv: partUV)
        // Rack block riding high on the back.
        addPrism(
            &pack,
            from: Section([0, spec.shoulderHeight * 0.28, spec.bodyDepth * 0.54], spec.shoulderWidth * 0.74, 0.17),
            to: Section([0, spec.shoulderHeight * 0.94, spec.bodyDepth * 0.58], spec.shoulderWidth * 0.86, 0.20),
            capBottom: true,
            capTop: true
        )
        // Mast, rising past the head.
        addPrism(
            &pack,
            from: Section([0, spec.shoulderHeight * 0.92, spec.bodyDepth * 0.56], 0.075, 0.075),
            to: Section([0, mastTop - 0.16, spec.bodyDepth * 0.44], 0.055, 0.055),
            capBottom: false,
            capTop: false
        )
        let packPart = makePart(
            "pack",
            mesh: "\(spec.qualifier).pack",
            pack,
            plate(livery, roughness: 0.88)
        )
        biped.torso.addChild(packPart)

        // Swept vanes. Faction colour, near-horizontal, and wider than the body:
        // from the RTS camera this is the pathfinder's whole top-down identity.
        var vanes = FlatMeshBuilder(uv: partUV)
        for side in [Float(-1), Float(1)] {
            addQuad(
                &vanes,
                [side * spec.shoulderWidth * 0.40, spec.shoulderHeight * 0.90, spec.bodyDepth * 0.50],
                [side * spec.shoulderWidth * 1.16, spec.shoulderHeight * 0.74, spec.bodyDepth * 0.94],
                [side * spec.shoulderWidth * 1.12, spec.shoulderHeight * 0.44, spec.bodyDepth * 0.98],
                [side * spec.shoulderWidth * 0.38, spec.shoulderHeight * 0.52, spec.bodyDepth * 0.52],
                facing: [0, 1, 0]
            )
        }
        biped.torso.addChild(
            makePart("vanes", mesh: "\(spec.qualifier).vanes", vanes, team(livery, roughness: 0.86))
        )

        // Self-luminous sensor tip — the one place a scout is allowed to glow,
        // and the brightest single texel on any unit, so a scouting party is
        // findable in the void-dark half of the frame.
        var sensor = FlatMeshBuilder(uv: partUV)
        addPyramid(
            &sensor,
            base: Section([0, mastTop - 0.16, spec.bodyDepth * 0.44], 0.13, 0.13),
            apex: [0, mastTop, spec.bodyDepth * 0.44],
            capBase: true
        )
        let sensorPart = makePart(
            "sensor",
            mesh: "\(spec.qualifier).sensor",
            sensor,
            glow(livery.lume)
        )
        biped.torso.addChild(sensorPart)

        return biped.root
    }

    /// The melee line unit. Broadest shoulders, faction pauldrons, crested helm,
    /// shield and haft. Reads as a **wide rectangle** from above — the only
    /// unit whose shoulder span exceeds its hem. 2.80 m, ~250 triangles.
    static func vanguard(faction: Faction, seed: UInt64) -> Entity {
        var random = DeterministicRandom.stream(seed: seed, tag: "unit.vanguard.\(faction.rawValue)")
        let livery = Livery.of(faction)

        let spec = BipedSpec(
            qualifier: "vanguard.\(faction.rawValue)",
            height: 2.80,
            crownHeight: 2.80,
            hipHeight: 1.10,
            hipSpread: 0.220,
            legWidth: 0.30,
            legDepth: 0.33,
            footDepth: 0.44,
            waistWidth: 0.56,
            shoulderWidth: 0.86,
            bodyDepth: 0.44,
            shoulderHeight: 1.16,
            hemDrop: 0.30,
            armLength: 0.72,
            armWidth: 0.190,
            hasPauldrons: true,
            mantleFlare: 1.18,
            contactRadius: 0.88
        )

        let biped = makeBiped(spec: spec, livery: livery, random: &random)
        let head = biped.torso.findEntity(named: Part.head)

        // Helm crest — a single fin, read from the side and from above. Sits
        // inside the head's envelope, so the 2.80 m contract is unaffected.
        var crest = FlatMeshBuilder(uv: partUV)
        let headHeight = spec.crownHeight - spec.hipHeight - (spec.shoulderHeight - 0.04)
        let crestBase = headHeight - 0.20
        addQuad(
            &crest,
            [0, crestBase, -0.15],
            [0, crestBase, 0.15],
            [0, crestBase + 0.19, 0.10],
            [0, crestBase + 0.19, -0.10],
            facing: [1, 0, 0]
        )
        head?.addChild(
            makePart("crest", mesh: "\(spec.qualifier).crest", crest, accent(livery, roughness: 0.6))
        )

        // Shield on the guard arm, in faction colour: a soldier's team read is
        // the thing he holds up, not the thing he wears.
        var shield = FlatMeshBuilder(uv: partUV)
        let shieldZ: Float = -0.09
        addQuad(
            &shield,
            [-0.27, -0.34, shieldZ],
            [0.27, -0.34, shieldZ],
            [0.31, 0.36, shieldZ],
            [-0.31, 0.36, shieldZ],
            facing: [0, 0, -1]
        )
        let shieldPart = makePart(
            "shield",
            mesh: "\(spec.qualifier).shield",
            shield,
            team(livery, roughness: 0.78)
        )
        shieldPart.position = [-0.06, -spec.armLength * 0.72, -0.02]
        biped.armLeft.addChild(shieldPart)

        // Accent boss, so the shield is not one flat colour chip.
        var boss = FlatMeshBuilder(uv: partUV)
        addQuad(
            &boss,
            [-0.12, -0.07, shieldZ - 0.05],
            [0.12, -0.07, shieldZ - 0.05],
            [0.12, 0.16, shieldZ - 0.05],
            [-0.12, 0.16, shieldZ - 0.05],
            facing: [0, 0, -1]
        )
        shieldPart.addChild(
            makePart("shieldBoss", mesh: "\(spec.qualifier).shieldBoss", boss, accent(livery, roughness: 0.5))
        )

        // Short haft with a wedge head, carried low.
        var weapon = FlatMeshBuilder(uv: partUV)
        let haftLength = random.float(in: 0.78...0.90)
        addPrism(
            &weapon,
            from: Section([0, -haftLength * 0.45, -0.13], 0.065, 0.065),
            to: Section([0, haftLength * 0.55, 0.08], 0.070, 0.070),
            capBottom: false,
            capTop: false
        )
        let weaponPart = makePart(
            "weapon",
            mesh: "\(spec.qualifier).weapon",
            weapon,
            dark(livery, roughness: 0.84)
        )
        weaponPart.position = [0.03, -spec.armLength * 0.88, 0.02]
        biped.armRight.addChild(weaponPart)

        var blade = FlatMeshBuilder(uv: partUV)
        addPyramid(
            &blade,
            base: Section([0, haftLength * 0.52, 0.075], 0.19, 0.16),
            apex: [0, haftLength * 0.55 + 0.26, 0.07],
            capBase: true
        )
        weaponPart.addChild(
            makePart("weaponHead", mesh: "\(spec.qualifier).weaponHead", blade, accent(livery, roughness: 0.5))
        )

        return biped.root
    }

    /// The Quarrel unit. A long lumen launcher held forward across the body
    /// is the whole silhouette read — the only unit with a horizontal bar
    /// projecting past its own outline. 2.52 m, ~215 triangles.
    static func quarrel(faction: Faction, seed: UInt64) -> Entity {
        var random = DeterministicRandom.stream(seed: seed, tag: "unit.quarrel.\(faction.rawValue)")
        let livery = Livery.of(faction)

        let spec = BipedSpec(
            qualifier: "quarrel.\(faction.rawValue)",
            height: 2.52,
            crownHeight: 2.52,
            hipHeight: 1.00,
            hipSpread: 0.175,
            legWidth: 0.24,
            legDepth: 0.27,
            footDepth: 0.36,
            waistWidth: 0.44,
            shoulderWidth: 0.62,
            bodyDepth: 0.34,
            shoulderHeight: 1.06,
            hemDrop: 0.20,
            armLength: 0.68,
            armWidth: 0.150,
            mantleFlare: 1.24,
            contactRadius: 0.66
        )

        let biped = makeBiped(spec: spec, livery: livery, random: &random)

        // The launcher is authored along local +Y and then laid forward, because
        // `addPrism` sections are horizontal slices through a part.
        var launcher = FlatMeshBuilder(uv: partUV)
        let barrel = random.float(in: 0.90...1.02)
        addPrism(
            &launcher,
            from: Section([0, -0.20, 0], 0.115, 0.125),
            to: Section([0, barrel, 0], 0.085, 0.095),
            capBottom: true,
            capTop: false
        )
        addPyramid(
            &launcher,
            base: Section([0, barrel, 0], 0.085, 0.095),
            apex: [0, barrel + 0.17, 0]
        )
        // Shoulder brace, so the weapon reads as braced rather than floating.
        addQuad(
            &launcher,
            [-0.04, -0.20, -0.07],
            [0.04, -0.20, -0.07],
            [0.04, -0.42, -0.20],
            [-0.04, -0.42, -0.20],
            facing: [0, 0, -1]
        )
        let launcherPart = makePart(
            "weapon",
            mesh: "\(spec.qualifier).weapon",
            launcher,
            dark(livery, roughness: 0.82)
        )
        launcherPart.position = [-0.05, -spec.armLength * 0.80, 0.02]
        // Local +Y becomes world −Z: the barrel points where the unit faces.
        launcherPart.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
        biped.armRight.addChild(launcherPart)

        // Faction band along the receiver, so the weapon carries team colour too.
        var band = FlatMeshBuilder(uv: partUV)
        addPrism(
            &band,
            from: Section([0, 0.02, 0], 0.125, 0.135),
            to: Section([0, 0.22, 0], 0.120, 0.130),
            capBottom: false,
            capTop: false
        )
        launcherPart.addChild(
            makePart("weaponBand", mesh: "\(spec.qualifier).weaponBand", band, team(livery, roughness: 0.8))
        )

        // Charged coil at the muzzle.
        var coil = FlatMeshBuilder(uv: partUV)
        addQuad(
            &coil,
            [-0.075, barrel - 0.14, -0.070],
            [0.075, barrel - 0.14, -0.070],
            [0.075, barrel - 0.02, -0.070],
            [-0.075, barrel - 0.02, -0.070],
            facing: [0, 0, -1]
        )
        launcherPart.addChild(
            makePart("coil", mesh: "\(spec.qualifier).coil", coil, glow(livery.lume))
        )

        return biped.root
    }

    /// The Gravemark signature: a heavy quadruped walker. Stacked mineral hull,
    /// copper seams, four splayed legs in a diagonal trot. 4.30 m, ~150 triangles.
    ///
    /// No faction parameter — the Bastion Walker is Gravemark by definition.
    static func bastionWalker(seed: UInt64) -> Entity {
        var random = DeterministicRandom.stream(seed: seed, tag: "unit.bastionWalker")
        let livery = Livery.of(.gravemark)

        let hullPivot: Float = 2.55      // world y of the leg joints and hull pivot
        let height: Float = 4.30
        let spread = random.float(in: 0.80...0.90)
        let reach = random.float(in: 0.98...1.10)

        let root = Entity()
        root.name = "unit.bastionWalker"

        // An elongated pool: a four-legged machine sits on a footprint that is
        // longer than it is wide, and a circular patch under it reads as a disc
        // the walker happens to be standing near.
        let contact = makeContactShadow(radius: 1.55, tint: livery.contact, name: "bastionWalker")
        contact.scale = [1, 1, 1.42]
        root.addChild(contact)

        // MARK: Legs — front pair steps against the rear pair.
        let legs: [(name: String, side: Float, front: Float)] = [
            (Part.legL, -1, -1),
            (Part.legR, 1, -1),
            (Part.legLRear, -1, 1),
            (Part.legRRear, 1, 1),
        ]
        for leg in legs {
            var builder = FlatMeshBuilder(uv: partUV)
            // Thigh, angling outward into the knee.
            addPrism(
                &builder,
                from: Section([leg.side * 0.20, -1.36, leg.front * 0.08], 0.32, 0.34),
                to: Section([0, 0, 0], 0.42, 0.44),
                capBottom: false,
                capTop: false
            )
            // Shin, angling back under the hull into a broad pad.
            addPrism(
                &builder,
                from: Section([leg.side * 0.13, -hullPivot, leg.front * -0.05], 0.40, 0.55),
                to: Section([leg.side * 0.20, -1.36, leg.front * 0.08], 0.32, 0.34),
                capBottom: true,
                capTop: false
            )
            let part = makePart(
                leg.name,
                mesh: "bastionWalker.\(leg.name)",
                builder,
                dark(livery, roughness: 0.9)
            )
            part.position = [leg.side * spread, hullPivot, leg.front * reach]
            root.addChild(part)
        }

        // MARK: Hull
        var hull = FlatMeshBuilder(uv: partUV)
        addPrism(
            &hull,
            from: Section([0, -0.38, 0], 1.55, 2.82),
            to: Section([0, 0.42, -0.05], 1.65, 2.62),
            capBottom: true,
            capTop: false
        )
        addPrism(
            &hull,
            from: Section([0, 0.42, -0.05], 1.65, 2.62),
            to: Section([0, 1.00, -0.20], 1.25, 1.92),
            capBottom: false,
            capTop: true
        )
        let torso = makePart(
            Part.torso,
            mesh: "bastionWalker.hull",
            hull,
            plate(livery, roughness: 0.9)
        )
        torso.position = [0, hullPivot, 0]
        root.addChild(torso)

        // MARK: Dorsal deck — the faction-coloured area a top-down camera sees.
        var deck = FlatMeshBuilder(uv: partUV)
        addPrism(
            &deck,
            from: Section([0, 0.98, -0.20], 1.31, 1.98),
            to: Section([0, 1.16, -0.22], 1.02, 1.60),
            capBottom: false,
            capTop: true
        )
        torso.addChild(
            makePart("deck", mesh: "bastionWalker.deck", deck, team(livery, roughness: 0.88))
        )

        // MARK: Dorsal spire — the tallest point, and the read at distance.
        var spire = FlatMeshBuilder(uv: partUV)
        let spireTop = height - hullPivot
        addPrism(
            &spire,
            from: Section([0, 1.10, 0.30], 0.56, 0.62),
            to: Section([0, spireTop - 0.32, 0.25], 0.36, 0.40),
            capBottom: false,
            capTop: false
        )
        addPyramid(
            &spire,
            base: Section([0, spireTop - 0.32, 0.25], 0.36, 0.40),
            apex: [0, spireTop, 0.25]
        )
        torso.addChild(
            makePart("spire", mesh: "bastionWalker.spire", spire, plate(livery, roughness: 0.88))
        )

        // MARK: Copper seams down the flanks.
        var seams = FlatMeshBuilder(uv: partUV)
        for side in [Float(-1), Float(1)] {
            addQuad(
                &seams,
                [side * 0.85, 0.14, -1.28],
                [side * 0.85, 0.14, 1.18],
                [side * 0.85, -0.08, 1.22],
                [side * 0.85, -0.08, -1.32],
                facing: [side, 0, 0]
            )
        }
        torso.addChild(
            makePart("seams", mesh: "bastionWalker.seams", seams, accent(livery, roughness: 0.6))
        )

        // MARK: Sensor band on the prow.
        var sensor = FlatMeshBuilder(uv: partUV)
        addQuad(
            &sensor,
            [-0.42, 0.20, -1.43],
            [0.42, 0.20, -1.43],
            [0.42, 0.38, -1.38],
            [-0.42, 0.38, -1.38],
            facing: [0, 0, -1]
        )
        torso.addChild(
            makePart("sensor", mesh: "bastionWalker.sensor", sensor, glow(livery.lume))
        )

        return root
    }

    // MARK: - Shared biped

    /// The 60% of the grammar every biped shares. Equipment supplies the rest.
    private struct BipedSpec {
        var qualifier: String
        /// Nominal standing height. Documented contract, not a computed result.
        var height: Float
        /// World y of the top of the head. Below `height` when equipment tops
        /// the silhouette out instead.
        var crownHeight: Float
        var hipHeight: Float
        var hipSpread: Float
        var legWidth: Float
        var legDepth: Float
        var footDepth: Float
        var waistWidth: Float
        var shoulderWidth: Float
        var bodyDepth: Float
        /// Shoulder height above the hip pivot, in torso-local space.
        var shoulderHeight: Float
        /// How far the coat or robe hangs below the hip pivot.
        var hemDrop: Float
        var armLength: Float
        var armWidth: Float
        var hasPauldrons: Bool = false
        /// How far the faction mantle flares past the shoulders. At or below 1
        /// the mantle is omitted entirely.
        var mantleFlare: Float = 1.30
        /// Radius of the ground pool at the feet, in mesh metres.
        var contactRadius: Float = 0.68
    }

    private struct Biped {
        let root: Entity
        let torso: Entity
        let armLeft: Entity
        let armRight: Entity
        let spec: BipedSpec
    }

    /// Builds the contact pool, legs, torso, skirt, belt, mantle, head and arms
    /// into the rig contract.
    ///
    /// Jitter is applied to proportions only — never to the heights that carry
    /// the scale contract — so a crowd varies without any unit being off-spec.
    private static func makeBiped(
        spec authored: BipedSpec,
        livery: Livery,
        random: inout DeterministicRandom
    ) -> Biped {
        var spec = authored
        spec.shoulderWidth *= random.float(in: 0.96...1.04)
        spec.bodyDepth *= random.float(in: 0.97...1.04)
        spec.armWidth *= random.float(in: 0.94...1.06)
        spec.hemDrop *= random.float(in: 0.92...1.08)
        spec.shoulderWidth *= livery.bulk
        spec.bodyDepth *= livery.bulk

        let root = Entity()
        root.name = "unit.\(spec.qualifier)"

        // MARK: Contact pool. First child, and never posed — this is the only
        // thing in the rig that must not move when the gait does.
        root.addChild(
            makeContactShadow(radius: spec.contactRadius, tint: livery.contact, name: spec.qualifier)
        )

        // MARK: Legs. Pivot at the hip, sole exactly on the ground plane, and
        // the darkest value on the unit: the bottom quarter of the silhouette is
        // what separates a standing figure from a pale rock on pale ground.
        for (name, side) in [(Part.legL, Float(-1)), (Part.legR, Float(1))] {
            var builder = FlatMeshBuilder(uv: partUV)
            let ankle = -spec.hipHeight * 0.74
            addPrism(
                &builder,
                from: Section([0, -spec.hipHeight, -0.03], spec.legWidth * 1.06, spec.footDepth),
                to: Section([0, ankle, 0], spec.legWidth * 0.88, spec.legDepth * 0.92),
                capBottom: true,
                capTop: false
            )
            addPrism(
                &builder,
                from: Section([0, ankle, 0], spec.legWidth * 0.88, spec.legDepth * 0.92),
                to: Section([0, 0, 0], spec.legWidth, spec.legDepth),
                capBottom: false,
                capTop: false
            )
            let leg = makePart(
                name,
                mesh: "\(spec.qualifier).\(name)",
                builder,
                dark(livery, roughness: 0.9)
            )
            leg.position = [side * spec.hipSpread, spec.hipHeight, 0]
            root.addChild(leg)
        }

        // MARK: Torso. The hem hangs below the pivot and the chest rises above
        // it, so a pitch about local X swings the whole upper body from the
        // waist. The lower robe is split off into `skirt` so the faction colour
        // can occupy a real area instead of a decal.
        let waistHeight = spec.shoulderHeight * 0.30
        let hemY = -spec.hemDrop
        let hemWidth = spec.waistWidth * livery.hemFlare
        let hemDepth = spec.bodyDepth * 1.16
        let splitBlend: Float = 0.46
        let splitY = hemY + (waistHeight - hemY) * splitBlend
        let splitWidth = hemWidth + (spec.waistWidth - hemWidth) * splitBlend
        let splitDepth = hemDepth + (spec.bodyDepth * 0.94 - hemDepth) * splitBlend

        var torsoBuilder = FlatMeshBuilder(uv: partUV)
        addPrism(
            &torsoBuilder,
            from: Section([0, splitY, 0], splitWidth, splitDepth),
            to: Section([0, waistHeight, 0], spec.waistWidth, spec.bodyDepth * 0.94),
            capBottom: false,
            capTop: false
        )
        addPrism(
            &torsoBuilder,
            from: Section([0, waistHeight, 0], spec.waistWidth, spec.bodyDepth * 0.94),
            to: Section([0, spec.shoulderHeight, 0], spec.shoulderWidth, spec.bodyDepth),
            capBottom: false,
            capTop: true
        )
        let torso = makePart(
            Part.torso,
            mesh: "\(spec.qualifier).torso",
            torsoBuilder,
            cloth(livery, roughness: 0.95)
        )
        torso.position = [0, spec.hipHeight, 0]
        root.addChild(torso)

        // MARK: Skirt — faction colour, and the read from a low or side angle.
        var skirtBuilder = FlatMeshBuilder(uv: partUV)
        addPrism(
            &skirtBuilder,
            from: Section([0, hemY, 0], hemWidth, hemDepth),
            to: Section([0, splitY, 0], splitWidth, splitDepth),
            capBottom: true,
            capTop: false
        )
        torso.addChild(
            makePart("skirt", mesh: "\(spec.qualifier).skirt", skirtBuilder, team(livery, roughness: 0.92))
        )

        // MARK: Belt — a thin accent band at the waist. Small, but it is metal
        // against cloth, so it is the one place on the body that takes a
        // specular hit from the key light and survives the bright pass.
        let beltHalf = max(spec.shoulderHeight * 0.048, 0.032)
        var beltBuilder = FlatMeshBuilder(uv: partUV)
        addPrism(
            &beltBuilder,
            from: Section([0, waistHeight - beltHalf, 0], spec.waistWidth * 1.09, spec.bodyDepth * 1.03),
            to: Section([0, waistHeight + beltHalf, 0], spec.waistWidth * 1.07, spec.bodyDepth * 1.01),
            capBottom: false,
            capTop: false
        )
        torso.addChild(
            makePart("belt", mesh: "\(spec.qualifier).belt", beltBuilder, accent(livery, roughness: 0.5))
        )

        // MARK: Mantle — the primary faction-colour surface.
        //
        // A flared ring over the shoulders, wide at the bottom and narrow at the
        // collar, so its walls face outward *and upward*. At this camera's 57°
        // pitch that is the largest patch of a unit pointing anywhere near the
        // lens, and being a ring it presents the same block of colour under any
        // yaw — which a chest sash does not.
        if spec.mantleFlare > 1.001 {
            var mantleBuilder = FlatMeshBuilder(uv: partUV)
            addPrism(
                &mantleBuilder,
                from: Section(
                    [0, spec.shoulderHeight - 0.24, 0],
                    spec.shoulderWidth * spec.mantleFlare,
                    spec.bodyDepth * spec.mantleFlare
                ),
                to: Section(
                    [0, spec.shoulderHeight + 0.07, 0],
                    spec.waistWidth * 0.62,
                    spec.bodyDepth * 0.62
                ),
                capBottom: false,
                capTop: false
            )
            torso.addChild(
                makePart("mantle", mesh: "\(spec.qualifier).mantle", mantleBuilder, team(livery, roughness: 0.9))
            )
        }

        // MARK: Head. Height is whatever is left between the collar and the
        // authored crown, so the scale contract holds exactly.
        let headBase = spec.shoulderHeight - 0.04
        let headHeight = max(spec.crownHeight - spec.hipHeight - headBase, 0.16)
        let tilt = random.float(in: -0.012...0.012)
        let neckWidth = spec.waistWidth * 0.48
        let neckDepth = spec.bodyDepth * 0.58
        let browY = headHeight * 0.58
        let browWidth = spec.waistWidth * 0.76
        let browDepth = spec.bodyDepth * 0.86

        var headBuilder = FlatMeshBuilder(uv: partUV)
        addPrism(
            &headBuilder,
            from: Section([0, 0, 0], neckWidth, neckDepth),
            to: Section([0, browY, tilt], browWidth, browDepth),
            capBottom: false,
            capTop: false
        )
        addPyramid(
            &headBuilder,
            base: Section([0, browY, tilt], browWidth, browDepth),
            apex: [0, headHeight, tilt + 0.03]
        )
        let head = makePart(
            Part.head,
            mesh: "\(spec.qualifier).head",
            headBuilder,
            cloth(livery, roughness: 0.9)
        )
        head.position = [0, headBase, 0]
        torso.addChild(head)

        // Hood opening. The hood is the brightest cloth on the unit and sits
        // directly against a pale ground; a dark face plate under the brow is
        // what stops the crown reading as an unattached light blob.
        let faceY = headHeight * 0.16
        let faceBlend = min(faceY / max(browY, 1e-3), 1)
        let faceWidth = neckWidth + (browWidth - neckWidth) * faceBlend
        let faceDepth = neckDepth + (browDepth - neckDepth) * faceBlend
        var faceBuilder = FlatMeshBuilder(uv: partUV)
        addQuad(
            &faceBuilder,
            [-faceWidth * 0.34, faceY, -(faceDepth * 0.5) - 0.006],
            [faceWidth * 0.34, faceY, -(faceDepth * 0.5) - 0.006],
            [browWidth * 0.30, browY - 0.05, -(browDepth * 0.5) - 0.006],
            [-browWidth * 0.30, browY - 0.05, -(browDepth * 0.5) - 0.006],
            facing: [0, 0, -1]
        )
        head.addChild(
            makePart("face", mesh: "\(spec.qualifier).face", faceBuilder, dark(livery, roughness: 0.95))
        )

        // Brow band. A ring rather than a front decal, so a yawed camera never
        // loses it.
        var bandBuilder = FlatMeshBuilder(uv: partUV)
        addPrism(
            &bandBuilder,
            from: Section([0, browY - 0.06, tilt], browWidth * 1.04, browDepth * 1.04),
            to: Section([0, browY + 0.005, tilt], browWidth * 1.03, browDepth * 1.03),
            capBottom: false,
            capTop: false
        )
        head.addChild(
            makePart("brow", mesh: "\(spec.qualifier).brow", bandBuilder, accent(livery, roughness: 0.5))
        )

        // MARK: Arms. Pivot at the shoulder, hanging to a dark glove — the same
        // value trick the boots use, one step further out on the silhouette.
        let shoulderOffset = spec.shoulderWidth * 0.5 + spec.armWidth * 0.42
        let cuffY = -spec.armLength * 0.64
        var arms: [String: Entity] = [:]
        for (name, side) in [(Part.armL, Float(-1)), (Part.armR, Float(1))] {
            var builder = FlatMeshBuilder(uv: partUV)
            addPrism(
                &builder,
                from: Section([side * 0.012, cuffY, 0.02], spec.armWidth * 0.90, spec.armWidth * 0.98),
                to: Section([0, 0, 0], spec.armWidth, spec.armWidth * 1.06),
                capBottom: false,
                capTop: false
            )
            let arm = makePart(
                name,
                mesh: "\(spec.qualifier).\(name)",
                builder,
                cloth(livery, roughness: 0.9)
            )
            arm.position = [side * shoulderOffset, spec.shoulderHeight - 0.06, 0]
            torso.addChild(arm)
            arms[name] = arm

            var gloveBuilder = FlatMeshBuilder(uv: partUV)
            addPrism(
                &gloveBuilder,
                from: Section([side * 0.018, -spec.armLength, 0.03], spec.armWidth * 0.96, spec.armWidth * 1.02),
                to: Section([side * 0.012, cuffY, 0.02], spec.armWidth * 0.92, spec.armWidth * 1.00),
                capBottom: true,
                capTop: false
            )
            arm.addChild(
                makePart(
                    side < 0 ? "gloveL" : "gloveR",
                    mesh: "\(spec.qualifier).glove\(side < 0 ? "L" : "R")",
                    gloveBuilder,
                    dark(livery, roughness: 0.88)
                )
            )
        }

        // MARK: Pauldrons — armoured shoulders, for the units that carry them.
        // Faction-coloured, because on a soldier they are the widest thing the
        // camera sees.
        if spec.hasPauldrons {
            for side in [Float(-1), Float(1)] {
                var builder = FlatMeshBuilder(uv: partUV)
                addPrism(
                    &builder,
                    from: Section([side * 0.04, -0.17, 0], spec.armWidth * 1.9, spec.bodyDepth * 0.90),
                    to: Section([0, 0.08, 0], spec.armWidth * 2.3, spec.bodyDepth * 1.00),
                    capBottom: false,
                    capTop: true
                )
                let pauldron = makePart(
                    side < 0 ? "pauldronL" : "pauldronR",
                    mesh: "\(spec.qualifier).pauldron\(side < 0 ? "L" : "R")",
                    builder,
                    team(livery, roughness: 0.8)
                )
                pauldron.position = [side * shoulderOffset, spec.shoulderHeight - 0.02, 0]
                torso.addChild(pauldron)
            }
        }

        torso.addChild(makeLume(spec: spec, livery: livery))

        return Biped(
            root: root,
            torso: torso,
            armLeft: arms[Part.armL] ?? torso,
            armRight: arms[Part.armR] ?? torso,
            spec: spec
        )
    }

    /// The single self-luminous accent every unit carries: a woven collar mote
    /// for Sunwoven, a mineral seam for Gravemark. Small on purpose — the bible
    /// keeps saturated glow for alerts, not for ambient unit chrome — but it is
    /// the one thing on a unit the bright pass can find, so it is what makes a
    /// crowd twinkle rather than smear.
    private static func makeLume(spec: BipedSpec, livery: Livery) -> Entity {
        let front = -(spec.bodyDepth * 0.5 + 0.012)
        let top = spec.shoulderHeight * 0.78
        var builder = FlatMeshBuilder(uv: partUV)
        switch livery.silhouette {
        case .woven:
            addQuad(
                &builder,
                [-spec.shoulderWidth * 0.17, top, front],
                [spec.shoulderWidth * 0.17, top, front],
                [spec.shoulderWidth * 0.13, top - 0.07, front],
                [-spec.shoulderWidth * 0.13, top - 0.07, front],
                facing: [0, 0, -1]
            )
        case .plated:
            addQuad(
                &builder,
                [-spec.shoulderWidth * 0.06, top, front],
                [spec.shoulderWidth * 0.06, top, front],
                [spec.shoulderWidth * 0.06, top - 0.28, front],
                [-spec.shoulderWidth * 0.06, top - 0.28, front],
                facing: [0, 0, -1]
            )
        }
        return makePart("lume", mesh: "\(spec.qualifier).lume", builder, glow(livery.lume))
    }

    // MARK: - Contact pool

    /// Two flat unlit discs under the feet: an inner core and a wider, fainter
    /// halo.
    ///
    /// This is not a substitute for the key light's cast shadow — that still
    /// runs, and still falls to one side. It is the *ambient* half: the darkening
    /// directly beneath a body where the sky is occluded, which is the cue that
    /// tells a viewer an object is standing on a surface rather than hovering
    /// over it. Without it every unit on a bright fragment reads as a decal.
    ///
    /// Two rings rather than one because a single hard-edged disc reads as a
    /// painted spot; a core plus a fainter ring reads as a penumbra. They do not
    /// overlap in plan, so nothing double-blends.
    ///
    /// `UnlitMaterial` on purpose: `LightingRigSystem` excludes unlit-only
    /// entities from the shadow map, so the pool can never cast a shadow of its
    /// own, and being unlit it holds the same density whether the unit stands in
    /// the key light or in a building's shadow.
    private static func makeContactShadow(radius: Float, tint: UIColor, name: String) -> Entity {
        let root = Entity()
        root.name = Part.contact

        let core = Entity()
        core.name = "contact.core"
        core.components.set(
            ModelComponent(
                mesh: disc(inner: 0, outer: radius * 0.74, segments: 12)
                    .makeMesh(named: "\(name).contact.core"),
                materials: [shadowMaterial(tint, opacity: 0.40)]
            )
        )
        core.position = [0, 0.020, 0]
        root.addChild(core)

        let halo = Entity()
        halo.name = "contact.halo"
        halo.components.set(
            ModelComponent(
                mesh: disc(inner: radius * 0.74, outer: radius * 1.34, segments: 12)
                    .makeMesh(named: "\(name).contact.halo"),
                materials: [shadowMaterial(tint, opacity: 0.17)]
            )
        )
        halo.position = [0, 0.016, 0]
        root.addChild(halo)

        return root
    }

    /// A flat horizontal disc or annulus at y = 0. No UV projection: the pool is
    /// an unlit blend, and an unlit material samples no texture.
    private static func disc(inner: Float, outer: Float, segments: Int) -> FlatMeshBuilder {
        var builder = FlatMeshBuilder()
        let up = SIMD3<Float>(0, 1, 0)
        for index in 0..<segments {
            let a = Float(index) / Float(segments) * 2 * .pi
            let b = Float(index + 1) / Float(segments) * 2 * .pi
            let outerA = SIMD3<Float>(cos(a) * outer, 0, sin(a) * outer)
            let outerB = SIMD3<Float>(cos(b) * outer, 0, sin(b) * outer)
            if inner <= 1e-4 {
                builder.addTriangle(.zero, outerA, outerB, facing: up)
            } else {
                let innerA = SIMD3<Float>(cos(a) * inner, 0, sin(a) * inner)
                let innerB = SIMD3<Float>(cos(b) * inner, 0, sin(b) * inner)
                builder.addTriangle(innerA, outerA, outerB, facing: up)
                builder.addTriangle(innerA, outerB, innerB, facing: up)
            }
        }
        return builder
    }

    /// A darkening blend, not an emitter — so it deliberately does **not** go
    /// through `LuminousMaterial`, whose whole job is to raise a colour to
    /// emitter brightness. An alpha on the tint alone leaves an `UnlitMaterial`
    /// opaque; `blending` is what makes it a blend.
    private static func shadowMaterial(_ tint: UIColor, opacity: Float) -> UnlitMaterial {
        var material = UnlitMaterial(color: tint)
        material.faceCulling = .none
        material.blending = .transparent(opacity: .init(floatLiteral: opacity))
        return material
    }

    // MARK: - Livery

    private enum Silhouette {
        /// Sunwoven: cloth, drape, light lattice.
        case woven
        /// Gravemark: plate, stacked mass, bunker edges.
        case plated
    }

    private struct Livery {
        /// The main robe or coat. The mid value of the unit.
        let cloth: UIColor
        /// Equipment shell — packs, hulls, racks.
        let plate: UIColor
        /// Metal trim: belt, brow band, weapon head.
        let accent: UIColor
        /// The faction identity block: mantle, skirt, pauldrons, shield, deck.
        /// This is the colour a player reads ownership from, so it goes on area,
        /// never on a line.
        let team: UIColor
        /// Boots, gloves, hood shadow, greaves. The dark end of the value ramp,
        /// and the reason a unit does not dissolve into pale ground.
        let dark: UIColor
        let lume: UIColor
        /// The contact pool's blend colour. A shadow on this faction's home
        /// ground, so it stays warm on regolith and cool on slate.
        let contact: UIColor

        /// Which `MaterialLibrary` surface class each zone is cut from.
        ///
        /// Named rather than inferred from the tint, for two independent reasons.
        ///
        /// First, ambiguity: both factions have a livery colour that inference
        /// gets wrong. A Sunwoven unit's `plate` colour *is* `sunwovenSurface`,
        /// the habitable ground, so inference would dress a citizen's pack in
        /// regolith dunes; and a Gravemark unit's `cloth` colour is the same
        /// value as its armour, so inference cannot tell a coat from a hull.
        ///
        /// Second, headroom: `MaterialLibrary.correction` clamps at 1, so a tint
        /// can only be reproduced on a recipe whose authored mid-tone is at least
        /// as bright in every channel. `gravemarkMineral` is brighter in blue
        /// than the `oxidisedMetal` mid-tone, so routing the Gravemark team
        /// colour through `.platedSlate` would clamp it back to plain slate and
        /// the faction block would vanish. `.rimStone` has the headroom, is a
        /// mineral recipe, and is what Gravemark's identity is built from anyway.
        let clothSurface: MaterialLibrary.Surface
        let plateSurface: MaterialLibrary.Surface
        let accentSurface: MaterialLibrary.Surface
        let teamSurface: MaterialLibrary.Surface
        let darkSurface: MaterialLibrary.Surface
        let silhouette: Silhouette

        /// Side-to-side and front-to-back mass multiplier. Never applied to a
        /// height, so the scale contract is unaffected by faction.
        var bulk: Float { silhouette == .plated ? 1.10 : 1.0 }
        /// How far the hem flares past the waist. A robe, or a plated skirt.
        var hemFlare: Float { silhouette == .woven ? 1.34 : 1.10 }

        static func of(_ faction: Faction) -> Livery {
            switch faction {
            case .sunwoven:
                // Ivory over ivory, separated by value rather than by material,
                // with turquoise carrying ownership and gold the one metal.
                // Boots are a deep shade of the faction's own rock — dark enough
                // to anchor the figure, still traceable to the locked palette.
                Livery(
                    cloth: SunfoldPalette.sunwovenIvory,
                    plate: SunfoldPalette.sunwovenSurface,
                    accent: SunfoldPalette.sunwovenGold,
                    team: SunfoldPalette.sunwovenTurquoise,
                    dark: StructureMaterial.shade(SunfoldPalette.sunwovenRock, 0.60),
                    lume: SunfoldPalette.sunwovenTurquoise,
                    contact: StructureMaterial.shade(SunfoldPalette.sunwovenRock, 0.30),
                    clothSurface: .wovenIvory,
                    plateSurface: .wovenIvory,
                    accentSurface: .goldTrim,
                    teamSurface: .wovenIvory,
                    darkSurface: .wovenIvory,
                    silhouette: .woven
                )
            case .gravemark:
                // The exact inverse: a plated coat over a rock-toned hull, with
                // mineral blue for ownership and oxidised copper for the trim.
                Livery(
                    cloth: SunfoldPalette.gravemarkSurface,
                    plate: SunfoldPalette.gravemarkRock,
                    accent: SunfoldPalette.gravemarkCopper,
                    team: SunfoldPalette.gravemarkMineral,
                    dark: StructureMaterial.shade(SunfoldPalette.gravemarkRock, 0.62),
                    lume: SunfoldPalette.gravemarkMineral,
                    contact: StructureMaterial.shade(SunfoldPalette.gravemarkRock, 0.40),
                    clothSurface: .platedSlate,
                    plateSurface: .armouredHull,
                    accentSurface: .oxidisedCopper,
                    teamSurface: .rimStone,
                    darkSurface: .platedSlate,
                    silhouette: .plated
                )
            }
        }
    }

    // MARK: - Materials

    /// How a unit part's surface points become UVs.
    ///
    /// Every part here is a prism or a pyramid — boxy by construction — so units
    /// take the same dominant-axis box mapping every authored structure takes,
    /// at the same `MaterialLibrary.metersPerTile`. Quoting the shared anchor
    /// rather than a local constant is what stops a citizen's coat being grained
    /// differently from the Core it walks past.
    ///
    /// One known approximation: `EntityPresenter` renders units at
    /// `SkirmishTuning.unitVisualScale`, and UVs are generated in mesh-local
    /// metres, so a unit's texel density is that factor coarser than the world's.
    /// At 1.25 it is a 20% difference on the smallest objects in frame, which is
    /// well below what the pattern itself varies by, and correcting it would put
    /// tuning state inside a mesh factory.
    private static let partUV = MaterialLibrary.structureUVProjection

    /// The lit material zones a unit is made of. Each names its surface class
    /// explicitly — see `Livery` for why inference is unsafe here.
    ///
    /// `roughness` keeps the meaning it had when these were flat materials —
    /// "how rough, relative to the other parts" — but now multiplies the
    /// recipe's roughness map instead of replacing it, exactly as
    /// `StructureMaterial.matte` does for buildings.
    private static func cloth(_ livery: Livery, roughness: Float) -> PhysicallyBasedMaterial {
        MaterialLibrary.material(
            livery.clothSurface,
            tint: livery.cloth,
            roughness: roughness,
            emissiveIntensity: 0
        )
    }

    private static func plate(_ livery: Livery, roughness: Float) -> PhysicallyBasedMaterial {
        MaterialLibrary.material(
            livery.plateSurface,
            tint: livery.plate,
            roughness: roughness,
            emissiveIntensity: 0
        )
    }

    private static func accent(_ livery: Livery, roughness: Float) -> PhysicallyBasedMaterial {
        MaterialLibrary.material(
            livery.accentSurface,
            tint: livery.accent,
            roughness: roughness,
            emissiveIntensity: 0
        )
    }

    /// The faction block. Kept lit rather than emissive: ownership colour has to
    /// read the same in shadow as in the key light, but a glowing citizen would
    /// compete with the alert vocabulary the bible reserves saturation for.
    private static func team(_ livery: Livery, roughness: Float) -> PhysicallyBasedMaterial {
        MaterialLibrary.material(
            livery.teamSurface,
            tint: livery.team,
            roughness: roughness,
            emissiveIntensity: 0
        )
    }

    private static func dark(_ livery: Livery, roughness: Float) -> PhysicallyBasedMaterial {
        MaterialLibrary.material(
            livery.darkSurface,
            tint: livery.dark,
            roughness: roughness,
            emissiveIntensity: 0
        )
    }

    /// Reserved for the self-luminous accents. Everything else is lit.
    private static func glow(_ color: UIColor) -> UnlitMaterial {
        // Emitter brightness, not paint brightness — see LuminousMaterial. The
        // hue is untouched; only the level moves, which is what lets the
        // post-process bright pass separate an accent from the hull around it.
        LuminousMaterial.unlit(color)
    }

    private static func makePart(
        _ name: String,
        mesh meshName: String,
        _ builder: FlatMeshBuilder,
        _ material: any Material
    ) -> Entity {
        let entity = Entity()
        entity.name = name
        entity.components.set(
            ModelComponent(mesh: builder.makeMesh(named: meshName), materials: [material])
        )
        return entity
    }

    // MARK: - Geometry

    /// A rectangular cross-section through a part, in that part's local space.
    /// `width` runs along local X (side to side), `depth` along local Z (front
    /// to back, with −Z forward).
    private struct Section {
        var center: SIMD3<Float>
        var width: Float
        var depth: Float

        init(_ center: SIMD3<Float>, _ width: Float, _ depth: Float) {
            self.center = center
            self.width = width
            self.depth = depth
        }

        /// Corners in a consistent loop: front-left, front-right, back-right,
        /// back-left. The loop order is what makes the walls simple quads.
        var corners: [SIMD3<Float>] {
            let halfWidth = width * 0.5
            let halfDepth = depth * 0.5
            return [
                center + [-halfWidth, 0, -halfDepth],
                center + [halfWidth, 0, -halfDepth],
                center + [halfWidth, 0, halfDepth],
                center + [-halfWidth, 0, halfDepth],
            ]
        }
    }

    /// Adds a tapered box between two cross-sections: 8 triangles of wall, plus
    /// 2 for each cap that is asked for. Caps that end up buried inside another
    /// part are simply not requested, which is where the triangle budget goes.
    ///
    /// Sections are horizontal slices, so a part that runs horizontally is built
    /// upright and then rotated into place by its entity.
    private static func addPrism(
        _ builder: inout FlatMeshBuilder,
        from lower: Section,
        to upper: Section,
        capBottom: Bool = true,
        capTop: Bool = true
    ) {
        let low = lower.corners
        let high = upper.corners
        let axis = normalized(upper.center - lower.center, fallback: [0, 1, 0])
        let core = (lower.center + upper.center) * 0.5

        for index in 0..<4 {
            let next = (index + 1) % 4
            let face = (low[index] + low[next] + high[index] + high[next]) * 0.25
            // The horizontal offset from the part's axis is always on the
            // outside of the wall, which is all `facing` needs to be.
            let outward = normalized([face.x - core.x, 0, face.z - core.z], fallback: [0, 0, -1])
            addQuad(&builder, low[index], low[next], high[next], high[index], facing: outward)
        }

        if capBottom { addQuad(&builder, low[0], low[1], low[2], low[3], facing: -axis) }
        if capTop { addQuad(&builder, high[0], high[1], high[2], high[3], facing: axis) }
    }

    /// Adds a four-sided taper to a point: 4 triangles, plus 2 if the base is
    /// closed. Used for hoods, helms, blade heads and mast tips.
    private static func addPyramid(
        _ builder: inout FlatMeshBuilder,
        base: Section,
        apex: SIMD3<Float>,
        capBase: Bool = false
    ) {
        let corners = base.corners
        for index in 0..<4 {
            let next = (index + 1) % 4
            let edge = (corners[index] + corners[next]) * 0.5
            let outward = normalized([edge.x - base.center.x, 0, edge.z - base.center.z], fallback: [0, 0, -1])
            builder.addTriangle(corners[index], corners[next], apex, facing: outward)
        }
        if capBase {
            addQuad(&builder, corners[0], corners[1], corners[2], corners[3], facing: base.center - apex)
        }
    }

    /// Adds a quad as two triangles. Corners must walk the perimeter in order.
    private static func addQuad(
        _ builder: inout FlatMeshBuilder,
        _ a: SIMD3<Float>,
        _ b: SIMD3<Float>,
        _ c: SIMD3<Float>,
        _ d: SIMD3<Float>,
        facing: SIMD3<Float>
    ) {
        builder.addTriangle(a, b, c, facing: facing)
        builder.addTriangle(a, c, d, facing: facing)
    }

    /// `simd_normalize` of a zero vector is NaN, which would silently poison a
    /// winding reference. Degenerate input falls back to a usable direction.
    private static func normalized(_ vector: SIMD3<Float>, fallback: SIMD3<Float>) -> SIMD3<Float> {
        let lengthSquared = simd_length_squared(vector)
        return lengthSquared > 1e-10 ? vector / sqrt(lengthSquared) : fallback
    }
}
