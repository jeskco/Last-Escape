import Foundation

enum ESPNError: Error { case badResponse }

/// Thin client for ESPN's public (unofficial) JSON feeds.
struct ESPNService {
    static let shared = ESPNService()
    private let base = "https://site.api.espn.com/apis"
    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 12
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: cfg)
    }()

    private func fetch(_ urlString: String) async throws -> JSON {
        guard let url = URL(string: urlString) else { throw ESPNError.badResponse }
        let (data, response) = try await session.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: data) else { throw ESPNError.badResponse }
        return JSON(obj)
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd"; f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()

    func scoreboard(_ sport: Sport, date: Date) async throws -> [Match] {
        let day = Self.dayFormatter.string(from: date)
        let json = try await fetch("\(base)/site/v2/sports/\(sport.path)/scoreboard?dates=\(day)&limit=200")
        return MatchParser.scoreboard(json, sport: sport)
    }

    /// Fresh copy of one game (score, clock, field situation) from the scoreboard.
    func refreshed(_ match: Match) async throws -> Match? {
        let list = try await scoreboard(match.sport, date: match.start ?? Date())
        return list.first { $0.id == match.id }
    }

    func detail(for match: Match) async throws -> MatchDetail {
        let json = try await fetch("\(base)/site/v2/sports/\(match.sport.path)/summary?event=\(match.id)")
        var d = MatchDetail()

        // Team stats (home/away aligned by team id, falling back to order).
        let teams = json["boxscore"]["teams"].array
        if teams.count >= 2 {
            func stats(_ t: JSON) -> [(String, String)] {
                t["statistics"].array.compactMap { s in
                    guard let label = s["label"].string ?? s["name"].string,
                          let value = s["displayValue"].string else { return nil }
                    return (label, value)
                }
            }
            let homeTeam = teams.first { $0["homeAway"].string == "home" } ?? teams[1]
            let awayTeam = teams.first { $0["homeAway"].string == "away" } ?? teams[0]
            let home = stats(homeTeam), away = Dictionary(stats(awayTeam), uniquingKeysWith: { a, _ in a })
            d.stats = home.map { StatLine(label: $0.0, home: $0.1, away: away[$0.0] ?? "—") }
        }

        // Player tables.
        for teamBlock in json["boxscore"]["players"].array {
            let teamName = teamBlock["team"]["displayName"].string ?? ""
            for stat in teamBlock["statistics"].array {
                let labels = stat["labels"].array.compactMap { $0.string }
                let rows: [[String]] = stat["athletes"].array.compactMap { a in
                    guard let name = a["athlete"]["displayName"].string else { return nil }
                    return [name] + a["stats"].array.map { $0.string ?? "" }
                }
                guard !labels.isEmpty, !rows.isEmpty else { continue }
                let kind = stat["name"].string ?? stat["type"].string ?? ""
                d.players.append(PlayerTable(title: kind.isEmpty ? teamName : "\(teamName) · \(kind.capitalized)",
                                             labels: labels, rows: rows))
            }
        }

        // Key plays.
        let scoring = json["scoringPlays"].array
        let source = scoring.isEmpty ? Array(json["plays"].array.suffix(60).reversed()) : scoring
        d.plays = source.compactMap { p in
            guard let text = p["text"].string ?? p["shortText"].string else { return nil }
            let clock = p["clock"]["displayValue"].string ?? ""
            let period = p["period"]["displayValue"].string ?? p["period"]["number"].string ?? ""
            let time = [period, clock].filter { !$0.isEmpty }.joined(separator: " ")
            return PlayItem(time: time, text: text, scoring: p["scoringPlay"].bool ?? !scoring.isEmpty)
        }

        // Roster (jersey numbers, starters) for the animated court.
        var seen = Set<String>()
        for teamBlock in json["boxscore"]["players"].array {
            let teamId = teamBlock["team"]["id"].string ?? ""
            for stat in teamBlock["statistics"].array {
                for a in stat["athletes"].array {
                    guard let name = a["athlete"]["displayName"].string, seen.insert("\(teamId)\(name)").inserted else { continue }
                    d.roster.append(RosterPlayer(name: name, jersey: a["athlete"]["jersey"].string ?? "",
                                                 starter: a["starter"].bool ?? false, teamId: teamId))
                }
            }
        }

        // Full chronological play list for the replay.
        var lastAway = 0, lastHome = 0
        for (i, p) in json["plays"].array.enumerated() {
            lastAway = p["awayScore"].int ?? lastAway
            lastHome = p["homeScore"].int ?? lastHome
            guard let text = p["text"].string else { continue }
            let c = p["coordinate"]
            var x = c["x"].double, y = c["y"].double
            if let xv = x, let yv = y, abs(xv) > 1000 || abs(yv) > 1000 { x = nil; y = nil }
            d.cast.append(CastPlay(id: i, period: p["period"]["number"].int ?? 1,
                                   clock: p["clock"]["displayValue"].string ?? "",
                                   text: text, type: p["type"]["text"].string ?? "",
                                   teamId: p["team"]["id"].string,
                                   shooting: p["shootingPlay"].bool ?? false,
                                   scoring: p["scoringPlay"].bool ?? false,
                                   points: p["scoreValue"].int ?? 0, x: x, y: y,
                                   away: lastAway, home: lastHome))
        }

        // Located plays (shots) for the court / rink view.
        for p in json["plays"].array {
            let c = p["coordinate"]
            guard let x = c["x"].double, let y = c["y"].double, abs(x) < 1000, abs(y) < 1000 else { continue }
            let text = p["text"].string ?? ""
            let made = p["scoringPlay"].bool ?? false
            let isShot = p["shootingPlay"].bool ?? (match.sport == .nhl)
            guard isShot || made else { continue }
            d.shots.append(ShotMark(x: x, y: y, made: made, teamId: p["team"]["id"].string, text: text))
        }

        let pick = json["pickcenter"][0]
        d.odds = pick["details"].string
        d.overUnder = pick["overUnder"].string
        d.venue = json["gameInfo"]["venue"]["fullName"].string
        d.attendance = json["gameInfo"]["attendance"].string
        return d
    }

    func standings(_ sport: Sport) async throws -> [StandingGroup] {
        if sport.isTennis { return try await rankings(sport) }
        let json = try await fetch("\(base)/v2/sports/\(sport.path)/standings")
        let wanted: [(String, String)]
        switch sport {
        case .nba: wanted = [("wins", "W"), ("losses", "L"), ("winPercent", "PCT"), ("gamesBehind", "GB"), ("streak", "STRK")]
        case .nfl: wanted = [("wins", "W"), ("losses", "L"), ("ties", "T"), ("winPercent", "PCT"), ("pointDifferential", "DIFF")]
        case .mlb: wanted = [("wins", "W"), ("losses", "L"), ("winPercent", "PCT"), ("gamesBehind", "GB"), ("streak", "STRK")]
        default:   wanted = [("wins", "W"), ("losses", "L"), ("otLosses", "OTL"), ("points", "PTS"), ("streak", "STRK")]
        }
        var groups: [StandingGroup] = []
        func build(name: String, node: JSON) {
            let entries = node["standings"]["entries"].array
            guard !entries.isEmpty else { return }
            let present = wanted.filter { key, _ in entries.contains { e in e["stats"].array.contains { $0["name"].string == key } } }
            var rows: [(Double, StandingRow)] = entries.enumerated().map { i, e in
                let team = e["team"]
                var map: [String: String] = [:]
                var sortKey = 0.0
                for s in e["stats"].array {
                    if let n = s["name"].string { map[n] = s["displayValue"].string ?? "" }
                    if s["name"].string == "winPercent" || (sport == .nhl && s["name"].string == "points") {
                        sortKey = s["value"].double ?? sortKey
                    }
                }
                let name = team["displayName"].string ?? "—"
                return (sortKey, StandingRow(id: team["id"].string ?? "\(name)\(i)", rank: 0, name: name,
                                              short: team["abbreviation"].string ?? "",
                                              logo: team["logos"][0]["href"].url ?? team["logo"].url,
                                              values: present.map { map[$0.0] ?? "—" }))
            }
            rows.sort { $0.0 > $1.0 }
            let ranked = rows.enumerated().map { i, pair -> StandingRow in var r = pair.1; r.rank = i + 1; return r }
            groups.append(StandingGroup(name: name, columns: present.map { $0.1 }, rows: ranked))
        }
        let children = json["children"].array
        if children.isEmpty { build(name: sport.title, node: json) }
        for child in children {
            if child["children"].array.isEmpty {
                build(name: child["name"].string ?? "Standings", node: child)
            } else {
                for sub in child["children"].array {
                    build(name: sub["name"].string ?? "Standings", node: sub)
                }
            }
        }
        return groups
    }

    private func rankings(_ sport: Sport) async throws -> [StandingGroup] {
        let json = try await fetch("\(base)/site/v2/sports/\(sport.path)/rankings")
        var groups: [StandingGroup] = []
        for ranking in json["rankings"].array {
            let rows: [StandingRow] = ranking["ranks"].array.enumerated().map { i, r in
                let a = r["athlete"]
                return StandingRow(id: a["id"].string ?? "\(i)", rank: r["current"].int ?? i + 1,
                                   name: a["displayName"].string ?? "—", short: a["shortName"].string ?? "",
                                   logo: a["flag"]["href"].url,
                                   values: [r["points"].string ?? "—"])
            }
            if !rows.isEmpty {
                groups.append(StandingGroup(name: ranking["name"].string ?? "\(sport.title) Rankings", columns: ["PTS"], rows: rows))
            }
        }
        return groups
    }

    func news(_ sport: Sport) async throws -> [Article] {
        let json = try await fetch("\(base)/site/v2/sports/\(sport.path)/news?limit=30")
        return json["articles"].array.compactMap { a in
            guard let headline = a["headline"].string else { return nil }
            return Article(id: a["id"].string ?? headline, headline: headline,
                           summary: a["description"].string ?? "",
                           image: a["images"][0]["url"].url,
                           link: a["links"]["web"]["href"].url,
                           published: MatchParser.parseDate(a["published"].string))
        }
    }

    func teams(_ sport: Sport) async throws -> [TeamInfo] {
        guard sport.hasTeams else { return [] }
        let json = try await fetch("\(base)/site/v2/sports/\(sport.path)/teams?limit=100")
        return json["sports"][0]["leagues"][0]["teams"].array.compactMap { t in
            let team = t["team"]
            guard let id = team["id"].string, let name = team["displayName"].string else { return nil }
            return TeamInfo(sport: sport, teamId: id, name: name,
                            short: team["abbreviation"].string ?? "",
                            logo: team["logos"][0]["href"].url)
        }
    }
}
