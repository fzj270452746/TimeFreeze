import SpriteKit
import Foundation

enum ReplayEventKind: String, Codable {
    case freeze
    case resume
    case slowMotion
    case rewind
    case interaction
    case switchActivated
    case portal
    case collision
    case failure
    case completion
    case snapshot
}

struct ReplayTileState: Codable, Hashable {
    var id: String
    var position: WorldPoint
    var rotation: CGFloat
    var visible: Bool
}

struct ReplayFrame: Codable, Hashable {
    var worldTime: TimeInterval
    var realOffset: TimeInterval
    var event: ReplayEventKind
    var subjectID: String?
    var value: String?
    var tiles: [ReplayTileState]
}

struct ReplayData: Codable {
    var version = 1
    var levelID: Int
    var seed: UInt64
    var recordedAt: Date
    var duration: TimeInterval
    var frames: [ReplayFrame]
    var completed: Bool
    var stars: Int
    var score: Int
}

final class ReplayRecorder {
    private let levelID: Int
    private let seed: UInt64
    private let startedAt = Date()
    private var frames: [ReplayFrame] = []
    private var lastFrameWorldTime: TimeInterval = -1
    private var completedResult: LevelResult?
    private var isFinished = false

    init(levelID: Int, seed: UInt64) {
        self.levelID = levelID
        self.seed = seed
    }

    func update(world: GameWorld) {
        guard !isFinished else { return }
        let worldTime = world.timeController.clock.worldTime
        if lastFrameWorldTime < 0 || worldTime - lastFrameWorldTime >= 0.12 {
            lastFrameWorldTime = worldTime
            append(kind: .snapshot, subjectID: nil, value: nil, worldTime: worldTime, world: world)
        }
    }

    func recordTimeState(_ state: TimeState, worldTime: TimeInterval) {
        let kind: ReplayEventKind
        switch state {
        case .running: kind = .resume
        case .frozen: kind = .freeze
        case .slowMotion: kind = .slowMotion
        case .rewinding: kind = .rewind
        }
        append(kind: kind, subjectID: nil, value: state.rawValue, worldTime: worldTime, world: nil)
    }

    func record(event: GameEvent, worldTime: TimeInterval) {
        switch event {
        case let .switchActivated(id, channel):
            append(kind: .switchActivated, subjectID: id, value: channel, worldTime: worldTime, world: nil)
        case let .portalEntered(tileID, portalID):
            append(kind: .portal, subjectID: tileID, value: portalID, worldTime: worldTime, world: nil)
        case let .tileCollided(firstID, secondID, impulse):
            append(kind: .collision, subjectID: firstID, value: "\(secondID):\(impulse)", worldTime: worldTime, world: nil)
        case let .timeRewound(seconds):
            append(kind: .rewind, subjectID: nil, value: "\(seconds)", worldTime: worldTime, world: nil)
        default: break
        }
    }

    func recordFailure(_ reason: FailureKind, worldTime: TimeInterval) {
        append(kind: .failure, subjectID: nil, value: reason.rawValue, worldTime: worldTime, world: nil)
    }

    func recordCompletion(_ result: LevelResult, worldTime: TimeInterval) {
        completedResult = result
        append(kind: .completion, subjectID: nil, value: "\(result.stars):\(result.score)", worldTime: worldTime, world: nil)
    }

    func finish(world: GameWorld) {
        guard !isFinished else { return }
        isFinished = true
        append(kind: .snapshot, subjectID: nil, value: "final", worldTime: world.timeController.clock.worldTime, world: world)
        let replay = ReplayData(
            levelID: levelID,
            seed: seed,
            recordedAt: startedAt,
            duration: Date().timeIntervalSince(startedAt),
            frames: frames,
            completed: completedResult?.completed ?? false,
            stars: completedResult?.stars ?? 0,
            score: completedResult?.score ?? 0
        )
        ReplayStore.shared.save(replay)
    }

    private func append(
        kind: ReplayEventKind,
        subjectID: String?,
        value: String?,
        worldTime: TimeInterval,
        world: GameWorld?
    ) {
        guard !isFinished || value == "final" else { return }
        let tiles = world?.tiles.map {
            ReplayTileState(id: $0.objectID, position: WorldPoint($0.position), rotation: $0.zRotation, visible: !$0.isDestroyed)
        } ?? []
        frames.append(ReplayFrame(
            worldTime: worldTime,
            realOffset: Date().timeIntervalSince(startedAt),
            event: kind,
            subjectID: subjectID,
            value: value,
            tiles: tiles
        ))
        if frames.count > 3_600 {
            let preservedEvents = frames.filter { $0.event != .snapshot }
            let sampledSnapshots = frames.enumerated().compactMap { index, frame in
                frame.event == .snapshot && index % 2 == 0 ? frame : nil
            }
            frames = (preservedEvents + sampledSnapshots).sorted { $0.realOffset < $1.realOffset }
        }
    }
}

final class ReplayStore {
    static let shared = ReplayStore()
    private let directory: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("TimeFreezeReplays", isDirectory: true)
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func save(_ replay: ReplayData) {
        guard replay.completed, let data = try? encoder.encode(replay) else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url(for: replay.levelID), options: .atomic)
        } catch {
            return
        }
    }

    func load(levelID: Int) -> ReplayData? {
        guard let data = try? Data(contentsOf: url(for: levelID)) else { return nil }
        return try? decoder.decode(ReplayData.self, from: data)
    }

    func removeAll() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func url(for levelID: Int) -> URL {
        directory.appendingPathComponent("level-\(levelID).json")
    }
}

final class GhostReplayNode: SKNode {
    private let replay: ReplayData
    private let definitions: [String: TileDefinition]
    private var ghostTiles: [String: SKNode] = [:]
    private var playbackTime: TimeInterval = 0
    private var frameIndex = 0
    private var isPlaying = false

    init(replay: ReplayData, tileDefinitions: [TileDefinition]) {
        self.replay = replay
        definitions = Dictionary(uniqueKeysWithValues: tileDefinitions.map { ($0.id, $0) })
        super.init()
        name = "ghostReplay"
        zPosition = 25
        alpha = 0.42
        for definition in tileDefinitions {
            let node = MahjongTileRenderer.makeGhost(from: definition, skin: SaveStore.shared.settings.tileSkin)
            node.isHidden = true
            addChild(node)
            ghostTiles[definition.id] = node
        }
    }

    required init?(coder aDecoder: NSCoder) { nil }

    func play() {
        playbackTime = 0
        frameIndex = 0
        isPlaying = true
    }

    func stop() {
        isPlaying = false
        ghostTiles.values.forEach { $0.isHidden = true }
    }

    func update(deltaTime: TimeInterval) {
        guard isPlaying, !replay.frames.isEmpty else { return }
        playbackTime += deltaTime
        while frameIndex + 1 < replay.frames.count && replay.frames[frameIndex + 1].realOffset <= playbackTime {
            frameIndex += 1
        }
        guard let currentIndex = previousSnapshotIndex(from: frameIndex) else { return }
        let current = replay.frames[currentIndex]
        let nextIndex = nextSnapshotIndex(from: currentIndex)
        let next = nextIndex.map { replay.frames[$0] }
        let t: CGFloat
        if let next, next.realOffset > current.realOffset {
            t = CGFloat((playbackTime - current.realOffset) / (next.realOffset - current.realOffset))
        } else {
            t = 0
        }
        apply(current: current, next: next, t: ScalarMath.clamp(t, 0, 1))
        if frameIndex >= replay.frames.count - 1 { stop() }
    }

    private func apply(current: ReplayFrame, next: ReplayFrame?, t: CGFloat) {
        let nextStates = Dictionary(uniqueKeysWithValues: (next?.tiles ?? []).map { ($0.id, $0) })
        for state in current.tiles {
            guard let node = ghostTiles[state.id] else { continue }
            node.isHidden = !state.visible
            if let nextState = nextStates[state.id] {
                node.position = state.position.cgPoint.lerped(to: nextState.position.cgPoint, t: t)
                node.zRotation = state.rotation + ScalarMath.shortestAngle(from: state.rotation, to: nextState.rotation) * t
                node.isHidden = !state.visible && !nextState.visible
            } else {
                node.position = state.position.cgPoint
                node.zRotation = state.rotation
            }
        }
    }

    private func previousSnapshotIndex(from index: Int) -> Int? {
        guard index >= 0 else { return nil }
        return stride(from: index, through: 0, by: -1).first { !replay.frames[$0].tiles.isEmpty }
    }

    private func nextSnapshotIndex(from index: Int) -> Int? {
        guard index + 1 < replay.frames.count else { return nil }
        return ((index + 1)..<replay.frames.count).first { !replay.frames[$0].tiles.isEmpty }
    }
}
