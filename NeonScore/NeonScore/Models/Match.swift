import Foundation
import SwiftUI

enum MatchState: Int, Codable { case live = 0, upcoming = 1, finished = 2 }

struct Side: Hashable, Codable {
    var id: String
    var name: String
    var short: String
    var logo: URL?
    var score: String
    var record: String?
    var winner: Bool
    var lines: [String]
    var colorHex: String?
}

struct Situation: Hashable, Codable {
    var downDistance: String?      // "1st & 10 at KC 42"
    var yardLine: Int?
    var possessionId: String?
    var redZone = false
    var balls: Int?
    var strikes: Int?
    var outs: Int?
    var onFirst = false
    var onSecond = false
    var onThird = false
    var batter: String?
    var pitcher: String?
}

struct Match: Identifiable, Hashable, Codable {
    var id: String
    var sport: Sport
    var group: String          // league / tournament / round heading
    var state: MatchState
    var statusText: String     // "Q3 4:12", "Final", "7:30 PM"
    var start: Date?
    var home: Side
    var away: Side
    var venue: String?
    var broadcast: String?
    var odds: String?
    var situation: Situation? = nil
}

enum MatchParser {
    static func parseDate(_ s: String?) -> Date? {
        guard let s else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH:mmZ"
        return f.date(from: s)
    }

    static func scoreboard(_ root: JSON, sport: Sport) -> [Match] {
        var out: [Match] = []
        for event in root["events"].array {
            if sport.isTennis {
                let tournament = event["name"].string ?? event["shortName"].string ?? sport.title
                for grouping in event["groupings"].array {
                    let groupName = grouping["grouping"]["displayName"].string ?? ""
                    for comp in grouping["competitions"].array {
                        if let m = parse(comp: comp, event: event, sport: sport,
                                         group: groupName.isEmpty ? tournament : "\(tournament) · \(groupName)") {
                            out.append(m)
                        }
                    }
                }
                // Some tennis payloads put competitions directly on the event.
                if event["groupings"].array.isEmpty {
                    for comp in event["competitions"].array {
                        if let m = parse(comp: comp, event: event, sport: sport, group: tournament) { out.append(m) }
                    }
                }
            } else if let m = parse(comp: event["competitions"][0], event: event, sport: sport,
                                    group: root["leagues"][0]["abbreviation"].string ?? sport.title) {
                out.append(m)
            }
        }
        return out
    }

    private static func side(_ c: JSON, tennis: Bool) -> Side {
        let team = c["team"]
        let athlete = c["athlete"]
        let name = tennis ? (athlete["displayName"].string ?? athlete["shortName"].string ?? "TBD")
                          : (team["displayName"].string ?? team["shortDisplayName"].string ?? "TBD")
        let short = tennis ? (athlete["shortName"].string ?? name)
                           : (team["abbreviation"].string ?? String(name.prefix(3)).uppercased())
        let logo = tennis ? athlete["flag"]["href"].url : (team["logo"].url ?? team["logos"][0]["href"].url)
        var score = c["score"].string ?? c["score"]["displayValue"].string ?? ""
        if score.isEmpty, let v = c["score"]["value"].double { score = String(Int(v)) }
        let lines = c["linescores"].array.compactMap { ls -> String? in
            if let v = ls["displayValue"].string, !v.isEmpty { return v }
            if let d = ls["value"].double { return String(Int(d)) }
            return nil
        }
        return Side(id: tennis ? (athlete["id"].string ?? name) : (team["id"].string ?? name),
                    name: name, short: short, logo: logo, score: score,
                    record: c["records"][0]["summary"].string,
                    winner: c["winner"].bool ?? false, lines: lines,
                    colorHex: team["color"].string)
    }

    private static func parse(comp: JSON, event: JSON, sport: Sport, group: String) -> Match? {
        let competitors = comp["competitors"].array
        guard competitors.count >= 2 else { return nil }
        let tennis = sport.isTennis
        var homeC = competitors.first { $0["homeAway"].string == "home" } ?? competitors[0]
        var awayC = competitors.first { $0["homeAway"].string == "away" } ?? competitors[1]
        if tennis {
            let sorted = competitors.sorted { ($0["order"].int ?? 0) < ($1["order"].int ?? 0) }
            homeC = sorted[0]; awayC = sorted[1]
        }
        let status = comp["status"].exists ? comp["status"] : event["status"]
        let stateStr = status["type"]["state"].string ?? "pre"
        let state: MatchState = stateStr == "in" ? .live : (stateStr == "post" ? .finished : .upcoming)
        let start = parseDate(comp["date"].string ?? comp["startDate"].string ?? event["date"].string)

        var text: String
        switch state {
        case .live:
            text = status["type"]["shortDetail"].string ?? status["type"]["detail"].string ?? "Live"
        case .finished:
            text = status["type"]["shortDetail"].string ?? "Final"
        case .upcoming:
            if let start {
                let f = DateFormatter(); f.dateFormat = "h:mm a"; text = f.string(from: start)
            } else { text = status["type"]["shortDetail"].string ?? "Scheduled" }
        }
        if text.isEmpty { text = "—" }

        let broadcast = comp["broadcasts"][0]["names"][0].string ?? comp["broadcast"].string
        let odds = comp["odds"][0]["details"].string

        var situation: Situation?
        let sit = comp["situation"]
        if sit.exists {
            situation = Situation(
                downDistance: sit["downDistanceText"].string ?? sit["shortDownDistanceText"].string,
                yardLine: sit["yardLine"].int,
                possessionId: sit["possession"].string,
                redZone: sit["isRedZone"].bool ?? false,
                balls: sit["balls"].int, strikes: sit["strikes"].int, outs: sit["outs"].int,
                onFirst: sit["onFirst"].bool ?? false, onSecond: sit["onSecond"].bool ?? false, onThird: sit["onThird"].bool ?? false,
                batter: sit["batter"]["athlete"]["displayName"].string,
                pitcher: sit["pitcher"]["athlete"]["displayName"].string)
        }

        return Match(id: comp["id"].string ?? event["id"].string ?? UUID().uuidString,
                     sport: sport, group: group, state: state, statusText: text, start: start,
                     home: side(homeC, tennis: tennis), away: side(awayC, tennis: tennis),
                     venue: comp["venue"]["fullName"].string ?? event["venue"]["displayName"].string,
                     broadcast: broadcast, odds: odds, situation: situation)
    }
}

// MARK: - Other payloads

struct StandingRow: Identifiable, Hashable {
    var id: String
    var rank: Int
    var name: String
    var short: String
    var logo: URL?
    var values: [String]
}

struct StandingGroup: Identifiable, Hashable {
    var id: String { name }
    var name: String
    var columns: [String]
    var rows: [StandingRow]
}

struct Article: Identifiable, Hashable {
    var id: String
    var headline: String
    var summary: String
    var image: URL?
    var link: URL?
    var published: Date?
}

struct TeamInfo: Identifiable, Hashable {
    var id: String { "\(sport.rawValue):\(teamId)" }
    var sport: Sport
    var teamId: String
    var name: String
    var short: String
    var logo: URL?
}

struct StatLine: Identifiable, Hashable {
    var id = UUID()
    var label: String
    var home: String
    var away: String
}

struct PlayerTable: Identifiable, Hashable {
    var id = UUID()
    var title: String
    var labels: [String]
    var rows: [[String]]   // first element = player name
}

struct PlayItem: Identifiable, Hashable {
    var id = UUID()
    var time: String
    var text: String
    var scoring: Bool
}

struct ShotMark: Identifiable, Hashable {
    var id = UUID()
    var x: Double
    var y: Double
    var made: Bool
    var teamId: String?
    var text: String
}

struct RosterPlayer: Hashable {
    var name: String
    var jersey: String
    var starter: Bool
    var teamId: String
}

struct CastPlay: Identifiable, Hashable {
    var id: Int
    var period: Int
    var clock: String
    var text: String
    var type: String
    var teamId: String?
    var shooting: Bool
    var scoring: Bool
    var points: Int
    var x: Double?
    var y: Double?
    var away: Int
    var home: Int
}

struct MatchDetail {
    var roster: [RosterPlayer] = []
    var cast: [CastPlay] = []
    var shots: [ShotMark] = []
    var stats: [StatLine] = []
    var players: [PlayerTable] = []
    var plays: [PlayItem] = []
    var odds: String?
    var overUnder: String?
    var venue: String?
    var attendance: String?
}
