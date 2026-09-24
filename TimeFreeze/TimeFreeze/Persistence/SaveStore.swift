import Foundation

final class SaveStore {
    static let shared = SaveStore()

    private let queue = DispatchQueue(label: "com.timefreeze.save", qos: .utility)
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let progressURL: URL
    private let settingsKey = "timeFreeze.settings.v1"
    private(set) var progress: PlayerProgress
    private(set) var settings: GameSettings
    private var pendingSave: DispatchWorkItem?

    private init() {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        progressURL = documents.appendingPathComponent("time-freeze-progress.json")
        progress = PlayerProgress()
        settings = .standard
        load()
    }

    func progressForLevel(_ id: Int) -> LevelProgress? {
        progress.levels[id]
    }

    /// Keeps a failed attempt visible in the level grid without granting
    /// completion or unlocking the following level.
    func markLevelStarted(_ id: Int) {
        guard (1...200).contains(id), progress.levels[id] == nil else { return }
        progress.levels[id] = LevelProgress(levelID: id)
        scheduleSave()
    }

    func record(_ result: LevelResult) {
        if var current = progress.levels[result.levelID] {
            current.merge(result)
            progress.levels[result.levelID] = current
        } else {
            progress.levels[result.levelID] = LevelProgress(result: result)
        }
        progress.lastLevelID = min(200, result.levelID + (result.completed ? 1 : 0))
        progress.totalFreezes += result.freezeCount
        progress.totalWorldTime += result.worldTime
        progress.totalRewinds += result.rewinds
        scheduleSave()
    }

    func recordEndless(score: Int, stage: Int) {
        progress.endlessBestScore = max(progress.endlessBestScore, score)
        progress.endlessBestStage = max(progress.endlessBestStage, stage)
        scheduleSave()
    }

    func recordDaily(key: String, result: LevelResult) {
        let previous = progress.dailyResults[key]
        let isBestToday = previous == nil || result.score > previous!.score
        if isBestToday {
            progress.dailyResults[key] = result
        }
        // Totals are accumulated rather than derived: `dailyResults` is trimmed,
        // so counting its entries would make the numbers go down over time.
        if result.completed {
            progress.dailyCompletionCount += 1
            progress.dailyActiveDays.insert(key)
        }
        progress.bestDailyScore = max(progress.bestDailyScore, result.score)
        progress.trimDailyHistory()
        updateDailyStreak(for: key)
        scheduleSave()
    }

    func markTutorialSeen(_ key: String) {
        progress.tutorialKeysSeen.insert(key)
        scheduleSave()
    }

    func markOnboardingSeen() {
        guard !progress.hasSeenOnboarding else { return }
        progress.hasSeenOnboarding = true
        scheduleSave()
    }

    func updateSettings(_ transform: (inout GameSettings) -> Void) {
        transform(&settings)
        if let data = try? encoder.encode(settings) {
            UserDefaults.standard.set(data, forKey: settingsKey)
        }
    }

    func resetProgress() {
        progress = PlayerProgress()
        pendingSave?.cancel()
        saveSynchronously()
    }

    func flush() {
        pendingSave?.cancel()
        saveSynchronously()
    }

    private func load() {
        if let data = try? Data(contentsOf: progressURL) {
            do {
                progress = try decoder.decode(PlayerProgress.self, from: data)
                progress.lastLaunch = Date()
            } catch {
                // A save that cannot be decoded is moved aside rather than
                // overwritten, so a decoding bug does not permanently destroy
                // the player's progress on the next save.
                SaveDiagnostics.report(.loadFailed(error))
                quarantineUnreadableSave()
            }
        }
        if let data = UserDefaults.standard.data(forKey: settingsKey),
           let decoded = try? decoder.decode(GameSettings.self, from: data) {
            settings = decoded
        }
    }

    private func quarantineUnreadableSave() {
        let stamp = Int(Date().timeIntervalSince1970)
        let target = progressURL
            .deletingPathExtension()
            .appendingPathExtension("corrupt-\(stamp).json")
        do {
            try FileManager.default.moveItem(at: progressURL, to: target)
            SaveDiagnostics.report(.corruptSaveQuarantined(target))
        } catch {
            SaveDiagnostics.report(.saveFailed(error))
        }
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveSynchronously() }
        pendingSave = work
        queue.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func saveSynchronously() {
        guard let data = try? encoder.encode(progress) else {
            SaveDiagnostics.report(.saveFailed(SaveError.encodingFailed))
            return
        }
        do {
            try FileManager.default.createDirectory(
                at: progressURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: progressURL, options: .atomic)
        } catch {
            SaveDiagnostics.report(.saveFailed(error))
        }
    }

    private enum SaveError: Error {
        case encodingFailed
    }

    /// Derived from the recorded day set rather than incremented in place, so
    /// replaying the same day's challenge cannot inflate the streak.
    private func updateDailyStreak(for key: String) {
        guard progress.dailyActiveDays.contains(key) else { return }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd"
        guard var cursor = formatter.date(from: key) else { return }
        var streak = 0
        while progress.dailyActiveDays.contains(formatter.string(from: cursor)) {
            streak += 1
            guard let previous = formatter.calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        progress.currentStreak = streak
        progress.bestStreak = max(progress.bestStreak, streak)
    }
}
