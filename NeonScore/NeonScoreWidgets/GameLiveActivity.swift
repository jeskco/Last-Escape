import ActivityKit
import WidgetKit
import SwiftUI

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
                    VStack { Text(context.attributes.awayShort).font(.caption.bold()).foregroundStyle(C.magenta)
                             Text(context.state.awayScore).font(.title.bold().monospacedDigit()) }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack { Text(context.attributes.homeShort).font(.caption.bold()).foregroundStyle(C.cyan)
                             Text(context.state.homeScore).font(.title.bold().monospacedDigit()) }
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.finished ? "FINAL" : context.state.status)
                        .font(.caption.bold()).foregroundStyle(context.state.live ? C.magenta : C.cyan)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("\(context.attributes.awayName) vs \(context.attributes.homeName)")
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            } compactLeading: {
                Text("\(context.attributes.awayShort) \(context.state.awayScore)").font(.caption2.bold()).foregroundStyle(C.magenta)
            } compactTrailing: {
                Text("\(context.state.homeScore) \(context.attributes.homeShort)").font(.caption2.bold()).foregroundStyle(C.cyan)
            } minimal: {
                Image(systemName: "bolt.fill").foregroundStyle(C.cyan)
            }
        }
    }
}

private struct LockScreenView: View {
    let attributes: GameAttributes
    let state: GameAttributes.ContentState

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(state.finished ? "FINAL" : (state.live ? "LIVE" : "UPCOMING"))
                    .font(.caption2.weight(.heavy)).foregroundStyle(state.live ? C.magenta : C.cyan)
                Spacer()
                Text(state.status).font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.8))
            }
            HStack {
                team(attributes.awayShort, attributes.awayName, C.magenta, alignment: .leading)
                Spacer()
                HStack(spacing: 10) {
                    Text(state.awayScore); Text("–").foregroundStyle(.secondary); Text(state.homeScore)
                }
                .font(.system(size: 34, weight: .heavy).monospacedDigit()).foregroundStyle(.white)
                Spacer()
                team(attributes.homeShort, attributes.homeName, C.cyan, alignment: .trailing)
            }
        }
        .padding(16)
    }

    private func team(_ short: String, _ name: String, _ color: Color, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(short).font(.title3.weight(.heavy)).foregroundStyle(color)
            Text(name).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(width: 90, alignment: alignment == .leading ? .leading : .trailing)
    }
}
