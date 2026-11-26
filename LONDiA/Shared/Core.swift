// ===== LONDiA core (Swift): backend, data, state, theme, helpers =====
// Shared by every target: the classic UIKit storefront/admin and the redesigned SwiftUI ones.
// Uses the same Firebase project, keychain keys and UserDefaults keys as the Objective-C app,
// so installing over the old build keeps the bag, saved pieces, reminders and sign-in.
import UIKit
import UserNotifications
import Security

let kChange = Notification.Name("LDChanged")
var gSeason = ""

// ---------- brand + accent theme ----------
var gBrandName = "LONDiA"
var gAccent = "red"

// ---------- backend: Firebase config + tiny REST/keychain helpers ----------
let FB_API_KEY = "AIzaSyBNRfBZ8dQlBOnxDJ3IAAPADKh7Z7qsLSE"
let FB_PROJECT = "londia-app"
let FS_BASE = "https://firestore.googleapis.com/v1/projects/\(FB_PROJECT)/databases/(default)/documents"

typealias JSON = [String: Any]

func onMain(_ f: @escaping () -> Void) { DispatchQueue.main.async(execute: f) }
func after(_ s: Double, _ f: @escaping () -> Void) { DispatchQueue.main.asyncAfter(deadline: .now() + s, execute: f) }

func HttpPostJSON(_ urlStr: String, _ body: JSON?, _ cb: @escaping (JSON?, Int, Error?) -> Void) {
  guard let url = URL(string: urlStr) else { onMain { cb(nil, 0, nil) }; return }
  var req = URLRequest(url: url); req.httpMethod = "POST"; req.setValue("application/json", forHTTPHeaderField: "Content-Type")
  do { req.httpBody = try JSONSerialization.data(withJSONObject: body ?? [:]) } catch { onMain { cb(nil, 0, error) }; return }
  URLSession.shared.dataTask(with: req) { data, resp, err in
    let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
    let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? JSON }
    onMain { cb(json ?? nil, status, err) }
  }.resume()
}

func KSet(_ key: String, _ val: String?) {
  let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key, kSecAttrService as String: "LONDiA"]
  SecItemDelete(q as CFDictionary)
  if let v = val, !v.isEmpty {
    var add = q; add[kSecValueData as String] = Data(v.utf8); add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
    SecItemAdd(add as CFDictionary, nil)
  }
}
func KGet(_ key: String) -> String? {
  let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key, kSecAttrService as String: "LONDiA",
                          kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
  var result: CFTypeRef?
  guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let d = result as? Data else { return nil }
  return String(data: d, encoding: .utf8)
}
func Token() -> String { KGet("ld_idtoken") ?? "" }

// Firestore REST value decoding
func FSVal(_ v: JSON?) -> Any? {
  guard let v = v else { return nil }
  if let s = v["stringValue"] as? String { return s }
  if let s = v["timestampValue"] as? String { return s }
  if let s = v["integerValue"] { if let str = s as? String { return Int(str) ?? 0 }; if let n = s as? NSNumber { return n.intValue } }
  if let n = v["doubleValue"] as? NSNumber { return n.doubleValue }
  if let b = v["booleanValue"] as? NSNumber { return b.boolValue }
  return nil
}
func FSFields(_ doc: JSON) -> JSON {
  var o: JSON = [:]
  if let f = doc["fields"] as? [String: JSON] { for (k, v) in f { if let val = FSVal(v) { o[k] = val } } }
  return o
}
// tolerant readers for decoded documents
func S(_ v: Any?) -> String? { if let s = v as? String { return s }; if let n = v as? NSNumber { return n.stringValue }; return nil }
func I(_ v: Any?) -> Int? { if let i = v as? Int { return i }; if let d = v as? Double { return Int(d) }; if let n = v as? NSNumber { return n.intValue }; if let s = v as? String { return Int(s) }; return nil }
func B(_ v: Any?) -> Bool { if let b = v as? Bool { return b }; if let n = v as? NSNumber { return n.boolValue }; return false }

func FSList(_ collection: String, _ cb: @escaping ([JSON]) -> Void) {
  guard let url = URL(string: "\(FS_BASE)/\(collection)?key=\(FB_API_KEY)&pageSize=300") else { onMain { cb([]) }; return }
  URLSession.shared.dataTask(with: url) { data, _, _ in
    var out: [JSON] = []
    if let data = data, let j = (try? JSONSerialization.jsonObject(with: data)) as? JSON, let docs = j["documents"] as? [JSON] {
      for doc in docs {
        var f = FSFields(doc)
        if let name = doc["name"] as? String, let id = name.components(separatedBy: "/").last { f["__id"] = id }
        out.append(f)
      }
    }
    onMain { cb(out) }
  }.resume()
}
func FSEncode(_ plain: JSON) -> JSON {
  var f: JSON = [:]
  for (k, v) in plain {
    if let s = v as? String { f[k] = ["stringValue": s] }
    else if let b = v as? Bool { f[k] = ["booleanValue": b] }
    else if let i = v as? Int { f[k] = ["integerValue": String(i)] }
  }
  return ["fields": f]
}
// id tokens expire after ~1hr; this silently mints a fresh one from the stored refresh token (no re-login needed)
func FBRefreshToken(_ cb: @escaping (Bool) -> Void) {
  guard let ref = KGet("ld_reftoken"), !ref.isEmpty, let url = URL(string: "https://securetoken.googleapis.com/v1/token?key=\(FB_API_KEY)") else { onMain { cb(false) }; return }
  var r = URLRequest(url: url); r.httpMethod = "POST"; r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
  let enc = ref.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ref
  r.httpBody = "grant_type=refresh_token&refresh_token=\(enc)".data(using: .utf8)
  URLSession.shared.dataTask(with: r) { data, _, _ in
    let j = data.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? JSON }
    let newId = S(j?["id_token"]) ?? "", newRef = S(j?["refresh_token"]) ?? "", uid = S(j?["user_id"]) ?? ""
    onMain {
      if !newId.isEmpty { KSet("ld_idtoken", newId); if !newRef.isEmpty { KSet("ld_reftoken", newRef) }; if !uid.isEmpty { KSet("ld_uid", uid) }; cb(true) }
      else { cb(false) }
    }
  }.resume()
}
private func FSAuthRequest(_ method: String, _ collection: String, _ docId: String, _ body: JSON?, _ idToken: String, _ cb: @escaping (Int) -> Void) {
  let id = docId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? docId
  guard let url = URL(string: "\(FS_BASE)/\(collection)/\(id)?key=\(FB_API_KEY)") else { onMain { cb(0) }; return }
  var r = URLRequest(url: url); r.httpMethod = method
  if !idToken.isEmpty { r.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization") }
  if let body = body { r.setValue("application/json", forHTTPHeaderField: "Content-Type"); r.httpBody = try? JSONSerialization.data(withJSONObject: FSEncode(body)) }
  URLSession.shared.dataTask(with: r) { _, resp, _ in
    let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
    onMain { cb(code) }
  }.resume()
}
private func FSWithRetry(_ method: String, _ collection: String, _ docId: String, _ body: JSON?, _ idToken: String, _ cb: ((Bool) -> Void)?) {
  FSAuthRequest(method, collection, docId, body, idToken) { code in
    if (200..<300).contains(code) { cb?(true); return }
    if code == 401 || code == 403 {
      FBRefreshToken { ok in
        guard ok else { cb?(false); return }
        FSAuthRequest(method, collection, docId, body, Token()) { c2 in cb?((200..<300).contains(c2)) }
      }
      return
    }
    cb?(false)
  }
}
func FSUpsertAuth(_ collection: String, _ docId: String, _ plain: JSON, _ idToken: String, _ cb: ((Bool) -> Void)?) { FSWithRetry("PATCH", collection, docId, plain, idToken, cb) }
func FSDeleteAuth(_ collection: String, _ docId: String, _ idToken: String, _ cb: ((Bool) -> Void)?) { FSWithRetry("DELETE", collection, docId, nil, idToken, cb) }

private let isoF = ISO8601DateFormatter()
func ISOFromDate(_ d: Date) -> String { isoF.string(from: d) }
func DateFromISO(_ s: String?) -> Date {
  guard let s = s, !s.isEmpty else { return Date() }
  if let d = isoF.date(from: s) { return d }
  let f2 = ISO8601DateFormatter(); f2.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  return f2.date(from: s) ?? Date()
}
func FBErrMsg(_ json: JSON?, _ err: Error?) -> String {
  if err != nil { return "Couldn't connect. Check your internet and try again." }
  let code = S((json?["error"] as? JSON)?["message"]) ?? ""
  if code.hasPrefix("EMAIL_EXISTS") { return "That email already has an account." }
  if code.hasPrefix("EMAIL_NOT_FOUND") || code.hasPrefix("INVALID_PASSWORD") || code.hasPrefix("INVALID_LOGIN_CREDENTIALS") { return "Wrong email or password." }
  if code.hasPrefix("WEAK_PASSWORD") { return "Password needs 6+ characters." }
  if code.hasPrefix("TOO_MANY_ATTEMPTS_TRY_LATER") { return "Too many tries. Wait a bit and try again." }
  if code.hasPrefix("INVALID_EMAIL") { return "Enter a valid email." }
  return "Something went wrong. Try again."
}
private let idBase = "https://identitytoolkit.googleapis.com/v1/accounts"
func FBSignUp(_ email: String, _ pw: String, _ cb: @escaping (JSON?, String?) -> Void) {
  HttpPostJSON("\(idBase):signUp?key=\(FB_API_KEY)", ["email": email, "password": pw, "returnSecureToken": true]) { j, st, e in
    if st != 200 || e != nil { cb(nil, FBErrMsg(j, e)); return }; cb(j, nil) }
}
func FBSignIn(_ email: String, _ pw: String, _ cb: @escaping (JSON?, String?) -> Void) {
  HttpPostJSON("\(idBase):signInWithPassword?key=\(FB_API_KEY)", ["email": email, "password": pw, "returnSecureToken": true]) { j, st, e in
    if st != 200 || e != nil { cb(nil, FBErrMsg(j, e)); return }; cb(j, nil) }
}
func FBSetDisplayName(_ idToken: String, _ name: String) {
  HttpPostJSON("\(idBase):update?key=\(FB_API_KEY)", ["idToken": idToken, "displayName": name, "returnSecureToken": false]) { _, _, _ in }
}
func FBLookupName(_ idToken: String, _ cb: @escaping (String?) -> Void) {
  HttpPostJSON("\(idBase):lookup?key=\(FB_API_KEY)", ["idToken": idToken]) { j, st, e in
    if st != 200 || e != nil { cb(nil); return }
    let us = j?["users"] as? [JSON]; cb(S(us?.first?["displayName"]))
  }
}
func FBSendPasswordReset(_ email: String, _ cb: @escaping (String?) -> Void) {
  HttpPostJSON("\(idBase):sendOobCode?key=\(FB_API_KEY)", ["requestType": "PASSWORD_RESET", "email": email]) { j, st, e in
    cb(st != 200 || e != nil ? FBErrMsg(j, e) : nil) }
}
func FBSendVerifyEmail(_ idToken: String) {
  HttpPostJSON("\(idBase):sendOobCode?key=\(FB_API_KEY)", ["requestType": "VERIFY_EMAIL", "idToken": idToken]) { _, _, _ in }
}
/// Stores a sign-in response and sets the signed-in user. Shared by every sign-in screen.
func StoreAuth(_ json: JSON) -> (idToken: String, uid: String) {
  let idT = S(json["idToken"]) ?? "", refT = S(json["refreshToken"]) ?? "", uid = S(json["localId"]) ?? ""
  KSet("ld_idtoken", idT); KSet("ld_reftoken", refT); KSet("ld_uid", uid)
  return (idT, uid)
}
func SignOut() { gUser = nil; KSet("ld_idtoken", nil); KSet("ld_reftoken", nil); KSet("ld_uid", nil); Changed() }

// ---------- colors + fonts ----------
func Dyn(_ l: UIColor, _ d: UIColor) -> UIColor { UIColor { $0.userInterfaceStyle == .dark ? d : l } }
func Hex(_ h: UInt32) -> UIColor { UIColor(red: CGFloat((h >> 16) & 255) / 255, green: CGFloat((h >> 8) & 255) / 255, blue: CGFloat(h & 255) / 255, alpha: 1) }
// name -> hex preset; "red" is the original fixed brand color
let AccentThemes: [String: UInt32] = ["red": 0xE10600, "blue": 0x1C56D6, "green": 0x149A4B, "purple": 0x7A3FE0, "orange": 0xE2650C, "black": 0x141414]
func AccentColor() -> UIColor { Hex(AccentThemes[gAccent] ?? 0xE10600) }
func cBG() -> UIColor {
  switch gSeason {
  case "halloween": return Dyn(Hex(0xF4EFE8), Hex(0x171310))
  case "thanksgiving": return Dyn(Hex(0xF4EDE0), Hex(0x191410))
  case "christmas": return Dyn(Hex(0xEEF2EC), Hex(0x101713))
  default: return Dyn(Hex(0xF1F0EC), Hex(0x161615))
  }
}
func cInk() -> UIColor { Dyn(Hex(0x0B0B0A), Hex(0xF2F1ED)) }
func cMute() -> UIColor { Dyn(Hex(0x8E8D88), Hex(0x8A8985)) }
func cSoft() -> UIColor { Dyn(UIColor(white: 0, alpha: 0.07), UIColor(white: 1, alpha: 0.09)) }
func cLine() -> UIColor { Dyn(UIColor(white: 0, alpha: 0.13), UIColor(white: 1, alpha: 0.15)) }
func cPanel() -> UIColor { Dyn(Hex(0xD0CFCA), Hex(0x2E2E2D)) }
func cTint() -> UIColor { Dyn(Hex(0xEDECE8).withAlphaComponent(0.7), Hex(0x0A0A0A).withAlphaComponent(0.7)) }
func cRed() -> UIColor {
  switch gSeason {
  case "halloween": return Hex(0xF26A00)
  case "thanksgiving": return Hex(0xB4531A)
  case "christmas": return Hex(0x178A4E)
  default: return AccentColor()
  }
}
func Fd(_ s: CGFloat) -> UIFont { UIFont(name: "HelveticaNeue-CondensedBlack", size: s) ?? .systemFont(ofSize: s, weight: .heavy) }
func Fw(_ s: CGFloat) -> UIFont { UIFont(name: "VtksSportage", size: s) ?? Fd(s) }
func Fc(_ s: CGFloat) -> UIFont { .systemFont(ofSize: s, weight: .heavy) }
func Fm(_ s: CGFloat) -> UIFont { .systemFont(ofSize: s, weight: .semibold) }

func CapStr(_ t: String, _ sz: CGFloat, _ c: UIColor) -> NSAttributedString {
  NSAttributedString(string: t.uppercased(), attributes: [.font: Fc(sz), .foregroundColor: c, .kern: sz * 0.16])
}
func Cap(_ t: String, _ sz: CGFloat, _ c: UIColor, _ a: NSTextAlignment) -> UILabel { let l = UILabel(); l.attributedText = CapStr(t, sz, c); l.textAlignment = a; return l }
func SetCap(_ l: UILabel, _ t: String, _ sz: CGFloat, _ c: UIColor) { l.attributedText = CapStr(t, sz, c) }
func Disp(_ t: String, _ sz: CGFloat, _ c: UIColor, _ a: NSTextAlignment) -> UILabel {
  let l = UILabel(); l.text = t.uppercased(); l.font = Fd(sz); l.textColor = c; l.textAlignment = a; return l
}
func Line() -> UIView { let v = UIView(); v.backgroundColor = cLine(); return v }
func R(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: x, y: y, width: w, height: h) }
func Cl(_ x: CGFloat, _ a: CGFloat, _ b: CGFloat) -> CGFloat { max(a, min(b, x)) }
func Hap(_ s: Int) { UIImpactFeedbackGenerator(style: s >= 2 ? .medium : .light).impactOccurred() }
func Sym(_ n: String, _ pt: CGFloat) -> UIImage? { UIImage(systemName: n, withConfiguration: UIImage.SymbolConfiguration(pointSize: pt, weight: .semibold)) }
func SymT(_ n: String, _ pt: CGFloat, _ c: UIColor) -> UIImage? { Sym(n, pt)?.withTintColor(c, renderingMode: .alwaysOriginal) }

// ---------- press button ----------
final class PButton: UIButton {
  var tap: (() -> Void)?
  @objc func fire() { tap?() }
  override var isHighlighted: Bool {
    didSet {
      let h = isHighlighted
      UIView.animate(withDuration: 0.16, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
        self.transform = h ? CGAffineTransform(scaleX: 0.965, y: 0.965) : .identity; self.alpha = h ? 0.88 : 1
      }
    }
  }
}
func Btn(_ title: String, _ bg: UIColor, _ fg: UIColor, _ sz: CGFloat, _ tap: (() -> Void)?) -> PButton {
  let b = PButton(type: .custom); b.backgroundColor = bg
  b.setAttributedTitle(CapStr(title, sz, fg), for: .normal); b.tap = tap; b.layer.masksToBounds = true
  b.addTarget(b, action: #selector(PButton.fire), for: .touchUpInside); return b
}
func RetitleBtn(_ b: UIButton, _ t: String, _ sz: CGFloat, _ fg: UIColor) { b.setAttributedTitle(CapStr(t, sz, fg), for: .normal) }

// ---------- data ----------
// every item/drop belongs to a shop (ownerId == the Firebase uid that created it); "demo" is the seed shop
let kDemoShop = "demo"
final class Item {
  var iid = "", cat = "Tees", name = "", code = "", color = "", drop = "", ownerId = kDemoShop
  var desc: String?, imgURL: String?
  var price = 0
}
final class Drop {
  var did = "", name = "", nick = "", ownerId = kDemoShop
  var date = Date()
}
final class Shop { var shopId = "", name = "", accent = "red"; var logoURL: String? }

var gItems: [Item] = []
var gDrops: [Drop] = []
var gShops: [String: Shop] = [:]
var gUser: [String: String]?
func MyUid() -> String { gUser?["uid"] ?? KGet("ld_uid") ?? "" }
func ShopFor(_ ownerId: String?) -> Shop {
  let oid = (ownerId?.isEmpty ?? true) ? kDemoShop : ownerId!
  if let s = gShops[oid] { return s }
  let s = Shop(); s.shopId = oid; s.name = oid == kDemoShop ? gBrandName : "Untitled Shop"; gShops[oid] = s; return s
}
// when set (admin build only), taps that would open the customer product/drop sheet are redirected here instead
var gItemTapOverride: ((Item) -> Void)?
var gDropTapOverride: ((Drop) -> Void)?
var gDropAddOverride: (() -> Void)?

func DateAt(_ y: Int, _ m: Int, _ d: Int, _ h: Int) -> Date { Calendar.current.date(from: DateComponents(year: y, month: m, day: d, hour: h)) ?? Date() }
func LoadData() {
  let seeds: [(String, String, String, Date)] = [("d1", "Drop 01 · The Tees", "The Tees", DateAt(2026, 12, 15, 20)),
                                                ("d2", "Drop 02 · The Hoodies", "The Hoodies", DateAt(2027, 1, 15, 20)),
                                                ("d3", "Drop 03 · The Pants", "The Pants", DateAt(2027, 1, 15, 20))]
  gDrops = seeds.map { let d = Drop(); d.did = $0.0; d.name = $0.1; d.nick = $0.2; d.date = $0.3; return d }
  let demo = Shop(); demo.shopId = kDemoShop; demo.name = gBrandName; gShops[kDemoShop] = demo
  let rows: [(String, String, String, String, Int, String, String)] = [
    ("SH-01", "tee-lift", "Elevator", "Tees", 45, "d1", ""), ("SH-02", "tee-fire", "Bonfire", "Tees", 45, "d1", ""),
    ("SH-03", "tee-cards", "Card Table", "Tees", 45, "d1", ""), ("SH-04", "tee-door", "Open Door", "Tees", 45, "d1", ""),
    ("SH-05", "tee-chair", "Lawn Chair", "Tees", 45, "d1", ""),
    ("HD-01", "hood-white", "Hoodie White", "Hoodies", 95, "d2", "white"), ("HD-02", "hood-black", "Hoodie Black", "Hoodies", 95, "d2", "black"),
    ("HD-03", "hood-grey", "Hoodie Grey", "Hoodies", 95, "d2", "grey"), ("HD-04", "hood-yellow", "Hoodie Yellow", "Hoodies", 95, "d2", "yellow"),
    ("HD-05", "hood-blue", "Hoodie Blue", "Hoodies", 95, "d2", "blue"),
    ("PT-01", "pant-white", "Pants White", "Pants", 85, "d3", "white"), ("PT-02", "pant-black", "Pants Black", "Pants", 85, "d3", "black"),
    ("PT-03", "pant-grey", "Pants Grey", "Pants", 85, "d3", "grey"), ("PT-04", "pant-yellow", "Pants Yellow", "Pants", 85, "d3", "yellow"),
    ("PT-05", "pant-blue", "Pants Blue", "Pants", 85, "d3", "blue")]
  gItems = rows.map { r in let i = Item(); i.code = r.0; i.iid = r.1; i.name = r.2; i.cat = r.3; i.price = r.4; i.drop = r.5; i.color = r.6; return i }
}
func ItemById(_ i: String?) -> Item? { gItems.first { $0.iid == i } }
func DropById(_ i: String?) -> Drop? { gDrops.first { $0.did == i } }
func DropFor(_ it: Item) -> Drop { DropById(it.drop) ?? gDrops.first ?? { let d = Drop(); d.did = it.drop; d.date = Date(); return d }() }
func IsLive(_ it: Item) -> Bool { DropFor(it).date.timeIntervalSinceNow <= 0 }
func NextDrop() -> Drop? { gDrops.filter { $0.date.timeIntervalSinceNow > 0 }.min { $0.date < $1.date } }
private let sharedDF: DateFormatter = { let d = DateFormatter(); d.locale = .current; return d }()
func Fmt(_ f: String, _ d: Date) -> String { sharedDF.dateFormat = f; return sharedDF.string(from: d) }
func DateShort(_ d: Date) -> String { Fmt("MMM d", d) }
func DateLong(_ d: Date) -> String { Fmt("EEEE, MMMM d 'at' h:mm a", d) }
func Kind(_ it: Item) -> String { it.cat == "Tees" ? "Tee" : it.cat == "Hoodies" ? "Hoodie" : "Pants" }
func SubLine(_ it: Item) -> String { it.color.isEmpty ? Kind(it) : "\(Kind(it)) · \(it.color.capitalized)" }
func DescFor(_ it: Item) -> String {
  if let d = it.desc, !d.isEmpty { return d }
  if it.cat == "Tees" { return "Heavyweight tee with hand-drawn art from the L'Art de la Vie collection." }
  if it.cat == "Hoodies" { return "Heavyweight fleece hoodie with the \(gBrandName) wordmark across the chest." }
  return "Matching fleece pants with \(gBrandName) on the leg. Pairs with the hoodie."
}
func Money(_ p: Int) -> String { "$\(p)" }
func Pad(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }
func DropNum(_ it: Item) -> String { String(it.drop.dropFirst()) }

// ---------- images ----------
private let gImgCache = NSCache<NSString, UIImage>()
func ImgOverrideDir(_ kind: String) -> String {
  let base = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true).first ?? NSTemporaryDirectory()
  let dir = (base as NSString).appendingPathComponent("ld_img/\(kind)")
  try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
  return dir
}
func Img(_ iid: String, _ kind: String) -> UIImage? {
  let k = "\(kind)/\(iid)" as NSString
  if let im = gImgCache.object(forKey: k) { return im }
  let op = (ImgOverrideDir(kind) as NSString).appendingPathComponent("\(iid).png")
  if FileManager.default.fileExists(atPath: op), let im = UIImage(contentsOfFile: op) { gImgCache.setObject(im, forKey: k); return im }
  let bp = Bundle.main.bundlePath
  var p = "\(bp)/img/\(kind)/\(iid).webp"
  if !FileManager.default.fileExists(atPath: p) { p = "\(bp)/\(kind)/\(iid).webp" }
  let im = UIImage(contentsOfFile: p)
  if let im = im { gImgCache.setObject(im, forKey: k) }
  return im
}
private let gTrim = NSCache<UIImage, UIImage>()
/// Crops transparent margins off a product cut-out so it fills its frame.
func TrimImg(_ im: UIImage?) -> UIImage? {
  guard let im = im, let cg = im.cgImage else { return im }
  if let hit = gTrim.object(forKey: im) { return hit }
  let W = cg.width, H = cg.height; if W < 2 || H < 2 { return im }
  let sw = 160, sh = max(1, H * sw / W)
  var buf = [UInt8](repeating: 0, count: sw * sh * 4)
  let ok: Bool = buf.withUnsafeMutableBytes { raw in
    guard let cx = CGContext(data: raw.baseAddress, width: sw, height: sh, bitsPerComponent: 8, bytesPerRow: sw * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
    cx.draw(cg, in: CGRect(x: 0, y: 0, width: sw, height: sh)); return true
  }
  if !ok { return im }
  var x0 = sw, y0 = sh, x1 = 0, y1 = 0
  for y in 0..<sh { for x in 0..<sw where buf[(y * sw + x) * 4 + 3] > 12 { if x < x0 { x0 = x }; if x > x1 { x1 = x }; if y < y0 { y0 = y }; if y > y1 { y1 = y } } }
  if x1 <= x0 || y1 <= y0 { return im }
  let fx = CGFloat(W) / CGFloat(sw), fy = CGFloat(H) / CGFloat(sh)
  var r = CGRect(x: max(0, CGFloat(x0 - 1) * fx), y: max(0, CGFloat(y0 - 1) * fy), width: 0, height: 0)
  r.size.width = min(CGFloat(W) - r.origin.x, CGFloat(x1 - x0 + 3) * fx); r.size.height = min(CGFloat(H) - r.origin.y, CGFloat(y1 - y0 + 3) * fy)
  guard let cr = cg.cropping(to: r.integral) else { return im }
  let out = UIImage(cgImage: cr, scale: im.scale, orientation: .up)
  gTrim.setObject(out, forKey: im); return out
}
func BundleImg(_ name: String) -> UIImage? { UIImage(contentsOfFile: (Bundle.main.bundlePath as NSString).appendingPathComponent(name)) }

// ---------- state ----------
struct BagLine { var id: String; var size: String; var q: Int }
var gSaved: [String] = [], gBag: [BagLine] = []
var gSize = "M", gTheme = "auto", gIcon = ""
var gRemind: [String: Bool] = [:]
var gAlerts = true
let UD = UserDefaults.standard
func LoadState() {
  gSaved = (UD.array(forKey: "ld_saved") as? [String]) ?? []
  gBag = ((UD.array(forKey: "ld_bag") as? [[String: Any]]) ?? []).compactMap { d in
    guard let id = S(d["id"]) else { return nil }; return BagLine(id: id, size: S(d["size"]) ?? "M", q: I(d["q"]) ?? 1) }
  gSize = UD.string(forKey: "ld_size") ?? "M"; gTheme = UD.string(forKey: "ld_theme") ?? "auto"; gIcon = UD.string(forKey: "ld_icon") ?? ""
  gRemind = [:]; for (k, v) in (UD.dictionary(forKey: "ld_remind") ?? [:]) { gRemind[k] = B(v) }
  gAlerts = UD.object(forKey: "ld_alerts") != nil ? UD.bool(forKey: "ld_alerts") : true
  gUser = UD.dictionary(forKey: "ld_user") as? [String: String]; gSeason = UD.string(forKey: "ld_season") ?? ""
  gBrandName = UD.string(forKey: "ld_brand") ?? "LONDiA"; gAccent = UD.string(forKey: "ld_accent") ?? "red"
}
func SaveState() {
  UD.set(gSaved, forKey: "ld_saved"); UD.set(gBag.map { ["id": $0.id, "size": $0.size, "q": $0.q] as [String: Any] }, forKey: "ld_bag")
  UD.set(gSize, forKey: "ld_size"); UD.set(gTheme, forKey: "ld_theme"); UD.set(gIcon, forKey: "ld_icon"); UD.set(gRemind, forKey: "ld_remind")
  UD.set(gAlerts, forKey: "ld_alerts"); UD.set(gSeason, forKey: "ld_season"); UD.set(gBrandName, forKey: "ld_brand"); UD.set(gAccent, forKey: "ld_accent")
  if let u = gUser { UD.set(u, forKey: "ld_user") } else { UD.removeObject(forKey: "ld_user") }
}
func Changed() { SaveState(); NotificationCenter.default.post(name: kChange, object: nil) }
func Stamp() { UD.set(Date().timeIntervalSince1970, forKey: "ld_last") }

func ClearItemImageOverride(_ it: Item) {
  let verKey = "ld_imgv_" + it.iid
  guard UD.string(forKey: verKey) != nil else { return }
  for kind in ["thumb", "med", "hires"] {
    try? FileManager.default.removeItem(atPath: (ImgOverrideDir(kind) as NSString).appendingPathComponent("\(it.iid).png"))
    gImgCache.removeObject(forKey: "\(kind)/\(it.iid)" as NSString)
  }
  UD.removeObject(forKey: verKey)
}
/// writes image bytes into the on-disk override cache for an item and marks its imgURL as the cached version
func StoreItemImageData(_ it: Item, _ png: Data?) {
  guard let png = png, !it.iid.isEmpty else { return }
  for kind in ["thumb", "med", "hires"] {
    try? png.write(to: URL(fileURLWithPath: (ImgOverrideDir(kind) as NSString).appendingPathComponent("\(it.iid).png")), options: .atomic)
    gImgCache.removeObject(forKey: "\(kind)/\(it.iid)" as NSString)
  }
  if let u = it.imgURL, !u.isEmpty { UD.set(u, forKey: "ld_imgv_" + it.iid) }
}
func DownloadItemImage(_ it: Item) {
  guard let s = it.imgURL, !s.isEmpty, UD.string(forKey: "ld_imgv_" + it.iid) != s, let u = URL(string: s) else { return }
  URLSession.shared.dataTask(with: u) { data, _, _ in
    guard let data = data, let im = UIImage(data: data), let png = im.pngData() else { return }
    onMain { StoreItemImageData(it, png); Changed() }
  }.resume()
}
func ItemFields(_ it: Item, _ overrides: JSON = [:]) -> JSON {
  var f: JSON = ["code": it.code, "cat": it.cat, "color": it.color, "drop": it.drop, "price": it.price, "desc": it.desc ?? ""]
  if let u = it.imgURL, !u.isEmpty { f["img"] = u }
  for (k, v) in overrides { f[k] = v }
  return f
}
func SyncCatalog() {
  FSList("shops") { sDocs in
    for f in sDocs {
      guard let sid = S(f["__id"]) else { continue }
      let s = gShops[sid] ?? Shop(); s.shopId = sid; s.name = S(f["name"]) ?? s.name; s.logoURL = S(f["logo"]); s.accent = S(f["accent"]) ?? "red"; gShops[sid] = s
    }
    FSList("catalog_drops") { dDocs in
      if !dDocs.isEmpty {
        let nd: [Drop] = dDocs.compactMap { f in
          guard let id = S(f["__id"]) else { return nil }
          let d = Drop(); d.did = id; d.name = S(f["name"]) ?? id; d.nick = S(f["nick"]) ?? d.name; d.date = DateFromISO(S(f["date"])); d.ownerId = S(f["ownerId"]) ?? kDemoShop; return d }
        if !nd.isEmpty { gDrops = nd }
      } else {
        let tok = Token()
        if !tok.isEmpty { for d in gDrops { FSUpsertAuth("catalog_drops", d.did, ["name": d.name, "nick": d.nick, "date": ISOFromDate(d.date), "ownerId": d.ownerId], tok, nil) } }
      }
      FSList("catalog_items") { iDocs in
        if !iDocs.isEmpty {
          var merged = gItems; var liveIds = Set<String>()
          for f in iDocs {
            guard let iid = S(f["__id"]) else { continue }
            if B(f["hidden"]) { merged.removeAll { $0.iid == iid }; continue }
            liveIds.insert(iid)
            var it = merged.first { $0.iid == iid }
            if it == nil { let n = Item(); n.iid = iid; merged.append(n); it = n }
            guard let item = it else { continue }
            item.code = S(f["code"]) ?? (item.code.isEmpty ? iid : item.code); item.cat = S(f["cat"]) ?? item.cat; item.color = S(f["color"]) ?? ""
            item.drop = S(f["drop"]) ?? (item.drop.isEmpty ? "d1" : item.drop); item.price = I(f["price"]) ?? item.price
            item.name = S(f["name"]) ?? item.code; item.desc = S(f["desc"]); item.imgURL = S(f["img"]); item.ownerId = S(f["ownerId"]) ?? kDemoShop
            if (item.imgURL ?? "").isEmpty { ClearItemImageOverride(item) }
          }
          // Firestore is the source of truth once seeded: anything without a doc was deleted remotely.
          merged.removeAll { !liveIds.contains($0.iid) }
          gItems = merged; gItems.forEach(DownloadItemImage)
        } else {
          let tok = Token()
          if !tok.isEmpty { for it in gItems { FSUpsertAuth("catalog_items", it.iid, ["code": it.code, "cat": it.cat, "color": it.color, "drop": it.drop, "price": it.price, "ownerId": it.ownerId], tok, nil) } }
        }
        Changed()
      }
    }
  }
}
func Toast(_ t: String) { _ = t }
func IsSaved(_ i: String) -> Bool { gSaved.contains(i) }
func ToggleSaved(_ i: String) { if IsSaved(i) { gSaved.removeAll { $0 == i } } else { gSaved.append(i) }; Hap(1); Changed() }
func BagCount() -> Int { gBag.reduce(0) { $0 + $1.q } }
func BagTotal() -> Int { gBag.reduce(0) { t, d in t + (ItemById(d.id).map { $0.price * d.q } ?? 0) } }
func AddBag(_ i: String, _ sz: String) {
  if let k = gBag.firstIndex(where: { $0.id == i && $0.size == sz }) { gBag[k].q += 1 } else { gBag.append(BagLine(id: i, size: sz, q: 1)) }
  Changed()
}
func BagQty(_ k: Int, _ delta: Int) {
  guard k >= 0 && k < gBag.count else { return }
  let q = gBag[k].q + delta
  if q <= 0 { gBag.remove(at: k) } else { gBag[k].q = q }
  Changed()
}

// ---------- seasonal background art (tiled, slowly drifting) ----------
final class ArtView: UIView {
  var tiles: UIView?
  override init(frame f: CGRect) {
    super.init(frame: f); isUserInteractionEnabled = false; clipsToBounds = true; autoresizingMask = [.flexibleWidth, .flexibleHeight]
    guard let im = BundleImg("art_\(gSeason).png") else { return }
    let sc = UIScreen.main.bounds.size; let cols = Int(ceil(sc.width / 360)), rows = Int(ceil((sc.height + 960) / 480))
    let t = UIView(frame: R(0, -480, CGFloat(cols) * 360, CGFloat(rows) * 480)); addSubview(t); tiles = t
    for r in 0..<rows { for k in 0..<cols { let iv = UIImageView(image: im); iv.frame = R(CGFloat(k) * 360, CGFloat(r) * 480, 360, 480); t.addSubview(iv) } }
    NotificationCenter.default.addObserver(self, selector: #selector(drift), name: UIApplication.didBecomeActiveNotification, object: nil)
  }
  required init?(coder: NSCoder) { fatalError() }
  deinit { NotificationCenter.default.removeObserver(self) }
  override func didMoveToWindow() { super.didMoveToWindow(); drift() }
  @objc func drift() {
    guard let t = tiles, window != nil, !UIAccessibility.isReduceMotionEnabled else { return }
    let a = CABasicAnimation(keyPath: "transform.translation.y"); a.fromValue = 0; a.toValue = 480; a.duration = 140; a.repeatCount = .infinity
    a.timingFunction = CAMediaTimingFunction(name: .linear); t.layer.add(a, forKey: "drift")
  }
  override func layoutSubviews() { super.layoutSubviews(); alpha = traitCollection.userInterfaceStyle == .dark ? 0.6 : 0.085 }
}
func AddArt(_ host: UIView) { if gSeason.isEmpty { return }; host.insertSubview(ArtView(frame: host.bounds), at: 0) }

// ---------- window helpers ----------
func KeyWin() -> UIWindow? {
  for s in UIApplication.shared.connectedScenes { if let ws = s as? UIWindowScene { for w in ws.windows where w.isKeyWindow { return w } } }
  return UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.windows.first }.first
}
func TopVC() -> UIViewController? { var v = KeyWin()?.rootViewController; while let p = v?.presentedViewController { v = p }; return v }
func ApplyThemeStyle() { KeyWin()?.overrideUserInterfaceStyle = gTheme == "dark" ? .dark : gTheme == "light" ? .light : .unspecified }

// ---------- notifications / reminders ----------
func NoteSchedule(_ ident: String, _ title: String, _ body: String, _ dt: TimeInterval) {
  if dt < 1 { return }
  let c = UNUserNotificationCenter.current()
  c.requestAuthorization(options: [.alert, .sound, .badge]) { ok, _ in
    guard ok else { return }
    let n = UNMutableNotificationContent(); n.title = title; n.body = body; n.sound = .default
    c.add(UNNotificationRequest(identifier: ident, content: n, trigger: UNTimeIntervalNotificationTrigger(timeInterval: dt, repeats: false)))
  }
}
func RemDrop(_ d: Drop) -> Bool { gRemind[d.did] ?? false }
func RemItem(_ it: Item) -> Bool { (gRemind["i:" + it.iid] ?? false) || (gRemind[it.drop] ?? false) }
func ScheduleDrop(_ d: Drop) {
  let c = UNUserNotificationCenter.current()
  var ids = [d.did + "-t", d.did + "-h"]
  let its = gItems.filter { $0.drop == d.did }
  for i in its { ids.append("i-\(i.iid)-t"); ids.append("i-\(i.iid)-h") }
  c.removePendingNotificationRequests(withIdentifiers: ids)
  if !gAlerts { return }
  let dt = d.date.timeIntervalSinceNow, pre = gBrandName + " — "
  if gRemind[d.did] ?? false {
    NoteSchedule(d.did + "-t", pre + d.name, "It's live. Go get it.", dt)
    if dt - 3600 > 1 { NoteSchedule(d.did + "-h", pre + d.name, "Drops in 1 hour.", dt - 3600) }
    return
  }
  for i in its where gRemind["i:" + i.iid] ?? false {
    NoteSchedule("i-\(i.iid)-t", pre + i.code, "\(i.code) is live. Go get it.", dt)
    if dt - 3600 > 1 { NoteSchedule("i-\(i.iid)-h", pre + i.code, "\(i.code) drops in 1 hour.", dt - 3600) }
  }
}
func ScheduleAll() { gDrops.forEach(ScheduleDrop) }
func ToggleRemDrop(_ d: Drop) {
  let on = !(gRemind[d.did] ?? false); gRemind[d.did] = on
  if on { for i in gItems where i.drop == d.did { gRemind.removeValue(forKey: "i:" + i.iid) } }
  ScheduleDrop(d); Hap(2); Changed()
}
func ToggleRemItem(_ it: Item) {
  let d = DropFor(it)
  if gRemind[d.did] ?? false { gRemind[d.did] = false } else { let k = "i:" + it.iid; gRemind[k] = !(gRemind[k] ?? false) }
  ScheduleDrop(d); Hap(2); Changed()
}
func RemCount() -> Int { gRemind.values.filter { $0 }.count }

// ---------- admin helpers (shared by both admin apps) ----------
let CLOUDINARY_CLOUD_NAME = "dgs7mhk3g"
let CLOUDINARY_UPLOAD_PRESET = "londia-app"
func CloudinaryUpload(_ img: UIImage, _ cb: @escaping (String?, String?) -> Void) {
  guard let png = img.pngData() else { cb(nil, "Couldn't read that photo."); return }
  let boundary = "LDB\(UInt32.random(in: 0...UInt32.max))"
  guard let url = URL(string: "https://api.cloudinary.com/v1_1/\(CLOUDINARY_CLOUD_NAME)/image/upload") else { cb(nil, "Upload failed."); return }
  var r = URLRequest(url: url); r.httpMethod = "POST"; r.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
  var body = Data()
  body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"upload_preset\"\r\n\r\n\(CLOUDINARY_UPLOAD_PRESET)\r\n".data(using: .utf8)!)
  body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"photo.png\"\r\nContent-Type: image/png\r\n\r\n".data(using: .utf8)!)
  body.append(png); body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
  r.httpBody = body
  URLSession.shared.dataTask(with: r) { data, _, _ in
    let j = data.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? JSON }
    onMain {
      if let u = S(j?["secure_url"]) { cb(u, nil) }
      else { cb(nil, S((j?["error"] as? JSON)?["message"]) ?? "Upload failed. Check your internet and try again.") }
    }
  }.resume()
}
func CodePrefixForCat(_ cat: String) -> String { cat == "Hoodies" ? "HD" : cat == "Pants" ? "PT" : "SH" }
// a drop named like "The Hoodies" moves a tagged item into that category; an unrelated name leaves it alone
func CatForDropName(_ name: String?) -> String? {
  let n = (name ?? "").lowercased()
  if n.contains("hoodie") { return "Hoodies" }; if n.contains("pant") { return "Pants" }
  if n.contains("tee") || n.contains("shirt") { return "Tees" }; return nil
}
/// Starts the app's data: seed catalog, saved state, reminders, then the live Firestore sync.
func BootData() { LoadData(); LoadState(); ScheduleAll(); SyncCatalog() }
