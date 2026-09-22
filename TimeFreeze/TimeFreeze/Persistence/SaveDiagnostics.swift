import Foundation
import os

/// Surfaces persistence failures that would otherwise be swallowed.
///
/// A failed save is invisible to the player but loses their progress, so each
/// issue goes to the unified log, visible in Console.app.
enum SaveDiagnostics {
    enum Issue {
        case loadFailed(Error)
        case saveFailed(Error)
        case corruptSaveQuarantined(URL)
        case cloudDeleteFailed(Error)
    }

    private static let logger = Logger(subsystem: "com.timefreeze", category: "persistence")

    static func report(_ issue: Issue) {
        logger.error("\(describe(issue), privacy: .public)")
    }

    private static func describe(_ issue: Issue) -> String {
        switch issue {
        case let .loadFailed(error):
            return "Progress load failed: \(error)"
        case let .saveFailed(error):
            return "Progress save failed: \(error)"
        case let .corruptSaveQuarantined(url):
            return "Unreadable save moved aside to \(url.lastPathComponent)"
        case let .cloudDeleteFailed(error):
            return "Cloud data deletion failed: \(error)"
        }
    }
}
