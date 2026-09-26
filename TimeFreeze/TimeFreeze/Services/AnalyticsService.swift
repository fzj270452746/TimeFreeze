import Foundation
import AppsFlyerLib

/// Translates native game events into AppsFlyer events.
///
/// Shares the `AppsFlyerLib` singleton with `DailyTaskView`, whose H5-driven
/// reporting (with `amount`/`currency`) flows through the same SDK. This type
/// only turns level and achievement events into AppsFlyer events: built-in
/// constants where one exists (`af_level_achieved`, `af_achievement_unlocked`),
/// underscore-separated custom names otherwise.
final class AnalyticsService {
    static let shared = AnalyticsService()

    private init() {}

    // MARK: - Level

    /// Entering a run. Campaign, daily and endless share one event; `mode` tells
    /// them apart on the dashboard.
    func trackLevelStarted(_ definition: LevelDefinition) {
        log("start_level", values: [
            AFEventParamLevel: definition.id,
            AFEventParamContent: definition.name,
            "chapter": definition.chapter,
            "mode": definition.mode.rawValue,
            "difficulty": definition.difficulty
        ])
    }

    /// Completing a run. `chapter` is not part of `LevelResult`, so the caller
    /// passes it down from the level that is on screen.
    func trackLevelAchieved(_ result: LevelResult, chapter: Int) {
        log(AFEventLevelAchieved, values: [
            AFEventParamLevel: result.levelID,
            AFEventParamScore: result.score,
            AFEventParamSuccess: 1,
            "chapter": chapter,
            "mode": result.mode.rawValue,
            "stars": result.stars,
            "freeze_count": result.freezeCount,
            "world_time": Double(result.worldTime),
            "real_time": Double(result.realTime)
        ])
    }

    /// Failing a run. `level` is optional — a failure normally has a level on
    /// screen, but guarding keeps the call cheap to make from anywhere.
    func trackLevelFailed(reason: FailureKind, level: LevelDefinition?) {
        var values: [String: Any] = ["reason": reason.rawValue]
        if let level {
            values[AFEventParamLevel] = level.id
            values[AFEventParamContent] = level.name
            values["chapter"] = level.chapter
            values["mode"] = level.mode.rawValue
        }
        log("level_failed", values: values)
    }

    // MARK: - Achievement

    /// Unlocking a mark. A run can earn several at once, so the caller reports
    /// each definition separately.
    func trackAchievementUnlocked(_ definition: AchievementDefinition) {
        log(AFEventAchievementUnlocked, values: [
            AFEventParamAchievementId: definition.id,
            AFEventParamDescription: definition.title,
            "category": definition.category.rawValue
        ])
    }

    // MARK: - Daily

    /// Completing today's daily puzzle. `dayKey` is `yyyyMMdd`.
    func trackDailyCompleted(_ result: LevelResult, dayKey: String) {
        log("daily_completed", values: [
            AFEventParamLevel: result.levelID,
            AFEventParamScore: result.score,
            AFEventParamSuccess: 1,
            "stars": result.stars,
            "day_key": dayKey
        ])
    }

    // MARK: - Transport

    private func log(_ name: String, values: [String: Any]) {
        AppsFlyerLib.shared().logEvent(name, withValues: values)
    }
}
