import Foundation
import SwiftUI
import BackgroundTasks

@MainActor
final class AppStore: ObservableObject {
    @Published var sport: Sport = .nba
    @Published var date: Date = Date()
    @Published var matches: [Match] = []
    @Published var loading = false
    @Published var usingDemo = false

    @Published var favoriteTeams: Set<String> = [] { didSet { save() } }       // "sport:teamId"
    @Published var favoriteMatches: Set<String> = [] { didSet { save() } }     // "sport:matchId"
    @Published var favoriteMatchSnapshots: [String: Match] = [:] { didSet { saveSnapshots() } }

    static let shared = AppStore()

    private var timer: Timer?
    private let defaults = UserDefaults.standard

    init() {
        favoriteTeams = Set(defaults.stringArray(forKey: "favTeams") ?? [])
        favoriteMatches = Set(defaults.stringArray(forKey: "favMatches") ?? [])
        if let data = defaults.data(forKey: "favSnapshots"),
           let decoded = try? JSONDecoder().decode([String: Match].self, from: data) {
            favoriteMatchSnapshots = decoded
        }
        Task { await load() }
        timer = Timer.scheduledTimer(withTimeInterval: 25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                await self.pollFavorites()
                guard Calendar.current.isDateInToday(self.date) else { return }
                await self.load(silent: true)
            }
        }
    }

    private func saveSnapshots() {
        if let data = try? JSONEncoder().encode(favoriteMatchSnapshots) { defaults.set(data, forKey: "favSnapshots") }
    }

    /// Refreshes every starred game, updates its Live Activity and sends score notifications.
    func pollFavorites() async {
        for (key, old) in favoriteMatchSnapshots {
            guard old.state != .finished || old.start.map({ Date().timeIntervalSince($0) < 6 * 3600 }) == true else { continue }
            guard let fresh = try? await ESPNService.shared.refreshed(old) else { continue }
            favoriteMatchSnapshots[key] = fresh
            await LiveActivityManager.shared.update(fresh)
            Notifier.notifyChange(old: old, new: fresh)
        }
    }

    private func save() {
        defaults.set(Array(favoriteTeams), forKey: "favTeams")
        defaults.set(Array(favoriteMatches), forKey: "favMatches")
    }

    func load(silent: Bool = false) async {
        if !silent { loading = true }
        defer { loading = false }
        let requested = sport, day = date
        do {
            let result = try await ESPNService.shared.scoreboard(requested, date: day)
            guard requested == sport, Calendar.current.isDate(day, inSameDayAs: date) else { return }
            matches = Self.sorted(result)
            usingDemo = false
        } catch {
            guard requested == sport else { return }
            matches = Self.sorted(DemoData.matches(for: requested, date: day))
            usingDemo = true
        }
    }

    static func sorted(_ list: [Match]) -> [Match] {
        list.sorted {
            if $0.state != $1.state { return $0.state.rawValue < $1.state.rawValue }
            return ($0.start ?? .distantFuture) < ($1.start ?? .distantFuture)
        }
    }

    func select(_ s: Sport) { sport = s; matches = []; Task { await load() } }
    func select(date d: Date) { date = d; matches = []; Task { await load() } }

    // MARK: Favorites
    func key(_ m: Match) -> String { "\(m.sport.rawValue):\(m.id)" }
    func isFavorite(_ m: Match) -> Bool { favoriteMatches.contains(key(m)) }
    func toggle(_ m: Match) {
        let k = key(m)
        if favoriteMatches.contains(k) {
            favoriteMatches.remove(k); favoriteMatchSnapshots[k] = nil
            LiveActivityManager.shared.stop(m.id); Notifier.cancelStart(m)
        } else {
            favoriteMatches.insert(k); favoriteMatchSnapshots[k] = m
            Notifier.requestAuthorization()
            if m.state != .finished { LiveActivityManager.shared.start(m) }
            Notifier.scheduleStart(m)
        }
    }
    func isFavorite(_ t: TeamInfo) -> Bool { favoriteTeams.contains(t.id) }
    func toggle(_ t: TeamInfo) {
        if favoriteTeams.contains(t.id) { favoriteTeams.remove(t.id) } else { favoriteTeams.insert(t.id) }
    }
    func involvesFavorite(_ m: Match) -> Bool {
        favoriteTeams.contains("\(m.sport.rawValue):\(m.home.id)") || favoriteTeams.contains("\(m.sport.rawValue):\(m.away.id)") || isFavorite(m)
    }
}
