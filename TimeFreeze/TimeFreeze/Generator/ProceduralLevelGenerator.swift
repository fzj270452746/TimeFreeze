import CoreGraphics
import Foundation

final class ProceduralLevelGenerator {
    static let shared = ProceduralLevelGenerator()
    private init() {}

    static func dayKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: date)
    }

    func dailyLevel(for date: Date) -> LevelDefinition {
        let key = Self.dayKey(for: date)
        let seed = UInt64(key) ?? 20_260_101
        let weekday = Calendar(identifier: .gregorian).component(.weekday, from: date)
        let archetype = (Int(seed % 7) + weekday) % 7
        var level = generate(seed: seed, tier: 8 + Int(seed % 8), archetype: archetype, mode: .daily)
        level.id = 10_000 + Int(seed % 10_000)
        level.chapter = 0
        level.indexInChapter = 0
        level.name = dailyName(archetype: archetype)
        level.subtitle = "Today's board is shared by every player and works offline."
        return LevelValidator.shared.repaired(level)
    }

    func endlessLevel(stage: Int, seed: UInt64) -> LevelDefinition {
        let tier = max(1, stage)
        let archetype = Int(seed % 8)
        var level = generate(seed: seed, tier: tier, archetype: archetype, mode: .endless)
        level.id = 20_000 + stage
        level.chapter = 0
        level.indexInChapter = stage
        level.name = "ENDLESS \(String(format: "%02d", stage))"
        level.subtitle = endlessSubtitle(stage: stage, tileCount: level.tiles.count)
        return LevelValidator.shared.repaired(level)
    }

    func generate(seed: UInt64, tier: Int, archetype: Int, mode: GameMode) -> LevelDefinition {
        var random = SeededRandom(seed: seed)
        let safeTier = max(1, tier)
        let tileCount = ScalarMath.clamp(1 + safeTier / 5, 1, 5)
        let board = WorldSize(340, 500)
        let teams: [TileTeam] = [.jade, .red, .blue, .gold, .ivory]
        let suits: [MahjongSuit] = [.characters, .bamboo, .dots, .wind, .dragon]
        var tiles: [TileDefinition] = []
        var targets: [TargetDefinition] = []
        // Every tile is sampled at the same world time so multi-tile stages have
        // a real, repeatable alignment window instead of unrelated targets.
        let solutionTime = random.float(in: 1.8...3.4)
        let cycleDuration = random.float(in: 4.4...5.8)
        let layoutPhase = random.float(in: 0...(.pi * 2))
        for index in 0..<tileCount {
            let start = distributedPoint(index: index, count: tileCount, radiusX: 90, radiusY: 130, phase: layoutPhase)
            let team = teams[index % teams.count]
            let suit = suits[index % min(3 + safeTier / 10, suits.count)]
            let face = face(for: suit, value: random.int(in: 1...9), random: &random)
            let motion = proceduralMotion(index: index, tier: safeTier, start: start, archetype: archetype, cycleDuration: cycleDuration, random: &random)
            let targetPoint = position(on: motion, from: start, at: solutionTime)
            let behavior: TileBehavior
            if safeTier > 12 && index == tileCount - 1 { behavior = .fragile }
            else if index == 0 && safeTier > 8 { behavior = .heavy }
            else { behavior = .normal }
            let targetID = "target-\(index)"
            tiles.append(TileDefinition(
                id: "tile-\(index)",
                suit: suit,
                face: face,
                behavior: behavior,
                team: team,
                position: start,
                rotation: random.float(in: -.pi...(.pi)),
                weight: behavior == .heavy ? 2 : 1,
                canDragWhenFrozen: false,
                canRotateWhenFrozen: false,
                affectedByFreeze: true,
                motion: motion,
                targetIDs: []
            ))
            targets.append(TargetDefinition(
                id: targetID,
                position: targetPoint,
                radius: max(23, 34 - CGFloat(safeTier) * 0.22),
                requiredWeight: behavior == .heavy ? 2 : 0,
                holdDuration: max(0.08, 0.28 - CGFloat(safeTier) * 0.008)
            ))
        }
        let alignedTime = bestAlignmentTime(for: tiles, preferred: solutionTime, cycleDuration: cycleDuration)
        for index in targets.indices {
            targets[index].position = position(on: tiles[index].motion, from: tiles[index].position, at: alignedTime)
        }
        let mechanisms = targets.map { target in
            MechanismDefinition(
                id: "freeze-\(target.id)",
                kind: .freezeZone,
                position: target.position,
                size: WorldSize(target.radius * 2.35, target.radius * 2.35),
                startsActive: true
            )
        }
        let objectives = proceduralObjectives(tileCount: tileCount, tier: safeTier, targets: targets)
        var rules = LevelRules()
        rules.unlimitedFreeze = safeTier < 10
        rules.freezeEnergy = 100
        rules.freezeDrainPerSecond = min(25, 10 + CGFloat(safeTier) * 0.55)
        rules.freezeRecoveryPerSecond = max(3, 8 - CGFloat(safeTier) * 0.16)
        rules.slowMotionEnabled = safeTier >= 8
        rules.rewindEnabled = safeTier >= 14
        rules.rewindSeconds = min(8, 3 + CGFloat(safeTier) * 0.15)
        rules.maxWorldTime = safeTier > 20 ? CGFloat(75 + tileCount * 18) : 0
        rules.collisionEnabled = false
        let basePar = 2 + tileCount + mechanisms.count / 3
        return LevelDefinition(
            id: mode == .daily ? 10_000 : 20_000,
            chapter: 0,
            indexInChapter: 0,
            name: mode == .daily ? "DAILY ALIGNMENT" : "ENDLESS",
            subtitle: "Watch the routes converge, then freeze the board.",
            mode: mode,
            difficulty: safeTier,
            seed: seed,
            boardSize: board,
            tiles: tiles,
            mechanisms: mechanisms,
            targets: targets,
            objectives: objectives,
            rules: rules,
            starThresholds: StarThresholds(
                completionFreezes: basePar + 7,
                twoStarFreezes: basePar + 2,
                threeStarFreezes: basePar,
                twoStarTime: CGFloat(30 + safeTier * 3),
                threeStarTime: CGFloat(18 + safeTier * 2)
            )
        )
    }

    private func proceduralMotion(
        index: Int,
        tier: Int,
        start: WorldPoint,
        archetype: Int,
        cycleDuration: CGFloat,
        random: inout SeededRandom
    ) -> MotionDefinition {
        let unlocked: [MotionType]
        switch tier {
        case 1...3: unlocked = [.linear, .pingPong]
        case 4...7: unlocked = [.linear, .pingPong, .orbit, .rail]
        case 8...13: unlocked = [.pingPong, .orbit, .rail, .pendulum]
        default: unlocked = [.orbit, .rail, .pendulum, .pingPong]
        }
        let type = unlocked[(index + archetype) % unlocked.count]
        let speed = min(105, random.float(in: 42...78) + CGFloat(tier) * 1.2)
        let curve = MotionCurve.allCases[random.int(in: 0...min(tier / 3, MotionCurve.allCases.count - 1))]
        switch type {
        case .linear, .pingPong:
            let end = WorldPoint(-start.x, ScalarMath.clamp(start.y + random.float(in: -65...65), -190, 190))
            let duration = type == .pingPong ? cycleDuration / 2 : cycleDuration
            return MotionDefinition(type: type, points: [start, end], speed: speed, duration: duration, curve: curve)
        case .orbit:
            let radius: CGFloat = 48
            let inward = start.cgPoint.normalized
            let center = WorldPoint(start.cgPoint - inward * radius)
            return MotionDefinition(type: .orbit, points: [center], speed: speed, duration: cycleDuration, curve: curve, radius: radius, phase: 0, clockwise: random.bool())
        case .rail:
            let mid = WorldPoint(random.float(in: -80...80), random.float(in: -130...130))
            let points = [start, mid, WorldPoint(-start.x, -start.y * 0.6)]
            let cgPoints = points.map(\.cgPoint)
            let pathLength = zip(cgPoints, cgPoints.dropFirst()).reduce(CGFloat.zero) { result, pair in
                result + pair.0.distance(to: pair.1)
            }
            return MotionDefinition(type: .rail, points: points, speed: pathLength / cycleDuration, curve: curve)
        case .gravity:
            return MotionDefinition(type: .gravity, points: [WorldPoint(random.float(in: -18...18), 0)], speed: speed, curve: random.bool(chance: 0.35) ? .bounce : .linear, acceleration: WorldPoint(0, -random.float(in: 105...185)))
        case .conveyor:
            return MotionDefinition(type: .conveyor, points: [WorldPoint(random.bool() ? 1 : -1, 0)], speed: speed)
        case .magnetic:
            return MotionDefinition(type: .magnetic, speed: speed)
        case .pendulum:
            let radius = random.float(in: 42...58)
            return MotionDefinition(type: .pendulum, points: [WorldPoint(start.x, start.y + radius)], speed: speed, duration: cycleDuration, radius: radius, phase: random.float(in: 0.5...0.9))
        case .projectile:
            let direction = CGPoint(x: -start.x, y: -start.y).normalized
            return MotionDefinition(type: .projectile, points: [WorldPoint(direction)], speed: speed, acceleration: WorldPoint(0, tier > 18 ? -24 : 0))
        case .stationary:
            return MotionDefinition()
        }
    }

    private func position(on motion: MotionDefinition, from start: WorldPoint, at time: CGFloat) -> WorldPoint {
        let startPoint = start.cgPoint
        switch motion.type {
        case .linear:
            let end = motion.points.last?.cgPoint ?? startPoint
            var progress = time / max(0.01, motion.duration)
            if motion.repeats { progress.formTruncatingRemainder(dividingBy: 1) }
            else { progress = min(1, progress) }
            return WorldPoint(startPoint.lerped(to: end, t: ScalarMath.ease(motion.curve, progress)))
        case .pingPong:
            let end = motion.points.last?.cgPoint ?? startPoint
            let phase = ScalarMath.pingPong(time / max(0.01, motion.duration), length: 1)
            return WorldPoint(startPoint.lerped(to: end, t: ScalarMath.ease(motion.curve, phase)))
        case .orbit:
            let center = motion.points.first?.cgPoint ?? .zero
            let initialAngle = (startPoint - center).angle + motion.phase
            let direction: CGFloat = motion.clockwise ? -1 : 1
            let angle = initialAngle + direction * 2 * .pi / max(0.5, motion.duration) * time
            return WorldPoint(center + CGPoint(x: cos(angle), y: sin(angle)) * motion.radius)
        case .rail:
            let points = motion.points.map(\.cgPoint)
            guard points.count >= 2 else { return start }
            let lengths = zip(points, points.dropFirst()).map { pair in
                pair.0.distance(to: pair.1)
            }
            let total = max(1, lengths.reduce(0, +))
            var travel = time * motion.speed
            if motion.repeats { travel.formTruncatingRemainder(dividingBy: total) }
            else { travel = min(total, travel) }
            for index in lengths.indices {
                if travel <= lengths[index] || index == lengths.count - 1 {
                    let progress = ScalarMath.clamp(travel / max(0.01, lengths[index]), 0, 1)
                    return WorldPoint(points[index].lerped(to: points[index + 1], t: ScalarMath.ease(motion.curve, progress)))
                }
                travel -= lengths[index]
            }
            return WorldPoint(points.last ?? startPoint)
        case .pendulum:
            let pivot = motion.points.first?.cgPoint ?? CGPoint(x: start.x, y: start.y + motion.radius)
            let amplitude = min(.pi * 0.46, max(.pi * 0.08, motion.phase == 0 ? .pi * 0.32 : motion.phase))
            let angle = sin(time / max(0.6, motion.duration) * .pi * 2) * amplitude - .pi / 2
            return WorldPoint(pivot + CGPoint(x: cos(angle), y: sin(angle)) * max(24, motion.radius))
        case .conveyor:
            let direction = motion.points.first?.cgPoint.normalized ?? CGPoint(x: 1, y: 0)
            return WorldPoint(startPoint + direction * motion.speed * time)
        case .projectile:
            let velocity = (motion.points.first?.cgPoint ?? CGPoint(x: 1, y: 0)).normalized * motion.speed
            return WorldPoint(startPoint + velocity * time + motion.acceleration.cgPoint * (0.5 * time * time))
        case .gravity:
            let velocity = motion.points.first?.cgPoint ?? .zero
            return WorldPoint(startPoint + velocity * time + motion.acceleration.cgPoint * (0.5 * time * time))
        case .stationary, .magnetic:
            return start
        }
    }

    private func bestAlignmentTime(for tiles: [TileDefinition], preferred: CGFloat, cycleDuration: CGFloat) -> CGFloat {
        guard !tiles.isEmpty else { return preferred }
        let latest = max(1.2, cycleDuration - 0.55)
        let candidates = [preferred] + (0..<32).map { index in
            ScalarMath.lerp(0.9, latest, CGFloat(index) / 31)
        }
        let targetBounds = CGRect(x: -142, y: -222, width: 284, height: 444)
        var bestTime = preferred
        var bestScore = -CGFloat.greatestFiniteMagnitude

        for time in candidates {
            let points = tiles.map { position(on: $0.motion, from: $0.position, at: time).cgPoint }
            guard points.allSatisfy(targetBounds.contains) else { continue }
            let travel = zip(points, tiles).map { point, tile in
                point.distance(to: tile.position.cgPoint)
            }.min() ?? 0
            var separation: CGFloat = tiles.count == 1 ? 90 : .greatestFiniteMagnitude
            for first in points.indices {
                for second in points.indices where second > first {
                    separation = min(separation, points[first].distance(to: points[second]))
                }
            }
            // Prefer a clean board layout first, then a target far enough from
            // its starting tile to create a readable timing decision.
            let score = min(120, separation) * 3 + min(80, travel)
            if score > bestScore {
                bestScore = score
                bestTime = time
            }
        }
        return bestTime
    }

    private func proceduralObjectives(
        tileCount: Int,
        tier: Int,
        targets: [TargetDefinition]
    ) -> [ObjectiveDefinition] {
        var objectives = [ObjectiveDefinition(
            id: "delivery",
            kind: .simultaneousTargets,
            title: tileCount > 1 ? "Align every tile with its target" : "Wait for the tile to enter its target",
            requiredIDs: targets.map(\.id),
            requiredCount: tileCount
        ), ObjectiveDefinition(
            id: "freeze-alignment",
            kind: .freezeInZone,
            title: tileCount > 1 ? "Freeze while every tile is aligned" : "Freeze while the tile is inside the target",
            requiredCount: 1
        )]
        if tier >= 20 {
            objectives.append(ObjectiveDefinition(id: "efficiency", kind: .survive, title: "Stabilize world time", requiredValue: CGFloat(8 + tileCount * 2), optional: true))
        }
        return objectives
    }

    private func distributedPoint(index: Int, count: Int, radiusX: CGFloat, radiusY: CGFloat, phase: CGFloat) -> WorldPoint {
        let angle = CGFloat(index) / CGFloat(max(1, count)) * .pi * 2 + phase
        return WorldPoint(cos(angle) * radiusX, sin(angle) * radiusY)
    }

    private func face(for suit: MahjongSuit, value: Int, random: inout SeededRandom) -> MahjongFace {
        let numeric: [MahjongFace] = [.one, .two, .three, .four, .five, .six, .seven, .eight, .nine]
        switch suit {
        case .characters, .bamboo, .dots: return numeric[ScalarMath.clamp(value, 1, 9) - 1]
        case .wind: return random.choose([.east, .south, .west, .north])
        case .dragon: return random.choose([.redDragon, .greenDragon, .whiteDragon])
        }
    }

    private func dailyName(archetype: Int) -> String {
        let boardTypes = [
            "CROSSBOARD ROUTE",
            "BRASS CIRCUIT",
            "QUIET PASSAGE",
            "FOLDED LANES",
            "HIDDEN CROSSING",
            "NARROW ALIGNMENT",
            "GEARED TABLE"
        ]
        return boardTypes[archetype % boardTypes.count]
    }

    private func endlessSubtitle(stage: Int, tileCount: Int) -> String {
        let subject = tileCount == 1 ? "the tile enters its target" : "all \(tileCount) tiles align"
        return "Freeze when \(subject). The alignment repeats if you miss it. Stage \(stage)."
    }
}
