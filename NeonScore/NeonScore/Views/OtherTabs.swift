import SwiftUI

// MARK: Favorites
struct FavoritesView: View {
    @EnvironmentObject var store: AppStore
    @State private var games: [Match] = []
    @State private var loading = false

    var body: some View {
        NavigationStack {
            ZStack {
                NeonBackground()
                ScrollView {
                    VStack(spacing: 10) {
                        if store.favoriteTeams.isEmpty && store.favoriteMatches.isEmpty {
                            VStack(spacing: 10) {
                                Image(systemName: "star").font(.system(size: 40)).foregroundStyle(Neon.magenta)
                                Text("Star games or follow teams in Search\nand they show up here.")
                                    .multilineTextAlignment(.center).foregroundStyle(Neon.textDim)
                            }.padding(.top, 80)
                        } else if loading && games.isEmpty {
                            ProgressView().tint(Neon.cyan).padding(.top, 60)
                        } else {
                            SectionTitle(text: "Today & starred")
                            ForEach(games) { m in
                                NavigationLink(value: m) { MatchRow(match: m) }.buttonStyle(.plain)
                            }
                            if games.isEmpty { Text("None of your favorites play today.").foregroundStyle(Neon.textDim).padding(.top, 30) }
                        }
                    }
                    .padding(16)
                }
                .refreshable { await reload() }
            }
            .navigationTitle("Favorites")
            .navigationDestination(for: Match.self) { MatchDetailView(match: $0) }
            .task(id: store.favoriteTeams.count + store.favoriteMatches.count) { await reload() }
        }
    }

    private func reload() async {
        loading = true
        var found: [Match] = []
        await withTaskGroup(of: [Match].self) { group in
            for sport in Sport.allCases {
                group.addTask { (try? await ESPNService.shared.scoreboard(sport, date: Date())) ?? [] }
            }
            for await list in group { found += list.filter { store.involvesFavorite($0) } }
        }
        for (k, snap) in store.favoriteMatchSnapshots where !found.contains(where: { store.key($0) == k }) { found.append(snap) }
        games = AppStore.sorted(found)
        loading = false
    }
}

// MARK: Standings
struct StandingsView: View {
    @State private var sport: Sport = .nba
    @State private var groups: [StandingGroup] = []
    @State private var loading = true
    @State private var failed = false

    var body: some View {
        NavigationStack {
            ZStack {
                NeonBackground()
                ScrollView {
                    VStack(spacing: 14) {
                        SportPicker(selection: $sport) { _ in Task { await load() } }
                        if loading { ProgressView().tint(Neon.cyan).padding(.top, 50) }
                        else if groups.isEmpty {
                            Text(failed ? "Couldn't load standings." : "No standings available.")
                                .foregroundStyle(Neon.textDim).padding(.top, 50)
                        }
                        ForEach(groups) { g in
                            VStack(alignment: .leading, spacing: 8) {
                                SectionTitle(text: g.name)
                                HStack {
                                    Text("#").frame(width: 24, alignment: .leading)
                                    Text(sport.isTennis ? "PLAYER" : "TEAM")
                                    Spacer()
                                    ForEach(g.columns, id: \.self) { Text($0).frame(width: 42, alignment: .trailing) }
                                }
                                .font(.caption2.weight(.heavy)).foregroundStyle(Neon.cyan)
                                ForEach(g.rows) { r in
                                    HStack(spacing: 8) {
                                        Text("\(r.rank)").font(.caption.weight(.bold)).foregroundStyle(Neon.textDim).frame(width: 24, alignment: .leading)
                                        LogoView(url: r.logo, fallback: r.short, size: 22)
                                        Text(sport.isTennis ? r.name : (r.short.isEmpty ? r.name : r.short)).font(.subheadline.weight(.semibold)).lineLimit(1)
                                        Spacer()
                                        ForEach(Array(r.values.enumerated()), id: \.offset) { _, v in
                                            Text(v).font(.caption.monospacedDigit()).frame(width: 42, alignment: .trailing)
                                        }
                                    }
                                }
                            }
                            .neonCard()
                            .padding(.horizontal, 16)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .refreshable { await load() }
            }
            .navigationTitle("Standings")
            .task { await load() }
        }
    }

    private func load() async {
        loading = true; failed = false
        let requested = sport
        do { let g = try await ESPNService.shared.standings(requested); if requested == sport { groups = g } }
        catch { if requested == sport { groups = []; failed = true } }
        loading = false
    }
}

// MARK: News
struct NewsView: View {
    @State private var sport: Sport = .nba
    @State private var articles: [Article] = []
    @State private var loading = true

    var body: some View {
        NavigationStack {
            ZStack {
                NeonBackground()
                ScrollView {
                    VStack(spacing: 12) {
                        SportPicker(selection: $sport) { _ in Task { await load() } }
                        if loading { ProgressView().tint(Neon.cyan).padding(.top, 50) }
                        else if articles.isEmpty { Text("No news right now.").foregroundStyle(Neon.textDim).padding(.top, 50) }
                        ForEach(articles) { a in
                            if let link = a.link {
                                Link(destination: link) { card(a) }.buttonStyle(.plain)
                            } else { card(a) }
                        }
                    }
                    .padding(.vertical, 8)
                }
                .refreshable { await load() }
            }
            .navigationTitle("News")
            .task { await load() }
        }
    }

    private func card(_ a: Article) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let img = a.image {
                AsyncImage(url: img) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() } else { Neon.surfaceHigh }
                }
                .frame(height: 170).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            Text(a.headline).font(.headline).multilineTextAlignment(.leading)
            if !a.summary.isEmpty { Text(a.summary).font(.footnote).foregroundStyle(Neon.textDim).lineLimit(3).multilineTextAlignment(.leading) }
            if let d = a.published { Text(d.formatted(.relative(presentation: .named))).font(.caption2).foregroundStyle(Neon.magenta) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .neonCard()
        .padding(.horizontal, 16)
    }

    private func load() async {
        loading = true
        let requested = sport
        let result = (try? await ESPNService.shared.news(requested)) ?? []
        if requested == sport { articles = result }
        loading = false
    }
}

// MARK: Search / follow teams
struct SearchView: View {
    @EnvironmentObject var store: AppStore
    @State private var teams: [TeamInfo] = []
    @State private var query = ""
    @State private var loading = true

    private var filtered: [TeamInfo] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? teams : teams.filter { $0.name.lowercased().contains(q) || $0.short.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                NeonBackground()
                ScrollView {
                    LazyVStack(spacing: 8) {
                        if loading { ProgressView().tint(Neon.cyan).padding(.top, 50) }
                        ForEach(filtered) { t in
                            HStack(spacing: 12) {
                                LogoView(url: t.logo, fallback: t.short, size: 36)
                                VStack(alignment: .leading) {
                                    Text(t.name).font(.subheadline.weight(.semibold))
                                    Text(t.sport.title).font(.caption).foregroundStyle(Neon.textDim)
                                }
                                Spacer()
                                Button { store.toggle(t) } label: {
                                    Text(store.isFavorite(t) ? "Following" : "Follow")
                                        .font(.caption.weight(.bold))
                                        .padding(.horizontal, 12).padding(.vertical, 6)
                                        .foregroundStyle(store.isFavorite(t) ? Neon.black : Neon.cyan)
                                        .background(store.isFavorite(t) ? AnyShapeStyle(Neon.gradient) : AnyShapeStyle(Neon.cyan.opacity(0.14)), in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                            .neonCard()
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Search")
            .searchable(text: $query, prompt: "Teams across NBA, NFL, MLB, NHL")
            .task {
                var all: [TeamInfo] = []
                for sport in Sport.allCases where sport.hasTeams {
                    all += (try? await ESPNService.shared.teams(sport)) ?? []
                }
                teams = all.sorted { $0.name < $1.name }
                loading = false
            }
        }
    }
}
