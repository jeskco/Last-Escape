// ===== LONDiA New: storefront (SwiftUI redesign) =====
import SwiftUI

enum LDTab: Int, CaseIterable { case shop, drops, saved, bag, you
  var title: String { ["Shop", "Drops", "Saved", "Bag", "You"][rawValue] }
  var icon: String { ["square.grid.2x2", "calendar", "heart", "bag", "person"][rawValue] }
  var iconOn: String { ["square.grid.2x2.fill", "calendar", "heart.fill", "bag.fill", "person.fill"][rawValue] }
}
/// Which list the product viewer is paging through.
struct Viewer: Identifiable { let id = UUID(); let items: [Item]; let start: String }

struct StoreRoot: View {
  @EnvironmentObject var store: LDStore
  @State var tab: LDTab = .shop
  @State var viewer: Viewer?
  @State var splash = !UD.bool(forKey: "ld_welcomed")
  @State var flash = UD.bool(forKey: "ld_welcomed")
  @Namespace var ns
  var body: some View {
    let _ = store.rev
    ZStack(alignment: .bottom) {
      T.bg.ignoresSafeArea()
      SeasonArt()
      Group {
        switch tab {
        case .shop: ShopScreen(open: open)
        case .drops: DropsScreen(open: open)
        case .saved: SavedScreen(open: open, goShop: { select(.shop) })
        case .bag: BagScreen(goShop: { select(.shop) })
        case .you: YouScreen()
        }
      }
      .transition(.opacity.combined(with: .scale(scale: 0.985)))
      .id(tab)
      TabBar(tab: $tab, ns: ns)
      if splash { SplashScreen { withAnimation(.easeOut(duration: 0.45)) { splash = false } }.transition(.move(edge: .top)).zIndex(5) }
      if flash { RedFlash { flash = false }.zIndex(6) }
    }
    .fullScreenCover(item: $viewer) { v in ProductViewer(items: v.items, start: v.start).environmentObject(store) }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
      let last = UD.double(forKey: "ld_last"); if last > 0 && Date().timeIntervalSince1970 - last > 600 && !splash { flash = true }; Stamp(); SyncCatalog()
    }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in Stamp() }
  }
  func select(_ t: LDTab) { Hap(1); withAnimation(T.snappy) { tab = t } }
  func open(_ items: [Item], _ it: Item) { Hap(1); viewer = Viewer(items: items, start: it.iid) }
}

struct TabBar: View {
  @Binding var tab: LDTab; var ns: Namespace.ID
  @EnvironmentObject var store: LDStore
  var body: some View {
    let _ = store.rev
    HStack(spacing: 0) {
      ForEach(LDTab.allCases, id: \.self) { t in
        let on = t == tab
        Button { if t != tab { Hap(1) }; withAnimation(T.snappy) { tab = t } } label: {
          VStack(spacing: 3) {
            Image(systemName: on ? t.iconOn : t.icon).font(.system(size: 18, weight: .semibold)).frame(height: 22)
              .overlay(alignment: .topTrailing) { badge(t) }
            Text(t.title.uppercased()).font(DF(10.5)).kerning(1)
          }
          .foregroundStyle(on ? Color.white : T.ink.opacity(0.55))
          .frame(maxWidth: .infinity).frame(height: 54)
          .background { if on { Capsule().fill(T.red).matchedGeometryEffect(id: "pill", in: ns).padding(.horizontal, 4) } }
        }.buttonStyle(.plain)
      }
    }
    .padding(5).background(.ultraThinMaterial, in: Capsule()).overlay(Capsule().stroke(T.line, lineWidth: 0.5))
    .shadow(color: .black.opacity(0.12), radius: 18, y: 8).padding(.horizontal, 14).padding(.bottom, 4)
  }
  @ViewBuilder func badge(_ t: LDTab) -> some View {
    let n = t == .saved ? gSaved.count : t == .bag ? BagCount() : t == .drops ? RemCount() : 0
    if n > 0 && t != tab {
      Text("\(n)").font(.system(size: 9, weight: .heavy)).foregroundStyle(.white).padding(.horizontal, 5).frame(minWidth: 16, minHeight: 16)
        .background(T.red, in: Capsule()).offset(x: 12, y: -6).transition(.scale)
    }
  }
}

// ---------- header ----------
struct ScreenHeader<Trailing: View>: View {
  let title: String; var accent: String = ""; @ViewBuilder var trailing: () -> Trailing
  var body: some View {
    HStack(alignment: .lastTextBaseline) {
      (Text(title.uppercased()).foregroundStyle(T.ink) + Text(accent.uppercased()).foregroundStyle(T.red)).font(DF(46))
      Spacer(); trailing()
    }.padding(.horizontal, 20)
  }
}
extension ScreenHeader where Trailing == EmptyView { init(title: String, accent: String = "") { self.title = title; self.accent = accent; trailing = { EmptyView() } } }

// ---------- shop ----------
struct ShopScreen: View {
  let open: ([Item], Item) -> Void
  @EnvironmentObject var store: LDStore
  @State var cat = "All"
  let cats = ["All", "Tees", "Hoodies", "Pants"]
  var list: [Item] { store.items.filter { cat == "All" || $0.cat == cat } }
  var body: some View {
    let _ = store.rev
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        HStack { Wordmark(width: 132); Spacer(); Caps("L'Art de la Vie", 9.5) }.padding(.horizontal, 20).padding(.top, 6)
        NextDropBanner().padding(.horizontal, 16)
        CategoryBar(cat: $cat, cats: cats).padding(.horizontal, 16)
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 18) {
          ForEach(list) { it in ProductCard(item: it).onTapGesture { open(list, it) } }
        }.padding(.horizontal, 16).animation(T.spring, value: cat)
        if list.isEmpty { Caps("Nothing here yet", 11).frame(maxWidth: .infinity).padding(40) }
      }.padding(.bottom, 110)
    }.scrollIndicators(.hidden).refreshable { SyncCatalog() }
  }
}

struct CategoryBar: View {
  @Binding var cat: String; let cats: [String]
  @Namespace var ns
  var body: some View {
    HStack(spacing: 6) {
      ForEach(Array(cats.enumerated()), id: \.offset) { i, c in
        let on = c == cat
        Button { Hap(1); withAnimation(T.snappy) { cat = c } } label: {
          HStack(spacing: 6) {
            if i > 0, let sil = SilImage(i) { Image(uiImage: sil).renderingMode(.template).resizable().scaledToFit().frame(height: 16) }
            Text(c.uppercased()).font(DF(15)).kerning(0.6)
          }
          .foregroundStyle(on ? T.bg : T.ink.opacity(0.7)).frame(maxWidth: .infinity).frame(height: 42)
          .background { if on { Capsule().fill(T.ink).matchedGeometryEffect(id: "cat", in: ns) } else { Capsule().fill(T.soft) } }
        }.buttonStyle(Pressable())
      }
    }
  }
  func SilImage(_ k: Int) -> UIImage? { BundleImg(["", "sil_tee.png", "sil_hoodie.png", "sil_pants.png"][k]) }
}

struct NextDropBanner: View {
  @EnvironmentObject var store: LDStore
  var body: some View {
    let _ = store.rev
    if let d = NextDrop() {
      TimelineView(.periodic(from: .now, by: 1)) { ctx in
        VStack(alignment: .leading, spacing: 12) {
          HStack { Caps("Next drop", 10, .white.opacity(0.75)); Spacer(); BellButton(drop: d, dark: true) }
          Text(d.nick.uppercased()).font(DF(40)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.5)
          HStack(spacing: 8) {
            ForEach(Array(CountdownParts(d.date, now: ctx.date).enumerated()), id: \.offset) { _, p in
              VStack(spacing: 2) {
                Text(p.0).font(DF(30)).foregroundStyle(.white).monospacedDigit().contentTransition(.numericText(countsDown: true))
                Caps(p.1, 8, .white.opacity(0.65))
              }.frame(maxWidth: .infinity).padding(.vertical, 10).background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
          }.animation(.default, value: ctx.date)
          Caps(DateLong(d.date), 9, .white.opacity(0.7))
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [T.red, T.red.opacity(0.78)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
      }
    } else {
      HStack { Image(systemName: "bolt.fill"); Caps("Every drop is live — shop it all", 10.5, .white) }.foregroundStyle(.white)
        .frame(maxWidth: .infinity).padding(18).background(T.red, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
  }
}

struct BellButton: View {
  let drop: Drop; var dark = false
  @EnvironmentObject var store: LDStore
  var body: some View {
    let on = { let _ = store.rev; return RemDrop(drop) }()
    Button { ToggleRemDrop(drop) } label: {
      HStack(spacing: 6) { Image(systemName: on ? "bell.fill" : "bell").contentTransition(.symbolEffect(.replace)); Text(on ? "ON" : "REMIND").font(.system(size: 10, weight: .heavy)).kerning(1.2) }
        .font(.system(size: 13, weight: .bold)).foregroundStyle(dark ? (on ? T.red : .white) : (on ? .white : T.ink))
        .padding(.horizontal, 12).frame(height: 32)
        .background(dark ? AnyShapeStyle(on ? Color.white : Color.white.opacity(0.18)) : AnyShapeStyle(on ? T.red : T.soft), in: Capsule())
    }.buttonStyle(Pressable())
  }
}

struct ProductCard: View {
  let item: Item
  @EnvironmentObject var store: LDStore
  var body: some View {
    let _ = store.rev
    VStack(alignment: .leading, spacing: 6) {
      ZStack(alignment: .topTrailing) {
        RoundedRectangle(cornerRadius: 24, style: .continuous).fill(T.tile)
        ProductImage(item: item).padding(16)
        HeartButton(iid: item.iid, size: 14).padding(8)
        if !IsLive(item) { VStack { Spacer(); HStack { Caps("Soon", 8.5, .white).padding(.horizontal, 8).padding(.vertical, 5).background(T.ink.opacity(0.8), in: Capsule()); Spacer() } }.padding(10) }
      }.aspectRatio(0.84, contentMode: .fit)
      HStack(alignment: .firstTextBaseline) {
        Text(item.code.uppercased()).font(DF(22)).foregroundStyle(T.ink).lineLimit(1).minimumScaleFactor(0.6)
        Spacer(minLength: 4)
        Text(Money(item.price)).font(DF(19)).foregroundStyle(T.red)
      }.padding(.horizontal, 4)
      Caps("\(SubLine(item)) · \(StatusLine(item))", 8.5).padding(.horizontal, 4)
    }.contentShape(Rectangle())
  }
}

// ---------- product viewer: swipe between pieces ----------
struct ProductViewer: View {
  let items: [Item]; let start: String
  @EnvironmentObject var store: LDStore
  @Environment(\.dismiss) var dismiss
  @State var sel = ""
  @State var drag: CGFloat = 0
  var body: some View {
    ZStack(alignment: .top) {
      T.bg.ignoresSafeArea()
      TabView(selection: $sel) {
        ForEach(items) { it in ProductPage(item: it).tag(it.iid) }
      }.tabViewStyle(.page(indexDisplayMode: .never))
      HStack {
        Button { dismiss() } label: { Image(systemName: "chevron.down").font(.system(size: 16, weight: .bold)).foregroundStyle(T.ink).frame(width: 44, height: 44).background(.ultraThinMaterial, in: Circle()) }.buttonStyle(Pressable())
        Spacer()
        if let i = items.firstIndex(where: { $0.iid == sel }) { Caps("\(Pad(i + 1)) / \(Pad(items.count))", 10.5, T.ink) }
        Spacer()
        HeartButton(iid: sel, size: 16)
      }.padding(.horizontal, 16).padding(.top, 6)
    }
    .offset(y: drag).simultaneousGesture(DragGesture().onChanged { v in if v.translation.height > 0 && abs(v.translation.height) > abs(v.translation.width) { drag = v.translation.height } }
      .onEnded { v in if v.translation.height > 140 || v.predictedEndTranslation.height > 400 { dismiss() } else { withAnimation(T.spring) { drag = 0 } } })
    .onAppear { sel = start }
    .onChange(of: sel) { _, _ in Hap(1) }
  }
}

struct ProductPage: View {
  let item: Item
  @EnvironmentObject var store: LDStore
  @State var size = gSize
  @State var zoom = false
  @State var added = false
  var body: some View {
    let _ = store.rev
    let live = IsLive(item), rem = RemItem(item), d = DropFor(item)
    VStack(spacing: 0) {
      ZStack {
        RoundedRectangle(cornerRadius: 34, style: .continuous).fill(T.tile)
        ProductImage(item: item, kind: "hires").padding(26).scaleEffect(zoom ? 1.6 : 1).animation(T.spring, value: zoom)
      }
      .padding(.horizontal, 12).padding(.top, 58)
      .onTapGesture(count: 2) { Hap(1); zoom.toggle() }
      VStack(alignment: .leading, spacing: 12) {
        HStack(alignment: .firstTextBaseline) {
          Text(item.code.uppercased()).font(DF(56)).foregroundStyle(T.ink).lineLimit(1).minimumScaleFactor(0.5)
          Spacer()
          Text(Money(item.price)).font(DF(40)).foregroundStyle(T.red)
        }
        Caps("\(SubLine(item)) · \(d.nick)", 10)
        Text(DescFor(item)).font(.system(size: 15, weight: .medium)).foregroundStyle(T.ink.opacity(0.8)).lineLimit(3).fixedSize(horizontal: false, vertical: true)
        if live {
          HStack(spacing: 8) {
            ForEach(["S", "M", "L", "XL"], id: \.self) { s in
              Button { Hap(1); withAnimation(T.snappy) { size = s } } label: {
                Text(s).font(DF(18)).foregroundStyle(size == s ? T.bg : T.ink).frame(maxWidth: .infinity).frame(height: 42)
                  .background(size == s ? T.ink : T.soft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
              }.buttonStyle(Pressable())
            }
          }
          CTA(title: added ? "Added to bag" : "Add to bag · \(size)", icon: added ? "checkmark" : "bag.badge.plus") {
            AddBag(item.iid, size); Hap(2); withAnimation(T.snappy) { added = true }
            after(1.4) { withAnimation(T.snappy) { added = false } }
          }
        } else {
          HStack(spacing: 6) { Image(systemName: "clock"); Caps("Drops \(DateLong(d.date))", 9.5, T.ink) }.foregroundStyle(T.ink)
          CTA(title: rem ? "Reminder set" : "Remind me", color: rem ? T.soft : T.red, fg: rem ? T.ink : .white, icon: rem ? "bell.fill" : "bell") { ToggleRemItem(item) }
        }
      }
      .padding(20).padding(.bottom, 8)
    }
  }
}

// ---------- drops ----------
struct DropsScreen: View {
  let open: ([Item], Item) -> Void
  @EnvironmentObject var store: LDStore
  var body: some View {
    let _ = store.rev
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        ScreenHeader(title: "The ", accent: "Drops").padding(.top, 10)
        Caps("Turn on a bell to get a heads-up an hour before, and when it's live", 9).padding(.horizontal, 20)
        ForEach(store.drops) { d in DropCard(drop: d, open: open).padding(.horizontal, 16) }
        if store.drops.isEmpty { Caps("No drops scheduled", 11).frame(maxWidth: .infinity).padding(40) }
      }.padding(.bottom, 110)
    }.scrollIndicators(.hidden).refreshable { SyncCatalog() }
  }
}

struct DropCard: View {
  let drop: Drop; let open: ([Item], Item) -> Void
  @EnvironmentObject var store: LDStore
  var body: some View {
    let its = store.items(in: drop), up = drop.date.timeIntervalSinceNow > 0
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 2) {
          Caps(up ? Fmt("EEEE · h:mm a", drop.date) : "Live now", 9.5, up ? T.mute : T.red)
          Text(up ? Fmt("MMM d", drop.date).uppercased() : "SHOP NOW").font(DF(54)).foregroundStyle(T.ink).lineLimit(1).minimumScaleFactor(0.5)
          Text(drop.nick.uppercased()).font(DF(20)).foregroundStyle(T.red)
        }
        Spacer()
        if up { BellButton(drop: drop) }
      }
      if up {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
          HStack(spacing: 4) {
            ForEach(Array(CountdownParts(drop.date, now: ctx.date).enumerated()), id: \.offset) { i, p in
              Text(p.0).font(DF(18)).monospacedDigit().foregroundStyle(T.ink).contentTransition(.numericText(countsDown: true))
              Caps(p.1, 7.5); if i < 3 { Spacer(minLength: 2) }
            }
          }.animation(.default, value: ctx.date)
        }
      }
      if its.isEmpty { Caps("No pieces assigned yet", 9.5) }
      else {
        ScrollView(.horizontal) {
          HStack(spacing: 10) {
            ForEach(its) { it in
              VStack(spacing: 6) {
                ProductImage(item: it, kind: "thumb").frame(width: 86, height: 92).padding(8).background(T.tile, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                  .overlay(alignment: .topTrailing) { if RemItem(it) { Image(systemName: "bell.fill").font(.system(size: 9)).foregroundStyle(.white).padding(5).background(T.red, in: Circle()).padding(5) } }
                Text(it.code.uppercased()).font(DF(14)).foregroundStyle(T.ink)
              }.onTapGesture { open(its, it) }
            }
          }
        }.scrollIndicators(.hidden)
      }
    }
    .padding(18).background(T.card, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
  }
}

// ---------- saved ----------
struct SavedScreen: View {
  let open: ([Item], Item) -> Void; let goShop: () -> Void
  @EnvironmentObject var store: LDStore
  var body: some View {
    let _ = store.rev
    let its = store.saved
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        ScreenHeader(title: "Saved ", accent: Pad(its.count)).padding(.top, 10)
        if its.isEmpty {
          EmptyState(icon: "heart", title: "Nothing saved yet", line: "Tap the heart on any piece to keep it here.", button: "Browse the shop", action: goShop)
        } else {
          LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 18) {
            ForEach(its) { it in ProductCard(item: it).onTapGesture { open(its, it) }.transition(.scale.combined(with: .opacity)) }
          }.padding(.horizontal, 16).animation(T.spring, value: its.map(\.iid))
        }
      }.padding(.bottom, 110)
    }.scrollIndicators(.hidden)
  }
}

struct EmptyState: View {
  let icon: String, title: String, line: String; var button: String? = nil; var action: (() -> Void)? = nil
  var body: some View {
    VStack(spacing: 12) {
      Image(systemName: icon).font(.system(size: 40, weight: .light)).foregroundStyle(T.red).frame(width: 96, height: 96).background(T.soft, in: Circle())
      Text(title.uppercased()).font(DF(28)).foregroundStyle(T.ink)
      Text(line).font(.system(size: 15, weight: .medium)).foregroundStyle(T.mute).multilineTextAlignment(.center)
      if let b = button, let a = action { CTA(title: b, action: a).frame(maxWidth: 260).padding(.top, 6) }
    }.frame(maxWidth: .infinity).padding(.vertical, 50).padding(.horizontal, 30)
  }
}

// ---------- bag ----------
struct BagScreen: View {
  let goShop: () -> Void
  @EnvironmentObject var store: LDStore
  @State var checkout = false
  var body: some View {
    let _ = store.rev
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        ScreenHeader(title: "Your ", accent: "Bag").padding(.top, 10)
        if gBag.isEmpty {
          EmptyState(icon: "bag", title: "Your bag is empty", line: "Pieces you add will wait here.", button: "Start shopping", action: goShop)
        } else {
          VStack(spacing: 10) {
            ForEach(Array(gBag.enumerated()), id: \.element.key) { k, line in
              if let it = ItemById(line.id) { BagRow(item: it, line: line, index: k) }
            }
          }.padding(.horizontal, 16)
          Card {
            VStack(spacing: 12) {
              row("Pieces", "\(BagCount())"); row("Subtotal", Money(BagTotal()))
              Rectangle().fill(T.line).frame(height: 0.5)
              HStack(alignment: .firstTextBaseline) { Caps("Total", 11, T.ink); Spacer(); Text(Money(BagTotal())).font(DF(40)).foregroundStyle(T.ink).contentTransition(.numericText()) }
              CTA(title: "Checkout", icon: "lock.fill") { Hap(2); checkout = true }
            }
          }.padding(.horizontal, 16)
        }
      }.padding(.bottom, 110).animation(T.spring, value: gBag.map { "\($0.id)\($0.size)\($0.q)" })
    }.scrollIndicators(.hidden)
    .alert("Checkout connects next", isPresented: $checkout) { Button("OK", role: .cancel) {} } message: { Text("Your bag is saved on this device until checkout is live.") }
  }
  func row(_ a: String, _ b: String) -> some View { HStack { Caps(a, 10); Spacer(); Text(b).font(.system(size: 15, weight: .semibold)).foregroundStyle(T.ink) } }
}
extension BagLine { var key: String { "\(id)|\(size)" } }

struct BagRow: View {
  let item: Item; let line: BagLine; let index: Int
  var body: some View {
    HStack(spacing: 14) {
      ProductImage(item: item, kind: "thumb").frame(width: 72, height: 76).padding(6).background(T.tile, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
      VStack(alignment: .leading, spacing: 4) {
        Text(item.code.uppercased()).font(DF(24)).foregroundStyle(T.ink)
        Caps("\(Kind(item)) · Size \(line.size)", 9)
        HStack(spacing: 0) {
          stepBtn("minus") { BagQty(index, -1) }
          Text("\(line.q)").font(DF(18)).foregroundStyle(T.ink).frame(width: 30).contentTransition(.numericText())
          stepBtn("plus") { BagQty(index, 1) }
        }.background(T.soft, in: Capsule())
      }
      Spacer()
      Text(Money(item.price * line.q)).font(DF(24)).foregroundStyle(T.ink).contentTransition(.numericText())
    }
    .padding(12).background(T.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
  }
  func stepBtn(_ s: String, _ a: @escaping () -> Void) -> some View {
    Button { Hap(1); withAnimation(T.snappy) { a() } } label: { Image(systemName: s).font(.system(size: 12, weight: .bold)).foregroundStyle(T.ink).frame(width: 34, height: 32) }.buttonStyle(Pressable())
  }
}

// ---------- you ----------
struct YouScreen: View {
  @EnvironmentObject var store: LDStore
  @State var auth = false
  @State var confirmOut = false
  @State var taps = 0
  var body: some View {
    let _ = store.rev
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        HStack(spacing: 14) {
          let nm = gUser?["name"] ?? "", src = nm.isEmpty ? (gUser?["email"] ?? "") : nm
          Text(gUser != nil && !src.isEmpty ? String(src.prefix(1)).uppercased() : "L").font(DF(34)).foregroundStyle(T.bg).frame(width: 64, height: 64).background(T.ink, in: Circle())
            .overlay(alignment: .bottomTrailing) { Circle().fill(T.red).frame(width: 12, height: 12) }
          VStack(alignment: .leading, spacing: 2) {
            Text((gUser != nil && !nm.isEmpty ? (nm.components(separatedBy: " ").first ?? nm) : "You").uppercased()).font(DF(44)).foregroundStyle(T.ink).lineLimit(1).minimumScaleFactor(0.5)
            Caps(gUser?["email"] ?? "Guest · L'Art de la Vie", 9.5)
          }
        }.padding(.horizontal, 20).padding(.top, 14)
        Card {
          if gUser != nil {
            HStack { Label("Signed in", systemImage: "checkmark.seal.fill").font(.system(size: 15, weight: .semibold)).foregroundStyle(T.ink); Spacer()
              Button("Sign out") { Hap(1); confirmOut = true }.font(.system(size: 14, weight: .bold)).foregroundStyle(T.red) }
          } else {
            VStack(alignment: .leading, spacing: 10) {
              Text("Save your bag, reminders and favorites to your account.").font(.system(size: 15, weight: .medium)).foregroundStyle(T.ink)
              CTA(title: "Sign in or create account", icon: "person.crop.circle") { auth = true }
            }
          }
        }.padding(.horizontal, 16)
        Card {
          VStack(alignment: .leading, spacing: 16) {
            Toggle(isOn: Binding(get: { gAlerts }, set: { gAlerts = $0; ScheduleAll(); Hap(1); Changed() })) {
              Label("Drop alerts", systemImage: gAlerts ? "bell.fill" : "bell.slash").font(.system(size: 15, weight: .semibold)).foregroundStyle(T.ink)
            }.tint(T.red)
            VStack(alignment: .leading, spacing: 8) {
              Caps("Appearance", 9)
              Segmented(options: [("auto", "circle.lefthalf.filled", "Auto"), ("light", "sun.max.fill", "Light"), ("dark", "moon.fill", "Dark")], sel: gTheme) { gTheme = $0; Changed() }
            }
            VStack(alignment: .leading, spacing: 8) {
              Caps("My size", 9)
              Segmented(options: ["S", "M", "L", "XL"].map { ($0, "", $0) }, sel: gSize) { gSize = $0; Changed() }
            }
          }
        }.padding(.horizontal, 16)
        Card {
          VStack(alignment: .leading, spacing: 10) {
            Caps("App icon", 9)
            HStack(spacing: 16) {
              ForEach(Array([("", "icon-192.png", "Dark"), ("White", "icon-white-192.png", "White")].enumerated()), id: \.offset) { _, d in
                let on = gIcon == d.0
                Button { setIcon(d.0) } label: {
                  VStack(spacing: 6) {
                    if let ui = BundleImg(d.1) { Image(uiImage: ui).resizable().frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                      .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(on ? T.red : .clear, lineWidth: 3)) }
                    Caps(d.2, 8.5, on ? T.ink : T.mute)
                  }.opacity(on ? 1 : 0.55)
                }.buttonStyle(Pressable())
              }
            }
          }
        }.padding(.horizontal, 16)
        Caps("\(gBrandName) USA · Version 5.0 New · © 2026", 9).frame(maxWidth: .infinity).padding(.top, 8)
          .onTapGesture { taps += 1; if taps >= 5 { taps = 0; NoteSchedule("test", "LONDiA test", "Notifications work. Lock your phone to see it.", 10); Hap(2) } }
      }.padding(.bottom, 110)
    }.scrollIndicators(.hidden)
    .sheet(isPresented: $auth) { AuthSheet().environmentObject(store).presentationDetents([.large]).presentationCornerRadius(34) }
    .confirmationDialog("Sign out of \(gBrandName)?", isPresented: $confirmOut, titleVisibility: .visible) { Button("Sign out", role: .destructive) { Hap(2); SignOut() } }
  }
  func setIcon(_ n: String) {
    if n == gIcon { return }; gIcon = n; Hap(2); gSeason = ""
    if UIApplication.shared.supportsAlternateIcons { UIApplication.shared.setAlternateIconName(n.isEmpty ? nil : n + "2") { _ in } }
    Changed()
  }
}

struct Segmented: View {
  let options: [(String, String, String)]; let sel: String; let set: (String) -> Void
  @Namespace var ns
  var body: some View {
    HStack(spacing: 4) {
      ForEach(Array(options.enumerated()), id: \.offset) { _, o in
        let on = o.0 == sel
        Button { Hap(1); withAnimation(T.snappy) { set(o.0) } } label: {
          HStack(spacing: 6) { if !o.1.isEmpty { Image(systemName: o.1).font(.system(size: 13, weight: .semibold)) }; Text(o.2.uppercased()).font(DF(14)).kerning(0.5) }
            .foregroundStyle(on ? T.bg : T.ink.opacity(0.7)).frame(maxWidth: .infinity).frame(height: 38)
            .background { if on { Capsule().fill(T.ink).matchedGeometryEffect(id: "seg", in: ns) } }
        }.buttonStyle(.plain)
      }
    }.padding(4).background(T.soft, in: Capsule())
  }
}

// ---------- auth ----------
struct AuthSheet: View {
  @Environment(\.dismiss) var dismiss
  @State var signup = false
  @State var name = ""; @State var email = ""; @State var pw = ""
  @State var err = ""; @State var info = ""; @State var busy = false; @State var showPw = false
  @FocusState var focus: Int?
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        Capsule().fill(T.line).frame(width: 40, height: 5).frame(maxWidth: .infinity).padding(.top, 10)
        Text(signup ? "CREATE\nACCOUNT" : "WELCOME\nBACK").font(DF(60)).foregroundStyle(T.ink).lineSpacing(-12).padding(.top, 14)
        Caps("L'Art de la Vie · \(gBrandName)", 9.5).padding(.bottom, 8)
        if signup { field("Name", $name, 0).textContentType(.name).textInputAutocapitalization(.words).transition(.move(edge: .top).combined(with: .opacity)) }
        field("Email", $email, 1).keyboardType(.emailAddress).textContentType(.emailAddress).textInputAutocapitalization(.never)
        HStack {
          Group { if showPw { TextField("Password (6+ characters)", text: $pw) } else { SecureField("Password (6+ characters)", text: $pw) } }.focused($focus, equals: 2).submitLabel(.go).onSubmit(submit)
          Button { showPw.toggle(); Hap(1) } label: { Image(systemName: showPw ? "eye" : "eye.slash").foregroundStyle(T.mute) }
        }.font(.system(size: 16, weight: .semibold)).padding(.horizontal, 16).frame(height: 54).background(T.soft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        if !signup { Button("Forgot password?") { forgot() }.font(.system(size: 12, weight: .heavy)).foregroundStyle(T.mute) }
        if !err.isEmpty { Text(err).font(.system(size: 13, weight: .semibold)).foregroundStyle(T.red) }
        if !info.isEmpty { Text(info).font(.system(size: 13, weight: .semibold)).foregroundStyle(T.ink) }
        CTA(title: busy ? "Please wait…" : (signup ? "Create account" : "Sign in"), action: submit).opacity(busy ? 0.5 : 1).disabled(busy).padding(.top, 6)
        Button { Hap(1); withAnimation(T.spring) { signup.toggle(); err = "" } } label: {
          Text(signup ? "Have an account? Sign in" : "New here? Create an account").font(.system(size: 12, weight: .heavy)).foregroundStyle(T.red).frame(maxWidth: .infinity).frame(height: 44)
        }
      }.padding(.horizontal, 22)
    }.scrollDismissesKeyboard(.interactively).background(T.bg.ignoresSafeArea())
  }
  func field(_ ph: String, _ b: Binding<String>, _ i: Int) -> some View {
    TextField(ph, text: b).focused($focus, equals: i).submitLabel(.next).onSubmit { focus = i + 1 }.autocorrectionDisabled()
      .font(.system(size: 16, weight: .semibold)).padding(.horizontal, 16).frame(height: 54).background(T.soft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
  }
  func fail(_ m: String) { err = m; info = ""; busy = false; Hap(2) }
  func forgot() {
    let e = email.trimmingCharacters(in: .whitespaces).lowercased()
    guard e.contains("@") && e.contains(".") else { fail("Enter your email above first."); return }
    err = ""; info = "Sending reset link…"; Hap(1)
    FBSendPasswordReset(e) { r in if let r = r { fail(r) } else { info = "Check your email for a reset link."; Hap(2) } }
  }
  func submit() {
    if busy { return }
    let n = name.trimmingCharacters(in: .whitespaces), e = email.trimmingCharacters(in: .whitespaces).lowercased(), up = signup
    if up && n.isEmpty { fail("Add your name."); return }
    if !e.contains("@") || !e.contains(".") { fail("Enter a valid email."); return }
    if pw.count < 6 { fail("Password needs 6+ characters."); return }
    err = ""; busy = true
    let handle: (JSON?, String?) -> Void = { json, er in
      if let er = er { fail(er); return }; guard let j = json else { fail("Something went wrong. Try again."); return }
      let (idT, uid) = StoreAuth(j)
      let finish: (String?) -> Void = { nm in gUser = ["name": nm ?? "", "email": e, "uid": uid]; Changed(); Hap(2); dismiss() }
      if up && !n.isEmpty { FBSetDisplayName(idT, n); FBSendVerifyEmail(idT); finish(n) } else { FBLookupName(idT) { finish($0) } }
    }
    if up { FBSignUp(e, pw, handle) } else { FBSignIn(e, pw, handle) }
  }
}

// ---------- splash + launch flash ----------
struct SplashScreen: View {
  let done: () -> Void
  @State var drag: CGFloat = 0; @State var hint = false
  var body: some View {
    ZStack {
      T.red.ignoresSafeArea()
      WhiteWordmark()
      VStack(spacing: 8) {
        Spacer()
        Image(systemName: "chevron.up").font(.system(size: 20, weight: .semibold)).offset(y: hint ? -8 : 0).opacity(hint ? 0.5 : 1)
        Caps("Swipe up to discover", 10, .white)
      }.foregroundStyle(.white).padding(.bottom, 40)
    }
    .offset(y: min(0, drag))
    .gesture(DragGesture().onChanged { drag = $0.translation.height }.onEnded { v in
      if v.translation.height < -120 || v.predictedEndTranslation.height < -400 { Hap(2); UD.set(true, forKey: "ld_welcomed"); Stamp(); done() }
      else { withAnimation(T.spring) { drag = 0 } } })
    .onTapGesture { withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) { drag = -34 }; after(0.2) { withAnimation(T.spring) { drag = 0 } } }
    .onAppear { withAnimation(.easeInOut(duration: 0.9).repeatForever().delay(1.2)) { hint = true } }
  }
}
struct RedFlash: View {
  let done: () -> Void
  @State var out = false
  var body: some View {
    ZStack { T.red.ignoresSafeArea(); WhiteWordmark().scaleEffect(out ? 1.06 : 1) }
      .opacity(out ? 0 : 1).allowsHitTesting(!out)
      .onAppear { withAnimation(.easeInOut(duration: 0.35).delay(0.45)) { out = true }; after(0.85) { done() } }
  }
}
