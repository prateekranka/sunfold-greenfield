import Foundation
import RealityKit
import UIKit
import simd

/// The four gatherable resource nodes.
///
/// Deposits share one deliberate cue that scenery never gets: a **low luminous
/// pool on the ground at the node's base**, tinted to the resource. That single
/// piece of shared grammar is what lets a player scan a fragment and separate
/// "this is harvestable" from "this is landscape", before any selection ring or
/// HUD affordance is involved. Each kind then differs in form:
///
/// - **Matter** — a wide cluster of faceted grey boulders with two pale mineral
///   shards pushed up through it. Grounded, heavy, spread across ~4 m.
/// - **Lumen** — a fan of tapered gold crystals rising off a rock collar, with
///   a self-luminous inner core. Vertical and bright, ~3.5 m.
/// - **Aether** — a small outcrop with shards and motes *floating free above it*
///   on turquoise wisps. Nothing else in the world levitates; that is the point.
/// - **Provisions** — a low saffron scrub: a soil mound with a spray of folded
///   fronds and seed pods, ~2 m and knee-high to a citizen.
///
/// Every cluster is jittered from its own deterministic stream, so no two nodes
/// on a map are the same stamped copy while a given seed always rebuilds
/// identically.
@MainActor
enum DepositMeshes {

    // MARK: - Matter

    /// ~4 m across, ~1.7 m tall.
    static func matter(seed: UInt64) -> Entity {
        var random = DeterministicRandom.stream(seed: seed, tag: "deposit.matter")

        var rock = StructureBuilder()
        var stone = StructureBuilder()
        var crystal = StructureBuilder()
        var glow = StructureBuilder()

        // Two heavy boulders and two lighter ones, arranged around the centre so
        // the cluster has a readable mass on one side rather than a ring.
        let anchors: [(SIMD2<Float>, Float, Float, Int, Bool)] = [
            ([-0.55, -0.25], 1.05, 1.62, 6, true),
            ([0.72, 0.38], 0.86, 1.24, 6, true),
            ([-0.15, 1.02], 0.68, 0.86, 5, false),
            ([1.05, -0.78], 0.60, 0.74, 5, false),
        ]
        for (center, radius, height, sides, heavy) in anchors {
            let jitter = SIMD2<Float>(random.float(in: -0.18...0.18), random.float(in: -0.18...0.18))
            if heavy {
                rock.addBoulder(
                    center: center + jitter,
                    radius: radius, height: height * random.float(in: 0.90...1.10),
                    sides: sides, random: &random
                )
            } else {
                stone.addBoulder(
                    center: center + jitter,
                    radius: radius, height: height * random.float(in: 0.90...1.10),
                    sides: sides, random: &random
                )
            }
        }

        // Chips at the skirt: what makes a cluster read as broken rock rather
        // than as a few objects dropped on the ground.
        for index in 0..<2 {
            let angle = random.float(in: 0...(2 * .pi))
            let distance = 1.45 + Float(index) * 0.18
            stone.addBoulder(
                center: [cos(angle) * distance, sin(angle) * distance],
                radius: 0.34, height: random.float(in: 0.26...0.42),
                sides: 4, random: &random
            )
        }

        // Two pale shards breaking the boulder line — the "there is something in
        // this rock" cue.
        for index in 0..<2 {
            let angle = Float(index) * 2.2 + 0.6
            crystal.addBoulder(
                center: [cos(angle) * 0.72, sin(angle) * 0.72],
                radius: 0.24, height: random.float(in: 1.15...1.55),
                sides: 4, random: &random
            )
        }

        glow.addCap(
            ring: StructureGeometry.ring(sides: 6, radius: 1.95, y: 0.035),
            pivot: [0, -0.2, 0]
        )

        return StructureAssembly.entity(
            named: "deposit.matter",
            zones: [
                StructureZone("rock", rock, StructureMaterial.matte(SunfoldPalette.neutralRock, roughness: 0.99)),
                StructureZone("stone", stone, StructureMaterial.matte(SunfoldPalette.neutralSurface, roughness: 0.97)),
                StructureZone("shard", crystal, StructureMaterial.matte(StructureMaterial.shade(SunfoldPalette.gravemarkMineral, 1.28), roughness: 0.55)),
                StructureZone("pool", glow, StructureMaterial.glow(SunfoldPalette.gravemarkMineral, opacity: 0.28)),
            ]
        )
    }

    // MARK: - Lumen

    /// ~3.5 m across, ~2.6 m tall.
    static func lumen(seed: UInt64) -> Entity {
        var random = DeterministicRandom.stream(seed: seed, tag: "deposit.lumen")

        var collar = StructureBuilder()
        var ivory = StructureBuilder()
        var gold = StructureBuilder()
        var glow = StructureBuilder()

        collar.addSolid(
            lower: StructureGeometry.ring(sides: 7, radius: 1.55, y: 0, phase: random.float(in: 0...1)),
            upper: StructureGeometry.ring(sides: 7, radius: 1.34, y: 0.26)
        )

        // Three pale crystals, splayed outward from the collar.
        for index in 0..<3 {
            let angle = Float(index) / 3 * 2 * .pi + random.float(in: -0.25...0.25)
            let distance = random.float(in: 0.55...0.86)
            ivory.addBoulder(
                center: [cos(angle) * distance, sin(angle) * distance],
                radius: random.float(in: 0.30...0.42),
                height: random.float(in: 1.45...2.15),
                sides: 4, random: &random
            )
        }

        // Two taller gold crystals form the spike of the silhouette.
        for index in 0..<2 {
            let angle = Float(index) * .pi + random.float(in: -0.4...0.4)
            let distance = random.float(in: 0.18...0.42)
            gold.addBoulder(
                center: [cos(angle) * distance, sin(angle) * distance],
                radius: random.float(in: 0.28...0.38),
                height: random.float(in: 2.05...2.55),
                sides: 4, random: &random
            )
        }

        // Self-luminous inner spikes and the ground pool.
        for index in 0..<3 {
            let angle = Float(index) / 3 * 2 * .pi + 0.9
            let distance = random.float(in: 0.40...0.70)
            glow.addBoulder(
                center: [cos(angle) * distance, sin(angle) * distance],
                radius: random.float(in: 0.13...0.20),
                height: random.float(in: 0.95...1.55),
                sides: 3, random: &random
            )
        }
        glow.addCap(
            ring: StructureGeometry.ring(sides: 7, radius: 1.72, y: 0.04),
            pivot: [0, -0.2, 0]
        )

        return StructureAssembly.entity(
            named: "deposit.lumen",
            zones: [
                StructureZone("collar", collar, StructureMaterial.matte(SunfoldPalette.neutralRock, roughness: 0.98)),
                StructureZone("crystal", ivory, StructureMaterial.matte(SunfoldPalette.sunwovenIvory, roughness: 0.48)),
                StructureZone("gold", gold, StructureMaterial.matte(SunfoldPalette.sunwovenGold, roughness: 0.45)),
                StructureZone("core", glow, StructureMaterial.glow(SunfoldPalette.sunwovenGold, opacity: 0.92)),
            ]
        )
    }

    // MARK: - Aether

    /// ~3 m across, ~2.8 m tall. The only structure in the world with parts that
    /// do not touch the ground.
    static func aether(seed: UInt64) -> Entity {
        var random = DeterministicRandom.stream(seed: seed, tag: "deposit.aether")

        var rock = StructureBuilder()
        var shard = StructureBuilder()
        var wisp = StructureBuilder()
        var glow = StructureBuilder()

        rock.addBoulder(center: [0, 0], radius: 0.92, height: random.float(in: 0.62...0.86), sides: 6, random: &random)
        rock.addBoulder(
            center: [random.float(in: 0.8...1.15), random.float(in: -0.9...0.5)],
            radius: 0.40, height: random.float(in: 0.30...0.48),
            sides: 4, random: &random
        )

        // Suspended shards. Their height is what carries the "rare" read at a
        // glance — a node that ignores the fragment's gravity.
        for index in 0..<2 {
            let angle = Float(index) * 2.6 + 0.4
            let distance = random.float(in: 0.42...0.78)
            let center = SIMD2<Float>(cos(angle) * distance, sin(angle) * distance)
            let height = random.float(in: 1.45...2.10)
            let span = random.float(in: 0.42...0.58)
            shard.addShard(
                ring: StructureGeometry.ring(sides: 4, radius: random.float(in: 0.20...0.30), y: height, phase: angle, center: center),
                top: [center.x, height + span, center.y],
                bottom: [center.x, height - span, center.y]
            )
        }

        for index in 0..<3 {
            let angle = Float(index) / 3 * 2 * .pi + 1.3
            let distance = random.float(in: 0.75...1.05)
            let center = SIMD2<Float>(cos(angle) * distance, sin(angle) * distance)
            let height = random.float(in: 0.95...2.45)
            glow.addShard(
                ring: StructureGeometry.ring(sides: 3, radius: 0.11, y: height, center: center),
                top: [center.x, height + 0.20, center.y],
                bottom: [center.x, height - 0.20, center.y]
            )
        }

        // Two rising wisps, each a short ribbon following a slow helix.
        for index in 0..<2 {
            let start = random.float(in: 0...(2 * .pi))
            let radius = random.float(in: 0.58...0.80)
            let turn = random.float(in: 1.6...2.4) * (index == 0 ? 1 : -1)

            func node(_ step: Int) -> SIMD3<Float> {
                let t = Float(step) / 4
                let angle = start + turn * t
                return [cos(angle) * radius, 0.35 + t * 2.20, sin(angle) * radius]
            }

            for step in 0..<4 {
                let low = node(step)
                let high = node(step + 1)
                let outward = StructureGeometry.direction([low.x + high.x, 0, low.z + high.z])
                let side = simd_cross([0, 1, 0], outward) * 0.085
                wisp.addQuad(low - side, low + side, high + side, high - side, facing: outward)
            }
        }

        glow.addCap(
            ring: StructureGeometry.ring(sides: 8, radius: 1.30, y: 0.04),
            pivot: [0, -0.2, 0]
        )

        return StructureAssembly.entity(
            named: "deposit.aether",
            zones: [
                StructureZone("outcrop", rock, StructureMaterial.matte(StructureMaterial.shade(SunfoldPalette.neutralRock, 0.80), roughness: 0.98)),
                StructureZone("shard", shard, StructureMaterial.matte(StructureMaterial.shade(SunfoldPalette.sunwovenTurquoise, 0.86), roughness: 0.42)),
                StructureZone("wisp", wisp, StructureMaterial.glow(SunfoldPalette.sunwovenTurquoise, opacity: 0.42)),
                StructureZone("mote", glow, StructureMaterial.glow(SunfoldPalette.sunwovenTurquoise, opacity: 0.90)),
            ]
        )
    }

    // MARK: - Provisions

    /// ~2 m across, ~1.1 m tall. Renewable, so it stays deliberately humble:
    /// no crystal, no metal, nothing that competes with a building.
    static func provisions(seed: UInt64) -> Entity {
        var random = DeterministicRandom.stream(seed: seed, tag: "deposit.provisions")

        var mound = StructureBuilder()
        var frond = StructureBuilder()
        var husk = StructureBuilder()
        var glow = StructureBuilder()

        mound.addBoulder(
            center: [0, 0], radius: 0.78,
            height: random.float(in: 0.24...0.34),
            sides: 6, random: &random
        )

        // Twelve folded fronds fanning off the mound.
        for index in 0..<12 {
            let angle = Float(index) / 12 * 2 * .pi + random.float(in: -0.22...0.22)
            let lean = random.float(in: 0.42...0.78)
            let base = SIMD3<Float>(cos(angle) * 0.22, 0.20, sin(angle) * 0.22)
            let tip = SIMD3<Float>(
                cos(angle) * lean,
                random.float(in: 0.72...1.08),
                sin(angle) * lean
            )
            let side = simd_cross([0, 1, 0], StructureGeometry.direction(tip - base)) * 0.10
            frond.addBlade(base: base, tip: tip, side: side, lift: 0.09)
        }

        // A few darker dry stalks so the spray is not one flat tone.
        for index in 0..<4 {
            let angle = Float(index) / 4 * 2 * .pi + 0.8
            let base = SIMD3<Float>(cos(angle) * 0.40, 0.16, sin(angle) * 0.40)
            let tip = base + [
                cos(angle) * random.float(in: 0.15...0.35),
                random.float(in: 0.30...0.52),
                sin(angle) * random.float(in: 0.15...0.35),
            ]
            husk.addBlade(base: base, tip: tip, side: [0.07, 0, 0], lift: 0.05)
        }

        // Seed pods.
        for index in 0..<3 {
            let angle = Float(index) / 3 * 2 * .pi + 2.0
            let center = SIMD2<Float>(cos(angle) * 0.30, sin(angle) * 0.30)
            husk.addSpire(
                base: StructureGeometry.ring(sides: 4, radius: 0.10, y: 0.30, phase: angle, center: center),
                apex: [center.x, random.float(in: 0.62...0.82), center.y]
            )
        }

        glow.addCap(
            ring: StructureGeometry.ring(sides: 6, radius: 0.98, y: 0.03),
            pivot: [0, -0.2, 0]
        )

        return StructureAssembly.entity(
            named: "deposit.provisions",
            zones: [
                StructureZone("soil", mound, StructureMaterial.matte(StructureMaterial.shade(SunfoldPalette.sunwovenRock, 0.78), roughness: 0.99)),
                StructureZone("frond", frond, StructureMaterial.matte(StructureMaterial.shade(SunfoldPalette.sunwovenGold, 1.10), roughness: 0.95)),
                StructureZone("husk", husk, StructureMaterial.matte(StructureMaterial.shade(SunfoldPalette.sunwovenGold, 0.74), roughness: 0.97)),
                StructureZone("pool", glow, StructureMaterial.glow(SunfoldPalette.sunwovenGold, opacity: 0.22)),
            ]
        )
    }
}
