import Foundation

/// Shown when the live feed can't be reached, so the app is never an empty screen.
enum DemoData {
    private static func side(_ id: String, _ name: String, _ short: String, _ score: String, _ lines: [String] = [], winner: Bool = false) -> Side {
        Side(id: id, name: name, short: short, logo: nil, score: score, record: nil, winner: winner, lines: lines, colorHex: nil)
    }

    static func matches(for sport: Sport, date: Date) -> [Match] {
        func m(_ id: String, _ state: MatchState, _ text: String, _ a: Side, _ h: Side, group: String? = nil) -> Match {
            Match(id: "demo-\(sport.rawValue)-\(id)", sport: sport, group: group ?? sport.title, state: state,
                  statusText: text, start: date, home: h, away: a, venue: "Demo Arena", broadcast: "NeonTV", odds: nil)
        }
        switch sport {
        case .nba:
            return [m("1", .live, "Q3 5:41", side("a", "Los Angeles Lakers", "LAL", "78", ["24", "27", "27"]), side("b", "Boston Celtics", "BOS", "82", ["28", "25", "29"])),
                    m("2", .finished, "Final", side("c", "Denver Nuggets", "DEN", "118", winner: true), side("d", "Phoenix Suns", "PHX", "109")),
                    m("3", .upcoming, "7:30 PM", side("e", "Miami Heat", "MIA", ""), side("f", "New York Knicks", "NYK", ""))]
        case .nfl:
            return [m("1", .live, "Q2 2:10", side("a", "Kansas City Chiefs", "KC", "17", ["7", "10"]), side("b", "Buffalo Bills", "BUF", "14", ["7", "7"])),
                    m("2", .upcoming, "3:25 PM", side("c", "Dallas Cowboys", "DAL", ""), side("d", "Philadelphia Eagles", "PHI", ""))]
        case .mlb:
            return [m("1", .live, "Top 6th", side("a", "New York Yankees", "NYY", "4"), side("b", "Boston Red Sox", "BOS", "2")),
                    m("2", .finished, "Final", side("c", "LA Dodgers", "LAD", "6", winner: true), side("d", "San Diego Padres", "SD", "3"))]
        case .nhl:
            return [m("1", .live, "P2 8:33", side("a", "Toronto Maple Leafs", "TOR", "2"), side("b", "Montreal Canadiens", "MTL", "2")),
                    m("2", .upcoming, "8:00 PM", side("c", "Vegas Golden Knights", "VGK", ""), side("d", "Colorado Avalanche", "COL", ""))]
        case .atp, .wta:
            return [m("1", .live, "Set 3", side("a", "C. Alcaraz", "Alcaraz", "1", ["6", "4", "3"]), side("b", "J. Sinner", "Sinner", "1", ["3", "6", "2"]), group: "Demo Open · Final"),
                    m("2", .finished, "Final", side("c", "N. Djokovic", "Djokovic", "2", ["6", "7"], winner: true), side("d", "D. Medvedev", "Medvedev", "0", ["4", "5"]), group: "Demo Open · Semifinal")]
        }
    }
}
