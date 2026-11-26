// ===== sheets: auth, profile/settings (classic) =====
import UIKit

let kGoTab = Notification.Name("LDGoTab")
let kRebuild = Notification.Name("LDRebuild")
let kOpenSettings = Notification.Name("LDOpenSettings")
let kCloseSettings = Notification.Name("LDCloseSettings")
let kOpenItem = Notification.Name("LDOpenItem")

func CircleBtn(_ sym: String, _ target: Any, _ sel: Selector) -> UIButton {
  let b = UIButton(type: .custom); b.backgroundColor = cSoft(); b.layer.cornerRadius = 22; b.layer.masksToBounds = true; b.bounds = R(0, 0, 44, 44)
  b.setImage(SymT(sym, 16, cInk()), for: .normal); b.addTarget(target, action: sel, for: .touchUpInside); return b
}

/// Full-screen sheet that can be pulled down to dismiss (the "edge back" gesture from the original).
class EdgeBackVC: UIViewController, UIGestureRecognizerDelegate {
  func addEdgeBack() { let pg = UIPanGestureRecognizer(target: self, action: #selector(edgeBack(_:))); pg.delegate = self; view.addGestureRecognizer(pg) }
  @objc func edgeBack(_ g: UIPanGestureRecognizer) {
    let ty = max(0, g.translation(in: g.view).y)
    switch g.state {
    case .changed: view.transform = CGAffineTransform(translationX: 0, y: ty * 0.95)
    case .ended, .cancelled, .failed:
      let vy = g.velocity(in: g.view).y
      if g.state == .ended && (ty > 130 || vy > 900) {
        Hap(1); view.endEditing(true)
        anim(0.22, { self.view.transform = CGAffineTransform(translationX: 0, y: self.view.bounds.height) }, done: { _ in self.dismiss(animated: false) { self.view.transform = .identity } })
      } else { spring(0.3, 0.85, { self.view.transform = .identity }) }
    default: break
    }
  }
  func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
    guard let pg = g as? UIPanGestureRecognizer else { return true }
    let v = pg.velocity(in: view); if v.y <= 0 || abs(v.y) < abs(v.x) * 1.3 { return false }
    for sv in view.subviews { if let s = sv as? UIScrollView, s.contentOffset.y > 1 { return false } }
    return true
  }
  func gestureRecognizer(_ a: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith b: UIGestureRecognizer) -> Bool { true }
  @objc func keyboardChange(_ n: Notification) {
    guard let f = (n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue, let sv = keyboardScroll else { return }
    var e = sv.contentInset; e.bottom = max(0, view.bounds.height - view.convert(f, from: nil).origin.y); sv.contentInset = e
  }
  var keyboardScroll: UIScrollView?
  func watchKeyboard(_ sv: UIScrollView) { keyboardScroll = sv; NotificationCenter.default.addObserver(self, selector: #selector(keyboardChange(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil) }
}

// ---------- open item: jump to the Feed and expand its card ----------
func OpenItem(_ it: Item?) {
  guard let it = it else { return }
  if let o = gItemTapOverride { o(it); return }
  let iid = it.iid; let go = { NotificationCenter.default.post(name: kOpenItem, object: iid) }
  if let tv = TopVC(), tv.presentingViewController != nil { tv.dismiss(animated: false, completion: go) } else { go() }
}

// ---------- auth ----------
final class AuthVC: EdgeBackVC, UITextFieldDelegate {
  var signup = false; let sv = UIScrollView(); var back: UIButton!
  let t1 = Disp("", 64, cInk(), .left), t2 = Disp("", 64, cInk(), .left), sub = Cap("L'Art de la Vie · saved on this device", 9.5, cMute(), .left), err = UILabel()
  var fields: [UITextField] = []; var go: PButton!; let swap = UIButton(type: .custom), forgot = UIButton(type: .custom), eye = UIButton(type: .custom)
  override func viewDidLoad() {
    super.viewDidLoad(); view.backgroundColor = cBG(); AddArt(view)
    sv.keyboardDismissMode = .interactive; sv.bounces = false; sv.contentInsetAdjustmentBehavior = .never; view.addSubview(sv)
    addEdgeBack(); back = CircleBtn("chevron.left", self, #selector(goBack)); view.addSubview(back)
    sv.addSubview(t1); sv.addSubview(t2); sv.addSubview(sub)
    let ph = ["Name", "Email", "Password (6+ characters)"]
    for i in 0..<3 {
      let f = UITextField(); f.backgroundColor = cSoft(); f.layer.cornerRadius = 14; f.font = Fm(16); f.textColor = cInk(); f.tintColor = cRed(); f.delegate = self; f.tag = i
      f.attributedPlaceholder = NSAttributedString(string: ph[i], attributes: [.foregroundColor: cMute(), .font: Fm(16)])
      f.leftView = UIView(frame: R(0, 0, 16, 10)); f.leftViewMode = .always; f.autocorrectionType = .no; f.autocapitalizationType = i == 0 ? .words : .none
      if i == 1 { f.keyboardType = .emailAddress; f.textContentType = .emailAddress }; if i == 2 { f.isSecureTextEntry = true; f.textContentType = .password }
      f.returnKeyType = i == 2 ? .go : .next; sv.addSubview(f); fields.append(f)
    }
    let eyeWrap = UIView(frame: R(0, 0, 40, 52)); eye.frame = R(40 - 24 - 10, (52 - 24) / 2, 24, 24)
    eye.setImage(SymT("eye.slash", 16, cMute()), for: .normal); eye.addTarget(self, action: #selector(eyeTap), for: .touchUpInside); eyeWrap.addSubview(eye)
    fields[2].rightView = eyeWrap; fields[2].rightViewMode = .always
    err.font = Fm(13); err.textColor = cRed(); err.numberOfLines = 2; sv.addSubview(err)
    go = Btn("", cRed(), .white, 12) { [weak self] in self?.submit() }; go.layer.cornerRadius = 28; sv.addSubview(go)
    swap.addTarget(self, action: #selector(toggle), for: .touchUpInside); sv.addSubview(swap)
    forgot.setAttributedTitle(NSAttributedString(string: "Forgot password?", attributes: [.font: Fc(12), .foregroundColor: cMute()]), for: .normal)
    forgot.addTarget(self, action: #selector(forgotTap), for: .touchUpInside); sv.addSubview(forgot)
    watchKeyboard(sv); mode()
  }
  deinit { NotificationCenter.default.removeObserver(self) }
  @objc func goBack() { view.endEditing(true); dismiss(animated: true) }
  @objc func eyeTap() {
    let f = fields[2]; f.isSecureTextEntry.toggle(); let t = f.text; f.text = ""; f.text = t
    eye.setImage(SymT(f.isSecureTextEntry ? "eye.slash" : "eye", 16, cMute()), for: .normal); Hap(1)
  }
  @objc func toggle() { signup.toggle(); err.text = ""; Hap(1); anim(0.25, { self.mode(); self.view.setNeedsLayout(); self.view.layoutIfNeeded() }) }
  func mode() {
    t1.text = signup ? "CREATE" : "WELCOME"; t2.text = signup ? "ACCOUNT" : "BACK"; fields[0].alpha = signup ? 1 : 0; fields[0].isUserInteractionEnabled = signup
    RetitleBtn(go, signup ? "Create account" : "Sign in", 12, .white)
    swap.setAttributedTitle(NSAttributedString(string: signup ? "Have an account? Sign in" : "New here? Create an account", attributes: [.font: Fc(12), .foregroundColor: cRed()]), for: .normal)
    forgot.isHidden = signup
  }
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews(); let w = view.bounds.width, T = view.safeAreaInsets.top
    back.frame = R(16, T + 6, 44, 44); sv.frame = R(0, T + 12, w, view.bounds.height - T - 12)
    var y: CGFloat = 0; t1.frame = R(20, y, w - 40, 60); y += 58; t2.frame = R(20, y, w - 40, 60); y += 70; sub.frame = R(20, y, w - 40, 16); y += 34
    fields[0].frame = R(20, y, w - 40, 52); if signup { y += 62 }
    fields[1].frame = R(20, y, w - 40, 52); y += 62; fields[2].frame = R(20, y, w - 40, 52); y += 62
    if !signup { forgot.frame = R(20, y, w - 40, 22); y += 26 }
    err.frame = R(20, y, w - 40, 34); y += 38; go.frame = R(20, y, w - 40, 56); y += 64; swap.frame = R(20, y, w - 40, 40); y += 48
    sv.contentSize = CGSize(width: w, height: y + 20)
  }
  func textFieldShouldReturn(_ f: UITextField) -> Bool { if f.tag == 0 { fields[1].becomeFirstResponder() } else if f.tag == 1 { fields[2].becomeFirstResponder() } else { submit() }; return true }
  func fail(_ m: String) { err.textColor = cRed(); err.text = m; Hap(2); go.isEnabled = true; go.alpha = 1; RetitleBtn(go, signup ? "Create account" : "Sign in", 12, .white) }
  @objc func forgotTap() {
    let email = (fields[1].text ?? "").trimmingCharacters(in: .whitespaces).lowercased()
    if !email.contains("@") || !email.contains(".") { fail("Enter your email above first."); return }
    err.textColor = cMute(); err.text = "Sending reset link…"; Hap(1)
    FBSendPasswordReset(email) { [weak self] e in guard let s = self else { return }; if let e = e { s.fail(e); return }; s.err.textColor = cInk(); s.err.text = "Check your email for a reset link."; Hap(2) }
  }
  func submit() {
    if !go.isEnabled { return }
    let name = (fields[0].text ?? "").trimmingCharacters(in: .whitespaces), email = (fields[1].text ?? "").trimmingCharacters(in: .whitespaces).lowercased(), pw = fields[2].text ?? ""
    if signup && name.isEmpty { fail("Add your name."); return }
    if !email.contains("@") || !email.contains(".") { fail("Enter a valid email."); return }
    if pw.count < 6 { fail("Password needs 6+ characters."); return }
    err.text = ""; go.isEnabled = false; go.alpha = 0.5; RetitleBtn(go, "Please wait…", 12, .white); let up = signup
    let onOK: (JSON) -> Void = { [weak self] json in
      guard let s = self else { return }
      let (idT, uid) = StoreAuth(json)
      let finish: (String?) -> Void = { finalName in
        gUser = ["name": finalName ?? "", "email": email, "uid": uid]; Changed(); Hap(2); s.view.endEditing(true)
        s.dismiss(animated: true) { if up { Toast("Account created") } }
      }
      if up && !name.isEmpty { FBSetDisplayName(idT, name); FBSendVerifyEmail(idT); finish(name) } else { FBLookupName(idT) { finish($0) } }
    }
    let handle: (JSON?, String?) -> Void = { [weak self] json, e in guard let s = self else { return }; if let e = e { s.fail(e); return }; if let j = json { onOK(j) } }
    if signup { FBSignUp(email, pw, handle) } else { FBSignIn(email, pw, handle) }
  }
}
func OpenAuth(_ signup: Bool) { let a = AuthVC(); a.signup = signup; a.modalPresentationStyle = .overFullScreen; TopVC()?.present(a, animated: true) }

// ---------- profile / settings ----------
final class ProfileVC: EdgeBackVC {
  var back: UIButton!; let avatar = UIView(), avDot = UIView(), panel = UIView(); var avL = UILabel(), name = UILabel(), email = UILabel(), foot = UILabel()
  var rows: [UIView] = []; var themeB: [UIButton] = [], sizeB: [UIButton] = [], iconB: [UIButton] = []; var footCells: [UIButton] = []
  var taps = 0; var tapT: Timer?; var obs: NSObjectProtocol?
  var confirmSO = false; let soLabel = UILabel(); let soX = UIButton(type: .custom), soCheck = UIButton(type: .custom)
  let iconDefs: [(String, String, String)] = [("", "icon-192.png", "Dark"), ("White", "icon-white-192.png", "White")]
  override func viewDidLoad() {
    super.viewDidLoad(); build()
    obs = NotificationCenter.default.addObserver(forName: kChange, object: nil, queue: .main) { [weak self] _ in self?.refreshValues() }
  }
  deinit { if let o = obs { NotificationCenter.default.removeObserver(o) } }
  @objc func goBack() { if parent != nil { NotificationCenter.default.post(name: kCloseSettings, object: nil) } else { dismiss(animated: true) } }
  func build() {
    if gIcon != "" && gIcon != "White" { gIcon = ""; gSeason = ""; SaveState(); if UIApplication.shared.supportsAlternateIcons { UIApplication.shared.setAlternateIconName(nil) { _ in } } }
    view.subviews.forEach { $0.removeFromSuperview() }
    let ch = parent != nil; view.backgroundColor = ch ? .clear : cBG(); if !ch { AddArt(view); addEdgeBack() }
    back = CircleBtn("chevron.left", self, #selector(goBack))
    avatar.backgroundColor = cInk(); avatar.layer.cornerRadius = 32; view.addSubview(avatar)
    avL = Disp("L", 34, cBG(), .center); avatar.addSubview(avL); avDot.backgroundColor = cRed(); avDot.layer.cornerRadius = 4.5; avatar.addSubview(avDot)
    name = Disp("You", 54, cInk(), .left); name.adjustsFontSizeToFitWidth = true; name.minimumScaleFactor = 0.5; view.addSubview(name)
    email = Cap("", 9.5, cMute(), .left); view.addSubview(email)
    panel.backgroundColor = .clear; view.addSubview(panel); rows = []
    // row 0: orders + account
    let ft = UIView(); panel.addSubview(ft); rows.append(ft); footCells = []
    for i in 0..<2 { let c = Btn("", .clear, cInk(), 10) { [weak self] in self?.footTap(i) }; c.layer.cornerRadius = 16; ft.addSubview(c); footCells.append(c) }
    // row 1: alerts + theme
    let r0 = UIView(); panel.addSubview(r0); rows.append(r0); themeB = []
    for m in ["alerts", "auto", "light", "dark"] {
      let b = UIButton(type: .custom); b.accessibilityIdentifier = m; b.layer.cornerRadius = 16
      b.addTarget(self, action: m == "alerts" ? #selector(alertTap) : #selector(themeTap(_:)), for: .touchUpInside); r0.addSubview(b); themeB.append(b)
    }
    // row 2: size
    let r1 = UIView(); panel.addSubview(r1); rows.append(r1); sizeB = []
    for m in ["S", "M", "L", "XL"] { let b = UIButton(type: .custom); b.accessibilityIdentifier = m; b.layer.cornerRadius = 16; b.addTarget(self, action: #selector(sizeTap(_:)), for: .touchUpInside); r1.addSubview(b); sizeB.append(b) }
    // row 3: app icons
    let ic = UIView(); panel.addSubview(ic); rows.append(ic); iconB = []
    for d in iconDefs {
      let b = UIButton(type: .custom); b.accessibilityIdentifier = d.0
      let iv = UIImageView(image: BundleImg(d.1)); iv.tag = 5; iv.layer.cornerRadius = 14; iv.layer.masksToBounds = true; iv.contentMode = .scaleAspectFill; iv.isUserInteractionEnabled = false; b.addSubview(iv)
      b.addTarget(self, action: #selector(iconTap(_:)), for: .touchUpInside); ic.addSubview(b); iconB.append(b)
    }
    soLabel.numberOfLines = 0; soLabel.textAlignment = .center; soLabel.font = Fm(16); soLabel.textColor = cInk(); soLabel.text = "Are you sure you want to sign out?"; soLabel.alpha = 0; soLabel.isUserInteractionEnabled = false; panel.addSubview(soLabel)
    soX.alpha = 0; soX.isUserInteractionEnabled = false; soX.addTarget(self, action: #selector(soCancelTap), for: .touchUpInside); panel.addSubview(soX)
    soCheck.alpha = 0; soCheck.isUserInteractionEnabled = false; soCheck.addTarget(self, action: #selector(soConfirmTap), for: .touchUpInside); panel.addSubview(soCheck)
    confirmSO = false
    foot = Cap("LONDiA USA · Version 5.0 · © 2026", 9, cMute(), .center); foot.isUserInteractionEnabled = true
    foot.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(footerTap))); view.addSubview(foot)
    refreshValues(); view.setNeedsLayout()
  }
  func footTap(_ i: Int) {
    if i == 0 { Toast("Orders are coming soon"); return }
    if gUser != nil { Hap(1); setSO(true) } else { OpenAuth(true) }
  }
  @objc func soCancelTap() { Hap(1); setSO(false) }
  @objc func soConfirmTap() { Hap(2); setSO(false); SignOut() }
  func setSO(_ on: Bool) {
    confirmSO = on
    spring(0.4, 0.92, opts: [.curveEaseOut], {
      for b in self.themeB + self.sizeB + self.iconB { b.alpha = on ? 0 : 1; b.isUserInteractionEnabled = !on }
      self.soLabel.alpha = on ? 1 : 0
      self.soX.alpha = on ? 1 : 0; self.soX.isUserInteractionEnabled = on; self.soCheck.alpha = on ? 1 : 0; self.soCheck.isUserInteractionEnabled = on
    })
  }
  @objc func footerTap() {
    taps += 1; tapT?.invalidate(); tapT = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in self?.taps = 0 }
    if taps >= 5 { taps = 0; NoteSchedule("test", "LONDiA test", "Notifications work. Lock your phone to see it.", 10); Hap(2); Toast("Test sent · lock your phone") }
  }
  @objc func alertTap() { gAlerts.toggle(); ScheduleAll(); Hap(1); Changed() }
  @objc func themeTap(_ b: UIButton) { gTheme = b.accessibilityIdentifier ?? "auto"; Hap(1); ApplyThemeStyle(); Changed() }
  @objc func sizeTap(_ b: UIButton) { gSize = b.accessibilityIdentifier ?? "M"; Hap(1); Changed() }
  @objc func iconTap(_ b: UIButton) {
    let n = b.accessibilityIdentifier ?? ""; if n == gIcon { return }; gIcon = n; Hap(2)
    gSeason = n == "Halloween" ? "halloween" : n == "Thanksgiving" ? "thanksgiving" : n == "Christmas" ? "christmas" : ""
    if UIApplication.shared.supportsAlternateIcons { UIApplication.shared.setAlternateIconName(n.isEmpty ? nil : n + "2") { _ in } }
    SaveState(); refreshValues()
  }
  func styleTile(_ b: UIButton, _ sym: String, _ on: Bool) { b.accessibilityLabel = sym; b.isSelected = on; b.backgroundColor = .clear; renderTile(b) }
  func renderTile(_ b: UIButton) {
    let w = b.bounds.width, h = b.bounds.height; if w < 2 { return }
    let on = b.isSelected, al = b.accessibilityIdentifier == "alerts", isFoot = footCells.contains(b)
    let fg = on ? (al ? cRed() : cInk()) : cInk().withAlphaComponent(0.25); let r = fg.resolvedColor(with: traitCollection)
    var iv = b.viewWithTag(7) as? UIImageView
    if iv == nil { let n = UIImageView(); n.tag = 7; n.contentMode = .scaleAspectFit; n.isUserInteractionEnabled = false; b.addSubview(n); iv = n }
    guard let v = iv else { return }; let sym = b.accessibilityLabel ?? ""
    if isFoot {
      let isz = min(w, h); v.frame = b.bounds.insetBy(dx: (w - isz) / 2, dy: (h - isz) / 2); v.tintColor = nil
      v.image = SymT(sym, isz * 0.86, cInk().resolvedColor(with: traitCollection)); return
    }
    v.frame = b.bounds
    if sym.hasPrefix("sil:") {
      v.image = SilImg(1); v.tintColor = r; v.contentMode = .scaleAspectFit
      let sc = 0.35 + 0.1933 * CGFloat(sizeB.firstIndex(of: b) ?? 0); v.frame = b.bounds.insetBy(dx: w * (1 - sc) / 2, dy: h * (1 - sc) / 2)
    } else { v.tintColor = nil; v.image = SymT(sym, min(w, h) * 0.58, r); v.contentMode = .center }
  }
  func renderSO() {
    let w = soX.bounds.width, h = soX.bounds.height; if w < 2 { return }; let sz = min(w, h) * 0.6
    for (btn, sym, col) in [(soX, "xmark", cInk()), (soCheck, "checkmark", cRed())] {
      var iv = btn.viewWithTag(7) as? UIImageView
      if iv == nil { let n = UIImageView(); n.tag = 7; n.contentMode = .center; n.isUserInteractionEnabled = false; btn.addSubview(n); iv = n }
      iv?.frame = btn.bounds; iv?.image = SymT(sym, sz, col.resolvedColor(with: traitCollection))
    }
  }
  func refreshValues() {
    let nm = gUser?["name"] ?? ""; let first = (gUser != nil && !nm.isEmpty) ? (nm.components(separatedBy: " ").first ?? nm) : "You"
    name.text = first.uppercased(); SetCap(email, gUser?["email"] ?? "Guest · L'Art de la Vie", 9.5, cMute())
    let src = nm.isEmpty ? (gUser?["email"] ?? "") : nm; avL.text = gUser != nil && !src.isEmpty ? String(src.prefix(1)).uppercased() : "L"
    let ts = ["circle.lefthalf.filled", "sun.max.fill", "moon.fill"]
    for (k, b) in themeB.enumerated() { if k == 0 { styleTile(b, gAlerts ? "bell.fill" : "bell.slash.fill", gAlerts) } else { styleTile(b, ts[k - 1], b.accessibilityIdentifier == gTheme) } }
    for b in sizeB { styleTile(b, "sil:1", b.accessibilityIdentifier == gSize) }
    for b in iconB { let on = b.accessibilityIdentifier == gIcon; let iv = b.viewWithTag(5); iv?.layer.borderWidth = on ? 3 : 0; iv?.layer.borderColor = cRed().resolvedColor(with: traitCollection).cgColor; iv?.alpha = on ? 1 : 0.3 }
    if footCells.count == 2 { styleTile(footCells[0], "shippingbox.fill", false); styleTile(footCells[1], gUser != nil ? "rectangle.portrait.and.arrow.right" : "person.crop.circle.fill", false) }
  }
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews(); let w = view.bounds.width, h = view.bounds.height, T = view.safeAreaInsets.top, B = view.safeAreaInsets.bottom, small = h < 700
    back.frame = R(16, T + 4, 44, 44); let hy = T + (small ? 12 : 18), av: CGFloat = small ? 50 : 64
    avatar.frame = R(20, hy, av, av); avatar.layer.cornerRadius = av / 2; avL.frame = avatar.bounds; avL.font = Fd(av * 0.53); avDot.frame = R(av * 0.62, av * 0.62, 9, 9)
    name.font = Fd(small ? 44 : 54); name.frame = R(20 + av + 14, hy + 2, w - 40 - av - 14, small ? 40 : 50); email.frame = R(20 + av + 14, hy + (small ? 42 : 54), w - 40 - av - 14, 16)
    let py = hy + av + 14, footH: CGFloat = 26, ph = h - py - B - footH - 18; panel.frame = R(20, py, w - 40, ph); foot.frame = R(0, h - B - footH - 6, w, 16)
    let pw = w - 40, rh0 = ph / 4, pd: CGFloat = 4
    for (k, r) in rows.enumerated() { r.frame = R(0, CGFloat(k) * rh0, pw, rh0) }
    let tw = pw / 4
    for (k, b) in themeB.enumerated() { b.frame = R(CGFloat(k) * tw, pd, tw, rh0 - 2 * pd); renderTile(b) }
    for (k, b) in sizeB.enumerated() { b.frame = R(CGFloat(k) * tw, pd, tw, rh0 - 2 * pd); renderTile(b) }
    let nI = CGFloat(iconB.count), gw = pw / nI, isz = min(gw - 2 * pd, rh0 - 2 * pd)
    for (k, b) in iconB.enumerated() { b.frame = R(CGFloat(k) * gw + (gw - isz) / 2, pd + (rh0 - 2 * pd - isz) / 2, isz, isz); let ivk = b.viewWithTag(5); ivk?.frame = b.bounds; ivk?.layer.cornerRadius = isz * 0.22 }
    let fw = pw / 2; for (q, c) in footCells.enumerated() { c.frame = R(CGFloat(q) * fw, pd, fw, rh0 - 2 * pd); renderTile(c) }
    soLabel.frame = R(16, rh0 + 8, pw - 32, rh0 - 16)
    soX.frame = R(0, 2 * rh0, pw / 2, 2 * rh0); soCheck.frame = R(pw / 2, 2 * rh0, pw / 2, 2 * rh0); renderSO()
  }
}
func OpenProfile() { NotificationCenter.default.post(name: kOpenSettings, object: nil) }
