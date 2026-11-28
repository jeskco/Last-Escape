import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            ScoresView().tabItem { Label("Scores", systemImage: "bolt.fill") }
            FavoritesView().tabItem { Label("Favorites", systemImage: "star.fill") }
            StandingsView().tabItem { Label("Standings", systemImage: "list.number") }
            NewsView().tabItem { Label("News", systemImage: "newspaper.fill") }
            SearchView().tabItem { Label("Search", systemImage: "magnifyingglass") }
        }
    }
}

struct SportPicker: View {
    @Binding var selection: Sport
    var onChange: (Sport) -> Void
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Sport.allCases) { sport in
                    let on = selection == sport
                    Button {
                        selection = sport
                        onChange(sport)
                    } label: {
                        Label(sport.title, systemImage: sport.symbol)
                            .font(.subheadline.weight(.bold))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .foregroundStyle(on ? Color.black : Color.white)
                            .background(on ? AnyShapeStyle(Neon.gradient) : AnyShapeStyle(Neon.surfaceHigh), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }
}
