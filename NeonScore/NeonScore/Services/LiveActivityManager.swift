import Foundation
import ActivityKit
import UserNotifications

@MainActor
final class LiveActivityManager: ObservableObject {
    static let shared = LiveActivityManager()
    @Published private(set) var status = ""

    private func contentState(_ m: Match) -> GameAttributes.ContentState {
        func score(_ s: Side) -> String {
            if m.sport.isTennis { return s.lines.last ?? s.score }
            return s.score.isEmpty ? "–" : s.score
        }
        return .init(awayScore: score(m.away), homeScore: score(m.home), status: m.statusText,
                     live: m.state == .live, finished: m.state == .finished)
    }

    private func existing(_ id: String) -> Activity<GameAttributes>? {
        Activity<GameAttributes>.activities.first { $0.attributes.matchId == id }
    }

    func start(_ m: Match) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            status = "Live Activities are off. Turn them on in Settings > NeonScore."
            return
        }
        guard existing(m.id) == nil else { return }
        let attributes = GameAttributes(matchId: m.id, sport: m.sport.rawValue,
                                        awayShort: m.away.short, homeShort: m.home.short,
                                        awayName: m.away.name, homeName: m.home.name)
        do {
            _ = try Activity.request(attributes: attributes,
                                     content: .init(state: contentState(m), staleDate: nil), pushType: nil)
            status = "Live Activity started."
        } catch {
            status = "Couldn't start a Live Activity: \(error.localizedDescription)"
        }
    }

    func update(_ m: Match) async {
        guard let activity = existing(m.id) else { return }
        let content = ActivityContent(state: contentState(m), staleDate: nil)
        if m.state == .finished {
            await activity.end(content, dismissalPolicy: .after(Date().addingTimeInterval(20 * 60)))
        } else {
            await activity.update(content)
        }
    }

    func stop(_ id: String) {
        guard let activity = existing(id) else { return }
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }
}

enum Notifier {
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    private static func post(id: String, title: String, body: String, at date: Date? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title; content.body = body; content.sound = .default
        let trigger: UNNotificationTrigger? = date.map {
            UNCalendarNotificationTrigger(dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: $0), repeats: false)
        }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    static func scheduleStart(_ m: Match) {
        guard m.state == .upcoming, let start = m.start, start > Date() else { return }
        post(id: "start-\(m.sport.rawValue)-\(m.id)", title: "\(m.away.short) vs \(m.home.short) is starting",
             body: m.sport.title, at: start)
    }

    static func cancelStart(_ m: Match) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["start-\(m.sport.rawValue)-\(m.id)"])
    }

    static func notifyChange(old: Match, new: Match) {
        let score = "\(new.away.short) \(new.away.score) – \(new.home.score) \(new.home.short)"
        if old.state != .live && new.state == .live {
            post(id: "live-\(new.id)", title: "\(new.away.short) vs \(new.home.short) is live", body: new.statusText)
        } else if new.state == .finished && old.state != .finished {
            post(id: "final-\(new.id)", title: "Final: \(score)", body: new.sport.title)
        } else if new.state == .live && (old.home.score != new.home.score || old.away.score != new.away.score) {
            post(id: "score-\(new.id)-\(new.home.score)-\(new.away.score)", title: score, body: new.statusText)
        }
    }
}
