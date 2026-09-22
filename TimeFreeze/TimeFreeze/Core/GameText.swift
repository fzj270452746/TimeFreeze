import Foundation

enum GameText {
    static let title = "Time Freeze"
    static let subtitle = "Read the table. Stop at the right moment."
    static let play = "Play"
    static let continueGame = "Continue"
    static let chapters = "Chapters"
    static let endless = "Endless Table"
    static let dailyPuzzle = "Daily Puzzle"
    static let settings = "Settings"
    static let achievements = "Mastery"
    static let back = "Back"
    static let pause = "Pause"
    static let resume = "Resume"
    static let restart = "Restart"
    static let quit = "Quit Level"
    static let next = "Next"
    static let retry = "Try Again"
    static let levelComplete = "Level Complete"
    static let timeCollision = "TIME COLLISION"
    static let running = "TIME RUNNING"
    static let frozen = "TIME FROZEN"
    static let slowMotion = "SLOW MOTION"
    static let freezes = "FREEZES"
    static let best = "BEST"
    static let worldTime = "WORLD TIME"
    static let objective = "OBJECTIVE"
    static let freezeEnergy = "FREEZE ENERGY"
    static let locked = "LOCKED"
    static let completed = "COMPLETED"
    static let newBest = "NEW BEST"
    static let sound = "SOUND EFFECTS"
    static let music = "AMBIENT SOUND"
    static let haptics = "HAPTICS"
    static let reduceMotion = "REDUCE MOTION"
    static let highContrast = "HIGH CONTRAST"
    static let tutorial = "TUTORIAL HINTS"
    static let resetProgress = "RESET PROGRESS"
    static let confirmReset = "HOLD TO RESET"
    static let resetDone = "PROGRESS RESET"
    static let leaderboard = "Leaderboard"
    static let leaderboardSubtitle = "How the table ranks"
    static let rank = "RANK"
    static let player = "PLAYER"
    static let you = "YOU"
    static let loading = "LOADING"
    static let leaderboardEmpty = "No scores on this board yet."
    static let leaderboardFailed = "Could not reach the table."
    static let leaderboardOffline = "Leaderboards are unavailable right now."
    /// Stands in for a hidden mark's title and detail until it is earned. The
    /// detail is withheld rather than shown greyed out, because it states the
    /// condition and would give the secret away.
    static let hiddenMarkTitle = "???"
    static let hiddenMarkDetail = "Hidden mark"
    /// Closes a batch of unlock cards too long to play in full. The count of
    /// what was folded away is prefixed by the banner.
    static let moreMarksDetail = "See Mastery for the full list"
    static let deleteCloudData = "DELETE CLOUD DATA"
    static let confirmDeleteCloud = "HOLD TO DELETE"
    static let deleteCloudDone = "CLOUD DATA DELETED"
    static let deleteCloudDetail = "Removes your scores from the leaderboard and forgets this device's player ID. Your progress on this device is kept."
    static let tapToFreeze = "TAP THE DIAL TO FREEZE"
    static let freezeOnTarget = "FREEZE WHEN THE TILE ENTERS TARGET"
    static let tapToResume = "TAP AGAIN TO RESUME"
    static let dragWhileFrozen = "DRAG THE TILE INTO THE TARGET"
    static let turnWindTile = "TAP THE WIND TILE ONCE TO TURN IT"
    static let rotateWhileFrozen = "TAP THE GEAR WHILE FROZEN"
    static let activateSwitch = "TAP THE SWITCH WHILE FROZEN"
    static let swipeToRewind = "HOLD REWIND TO STEP BACK"
    static let chapterNames = [
        "FOUNDATIONS",
        "MOVING WORLD",
        "MOVING GATES",
        "TILE CONTROL",
        "DIRECTION",
        "GRAVITY",
        "PORTALS",
        "MACHINES",
        "CHAIN REACTION",
        "MASTER TABLE"
    ]
    static let chapterDescriptions = [
        "Learn freezing, dragging, switches, portals, and rewind.",
        "Pick the correct tile from crossing lanes and orbits.",
        "Open straight and rotating gates without losing the route.",
        "Drag, rotate, and sort tiles while the board is stopped.",
        "Turn wind tiles and mirrors to aim each route.",
        "Catch falling tiles and balance weighted plates.",
        "Follow entries, exits, loops, and linked portal networks.",
        "Coordinate lifts, belts, magnets, rails, and pendulums.",
        "Trace switches and plates through multi-step outcomes.",
        "Combine energy limits, selective freeze, and rewind."
    ]
}
