import Foundation
import UIKit

/// Pushes the player's aggregate stats and today's daily result to the service.
///
/// The payload carries absolute values rather than deltas, so a sync is just
/// "read the current state and upload it". That makes retries idempotent and
/// removes any need for an outbound operation queue — an upload that is lost
/// costs nothing, because the next one carries the same or newer numbers.
///
/// The cloud copy is write-only: `AnonymousIdentity` is regenerated when the app
/// is reinstalled, so nothing uploaded here is ever read back into the game.
@MainActor
final class SyncEngine {
    static let shared = SyncEngine()

    private let client = CloudClient.shared
    private let identity = AnonymousIdentity.shared

    /// Coalesces bursts (a level completion followed immediately by the app
    /// going to the background) into a single upload.
    private let debounceInterval: TimeInterval = 2
    private let retryDelays: [TimeInterval] = [5, 30, 120]

    private var pendingWork: DispatchWorkItem?
    private var isUploading = false
    private var retryAttempt = 0
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    /// Stats as last accepted by the server, used to skip no-op uploads.
    private var lastSyncedStats: CloudStats?
    /// Newest daily key already accepted, so a result recorded just before
    /// midnight is still delivered after the day rolls over.
    private var lastSyncedDailyKey: String?

    private(set) var latestRanks: CloudRanks?
    private(set) var displayName: String?

    /// Fired on the main actor whenever fresh ranks arrive.
    var onRanksUpdated: ((CloudRanks) -> Void)?

    private init() {}

    var isEnabled: Bool { CloudConfiguration.isConfigured }

    // MARK: - Scheduling

    /// Called once at launch to obtain a token if one is missing.
    func start() {
        guard isEnabled else { return }
        if identity.validToken == nil {
            Task { await authenticate() }
        } else {
            requestSync(reason: "launch")
        }
    }

    /// Debounced upload. Safe to call from any game event.
    func requestSync(reason: String) {
        guard isEnabled else { return }
        pendingWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { await self?.upload(reason: reason) }
        }
        pendingWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: work)
    }

    /// Uploads without waiting for the debounce, for the moment the app is about
    /// to be suspended.
    func flush() {
        guard isEnabled else { return }
        pendingWork?.cancel()
        pendingWork = nil
        beginBackgroundTask()
        Task {
            await upload(reason: "flush")
            endBackgroundTask()
        }
    }

    // MARK: - Auth

    private func authenticate() async {
        guard await obtainToken() != nil else { return }
        await upload(reason: "post-auth")
    }

    /// Fetches a token without uploading anything.
    ///
    /// Deletion needs credentials but must not write, and `authenticate()` writes
    /// on the way out — so the two steps are separate.
    @discardableResult
    private func obtainToken() async -> String? {
        do {
            let response = try await client.authenticate(playerID: identity.playerID)
            identity.storeToken(response.token, expiresAt: response.expiresAt)
            displayName = response.displayName
            retryAttempt = 0
            return response.token
        } catch {
            scheduleRetry(reason: "auth")
            return nil
        }
    }

    // MARK: - Upload

    private func upload(reason: String) async {
        guard isEnabled, !isUploading else { return }
        guard let token = identity.validToken else {
            await authenticate()
            return
        }

        let payload = makePayload()
        // Nothing changed since the last accepted upload, so skip the write.
        // This is what keeps a player who idles on the menu from spending the
        // daily write budget doing nothing.
        if payload.daily == nil, payload.stats == lastSyncedStats { return }

        isUploading = true
        defer { isUploading = false }

        do {
            let response = try await client.sync(payload, token: token)
            lastSyncedStats = payload.stats
            if let daily = payload.daily { lastSyncedDailyKey = daily.key }
            retryAttempt = 0
            if let ranks = response.rank {
                latestRanks = ranks
                onRanksUpdated?(ranks)
            }
            if let name = response.displayName { displayName = name }
        } catch let error as CloudError {
            if case .unauthorized = error {
                // Token lapsed or was revoked; re-auth and let the next sync run.
                identity.clearToken()
                await authenticate()
                return
            }
            if error.isRetryable { scheduleRetry(reason: reason) }
        } catch {
            scheduleRetry(reason: reason)
        }
    }

    private func scheduleRetry(reason: String) {
        guard retryAttempt < retryDelays.count else { return }
        let delay = retryDelays[retryAttempt]
        retryAttempt += 1
        pendingWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { await self?.upload(reason: "retry:\(reason)") }
        }
        pendingWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    // MARK: - Payload

    private func makePayload() -> CloudSyncRequest {
        let progress = SaveStore.shared.progress
        return CloudSyncRequest(
            stats: CloudStats(
                totalStars: progress.totalStars,
                completedLevels: progress.completedLevels,
                endlessBestStage: progress.endlessBestStage,
                endlessBestScore: progress.endlessBestScore,
                // Counted straight off the engine rather than through
                // `PlayerStatisticsCalculator`, which would also build chapter
                // statistics and do date arithmetic for one integer.
                achievementsUnlocked: AchievementEngine.shared.unlockedCount(progress: progress)
            ),
            daily: unsyncedDaily(from: progress),
            contentVersion: CloudConfiguration.contentVersion
        )
    }

    /// The newest daily result not yet accepted by the server. Day keys are
    /// `yyyyMMdd`, so a plain string comparison orders them chronologically.
    private func unsyncedDaily(from progress: PlayerProgress) -> CloudDailySubmission? {
        let threshold = lastSyncedDailyKey ?? ""
        guard let key = progress.dailyResults.keys.filter({ $0 > threshold }).max(),
              let result = progress.dailyResults[key] else { return nil }
        return CloudDailySubmission(
            key: key,
            score: result.score,
            stars: result.stars,
            freezes: result.freezeCount,
            worldTime: result.worldTime
        )
    }

    // MARK: - Leaderboard

    func fetchLeaderboard(
        type: CloudLeaderboardType,
        dayKey: String? = nil,
        limit: Int = 50
    ) async throws -> CloudLeaderboardResponse {
        // The board can be opened before the launch-time authentication has
        // finished. An anonymous read still succeeds, but the service answers it
        // with `me: null`, which quietly drops the player's own standing from the
        // screen — so a read waits for a token exactly as an upload does.
        var token = identity.validToken
        if token == nil {
            token = await obtainToken()
        }
        return try await client.leaderboard(
            type: type,
            dayKey: dayKey,
            limit: limit,
            token: token
        )
    }

    // MARK: - Deletion

    /// Erases the player's cloud rows. Called from the settings screen when the
    /// player asks for their data to be removed.
    ///
    /// The local identity is dropped afterwards, which is what stops the very
    /// next sync from writing the same rows straight back. The player keeps their
    /// on-device progress; they simply appear on the board as a new player from
    /// here on.
    func deleteCloudData() async {
        guard isEnabled else { return }
        pendingWork?.cancel()
        pendingWork = nil
        if let token = identity.validToken {
            do {
                try await client.deletePlayer(token: token)
            } catch {
                // Best effort: the local identity is dropped either way, so the
                // stale rows are unreachable from this device from now on and the
                // server ages them out via last_seen_at.
                SaveDiagnostics.report(.cloudDeleteFailed(error))
            }
        }
        identity.forgetPlayer()
        lastSyncedStats = nil
        lastSyncedDailyKey = nil
        latestRanks = nil
        displayName = nil
    }

    /// After a local reset the cloud row still holds the old totals. Uploading
    /// the zeroed state keeps the identity but clears the leaderboard entry,
    /// which matches "start over" rather than "delete me".
    func reportReset() {
        guard isEnabled else { return }
        lastSyncedStats = nil
        lastSyncedDailyKey = nil
        pendingWork?.cancel()
        Task { await upload(reason: "reset") }
    }

    // MARK: - Background execution

    /// Buys a little time for the final upload when the app is being suspended.
    private func beginBackgroundTask() {
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }
}
