import ActivityKit
import Foundation

/// Shared by the app and the widget extension.
struct GameAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var awayScore: String
        var homeScore: String
        var status: String
        var live: Bool
        var finished: Bool
    }
    var matchId: String
    var sport: String
    var awayShort: String
    var homeShort: String
    var awayName: String
    var homeName: String
    var awayRecord: String = ""
    var homeRecord: String = ""
    var venue: String = ""
    var broadcast: String = ""
    var odds: String = ""
    var startDate: Date? = nil
}
