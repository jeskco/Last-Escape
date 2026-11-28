import SwiftUI

struct MatchDetailView: View {
    @EnvironmentObject var store: AppStore
    let initialMatch: Match
    @State private var live: Match?
    @State private var detail: MatchDetail?
    @State private var tab = 0
    @State private var failed = false
    private var match: Match { live ?? initialMatch }

    init(match: Match) {
        self.initialMatch = match
        _tab = State(initialValue: match.state == .live ? 1 : 0)
    }
    @State private var loading = true

    var body: some View {
        ZStack {
            NeonBackground()
            ScrollView {
                VStack(spacing: 16) {
                    header
                    Picker("", selection: $tab) {
                        Text("Overview").tag(0); Text("Cast").tag(1); Text("Stats").tag(2); Text("Players").tag(3); Text("Plays").tag(4)
                    }
                    .pickerStyle(.segmented).padding(.horizontal, 16)

                    if loading { ProgressView().tint(Neon.cyan).padding(.top, 30) }
                    else {
                        switch tab {
                        case 0: overview
                        case 1: GameCastView(match: match, shots: detail?.shots ?? [])
                        case 2: stats
                        case 3: players
                        default: plays
                        }
                    }
                }
                .padding(.vertical, 10)
            }
            .refreshable { await load() }
        }
        .navigationTitle(match.group)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { store.toggle(match) } label: {
                    Image(systemName: store.isFavorite(match) ? "star.fill" : "star").foregroundStyle(Neon.magenta)
                }
            }
        }
        .task {
            await load()
            // Keep a live game moving without pulling to refresh.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                guard match.state == .live else { continue }
                await load()
            }
        }
    }

    private func load() async {
        if let fresh = try? await ESPNService.shared.refreshed(match) { live = fresh }
        do { detail = try await ESPNService.shared.detail(for: match); failed = false }
        catch { failed = true }
        loading = false
    }

    private var header: some View {
        VStack(spacing: 14) {
            HStack(alignment: .top) {
                big(match.away); Spacer()
                VStack(spacing: 6) {
                    if match.state == .live { LivePill(text: match.statusText.uppercased()) }
                    else { Text(match.statusText).font(.subheadline.weight(.bold)).foregroundStyle(Neon.cyan) }
                    if !(match.sport.isTennis) && match.state != .upcoming {
                        HStack(spacing: 10) {
                            Text(match.away.score); Text("–").foregroundStyle(Neon.textDim); Text(match.home.score)
                        }
                        .font(.system(size: 38, weight: .heavy).monospacedDigit())
                    }
                }
                Spacer(); big(match.home)
            }
            if match.sport.isTennis, !match.home.lines.isEmpty { tennisGrid }
            else if !match.home.lines.isEmpty { lineScore }
        }
        .neonCard(highlight: match.state == .live)
        .padding(.horizontal, 16)
    }

    private func big(_ s: Side) -> some View {
        VStack(spacing: 6) {
            LogoView(url: s.logo, fallback: s.short, size: 56)
            Text(s.name).font(.footnote.weight(.semibold)).multilineTextAlignment(.center).lineLimit(2).frame(width: 100)
            if let r = s.record { Text(r).font(.caption2).foregroundStyle(Neon.textDim) }
        }
    }

    private var lineScore: some View {
        VStack(spacing: 6) {
            ForEach([match.away, match.home], id: \.id) { s in
                HStack {
                    Text(s.short).font(.caption.weight(.bold)).frame(width: 46, alignment: .leading)
                    ForEach(Array(s.lines.enumerated()), id: \.offset) { _, l in
                        Text(l).font(.caption.monospacedDigit()).frame(maxWidth: .infinity)
                    }
                    Text(s.score).font(.caption.monospacedDigit().weight(.heavy)).foregroundStyle(Neon.cyan).frame(width: 36)
                }
            }
        }
        .padding(.top, 4)
    }

    private var tennisGrid: some View {
        VStack(spacing: 6) {
            ForEach([match.away, match.home], id: \.id) { s in
                HStack {
                    Text(s.name).font(.caption.weight(s.winner ? .heavy : .regular)).frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(Array(s.lines.enumerated()), id: \.offset) { _, l in
                        Text(l).font(.subheadline.monospacedDigit().weight(.bold)).frame(width: 30)
                    }
                }
            }
        }
    }

    private var overview: some View {
        VStack(spacing: 12) {
            infoRow("calendar", match.start.map { $0.formatted(date: .abbreviated, time: .shortened) })
            infoRow("mappin.and.ellipse", detail?.venue ?? match.venue)
            infoRow("tv", match.broadcast)
            infoRow("chart.line.uptrend.xyaxis", [detail?.odds ?? match.odds, detail?.overUnder.map { "O/U \($0)" }].compactMap { $0 }.joined(separator: " · "))
            infoRow("person.3", detail?.attendance.map { "Attendance \($0)" })
            if failed { Text("Detailed stats aren't available for this game yet.").font(.footnote).foregroundStyle(Neon.textDim) }
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder private func infoRow(_ icon: String, _ text: String?) -> some View {
        if let text, !text.isEmpty {
            HStack(spacing: 12) {
                Image(systemName: icon).foregroundStyle(Neon.cyan).frame(width: 24)
                Text(text).font(.subheadline)
                Spacer()
            }
            .neonCard()
        }
    }

    private var stats: some View {
        VStack(spacing: 10) {
            if let list = detail?.stats, !list.isEmpty {
                ForEach(list) { s in
                    VStack(spacing: 6) {
                        HStack {
                            Text(s.away).font(.subheadline.weight(.bold).monospacedDigit())
                            Spacer()
                            Text(s.label).font(.caption).foregroundStyle(Neon.textDim)
                            Spacer()
                            Text(s.home).font(.subheadline.weight(.bold).monospacedDigit())
                        }
                        bar(s)
                    }
                    .neonCard()
                }
            } else { empty("No team stats yet") }
        }
        .padding(.horizontal, 16)
    }

    private func bar(_ s: StatLine) -> some View {
        let a = Double(s.away.filter { "0123456789.".contains($0) }) ?? 0
        let h = Double(s.home.filter { "0123456789.".contains($0) }) ?? 0
        let total = max(a + h, 0.0001)
        return GeometryReader { g in
            HStack(spacing: 3) {
                Capsule().fill(Neon.magenta).frame(width: max(4, g.size.width * a / total))
                Capsule().fill(Neon.cyan).frame(width: max(4, g.size.width * h / total))
            }
        }
        .frame(height: 5)
    }

    private var players: some View {
        VStack(spacing: 14) {
            if let tables = detail?.players, !tables.isEmpty {
                ForEach(tables) { t in
                    VStack(alignment: .leading, spacing: 8) {
                        SectionTitle(text: t.title)
                        ScrollView(.horizontal, showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 6) {
                                row(["PLAYER"] + t.labels, header: true)
                                ForEach(Array(t.rows.enumerated()), id: \.offset) { _, r in row(r, header: false) }
                            }
                        }
                    }
                    .neonCard()
                }
            } else { empty("No player stats yet") }
        }
        .padding(.horizontal, 16)
    }

    private func row(_ cells: [String], header: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { i, c in
                Text(c).font(header ? .caption2.weight(.heavy) : .caption.monospacedDigit())
                    .foregroundStyle(header ? Neon.cyan : .white)
                    .frame(width: i == 0 ? 130 : 44, alignment: i == 0 ? .leading : .trailing)
                    .lineLimit(1)
            }
        }
    }

    private var plays: some View {
        VStack(spacing: 8) {
            if let list = detail?.plays, !list.isEmpty {
                ForEach(list) { p in
                    HStack(alignment: .top, spacing: 12) {
                        Text(p.time).font(.caption.weight(.bold)).foregroundStyle(p.scoring ? Neon.magenta : Neon.cyan).frame(width: 64, alignment: .leading)
                        Text(p.text).font(.subheadline)
                        Spacer(minLength: 0)
                    }
                    .neonCard()
                }
            } else { empty("No play-by-play yet") }
        }
        .padding(.horizontal, 16)
    }

    private func empty(_ text: String) -> some View {
        Text(text).foregroundStyle(Neon.textDim).padding(.top, 30)
    }
}
