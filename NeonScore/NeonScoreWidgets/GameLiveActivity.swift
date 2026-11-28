import ActivityKit
import WidgetKit
import SwiftUI

private struct Logo: View {
    let data: Data?
    let fallback: String
    var size: CGFloat = 44
    var body: some View {
        if let data, let image = UIImage(data: data) {
            Image(uiImage: image).resizable().scaledToFit().frame(width: size, height: size)
        } else {
            Text(String(fallback.prefix(3))).font(.system(size: size * 0.3, weight: .heavy))
                .frame(width: size, height: size).background(Color.white.opacity(0.1), in: Circle())
        }
    }
}

private enum C {
    static let cyan = Color(red: 0.0, green: 0.90, blue: 1.0)
    static let magenta = Color(red: 1.0, green: 0.17, blue: 0.84)
    static let bg = Color(red: 0.03, green: 0.03, blue: 0.06)
}

@main
struct NeonScoreWidgetBundle: WidgetBundle {
    var body: some Widget { GameLiveActivity() }
}

struct GameLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GameAttributes.self) { context in
            LockScreenView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(C.bg)
                .activitySystemActionForegroundColor(C.cyan)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack { Logo(data: context.attributes.awayLogo, fallback: context.attributes.awayShort, size: 30)
                             Text(context.attributes.awayShort).font(.caption.bold()).foregroundStyle(C.magenta)
                             Text(context.state.awayScore).font(.title.bold().monospacedDigit()) }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack { Logo(data: context.attributes.homeLogo, fallback: context.attributes.homeShort, size: 30)
                             Text(context.attributes.homeShort).font(.caption.bold()).foregroundStyle(C.cyan)
                             Text(context.state.homeScore).font(.title.bold().monospacedDigit()) }
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.finished ? "FINAL" : context.state.status)
                        .font(.caption.bold()).foregroundStyle(context.state.live ? C.magenta : C.cyan)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 2) {
                        Text("\(context.attributes.awayName) vs \(context.attributes.homeName)")
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        let info = [context.attributes.broadcast, context.attributes.odds].filter { !$0.isEmpty }.joined(separator: " · ")
                        if !info.isEmpty { Text(info).font(.caption2).foregroundStyle(.white.opacity(0.7)).lineLimit(1) }
                    }
                }
            } compactLeading: {
                HStack(spacing: 4) { Logo(data: context.attributes.awayLogo, fallback: context.attributes.awayShort, size: 18)
                    Text(context.state.awayScore).font(.caption.bold().monospacedDigit()).foregroundStyle(C.magenta) }
            } compactTrailing: {
                HStack(spacing: 4) { Text(context.state.homeScore).font(.caption.bold().monospacedDigit()).foregroundStyle(C.cyan)
                    Logo(data: context.attributes.homeLogo, fallback: context.attributes.homeShort, size: 18) }
            } minimal: {
                Image(systemName: "bolt.fill").foregroundStyle(C.cyan)
            }
        }
    }
}

private struct LockScreenView: View {
    let attributes: GameAttributes
    let state: GameAttributes.ContentState

    private var infoLine: String {
        [attributes.broadcast, attributes.venue, attributes.odds].filter { !$0.isEmpty }.joined(separator: "  ·  ")
    }

    var body: some View {
        VStack(spacing: 14) {
            // Header
            HStack {
                Text(state.finished ? "FINAL" : (state.live ? "● LIVE" : "UPCOMING"))
                    .font(.caption.weight(.heavy)).foregroundStyle(state.live ? C.magenta : C.cyan)
                Spacer()
                if !state.live && !state.finished, let start = attributes.startDate, start > Date() {
                    // Counts down on its own, no app updates needed.
                    (Text("Starts in ") + Text(start, style: .relative))
                        .font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
                } else {
                    Text(state.status).font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
                }
            }

            // Teams + score
            HStack(alignment: .center) {
                team(attributes.awayShort, attributes.awayName, attributes.awayRecord, C.magenta, alignment: .leading)
                Spacer(minLength: 4)
                if state.live || state.finished {
                    HStack(spacing: 12) {
                        Text(state.awayScore); Text("–").foregroundStyle(.secondary); Text(state.homeScore)
                    }
                    .font(.system(size: 44, weight: .heavy).monospacedDigit()).foregroundStyle(.white)
                } else if let start = attributes.startDate {
                    VStack(spacing: 2) {
                        Text(start, style: .time).font(.system(size: 30, weight: .heavy)).foregroundStyle(.white)
                        Text(start, style: .date).font(.caption2).foregroundStyle(.secondary)
                    }
                } else {
                    Text("vs").font(.title2.weight(.heavy)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                team(attributes.homeShort, attributes.homeName, attributes.homeRecord, C.cyan, alignment: .trailing)
            }

            // Pre-game / match info
            if !infoLine.isEmpty {
                Text(infoLine)
                    .font(.caption).foregroundStyle(.white.opacity(0.7))
                    .lineLimit(2).multilineTextAlignment(.center).frame(maxWidth: .infinity)
                    .padding(.vertical, 8).padding(.horizontal, 10)
                    .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .padding(18)
    }

    private func team(_ short: String, _ name: String, _ record: String, _ color: Color, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 3) {
            Logo(data: alignment == .leading ? attributes.awayLogo : attributes.homeLogo, fallback: short, size: 48)
            Text(short).font(.title3.weight(.heavy)).foregroundStyle(color)
            Text(name).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            if !record.isEmpty { Text(record).font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.8)) }
        }
        .frame(width: 100, alignment: alignment == .leading ? .leading : .trailing)
    }
}
