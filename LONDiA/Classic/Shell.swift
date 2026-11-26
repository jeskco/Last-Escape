// ===== shell: wordmark, splash, root curTab pager, settings card, app delegate (classic) =====
import UIKit
import UIKit.UIGestureRecognizerSubclass
import UserNotifications

let kReplay = Notification.Name("LDReplayIntro")
let kLogoRatio: CGFloat = 345.0 / 1100.0
let kWordRatio: CGFloat = 2.8350515463917527

// two-tone wordmark (ink letters + accent i) fitted to a width
func Lockup(_ w: CGFloat) -> UIView {
  let c = UIView(frame: R(0, 0, w, w * kLogoRatio))
  for (name, tint, tag) in [("logo_ink.png", cInk(), 11), ("logo_red.png", cRed(), 12)] {
    let iv = UIImageView(image: BundleImg(name)?.withRenderingMode(.alwaysTemplate)); iv.tintColor = tint; iv.frame = c.bounds
    iv.autoresizingMask = [.flexibleWidth, .flexibleHeight]; iv.contentMode = .scaleAspectFit; iv.tag = tag; c.addSubview(iv)
  }
  return c
}
func WhiteWordmark(_ w: CGFloat, _ h: CGFloat) -> UIImageView {
  let lw: CGFloat = 204, lh = lw / kWordRatio
  let wm = UIImageView(image: BundleImg("logo_word.png")?.withRenderingMode(.alwaysTemplate)); wm.tintColor = .white; wm.contentMode = .scaleAspectFit
  wm.frame = R((w - lw) / 2, h / 2 - lh / 2, lw, lh); return wm
}

// ---------- first-launch splash ----------
final class SplashView: UIView {
  var go: (() -> Void)?
  override init(frame f: CGRect) {
    super.init(frame: f); backgroundColor = cRed(); clipsToBounds = true
    let w = f.width, h = f.height, si = KeyWin()?.safeAreaInsets ?? .zero
    addSubview(WhiteWordmark(w, h))
    let hint = Cap("Swipe up to discover", 10, .white, .center); hint.frame = R(0, h - si.bottom - 56, w, 16); hint.alpha = 0; addSubview(hint)
    let chev = UILabel(); chev.text = "⌃"; chev.font = .systemFont(ofSize: 22, weight: .light); chev.textColor = .white; chev.textAlignment = .center
    chev.frame = R(0, h - si.bottom - 92, w, 28); chev.alpha = 0; addSubview(chev)
    anim(0.7, delay: 1.7, opts: [.curveEaseOut], { hint.alpha = 1; chev.alpha = 1 }, done: { _ in
      anim(0.9, delay: 0.1, opts: [.repeat, .autoreverse, .curveEaseInOut], { chev.transform = CGAffineTransform(translationX: 0, y: -9); chev.alpha = 0.4 })
    })
    addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(pan(_:))))
    addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(nudge)))
  }
  required init?(coder: NSCoder) { fatalError() }
  @objc func nudge() { anim(0.18, { self.transform = CGAffineTransform(translationX: 0, y: -34) }, done: { _ in spring(0.5, 0.6, { self.transform = .identity }) }) }
  @objc func pan(_ g: UIPanGestureRecognizer) {
    let H = bounds.height, ty = min(0, g.translation(in: superview).y), vy = g.velocity(in: superview).y
    if g.state == .changed { transform = CGAffineTransform(translationX: 0, y: ty) }
    else if g.state == .ended || g.state == .cancelled {
      if ty < -H * 0.18 || vy < -700 { anim(0.32, opts: [.curveEaseOut], { self.transform = CGAffineTransform(translationX: 0, y: -H) }, done: { _ in self.go?() }) }
      else { spring(0.5, 0.75, { self.transform = .identity }) }
    }
  }
}

private var sLastTouch: TimeInterval = 0
private var sIdleUp = false, sSplashUp = false
final class TouchSpy: UIGestureRecognizer {
  override func touchesBegan(_ t: Set<UITouch>, with e: UIEvent) { sLastTouch = Date().timeIntervalSince1970; state = .failed }
}

// ---------- root ----------
final class RootVC: UIViewController, UIScrollViewDelegate {
  var setCard: UIView?, setHost: SettingsHost?; var setVC: ProfileVC?; var setOpenTop: CGFloat = 0
  let top = UIView(); var lockup = UIView(); let pager = UIScrollView(); var screens: [SettingsHost] = []
  let tabBar = UIView(); var tabBtns: [UIButton] = [], tabIcons: [UIImageView] = [], tabLbls: [UILabel] = []
  var badgeS = UILabel(), badgeB = UILabel(), badgeR = UILabel(); var curTab = 0; var launched = false; var obs: [NSObjectProtocol] = []
  let nTabs = 5
  override func viewDidLoad() {
    super.viewDidLoad(); buildAll(); let nc = NotificationCenter.default
    obs.append(nc.addObserver(forName: kChange, object: nil, queue: .main) { [weak self] _ in self?.reloadAll() })
    obs.append(nc.addObserver(forName: kRebuild, object: nil, queue: .main) { [weak self] _ in self?.buildAll(); self?.view.setNeedsLayout(); self?.view.layoutIfNeeded() })
    obs.append(nc.addObserver(forName: kOpenItem, object: nil, queue: .main) { [weak self] n in
      guard let s = self, let iid = n.object as? String else { return }; s.goTab(0, false); (s.screens.first as? FeedView)?.showItem(iid) })
    obs.append(nc.addObserver(forName: kOpenSettings, object: nil, queue: .main) { [weak self] _ in self?.openSettings() })
    obs.append(nc.addObserver(forName: kCloseSettings, object: nil, queue: .main) { [weak self] _ in self?.closeSettings() })
    obs.append(nc.addObserver(forName: kGoTab, object: nil, queue: .main) { [weak self] n in self?.goTab((n.object as? Int) ?? 0, false) })
    obs.append(nc.addObserver(forName: kReplay, object: nil, queue: .main) { [weak self] _ in self?.showSplash() })
    if UD.bool(forKey: "ld_welcomed") { showIdle() } else { showSplash() }
  }
  func buildAll() {
    for v in view.subviews where v !== setCard { v.removeFromSuperview() }
    view.backgroundColor = cBG(); AddArt(view)
    view.addSubview(top); top.subviews.forEach { $0.removeFromSuperview() }
    lockup = Lockup(172); lockup.isUserInteractionEnabled = true; lockup.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(logoTap))); top.addSubview(lockup)
    pager.isPagingEnabled = true; pager.delegate = self; pager.showsHorizontalScrollIndicator = false; pager.bounces = false; pager.contentInsetAdjustmentBehavior = .never; pager.isDirectionalLockEnabled = true
    pager.subviews.forEach { $0.removeFromSuperview() }; view.addSubview(pager)
    screens = [FeedView(frame: .zero), IndexView(frame: .zero), DropsView(frame: .zero), SavedView(frame: .zero), BagView(frame: .zero)]
    screens.forEach { pager.addSubview($0) }
    tabBar.subviews.forEach { $0.removeFromSuperview() }; tabBar.backgroundColor = .clear; view.addSubview(tabBar)
    tabBtns = []; tabIcons = []; tabLbls = []
    for i in 0..<nTabs {
      let b = UIButton(type: .custom); b.tag = i; b.addTarget(self, action: #selector(tabTap(_:)), for: .touchUpInside); tabBar.addSubview(b); tabBtns.append(b)
      let iv = UIImageView(); iv.contentMode = .center; iv.isUserInteractionEnabled = false; b.addSubview(iv); tabIcons.append(iv)
      let l = UILabel(); l.textAlignment = .center; l.isUserInteractionEnabled = false; b.addSubview(l); tabLbls.append(l)
    }
    badgeS = UILabel(); badgeB = UILabel(); badgeR = UILabel()
    for b in [badgeS, badgeB, badgeR] { b.backgroundColor = cRed(); b.textColor = .white; b.font = Fc(9); b.textAlignment = .center; b.layer.cornerRadius = 8; b.layer.masksToBounds = true; b.isUserInteractionEnabled = false; tabBar.addSubview(b) }
    styleTabs(curTab); updateBadges(); if let c = setCard { view.bringSubviewToFront(c) }
  }
  @objc func logoTap() { Hap(1); if setCard != nil { closeSettings() } else { openSettings() } }
  func openSettings() {
    if setCard != nil { return }
    if curTab == 0, let fv = screens.first as? FeedView, fv.exOpen { return }
    if curTab == 1, let iv = screens[1] as? IndexView, iv.ex { return }
    if curTab < screens.count { openSettingsInHost(screens[curTab]) }
  }
  @objc func settingsPan(_ g: UIPanGestureRecognizer) {
    guard let ct = setCard, let host = setHost else { return }
    let tr = g.translation(in: view), v = g.velocity(in: view)
    switch g.state {
    case .began:
      host.settingsRestore(); if let wrap = ct.superview { wrap.superview?.bringSubviewToFront(wrap) }
      if curTab == 0, let fv = host as? FeedView { fv.chips.forEach { $0.alpha = 0 }; fv.dot.alpha = 0 }
    case .changed:
      let maxDown = host.bounds.height - setOpenTop + 40, dy = min(max(0, tr.y), maxDown)
      ct.transform = CGAffineTransform(translationX: 0, y: dy)
      if curTab == 0, let fv = host as? FeedView { let p = min(1, dy / max(1, maxDown)); fv.chips.forEach { $0.alpha = p }; fv.dot.alpha = p }
    case .ended, .cancelled:
      if g.state == .ended && (tr.y > 90 || v.y > 700) { Hap(1); closeSettingsInHost() }
      else { host.settingsMode(true); spring(0.42, 0.86, opts: [.allowUserInteraction], { ct.transform = .identity }) }
    default: break
    }
  }
  func closeSettings() { if setHost != nil { closeSettingsInHost() } }
  func openSettingsInHost(_ host: SettingsHost) {
    var cr: CGRect
    if curTab == 0 { guard let fv = host as? FeedView, let card = fv.card else { return }; cr = fv.convert(card.bounds, from: card); cr.size.height -= fv.bottomInset }
    else if curTab == 1 { cr = R(0, 0, host.bounds.width, host.bounds.height - host.bottomInset) }
    else { cr = R(0, 8, host.bounds.width, host.bounds.height - 8 - host.bottomInset) }
    setOpenTop = cr.origin.y
    let cw = UIView(); cw.tag = 991; cw.frame = cr; cw.clipsToBounds = true; host.addSubview(cw)
    let pv = ProfileVC(); addChild(pv)
    let ct = UIView(); ct.frame = R(0, 0, cr.width, cr.height); ct.backgroundColor = cPanel(); ct.clipsToBounds = true; ct.layer.cornerRadius = 34; ct.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
    let inn = UIView(); inn.frame = ct.bounds; ct.addSubview(inn)
    let sbg = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial)); sbg.frame = inn.bounds; sbg.autoresizingMask = [.flexibleWidth, .flexibleHeight]; inn.addSubview(sbg)
    let stn = UIView(); stn.frame = inn.bounds; stn.autoresizingMask = [.flexibleWidth, .flexibleHeight]; stn.backgroundColor = cTint(); inn.addSubview(stn)
    pv.view.frame = inn.bounds; pv.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]; pv.view.alpha = 0; inn.addSubview(pv.view); cw.addSubview(ct); pv.didMove(toParent: self)
    cw.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(settingsPan(_:))))
    setCard = ct; setVC = pv; setHost = host; pager.isScrollEnabled = false
    host.settingsMode(true)
    ct.transform = CGAffineTransform(translationX: 0, y: cr.height * 0.5)
    spring(0.62, 0.92, opts: [.curveEaseOut], { ct.transform = .identity })
    anim(0.5, delay: 0.12, opts: [.curveEaseOut], { pv.view.alpha = 1 })
  }
  func closeSettingsInHost() {
    guard let ct = setCard, let host = setHost else { return }
    let cw = ct.superview, pv = setVC, down = host.bounds.height - setOpenTop + 40
    setCard = nil; setVC = nil; setHost = nil; pager.isScrollEnabled = true
    host.settingsMode(false)
    anim(0.4, opts: [.curveEaseIn], { ct.transform = CGAffineTransform(translationX: 0, y: down) })
    after(0.41) { pv?.willMove(toParent: nil); pv?.view.removeFromSuperview(); pv?.removeFromParent(); cw?.removeFromSuperview() }
  }
  @objc func tabTap(_ b: UIButton) { if setCard != nil { closeSettings() }; if b.tag != curTab { Hap(1) }; goTab(b.tag, true) }
  func goTab(_ i: Int, _ a: Bool) { let i = max(0, min(nTabs - 1, i)); curTab = i; pager.setContentOffset(CGPoint(x: CGFloat(i) * pager.bounds.width, y: 0), animated: a); styleTabs(i) }
  func styleTabs(_ sel: Int) {
    let names = ["house", "text.alignleft", "drop", "heart", "bag"], fills = ["house.fill", "text.alignleft", "drop.fill", "heart.fill", "bag.fill"], lb = ["Shop", "Index", "Drops", "Saved", "Bag"]
    top.backgroundColor = cPanel()
    for i in 0..<min(nTabs, tabIcons.count) {
      let on = i == sel, c = on ? cInk() : cMute()
      tabIcons[i].image = SymT(on ? fills[i] : names[i], 19, c)
      tabLbls[i].attributedText = NSAttributedString(string: lb[i].uppercased(), attributes: [.font: Fd(11.5), .foregroundColor: c, .kern: 1.2])
    }
  }
  func updateBadges() {
    let ls = [badgeS, badgeB, badgeR], ns = [gSaved.count, BagCount(), RemCount()]
    for k in 0..<3 { ls[k].isHidden = ns[k] == 0; ls[k].text = "\(ns[k])" }; layoutBadges()
  }
  func layoutBadges() {
    guard tabBtns.count == nTabs else { return }
    for (k, l) in [badgeS, badgeB, badgeR].enumerated() {
      let btn = tabBtns[k == 0 ? 3 : k == 1 ? 4 : 2], w = max(16, l.sizeThatFits(CGSize(width: 60, height: 16)).width + 8)
      l.frame = R(btn.frame.origin.x + btn.frame.width / 2 + 4, 8, w, 16)
    }
  }
  func reloadAll() { screens.forEach { $0.reload() }; updateBadges() }
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews(); let W = view.bounds.width, H = view.bounds.height, T = view.safeAreaInsets.top, B = view.safeAreaInsets.bottom
    let topH = T + 56, tabH = 56 + B
    top.frame = R(0, 0, W, topH); lockup.frame = R((W - 172) / 2, T + (56 - 172 * kLogoRatio) / 2 + 1, 172, 172 * kLogoRatio)
    pager.frame = R(0, topH, W, H - topH); pager.contentSize = CGSize(width: W * CGFloat(nTabs), height: H - topH)
    for s in screens { s.bottomInset = tabH; s.setNeedsLayout() }
    for (i, s) in screens.enumerated() { s.frame = R(CGFloat(i) * W, 0, W, H - topH) }
    pager.contentOffset = CGPoint(x: CGFloat(curTab) * W, y: 0)
    tabBar.frame = R(0, H - tabH, W, tabH); let bw = W / CGFloat(nTabs)
    for i in 0..<tabBtns.count { tabBtns[i].frame = R(CGFloat(i) * bw, 0, bw, 56); tabIcons[i].frame = R(0, 9, bw, 24); tabLbls[i].frame = R(0, 34, bw, 16) }
    view.bringSubviewToFront(tabBar); layoutBadges()
  }
  func scrollViewDidScroll(_ s: UIScrollView) {
    guard s === pager, s.bounds.width >= 1 else { return }
    let t = max(0, min(nTabs - 1, Int((s.contentOffset.x / s.bounds.width).rounded())))
    if t != curTab { curTab = t; styleTabs(t); Hap(1) }
  }
  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated); if launched { return }; launched = true
    sLastTouch = Date().timeIntervalSince1970
    let sp = TouchSpy(target: nil, action: nil); sp.cancelsTouchesInView = false; sp.delaysTouchesBegan = false; sp.delaysTouchesEnded = false; view.window?.addGestureRecognizer(sp)
    Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in self?.idleTick() }
    Stamp()
  }
  override var preferredStatusBarStyle: UIStatusBarStyle { sSplashUp ? .lightContent : .default }
  func showSplash() {
    sSplashUp = true; setNeedsStatusBarAppearanceUpdate()
    var sb = view.bounds; if sb.width < 1 { sb = UIScreen.main.bounds }
    let sp = SplashView(frame: sb); sp.autoresizingMask = [.flexibleWidth, .flexibleHeight]; view.addSubview(sp)
    sp.go = { [weak self, weak sp] in
      Hap(2); UD.set(true, forKey: "ld_welcomed"); Stamp()
      anim(0.5, { sp?.alpha = 0 }, done: { _ in sp?.removeFromSuperview(); sSplashUp = false; self?.setNeedsStatusBarAppearanceUpdate() })
    }
  }
  func maybeWelcomeBack() { let last = UD.double(forKey: "ld_last"); if last > 0 && Date().timeIntervalSince1970 - last > 600 { showIdle() }; Stamp() }
  /// brief red wordmark flash shown on launch and after 10 idle minutes
  func showIdle() {
    if sIdleUp || sSplashUp { return }; sIdleUp = true; sSplashUp = true; sLastTouch = Date().timeIntervalSince1970; setNeedsStatusBarAppearanceUpdate()
    presentedViewController?.dismiss(animated: false)
    var bb = view.bounds; if bb.width < 1 { bb = UIScreen.main.bounds }
    let v = UIView(frame: bb); v.autoresizingMask = [.flexibleWidth, .flexibleHeight]; v.backgroundColor = cRed(); view.addSubview(v)
    let wm = WhiteWordmark(bb.width, bb.height); wm.autoresizingMask = [.flexibleLeftMargin, .flexibleRightMargin, .flexibleTopMargin, .flexibleBottomMargin]; v.addSubview(wm)
    anim(0.3, delay: 0.45, opts: [.curveEaseInOut], { v.alpha = 0; wm.transform = CGAffineTransform(scaleX: 1.06, y: 1.06) }, done: { [weak self] _ in
      v.removeFromSuperview(); sIdleUp = false; sSplashUp = false; self?.setNeedsStatusBarAppearanceUpdate() })
  }
  func idleTick() { if !launched || sIdleUp || sSplashUp { return }; if Date().timeIntervalSince1970 - sLastTouch > 600 { showIdle() } }
  func appBecameActive() { if launched { maybeWelcomeBack() } }
}

// ---------- app ----------
@main
final class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {
  var window: UIWindow?; var root: UIViewController?
  func application(_ a: UIApplication, didFinishLaunchingWithOptions o: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
    let w = UIWindow(frame: UIScreen.main.bounds); w.backgroundColor = Hex(0xE10600); window = w
    let pre = UIViewController(); pre.view.backgroundColor = Hex(0xE10600)
    let sz = UIScreen.main.bounds.size; pre.view.addSubview(WhiteWordmark(sz.width, sz.height))
    w.rootViewController = pre; w.makeKeyAndVisible(); CATransaction.flush()
    onMain {
      BootData(); UNUserNotificationCenter.current().delegate = self
      w.backgroundColor = cBG(); w.overrideUserInterfaceStyle = gTheme == "dark" ? .dark : gTheme == "light" ? .light : .unspecified
      #if LD_ADMIN
      self.root = AdminGateVC()
      #else
      self.root = RootVC()
      #endif
      w.rootViewController = self.root
    }
    return true
  }
  func applicationDidBecomeActive(_ a: UIApplication) {
    #if LD_ADMIN
    // admin has no settings screen, so coming back after 10+ minutes away signs out
    let last = UD.double(forKey: "ld_last")
    if gUser != nil && last > 0 && Date().timeIntervalSince1970 - last > 600 { SignOut() }
    Stamp()
    #else
    (root as? RootVC)?.appBecameActive()
    #endif
    if root != nil { SyncCatalog() }
  }
  func applicationWillResignActive(_ a: UIApplication) { Stamp() }
  func userNotificationCenter(_ c: UNUserNotificationCenter, willPresent n: UNNotification, withCompletionHandler h: @escaping (UNNotificationPresentationOptions) -> Void) { h([.banner, .sound]) }
}
