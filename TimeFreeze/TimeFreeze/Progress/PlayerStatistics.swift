import Foundation

struct ChapterStatistics {
    var chapter: Int
    var completed: Int
    var stars: Int
    var perfectLevels: Int
    var averageFreezes: CGFloat
    var averageWorldTime: CGFloat
    var isUnlocked: Bool
    var isComplete: Bool

    var completionFraction: CGFloat { CGFloat(completed) / 20 }
    var starFraction: CGFloat { CGFloat(stars) / 60 }
}

struct EfficiencyStatistics {
    var averageFreezes: CGFloat
    var averageWorldTime: CGFloat
    var oneFreezeLevels: Int
    var perfectLevels: Int
    var replayedLevels: Int
    var totalAttempts: Int
    var bestScore: Int
    var totalScore: Int

    var perfectFraction: CGFloat {
        totalAttempts > 0 ? CGFloat(perfectLevels) / CGFloat(totalAttempts) : 0
    }
}

struct PlayerStatistics {
    var chapters: [ChapterStatistics]
    var efficiency: EfficiencyStatistics
    var achievementFraction: CGFloat
    var unlockedAchievements: Int
    var totalAchievements: Int
    var dailyCompletionCount: Int
    var bestDailyScore: Int
    var accountAgeDays: Int
    var activeDays: Int

    var strongestChapter: ChapterStatistics? {
        chapters.max {
            if $0.starFraction == $1.starFraction { return $0.averageFreezes > $1.averageFreezes }
            return $0.starFraction < $1.starFraction
        }
    }

    var nextChapterToComplete: ChapterStatistics? {
        chapters.first { $0.isUnlocked && !$0.isComplete }
    }
}

final class PlayerStatisticsCalculator {
    static let shared = PlayerStatisticsCalculator()
    private init() {}

    /// Matches the `yyyyMMdd` keys used for daily challenge records.
    private let dailyDayKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd"
        return formatter
    }()

    func calculate(progress: PlayerProgress = SaveStore.shared.progress) -> PlayerStatistics {
        let chapters = (1...10).map { chapterStatistics(chapter: $0, progress: progress) }
        let achievements = AchievementEngine.shared.evaluations(progress: progress)
        let unlocked = achievements.filter(\.isUnlocked).count
        let daily = progress.dailyResults.values.filter(\.completed)
        let calendar = Calendar(identifier: .gregorian)
        let age = max(1, calendar.dateComponents([.day], from: progress.firstLaunch, to: Date()).day ?? 0)
        return PlayerStatistics(
            chapters: chapters,
            efficiency: efficiencyStatistics(progress: progress),
            achievementFraction: achievements.isEmpty ? 1 : CGFloat(unlocked) / CGFloat(achievements.count),
            unlockedAchievements: unlocked,
            totalAchievements: achievements.count,
            dailyCompletionCount: progress.dailyCompletionCount,
            bestDailyScore: max(progress.bestDailyScore, daily.map(\.score).max() ?? 0),
            accountAgeDays: age,
            activeDays: activeDayCount(progress: progress)
        )
    }

    /// Distinct calendar days on which the player did anything.
    ///
    /// Two sources, because neither covers the whole history on its own: level
    /// records carry a `lastPlayed` date each, and the daily-puzzle day keys
    /// catch a player who only ever opened the daily board. The trimmed day set
    /// is used rather than the retained daily results, so the count reflects all
    /// history rather than the last 90 days.
    func activeDayCount(progress: PlayerProgress) -> Int {
        let calendar = Calendar(identifier: .gregorian)
        return Set(progress.levels.values.map { calendar.startOfDay(for: $0.lastPlayed) })
            .union(progress.dailyActiveDays.compactMap { dailyDayKeyFormatter.date(from: $0) })
            .count
    }

    func chapterStatistics(chapter: Int, progress: PlayerProgress) -> ChapterStatistics {
        let safeChapter = ScalarMath.clamp(chapter, 1, 10)
        let ids = Array(((safeChapter - 1) * 20 + 1)...(safeChapter * 20))
        let records = ids.compactMap { progress.levels[$0] }
        let completed = records.filter { $0.stars > 0 }.count
        let stars = records.reduce(0) { $0 + $1.stars }
        let perfect = records.filter { $0.stars == 3 }.count
        let averageFreezes = records.isEmpty
            ? 0
            : CGFloat(records.reduce(0) { $0 + $1.bestFreezes }) / CGFloat(records.count)
        let averageTime = records.isEmpty
            ? 0
            : records.reduce(0) { $0 + $1.bestWorldTime } / CGFloat(records.count)
        return ChapterStatistics(
            chapter: safeChapter,
            completed: completed,
            stars: stars,
            perfectLevels: perfect,
            averageFreezes: averageFreezes,
            averageWorldTime: averageTime,
            isUnlocked: progress.isChapterUnlocked(safeChapter),
            isComplete: completed == 20
        )
    }

    func efficiencyStatistics(progress: PlayerProgress) -> EfficiencyStatistics {
        let records = Array(progress.levels.values)
        let totalAttempts = records.reduce(0) { $0 + $1.completionCount }
        let averageFreezes = records.isEmpty
            ? 0
            : CGFloat(records.reduce(0) { $0 + $1.bestFreezes }) / CGFloat(records.count)
        let averageTime = records.isEmpty
            ? 0
            : records.reduce(0) { $0 + $1.bestWorldTime } / CGFloat(records.count)
        return EfficiencyStatistics(
            averageFreezes: averageFreezes,
            averageWorldTime: averageTime,
            oneFreezeLevels: records.filter { $0.bestFreezes <= 1 }.count,
            perfectLevels: records.filter { $0.stars == 3 }.count,
            replayedLevels: records.filter { $0.completionCount > 1 }.count,
            totalAttempts: totalAttempts,
            bestScore: records.map(\.bestScore).max() ?? 0,
            totalScore: records.reduce(0) { $0 + $1.bestScore }
        )
    }

    func formattedPlayTime(progress: PlayerProgress = SaveStore.shared.progress) -> String {
        let seconds = Int(progress.totalWorldTime)
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3_600 { return "\(seconds / 60)m \(seconds % 60)s" }
        return "\(seconds / 3_600)h \((seconds % 3_600) / 60)m"
    }

    func summaryLines(progress: PlayerProgress = SaveStore.shared.progress) -> [String] {
        let statistics = calculate(progress: progress)
        let efficiency = statistics.efficiency
        return [
            "\(progress.completedLevels) of 200 levels complete",
            "\(progress.totalStars) of 600 stars earned",
            "\(efficiency.perfectLevels) perfect levels",
            String(format: "%.1f average freezes", efficiency.averageFreezes),
            String(format: "%.1fs average world time", efficiency.averageWorldTime),
            "\(statistics.unlockedAchievements) of \(statistics.totalAchievements) mastery marks",
            "\(statistics.activeDays) active days",
            "\(formattedPlayTime(progress: progress)) total world time"
        ]
    }
}
