import CoreGraphics
import Foundation

final class CampaignLevelBuilder {
    static let shared = CampaignLevelBuilder()
    private var cache: [Int: LevelDefinition] = [:]

    private init() {}

    func level(id: Int) -> LevelDefinition {
        let safeID = ScalarMath.clamp(id, 1, 200)
        if let cached = cache[safeID] { return cached }
        let chapter = (safeID - 1) / 20 + 1
        let index = (safeID - 1) % 20 + 1
        var random = SeededRandom(seed: UInt64(safeID) &* 0x9E3779B97F4A7C15)
        let definition: LevelDefinition
        switch chapter {
        case 1: definition = buildFoundationCourse(id: safeID, index: index, random: &random)
        case 2: definition = buildMovingWorld(id: safeID, index: index, random: &random)
        case 3: definition = buildGates(id: safeID, index: index, random: &random)
        case 4: definition = buildTileControl(id: safeID, index: index, random: &random)
        case 5: definition = buildDirection(id: safeID, index: index, random: &random)
        case 6: definition = buildGravity(id: safeID, index: index, random: &random)
        case 7: definition = buildPortals(id: safeID, index: index, random: &random)
        case 8: definition = buildMachines(id: safeID, index: index, random: &random)
        case 9: definition = buildChainReaction(id: safeID, index: index, random: &random)
        default: definition = buildMasterTable(id: safeID, index: index, random: &random)
        }
        // Builders can borrow a later chapter's mechanic at a gentler index.
        // Restore campaign coordinates after borrowing so saves and the level
        // select screen always see the actual 1...20 chapter position.
        var campaignDefinition = definition
        campaignDefinition.chapter = chapter
        campaignDefinition.indexInChapter = index
        campaignDefinition.name = CampaignCopy.title(chapter: chapter, index: index)
        let validated = LevelValidator.shared.repaired(campaignDefinition)
        cache[safeID] = validated
        return validated
    }

    func allLevels() -> [LevelDefinition] {
        (1...200).map(level(id:))
    }

    func preloadChapter(_ chapter: Int) {
        let safe = ScalarMath.clamp(chapter, 1, 10)
        let range = ((safe - 1) * 20 + 1)...(safe * 20)
        for id in range where cache[id] == nil { _ = level(id: id) }
    }

    private func buildFoundationCourse(
        id: Int,
        index: Int,
        random: inout SeededRandom
    ) -> LevelDefinition {
        switch index {
        case 1, 2: return buildFoundationTiming(id: id, variant: index, random: &random)
        case 3, 4: return buildFoundationPair(id: id, variant: index, random: &random)
        case 5, 6: return buildFoundationGate(id: id, variant: index, random: &random)
        case 7, 8: return buildFoundationDrag(id: id, variant: index, random: &random)
        case 9, 10: return buildFoundationDirection(id: id, variant: index, random: &random)
        case 11, 12: return buildFoundationGravity(id: id, variant: index, random: &random)
        case 13, 14: return buildFoundationPortal(id: id, variant: index, random: &random)
        case 15, 16: return buildFoundationMachine(id: id, variant: index, random: &random)
        case 17, 18: return buildFoundationChain(id: id, variant: index, random: &random)
        default: return buildFoundationMaster(id: id, variant: index, random: &random)
        }
    }

    private func buildFoundationTiming(id: Int, variant: Int, random: inout SeededRandom) -> LevelDefinition {
        let y: CGFloat = variant == 1 ? 35 : -72
        let start = WorldPoint(-135, y)
        let end = WorldPoint(135, y + (variant == 1 ? 0 : 105))
        let targetPoint = variant == 1 ? WorldPoint(35, y) : WorldPoint(70, 33)
        let suit: MahjongSuit = variant == 1 ? .characters : .bamboo
        let tile = makeNumberTile(
            id: "tile-a", value: variant, suit: suit, position: start, team: .ivory,
            motion: MotionDefinition(type: variant == 1 ? .linear : .pingPong, points: [start, end], speed: variant == 1 ? 52 : 68, duration: variant == 1 ? 5.2 : 3.8, curve: variant == 1 ? .linear : .sine),
            targetIDs: ["target-a"]
        )
        let zone = MechanismDefinition(id: "freeze-zone", kind: .freezeZone, position: targetPoint, size: WorldSize(variant == 1 ? 96 : 84, variant == 1 ? 82 : 84), startsActive: true)
        let target = TargetDefinition(id: "target-a", position: targetPoint, radius: 34, acceptsSuit: suit, holdDuration: 0.12)
        var rules = LevelRules()
        rules.maximumFreezes = 1
        if variant == 1 { rules.tutorialKey = "first-freeze" }
        return assemble(id: id, index: variant, name: CampaignCopy.title(chapter: 1, index: variant), subtitle: variant == 1 ? "Stop the tile inside the lit target." : "Catch the tile on its return pass.", mode: .timing, difficulty: variant, tiles: [tile], mechanisms: [zone], targets: [target], objectives: [ObjectiveDefinition(id: "freeze-window", kind: .freezeInZone, title: "Freeze inside the target window", requiredCount: 1)], rules: rules, par: par(index: variant, base: 2))
    }

    private func buildFoundationPair(id: Int, variant: Int, random: inout SeededRandom) -> LevelDefinition {
        let tiles: [TileDefinition]
        let targets: [TargetDefinition]
        if variant == 3 {
            let starts = [WorldPoint(-135, -88), WorldPoint(135, 88)]
            let ends = [WorldPoint(135, -88), WorldPoint(-135, 88)]
            tiles = [
                makeNumberTile(id: "tile-0", value: 3, suit: .bamboo, position: starts[0], team: .jade, motion: MotionDefinition(type: .linear, points: [starts[0], ends[0]], speed: 46, duration: 5.6), targetIDs: ["target-0"]),
                makeNumberTile(id: "tile-1", value: 4, suit: .dots, position: starts[1], team: .red, motion: MotionDefinition(type: .pingPong, points: [starts[1], ends[1]], speed: 58, duration: 5.6), targetIDs: ["target-1"])
            ]
            targets = [
                TargetDefinition(id: "target-0", position: WorldPoint(92, -88), radius: 29, acceptsTeam: .jade, holdDuration: 0.18),
                TargetDefinition(id: "target-1", position: WorldPoint(-92, 88), radius: 29, acceptsTeam: .red, holdDuration: 0.18)
            ]
        } else {
            let orbitStart = WorldPoint(0, 155)
            let lineStart = WorldPoint(-135, -115)
            let lineEnd = WorldPoint(135, -115)
            tiles = [
                makeNumberTile(id: "tile-0", value: 4, suit: .bamboo, position: orbitStart, team: .jade, motion: MotionDefinition(type: .orbit, points: [WorldPoint(0, 55)], speed: 52, duration: 4.6, radius: 100, clockwise: true), targetIDs: ["target-0"]),
                makeNumberTile(id: "tile-1", value: 5, suit: .dots, position: lineStart, team: .red, motion: MotionDefinition(type: .linear, points: [lineStart, lineEnd], speed: 58, duration: 4.6), targetIDs: ["target-1"])
            ]
            targets = [
                TargetDefinition(id: "target-0", position: WorldPoint(0, -45), radius: 29, acceptsTeam: .jade, holdDuration: 0.18),
                TargetDefinition(id: "target-1", position: WorldPoint(0, -115), radius: 29, acceptsTeam: .red, holdDuration: 0.18)
            ]
        }
        let zone = MechanismDefinition(id: "freeze-zone", kind: .freezeZone, position: targets[0].position, size: WorldSize(70, 68), startsActive: true)
        let objectives = [
            ObjectiveDefinition(id: "all-targets", kind: .simultaneousTargets, title: "Bring both tiles to their targets", requiredIDs: targets.map(\.id), requiredCount: 2),
            ObjectiveDefinition(id: "freeze-window", kind: .freezeInZone, title: "Freeze one tile in its marked window", requiredCount: 1)
        ]
        return assemble(id: id, index: variant, name: CampaignCopy.title(chapter: 1, index: variant), subtitle: variant == 3 ? "Watch where the two lanes overlap." : "Match the orbit and the lower lane.", mode: .multiTile, difficulty: 3 + variant / 2, tiles: tiles, mechanisms: [zone], targets: targets, objectives: objectives, rules: LevelRules(), par: par(index: variant, base: 4))
    }

    private func buildFoundationGate(id: Int, variant: Int, random: inout SeededRandom) -> LevelDefinition {
        let y: CGFloat = variant == 5 ? -38 : 62
        let start = WorldPoint(-140, y)
        let gatePoint = WorldPoint(0, y)
        let targetPoint = WorldPoint(125, y)
        let tile = makeNumberTile(id: "tile-a", value: variant, suit: .characters, position: start, team: .jade, motion: MotionDefinition(type: .linear, points: [start, targetPoint], speed: variant == 5 ? 50 : 62, duration: 5.4), targetIDs: ["target-a"])
        let gate = MechanismDefinition(id: "gate-a", kind: variant == 5 ? .gate : .rotatingGate, position: gatePoint, size: WorldSize(56, 70), channel: "alpha", startsActive: false, canInteractWhenFrozen: variant > 5)
        let switchNode = MechanismDefinition(id: "switch-a", kind: .switchControl, position: WorldPoint(-62, -185), channel: "alpha", canInteractWhenFrozen: true)
        let target = TargetDefinition(id: "target-a", position: targetPoint, radius: 31, acceptsTeam: .jade, holdDuration: 0.16)
        let objective = ObjectiveDefinition(id: "open-and-deliver", kind: .activateAll, title: "Open the gate, then deliver the tile", requiredIDs: ["switch-a"], requiredCount: 1)
        var rules = LevelRules()
        if variant == 5 { rules.tutorialKey = "switch" }
        return assemble(id: id, index: variant, name: CampaignCopy.title(chapter: 1, index: variant), subtitle: variant == 5 ? "Stop the board and open the straight gate." : "Turn the barrier before the tile arrives.", mode: .mechanism, difficulty: 5 + variant / 3, tiles: [tile], mechanisms: [gate, switchNode], targets: [target], objectives: [objective, ObjectiveDefinition(id: "deliver", kind: .reachTarget, title: "Reach the target", requiredIDs: ["target-a"], requiredCount: 1)], rules: rules, par: par(index: variant, base: 4))
    }

    private func buildFoundationDrag(id: Int, variant: Int, random: inout SeededRandom) -> LevelDefinition {
        let y: CGFloat = variant == 7 ? 30 : -95
        let suit: MahjongSuit = variant == 7 ? .dots : .characters
        let tile = makeNumberTile(id: "tile-a", value: variant, suit: suit, position: WorldPoint(-105, y), team: .ivory, motion: MotionDefinition(), canDrag: true, targetIDs: ["target-a"])
        let target = TargetDefinition(id: "target-a", position: WorldPoint(105, variant == 7 ? 30 : 105), radius: 31, acceptsSuit: suit, holdDuration: 0.12)
        var rules = LevelRules()
        rules.maximumDrags = variant == 7 ? 1 : 2
        if variant == 7 { rules.tutorialKey = "foundation-drag" }
        let objectiveTitle = variant == 7
            ? "Freeze time, then drag the tile into the target"
            : "Drag the tile into its matching target"
        return assemble(id: id, index: variant, name: CampaignCopy.title(chapter: 1, index: variant), subtitle: variant == 7 ? "Freeze first, then slide the tile across." : "Use the shortest drag into the corner target.", mode: .routing, difficulty: 5 + variant / 4, tiles: [tile], mechanisms: [], targets: [target], objectives: [ObjectiveDefinition(id: "arrange", kind: .reachTarget, title: objectiveTitle, requiredIDs: ["target-a"], requiredCount: 1)], rules: rules, par: par(index: variant, base: 3))
    }

    private func buildFoundationDirection(id: Int, variant: Int, random: inout SeededRandom) -> LevelDefinition {
        let start = variant == 9 ? WorldPoint(-105, -105) : WorldPoint(105, 105)
        let targetPoint = variant == 9 ? WorldPoint(-105, 105) : WorldPoint(105, -105)
        let initialRotation: CGFloat = variant == 9 ? 0 : .pi / 2
        let tile = TileDefinition(id: "tile-a", suit: .wind, face: variant == 9 ? .east : .north, behavior: .directional, team: .blue, position: start, rotation: initialRotation, canRotateWhenFrozen: true, motion: MotionDefinition(type: .linear, points: [start], speed: 44 + CGFloat(variant), duration: 3), targetIDs: ["target-a"])
        let target = TargetDefinition(id: "target-a", position: targetPoint, radius: 30, acceptsSuit: .wind, holdDuration: 0.14)
        let zone = MechanismDefinition(id: "freeze-zone", kind: .freezeZone, position: targetPoint, size: WorldSize(68, 68), startsActive: true)
        var rules = LevelRules()
        if variant == 9 { rules.tutorialKey = "foundation-direction" }
        return assemble(id: id, index: variant, name: CampaignCopy.title(chapter: 1, index: variant), subtitle: variant == 9 ? "Turn the wind tile toward the upper target." : "Turn the wind tile toward the lower target.", mode: .precision, difficulty: 7, tiles: [tile], mechanisms: [zone], targets: [target], objectives: [ObjectiveDefinition(id: "direct", kind: .reachTarget, title: "Turn the wind tile, then freeze it on target", requiredIDs: ["target-a"], requiredCount: 1), ObjectiveDefinition(id: "direction-freeze", kind: .freezeInZone, title: "Freeze the corrected route", requiredCount: 1)], rules: rules, par: par(index: variant, base: 4))
    }

    private func buildFoundationGravity(id: Int, variant: Int, random: inout SeededRandom) -> LevelDefinition {
        let start = WorldPoint(variant == 11 ? -55 : 55, 170)
        let targetPoint = WorldPoint(variant == 11 ? -55 : 55, -164)
        let tile = makeNumberTile(id: "tile-a", value: variant, suit: .dots, position: start, team: .gold, behavior: variant == 12 ? .heavy : .normal, weight: variant == 12 ? 2 : 1, motion: MotionDefinition(type: .gravity, points: [WorldPoint(variant == 11 ? 8 : -8, 0)], curve: .bounce, acceleration: WorldPoint(0, -120 - CGFloat(variant * 2))), targetIDs: ["target-a"])
        let target = TargetDefinition(id: "target-a", position: targetPoint, radius: 38, acceptsTeam: .gold, requiredWeight: tile.weight, holdDuration: 0.16)
        let zone = MechanismDefinition(id: "freeze-zone", kind: .freezeZone, position: targetPoint, size: WorldSize(84, 70), startsActive: true)
        return assemble(id: id, index: variant, name: CampaignCopy.title(chapter: 1, index: variant), subtitle: variant == 11 ? "Stop the tile at the bottom of its drop." : "The heavier tile needs room to settle.", mode: .mechanism, difficulty: 8, tiles: [tile], mechanisms: [zone], targets: [target], objectives: [ObjectiveDefinition(id: "freeze-landing", kind: .freezeInZone, title: "Freeze on the landing plate", requiredCount: 1)], rules: LevelRules(), par: par(index: variant, base: 5))
    }

    private func buildFoundationPortal(id: Int, variant: Int, random: inout SeededRandom) -> LevelDefinition {
        let first = WorldPoint(-72, variant == 13 ? -78 : 78)
        let second = WorldPoint(62, variant == 13 ? 78 : -78)
        let targetPoint = WorldPoint(130, variant == 13 ? 78 : -78)
        let portals = [MechanismDefinition(id: "portal-a", kind: .portal, position: first, size: WorldSize(58, 70), linkedIDs: ["portal-b"], startsActive: true, direction: WorldPoint(1, 0)), MechanismDefinition(id: "portal-b", kind: .portal, position: second, size: WorldSize(58, 70), linkedIDs: ["portal-a"], startsActive: true, direction: WorldPoint(1, 0))]
        let start = WorldPoint(-145, first.y)
        let tile = makeNumberTile(id: "tile-a", value: variant, suit: .characters, position: start, team: .blue, motion: MotionDefinition(type: .projectile, points: [WorldPoint(1, 0)], speed: 50 + CGFloat(variant), acceleration: WorldPoint(0, 0)), targetIDs: ["target-a"])
        let target = TargetDefinition(id: "target-a", position: targetPoint, radius: 30, acceptsTeam: .blue, holdDuration: 0.14)
        let zone = MechanismDefinition(id: "freeze-zone", kind: .freezeZone, position: targetPoint, size: WorldSize(64, 64), startsActive: true)
        return assemble(id: id, index: variant, name: CampaignCopy.title(chapter: 1, index: variant), subtitle: variant == 13 ? "Follow one transfer from entry to exit." : "Read the tile's direction as it leaves the portal.", mode: .routing, difficulty: 9, tiles: [tile], mechanisms: portals + [zone], targets: [target], objectives: [ObjectiveDefinition(id: "portal-freeze", kind: .freezeInZone, title: "Freeze after the portal exit", requiredCount: 1)], rules: LevelRules(), par: par(index: variant, base: 6))
    }

    private func buildFoundationMachine(id: Int, variant: Int, random: inout SeededRandom) -> LevelDefinition {
        let y: CGFloat = variant == 15 ? -105 : 80
        let start = WorldPoint(-140, y)
        let gate = WorldPoint(8, y)
        let targetPoint = WorldPoint(125, y)
        let tile = makeNumberTile(id: "tile-a", value: variant, suit: .bamboo, position: start, team: .gold, motion: MotionDefinition(type: .rail, points: [start, WorldPoint(-55, y), gate, targetPoint], speed: variant == 15 ? 46 : 58, curve: .easeInOut), targetIDs: ["target-a"])
        let mechanisms: [MechanismDefinition] = [MechanismDefinition(id: "conveyor-a", kind: .conveyor, position: WorldPoint(-78, y), size: WorldSize(92, 34), startsActive: true, direction: WorldPoint(1, 0), strength: 22), MechanismDefinition(id: "gate-a", kind: .gate, position: gate, size: WorldSize(52, 64), channel: "lift", startsActive: false), MechanismDefinition(id: "switch-a", kind: .switchControl, position: WorldPoint(92, -185), channel: "lift", canInteractWhenFrozen: true)]
        let target = TargetDefinition(id: "target-a", position: targetPoint, radius: 30, acceptsTeam: .gold, holdDuration: 0.16)
        let objectives = [ObjectiveDefinition(id: "machine-switch", kind: .activateAll, title: "Power the machine", requiredIDs: ["switch-a"], requiredCount: 1), ObjectiveDefinition(id: "machine-delivery", kind: .reachTarget, title: "Deliver the tile", requiredIDs: ["target-a"], requiredCount: 1)]
        return assemble(id: id, index: variant, name: CampaignCopy.title(chapter: 1, index: variant), subtitle: variant == 15 ? "Start the lift before the tile reaches the gate." : "Carry the tile from conveyor to rail.", mode: .mechanism, difficulty: 10, tiles: [tile], mechanisms: mechanisms, targets: [target], objectives: objectives, rules: LevelRules(), par: par(index: variant, base: 7))
    }

    private func buildFoundationChain(id: Int, variant: Int, random: inout SeededRandom) -> LevelDefinition {
        let tiles: [TileDefinition]
        let targets: [TargetDefinition]
        if variant == 17 {
            let starts = [WorldPoint(-138, -95), WorldPoint(-138, 95)]
            let ends = [WorldPoint(122, -95), WorldPoint(122, 95)]
            tiles = [
                makeNumberTile(id: "tile-0", value: 8, suit: .characters, position: starts[0], team: .jade, motion: MotionDefinition(type: .linear, points: [starts[0], ends[0]], speed: 52, duration: 4.5), targetIDs: ["target-0"]),
                makeNumberTile(id: "tile-1", value: 9, suit: .bamboo, position: starts[1], team: .red, motion: MotionDefinition(type: .pingPong, points: [starts[1], ends[1]], speed: 60, duration: 4.5), targetIDs: ["target-1"])
            ]
            targets = [
                TargetDefinition(id: "target-0", position: ends[0], radius: 28, acceptsTeam: .jade, holdDuration: 0.18),
                TargetDefinition(id: "target-1", position: ends[1], radius: 28, acceptsTeam: .red, holdDuration: 0.18)
            ]
        } else {
            let horizontalStart = WorldPoint(-140, -120)
            let horizontalEnd = WorldPoint(140, -120)
            let verticalStart = WorldPoint(-110, 180)
            let verticalEnd = WorldPoint(-110, -180)
            let orbitStart = WorldPoint(80, 140)
            tiles = [
                makeNumberTile(id: "tile-0", value: 1, suit: .characters, position: horizontalStart, team: .jade, motion: MotionDefinition(type: .linear, points: [horizontalStart, horizontalEnd], speed: 52, duration: 5), targetIDs: ["target-0"]),
                makeNumberTile(id: "tile-1", value: 2, suit: .bamboo, position: verticalStart, team: .red, motion: MotionDefinition(type: .pingPong, points: [verticalStart, verticalEnd], speed: 58, duration: 5), targetIDs: ["target-1"]),
                makeNumberTile(id: "tile-2", value: 3, suit: .dots, position: orbitStart, team: .gold, motion: MotionDefinition(type: .orbit, points: [WorldPoint(80, 40)], speed: 55, duration: 5, radius: 100, clockwise: true), targetIDs: ["target-2"])
            ]
            targets = [
                TargetDefinition(id: "target-0", position: WorldPoint(0, -120), radius: 28, acceptsTeam: .jade, holdDuration: 0.18),
                TargetDefinition(id: "target-1", position: WorldPoint(-110, 0), radius: 28, acceptsTeam: .red, holdDuration: 0.18),
                TargetDefinition(id: "target-2", position: WorldPoint(80, -60), radius: 28, acceptsTeam: .gold, holdDuration: 0.18)
            ]
        }
        let zone = MechanismDefinition(id: "freeze-zone", kind: .freezeZone, position: targets.last!.position, size: WorldSize(64, 64), startsActive: true)
        return assemble(id: id, index: variant, name: CampaignCopy.title(chapter: 1, index: variant), subtitle: variant == 17 ? "Bring both lanes onto their marks together." : "Line up the rail, drop, and orbit on one beat.", mode: .chainReaction, difficulty: 11, tiles: tiles, mechanisms: [zone], targets: targets, objectives: [ObjectiveDefinition(id: "chain-targets", kind: .simultaneousTargets, title: "Settle every target", requiredIDs: targets.map(\.id), requiredCount: targets.count), ObjectiveDefinition(id: "chain-freeze", kind: .freezeInZone, title: "Freeze the final consequence", requiredCount: 1)], rules: LevelRules(), par: par(index: variant, base: 8))
    }

    private func buildFoundationMaster(id: Int, variant: Int, random: inout SeededRandom) -> LevelDefinition {
        let starts = [WorldPoint(-140, -110), WorldPoint(120, 0), WorldPoint(0, 175)]
        let ends = [WorldPoint(140, -110), WorldPoint(-120, 0), WorldPoint(0, -95)]
        let targetPoints = [WorldPoint(0, -110), WorldPoint(0, 0), WorldPoint(0, -95)]
        let teams: [TileTeam] = [.jade, .red, .gold]
        var tiles: [TileDefinition] = []
        var targets: [TargetDefinition] = []
        for i in 0..<3 {
            let targetID = "target-\(i)"
            let motion: MotionDefinition = i == 0
                ? MotionDefinition(type: .linear, points: [starts[i], ends[i]], speed: 48, duration: 5.2)
                : i == 1
                    ? MotionDefinition(type: .pingPong, points: [starts[i], ends[i]], speed: 55, duration: 5.2, curve: .linear)
                    : MotionDefinition(type: .orbit, points: [WorldPoint(0, 40)], speed: 50, duration: 5.2, radius: 135, clockwise: true)
            tiles.append(makeNumberTile(id: "tile-\(i)", value: variant + i, suit: [.characters, .bamboo, .dots][i], position: starts[i], team: teams[i], behavior: i == 2 ? .heavy : .normal, weight: i == 2 ? 2 : 1, motion: motion, targetIDs: [targetID]))
            targets.append(TargetDefinition(id: targetID, position: targetPoints[i], radius: 28, acceptsTeam: teams[i], requiredWeight: i == 2 ? 2 : 0, holdDuration: 0.18))
        }
        let zone = MechanismDefinition(id: "freeze-zone", kind: .freezeZone, position: targets[0].position, size: WorldSize(68, 68), startsActive: true)
        var rules = LevelRules()
        rules.unlimitedFreeze = false
        rules.freezeEnergy = 100
        rules.freezeDrainPerSecond = 12
        rules.freezeRecoveryPerSecond = 5
        rules.slowMotionEnabled = true
        rules.rewindEnabled = true
        rules.rewindSeconds = 5
        if variant == 20 { rules.tutorialKey = "rewind" }
        return assemble(id: id, index: variant, name: CampaignCopy.title(chapter: 1, index: variant), subtitle: variant == 19 ? "Track three motion types at once." : "Rewind a missed alignment and stop it cleanly.", mode: .precision, difficulty: 14, tiles: tiles, mechanisms: [zone], targets: targets, objectives: [ObjectiveDefinition(id: "master-targets", kind: .simultaneousTargets, title: "Settle all three futures", requiredIDs: targets.map(\.id), requiredCount: 3), ObjectiveDefinition(id: "master-freeze", kind: .freezeInZone, title: "Choose the decisive freeze", requiredCount: 1)], rules: rules, par: par(index: variant, base: 10))
    }

    private func buildMovingWorld(
        id: Int,
        index: Int,
        random: inout SeededRandom
    ) -> LevelDefinition {
        let tileCount = 2 + min(2, index / 7)
        let targetTeam: TileTeam = [.jade, .blue, .red][index % 3]
        let laneHeight: CGFloat = 76
        var tiles: [TileDefinition] = []
        for tileIndex in 0..<tileCount {
            let y = (CGFloat(tileIndex) - CGFloat(tileCount - 1) / 2) * laneHeight
            let team: TileTeam = tileIndex == index % tileCount ? targetTeam : (tileIndex % 2 == 0 ? .red : .ivory)
            let start = WorldPoint(tileIndex % 2 == 0 ? -145 : 145, y)
            let end = WorldPoint(tileIndex % 2 == 0 ? 165 : -165, y)
            let motionType: MotionType = index < 8 ? .linear : (tileIndex % 2 == 0 ? .pingPong : .orbit)
            let motion: MotionDefinition
            if motionType == .orbit {
                motion = MotionDefinition(type: .orbit, points: [WorldPoint(0, y)], speed: 65, duration: 3.4 + CGFloat(tileIndex) * 0.35, radius: 120, phase: CGFloat(tileIndex) * .pi / 2, clockwise: tileIndex % 2 == 0)
            } else {
                motion = MotionDefinition(type: motionType, points: [start, end], speed: 52 + CGFloat(index) * 2, duration: 4.3 - CGFloat(index) * 0.04, curve: index > 12 ? .sine : .linear)
            }
            tiles.append(makeNumberTile(
                id: "tile-\(tileIndex)",
                value: (index + tileIndex) % 9 + 1,
                suit: MahjongSuit.allCases[(index + tileIndex) % 3],
                position: start,
                team: team,
                motion: motion,
                targetIDs: team == targetTeam ? ["target-a"] : []
            ))
        }
        let targetY = tiles.first(where: { $0.team == targetTeam })?.position.y ?? 0
        let target = TargetDefinition(id: "target-a", position: WorldPoint(index % 2 == 0 ? 105 : -105, targetY), radius: max(25, 34 - CGFloat(index) * 0.3), acceptsTeam: targetTeam, holdDuration: 0.1)
        var mechanisms: [MechanismDefinition] = []
        if index >= 10 {
            mechanisms.append(MechanismDefinition(id: "platform", kind: .rotatingPlatform, position: WorldPoint(0, 0), size: WorldSize(96, 96), startsActive: true, period: 3, strength: 18))
        }
        let objective = ObjectiveDefinition(id: "correct-tile", kind: .reachTarget, title: "Guide the \(targetTeam.rawValue.uppercased()) tile to target", requiredIDs: ["target-a"], requiredCount: 1)
        return assemble(
            id: id,
            index: index,
            name: CampaignCopy.title(chapter: 2, index: index),
            subtitle: "Track the right tile through a moving world.",
            mode: index < 11 ? .timing : .multiTile,
            difficulty: 3 + index / 4,
            tiles: tiles,
            mechanisms: mechanisms,
            targets: [target],
            objectives: [objective],
            rules: LevelRules(),
            par: par(index: index, base: 3)
        )
    }

    private func buildGates(
        id: Int,
        index: Int,
        random: inout SeededRandom
    ) -> LevelDefinition {
        let y = random.float(in: -48...48)
        let start = WorldPoint(-145, y)
        let end = WorldPoint(165, y)
        let channel = "gate-a"
        let tile = makeNumberTile(
            id: "tile-a",
            value: index % 9 + 1,
            suit: .bamboo,
            position: start,
            team: .jade,
            motion: MotionDefinition(type: index > 12 ? .pingPong : .linear, points: [start, end], speed: 70 + CGFloat(index), duration: 4.2, curve: .linear)
        )
        var mechanisms = [MechanismDefinition(
            id: "gate-a",
            kind: index > 10 ? .rotatingGate : .gate,
            position: WorldPoint(5, y),
            size: WorldSize(58, 58),
            channel: channel,
            startsActive: index <= 3,
            period: index <= 3 ? 2.8 : 0,
            phase: random.float(in: 0...2.4),
            canInteractWhenFrozen: index > 10
        )]
        if index > 3 {
            mechanisms.append(MechanismDefinition(
                id: "switch-a",
                kind: .switchControl,
                position: WorldPoint(-70, -135),
                channel: channel,
                linkedIDs: ["gate-a"],
                canInteractWhenFrozen: true
            ))
        }
        if index > 13 {
            mechanisms.append(MechanismDefinition(
                id: "gate-b",
                kind: .gate,
                position: WorldPoint(72, y),
                size: WorldSize(54, 54),
                channel: "gate-b",
                period: 2.2,
                phase: random.float(in: 0...2)
            ))
        }
        var rules = LevelRules()
        if index == 4 { rules.tutorialKey = "switch" }
        let target = TargetDefinition(id: "target-a", position: WorldPoint(128, y), radius: 29, acceptsTeam: .jade)
        let objective = ObjectiveDefinition(id: "pass-gate", kind: .reachTarget, title: index <= 3 ? "Pass while the gate is open" : "Freeze, operate the switch, then pass", requiredIDs: ["target-a"])
        return assemble(
            id: id,
            index: index,
            name: CampaignCopy.title(chapter: 3, index: index),
            subtitle: index < 4 ? "Read the gate's mechanical rhythm." : "Frozen time leaves the controls awake.",
            mode: .mechanism,
            difficulty: 4 + index / 3,
            tiles: [tile],
            mechanisms: mechanisms,
            targets: [target],
            objectives: [objective],
            rules: rules,
            par: par(index: index, base: 4)
        )
    }

    private func buildTileControl(
        id: Int,
        index: Int,
        random: inout SeededRandom
    ) -> LevelDefinition {
        let count = 1 + min(2, index / 7)
        var tiles: [TileDefinition] = []
        var targets: [TargetDefinition] = []
        for tileIndex in 0..<count {
            let y = CGFloat(tileIndex - (count - 1) / 2) * 78
            let suit: MahjongSuit = [.characters, .bamboo, .dots][tileIndex % 3]
            let value = (index + tileIndex) % 9 + 1
            let targetID = "target-\(tileIndex)"
            tiles.append(makeNumberTile(
                id: "tile-\(tileIndex)",
                value: value,
                suit: suit,
                position: WorldPoint(-110 + CGFloat(tileIndex) * 22, y),
                team: tileIndex % 2 == 0 ? .ivory : .blue,
                behavior: index > 10 && tileIndex == 0 ? .fragile : .normal,
                motion: MotionDefinition(type: index < 7 ? .stationary : .pingPong, points: [WorldPoint(-110, y), WorldPoint(30, y)], speed: 45, duration: 3.2),
                canDrag: true,
                canRotate: index >= 6,
                targetIDs: [targetID]
            ))
            targets.append(TargetDefinition(id: targetID, position: WorldPoint(90, y), radius: 31, acceptsSuit: suit, holdDuration: 0.08))
        }
        var mechanisms: [MechanismDefinition] = []
        if index >= 9 {
            mechanisms.append(MechanismDefinition(id: "hazard-a", kind: .hazard, position: WorldPoint(0, -145), size: WorldSize(120, 24), startsActive: true))
        }
        var rules = LevelRules()
        rules.maximumDrags = count + 1
        if index == 1 { rules.tutorialKey = "drag" }
        let kind: ObjectiveKind = count >= 3 ? .sameSuit : .reachTarget
        let objective = ObjectiveDefinition(id: "arrange", kind: kind, title: count == 1 ? "Drag the tile into its matching target" : "Arrange every tile while time is frozen", requiredIDs: targets.map(\.id), requiredCount: count)
        return assemble(
            id: id,
            index: index,
            name: CampaignCopy.title(chapter: 4, index: index),
            subtitle: "Time stops. Your hands do not.",
            mode: .routing,
            difficulty: 5 + index / 3,
            tiles: tiles,
            mechanisms: mechanisms,
            targets: targets,
            objectives: [objective],
            rules: rules,
            par: par(index: index, base: 3 + count)
        )
    }

    private func buildDirection(
        id: Int,
        index: Int,
        random: inout SeededRandom
    ) -> LevelDefinition {
        let windFaces: [MahjongFace] = [.east, .north, .west, .south]
        let start = WorldPoint(index % 2 == 0 ? -95 : 0, index % 2 == 0 ? 0 : -120)
        let requiredTurns = index % 4
        let initialRotation = CGFloat(requiredTurns) * -.pi / 2
        let directionAfterTurns = initialRotation + CGFloat(requiredTurns) * .pi / 2
        let distance: CGFloat = 190
        let targetPoint = WorldPoint(start.x + cos(directionAfterTurns) * distance, start.y + sin(directionAfterTurns) * distance)
        let tile = TileDefinition(
            id: "tile-a",
            suit: .wind,
            face: windFaces[index % 4],
            behavior: .directional,
            team: .blue,
            position: start,
            rotation: initialRotation,
            weight: 1,
            canDragWhenFrozen: false,
            canRotateWhenFrozen: true,
            motion: MotionDefinition(type: .linear, speed: 48 + CGFloat(index) * 1.4),
            targetIDs: ["target-a"]
        )
        var mechanisms: [MechanismDefinition] = []
        if index >= 7 {
            mechanisms.append(MechanismDefinition(id: "mirror-a", kind: .mirror, position: WorldPoint(0, 35), size: WorldSize(82, 14), rotation: index % 2 == 0 ? .pi / 4 : -.pi / 4, startsActive: true, canInteractWhenFrozen: index > 13))
        }
        if index >= 12 {
            mechanisms.append(MechanismDefinition(id: "no-freeze", kind: .noFreezeZone, position: WorldPoint(0, 0), size: WorldSize(74, 100), startsActive: true))
        }
        let target = TargetDefinition(id: "target-a", position: targetPoint, radius: max(25, 33 - CGFloat(index) * 0.25), acceptsSuit: .wind)
        let objective = ObjectiveDefinition(id: "direct", kind: .reachTarget, title: "Turn the wind tile toward its target", requiredIDs: ["target-a"])
        return assemble(
            id: id,
            index: index,
            name: CampaignCopy.title(chapter: 5, index: index),
            subtitle: "A quarter turn changes the future.",
            mode: index > 12 ? .precision : .routing,
            difficulty: 6 + index / 2,
            tiles: [tile],
            mechanisms: mechanisms,
            targets: [target],
            objectives: [objective],
            rules: LevelRules(),
            par: par(index: index, base: 4)
        )
    }

    private func buildGravity(
        id: Int,
        index: Int,
        random: inout SeededRandom
    ) -> LevelDefinition {
        let count = index > 11 ? 2 : 1
        var tiles: [TileDefinition] = []
        for tileIndex in 0..<count {
            let weight = index > 6 ? (tileIndex == 0 ? 2 : 1) : 1
            let behavior: TileBehavior = weight > 1 ? .heavy : (index > 15 ? .fragile : .normal)
            let start = WorldPoint(-70 + CGFloat(tileIndex) * 70, 175 - CGFloat(tileIndex) * 28)
            tiles.append(makeNumberTile(
                id: "tile-\(tileIndex)",
                value: weight == 2 ? 9 : (index + tileIndex) % 9 + 1,
                suit: .dots,
                position: start,
                team: weight == 2 ? .gold : .ivory,
                behavior: behavior,
                weight: weight,
                motion: MotionDefinition(type: .gravity, points: [WorldPoint(random.float(in: -14...14), 0)], curve: index % 3 == 0 ? .bounce : .linear, acceleration: WorldPoint(0, -125 - CGFloat(index) * 3)),
                canDrag: index > 10
            ))
        }
        let threshold = min(3, tiles.reduce(0) { $0 + $1.weight })
        var mechanisms = [MechanismDefinition(
            id: "plate-a",
            kind: .pressurePlate,
            position: WorldPoint(0, -165),
            size: WorldSize(105, 32),
            channel: "bridge",
            threshold: threshold
        )]
        if index >= 5 {
            mechanisms.append(MechanismDefinition(id: "conveyor-a", kind: .conveyor, position: WorldPoint(0, -95), size: WorldSize(190, 42), startsActive: true, direction: WorldPoint(index % 2 == 0 ? 1 : -1, 0), strength: 38 + CGFloat(index)))
        }
        if index >= 12 {
            mechanisms.append(MechanismDefinition(id: "bridge", kind: .bridge, position: WorldPoint(92, -35), size: WorldSize(110, 35), channel: "bridge", startsActive: false))
        }
        let target = TargetDefinition(id: "target-a", position: WorldPoint(index >= 12 ? 112 : 0, -150), radius: 34, requiredWeight: threshold)
        let objective = ObjectiveDefinition(id: "weight", kind: .totalWeight, title: "Place enough weight on the pressure plate", requiredIDs: ["plate-a"], requiredValue: CGFloat(threshold))
        return assemble(
            id: id,
            index: index,
            name: CampaignCopy.title(chapter: 6, index: index),
            subtitle: "Momentum is another kind of clock.",
            mode: .mechanism,
            difficulty: 7 + index / 2,
            tiles: tiles,
            mechanisms: mechanisms,
            targets: [target],
            objectives: [objective],
            rules: LevelRules(),
            par: par(index: index, base: 5)
        )
    }

    private func buildPortals(
        id: Int,
        index: Int,
        random: inout SeededRandom
    ) -> LevelDefinition {
        let portalCount = index > 12 ? 4 : (index > 5 ? 3 : 2)
        let positions = [WorldPoint(-105, -75), WorldPoint(95, 80), WorldPoint(-85, 145), WorldPoint(110, -145)]
        var mechanisms: [MechanismDefinition] = []
        for portalIndex in 0..<portalCount {
            let next = (portalIndex + 1) % portalCount
            mechanisms.append(MechanismDefinition(
                id: "portal-\(portalIndex)",
                kind: .portal,
                position: positions[portalIndex],
                size: WorldSize(58, 70),
                rotation: CGFloat(portalIndex) * .pi / 2,
                channel: "portals",
                linkedIDs: ["portal-\(next)"],
                startsActive: true,
                direction: WorldPoint(portalIndex % 2 == 0 ? 1 : -1, portalIndex < 2 ? 0 : -1),
                canInteractWhenFrozen: index >= 9
            ))
        }
        if index >= 14 {
            mechanisms.append(MechanismDefinition(id: "switch-a", kind: .switchControl, position: WorldPoint(0, -190), channel: "portals", startsActive: true, canInteractWhenFrozen: true))
        }
        let start = WorldPoint(-145, -75)
        let tile = makeNumberTile(
            id: "tile-a",
            value: index % 9 + 1,
            suit: .characters,
            position: start,
            team: .blue,
            motion: MotionDefinition(type: .projectile, points: [WorldPoint(1, 0)], speed: 54 + CGFloat(index) * 1.5, acceleration: WorldPoint(0, 0)),
            targetIDs: ["target-a"]
        )
        let targetPoint = portalCount == 2 ? WorldPoint(142, 80) : WorldPoint(142, -145)
        let target = TargetDefinition(id: "target-a", position: targetPoint, radius: 30, acceptsTeam: .blue)
        let objective = ObjectiveDefinition(id: "portal-route", kind: .reachTarget, title: "Route the tile through the portal chain", requiredIDs: ["target-a"])
        return assemble(
            id: id,
            index: index,
            name: CampaignCopy.title(chapter: 7, index: index),
            subtitle: "Connected space has its own sequence.",
            mode: .routing,
            difficulty: 8 + index / 2,
            tiles: [tile],
            mechanisms: mechanisms,
            targets: [target],
            objectives: [objective],
            rules: LevelRules(),
            par: par(index: index, base: 6)
        )
    }

    private func buildMachines(
        id: Int,
        index: Int,
        random: inout SeededRandom
    ) -> LevelDefinition {
        let start = WorldPoint(-140, -105)
        let railPoints = [start, WorldPoint(-45, -105), WorldPoint(-45, 80), WorldPoint(115, 80)]
        let tile = makeNumberTile(
            id: "tile-a",
            value: index % 9 + 1,
            suit: .bamboo,
            position: start,
            team: .gold,
            motion: MotionDefinition(type: .rail, points: railPoints, speed: 48 + CGFloat(index) * 1.2, curve: .easeInOut)
        )
        var mechanisms: [MechanismDefinition] = [
            MechanismDefinition(id: "conveyor-a", kind: .conveyor, position: WorldPoint(-85, -105), size: WorldSize(105, 38), startsActive: true, direction: WorldPoint(1, 0), strength: 28),
            MechanismDefinition(id: "elevator-a", kind: .elevator, position: WorldPoint(-45, -65), size: WorldSize(76, 28), channel: "lift", linkedIDs: ["-45,80"], startsActive: index < 6, period: 2.6),
            MechanismDefinition(id: "switch-a", kind: .switchControl, position: WorldPoint(85, -145), channel: "lift", canInteractWhenFrozen: true),
            MechanismDefinition(id: "platform-a", kind: .rotatingPlatform, position: WorldPoint(65, 80), size: WorldSize(105, 105), startsActive: true, strength: 20 + CGFloat(index), canInteractWhenFrozen: index >= 10)
        ]
        if index >= 7 {
            mechanisms.append(MechanismDefinition(id: "magnet-a", kind: .magnet, position: WorldPoint(20, 155), size: WorldSize(80, 80), channel: "magnet", startsActive: index % 2 == 0, strength: 95))
            mechanisms.append(MechanismDefinition(id: "switch-b", kind: .switchControl, position: WorldPoint(130, -145), channel: "magnet", canInteractWhenFrozen: true))
        }
        if index >= 14 {
            mechanisms.append(MechanismDefinition(id: "pendulum-a", kind: .pendulum, position: WorldPoint(65, 185), startsActive: true, period: 2.3, strength: 65))
        }
        let target = TargetDefinition(id: "target-a", position: WorldPoint(120, 80), radius: 30, acceptsTeam: .gold)
        let objective = ObjectiveDefinition(id: "machine-route", kind: .reachTarget, title: "Conduct the machine and deliver the tile", requiredIDs: ["target-a"])
        return assemble(
            id: id,
            index: index,
            name: CampaignCopy.title(chapter: 8, index: index),
            subtitle: "Every mechanism runs on the same clock.",
            mode: .mechanism,
            difficulty: 9 + index / 2,
            tiles: [tile],
            mechanisms: mechanisms,
            targets: [target],
            objectives: [objective],
            rules: LevelRules(),
            par: par(index: index, base: 7)
        )
    }

    private func buildChainReaction(
        id: Int,
        index: Int,
        random: inout SeededRandom
    ) -> LevelDefinition {
        let tileCount = 2 + min(2, index / 8)
        var tiles: [TileDefinition] = []
        var targets: [TargetDefinition] = []
        for tileIndex in 0..<tileCount {
            let y = -105 + CGFloat(tileIndex) * 70
            let team: TileTeam = [.jade, .red, .blue, .gold][tileIndex]
            let targetID = "target-\(tileIndex)"
            let start = WorldPoint(-145, y)
            tiles.append(makeNumberTile(
                id: "tile-\(tileIndex)",
                value: (index + tileIndex) % 9 + 1,
                suit: [.characters, .bamboo, .dots][tileIndex % 3],
                position: start,
                team: team,
                behavior: tileIndex == tileCount - 1 && index > 12 ? .fragile : .normal,
                motion: MotionDefinition(type: tileIndex % 2 == 0 ? .linear : .pingPong, points: [start, WorldPoint(165, y)], speed: 48 + CGFloat(tileIndex * 8), duration: 4 - CGFloat(tileIndex) * 0.3),
                targetIDs: [targetID]
            ))
            targets.append(TargetDefinition(id: targetID, position: WorldPoint(130, y), radius: 28, acceptsTeam: team))
        }
        var mechanisms: [MechanismDefinition] = [
            MechanismDefinition(id: "switch-a", kind: .switchControl, position: WorldPoint(-70, -185), channel: "gate-a", canInteractWhenFrozen: true),
            MechanismDefinition(id: "gate-a", kind: .gate, position: WorldPoint(-10, -105), size: WorldSize(55, 55), channel: "gate-a", period: 0),
            MechanismDefinition(id: "plate-a", kind: .pressurePlate, position: WorldPoint(30, -35), size: WorldSize(70, 35), channel: "gate-b", threshold: 1),
            MechanismDefinition(id: "gate-b", kind: .rotatingGate, position: WorldPoint(76, 35), size: WorldSize(55, 55), channel: "gate-b", period: 0)
        ]
        if index >= 9 {
            mechanisms.append(MechanismDefinition(id: "portal-a", kind: .portal, position: WorldPoint(-55, 105), size: WorldSize(55, 65), linkedIDs: ["portal-b"], startsActive: true, direction: WorldPoint(1, 0)))
            mechanisms.append(MechanismDefinition(id: "portal-b", kind: .portal, position: WorldPoint(78, 145), size: WorldSize(55, 65), linkedIDs: ["portal-a"], startsActive: true, direction: WorldPoint(1, 0)))
        }
        if index >= 15 {
            mechanisms.append(MechanismDefinition(id: "hazard-a", kind: .hazard, position: WorldPoint(45, -105), size: WorldSize(48, 25), startsActive: true))
        }
        let objective = ObjectiveDefinition(id: "simultaneous", kind: .simultaneousTargets, title: "Align every target in one chain reaction", requiredIDs: targets.map(\.id), requiredCount: tileCount)
        return assemble(
            id: id,
            index: index,
            name: CampaignCopy.title(chapter: 9, index: index),
            subtitle: "One action becomes many consequences.",
            mode: .chainReaction,
            difficulty: 11 + index / 2,
            tiles: tiles,
            mechanisms: mechanisms,
            targets: targets,
            objectives: [objective],
            rules: LevelRules(),
            par: par(index: index, base: 8)
        )
    }

    private func buildMasterTable(
        id: Int,
        index: Int,
        random: inout SeededRandom
    ) -> LevelDefinition {
        let count = 2 + min(2, index / 7)
        var tiles: [TileDefinition] = []
        var targets: [TargetDefinition] = []
        for tileIndex in 0..<count {
            let angle = CGFloat(tileIndex) / CGFloat(count) * .pi * 2
            let start = WorldPoint(cos(angle) * 125, sin(angle) * 165)
            let team: TileTeam = [.jade, .red, .blue, .gold][tileIndex]
            tiles.append(makeNumberTile(
                id: "tile-\(tileIndex)",
                value: (index + tileIndex * 2) % 9 + 1,
                suit: [.characters, .bamboo, .dots][tileIndex % 3],
                position: start,
                team: team,
                behavior: tileIndex == 0 ? .directional : .normal,
                weight: tileIndex == count - 1 ? 2 : 1,
                motion: MotionDefinition(type: tileIndex == 0 ? .linear : (tileIndex == 1 ? .orbit : .gravity), points: tileIndex == 1 ? [WorldPoint(0, 0)] : [WorldPoint(-1, 0)], speed: 50 + CGFloat(index), duration: 3.2, radius: 125, phase: angle, acceleration: WorldPoint(0, -100)),
                canDrag: tileIndex > 1,
                canRotate: tileIndex == 0,
                targetIDs: ["target-\(tileIndex)"]
            ))
            targets.append(TargetDefinition(id: "target-\(tileIndex)", position: WorldPoint(-start.x * 0.72, -start.y * 0.72), radius: max(24, 29 - CGFloat(index) * 0.12), acceptsTeam: team))
        }
        var mechanisms: [MechanismDefinition] = [
            MechanismDefinition(id: "portal-a", kind: .portal, position: WorldPoint(-92, 10), size: WorldSize(54, 64), linkedIDs: ["portal-b"], startsActive: true, direction: WorldPoint(1, 0), canInteractWhenFrozen: true),
            MechanismDefinition(id: "portal-b", kind: .portal, position: WorldPoint(92, -10), size: WorldSize(54, 64), linkedIDs: ["portal-a"], startsActive: true, direction: WorldPoint(-1, 0), canInteractWhenFrozen: true),
            MechanismDefinition(id: "platform", kind: .rotatingPlatform, position: WorldPoint(0, 0), size: WorldSize(120, 120), startsActive: true, strength: 25 + CGFloat(index), canInteractWhenFrozen: true),
            MechanismDefinition(id: "magnet", kind: .magnet, position: WorldPoint(0, 170), size: WorldSize(85, 85), channel: "magnet", startsActive: index % 2 == 0, strength: 85 + CGFloat(index)),
            MechanismDefinition(id: "switch", kind: .switchControl, position: WorldPoint(0, -190), channel: "magnet", canInteractWhenFrozen: true)
        ]
        if index >= 8 {
            mechanisms.append(MechanismDefinition(id: "selective", kind: .partialFreezeZone, position: WorldPoint(-85, 90), size: WorldSize(115, 130), startsActive: true, selectiveTeams: [.red, .blue]))
        }
        if index >= 13 {
            mechanisms.append(MechanismDefinition(id: "reverse", kind: .reverseZone, position: WorldPoint(90, 95), size: WorldSize(100, 110), startsActive: true))
        }
        if index >= 17 {
            mechanisms.append(MechanismDefinition(id: "pendulum", kind: .pendulum, position: WorldPoint(0, 210), startsActive: true, period: 1.8, strength: 80))
        }
        var rules = LevelRules()
        rules.unlimitedFreeze = index <= 4
        rules.freezeEnergy = 100
        rules.freezeDrainPerSecond = 12 + CGFloat(index) * 0.4
        rules.freezeRecoveryPerSecond = 6
        rules.slowMotionEnabled = index >= 6
        rules.rewindEnabled = index >= 10
        rules.rewindSeconds = min(7, 3 + CGFloat(index) * 0.2)
        if index == 10 { rules.tutorialKey = "rewind" }
        let objective = ObjectiveDefinition(id: "master", kind: .simultaneousTargets, title: index == 20 ? "Master the entire moving system" : "Align all futures at once", requiredIDs: targets.map(\.id), requiredCount: count)
        return assemble(
            id: id,
            index: index,
            name: CampaignCopy.title(chapter: 10, index: index),
            subtitle: index == 20 ? "Every lesson. One final clock." : "Freeze, route, rewind, and predict.",
            mode: index > 14 ? .precision : .chainReaction,
            difficulty: 13 + index,
            tiles: tiles,
            mechanisms: mechanisms,
            targets: targets,
            objectives: [objective],
            rules: rules,
            par: par(index: index, base: 10)
        )
    }

    private func assemble(
        id: Int,
        index: Int,
        name: String,
        subtitle: String,
        mode: GameMode,
        difficulty: Int,
        tiles: [TileDefinition],
        mechanisms: [MechanismDefinition],
        targets: [TargetDefinition],
        objectives: [ObjectiveDefinition],
        rules: LevelRules,
        par: StarThresholds
    ) -> LevelDefinition {
        LevelDefinition(
            id: id,
            chapter: (id - 1) / 20 + 1,
            indexInChapter: index,
            name: name,
            subtitle: subtitle,
            mode: mode,
            difficulty: difficulty,
            seed: UInt64(id) &* 7_919 &+ 17,
            boardSize: WorldSize(340, 500),
            tiles: tiles,
            mechanisms: mechanisms,
            targets: targets,
            objectives: objectives,
            rules: rules,
            starThresholds: par
        )
    }

    private func makeNumberTile(
        id: String,
        value: Int,
        suit: MahjongSuit,
        position: WorldPoint,
        team: TileTeam,
        behavior: TileBehavior = .normal,
        weight: Int = 1,
        motion: MotionDefinition,
        canDrag: Bool = false,
        canRotate: Bool = false,
        targetIDs: [String] = []
    ) -> TileDefinition {
        let faces: [MahjongFace] = [.one, .two, .three, .four, .five, .six, .seven, .eight, .nine]
        return TileDefinition(
            id: id,
            suit: suit,
            face: faces[ScalarMath.clamp(value, 1, 9) - 1],
            behavior: behavior,
            team: team,
            position: position,
            weight: weight,
            canDragWhenFrozen: canDrag,
            canRotateWhenFrozen: canRotate,
            motion: motion,
            targetIDs: targetIDs
        )
    }

    private func par(index: Int, base: Int) -> StarThresholds {
        let growth = index / 6
        return StarThresholds(
            completionFreezes: base + growth + 6,
            twoStarFreezes: base + growth + 2,
            threeStarFreezes: max(1, base + growth - 1),
            twoStarTime: CGFloat(25 + index * 2),
            threeStarTime: CGFloat(13 + index)
        )
    }

}
