import Foundation
import RealityKit
import UIKit
import simd

/// Low-poly unit bodies, built as animatable rigs rather than single meshes.
///
/// Authored placeholders in the same faceted idiom as `FragmentMeshFactory`:
/// flat-shaded triangles, no unmodified primitives, silhouette and equipment
/// doing the identification work so a unit is readable at gameplay zoom without
/// relying on colour alone. Sunwoven read light, woven and luminous; Gravemark
/// read plated, heavy and mineral.
///
/// # World conventions
/// Metres, Y up. A unit's origin is at its feet (`y = 0`) and it faces −Z
/// (north) by default, matching `WorldMap`'s north-up contract and the zero yaw
/// of `LocomotionState.facing`.
///
/// # Rig contract
/// Every unit returns a root whose children carry these exact names:
///
/// ```
/// root                      origin at the feet, facing −Z
/// ├── "legL"                pivot at the hip; mesh hangs down to y = 0
/// ├── "legR"                mirrored across X
/// ├── "legLRear" (walker)   rear pair, same pivot rule
/// ├── "legRRear" (walker)
/// └── "torso"               pivot at the hip/waist; mesh rises from there
///     ├── "head"
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
/// feet stay planted on the ground.
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
    }

    // MARK: - Units

    /// The worker biped. Hooded robe or plated work coat, gather haft in hand.
    /// 1.80 m. 86 triangles.
    static func citizen(faction: Faction, seed: UInt64) -> Entity {
        var random = DeterministicRandom.stream(seed: seed, tag: "unit.citizen.\(faction.rawValue)")
        let livery = Livery.of(faction)

        let spec = BipedSpec(
            qualifier: "citizen.\(faction.rawValue)",
            height: 1.80,
            crownHeight: 1.80,
            hipHeight: 0.86,
            hipSpread: 0.135,
            legWidth: 0.19,
            legDepth: 0.21,
            footDepth: 0.27,
            waistWidth: 0.34,
            shoulderWidth: 0.40,
            bodyDepth: 0.26,
            shoulderHeight: 0.62,
            hemDrop: 0.18,
            armLength: 0.52,
            armWidth: 0.115
        )

        let biped = makeBiped(spec: spec, livery: livery, random: &random)

        // Gather haft, angled forward out of the working hand. The one piece of
        // equipment a citizen carries, and the thing that separates its
        // silhouette from a soldier's at zoom.
        var haft = FlatMeshBuilder()
        let reach = random.float(in: 0.40...0.48)
        addPrism(
            &haft,
            from: Section([0, -0.26, -reach], 0.048, 0.048),
            to: Section([0, 0.22, 0.12], 0.052, 0.052),
            capBottom: false,
            capTop: false
        )
        let tool = makePart(
            "tool",
            mesh: "\(spec.qualifier).tool",
            haft,
            matte(livery.accent, roughness: 0.86)
        )
        tool.position = [0, -biped.spec.armLength * 0.86, 0.03]
        biped.armRight.addChild(tool)

        return biped.root
    }

    /// The scout. Slimmer than a citizen, short tunic, back pack carrying an
    /// elevated sensor mast that tops the silhouette out. 1.90 m. 98 triangles.
    static func pathfinder(faction: Faction, seed: UInt64) -> Entity {
        var random = DeterministicRandom.stream(seed: seed, tag: "unit.pathfinder.\(faction.rawValue)")
        let livery = Livery.of(faction)

        let spec = BipedSpec(
            qualifier: "pathfinder.\(faction.rawValue)",
            height: 1.90,
            // The head sits low; the mast above it carries the height contract.
            crownHeight: 1.72,
            hipHeight: 0.96,
            hipSpread: 0.125,
            legWidth: 0.165,
            legDepth: 0.19,
            footDepth: 0.26,
            waistWidth: 0.29,
            shoulderWidth: 0.34,
            bodyDepth: 0.22,
            shoulderHeight: 0.58,
            hemDrop: 0.09,
            armLength: 0.52,
            armWidth: 0.10
        )

        let biped = makeBiped(spec: spec, livery: livery, random: &random)
        let mastTop = spec.height - spec.hipHeight  // torso-local

        var pack = FlatMeshBuilder()
        // Pack block riding high on the back.
        addPrism(
            &pack,
            from: Section([0, 0.20, 0.14], 0.26, 0.13),
            to: Section([0, 0.52, 0.15], 0.30, 0.15),
            capBottom: false,
            capTop: false
        )
        // Mast, rising past the head.
        addPrism(
            &pack,
            from: Section([0, 0.50, 0.15], 0.06, 0.06),
            to: Section([0, mastTop - 0.10, 0.13], 0.05, 0.05),
            capBottom: false,
            capTop: false
        )
        let packPart = makePart(
            "pack",
            mesh: "\(spec.qualifier).pack",
            pack,
            matte(livery.plate, roughness: 0.88)
        )
        biped.torso.addChild(packPart)

        // Self-luminous sensor tip — the one place a scout is allowed to glow.
        var sensor = FlatMeshBuilder()
        addPyramid(
            &sensor,
            base: Section([0, mastTop - 0.10, 0.13], 0.09, 0.09),
            apex: [0, mastTop, 0.13]
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

    /// The melee line unit. Broader, pauldroned, crested helm, plate and haft.
    /// 2.10 m. 112 triangles.
    static func vanguard(faction: Faction, seed: UInt64) -> Entity {
        var random = DeterministicRandom.stream(seed: seed, tag: "unit.vanguard.\(faction.rawValue)")
        let livery = Livery.of(faction)

        let spec = BipedSpec(
            qualifier: "vanguard.\(faction.rawValue)",
            height: 2.10,
            crownHeight: 2.10,
            hipHeight: 1.00,
            hipSpread: 0.165,
            legWidth: 0.225,
            legDepth: 0.25,
            footDepth: 0.32,
            waistWidth: 0.42,
            shoulderWidth: 0.56,
            bodyDepth: 0.32,
            shoulderHeight: 0.70,
            hemDrop: 0.20,
            armLength: 0.56,
            armWidth: 0.14,
            hasPauldrons: true
        )

        let biped = makeBiped(spec: spec, livery: livery, random: &random)
        let head = biped.torso.findEntity(named: Part.head)

        // Helm crest — a single fin, read from the side and from above. Sits
        // inside the head's envelope, so the 2.10 m contract is unaffected.
        var crest = FlatMeshBuilder()
        let headHeight = spec.crownHeight - spec.hipHeight - (spec.shoulderHeight - 0.04)
        let crestBase = headHeight - 0.14
        addQuad(
            &crest,
            [0, crestBase, -0.11],
            [0, crestBase, 0.11],
            [0, crestBase + 0.13, 0.07],
            [0, crestBase + 0.13, -0.07],
            facing: [1, 0, 0]
        )
        let crestPart = makePart(
            "crest",
            mesh: "\(spec.qualifier).crest",
            crest,
            matte(livery.accent, roughness: 0.8)
        )
        head?.addChild(crestPart)

        // Shield on the guard arm.
        var shield = FlatMeshBuilder()
        let shieldZ: Float = -0.07
        addQuad(
            &shield,
            [-0.21, -0.26, shieldZ],
            [0.21, -0.26, shieldZ],
            [0.24, 0.28, shieldZ],
            [-0.24, 0.28, shieldZ],
            facing: [0, 0, -1]
        )
        addQuad(
            &shield,
            [-0.10, -0.05, shieldZ - 0.05],
            [0.10, -0.05, shieldZ - 0.05],
            [0.10, 0.13, shieldZ - 0.05],
            [-0.10, 0.13, shieldZ - 0.05],
            facing: [0, 0, -1]
        )
        let shieldPart = makePart(
            "shield",
            mesh: "\(spec.qualifier).shield",
            shield,
            matte(livery.plate, roughness: 0.82)
        )
        shieldPart.position = [-0.05, -spec.armLength * 0.72, -0.02]
        biped.armLeft.addChild(shieldPart)

        // Short haft with a wedge head, carried low.
        var weapon = FlatMeshBuilder()
        let haftLength = random.float(in: 0.62...0.72)
        addPrism(
            &weapon,
            from: Section([0, -haftLength * 0.45, -0.10], 0.055, 0.055),
            to: Section([0, haftLength * 0.55, 0.06], 0.06, 0.06),
            capBottom: false,
            capTop: false
        )
        addPyramid(
            &weapon,
            base: Section([0, haftLength * 0.52, 0.055], 0.15, 0.13),
            apex: [0, haftLength * 0.55 + 0.20, 0.05]
        )
        let weaponPart = makePart(
            "weapon",
            mesh: "\(spec.qualifier).weapon",
            weapon,
            matte(livery.accent, roughness: 0.78)
        )
        weaponPart.position = [0.02, -spec.armLength * 0.88, 0.02]
        biped.armRight.addChild(weaponPart)

        return biped.root
    }

    /// The ranged line unit. A long lumen launcher held forward across the body
    /// is the whole silhouette read. 1.90 m. 94 triangles.
    static func ranged(faction: Faction, seed: UInt64) -> Entity {
        var random = DeterministicRandom.stream(seed: seed, tag: "unit.ranged.\(faction.rawValue)")
        let livery = Livery.of(faction)

        let spec = BipedSpec(
            qualifier: "ranged.\(faction.rawValue)",
            height: 1.90,
            crownHeight: 1.90,
            hipHeight: 0.92,
            hipSpread: 0.13,
            legWidth: 0.18,
            legDepth: 0.20,
            footDepth: 0.26,
            waistWidth: 0.33,
            shoulderWidth: 0.42,
            bodyDepth: 0.25,
            shoulderHeight: 0.62,
            hemDrop: 0.14,
            armLength: 0.54,
            armWidth: 0.11
        )

        let biped = makeBiped(spec: spec, livery: livery, random: &random)

        // The launcher is authored along local +Y and then laid forward, because
        // `addPrism` sections are horizontal slices through a part.
        var launcher = FlatMeshBuilder()
        let barrel = random.float(in: 0.72...0.82)
        addPrism(
            &launcher,
            from: Section([0, -0.16, 0], 0.09, 0.10),
            to: Section([0, barrel, 0], 0.07, 0.08),
            capBottom: false,
            capTop: false
        )
        addPyramid(
            &launcher,
            base: Section([0, barrel, 0], 0.07, 0.08),
            apex: [0, barrel + 0.13, 0]
        )
        // Shoulder brace, so the weapon reads as braced rather than floating.
        addQuad(
            &launcher,
            [-0.03, -0.16, -0.06],
            [0.03, -0.16, -0.06],
            [0.03, -0.34, -0.16],
            [-0.03, -0.34, -0.16],
            facing: [0, 0, -1]
        )
        let launcherPart = makePart(
            "weapon",
            mesh: "\(spec.qualifier).weapon",
            launcher,
            matte(livery.plate, roughness: 0.8)
        )
        launcherPart.position = [-0.04, -spec.armLength * 0.80, 0.02]
        // Local +Y becomes world −Z: the barrel points where the unit faces.
        launcherPart.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
        biped.armRight.addChild(launcherPart)

        // Charged coil at the muzzle.
        var coil = FlatMeshBuilder()
        addQuad(
            &coil,
            [-0.06, barrel - 0.10, -0.055],
            [0.06, barrel - 0.10, -0.055],
            [0.06, barrel - 0.02, -0.055],
            [-0.06, barrel - 0.02, -0.055],
            facing: [0, 0, -1]
        )
        let coilPart = makePart(
            "coil",
            mesh: "\(spec.qualifier).coil",
            coil,
            glow(livery.lume)
        )
        launcherPart.addChild(coilPart)

        return biped.root
    }

    /// The Gravemark signature: a heavy quadruped walker. Stacked mineral hull,
    /// copper seams, four splayed legs in a diagonal trot. 3.40 m. 110 triangles.
    ///
    /// No faction parameter — the Bastion Walker is Gravemark by definition.
    static func bastionWalker(seed: UInt64) -> Entity {
        var random = DeterministicRandom.stream(seed: seed, tag: "unit.bastionWalker")
        let livery = Livery.of(.gravemark)

        let hullPivot: Float = 2.00      // world y of the leg joints and hull pivot
        let height: Float = 3.40
        let spread = random.float(in: 0.64...0.72)
        let reach = random.float(in: 0.78...0.88)

        let root = Entity()
        root.name = "unit.bastionWalker"

        // MARK: Legs — front pair steps against the rear pair.
        let legs: [(name: String, side: Float, front: Float)] = [
            (Part.legL, -1, -1),
            (Part.legR, 1, -1),
            (Part.legLRear, -1, 1),
            (Part.legRRear, 1, 1),
        ]
        for leg in legs {
            var builder = FlatMeshBuilder()
            // Thigh, angling outward into the knee.
            addPrism(
                &builder,
                from: Section([leg.side * 0.16, -1.08, leg.front * 0.06], 0.26, 0.28),
                to: Section([0, 0, 0], 0.34, 0.36),
                capBottom: false,
                capTop: false
            )
            // Shin, angling back under the hull into a broad pad.
            addPrism(
                &builder,
                from: Section([leg.side * 0.10, -hullPivot, leg.front * -0.04], 0.32, 0.44),
                to: Section([leg.side * 0.16, -1.08, leg.front * 0.06], 0.26, 0.28),
                capBottom: true,
                capTop: false
            )
            let part = makePart(
                leg.name,
                mesh: "bastionWalker.\(leg.name)",
                builder,
                matte(livery.plate, roughness: 0.9)
            )
            part.position = [leg.side * spread, hullPivot, leg.front * reach]
            root.addChild(part)
        }

        // MARK: Hull
        var hull = FlatMeshBuilder()
        addPrism(
            &hull,
            from: Section([0, -0.30, 0], 1.24, 2.26),
            to: Section([0, 0.34, -0.04], 1.32, 2.10),
            capBottom: true,
            capTop: false
        )
        addPrism(
            &hull,
            from: Section([0, 0.34, -0.04], 1.32, 2.10),
            to: Section([0, 0.80, -0.16], 1.00, 1.54),
            capBottom: false,
            capTop: true
        )
        let torso = makePart(
            Part.torso,
            mesh: "bastionWalker.hull",
            hull,
            matte(livery.cloth, roughness: 0.92)
        )
        torso.position = [0, hullPivot, 0]
        root.addChild(torso)

        // MARK: Dorsal spire — the tallest point, and the read at distance.
        var spire = FlatMeshBuilder()
        let spireTop = height - hullPivot
        addPrism(
            &spire,
            from: Section([0, 0.72, 0.24], 0.46, 0.50),
            to: Section([0, spireTop - 0.26, 0.20], 0.30, 0.32),
            capBottom: false,
            capTop: false
        )
        addPyramid(
            &spire,
            base: Section([0, spireTop - 0.26, 0.20], 0.30, 0.32),
            apex: [0, spireTop, 0.20]
        )
        let spirePart = makePart(
            "spire",
            mesh: "bastionWalker.spire",
            spire,
            matte(livery.plate, roughness: 0.88)
        )
        torso.addChild(spirePart)

        // MARK: Copper seams down the flanks.
        var seams = FlatMeshBuilder()
        for side in [Float(-1), Float(1)] {
            addQuad(
                &seams,
                [side * 0.68, 0.10, -1.02],
                [side * 0.68, 0.10, 0.94],
                [side * 0.68, -0.06, 0.98],
                [side * 0.68, -0.06, -1.06],
                facing: [side, 0, 0]
            )
        }
        let seamPart = makePart(
            "seams",
            mesh: "bastionWalker.seams",
            seams,
            matte(livery.accent, roughness: 0.7)
        )
        torso.addChild(seamPart)

        // MARK: Sensor band on the prow.
        var sensor = FlatMeshBuilder()
        addQuad(
            &sensor,
            [-0.34, 0.16, -1.14],
            [0.34, 0.16, -1.14],
            [0.34, 0.30, -1.10],
            [-0.34, 0.30, -1.10],
            facing: [0, 0, -1]
        )
        let sensorPart = makePart(
            "sensor",
            mesh: "bastionWalker.sensor",
            sensor,
            glow(livery.lume)
        )
        torso.addChild(sensorPart)

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
    }

    private struct Biped {
        let root: Entity
        let torso: Entity
        let armLeft: Entity
        let armRight: Entity
        let spec: BipedSpec
    }

    /// Builds legs, torso, head, arms and faction trim into the rig contract.
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
        spec.hemDrop *= random.float(in: 0.90...1.10)
        spec.shoulderWidth *= livery.bulk
        spec.bodyDepth *= livery.bulk

        let root = Entity()
        root.name = "unit.\(spec.qualifier)"

        // MARK: Legs. Pivot at the hip, sole exactly on the ground plane.
        for (name, side) in [(Part.legL, Float(-1)), (Part.legR, Float(1))] {
            var builder = FlatMeshBuilder()
            addPrism(
                &builder,
                from: Section([0, -spec.hipHeight, -0.02], spec.legWidth * 0.92, spec.footDepth),
                to: Section([0, 0, 0], spec.legWidth, spec.legDepth),
                capBottom: true,
                capTop: false
            )
            let leg = makePart(
                name,
                mesh: "\(spec.qualifier).\(name)",
                builder,
                matte(livery.plate, roughness: 0.88)
            )
            leg.position = [side * spec.hipSpread, spec.hipHeight, 0]
            root.addChild(leg)
        }

        // MARK: Torso. Hem below the pivot, chest above it, so a pitch about
        // local X swings the whole upper body from the waist.
        let waistHeight = spec.shoulderHeight * 0.32
        var torsoBuilder = FlatMeshBuilder()
        addPrism(
            &torsoBuilder,
            from: Section([0, -spec.hemDrop, 0], spec.waistWidth * livery.hemFlare, spec.bodyDepth * 1.10),
            to: Section([0, waistHeight, 0], spec.waistWidth, spec.bodyDepth * 0.92),
            capBottom: true,
            capTop: false
        )
        addPrism(
            &torsoBuilder,
            from: Section([0, waistHeight, 0], spec.waistWidth, spec.bodyDepth * 0.92),
            to: Section([0, spec.shoulderHeight, 0], spec.shoulderWidth, spec.bodyDepth),
            capBottom: false,
            capTop: true
        )
        let torso = makePart(
            Part.torso,
            mesh: "\(spec.qualifier).torso",
            torsoBuilder,
            matte(livery.cloth, roughness: 0.95)
        )
        torso.position = [0, spec.hipHeight, 0]
        root.addChild(torso)

        // MARK: Head. Height is whatever is left between the collar and the
        // authored crown, so the scale contract holds exactly.
        let headBase = spec.shoulderHeight - 0.04
        let headHeight = max(spec.crownHeight - spec.hipHeight - headBase, 0.12)
        let tilt = random.float(in: -0.012...0.012)
        var headBuilder = FlatMeshBuilder()
        addPrism(
            &headBuilder,
            from: Section([0, 0, 0], spec.waistWidth * 0.42, spec.bodyDepth * 0.52),
            to: Section([0, headHeight * 0.70, tilt], spec.waistWidth * 0.60, spec.bodyDepth * 0.70),
            capBottom: false,
            capTop: false
        )
        addPyramid(
            &headBuilder,
            base: Section([0, headHeight * 0.70, tilt], spec.waistWidth * 0.60, spec.bodyDepth * 0.70),
            apex: [0, headHeight, tilt + 0.01]
        )
        let head = makePart(
            Part.head,
            mesh: "\(spec.qualifier).head",
            headBuilder,
            matte(livery.cloth, roughness: 0.9)
        )
        head.position = [0, headBase, 0]
        torso.addChild(head)

        // MARK: Arms. Pivot at the shoulder, hanging to the hand.
        let shoulderOffset = spec.shoulderWidth * 0.5 + spec.armWidth * 0.42
        var arms: [String: Entity] = [:]
        for (name, side) in [(Part.armL, Float(-1)), (Part.armR, Float(1))] {
            var builder = FlatMeshBuilder()
            addPrism(
                &builder,
                from: Section([side * 0.015, -spec.armLength, 0.03], spec.armWidth * 0.84, spec.armWidth * 0.92),
                to: Section([0, 0, 0], spec.armWidth, spec.armWidth * 1.06),
                capBottom: true,
                capTop: false
            )
            let arm = makePart(
                name,
                mesh: "\(spec.qualifier).\(name)",
                builder,
                matte(livery.plate, roughness: 0.88)
            )
            arm.position = [side * shoulderOffset, spec.shoulderHeight - 0.06, 0]
            torso.addChild(arm)
            arms[name] = arm
        }

        // MARK: Pauldrons — armoured shoulders, for the units that carry them.
        if spec.hasPauldrons {
            for side in [Float(-1), Float(1)] {
                var builder = FlatMeshBuilder()
                addPrism(
                    &builder,
                    from: Section([side * 0.03, -0.13, 0], spec.armWidth * 1.7, spec.bodyDepth * 0.86),
                    to: Section([0, 0.06, 0], spec.armWidth * 2.1, spec.bodyDepth * 0.96),
                    capBottom: false,
                    capTop: false
                )
                let pauldron = makePart(
                    side < 0 ? "pauldronL" : "pauldronR",
                    mesh: "\(spec.qualifier).pauldron\(side < 0 ? "L" : "R")",
                    builder,
                    matte(livery.plate, roughness: 0.8)
                )
                pauldron.position = [side * shoulderOffset, spec.shoulderHeight - 0.02, 0]
                torso.addChild(pauldron)
            }
        }

        torso.addChild(makeTrim(spec: spec, livery: livery))
        torso.addChild(makeLume(spec: spec, livery: livery))

        return Biped(
            root: root,
            torso: torso,
            armLeft: arms[Part.armL] ?? torso,
            armRight: arms[Part.armR] ?? torso,
            spec: spec
        )
    }

    /// Faction trim on the chest. A woven sash runs on the diagonal; plated
    /// armour is a hard rectangular cuirass with a belt band. Same triangle
    /// cost, opposite reading.
    private static func makeTrim(spec: BipedSpec, livery: Livery) -> Entity {
        let front = -(spec.bodyDepth * 0.5 + 0.006)
        let top = spec.shoulderHeight * 0.92
        let bottom = spec.shoulderHeight * 0.24
        let band = spec.shoulderWidth * 0.14

        var builder = FlatMeshBuilder()
        switch livery.silhouette {
        case .woven:
            addQuad(
                &builder,
                [spec.shoulderWidth * 0.28 + band, top, front],
                [spec.shoulderWidth * 0.28 - band, top, front],
                [-spec.shoulderWidth * 0.24 - band, bottom, front],
                [-spec.shoulderWidth * 0.24 + band, bottom, front],
                facing: [0, 0, -1]
            )
            addQuad(
                &builder,
                [-spec.waistWidth * 0.46, bottom - 0.03, front],
                [spec.waistWidth * 0.46, bottom - 0.03, front],
                [spec.waistWidth * 0.42, bottom - 0.10, front],
                [-spec.waistWidth * 0.42, bottom - 0.10, front],
                facing: [0, 0, -1]
            )
        case .plated:
            addQuad(
                &builder,
                [-spec.shoulderWidth * 0.32, top, front],
                [spec.shoulderWidth * 0.32, top, front],
                [spec.shoulderWidth * 0.26, bottom, front],
                [-spec.shoulderWidth * 0.26, bottom, front],
                facing: [0, 0, -1]
            )
            addQuad(
                &builder,
                [-spec.waistWidth * 0.50, bottom - 0.04, front],
                [spec.waistWidth * 0.50, bottom - 0.04, front],
                [spec.waistWidth * 0.50, bottom - 0.11, front],
                [-spec.waistWidth * 0.50, bottom - 0.11, front],
                facing: [0, 0, -1]
            )
        }

        return makePart(
            "trim",
            mesh: "\(spec.qualifier).trim",
            builder,
            matte(livery.accent, roughness: 0.75)
        )
    }

    /// The single self-luminous accent every unit carries: a woven collar mote
    /// for Sunwoven, a mineral seam for Gravemark. Small on purpose — the bible
    /// keeps saturated glow for alerts, not for ambient unit chrome.
    private static func makeLume(spec: BipedSpec, livery: Livery) -> Entity {
        let front = -(spec.bodyDepth * 0.5 + 0.010)
        let top = spec.shoulderHeight * 0.86
        var builder = FlatMeshBuilder()
        switch livery.silhouette {
        case .woven:
            addQuad(
                &builder,
                [-spec.shoulderWidth * 0.16, top, front],
                [spec.shoulderWidth * 0.16, top, front],
                [spec.shoulderWidth * 0.12, top - 0.05, front],
                [-spec.shoulderWidth * 0.12, top - 0.05, front],
                facing: [0, 0, -1]
            )
        case .plated:
            addQuad(
                &builder,
                [-spec.shoulderWidth * 0.05, top, front],
                [spec.shoulderWidth * 0.05, top, front],
                [spec.shoulderWidth * 0.05, top - 0.22, front],
                [-spec.shoulderWidth * 0.05, top - 0.22, front],
                facing: [0, 0, -1]
            )
        }
        return makePart("lume", mesh: "\(spec.qualifier).lume", builder, glow(livery.lume))
    }

    // MARK: - Livery

    private enum Silhouette {
        /// Sunwoven: cloth, drape, light lattice.
        case woven
        /// Gravemark: plate, stacked mass, bunker edges.
        case plated
    }

    private struct Livery {
        let cloth: UIColor
        let plate: UIColor
        let accent: UIColor
        let lume: UIColor
        let silhouette: Silhouette

        /// Side-to-side and front-to-back mass multiplier. Never applied to a
        /// height, so the scale contract is unaffected by faction.
        var bulk: Float { silhouette == .plated ? 1.10 : 1.0 }
        /// How far the hem flares past the waist. A robe, or a plated skirt.
        var hemFlare: Float { silhouette == .woven ? 1.32 : 1.06 }

        static func of(_ faction: Faction) -> Livery {
            switch faction {
            case .sunwoven:
                Livery(
                    cloth: SunfoldPalette.sunwovenIvory,
                    plate: SunfoldPalette.sunwovenSurface,
                    accent: SunfoldPalette.sunwovenGold,
                    lume: SunfoldPalette.sunwovenTurquoise,
                    silhouette: .woven
                )
            case .gravemark:
                Livery(
                    cloth: SunfoldPalette.gravemarkSurface,
                    plate: SunfoldPalette.gravemarkRock,
                    accent: SunfoldPalette.gravemarkCopper,
                    lume: SunfoldPalette.gravemarkMineral,
                    silhouette: .plated
                )
            }
        }
    }

    // MARK: - Materials

    private static func matte(_ color: UIColor, roughness: Float) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: color)
        material.roughness = .init(floatLiteral: roughness)
        material.metallic = .init(floatLiteral: 0.0)
        material.faceCulling = .none
        return material
    }

    /// Reserved for the self-luminous accents. Everything else is lit.
    private static func glow(_ color: UIColor) -> UnlitMaterial {
        var material = UnlitMaterial(color: color)
        material.faceCulling = .none
        return material
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
