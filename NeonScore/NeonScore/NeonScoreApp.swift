import SwiftUI
import BackgroundTasks

@main
struct NeonScoreApp: App {
    @StateObject private var store = AppStore.shared

    init() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.jesk.neonscore.refresh", using: nil) { task in
            Self.scheduleRefresh()
            let work = Task { @MainActor in
                await AppStore.shared.pollFavorites()
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = { work.cancel() }
        }
        let nav = UINavigationBarAppearance()
        nav.configureWithTransparentBackground()
        nav.titleTextAttributes = [.foregroundColor: UIColor.white]
        nav.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = UIColor(red: 0.03, green: 0.03, blue: 0.06, alpha: 0.96)
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
    }

    static func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: "com.jesk.neonscore.refresh")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 5 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .tint(Neon.cyan)
        }
        .onChange(of: phase) { _, new in
            if new == .background { Self.scheduleRefresh() }
        }
    }
}
