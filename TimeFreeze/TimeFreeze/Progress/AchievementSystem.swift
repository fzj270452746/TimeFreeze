import Foundation

enum AchievementCategory: String, Codable, CaseIterable {
    case campaign
    case efficiency
    case mastery
    case endless
    case daily
    case timeControl
    case dedication

    var title: String {
        switch self {
        case .campaign: return "CAMPAIGN"
        case .efficiency: return "EFFICIENCY"
        case .mastery: return "MASTERY"
        case .endless: return "ENDLESS"
        case .daily: return "DAILY"
        case .timeControl: return "TIME CONTROL"
        case .dedication: return "DEDICATION"
        }
    }
}

enum AchievementMetric: Codable, Hashable {
    case completedLevels
    case totalStars
    case perfectLevels
    case completedChapter(Int)
    case endlessStage
    case endlessScore
    case dailyCompletions
    case dailyStreak
    case totalFreezes
    case totalRewinds
    case totalWorldMinutes
    case levelCompletions(Int)
    case lowFreezeCompletions(maximum: Int)
    case chapterStars(Int)
    case perfectChapters
    case totalCompletions
    case replayedLevels
    case fastCompletions(maximumSeconds: Int)
    case bestDailyScore
    case activeDays
    case accountAgeDays

    func value(in progress: PlayerProgress) -> Int {
        switch self {
        case .completedLevels:
            return progress.completedLevels
        case .totalStars:
            return progress.totalStars
        case .perfectLevels:
            return progress.levels.values.filter { $0.stars == 3 }.count
        case let .completedChapter(chapter):
            let lastID = ScalarMath.clamp(chapter, 1, 10) * 20
            return progress.levels[lastID]?.stars ?? 0 > 0 ? 1 : 0
        case .endlessStage:
            return progress.endlessBestStage
        case .endlessScore:
            return progress.endlessBestScore
        case .dailyCompletions:
            return progress.dailyCompletionCount
        case .dailyStreak:
            return progress.bestStreak
        case .totalFreezes:
            return progress.totalFreezes
        case .totalRewinds:
            return progress.totalRewinds
        case .totalWorldMinutes:
            return Int(progress.totalWorldTime / 60)
        case let .levelCompletions(id):
            return progress.levels[id]?.completionCount ?? 0
        case let .lowFreezeCompletions(maximum):
            // The `stars > 0` guard is what keeps the count to boards actually
            // solved. `markLevelStarted` writes a zeroed record the moment a
            // board opens, and a failed attempt never clears it, so without the
            // guard every board merely *opened* would count as a tidy solve.
            return progress.levels.values.filter { $0.stars > 0 && $0.bestFreezes <= maximum }.count
        case let .chapterStars(chapter):
            return progress.chapterStars(ScalarMath.clamp(chapter, 1, 10))
        case .perfectChapters:
            return (1...10).filter { progress.chapterStars($0) == 60 }.count
        case .totalCompletions:
            return progress.levels.values.reduce(0) { $0 + $1.completionCount }
        case .replayedLevels:
            return progress.levels.values.filter { $0.completionCount > 1 }.count
        case let .fastCompletions(maximumSeconds):
            // `bestWorldTime > 0` excludes boards opened but never solved, which
            // would otherwise pass a `<=` test against any positive target.
            return progress.levels.values.filter {
                $0.stars > 0 && $0.bestWorldTime > 0 && $0.bestWorldTime <= CGFloat(maximumSeconds)
            }.count
        case .bestDailyScore:
            return progress.bestDailyScore
        case .activeDays:
            return PlayerStatisticsCalculator.shared.activeDayCount(progress: progress)
        case .accountAgeDays:
            let calendar = Calendar(identifier: .gregorian)
            let days = calendar.dateComponents([.day], from: progress.firstLaunch, to: Date()).day ?? 0
            return max(0, days)
        }
    }
}

struct AchievementDefinition: Identifiable, Hashable {
    var id: String
    var title: String
    var detail: String
    var category: AchievementCategory
    var metric: AchievementMetric
    var target: Int
    var tier: Int
    var hidden: Bool

    func evaluation(in progress: PlayerProgress) -> AchievementEvaluation {
        let current = metric.value(in: progress)
        return AchievementEvaluation(
            definition: self,
            current: min(current, target),
            target: target,
            isUnlocked: current >= target,
            progress: target > 0 ? min(1, CGFloat(current) / CGFloat(target)) : 1
        )
    }
}

struct AchievementEvaluation {
    var definition: AchievementDefinition
    var current: Int
    var target: Int
    var isUnlocked: Bool
    var progress: CGFloat
}

final class AchievementEngine {
    static let shared = AchievementEngine()

    let catalog: [AchievementDefinition]

    private init() {
        catalog = [
            // MARK: Campaign
            AchievementDefinition(id: "first-moment", title: "TILE ON MARK", detail: "Complete Opening Window", category: .campaign, metric: .completedLevels, target: 1, tier: 1, hidden: false),
            AchievementDefinition(id: "chapter-one", title: "RULES LEARNED", detail: "Clear all 20 Foundations boards", category: .campaign, metric: .completedChapter(1), target: 1, tier: 1, hidden: false),
            AchievementDefinition(id: "chapter-two", title: "MOVEMENT MASTERED", detail: "Clear all 20 Moving World boards", category: .campaign, metric: .completedChapter(2), target: 1, tier: 1, hidden: false),
            AchievementDefinition(id: "gatekeeper", title: "CONTROL ROOM KEY", detail: "Clear all 20 Moving Gates boards", category: .campaign, metric: .completedChapter(3), target: 1, tier: 1, hidden: false),
            AchievementDefinition(id: "chapter-four", title: "TABLE HAND", detail: "Clear all 20 Tile Control boards", category: .campaign, metric: .completedChapter(4), target: 1, tier: 1, hidden: false),
            AchievementDefinition(id: "chapter-five", title: "WIND AND MIRROR", detail: "Clear all 20 Direction boards", category: .campaign, metric: .completedChapter(5), target: 1, tier: 2, hidden: false),
            AchievementDefinition(id: "chapter-six", title: "WEIGHTLESS", detail: "Clear all 20 Gravity boards", category: .campaign, metric: .completedChapter(6), target: 1, tier: 2, hidden: false),
            AchievementDefinition(id: "space-folder", title: "NETWORK MAPPED", detail: "Clear all 20 Portals boards", category: .campaign, metric: .completedChapter(7), target: 1, tier: 2, hidden: false),
            AchievementDefinition(id: "clockwork", title: "ALL SYSTEMS RUNNING", detail: "Clear all 20 Machines boards", category: .campaign, metric: .completedChapter(8), target: 1, tier: 2, hidden: false),
            AchievementDefinition(id: "chapter-nine", title: "CHAIN COMPLETE", detail: "Clear all 20 Chain Reaction boards", category: .campaign, metric: .completedChapter(9), target: 1, tier: 3, hidden: false),
            AchievementDefinition(id: "chapter-ten", title: "MASTER OF THE TABLE", detail: "Clear all 20 Master Table boards", category: .campaign, metric: .completedChapter(10), target: 1, tier: 3, hidden: false),
            AchievementDefinition(id: "campaign-100", title: "HUNDRED BOARDS", detail: "Complete 100 campaign boards", category: .campaign, metric: .completedLevels, target: 100, tier: 2, hidden: false),
            AchievementDefinition(id: "time-master", title: "TABLE CLEARED", detail: "Complete all 200 campaign boards", category: .campaign, metric: .completedLevels, target: 200, tier: 3, hidden: false),

            // MARK: Mastery
            AchievementDefinition(id: "stars-30", title: "BRASS RACK", detail: "Earn 30 campaign stars", category: .mastery, metric: .totalStars, target: 30, tier: 1, hidden: false),
            AchievementDefinition(id: "stars-60", title: "FIRST RACK FILLED", detail: "Earn 60 campaign stars", category: .mastery, metric: .totalStars, target: 60, tier: 1, hidden: false),
            AchievementDefinition(id: "stars-100", title: "BRONZE SHELF", detail: "Earn 100 campaign stars", category: .mastery, metric: .totalStars, target: 100, tier: 1, hidden: false),
            AchievementDefinition(id: "stars-150", title: "JADE RACK", detail: "Earn 150 campaign stars", category: .mastery, metric: .totalStars, target: 150, tier: 2, hidden: false),
            AchievementDefinition(id: "stars-200", title: "SILVER SHELF", detail: "Earn 200 campaign stars", category: .mastery, metric: .totalStars, target: 200, tier: 2, hidden: false),
            AchievementDefinition(id: "stars-300", title: "HALF THE RACK", detail: "Earn 300 campaign stars", category: .mastery, metric: .totalStars, target: 300, tier: 2, hidden: false),
            AchievementDefinition(id: "stars-450", title: "GOLD SHELF", detail: "Earn 450 campaign stars", category: .mastery, metric: .totalStars, target: 450, tier: 3, hidden: false),
            AchievementDefinition(id: "stars-600", title: "FULL STAR RACK", detail: "Earn every campaign star", category: .mastery, metric: .totalStars, target: 600, tier: 3, hidden: false),
            AchievementDefinition(id: "chapter-perfect-1", title: "FIRST PERFECT CHAPTER", detail: "Hold all 60 stars in one chapter", category: .mastery, metric: .perfectChapters, target: 1, tier: 2, hidden: false),
            AchievementDefinition(id: "chapter-perfect-5", title: "FIVE PERFECT CHAPTERS", detail: "Hold all 60 stars in five chapters", category: .mastery, metric: .perfectChapters, target: 5, tier: 3, hidden: false),
            AchievementDefinition(id: "chapter-perfect-10", title: "EVERY STAR IN THE ROOM", detail: "Hold all 60 stars in every chapter", category: .mastery, metric: .perfectChapters, target: 10, tier: 3, hidden: false),
            AchievementDefinition(id: "repeat-master", title: "OPENING SPECIALIST", detail: "Complete Opening Window 10 times", category: .mastery, metric: .levelCompletions(1), target: 10, tier: 2, hidden: true),
            AchievementDefinition(id: "chapter-one-perfect", title: "FOUNDATIONS FLAWLESS", detail: "Hold all 60 stars in Foundations", category: .mastery, metric: .chapterStars(1), target: 60, tier: 2, hidden: true),

            // MARK: Efficiency
            AchievementDefinition(id: "perfect-10", title: "TEN CLEAN BOARDS", detail: "Earn three stars on 10 boards", category: .efficiency, metric: .perfectLevels, target: 10, tier: 1, hidden: false),
            AchievementDefinition(id: "perfect-50", title: "FIFTY CLEAN BOARDS", detail: "Earn three stars on 50 boards", category: .efficiency, metric: .perfectLevels, target: 50, tier: 2, hidden: false),
            AchievementDefinition(id: "perfect-100", title: "HUNDRED CLEAN BOARDS", detail: "Earn three stars on 100 boards", category: .efficiency, metric: .perfectLevels, target: 100, tier: 3, hidden: false),
            AchievementDefinition(id: "perfect-150", title: "ONE HUNDRED FIFTY CLEAN", detail: "Earn three stars on 150 boards", category: .efficiency, metric: .perfectLevels, target: 150, tier: 3, hidden: false),
            AchievementDefinition(id: "perfect-200", title: "EVERY BOARD CLEAN", detail: "Earn three stars on all 200 boards", category: .efficiency, metric: .perfectLevels, target: 200, tier: 3, hidden: false),
            AchievementDefinition(id: "single-freeze-10", title: "TEN SINGLE STOPS", detail: "Solve 10 boards with one freeze", category: .efficiency, metric: .lowFreezeCompletions(maximum: 1), target: 10, tier: 2, hidden: false),
            AchievementDefinition(id: "single-freeze-40", title: "FORTY SINGLE STOPS", detail: "Solve 40 boards with one freeze", category: .efficiency, metric: .lowFreezeCompletions(maximum: 1), target: 40, tier: 3, hidden: false),
            AchievementDefinition(id: "low-freeze-100", title: "HUNDRED TIDY BOARDS", detail: "Solve 100 boards with three freezes or fewer", category: .efficiency, metric: .lowFreezeCompletions(maximum: 3), target: 100, tier: 3, hidden: false),
            AchievementDefinition(id: "fast-30", title: "THIRTY QUICK BOARDS", detail: "Solve 30 boards in under 30 seconds", category: .efficiency, metric: .fastCompletions(maximumSeconds: 30), target: 30, tier: 2, hidden: false),
            AchievementDefinition(id: "fast-100", title: "HUNDRED QUICK BOARDS", detail: "Solve 100 boards in under 30 seconds", category: .efficiency, metric: .fastCompletions(maximumSeconds: 30), target: 100, tier: 3, hidden: false),
            AchievementDefinition(id: "replay-25", title: "TWENTY-FIVE RETURNS", detail: "Replay 25 boards you have already cleared", category: .efficiency, metric: .replayedLevels, target: 25, tier: 1, hidden: false),

            // MARK: Endless
            AchievementDefinition(id: "endless-5", title: "FIVE BOARDS DEEP", detail: "Reach Endless stage 5", category: .endless, metric: .endlessStage, target: 5, tier: 1, hidden: false),
            AchievementDefinition(id: "endless-10", title: "TEN BOARDS DEEP", detail: "Reach Endless stage 10", category: .endless, metric: .endlessStage, target: 10, tier: 1, hidden: false),
            AchievementDefinition(id: "endless-20", title: "TWENTY BOARDS DEEP", detail: "Reach Endless stage 20", category: .endless, metric: .endlessStage, target: 20, tier: 2, hidden: false),
            AchievementDefinition(id: "endless-30", title: "THIRTY BOARDS DEEP", detail: "Reach Endless stage 30", category: .endless, metric: .endlessStage, target: 30, tier: 2, hidden: false),
            AchievementDefinition(id: "endless-50", title: "FIFTY BOARDS DEEP", detail: "Reach Endless stage 50", category: .endless, metric: .endlessStage, target: 50, tier: 3, hidden: false),
            AchievementDefinition(id: "endless-75", title: "SEVENTY-FIVE DEEP", detail: "Reach Endless stage 75", category: .endless, metric: .endlessStage, target: 75, tier: 3, hidden: false),
            AchievementDefinition(id: "endless-100", title: "HUNDRED BOARDS DEEP", detail: "Reach Endless stage 100", category: .endless, metric: .endlessStage, target: 100, tier: 3, hidden: false),
            AchievementDefinition(id: "endless-score-500k", title: "HALF-MILLION RUN", detail: "Score 500,000 in Endless", category: .endless, metric: .endlessScore, target: 500_000, tier: 2, hidden: false),
            AchievementDefinition(id: "endless-score", title: "SEVEN-DIGIT RUN", detail: "Score 1,000,000 in Endless", category: .endless, metric: .endlessScore, target: 1_000_000, tier: 3, hidden: false),

            // MARK: Daily
            AchievementDefinition(id: "daily-one", title: "DAILY ENTRY", detail: "Complete one Daily Puzzle", category: .daily, metric: .dailyCompletions, target: 1, tier: 1, hidden: false),
            AchievementDefinition(id: "daily-three", title: "THREE DAILY BOARDS", detail: "Complete 3 Daily Puzzles", category: .daily, metric: .dailyCompletions, target: 3, tier: 1, hidden: false),
            AchievementDefinition(id: "daily-seven", title: "SEVEN DAILY BOARDS", detail: "Complete 7 Daily Puzzles", category: .daily, metric: .dailyCompletions, target: 7, tier: 2, hidden: false),
            AchievementDefinition(id: "daily-fourteen", title: "FOURTEEN DAILY BOARDS", detail: "Complete 14 Daily Puzzles", category: .daily, metric: .dailyCompletions, target: 14, tier: 2, hidden: false),
            AchievementDefinition(id: "daily-thirty", title: "THIRTY DAILY BOARDS", detail: "Complete 30 Daily Puzzles", category: .daily, metric: .dailyCompletions, target: 30, tier: 3, hidden: false),
            AchievementDefinition(id: "daily-sixty", title: "SIXTY DAILY BOARDS", detail: "Complete 60 Daily Puzzles", category: .daily, metric: .dailyCompletions, target: 60, tier: 3, hidden: false),
            AchievementDefinition(id: "streak-three", title: "THREE-DAY STREAK", detail: "Build a 3-day Daily Puzzle streak", category: .daily, metric: .dailyStreak, target: 3, tier: 1, hidden: false),
            AchievementDefinition(id: "streak-seven", title: "WEEKLY STREAK", detail: "Build a 7-day Daily Puzzle streak", category: .daily, metric: .dailyStreak, target: 7, tier: 2, hidden: false),
            AchievementDefinition(id: "streak-fourteen", title: "FORTNIGHT STREAK", detail: "Build a 14-day Daily Puzzle streak", category: .daily, metric: .dailyStreak, target: 14, tier: 3, hidden: false),
            AchievementDefinition(id: "daily-score-10000", title: "FIVE FIGURES IN A DAY", detail: "Score 10,000 on a Daily Puzzle", category: .daily, metric: .bestDailyScore, target: 10_000, tier: 3, hidden: false),

            // MARK: Time control
            AchievementDefinition(id: "freeze-10", title: "TEN STOPS", detail: "Freeze the board 10 times", category: .timeControl, metric: .totalFreezes, target: 10, tier: 1, hidden: false),
            AchievementDefinition(id: "freeze-100", title: "HUNDRED STOPS", detail: "Freeze the board 100 times", category: .timeControl, metric: .totalFreezes, target: 100, tier: 1, hidden: false),
            AchievementDefinition(id: "freeze-1000", title: "THOUSAND STOPS", detail: "Freeze the board 1,000 times", category: .timeControl, metric: .totalFreezes, target: 1_000, tier: 2, hidden: false),
            AchievementDefinition(id: "freeze-5000", title: "FIVE THOUSAND STOPS", detail: "Freeze the board 5,000 times", category: .timeControl, metric: .totalFreezes, target: 5_000, tier: 3, hidden: false),
            AchievementDefinition(id: "rewind-1", title: "FIRST CORRECTION", detail: "Use rewind once", category: .timeControl, metric: .totalRewinds, target: 1, tier: 1, hidden: false),
            AchievementDefinition(id: "rewind-10", title: "TEN CORRECTIONS", detail: "Use rewind 10 times", category: .timeControl, metric: .totalRewinds, target: 10, tier: 1, hidden: false),
            AchievementDefinition(id: "rewind-100", title: "HUNDRED CORRECTIONS", detail: "Use rewind 100 times", category: .timeControl, metric: .totalRewinds, target: 100, tier: 3, hidden: false),
            AchievementDefinition(id: "world-ten-minutes", title: "TEN MINUTES IN PLAY", detail: "Accumulate 10 minutes of board time", category: .timeControl, metric: .totalWorldMinutes, target: 10, tier: 1, hidden: false),
            AchievementDefinition(id: "world-hour", title: "SIXTY MINUTES IN PLAY", detail: "Accumulate 60 minutes of board time", category: .timeControl, metric: .totalWorldMinutes, target: 60, tier: 2, hidden: false),
            AchievementDefinition(id: "world-three-hours", title: "THREE HOURS IN PLAY", detail: "Accumulate 3 hours of board time", category: .timeControl, metric: .totalWorldMinutes, target: 180, tier: 3, hidden: false),
            AchievementDefinition(id: "world-ten-hours", title: "TEN HOURS IN PLAY", detail: "Accumulate 10 hours of board time", category: .timeControl, metric: .totalWorldMinutes, target: 600, tier: 3, hidden: false),

            // MARK: Dedication
            AchievementDefinition(id: "active-days-7", title: "SEVEN ACTIVE DAYS", detail: "Play on 7 different days", category: .dedication, metric: .activeDays, target: 7, tier: 1, hidden: false),
            AchievementDefinition(id: "active-days-30", title: "THIRTY ACTIVE DAYS", detail: "Play on 30 different days", category: .dedication, metric: .activeDays, target: 30, tier: 2, hidden: false),
            AchievementDefinition(id: "active-days-100", title: "HUNDRED ACTIVE DAYS", detail: "Play on 100 different days", category: .dedication, metric: .activeDays, target: 100, tier: 3, hidden: false),
            AchievementDefinition(id: "account-age-30", title: "ONE MONTH IN", detail: "Keep the table for 30 days", category: .dedication, metric: .accountAgeDays, target: 30, tier: 1, hidden: false),
            AchievementDefinition(id: "account-age-365", title: "ONE YEAR IN", detail: "Keep the table for a full year", category: .dedication, metric: .accountAgeDays, target: 365, tier: 3, hidden: false),
            AchievementDefinition(id: "completions-1000", title: "THOUSAND RUNS", detail: "Complete 1,000 boards in total", category: .dedication, metric: .totalCompletions, target: 1_000, tier: 3, hidden: true)
        ]
    }

    func evaluations(progress: PlayerProgress = SaveStore.shared.progress) -> [AchievementEvaluation] {
        catalog.map { $0.evaluation(in: progress) }
    }

    func evaluations(
        category: AchievementCategory,
        progress: PlayerProgress = SaveStore.shared.progress
    ) -> [AchievementEvaluation] {
        catalog.filter { $0.category == category }.map { $0.evaluation(in: progress) }
    }

    func unlocked(progress: PlayerProgress = SaveStore.shared.progress) -> [AchievementDefinition] {
        evaluations(progress: progress).filter(\.isUnlocked).map(\.definition)
    }

    /// How many marks the player holds. This is the value the cloud copy ranks
    /// on, so it is stated once here rather than re-derived at each call site.
    func unlockedCount(progress: PlayerProgress = SaveStore.shared.progress) -> Int {
        catalog.reduce(0) { $0 + ($1.evaluation(in: progress).isUnlocked ? 1 : 0) }
    }

    /// The same count for one category, for the heading of each block in the
    /// catalogue.
    func unlockedCount(
        category: AchievementCategory,
        progress: PlayerProgress = SaveStore.shared.progress
    ) -> Int {
        evaluations(category: category, progress: progress).filter(\.isUnlocked).count
    }

    func newlyUnlocked(
        before: PlayerProgress,
        after: PlayerProgress
    ) -> [AchievementDefinition] {
        let old = Set(evaluations(progress: before).filter(\.isUnlocked).map { $0.definition.id })
        return evaluations(progress: after)
            .filter { $0.isUnlocked && !old.contains($0.definition.id) }
            .map(\.definition)
    }

    func completionFraction(progress: PlayerProgress = SaveStore.shared.progress) -> CGFloat {
        guard !catalog.isEmpty else { return 1 }
        return CGFloat(unlockedCount(progress: progress)) / CGFloat(catalog.count)
    }
}
