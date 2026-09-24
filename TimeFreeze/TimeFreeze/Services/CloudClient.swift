import Foundation

/// Endpoint and protocol constants for the cloud service.
enum CloudConfiguration {
    /// The deployed Worker origin, without a trailing slash.
    ///
    /// A custom domain rather than the `*.workers.dev` hostname the Worker also
    /// answers on. That hostname is unreachable from mainland China: it resolves
    /// to ordinary Cloudflare anycast addresses, but every connection stalls
    /// before the TLS handshake completes, so the app could never reach the API
    /// there. `api.pansdoor.com` goes through the same Worker and does resolve.
    ///
    /// An empty base URL means "cloud disabled": `CloudClient` fails every call
    /// fast with `.notConfigured`, so clearing this reverts the game to its
    /// off-line behaviour without any other change.
    static let baseURL = "https://api.pansdoor.com"

    /// Identifies the shape of procedurally generated boards.
    ///
    /// The daily and endless levels are derived from a seed, so changing
    /// `ProceduralLevelGenerator` or `CampaignLevelBuilder` produces a different
    /// board for the same day. Scores are therefore filed under this version and
    /// leaderboards are partitioned by it. **Bump this whenever the generated
    /// geometry changes**, otherwise old and new clients will rank against each
    /// other on incomparable boards.
    static let contentVersion = 1

    static var isConfigured: Bool { !baseURL.isEmpty }
}

// MARK: - Wire types

struct CloudStats: Codable, Equatable {
    var totalStars: Int
    var completedLevels: Int
    var endlessBestStage: Int
    var endlessBestScore: Int
    /// How many achievement marks the player holds. Reported here rather than
    /// derived server-side because the catalogue lives in the client, and it
    /// grows between releases — the server only stores and ranks the number.
    var achievementsUnlocked: Int
}

struct CloudDailySubmission: Codable, Equatable {
    var key: String
    var score: Int
    var stars: Int
    var freezes: Int
    var worldTime: CGFloat
}

struct CloudSyncRequest: Codable, Equatable {
    var stats: CloudStats
    var daily: CloudDailySubmission?
    var contentVersion: Int
}

struct CloudRanks: Codable {
    var campaign: Int?
    var endless: Int?
    var daily: Int?
    var achievements: Int?
}

struct CloudSyncResponse: Codable {
    var serverTime: TimeInterval
    var rank: CloudRanks?
    var displayName: String?
}

struct CloudAuthRequest: Codable {
    var playerID: String
    var platform: String
    var appVersion: String
}

struct CloudAuthResponse: Codable {
    var token: String
    var playerID: String
    var expiresAt: TimeInterval
    var serverTime: TimeInterval
    var displayName: String?
}

enum CloudLeaderboardType: String {
    case campaign
    case endless
    case daily
    case achievements
}

struct CloudLeaderboardEntry: Codable {
    var rank: Int
    var playerID: String
    var displayName: String
    var totalStars: Int?
    var completedLevels: Int?
    var bestStage: Int?
    var bestScore: Int?
    var score: Int?
    /// Only the daily board reports stars; the others carry it in totals.
    var stars: Int?
    /// Only the achievements board reports this; the others carry it in totals.
    var achievementsUnlocked: Int?
}

extension CloudLeaderboardEntry {
    /// Constructs a bare entry for the built-in sample board, where only the
    /// metric the board ranks on is filled in. The untouched fields stay nil
    /// and are never read by that board's row. Lives in an extension so the
    /// memberwise initialiser the decoder path relies on stays synthesised.
    init(rank: Int, playerID: String, displayName: String) {
        self.rank = rank
        self.playerID = playerID
        self.displayName = displayName
        self.totalStars = nil
        self.completedLevels = nil
        self.bestStage = nil
        self.bestScore = nil
        self.score = nil
        self.stars = nil
        self.achievementsUnlocked = nil
    }
}

struct CloudLeaderboardResponse: Codable {
    var type: String
    var entries: [CloudLeaderboardEntry]
    var me: CloudLeaderboardEntry?
    var nextCursor: String?
}

// MARK: - Errors

enum CloudError: Error {
    case notConfigured
    case transport(Error)
    case unauthorized
    case server(status: Int, body: String?)
    case decoding(Error)

    var isRetryable: Bool {
        switch self {
        case .notConfigured, .unauthorized: return false
        case .transport: return true
        case let .server(status, _): return status >= 500 || status == 429
        case .decoding: return false
        }
    }
}

// MARK: - Client

/// Thin HTTP layer over the four service endpoints. Knows nothing about game
/// state; `SyncEngine` decides what to send and when.
final class CloudClient {
    static let shared = CloudClient()

    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        // Progress uploads are small and idempotent, so a stale cache is worse
        // than a refetch.
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.waitsForConnectivity = true
        session = URLSession(configuration: configuration)
    }

    func authenticate(playerID: String) async throws -> CloudAuthResponse {
        let body = CloudAuthRequest(
            playerID: playerID,
            platform: "ios",
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        )
        return try await send(
            path: "/v1/auth/anonymous",
            method: "POST",
            body: try encode(body),
            token: nil,
            as: CloudAuthResponse.self
        )
    }

    func sync(_ payload: CloudSyncRequest, token: String) async throws -> CloudSyncResponse {
        try await send(
            path: "/v1/sync",
            method: "POST",
            body: try encode(payload),
            token: token,
            as: CloudSyncResponse.self
        )
    }

    func leaderboard(
        type: CloudLeaderboardType,
        dayKey: String?,
        limit: Int,
        token: String?
    ) async throws -> CloudLeaderboardResponse {
        var query = "type=\(type.rawValue)&limit=\(limit)"
        if let dayKey {
            // The daily board is partitioned by board geometry, so the version
            // has to travel with the query. The server defaults to 1, which would
            // silently read the wrong partition as soon as the version is bumped.
            query += "&dayKey=\(dayKey)&contentVersion=\(CloudConfiguration.contentVersion)"
        }
        return try await send(
            path: "/v1/leaderboard?\(query)",
            method: "GET",
            body: nil,
            token: token,
            as: CloudLeaderboardResponse.self
        )
    }

    func deletePlayer(token: String) async throws {
        _ = try await sendRaw(path: "/v1/player", method: "DELETE", body: nil, token: token)
    }

    // MARK: - Transport

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        do {
            return try encoder.encode(value)
        } catch {
            throw CloudError.decoding(error)
        }
    }

    private func send<Result: Decodable>(
        path: String,
        method: String,
        body: Data?,
        token: String?,
        as type: Result.Type
    ) async throws -> Result {
        let data = try await sendRaw(path: path, method: method, body: body, token: token)
        do {
            return try decoder.decode(Result.self, from: data)
        } catch {
            throw CloudError.decoding(error)
        }
    }

    private func sendRaw(
        path: String,
        method: String,
        body: Data?,
        token: String?
    ) async throws -> Data {
        guard CloudConfiguration.isConfigured,
              let url = URL(string: CloudConfiguration.baseURL + path) else {
            throw CloudError.notConfigured
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw CloudError.transport(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw CloudError.transport(URLError(.badServerResponse))
        }
        if http.statusCode == 401 { throw CloudError.unauthorized }
        guard (200..<300).contains(http.statusCode) else {
            throw CloudError.server(
                status: http.statusCode,
                body: String(data: data, encoding: .utf8)
            )
        }
        return data
    }
}
