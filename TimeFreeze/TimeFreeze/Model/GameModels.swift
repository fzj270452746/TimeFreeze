import CoreGraphics
import Foundation

enum AppFlowState: String, Codable {
    case boot
    case onboarding
    case menu
    case chapterSelect
    case levelSelect
    case levelLoading
    case playing
    case frozen
    case slowMotion
    case success
    case failure
    case paused
    case settings
    case mastery
    case leaderboard
    case skins
    case transition
}

enum TimeState: String, Codable, CaseIterable {
    case running
    case frozen
    case slowMotion
    case rewinding

    var scale: CGFloat {
        switch self {
        case .running: return 1
        case .frozen: return 0
        case .slowMotion: return 0.25
        case .rewinding: return 0
        }
    }
}

enum GameMode: String, Codable, CaseIterable {
    case classic
    case timing
    case routing
    case mechanism
    case multiTile
    case chainReaction
    case precision
    case endless
    case daily

    var displayName: String {
        switch self {
        case .classic: return "CLASSIC FREEZE"
        case .timing: return "TIMING"
        case .routing: return "ROUTING"
        case .mechanism: return "MECHANISM"
        case .multiTile: return "MULTI-TILE"
        case .chainReaction: return "CHAIN REACTION"
        case .precision: return "PRECISION"
        case .endless: return "ENDLESS"
        case .daily: return "DAILY"
        }
    }
}

enum MahjongSuit: String, Codable, CaseIterable {
    case characters
    case bamboo
    case dots
    case wind
    case dragon

    var shortName: String {
        switch self {
        case .characters: return "WAN"
        case .bamboo: return "BAM"
        case .dots: return "DOT"
        case .wind: return "WIND"
        case .dragon: return "DRAGON"
        }
    }
}

enum MahjongFace: String, Codable, CaseIterable {
    case one, two, three, four, five, six, seven, eight, nine
    case east, south, west, north
    case redDragon, greenDragon, whiteDragon

    var numericValue: Int? {
        switch self {
        case .one: return 1
        case .two: return 2
        case .three: return 3
        case .four: return 4
        case .five: return 5
        case .six: return 6
        case .seven: return 7
        case .eight: return 8
        case .nine: return 9
        default: return nil
        }
    }

    var glyph: String {
        switch self {
        case .one: return "1"
        case .two: return "2"
        case .three: return "3"
        case .four: return "4"
        case .five: return "5"
        case .six: return "6"
        case .seven: return "7"
        case .eight: return "8"
        case .nine: return "9"
        case .east: return "E"
        case .south: return "S"
        case .west: return "W"
        case .north: return "N"
        case .redDragon: return "R"
        case .greenDragon: return "G"
        case .whiteDragon: return "W"
        }
    }
}

enum TileBehavior: String, Codable, CaseIterable {
    case normal
    case directional
    case key
    case activator
    case heavy
    case fragile
    case ghost
}

enum TileTeam: String, Codable, CaseIterable {
    case ivory
    case jade
    case red
    case blue
    case gold
}

enum MotionType: String, Codable, CaseIterable {
    case stationary
    case linear
    case pingPong
    case orbit
    case rail
    case gravity
    case conveyor
    case magnetic
    case pendulum
    case projectile
}

enum MotionCurve: String, Codable, CaseIterable {
    case linear
    case easeIn
    case easeOut
    case easeInOut
    case sine
    case bounce
    case elastic
}

enum MechanismKind: String, Codable, CaseIterable {
    case gate
    case rotatingGate
    case switchControl
    case pressurePlate
    case conveyor
    case portal
    case elevator
    case magnet
    case mirror
    case rotatingPlatform
    case pendulum
    case freezeZone
    case noFreezeZone
    case reverseZone
    case partialFreezeZone
    case hazard
    case bridge
}

enum ObjectiveKind: String, Codable, CaseIterable {
    case reachTarget
    case freezeInZone
    case activateAll
    case orderedSwitches
    case matchingTiles
    case sameSuit
    case totalWeight
    case protectTile
    case simultaneousTargets
    case survive
}

enum FailureKind: String, Codable, CaseIterable {
    case outOfBounds
    case wrongTarget
    case freezeMissed
    case freezeLimitReached
    case hazardCollision
    case fragileDestroyed
    case mechanismLocked
    case worldTimeExpired
    case wrongSequence

    var message: String {
        switch self {
        case .outOfBounds: return "A TILE LEFT THE TABLE"
        case .wrongTarget: return "WRONG TILE"
        case .freezeMissed: return "MISSED FREEZE WINDOW"
        case .freezeLimitReached: return "NO FREEZES LEFT"
        case .hazardCollision: return "TIME COLLISION"
        case .fragileDestroyed: return "FRAGILE TILE BROKE"
        case .mechanismLocked: return "MECHANISM LOCKED"
        case .worldTimeExpired: return "WORLD TIME EXPIRED"
        case .wrongSequence: return "SEQUENCE RESET"
        }
    }
}

struct WorldPoint: Codable, Hashable {
    var x: CGFloat
    var y: CGFloat

    init(_ x: CGFloat, _ y: CGFloat) {
        self.x = x
        self.y = y
    }

    init(_ point: CGPoint) {
        x = point.x
        y = point.y
    }

    var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}

struct WorldSize: Codable, Hashable {
    var width: CGFloat
    var height: CGFloat

    init(_ width: CGFloat, _ height: CGFloat) {
        self.width = width
        self.height = height
    }

    var cgSize: CGSize { CGSize(width: width, height: height) }
}

struct MotionDefinition: Codable, Hashable {
    var type: MotionType
    var points: [WorldPoint]
    var speed: CGFloat
    var duration: CGFloat
    var curve: MotionCurve
    var radius: CGFloat
    var phase: CGFloat
    var clockwise: Bool
    var repeats: Bool
    var acceleration: WorldPoint

    init(
        type: MotionType = .stationary,
        points: [WorldPoint] = [],
        speed: CGFloat = 70,
        duration: CGFloat = 3,
        curve: MotionCurve = .linear,
        radius: CGFloat = 60,
        phase: CGFloat = 0,
        clockwise: Bool = true,
        repeats: Bool = true,
        acceleration: WorldPoint = WorldPoint(0, -180)
    ) {
        self.type = type
        self.points = points
        self.speed = speed
        self.duration = duration
        self.curve = curve
        self.radius = radius
        self.phase = phase
        self.clockwise = clockwise
        self.repeats = repeats
        self.acceleration = acceleration
    }
}

struct TileDefinition: Codable, Hashable, Identifiable {
    var id: String
    var suit: MahjongSuit
    var face: MahjongFace
    var behavior: TileBehavior
    var team: TileTeam
    var position: WorldPoint
    var rotation: CGFloat
    var weight: Int
    var collisionRadius: CGFloat
    var canDragWhenFrozen: Bool
    var canRotateWhenFrozen: Bool
    var affectedByFreeze: Bool
    var motion: MotionDefinition
    var targetIDs: [String]

    init(
        id: String,
        suit: MahjongSuit,
        face: MahjongFace,
        behavior: TileBehavior = .normal,
        team: TileTeam = .ivory,
        position: WorldPoint,
        rotation: CGFloat = 0,
        weight: Int = 1,
        collisionRadius: CGFloat = 18,
        canDragWhenFrozen: Bool = false,
        canRotateWhenFrozen: Bool = false,
        affectedByFreeze: Bool = true,
        motion: MotionDefinition,
        targetIDs: [String] = []
    ) {
        self.id = id
        self.suit = suit
        self.face = face
        self.behavior = behavior
        self.team = team
        self.position = position
        self.rotation = rotation
        self.weight = weight
        self.collisionRadius = collisionRadius
        self.canDragWhenFrozen = canDragWhenFrozen
        self.canRotateWhenFrozen = canRotateWhenFrozen
        self.affectedByFreeze = affectedByFreeze
        self.motion = motion
        self.targetIDs = targetIDs
    }
}

struct MechanismDefinition: Codable, Hashable, Identifiable {
    var id: String
    var kind: MechanismKind
    var position: WorldPoint
    var size: WorldSize
    var rotation: CGFloat
    var channel: String
    var linkedIDs: [String]
    var startsActive: Bool
    var period: CGFloat
    var phase: CGFloat
    var threshold: Int
    var direction: WorldPoint
    var strength: CGFloat
    var canInteractWhenFrozen: Bool
    var selectiveTeams: [TileTeam]
    var metadata: [String: String]

    init(
        id: String,
        kind: MechanismKind,
        position: WorldPoint,
        size: WorldSize = WorldSize(54, 54),
        rotation: CGFloat = 0,
        channel: String = "default",
        linkedIDs: [String] = [],
        startsActive: Bool = false,
        period: CGFloat = 2.5,
        phase: CGFloat = 0,
        threshold: Int = 1,
        direction: WorldPoint = WorldPoint(1, 0),
        strength: CGFloat = 80,
        canInteractWhenFrozen: Bool = false,
        selectiveTeams: [TileTeam] = [],
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.kind = kind
        self.position = position
        self.size = size
        self.rotation = rotation
        self.channel = channel
        self.linkedIDs = linkedIDs
        self.startsActive = startsActive
        self.period = period
        self.phase = phase
        self.threshold = threshold
        self.direction = direction
        self.strength = strength
        self.canInteractWhenFrozen = canInteractWhenFrozen
        self.selectiveTeams = selectiveTeams
        self.metadata = metadata
    }
}

struct TargetDefinition: Codable, Hashable, Identifiable {
    var id: String
    var position: WorldPoint
    var radius: CGFloat
    var acceptsSuit: MahjongSuit?
    var acceptsFace: MahjongFace?
    var acceptsTeam: TileTeam?
    var requiredWeight: Int
    var holdDuration: CGFloat
    var channel: String

    init(
        id: String,
        position: WorldPoint,
        radius: CGFloat = 31,
        acceptsSuit: MahjongSuit? = nil,
        acceptsFace: MahjongFace? = nil,
        acceptsTeam: TileTeam? = nil,
        requiredWeight: Int = 0,
        holdDuration: CGFloat = 0.2,
        channel: String = "default"
    ) {
        self.id = id
        self.position = position
        self.radius = radius
        self.acceptsSuit = acceptsSuit
        self.acceptsFace = acceptsFace
        self.acceptsTeam = acceptsTeam
        self.requiredWeight = requiredWeight
        self.holdDuration = holdDuration
        self.channel = channel
    }
}

struct ObjectiveDefinition: Codable, Hashable, Identifiable {
    var id: String
    var kind: ObjectiveKind
    var title: String
    var requiredIDs: [String]
    var requiredCount: Int
    var requiredValue: CGFloat
    var optional: Bool

    init(
        id: String,
        kind: ObjectiveKind,
        title: String,
        requiredIDs: [String] = [],
        requiredCount: Int = 1,
        requiredValue: CGFloat = 0,
        optional: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.requiredIDs = requiredIDs
        self.requiredCount = requiredCount
        self.requiredValue = requiredValue
        self.optional = optional
    }
}

struct LevelRules: Codable, Hashable {
    var freezeEnabled: Bool = true
    var unlimitedFreeze: Bool = true
    /// Zero means there is no per-level Freeze count limit.
    var maximumFreezes: Int = 0
    var freezeEnergy: CGFloat = 100
    var freezeDrainPerSecond: CGFloat = 14
    var freezeRecoveryPerSecond: CGFloat = 7
    var slowMotionEnabled: Bool = false
    var rewindEnabled: Bool = false
    var rewindSeconds: CGFloat = 4
    var maxWorldTime: CGFloat = 0
    var maximumDrags: Int = 0
    var maximumRotations: Int = 0
    var failWhenTileLeavesBoard: Bool = true
    var collisionEnabled: Bool = true
    var tutorialKey: String?

    init() {}
}

struct StarThresholds: Codable, Hashable {
    var completionFreezes: Int
    var twoStarFreezes: Int
    var threeStarFreezes: Int
    var twoStarTime: CGFloat
    var threeStarTime: CGFloat

    init(
        completionFreezes: Int = 99,
        twoStarFreezes: Int,
        threeStarFreezes: Int,
        twoStarTime: CGFloat = 0,
        threeStarTime: CGFloat = 0
    ) {
        self.completionFreezes = completionFreezes
        self.twoStarFreezes = twoStarFreezes
        self.threeStarFreezes = threeStarFreezes
        self.twoStarTime = twoStarTime
        self.threeStarTime = threeStarTime
    }

    func stars(freezes: Int, time: CGFloat) -> Int {
        var result = 1
        if freezes <= twoStarFreezes || (twoStarTime > 0 && time <= twoStarTime) { result = 2 }
        if freezes <= threeStarFreezes || (threeStarTime > 0 && time <= threeStarTime) { result = 3 }
        return result
    }
}

struct LevelDefinition: Codable, Hashable, Identifiable {
    var id: Int
    var chapter: Int
    var indexInChapter: Int
    var name: String
    var subtitle: String
    var mode: GameMode
    var difficulty: Int
    var seed: UInt64
    var boardSize: WorldSize
    var tiles: [TileDefinition]
    var mechanisms: [MechanismDefinition]
    var targets: [TargetDefinition]
    var objectives: [ObjectiveDefinition]
    var rules: LevelRules
    var starThresholds: StarThresholds

    var displayNumber: String { String(format: "%03d", id) }
    var chapterName: String { GameText.chapterNames[max(0, min(9, chapter - 1))] }
}

struct LevelResult: Codable, Hashable {
    var levelID: Int
    var completed: Bool
    var stars: Int
    var freezeCount: Int
    var worldTime: CGFloat
    var realTime: CGFloat
    var interactions: Int
    var rewinds: Int
    var completedAt: Date
    var mode: GameMode
    var score: Int

    static func score(stars: Int, freezes: Int, worldTime: CGFloat, difficulty: Int) -> Int {
        let starValue = stars * 5_000
        let efficiency = max(0, 3_000 - freezes * 180)
        let speed = max(0, 2_000 - Int(worldTime * 20))
        return starValue + efficiency + speed + difficulty * 250
    }
}

struct GameSettings: Codable, Equatable {
    var soundEnabled = true
    var ambientEnabled = true
    var hapticsEnabled = true
    var reduceMotion = false
    var highContrast = false
    var tutorialHints = true
    var leftHandedControls = false
    var audioVolume: CGFloat = 0.75
    var tileSkin: TileSkin = .classic

    static let standard = GameSettings()

    init() {}

    /// Decoded field by field rather than with the synthesised decoder: a
    /// settings blob written before `tileSkin` existed lacks that key, and the
    /// synthesised decoder would reject the whole blob and silently fall back to
    /// `.standard`, dropping the player's sound, haptics and other preferences.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        soundEnabled = try container.decodeIfPresent(Bool.self, forKey: .soundEnabled) ?? true
        ambientEnabled = try container.decodeIfPresent(Bool.self, forKey: .ambientEnabled) ?? true
        hapticsEnabled = try container.decodeIfPresent(Bool.self, forKey: .hapticsEnabled) ?? true
        reduceMotion = try container.decodeIfPresent(Bool.self, forKey: .reduceMotion) ?? false
        highContrast = try container.decodeIfPresent(Bool.self, forKey: .highContrast) ?? false
        tutorialHints = try container.decodeIfPresent(Bool.self, forKey: .tutorialHints) ?? true
        leftHandedControls = try container.decodeIfPresent(Bool.self, forKey: .leftHandedControls) ?? false
        audioVolume = try container.decodeIfPresent(CGFloat.self, forKey: .audioVolume) ?? 0.75
        tileSkin = try container.decodeIfPresent(TileSkin.self, forKey: .tileSkin) ?? .classic
    }
}

struct LevelProgress: Codable, Hashable {
    var levelID: Int
    var stars: Int
    var bestFreezes: Int
    var bestWorldTime: CGFloat
    var bestScore: Int
    var completionCount: Int
    var lastPlayed: Date

    init(levelID: Int) {
        self.levelID = levelID
        stars = 0
        bestFreezes = 0
        bestWorldTime = 0
        bestScore = 0
        completionCount = 0
        lastPlayed = Date()
    }

    init(result: LevelResult) {
        levelID = result.levelID
        stars = result.stars
        bestFreezes = result.freezeCount
        bestWorldTime = result.worldTime
        bestScore = result.score
        completionCount = result.completed ? 1 : 0
        lastPlayed = result.completedAt
    }

    mutating func merge(_ result: LevelResult) {
        if stars == 0 && completionCount == 0 && result.completed {
            self = LevelProgress(result: result)
            return
        }
        stars = max(stars, result.stars)
        bestFreezes = min(bestFreezes, result.freezeCount)
        bestWorldTime = min(bestWorldTime, result.worldTime)
        bestScore = max(bestScore, result.score)
        if result.completed { completionCount += 1 }
        lastPlayed = result.completedAt
    }
}

struct PlayerProgress: Codable {
    var version = 1
    var levels: [Int: LevelProgress] = [:]
    var lastLevelID = 1
    var totalFreezes = 0
    var totalWorldTime: CGFloat = 0
    var totalRewinds = 0
    var endlessBestScore = 0
    var endlessBestStage = 0
    var dailyResults: [String: LevelResult] = [:]
    var tutorialKeysSeen: Set<String> = []
    var hasSeenOnboarding = false
    var firstLaunch = Date()
    var lastLaunch = Date()
    var currentStreak = 0
    var bestStreak = 0

    /// Monotonic daily aggregates. `dailyResults` is trimmed on every write, so
    /// totals that must never shrink are accumulated here instead of being
    /// derived from the dictionary.
    var dailyCompletionCount = 0
    var bestDailyScore = 0
    /// Day keys (`yyyyMMdd`) with a completed daily challenge. Trimmed to the
    /// most recent `retainedActiveDays`; day keys sort chronologically as text.
    var dailyActiveDays: Set<String> = []

    /// How many day keys `dailyResults` keeps before the oldest are dropped.
    static let retainedDailyResults = 90
    /// How many day keys `dailyActiveDays` keeps.
    static let retainedActiveDays = 366

    /// Decoded key by key rather than with the synthesised decoder: the
    /// synthesised one ignores property defaults, so adding a field here would
    /// fail to decode every existing save and silently reset the player.
    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        levels = try container.decodeIfPresent([Int: LevelProgress].self, forKey: .levels) ?? [:]
        lastLevelID = try container.decodeIfPresent(Int.self, forKey: .lastLevelID) ?? 1
        totalFreezes = try container.decodeIfPresent(Int.self, forKey: .totalFreezes) ?? 0
        totalWorldTime = try container.decodeIfPresent(CGFloat.self, forKey: .totalWorldTime) ?? 0
        totalRewinds = try container.decodeIfPresent(Int.self, forKey: .totalRewinds) ?? 0
        endlessBestScore = try container.decodeIfPresent(Int.self, forKey: .endlessBestScore) ?? 0
        endlessBestStage = try container.decodeIfPresent(Int.self, forKey: .endlessBestStage) ?? 0
        dailyResults = try container.decodeIfPresent([String: LevelResult].self, forKey: .dailyResults) ?? [:]
        tutorialKeysSeen = try container.decodeIfPresent(Set<String>.self, forKey: .tutorialKeysSeen) ?? []
        hasSeenOnboarding = try container.decodeIfPresent(Bool.self, forKey: .hasSeenOnboarding) ?? false
        firstLaunch = try container.decodeIfPresent(Date.self, forKey: .firstLaunch) ?? Date()
        lastLaunch = try container.decodeIfPresent(Date.self, forKey: .lastLaunch) ?? Date()
        currentStreak = try container.decodeIfPresent(Int.self, forKey: .currentStreak) ?? 0
        bestStreak = try container.decodeIfPresent(Int.self, forKey: .bestStreak) ?? 0
        // Saves written before these fields existed derive them from whatever
        // daily history they still carry, so the totals do not start at zero.
        let storedDaily = dailyResults.values
        dailyCompletionCount = try container.decodeIfPresent(Int.self, forKey: .dailyCompletionCount)
            ?? storedDaily.filter(\.completed).count
        bestDailyScore = try container.decodeIfPresent(Int.self, forKey: .bestDailyScore)
            ?? (storedDaily.map(\.score).max() ?? 0)
        dailyActiveDays = try container.decodeIfPresent(Set<String>.self, forKey: .dailyActiveDays)
            ?? Set(dailyResults.filter(\.value.completed).keys)
    }

    var totalStars: Int { levels.values.reduce(0) { $0 + $1.stars } }
    var completedLevels: Int { levels.values.filter { $0.stars > 0 }.count }

    /// Drops the oldest daily history so the save file stays bounded however
    /// long the app is kept. Called on every daily write.
    mutating func trimDailyHistory() {
        if dailyResults.count > Self.retainedDailyResults {
            let kept = dailyResults.keys.sorted(by: >).prefix(Self.retainedDailyResults)
            dailyResults = dailyResults.filter { kept.contains($0.key) }
        }
        if dailyActiveDays.count > Self.retainedActiveDays {
            dailyActiveDays = Set(dailyActiveDays.sorted(by: >).prefix(Self.retainedActiveDays))
        }
    }

    func isLevelUnlocked(_ id: Int) -> Bool {
        id == 1 || levels[id] != nil || levels[id - 1]?.stars ?? 0 > 0
    }

    func chapterStars(_ chapter: Int) -> Int {
        let range = ((chapter - 1) * 20 + 1)...(chapter * 20)
        return range.reduce(0) { $0 + (levels[$1]?.stars ?? 0) }
    }

    func isChapterUnlocked(_ chapter: Int) -> Bool {
        chapter == 1 || levels[(chapter - 1) * 20]?.stars ?? 0 > 0
    }
}
