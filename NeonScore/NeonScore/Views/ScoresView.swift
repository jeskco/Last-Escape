import SwiftUI

struct ScoresView: View {
    @EnvironmentObject var store: AppStore
    @State private var liveOnly = false

    private var visible: [Match] { liveOnly ? store.matches.filter { $0.state == .live } : store.matches }
    private var groups: [(String, [Match])] {
        var order: [String] = []
        var dict: [String: [Match]] = [:]
        for m in visible {
            if dict[m.group] == nil { order.append(m.group) }
            dict[m.group, default: []].append(m)
        }
        return order.map { ($0, dict[$0]!) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                NeonBackground()
                ScrollView {
                    VStack(spacing: 14) {
                        SportPicker(selection: Binding(get: { store.sport }, set: { _ in })) { store.select($0) }
                        DateStrip()
                        HStack {
                            Toggle(isOn: $liveOnly) {
                                Label("Live only", systemImage: "dot.radiowaves.left.and.right")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .toggleStyle(.switch).tint(Neon.magenta)
                        }
                        .padding(.horizontal, 20)

                        if store.usingDemo {
                            Label("Can't reach live scores — showing demo data", systemImage: "wifi.exclamationmark")
                                .font(.footnote).foregroundStyle(Neon.magenta)
                        }

                        if store.loading && store.matches.isEmpty {
                            ProgressView().tint(Neon.cyan).padding(.top, 60)
                        } else if visible.isEmpty {
                            VStack(spacing: 10) {
                                Image(systemName: "sportscourt").font(.system(size: 40)).foregroundStyle(Neon.cyan)
                                Text(liveOnly ? "Nothing live right now" : "No games on this day")
                                    .foregroundStyle(Neon.textDim)
                            }.padding(.top, 60)
                        } else {
                            ForEach(groups, id: \.0) { name, list in
                                VStack(spacing: 8) {
                                    SectionTitle(text: name)
                                    ForEach(list) { match in
                                        NavigationLink(value: match) { MatchRow(match: match) }
                                            .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
                .refreshable { await store.load() }
            }
            .navigationTitle("NeonScore")
            .navigationDestination(for: Match.self) { MatchDetailView(match: $0) }
        }
    }
}

struct DateStrip: View {
    @EnvironmentObject var store: AppStore
    private let days: [Date] = (-3...5).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: Date()) }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(days, id: \.self) { day in
                        let on = Calendar.current.isDate(day, inSameDayAs: store.date)
                        Button { store.select(date: day) } label: {
                            VStack(spacing: 2) {
                                Text(Calendar.current.isDateInToday(day) ? "TODAY" : day.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                                    .font(.caption2.weight(.heavy))
                                Text(day.formatted(.dateTime.day())).font(.headline)
                            }
                            .frame(width: 58, height: 54)
                            .foregroundStyle(on ? Neon.black : Color.white)
                            .background(on ? AnyShapeStyle(Neon.cyan) : AnyShapeStyle(Neon.surface), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(on ? 0 : 0.08)))
                        }
                        .buttonStyle(.plain)
                        .id(day)
                    }
                }
                .padding(.horizontal, 16)
            }
            .onAppear { if let today = days.first(where: { Calendar.current.isDateInToday($0) }) { proxy.scrollTo(today, anchor: .center) } }
        }
    }
}

struct MatchRow: View {
    @EnvironmentObject var store: AppStore
    let match: Match

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                teamLine(match.away)
                teamLine(match.home)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                if match.state == .live { LivePill(text: match.statusText.uppercased()) }
                else {
                    Text(match.statusText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(match.state == .finished ? Neon.textDim : Neon.cyan)
                }
                Button { store.toggle(match) } label: {
                    Image(systemName: store.isFavorite(match) ? "star.fill" : "star")
                        .foregroundStyle(store.isFavorite(match) ? Neon.magenta : Neon.textDim)
                }
                .buttonStyle(.borderless)
            }
        }
        .neonCard(highlight: match.state == .live)
    }

    private func teamLine(_ side: Side) -> some View {
        HStack(spacing: 10) {
            LogoView(url: side.logo, fallback: side.short, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(side.name).font(.subheadline.weight(side.winner ? .bold : .medium)).lineLimit(1)
                    .foregroundStyle(match.state == .finished && !side.winner ? Neon.textDim : .white)
                if let r = side.record { Text(r).font(.caption2).foregroundStyle(Neon.textDim) }
            }
            Spacer(minLength: 4)
            if match.sport.isTennis && !side.lines.isEmpty {
                HStack(spacing: 8) {
                    ForEach(Array(side.lines.enumerated()), id: \.offset) { _, s in
                        Text(s).font(.subheadline.monospacedDigit().weight(.semibold))
                    }
                }
            } else if !side.score.isEmpty {
                Text(side.score).font(.title3.monospacedDigit().weight(.heavy))
                    .foregroundStyle(side.winner || match.state == .live ? Neon.cyan : .white)
            }
        }
    }
}
