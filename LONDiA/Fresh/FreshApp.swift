// ===== LONDiA New: app entry (store or admin, chosen at compile time) =====
import SwiftUI
import UserNotifications

final class FreshDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
  func application(_ a: UIApplication, didFinishLaunchingWithOptions o: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
    UNUserNotificationCenter.current().delegate = self; return true
  }
  func userNotificationCenter(_ c: UNUserNotificationCenter, willPresent n: UNNotification, withCompletionHandler h: @escaping (UNNotificationPresentationOptions) -> Void) { h([.banner, .sound]) }
}

@main
struct LONDiANewApp: App {
  @UIApplicationDelegateAdaptor(FreshDelegate.self) var delegate
  @StateObject var store = LDStore.shared
  init() { BootData() }
  var body: some Scene { WindowGroup { RootContainer().environmentObject(store) } }
}

struct RootContainer: View {
  @EnvironmentObject var store: LDStore
  var body: some View {
    let _ = store.rev
    Group {
      #if LD_ADMIN
      AdminGate()
      #else
      StoreRoot()
      #endif
    }
    .preferredColorScheme(store.colorScheme)
    .tint(T.red)
  }
}
