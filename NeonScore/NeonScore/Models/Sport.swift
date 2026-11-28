import SwiftUI

enum Sport: String, CaseIterable, Identifiable, Codable {
    case nba, nfl, mlb, nhl, atp, wta
    var id: String { rawValue }

    var title: String {
        switch self {
        case .nba: return "NBA"
        case .nfl: return "NFL"
        case .mlb: return "MLB"
        case .nhl: return "NHL"
        case .atp: return "ATP"
        case .wta: return "WTA"
        }
    }
    var fullName: String {
        switch self {
        case .nba: return "Basketball"
        case .nfl: return "American Football"
        case .mlb: return "Baseball"
        case .nhl: return "Hockey"
        case .atp: return "Men's Tennis"
        case .wta: return "Women's Tennis"
        }
    }
    var symbol: String {
        switch self {
        case .nba: return "basketball.fill"
        case .nfl: return "football.fill"
        case .mlb: return "baseball.fill"
        case .nhl: return "hockey.puck.fill"
        case .atp, .wta: return "tennisball.fill"
        }
    }
    var path: String {
        switch self {
        case .nba: return "basketball/nba"
        case .nfl: return "football/nfl"
        case .mlb: return "baseball/mlb"
        case .nhl: return "hockey/nhl"
        case .atp: return "tennis/atp"
        case .wta: return "tennis/wta"
        }
    }
    var isTennis: Bool { self == .atp || self == .wta }
    var hasTeams: Bool { !isTennis }
}
