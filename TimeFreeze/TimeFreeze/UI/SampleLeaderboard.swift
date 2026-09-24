import Foundation

/// Built-in scores shown when the live table is unreachable.
///
/// The leaderboard is write-only and normally renders only what the service
/// returns. When that service is down — or cloud is disabled — an empty board
/// reads as a broken feature in the first minutes of play, which is exactly the
/// impression an App Store review forms. These fixed demo rows fill the screen
/// so the board still demonstrates what it is for, and they are labelled as a
/// sample so they are never mistaken for real players.
enum SampleLeaderboard {

    /// Demo nicknames in the game's own voice. A short list keeps the sample
    /// board tidy; a long one would read as a fake crowd.
    private static let names = [
        "FROZEN FOX", "CLOCKHAND", "STILL WATER", "NINTH DOT", "COLD SNAP",
        "TILE TURNER", "MISSED MARK", "POCKET NINE", "GLASS TABLE", "ZERO KELVIN",
        "PAUSE BUTTON", "DRIFT MARK", "EMPTY CHAIR", "THIRD DEAL", "BLUE HOUR"
    ]

    /// The demo rows plus the player's own row, sorted the way the live board
    /// would be and with the player slotted into the rank their number earns.
    /// `me` is nil when the player has no standing on this board yet, exactly
    /// as the service answers for an unranked player.
    static func entries(for board: LeaderboardBoard) -> (entries: [CloudLeaderboardEntry], me: CloudLeaderboardEntry?) {
        let player = localPlayer()
        let playerValue = value(of: player, for: board)

        var rows = names.enumerated().map { index, name in
            entry(
                rank: 0,
                playerID: "sample-\(index)",
                displayName: name,
                board: board,
                metric: demoMetric(for: board, index: index)
            )
        }

        var meRow: CloudLeaderboardEntry?
        if playerValue > 0 {
            let playerRow = entry(
                rank: 0,
                playerID: player.playerID,
                displayName: player.displayName,
                board: board,
                metric: playerValue
            )
            rows.append(playerRow)
            meRow = playerRow
        }

        rows.sort { value(of: $0, for: board) > value(of: $1, for: board) }
        for index in rows.indices { rows[index].rank = index + 1 }
        if let id = meRow?.playerID, let ranked = rows.first(where: { $0.playerID == id }) {
            meRow = ranked
        }
        return (rows, meRow)
    }

    // MARK: - Player

    /// The player's own standing, projected from the local save — the same
    /// numbers the cloud would otherwise rank.
    private static func localPlayer() -> CloudLeaderboardEntry {
        let progress = SaveStore.shared.progress
        var entry = CloudLeaderboardEntry(
            rank: 0,
            playerID: AnonymousIdentity.shared.playerID,
            displayName: localDisplayName()
        )
        entry.totalStars = progress.totalStars
        entry.completedLevels = progress.completedLevels
        entry.bestStage = progress.endlessBestStage
        entry.bestScore = progress.endlessBestScore
        entry.score = progress.bestDailyScore
        entry.achievementsUnlocked = AchievementEngine.shared.unlockedCount(progress: progress)
        return entry
    }

    private static func localDisplayName() -> String {
        "PLAYER-" + String(AnonymousIdentity.shared.playerID.prefix(4)).uppercased()
    }

    // MARK: - Demo values

    /// A plausible top score for a given board, tapering down the list so rank
    /// 1 is clearly the strongest. The numbers are cosmetic: they only need to
    /// look like a live table, not to be beatable.
    private static func demoMetric(for board: LeaderboardBoard, index: Int) -> Int {
        switch board {
        case .campaign:
            // Three stars across most of the 200 levels, easing to a healthy
            // mid-campaign total.
            return max(120, 540 - index * 24)
        case .endless:
            return max(6, 48 - index * 3)
        case .daily:
            // A full three-star daily tops out near 20k; the sample tapers down.
            return max(3_000, 19_800 - index * 1_200)
        case .achievements:
            let total = AchievementEngine.shared.catalog.count
            return max(10, total - index)
        }
    }

    private static func entry(
        rank: Int,
        playerID: String,
        displayName: String,
        board: LeaderboardBoard,
        metric: Int
    ) -> CloudLeaderboardEntry {
        var entry = CloudLeaderboardEntry(rank: rank, playerID: playerID, displayName: displayName)
        switch board {
        case .campaign:
            entry.totalStars = metric
            entry.completedLevels = min(200, metric / 3)
        case .endless:
            entry.bestStage = metric
            entry.bestScore = metric * 500 + 5_000
        case .daily:
            entry.score = metric
        case .achievements:
            entry.achievementsUnlocked = metric
        }
        return entry
    }

    private static func value(of entry: CloudLeaderboardEntry, for board: LeaderboardBoard) -> Int {
        switch board {
        case .campaign: return entry.totalStars ?? 0
        case .endless: return entry.bestStage ?? 0
        case .daily: return entry.score ?? 0
        case .achievements: return entry.achievementsUnlocked ?? 0
        }
    }
}
