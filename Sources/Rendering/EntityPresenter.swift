import Foundation
import RealityKit
import UIKit
import simd

/// Projects simulation entities into the RealityKit scene.
///
/// This is a one-way mirror: it reads simulation truth and player selection, and
/// writes entity transforms. It never decides a rule, never moves a unit, and
/// never invents a position the simulation does not already hold.
@MainActor
final class EntityPresenter {

    let root = Entity()

    private var unitEntities: [EntityID: Entity] = [:]
    private var buildingEntities: [EntityID: Entity] = [:]
    private var depositEntities: [EntityID: Entity] = [:]

    /// Gait and facing state, one per unit, keyed by durable ID so a unit keeps
    /// its walk phase across any spawn or removal elsewhere.
    private var locomotion: [EntityID: LocomotionState] = [:]
    /// Authored rest height of each unit's torso, so bob is applied as an offset
    /// rather than overwriting the mesh's own proportions.
    private var torsoRestHeight: [EntityID: Float] = [:]

    private var selectionRings: [EntityID: Entity] = [:]
    private var orderMarker: Entity?

    /// Soft build-ghost footprint entity (CP-G2a).
    private var buildGhostEntity: Entity?
    /// Progress rings for incomplete foundations.
    private var constructionRings: [EntityID: Entity] = [:]
    /// Brief gold flash entities when a building completes.
    private var completionFlashes: [EntityID: (entity: Entity, until: Double)] = [:]

    /// The load a citizen is carrying, and which kind it is currently tinted for,
    /// so the material is only rebuilt when the resource actually changes.
    private var cargoPacks: [EntityID: Entity] = [:]
    private var cargoKinds: [EntityID: ResourceKind] = [:]
    /// One box shared by every pack — the shape never varies, only its tint.
    private var sharedCargoMesh: MeshResource?

    private let seed: UInt64
    private let unitScale: Float
    /// Carry capacity, so the pack can show how close to full a load is.
    private let cargoFullAt: Double

    init(seed: UInt64, tuning: SkirmishTuning) {
        self.seed = seed
        self.unitScale = tuning.unitVisualScale
        self.cargoFullAt = tuning.carryCapacity
        root.name = "world.entities"
    }

    /// Reconciles the scene with simulation state for this frame.
    func sync(
        simulation: SkirmishSimulation,
        selection: SelectionModel,
        deltaTime: Double,
        reducedMotion: Bool,
        buildGhost: ConstructionPlacement.Session? = nil,
        completionFlashes justFinished: Set<EntityID> = []
    ) {
        syncBuildings(simulation)
        syncDeposits(simulation)
        syncUnits(simulation, deltaTime: deltaTime, reducedMotion: reducedMotion)
        syncSelection(simulation, selection)
        syncOrderMarker(simulation, selection)
        syncConstructionProgress(simulation)
        syncCompletionFlashes(justFinished, simulation: simulation, now: simulation.elapsed)
        syncBuildGhost(buildGhost, map: simulation.map, now: simulation.elapsed)
    }

    // MARK: - Units

    private func syncUnits(_ simulation: SkirmishSimulation, deltaTime: Double, reducedMotion: Bool) {
        for (id, unit) in simulation.units {
            let entity = unitEntities[id] ?? makeUnitEntity(for: unit, id: id)

            var walk = locomotion[id] ?? LocomotionState(id: id, position: unit.position, facing: unit.facing)
            walk.reducedMotion = reducedMotion
            walk.update(deltaTime: deltaTime, position: unit.position)
            locomotion[id] = walk

            // A unit aboard a transport is cargo: hide it rather than leaving it
            // standing on the void where its hull used to be.
            entity.isEnabled = !unit.isAboard
            // Sampled every frame, not once: a unit walks across the relief, so
            // its footing changes as it moves. The simulation's position stays
            // planar — this only decides where that position is drawn.
            entity.position = TerrainSurface.standing(at: unit.position, in: simulation.map)
            entity.orientation = simd_quatf(angle: walk.facing, axis: [0, 1, 0])
            applyPose(walk.pose, to: entity, id: id)
            syncCargo(unit, on: entity, id: id)
        }

        removeStale(from: &unitEntities, keeping: simulation.units.keys) { id in
            self.locomotion[id] = nil
            self.torsoRestHeight[id] = nil
            self.selectionRings[id] = nil
            self.cargoPacks[id] = nil
            self.cargoKinds[id] = nil
        }
    }

    private func makeUnitEntity(for unit: Unit, id: EntityID) -> Entity {
        let entity: Entity
        switch unit.kind {
        case .citizen: entity = UnitMeshes.citizen(faction: unit.faction, seed: seed &+ UInt64(id.raw))
        case .pathfinder: entity = UnitMeshes.pathfinder(faction: unit.faction, seed: seed &+ UInt64(id.raw))
        case .vanguard: entity = UnitMeshes.vanguard(faction: unit.faction, seed: seed &+ UInt64(id.raw))
        case .ranged: entity = UnitMeshes.ranged(faction: unit.faction, seed: seed &+ UInt64(id.raw))
        case .bastionWalker: entity = UnitMeshes.bastionWalker(seed: seed &+ UInt64(id.raw))
        case .lightTransport: entity = TransportMesh.lightTransport(
            faction: unit.faction, seed: seed &+ UInt64(id.raw)
        )
        }

        entity.name = "unit.\(unit.kind.rawValue).\(id.raw)"
        entity.scale = .init(repeating: unitScale)
        if let torso = entity.findEntity(named: UnitMeshes.Part.torso) {
            torsoRestHeight[id] = torso.position.y
        }

        // The ring is a child, so it inherits the unit's scale. Dividing it out
        // here lands the ring at the world radius the picker actually uses —
        // otherwise the visible ring and the tappable area drift apart by the
        // square of the scale.
        let ring = makeSelectionRing(
            radius: (unit.kind.footprintRadius + 0.35) / unitScale,
            faction: unit.faction
        )
        ring.isEnabled = false
        entity.addChild(ring)
        selectionRings[id] = ring

        unitEntities[id] = entity
        root.addChild(entity)
        return entity
    }

    /// Applies the gait rig. Rotations are used exactly as the locomotion layer
    /// publishes them — it already accounts for the sign convention that a
    /// positive turn about +X swings a hanging limb forward.
    private func applyPose(_ pose: LimbPose, to entity: Entity, id: EntityID) {
        func rotate(_ name: String, _ pitch: Float) {
            entity.findEntity(named: name)?.orientation = simd_quatf(angle: pitch, axis: [1, 0, 0])
        }

        rotate(UnitMeshes.Part.legL, pose.legLeftPitch)
        rotate(UnitMeshes.Part.legR, pose.legRightPitch)
        rotate(UnitMeshes.Part.legLRear, pose.rearLegLeftPitch)
        rotate(UnitMeshes.Part.legRRear, pose.rearLegRightPitch)
        rotate(UnitMeshes.Part.armL, pose.armLeftPitch)
        rotate(UnitMeshes.Part.armR, pose.armRightPitch)

        guard let torso = entity.findEntity(named: UnitMeshes.Part.torso) else { return }
        torso.orientation = simd_quatf(angle: pose.torsoPitch, axis: [1, 0, 0])
            * simd_quatf(angle: pose.torsoYaw, axis: [0, 1, 0])
        if let rest = torsoRestHeight[id] {
            torso.position.y = rest + pose.bob
        }
    }

    /// A load on the citizen's back, tinted to what it is carrying.
    ///
    /// Without this the gather loop is invisible: a citizen walking home with
    /// ten Matter looks exactly like a citizen walking home with nothing, and the
    /// only evidence the economy is running is a number ticking up. The pack is
    /// the readable half of the whole first-hearth loop.
    private func syncCargo(_ unit: Unit, on entity: Entity, id: EntityID) {
        guard let cargo = unit.cargo else {
            cargoPacks[id]?.isEnabled = false
            return
        }

        let pack = cargoPacks[id] ?? makeCargoPack(on: entity, id: id)
        pack.isEnabled = true

        // The pack grows with the load, so "nearly full" is visible from the
        // camera without any UI at all.
        let fill = Float(min(cargo.amount / cargoFullAt, 1))
        pack.scale = .init(repeating: 0.55 + 0.45 * fill)

        if cargoKinds[id] != cargo.kind {
            cargoKinds[id] = cargo.kind
            pack.components.set(
                ModelComponent(
                    mesh: cargoMesh(),
                    materials: [
                        StructureMaterial.matte(
                            SunfoldPalette.resourceTint(cargo.kind),
                            surface: Self.cargoSurface(cargo.kind)
                        )
                    ]
                )
            )
        }
    }

    /// A carried load is made of the same stuff as the deposit it came from, so
    /// it takes the deposit's surface class rather than being classified from
    /// its tint. Provisions in particular must not land on the gold-trim
    /// surface: the resource tint is a hair from `sunwovenGold`, and a bushel
    /// rendered as burnished metal is the one reading that would be wrong.
    private static func cargoSurface(_ kind: ResourceKind) -> MaterialLibrary.Surface {
        switch kind {
        case .provisions: .growth
        case .matter: .rawMatter
        case .lumen: .crystallineLumen
        case .aether: .crystallineAether
        }
    }

    private func makeCargoPack(on entity: Entity, id: EntityID) -> Entity {
        let pack = Entity()
        pack.name = "unit.cargo"
        // Ride the torso, so the pack inherits the walk bob and lean rather than
        // floating along at a fixed height beside the citizen.
        let host = entity.findEntity(named: UnitMeshes.Part.torso) ?? entity
        host.addChild(pack)
        pack.position = [0, 0.42, 0.24]
        cargoPacks[id] = pack
        return pack
    }

    private func cargoMesh() -> MeshResource {
        if let cached = sharedCargoMesh { return cached }
        var builder = StructureBuilder()
        let lower = StructureGeometry.rectangle(width: 0.44, depth: 0.30, y: 0)
        let upper = StructureGeometry.rectangle(width: 0.36, depth: 0.24, y: 0.40)
        builder.addSolid(lower: lower, upper: upper, capTop: true, capBottom: true)
        let mesh = builder.makeEntity(named: "cargo", material: UnlitMaterial())?
            .components[ModelComponent.self]?.mesh
        sharedCargoMesh = mesh ?? MeshResource.generateBox(size: 0.4)
        return sharedCargoMesh!
    }

    // MARK: - Buildings

    private func syncBuildings(_ simulation: SkirmishSimulation) {
        for (id, building) in simulation.buildings {
            if buildingEntities[id] == nil {
                let entity = makeBuildingEntity(for: building, id: id)
                entity.name = "building.\(building.kind.rawValue).\(id.raw)"
                entity.position = TerrainSurface.standing(at: building.position, in: simulation.map)
                buildingEntities[id] = entity
                root.addChild(entity)
            }
            guard let entity = buildingEntities[id] else { continue }
            // Incomplete foundations read as rising out of the ground.
            let progress = Float(building.constructionProgress)
            let rise = 0.35 + 0.65 * progress
            entity.scale = [rise, rise, rise]
            entity.isEnabled = true
        }
        removeStale(from: &buildingEntities, keeping: simulation.buildings.keys) { id in
            constructionRings[id]?.removeFromParent()
            constructionRings[id] = nil
        }
    }

    private func syncConstructionProgress(_ simulation: SkirmishSimulation) {
        for (id, building) in simulation.buildings {
            guard !building.isComplete else {
                constructionRings[id]?.isEnabled = false
                continue
            }
            let progress = Float(building.constructionProgress)
            let ring = constructionRings[id] ?? {
                let created = makeConstructionRing(
                    radius: max(building.kind.footprintRadius * 1.05, 2.4)
                )
                created.name = "feedback.construction.\(id.raw)"
                root.addChild(created)
                constructionRings[id] = created
                return created
            }()
            ring.isEnabled = true
            ring.position = TerrainSurface.standing(
                at: building.position, in: simulation.map, lift: 0.12
            )
            // Arc fills as progress climbs; slight pulse so activity is felt.
            let pulse = 1 + 0.04 * sin(Float(simulation.elapsed) * 6)
            ring.scale = [pulse, 1, pulse]
            if var model = ring.components[ModelComponent.self] {
                let alpha = 0.35 + 0.45 * progress
                var material = UnlitMaterial(
                    color: SunfoldPalette.sunwovenGold.withAlphaComponent(CGFloat(alpha))
                )
                material.blending = .transparent(opacity: .init(floatLiteral: alpha))
                model.materials = [material]
                ring.components.set(model)
            }
        }
        for id in constructionRings.keys where simulation.buildings[id] == nil
            || simulation.buildings[id]?.isComplete == true {
            constructionRings[id]?.removeFromParent()
            constructionRings[id] = nil
        }
    }

    private func syncCompletionFlashes(
        _ justFinished: Set<EntityID>,
        simulation: SkirmishSimulation,
        now: Double
    ) {
        for id in justFinished {
            guard let building = simulation.building(id) else { continue }
            let flash = makeCompletionFlash(
                radius: max(building.kind.footprintRadius * 1.3, 3.0)
            )
            flash.name = "feedback.complete.\(id.raw)"
            flash.position = TerrainSurface.standing(
                at: building.position, in: simulation.map, lift: 0.2
            )
            root.addChild(flash)
            completionFlashes[id] = (flash, now + 0.85)
        }

        for (id, entry) in completionFlashes {
            let age = Float(max(0, entry.until - now))
            if age <= 0 {
                entry.entity.removeFromParent()
                completionFlashes[id] = nil
                continue
            }
            let t = age / 0.85
            let expand = 1.0 + (1.0 - t) * 0.55
            entry.entity.scale = [expand, 1, expand]
            if var model = entry.entity.components[ModelComponent.self] {
                let alpha = 0.55 * t
                var material = UnlitMaterial(
                    color: SunfoldPalette.sunwovenGold.withAlphaComponent(CGFloat(alpha))
                )
                material.blending = .transparent(opacity: .init(floatLiteral: Float(alpha)))
                model.materials = [material]
                entry.entity.components.set(model)
            }
        }
    }

    private func makeConstructionRing(radius: Float) -> Entity {
        let entity = Entity()
        entity.components.set(
            ModelComponent(
                mesh: makeBuildGhostDiscMesh(radius: radius),
                materials: [UnlitMaterial(color: .white)]
            )
        )
        return entity
    }

    private func makeCompletionFlash(radius: Float) -> Entity {
        let entity = Entity()
        entity.components.set(
            ModelComponent(
                mesh: makeBuildGhostDiscMesh(radius: radius),
                materials: [UnlitMaterial(color: .white)]
            )
        )
        return entity
    }

    private func makeBuildingEntity(for building: Building, id: EntityID) -> Entity {
        let entitySeed = seed &+ UInt64(id.raw)
        switch building.kind {
        case .civilizationCore:
            return CivilizationCoreMesh.make(faction: building.faction, seed: entitySeed)
        case .farm:
            return BuildingMeshes.farm(faction: building.faction, seed: entitySeed)
        case .matterExtractor:
            return BuildingMeshes.matterExtractor(faction: building.faction, seed: entitySeed)
        case .dwelling:
            return BuildingMeshes.dwelling(faction: building.faction, seed: entitySeed)
        case .formationYard:
            return BuildingMeshes.formationYard(faction: building.faction, seed: entitySeed)
        case .expansionOutpost:
            return BuildingMeshes.expansionOutpost(faction: building.faction, seed: entitySeed)
        case .dawnLoom:
            // The Voyager landmark arrives with G4. Fail closed: show something
            // readable and say so, rather than rendering nothing.
            DebugLog.warn("Dawn Loom mesh not authored yet; using Core silhouette.")
            return CivilizationCoreMesh.make(faction: building.faction, seed: entitySeed)
        }
    }

    // MARK: - Deposits

    private func syncDeposits(_ simulation: SkirmishSimulation) {
        for (id, deposit) in simulation.deposits where depositEntities[id] == nil {
            let entitySeed = seed &+ UInt64(id.raw)
            let entity: Entity
            switch deposit.kind {
            case .matter: entity = DepositMeshes.matter(seed: entitySeed)
            case .lumen: entity = DepositMeshes.lumen(seed: entitySeed)
            case .aether: entity = DepositMeshes.aether(seed: entitySeed)
            case .provisions: entity = DepositMeshes.provisions(seed: entitySeed)
            }
            entity.name = "deposit.\(deposit.kind.rawValue).\(id.raw)"
            entity.position = TerrainSurface.standing(at: deposit.position, in: simulation.map)
            depositEntities[id] = entity
            root.addChild(entity)
        }
        removeStale(from: &depositEntities, keeping: simulation.deposits.keys) { _ in }
    }

    // MARK: - Selection feedback

    private func syncSelection(_ simulation: SkirmishSimulation, _ selection: SelectionModel) {
        for (id, ring) in selectionRings {
            ring.isEnabled = selection.selectedUnits.contains(id)
        }
    }

    private func syncOrderMarker(_ simulation: SkirmishSimulation, _ selection: SelectionModel) {
        guard let marker = selection.lastOrderMarker else {
            orderMarker?.isEnabled = false
            return
        }

        let entity = orderMarker ?? {
            let created = makeSelectionRing(radius: 1.6, faction: .sunwoven)
            created.name = "feedback.destination"
            root.addChild(created)
            orderMarker = created
            return created
        }()

        // A short outward pulse, so a confirmed order is felt rather than guessed.
        let age = Float(max(simulation.elapsed - marker.issuedAt, 0))
        let pulse = 1 + min(age, 0.6) * 1.1
        entity.isEnabled = true
        entity.position = TerrainSurface.standing(at: marker.position, in: simulation.map, lift: 0.04)
        entity.scale = [pulse, 1, pulse]
    }

    // MARK: - Build ghost (Soft, shipping)

    private func syncBuildGhost(
        _ session: ConstructionPlacement.Session?,
        map: WorldMap,
        now: Double
    ) {
        guard let session else {
            buildGhostEntity?.isEnabled = false
            return
        }

        let entity = buildGhostEntity ?? {
            let created = Entity()
            created.name = "placement.ghost"
            root.addChild(created)
            buildGhostEntity = created
            return created
        }()

        let denying = now < session.denyUntil
        let placing = now < session.placeUntil

        // Soft palette — locked feel from #11, Sunfold colours.
        let color: UIColor
        if denying {
            color = UIColor(red: 0.90, green: 0.32, blue: 0.26, alpha: 1)
        } else if placing {
            color = SunfoldPalette.sunwovenGold
        } else if session.isLegal {
            color = SunfoldPalette.sunwovenTurquoise
        } else {
            color = UIColor(red: 0.85, green: 0.35, blue: 0.28, alpha: 1)
        }

        let opacity: CGFloat = session.isLegal ? 0.70 : 0.65
        var material = UnlitMaterial(color: color.withAlphaComponent(opacity))
        material.blending = .transparent(opacity: .init(floatLiteral: Float(opacity)))

        let shapeKey = session.kind.rawValue
        if entity.name != "placement.ghost.\(shapeKey)" {
            entity.name = "placement.ghost.\(shapeKey)"
            if let half = ConstructionPlacement.halfExtents(for: session.kind) {
                entity.components.set(
                    ModelComponent(
                        mesh: makeBuildGhostRectMesh(halfWidth: half.x, halfDepth: half.y),
                        materials: [material]
                    )
                )
            } else {
                entity.components.set(
                    ModelComponent(
                        mesh: makeBuildGhostDiscMesh(radius: 1),
                        materials: [material]
                    )
                )
            }
        } else if var model = entity.components[ModelComponent.self] {
            model.materials = [material]
            entity.components.set(model)
        }

        entity.isEnabled = true
        entity.position = TerrainSurface.standing(at: session.position, in: map, lift: 0.35)
        if ConstructionPlacement.halfExtents(for: session.kind) != nil {
            entity.scale = [1, 1, 1]
        } else {
            let visualScale = max(session.kind.footprintRadius * 1.15, 2.2)
            entity.scale = [visualScale, 1, visualScale]
        }
    }

    private func makeBuildGhostDiscMesh(radius: Float) -> MeshResource {
        var builder = FlatMeshBuilder()
        let segments = 36
        let up = SIMD3<Float>(0, 1, 0)
        for index in 0..<segments {
            let a = Float(index) / Float(segments) * 2 * .pi
            let b = Float(index + 1) / Float(segments) * 2 * .pi
            let outerA = SIMD3<Float>(cos(a) * radius, 0, sin(a) * radius)
            let outerB = SIMD3<Float>(cos(b) * radius, 0, sin(b) * radius)
            builder.addTriangle(.zero, outerA, outerB, facing: up)
        }
        let inner = radius * 0.82
        for index in 0..<segments {
            let a = Float(index) / Float(segments) * 2 * .pi
            let b = Float(index + 1) / Float(segments) * 2 * .pi
            let outerA = SIMD3<Float>(cos(a) * radius, 0.01, sin(a) * radius)
            let outerB = SIMD3<Float>(cos(b) * radius, 0.01, sin(b) * radius)
            let innerA = SIMD3<Float>(cos(a) * inner, 0.01, sin(a) * inner)
            let innerB = SIMD3<Float>(cos(b) * inner, 0.01, sin(b) * inner)
            builder.addTriangle(innerA, outerA, outerB, facing: up)
            builder.addTriangle(innerA, outerB, innerB, facing: up)
        }
        return builder.makeMesh(named: "placement.ghost.disc")
    }

    private func makeBuildGhostRectMesh(halfWidth: Float, halfDepth: Float) -> MeshResource {
        var builder = FlatMeshBuilder()
        let up = SIMD3<Float>(0, 1, 0)
        let hw = halfWidth
        let hd = halfDepth
        let corners = [
            SIMD3<Float>(-hw, 0, -hd),
            SIMD3<Float>( hw, 0, -hd),
            SIMD3<Float>( hw, 0,  hd),
            SIMD3<Float>(-hw, 0,  hd)
        ]
        builder.addTriangle(corners[0], corners[1], corners[2], facing: up)
        builder.addTriangle(corners[0], corners[2], corners[3], facing: up)

        let inset: Float = 0.82
        let inner = [
            SIMD3<Float>(-hw * inset, 0.01, -hd * inset),
            SIMD3<Float>( hw * inset, 0.01, -hd * inset),
            SIMD3<Float>( hw * inset, 0.01,  hd * inset),
            SIMD3<Float>(-hw * inset, 0.01,  hd * inset)
        ]
        let outer = [
            SIMD3<Float>(-hw, 0.01, -hd),
            SIMD3<Float>( hw, 0.01, -hd),
            SIMD3<Float>( hw, 0.01,  hd),
            SIMD3<Float>(-hw, 0.01,  hd)
        ]
        for i in 0..<4 {
            let j = (i + 1) % 4
            builder.addTriangle(inner[i], outer[i], outer[j], facing: up)
            builder.addTriangle(inner[i], outer[j], inner[j], facing: up)
        }
        return builder.makeMesh(named: "placement.ghost.rect")
    }

    // MARK: - Shared geometry

    /// A flat annulus that sits on the ground under a selected entity.
    private func makeSelectionRing(radius: Float, faction: Faction) -> Entity {
        let entity = Entity()
        entity.name = "selection.ring"

        // No UV projection, deliberately. The ring is a UI affordance, not a
        // surface: it is drawn with an `UnlitMaterial` so it stays equally
        // readable in shadow and in the key light, and an unlit material samples
        // no texture. Emitting coordinates for it would cost three extra vertex
        // buffers per selected unit and change nothing on screen.
        var builder = FlatMeshBuilder()
        let segments = 28
        let inner = radius * 0.82
        let up = SIMD3<Float>(0, 1, 0)

        for index in 0..<segments {
            let a = Float(index) / Float(segments) * 2 * .pi
            let b = Float(index + 1) / Float(segments) * 2 * .pi
            let outerA = SIMD3<Float>(cos(a) * radius, 0, sin(a) * radius)
            let outerB = SIMD3<Float>(cos(b) * radius, 0, sin(b) * radius)
            let innerA = SIMD3<Float>(cos(a) * inner, 0, sin(a) * inner)
            let innerB = SIMD3<Float>(cos(b) * inner, 0, sin(b) * inner)
            builder.addTriangle(innerA, outerA, outerB, facing: up)
            builder.addTriangle(innerA, outerB, innerB, facing: up)
        }

        let tint = faction == .sunwoven
            ? SunfoldPalette.sunwovenTurquoise
            : SunfoldPalette.gravemarkCopper
        let material = StructureMaterial.glow(tint, opacity: 0.85)
        entity.components.set(
            ModelComponent(mesh: builder.makeMesh(named: "selection.ring"), materials: [material])
        )
        entity.position = [0, 0.03, 0]
        return entity
    }

    // MARK: - Housekeeping

    private func removeStale(
        from table: inout [EntityID: Entity],
        keeping live: some Sequence<EntityID>,
        onRemove: (EntityID) -> Void
    ) {
        let liveSet = Set(live)
        for (id, entity) in table where !liveSet.contains(id) {
            entity.removeFromParent()
            table[id] = nil
            onRemove(id)
        }
    }
}
