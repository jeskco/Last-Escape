// ===== LONDiA New: theme, shared store, small components =====
import SwiftUI
import Combine

extension Item: Identifiable { var id: String { iid } }
extension Drop: Identifiable { var id: String { did } }

/// Bridges the shared core's globals into SwiftUI: every `Changed()` bumps `rev`, so views re-read.
final class LDStore: ObservableObject {
  static let shared = LDStore()
  @Published var rev = 0
  private var obs: NSObjectProtocol?
  init() { obs = NotificationCenter.default.addObserver(forName: kChange, object: nil, queue: .main) { [weak self] _ in self?.rev &+= 1 } }
  func bump() { rev &+= 1 }
  var items: [Item] { gItems }
  var drops: [Drop] { gDrops.sorted { $0.date < $1.date } }
  var saved: [Item] { gItems.filter { IsSaved($0.iid) } }
  func items(in d: Drop) -> [Item] { gItems.filter { $0.drop == d.did } }
  var colorScheme: ColorScheme? { gTheme == "dark" ? .dark : gTheme == "light" ? .light : nil }
}

enum T {
  static var red: Color { Color(uiColor: cRed()) }
  static var ink: Color { Color(uiColor: cInk()) }
  static var mute: Color { Color(uiColor: cMute()) }
  static var bg: Color { Color(uiColor: cBG()) }
  static var soft: Color { Color(uiColor: cSoft()) }
  static var line: Color { Color(uiColor: cLine()) }
  static var tile: Color { Color(uiColor: Dyn(Hex(0xE6E5E0), Hex(0x232322))) }
  static var card: Color { Color(uiColor: Dyn(.white, Hex(0x1E1E1D))) }
  static let spring = Animation.spring(response: 0.42, dampingFraction: 0.82)
  static let snappy = Animation.spring(response: 0.3, dampingFraction: 0.86)
}
func DF(_ s: CGFloat) -> Font { .custom("HelveticaNeue-CondensedBlack", size: s) }
let wordRatio: CGFloat = 345.0 / 1100.0

/// Spaced-out uppercase caption, the brand's small-label style.
struct Caps: View {
  let t: String; var size: CGFloat = 10; var color: Color = T.mute
  init(_ t: String, _ size: CGFloat = 10, _ color: Color = T.mute) { self.t = t; self.size = size; self.color = color }
  var body: some View { Text(t.uppercased()).font(.system(size: size, weight: .heavy)).kerning(size * 0.16).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.7) }
}

struct TintedBundleImage: View {
  let name: String; let color: Color
  var body: some View {
    if let ui = BundleImg(name) { Image(uiImage: ui).renderingMode(.template).resizable().scaledToFit().foregroundStyle(color) } else { Color.clear }
  }
}
/// Two-tone LONDiA wordmark (ink letters, accent i).
struct Wordmark: View {
  var width: CGFloat = 150; var ink: Color = T.ink; var accent: Color = T.red
  var body: some View {
    ZStack { TintedBundleImage(name: "logo_ink.png", color: ink); TintedBundleImage(name: "logo_red.png", color: accent) }
      .frame(width: width, height: width * wordRatio)
  }
}
struct WhiteWordmark: View {
  var width: CGFloat = 204
  var body: some View { TintedBundleImage(name: "logo_word.png", color: .white).frame(width: width, height: width / 2.8350515463917527) }
}

/// Product cut-out from the bundle or the admin-uploaded cache, with transparent margins trimmed.
struct ProductImage: View {
  let item: Item; var kind = "med"
  @EnvironmentObject var store: LDStore
  var body: some View {
    let _ = store.rev
    if let ui = TrimImg(Img(item.iid, kind)) { Image(uiImage: ui).resizable().scaledToFit() }
    else { Image(systemName: "tshirt").font(.system(size: 34, weight: .light)).foregroundStyle(T.mute) }
  }
}

struct HeartButton: View {
  let iid: String; var size: CGFloat = 17
  @EnvironmentObject var store: LDStore
  var body: some View {
    let on = { let _ = store.rev; return IsSaved(iid) }()
    Button { withAnimation(T.snappy) { ToggleSaved(iid) } } label: {
      Image(systemName: on ? "heart.fill" : "heart").font(.system(size: size, weight: .semibold))
        .foregroundStyle(on ? T.red : T.ink).contentTransition(.symbolEffect(.replace))
        .frame(width: size * 2.3, height: size * 2.3).background(.ultraThinMaterial, in: Circle())
    }.buttonStyle(Pressable())
  }
}

struct Pressable: ButtonStyle {
  func makeBody(configuration c: Configuration) -> some View {
    c.label.scaleEffect(c.isPressed ? 0.95 : 1).opacity(c.isPressed ? 0.85 : 1).animation(T.snappy, value: c.isPressed)
  }
}
/// Big rounded call-to-action.
struct CTA: View {
  let title: String; var color: Color = T.red; var fg: Color = .white; var icon: String? = nil; let action: () -> Void
  var body: some View {
    Button(action: action) {
      HStack(spacing: 8) { if let i = icon { Image(systemName: i).font(.system(size: 14, weight: .bold)) }; Text(title.uppercased()).font(.system(size: 13, weight: .heavy)).kerning(2) }
        .foregroundStyle(fg).frame(maxWidth: .infinity).frame(height: 56).background(color, in: Capsule())
    }.buttonStyle(Pressable())
  }
}

func StatusLine(_ it: Item) -> String { IsLive(it) ? "Out now" : "Drops \(DateShort(DropFor(it).date))" }

/// "02d 14h 05m 09s" style countdown parts.
func CountdownParts(_ to: Date, now: Date = Date()) -> [(String, String)] {
  let s = max(0, Int(to.timeIntervalSince(now)))
  return [(String(format: "%02d", s / 86400), "Days"), (String(format: "%02d", (s % 86400) / 3600), "Hrs"), (String(format: "%02d", (s % 3600) / 60), "Min"), (String(format: "%02d", s % 60), "Sec")]
}

struct Card<C: View>: View {
  var padding: CGFloat = 18; @ViewBuilder let content: () -> C
  var body: some View { content().padding(padding).frame(maxWidth: .infinity, alignment: .leading).background(T.card, in: RoundedRectangle(cornerRadius: 26, style: .continuous)) }
}

struct SeasonArt: View {
  var body: some View {
    if !gSeason.isEmpty, let ui = BundleImg("art_\(gSeason).png") {
      GeometryReader { _ in Image(uiImage: ui).resizable(resizingMode: .tile).opacity(0.08) }.ignoresSafeArea().allowsHitTesting(false)
    }
  }
}
