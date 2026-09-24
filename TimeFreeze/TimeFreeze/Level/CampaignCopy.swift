import Foundation

/// Player-facing campaign titles live separately from level construction so
/// they can be reviewed alongside playtest notes without touching game rules.
enum CampaignCopy {

    /// Every chapter carries the same twenty levels. Stated once here because
    /// the campaign copy, the path map and the progress model all index against
    /// it, and a chapter that quietly grew a twenty-first level would otherwise
    /// desynchronise them.
    static let levelsPerChapter = 20

    private static let titlesByChapter: [[String]] = [
        [
            "FIRST FREEZE", "STILL HAND", "LIVE SWITCH", "POWER ROUTE",
            "PORTAL HOP", "RETURN PASS", "CORNER POCKET", "CROSSING PAIR",
            "ORBIT RENDEZVOUS", "TURNSTILE", "UPWARD WIND", "DOWNWARD WIND",
            "DROP ZONE", "HEAVY NINE", "EXIT ANGLE", "BELT AND RAIL",
            "TWIN ARRIVAL", "THREE-WAY SETTLE", "THREE ROUTES", "ROLL BACK"
        ],
        [
            "PARALLEL RUN", "JADE LANE", "CROSS TRAFFIC", "COLOR PICK",
            "TRIPLE TRACK", "COUNTERFLOW", "STAGGERED PASS", "LOOP PATROL",
            "DECOY ARRIVAL", "ROTARY CROSSING", "OUTER ORBIT", "INNER ORBIT",
            "BLIND INTERVAL", "FOUR IN PLAY", "CENTER MERGE", "DRIFTING MARK",
            "PACKED LANES", "DIVIDED ATTENTION", "FOUR APPROACHES", "TRAFFIC CONTROL"
        ],
        [
            "OPENING CYCLE", "SHUTTER GAP", "GEAR MESH", "LOCAL SWITCH",
            "CATCH RELEASE", "REMOTE SWITCH", "CIRCUIT BREAK", "DOUBLE CADENCE",
            "WEIGHTED SHUTTER", "BRASS GAP", "ROTARY BARRIER", "ELBOW PASS",
            "INTERLOCK", "REAR GATE", "OFFSET PAIR", "ALTERNATING DOORS",
            "THIN PASSAGE", "CAM AND FOLLOWER", "TRIPLE MECHANISM", "CONTROL ROOM"
        ],
        [
            "FROZEN HAND", "RIGHT SLOT", "SINGLE PLACEMENT", "FULL REACH",
            "CORNER SLOT", "QUARTER TURN", "MOVING HOLD", "CATCH THEN PLACE",
            "HAZARD STRIP", "DOUBLE PLACEMENT", "FRAGILE EDGE", "SUIT PAIR",
            "CROSSBOARD MOVE", "THREE SLOTS", "SORT BY SUIT", "TIGHT QUARTERS",
            "MOVING SET", "ORDERED ROW", "FULL TABLE", "DEALER'S LAYOUT"
        ],
        [
            "EASTBOUND", "NORTHBOUND", "WESTBOUND", "SOUTHBOUND",
            "QUARTER TURN", "HALF TURN", "FIXED MIRROR", "REFLECTED PATH",
            "RETURN ANGLE", "WIND CHANNEL", "COMPASS DECOY", "QUIET SECTOR",
            "NO STOPPING", "ADJUSTABLE MIRROR", "ONE-WAY LANE", "EDGE ROUTE",
            "COMPASS LOCK", "NARROW BEARING", "FOUR WINDS", "TRUE BEARING"
        ],
        [
            "DROP TEST", "SOFT LANDING", "REBOUND", "LANDING WINDOW",
            "BELT UNDERFOOT", "SHIFTING FLOOR", "WEIGHTED NINE", "COUNTERWEIGHT",
            "DOUBLE LOAD", "CROSSWIND", "CATCH POINT", "BRIDGE LOAD",
            "LOAD LIMIT", "TWIN DROP", "CARRYING SPEED", "FRAGILE DESCENT",
            "MOVING WEIGHT", "REBOUND PLATE", "CASCADE FALL", "GROUND CONTROL"
        ],
        [
            "SINGLE TRANSFER", "ANGLED EXIT", "RETURN LOOP", "FOLDED PATH",
            "EXPRESS TRANSIT", "THIRD APERTURE", "THREE-PORT ROUTE", "CHAIN ENTRY",
            "ROTATE THE EXIT", "DECOY PORTAL", "SPATIAL CADENCE", "BREAK THE LOOP",
            "FOURTH APERTURE", "SWITCHED PORTAL", "CLOSED CIRCUIT", "TWIN NETWORKS",
            "ANGLED NETWORK", "FOLDED BOARD", "LONG TRANSFER", "THE WHOLE NETWORK"
        ],
        [
            "LIFT TEST", "LIFT CALL", "BELT TO RAIL", "UPPER PLATFORM",
            "LOWER PLATFORM", "MOVING DECK", "MAGNET TEST", "REVERSE POLARITY",
            "FIELD LINE", "MANUAL CRANK", "LIFT SWITCH", "MAGNET SWITCH",
            "MACHINE FLOOR", "PENDULUM BAY", "SWING TRANSFER", "THREE MOTORS",
            "GEAR TABLE", "CONTROL DESK", "FULL ASSEMBLY", "MASTER CIRCUIT"
        ],
        [
            "OPENING DOMINO", "TWIN TARGETS", "LEVER AND DOOR", "PLATE AND GATE",
            "FORKED RESULT", "DOUBLE ENTRY", "ORDER MATTERS", "THIRD TILE",
            "PORTAL RELAY", "ROUND TRIP", "CROSS SIGNAL", "FRAGILE RELAY",
            "TWO-STAGE ROUTE", "THREE-STAGE ROUTE", "HAZARD RELAY", "SAME BEAT",
            "DEEP RELAY", "FOUR OUTCOMES", "SINGLE INPUT", "CHAIN BOARD"
        ],
        [
            "EVERYTHING MOVES", "MACHINE THROUGH PORTAL", "WEIGHTED TRANSFER", "LAST OPEN FREEZE",
            "ENERGY BUDGET", "SLOWED BOARD", "THIN RESERVE", "SELECTIVE FREEZE",
            "COLOR-SPLIT FREEZE", "REWIND ENTRY", "CORRECT THE MISS", "RESTORE POINT",
            "REVERSE FIELD", "LOCAL TIME ZONE", "PRECISION RUN", "LOW BATTERY",
            "FINAL PENDULUM", "FOUR ROUTES", "FULL SYSTEM", "MASTER TABLE"
        ]
    ]

    static func title(chapter: Int, index: Int) -> String {
        guard titlesByChapter.indices.contains(chapter - 1),
              titlesByChapter[chapter - 1].indices.contains(index - 1) else {
            return "LEVEL \(chapter)-\(index)"
        }
        return titlesByChapter[chapter - 1][index - 1]
    }
}
