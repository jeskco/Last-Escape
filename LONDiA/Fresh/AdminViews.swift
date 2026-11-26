// ===== LONDiA Admin New: catalog editor (SwiftUI redesign) =====
import SwiftUI
import PhotosUI

struct AdminGate: View {
  @EnvironmentObject var store: LDStore
  @Environment(\.scenePhase) var phase
  var body: some View {
    let _ = store.rev
    Group { if gUser == nil { AdminSignIn() } else { AdminRoot() } }
      .animation(T.spring, value: gUser == nil)
      .onChange(of: phase) { _, p in
        if p == .active {
          // no settings screen in admin, so coming back after 10+ minutes away signs out
          let last = UD.double(forKey: "ld_last"); if gUser != nil && last > 0 && Date().timeIntervalSince1970 - last > 600 { SignOut() }
          Stamp(); SyncCatalog()
        } else if p == .background { Stamp() }
      }
  }
}

struct AdminSignIn: View {
  @State var signup = false; @State var email = ""; @State var pw = ""; @State var err = ""; @State var busy = false
  var body: some View {
    ZStack {
      T.bg.ignoresSafeArea()
      VStack(alignment: .leading, spacing: 12) {
        Spacer()
        Wordmark(width: 190)
        Text("ADMIN").font(DF(64)).foregroundStyle(T.red)
        Caps("Manage products, photos and drops", 9.5).padding(.bottom, 14)
        TextField("Email", text: $email).keyboardType(.emailAddress).textContentType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled().modifier(FieldStyle())
        SecureField("Password (6+ characters)", text: $pw).textContentType(.password).modifier(FieldStyle()).onSubmit(submit)
        if !err.isEmpty { Text(err).font(.system(size: 13, weight: .semibold)).foregroundStyle(T.red) }
        CTA(title: busy ? "Please wait…" : (signup ? "Create admin account" : "Sign in"), action: submit).opacity(busy ? 0.5 : 1).disabled(busy)
        Button { Hap(1); signup.toggle(); err = "" } label: {
          Text(signup ? "Already have it? Sign in" : "First time? Create the account").font(.system(size: 12, weight: .heavy)).foregroundStyle(T.red).frame(maxWidth: .infinity).frame(height: 44)
        }
        Spacer(); Spacer()
      }.padding(.horizontal, 24)
    }
  }
  func submit() {
    if busy { return }
    let e = email.trimmingCharacters(in: .whitespaces).lowercased()
    guard e.contains("@") else { err = "Enter a valid email."; Hap(2); return }
    guard pw.count >= 6 else { err = "Password needs 6+ characters."; Hap(2); return }
    err = ""; busy = true
    let h: (JSON?, String?) -> Void = { j, er in
      busy = false; if let er = er { err = er; Hap(2); return }; guard let j = j else { return }
      let (_, uid) = StoreAuth(j); gUser = ["name": "Admin", "email": e, "uid": uid]; Hap(2); Changed()
    }
    if signup { FBSignUp(e, pw, h) } else { FBSignIn(e, pw, h) }
  }
}
struct FieldStyle: ViewModifier {
  func body(content: Content) -> some View {
    content.font(.system(size: 16, weight: .semibold)).padding(.horizontal, 16).frame(height: 54).background(T.soft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
  }
}

enum AdminTab { case products, drops }
struct AdminRoot: View {
  @EnvironmentObject var store: LDStore
  @State var tab: AdminTab = .products
  @State var confirmOut = false
  @Namespace var ns
  var body: some View {
    let _ = store.rev
    ZStack(alignment: .bottom) {
      T.bg.ignoresSafeArea()
      VStack(spacing: 0) {
        HStack {
          Wordmark(width: 110); Caps("Admin", 10, T.red); Spacer()
          Button { confirmOut = true } label: { Image(systemName: "rectangle.portrait.and.arrow.right").font(.system(size: 15, weight: .semibold)).foregroundStyle(T.ink).frame(width: 40, height: 40).background(T.soft, in: Circle()) }
        }.padding(.horizontal, 20).padding(.vertical, 8)
        Group { if tab == .products { AdminProducts() } else { AdminDrops() } }.transition(.opacity)
      }
      HStack(spacing: 0) {
        tabBtn(.products, "Products", "square.grid.2x2"); tabBtn(.drops, "Drops", "calendar")
      }.padding(5).background(.ultraThinMaterial, in: Capsule()).overlay(Capsule().stroke(T.line, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.12), radius: 18, y: 8).padding(.horizontal, 60).padding(.bottom, 4)
    }
    .confirmationDialog("Sign out of admin?", isPresented: $confirmOut, titleVisibility: .visible) { Button("Sign out", role: .destructive) { SignOut() } }
  }
  func tabBtn(_ t: AdminTab, _ title: String, _ icon: String) -> some View {
    let on = t == tab
    return Button { if !on { Hap(1) }; withAnimation(T.snappy) { tab = t } } label: {
      HStack(spacing: 6) { Image(systemName: icon).font(.system(size: 15, weight: .semibold)); Text(title.uppercased()).font(DF(13)).kerning(1) }
        .foregroundStyle(on ? Color.white : T.ink.opacity(0.6)).frame(maxWidth: .infinity).frame(height: 48)
        .background { if on { Capsule().fill(T.red).matchedGeometryEffect(id: "atab", in: ns) } }
    }.buttonStyle(.plain)
  }
}

// ---------- products ----------
struct EditTarget: Identifiable { let id = UUID(); let item: Item; let isNew: Bool }
struct AdminProducts: View {
  @EnvironmentObject var store: LDStore
  @State var edit: EditTarget?
  @State var query = ""
  @State var cat = "All"
  var list: [Item] {
    store.items.filter { (cat == "All" || $0.cat == cat) && (query.isEmpty || $0.code.localizedCaseInsensitiveContains(query) || $0.name.localizedCaseInsensitiveContains(query)) }
  }
  var body: some View {
    let _ = store.rev
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        HStack(alignment: .lastTextBaseline) {
          (Text("PRODUCTS ").foregroundStyle(T.ink) + Text(Pad(store.items.count)).foregroundStyle(T.red)).font(DF(40)); Spacer()
          Button { newItem() } label: { Label("Add", systemImage: "plus").font(.system(size: 14, weight: .heavy)).foregroundStyle(.white).padding(.horizontal, 16).frame(height: 40).background(T.red, in: Capsule()) }.buttonStyle(Pressable())
        }.padding(.horizontal, 20)
        HStack { Image(systemName: "magnifyingglass").foregroundStyle(T.mute); TextField("Search code or name", text: $query).autocorrectionDisabled().textInputAutocapitalization(.never) }
          .font(.system(size: 15, weight: .semibold)).padding(.horizontal, 14).frame(height: 44).background(T.soft, in: Capsule()).padding(.horizontal, 16)
        CategoryBar(cat: $cat, cats: ["All", "Tees", "Hoodies", "Pants"]).padding(.horizontal, 16)
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 16) {
          ForEach(list) { it in
            AdminProductCard(item: it).onTapGesture { Hap(1); edit = EditTarget(item: it, isNew: false) }
          }
        }.padding(.horizontal, 16).animation(T.spring, value: list.map(\.iid))
        if list.isEmpty { EmptyState(icon: "tshirt", title: "No products", line: "Tap Add to create your first piece.") }
      }.padding(.bottom, 100)
    }.scrollIndicators(.hidden).refreshable { SyncCatalog() }
    .sheet(item: $edit) { t in ProductEditor(item: t.item, isNew: t.isNew).environmentObject(store).presentationCornerRadius(34) }
  }
  func newItem() {
    Hap(1); let it = Item(); it.iid = "item-\(Int(Date().timeIntervalSince1970))"; it.code = ""; it.cat = "Tees"; it.desc = ""; it.drop = gDrops.first?.did ?? ""
    edit = EditTarget(item: it, isNew: true)
  }
}

struct AdminProductCard: View {
  let item: Item
  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      ZStack(alignment: .topLeading) {
        RoundedRectangle(cornerRadius: 22, style: .continuous).fill(T.tile)
        ProductImage(item: item).padding(14)
        Caps(DropFor(item).nick, 8, .white).padding(.horizontal, 8).padding(.vertical, 5).background(IsLive(item) ? T.red : T.ink.opacity(0.75), in: Capsule()).padding(10)
      }.aspectRatio(0.9, contentMode: .fit)
      HStack {
        Text((item.code.isEmpty ? "—" : item.code).uppercased()).font(DF(20)).foregroundStyle(T.ink)
        Spacer(); Text(Money(item.price)).font(DF(18)).foregroundStyle(T.red)
      }.padding(.horizontal, 4)
      HStack(spacing: 4) { Image(systemName: "pencil").font(.system(size: 9, weight: .bold)); Caps("Tap to edit", 8) }.foregroundStyle(T.mute).padding(.horizontal, 4)
    }.contentShape(Rectangle())
  }
}

struct ProductEditor: View {
  let item: Item; let isNew: Bool
  @Environment(\.dismiss) var dismiss
  @State var code = ""; @State var color = ""; @State var price = ""; @State var desc = ""; @State var cat = "Tees"; @State var drop = ""
  @State var pick: PhotosPickerItem?
  @State var picked: UIImage?
  @State var removePhoto = false
  @State var status = ""; @State var statusErr = false; @State var busy = false; @State var confirmDelete = false
  let cats = ["Tees", "Hoodies", "Pants"]
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          PhotosPicker(selection: $pick, matching: .images) {
            ZStack {
              RoundedRectangle(cornerRadius: 28, style: .continuous).fill(T.tile)
              if let p = picked { Image(uiImage: p).resizable().scaledToFit().padding(18) }
              else if !removePhoto, let ui = TrimImg(Img(item.iid, "med")) { Image(uiImage: ui).resizable().scaledToFit().padding(18) }
              else { VStack(spacing: 8) { Image(systemName: "photo.badge.plus").font(.system(size: 34)); Caps("Add a photo", 9.5) }.foregroundStyle(T.mute) }
              VStack { Spacer(); HStack { Spacer(); Label("Change photo", systemImage: "camera.fill").font(.system(size: 12, weight: .heavy)).foregroundStyle(.white).padding(.horizontal, 12).frame(height: 32).background(T.ink.opacity(0.8), in: Capsule()) } }.padding(12)
            }.frame(height: 300)
          }
          if picked != nil || (!(item.imgURL ?? "").isEmpty && !removePhoto) {
            Button { Hap(1); picked = nil; pick = nil; removePhoto = true } label: { Caps("Remove custom photo (use default)", 9, T.red) }
          }
          section("Code") { TextField("HD-06", text: $code).textInputAutocapitalization(.characters).autocorrectionDisabled().modifier(FieldStyle()) }
          section("Category") { Segmented(options: cats.map { ($0, "", $0) }, sel: cat) { cat = $0 } }
          HStack(spacing: 12) {
            section("Price (USD)") { TextField("95", text: $price).keyboardType(.numberPad).modifier(FieldStyle()) }
            section("Color") { TextField("black", text: $color).textInputAutocapitalization(.never).modifier(FieldStyle()) }
          }
          section("Drop") {
            if gDrops.isEmpty { Caps("No drops yet — add one in the Drops tab", 9) }
            else {
              ScrollView(.horizontal) {
                HStack(spacing: 8) {
                  ForEach(gDrops) { d in
                    let on = d.did == drop
                    Button { Hap(1); drop = d.did; if let c = CatForDropName(d.nick) { cat = c } } label: {
                      Text((d.nick.isEmpty ? d.name : d.nick).uppercased()).font(DF(15)).foregroundStyle(on ? .white : T.ink).padding(.horizontal, 16).frame(height: 40).background(on ? T.red : T.soft, in: Capsule())
                    }.buttonStyle(Pressable())
                  }
                }
              }.scrollIndicators(.hidden)
            }
          }
          section("Description (blank uses the category default)") {
            TextEditor(text: $desc).font(.system(size: 15, weight: .medium)).scrollContentBackground(.hidden).frame(height: 100).padding(10).background(T.soft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
          }
          if !status.isEmpty { Text(status).font(.system(size: 13, weight: .semibold)).foregroundStyle(statusErr ? T.red : T.ink).frame(maxWidth: .infinity) }
          CTA(title: busy ? "Saving…" : "Save", icon: "checkmark", action: save).opacity(busy ? 0.5 : 1).disabled(busy)
          if !isNew { Button { confirmDelete = true } label: { Caps("Delete this product", 10.5, T.red).frame(maxWidth: .infinity).frame(height: 44) } }
        }.padding(20)
      }
      .scrollDismissesKeyboard(.interactively).background(T.bg.ignoresSafeArea())
      .navigationTitle(isNew ? "New product" : (item.code.isEmpty ? "Edit product" : item.code)).navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.tint(T.ink) } }
    }
    .onAppear {
      code = item.code; color = item.color; price = item.price > 0 ? "\(item.price)" : ""; desc = item.desc ?? ""; cat = cats.contains(item.cat) ? item.cat : "Tees"
      drop = item.drop.isEmpty ? (gDrops.first?.did ?? "") : item.drop
    }
    .onChange(of: pick) { _, p in
      guard let p = p else { return }
      Task { if let d = try? await p.loadTransferable(type: Data.self), let im = UIImage(data: d) { await MainActor.run { picked = im; removePhoto = false; Hap(2) } } else { await MainActor.run { setStatus("Couldn't load that photo — try a different one.", true) } } }
    }
    .alert("Delete this product?", isPresented: $confirmDelete) {
      Button("Delete", role: .destructive, action: delete); Button("Cancel", role: .cancel) {}
    } message: { Text("\(item.code.isEmpty ? "This item" : item.code) will be removed for everyone. This can't be undone.") }
  }
  func section<C: View>(_ t: String, @ViewBuilder _ c: () -> C) -> some View { VStack(alignment: .leading, spacing: 8) { Caps(t, 9.5); c() } }
  func setStatus(_ t: String, _ e: Bool) { status = t; statusErr = e; if e { Hap(2) } }
  func save() {
    let c = code.trimmingCharacters(in: .whitespaces).uppercased(); guard !c.isEmpty else { setStatus("Add a code (like HD-06).", true); return }
    let tok = Token(); guard !tok.isEmpty else { setStatus("You're signed out — sign in again.", true); return }
    busy = true; setStatus("", false)
    let p = Int(price) ?? 0, col = color.trimmingCharacters(in: .whitespaces), dr = drop.isEmpty ? "d1" : drop
    let finish: (String?) -> Void = { newURL in
      var f: JSON = ["code": c, "cat": cat, "color": col, "drop": dr, "price": p, "desc": desc]
      let finalImg: String? = removePhoto ? nil : ((newURL ?? "").isEmpty ? item.imgURL : newURL)
      if let fi = finalImg, !fi.isEmpty { f["img"] = fi }
      FSUpsertAuth("catalog_items", item.iid, f, tok) { ok in
        busy = false
        guard ok else { setStatus("Couldn't save. Check your internet and try again.", true); return }
        item.code = c; item.cat = cat; item.color = col; item.drop = dr; item.price = p; item.desc = desc; item.imgURL = finalImg
        if isNew && !gItems.contains(where: { $0 === item }) { gItems.append(item) }
        if let pk = picked, !(finalImg ?? "").isEmpty { StoreItemImageData(item, pk.pngData()) } else if removePhoto { ClearItemImageOverride(item) }
        setStatus("Saved.", false); Hap(2); Changed(); SyncCatalog(); after(0.45) { dismiss() }
      }
    }
    if let pk = picked { setStatus("Uploading photo…", false); CloudinaryUpload(pk) { url, e in if let e = e { busy = false; setStatus(e, true); return }; finish(url) } }
    else { finish(nil) }
  }
  func delete() {
    let tok = Token(); guard !tok.isEmpty else { setStatus("You're signed out — sign in again.", true); return }
    busy = true; setStatus("Deleting…", false)
    FSDeleteAuth("catalog_items", item.iid, tok) { ok in
      busy = false; guard ok else { setStatus("Couldn't delete. Check your internet and try again.", true); return }
      gItems.removeAll { $0 === item }; ClearItemImageOverride(item); Hap(2); Changed(); SyncCatalog(); after(0.3) { dismiss() }
    }
  }
}

// ---------- drops ----------
struct DropTarget: Identifiable { let id = UUID(); let drop: Drop; let isNew: Bool }
struct AdminDrops: View {
  @EnvironmentObject var store: LDStore
  @State var edit: DropTarget?
  @State var maxAlert = false
  var body: some View {
    let _ = store.rev
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        HStack(alignment: .lastTextBaseline) {
          (Text("DROPS ").foregroundStyle(T.ink) + Text(Pad(store.drops.count)).foregroundStyle(T.red)).font(DF(40)); Spacer()
          Button { add() } label: { Label("Add", systemImage: "plus").font(.system(size: 14, weight: .heavy)).foregroundStyle(.white).padding(.horizontal, 16).frame(height: 40).background(T.red, in: Capsule()) }.buttonStyle(Pressable())
        }.padding(.horizontal, 20)
        Caps("Up to 3 drops show in the store at once", 9).padding(.horizontal, 20)
        ForEach(store.drops) { d in
          let its = store.items(in: d), up = d.date.timeIntervalSinceNow > 0
          Button { Hap(1); edit = DropTarget(drop: d, isNew: false) } label: {
            VStack(alignment: .leading, spacing: 10) {
              HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                  Caps(up ? DateLong(d.date) : "Live now", 9, up ? T.mute : T.red)
                  Text((d.nick.isEmpty ? d.name : d.nick).uppercased()).font(DF(34)).foregroundStyle(T.ink).lineLimit(1).minimumScaleFactor(0.5)
                  Caps(d.name, 8.5)
                }
                Spacer(); Image(systemName: "pencil").font(.system(size: 14, weight: .bold)).foregroundStyle(T.ink).frame(width: 38, height: 38).background(T.soft, in: Circle())
              }
              if its.isEmpty { Caps("No pieces assigned yet", 9) }
              else {
                HStack(spacing: 8) {
                  ForEach(its.prefix(5)) { it in ProductImage(item: it, kind: "thumb").frame(width: 48, height: 52).padding(4).background(T.tile, in: RoundedRectangle(cornerRadius: 12, style: .continuous)) }
                  if its.count > 5 { Caps("+\(its.count - 5)", 10, T.ink) }
                }
              }
            }.padding(18).background(T.card, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
          }.buttonStyle(Pressable()).padding(.horizontal, 16)
        }
        if store.drops.isEmpty { EmptyState(icon: "calendar.badge.plus", title: "No drops", line: "Tap Add to schedule your first drop.") }
      }.padding(.bottom, 100)
    }.scrollIndicators(.hidden).refreshable { SyncCatalog() }
    .sheet(item: $edit) { t in DropEditor(drop: t.drop, isNew: t.isNew).environmentObject(store).presentationCornerRadius(34) }
    .alert("3 drop max", isPresented: $maxAlert) { Button("OK", role: .cancel) {} } message: { Text("The store shows up to 3 drops at once. Delete one first if you need to add another.") }
  }
  func add() {
    Hap(1); if gDrops.count >= 3 { maxAlert = true; return }
    let d = Drop(); d.did = "drop-\(Int(Date().timeIntervalSince1970))"; d.name = "New drop"; d.nick = "New drop"; d.date = Date().addingTimeInterval(86400 * 30)
    edit = DropTarget(drop: d, isNew: true)
  }
}

struct DropEditor: View {
  let drop: Drop; let isNew: Bool
  @Environment(\.dismiss) var dismiss
  @State var name = ""; @State var nick = ""; @State var customId = ""; @State var date = Date()
  @State var status = ""; @State var statusErr = false; @State var busy = false; @State var confirmDelete = false
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          section("Name") { TextField("Drop 01 · The Tees", text: $name).modifier(FieldStyle()) }
          section("Short name") { TextField("The Tees", text: $nick).modifier(FieldStyle()) }
          section("Drops on") {
            DatePicker("", selection: $date, displayedComponents: [.date, .hourAndMinute]).datePickerStyle(.graphical).tint(T.red)
              .padding(10).background(T.soft, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
          }
          if isNew { section("ID (advanced — only to restore a deleted drop with its items)") { TextField("leave blank for a new drop", text: $customId).textInputAutocapitalization(.never).autocorrectionDisabled().modifier(FieldStyle()) } }
          if !status.isEmpty { Text(status).font(.system(size: 13, weight: .semibold)).foregroundStyle(statusErr ? T.red : T.ink).frame(maxWidth: .infinity) }
          CTA(title: busy ? "Saving…" : "Save", icon: "checkmark", action: save).opacity(busy ? 0.5 : 1).disabled(busy)
          if !isNew { Button { confirmDelete = true } label: { Caps("Delete this drop", 10.5, T.red).frame(maxWidth: .infinity).frame(height: 44) } }
        }.padding(20)
      }
      .scrollDismissesKeyboard(.interactively).background(T.bg.ignoresSafeArea())
      .navigationTitle(isNew ? "New drop" : "Edit drop").navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.tint(T.ink) } }
    }
    .onAppear { name = drop.name; nick = drop.nick; date = drop.date }
    .alert("Delete this drop?", isPresented: $confirmDelete) {
      Button("Delete", role: .destructive, action: delete); Button("Cancel", role: .cancel) {}
    } message: {
      let n = gItems.filter { $0.drop == drop.did }.count
      Text(n > 0 ? "\(n) item\(n == 1 ? "" : "s") still use this drop and will need to be moved first. Delete anyway?" : "This can't be undone.")
    }
  }
  func section<C: View>(_ t: String, @ViewBuilder _ c: () -> C) -> some View { VStack(alignment: .leading, spacing: 8) { Caps(t, 9.5); c() } }
  func setStatus(_ t: String, _ e: Bool) { status = t; statusErr = e; if e { Hap(2) } }
  func save() {
    let n = name.trimmingCharacters(in: .whitespaces); guard !n.isEmpty else { setStatus("Add a name for this drop.", true); return }
    let k = nick.trimmingCharacters(in: .whitespaces), tok = Token(); guard !tok.isEmpty else { setStatus("You're signed out — sign in again.", true); return }
    let cid = customId.trimmingCharacters(in: .whitespaces); if isNew && !cid.isEmpty { drop.did = cid }
    busy = true
    FSUpsertAuth("catalog_drops", drop.did, ["name": n, "nick": k.isEmpty ? n : k, "date": ISOFromDate(date)], tok) { ok in
      busy = false; guard ok else { setStatus("Couldn't save. Check your internet and try again.", true); return }
      drop.name = n; drop.nick = k.isEmpty ? n : k; drop.date = date
      if isNew && !gDrops.contains(where: { $0 === drop }) { gDrops.append(drop) }
      setStatus("Saved.", false); Hap(2); ScheduleDrop(drop); Changed(); SyncCatalog(); after(0.45) { dismiss() }
    }
  }
  func delete() {
    let tok = Token(); guard !tok.isEmpty else { setStatus("You're signed out — sign in again.", true); return }
    busy = true; setStatus("Deleting…", false)
    FSDeleteAuth("catalog_drops", drop.did, tok) { ok in
      busy = false; guard ok else { setStatus("Couldn't delete. Check your internet and try again.", true); return }
      gDrops.removeAll { $0 === drop }; Hap(2); Changed(); SyncCatalog(); after(0.3) { dismiss() }
    }
  }
}
