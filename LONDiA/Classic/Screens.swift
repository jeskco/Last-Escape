// ===== screens (classic, faithful port of V326) =====
import UIKit

func spring(_ d: Double, _ damp: CGFloat, delay: Double = 0, opts: UIView.AnimationOptions = [], _ a: @escaping () -> Void, done c: ((Bool) -> Void)? = nil) {
  UIView.animate(withDuration: d, delay: delay, usingSpringWithDamping: damp, initialSpringVelocity: 0, options: opts, animations: a, completion: c)
}
func anim(_ d: Double, delay: Double = 0, opts: UIView.AnimationOptions = [], _ a: @escaping () -> Void, done c: ((Bool) -> Void)? = nil) {
  UIView.animate(withDuration: d, delay: delay, options: opts, animations: a, completion: c)
}

/// Views that the settings card can open over (Feed, Index, Drops, Saved, Bag).
protocol SettingsHost: UIView {
  var bottomInset: CGFloat { get set }
  func settingsPanel() -> UIView?
  func settingsRestore()
  func settingsMode(_ on: Bool)
  func reload()
}

/// Blurred, tinted rounded-top panel used behind most tabs.
func MakePanel() -> UIView {
  let pn = UIView(); pn.layer.cornerRadius = 34; pn.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]; pn.clipsToBounds = true; pn.isUserInteractionEnabled = false
  let bl = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial)); bl.frame = pn.bounds; bl.autoresizingMask = [.flexibleWidth, .flexibleHeight]; pn.addSubview(bl)
  let tn = UIView(); tn.frame = pn.bounds; tn.autoresizingMask = [.flexibleWidth, .flexibleHeight]; tn.backgroundColor = cTint(); pn.addSubview(tn)
  return pn
}

func StyleCTA(_ b: PButton, _ it: Item) {
  if IsLive(it) { b.backgroundColor = cRed(); RetitleBtn(b, "Add to bag", 11.5, .white); return }
  if RemItem(it) { b.backgroundColor = cSoft(); RetitleBtn(b, "Reminder set", 11.5, cInk()) }
  else { b.backgroundColor = cRed(); RetitleBtn(b, "Remind me · \(DateShort(DropFor(it).date))", 11.5, .white) }
}
func CTAAction(_ it: Item) { if IsLive(it) { AddBag(it.iid, gSize); Hap(2) } else { ToggleRemItem(it) } }
func HeartBtn() -> UIButton { let b = UIButton(type: .custom); b.backgroundColor = cSoft(); b.layer.masksToBounds = true; return b }
func StyleHeartL(_ b: UIButton, _ on: Bool) { b.setImage(SymT(on ? "heart.fill" : "heart", 30, on ? cRed() : cInk()), for: .normal) }
func StyleHeart(_ b: UIButton, _ on: Bool) { b.setImage(SymT(on ? "heart.fill" : "heart", 17, on ? cRed() : cInk()), for: .normal) }

private var silCache: [String: UIImage] = [:]
func SilImg(_ k: Int) -> UIImage? {
  let names = ["", "sil_tee.png", "sil_hoodie.png", "sil_pants.png"]; guard k > 0 && k < names.count else { return nil }
  let n = names[k]; if let i = silCache[n] { return i }
  let i = BundleImg(n)?.withRenderingMode(.alwaysTemplate); if let i = i { silCache[n] = i }; return i
}
func SilSize(_ k: Int) -> CGSize { guard let i = SilImg(k) else { return .zero }; let sc = min(30 / i.size.height, 46 / i.size.width); return CGSize(width: i.size.width * sc, height: i.size.height * sc) }

// ---------- Feed ----------
func InnInk() -> UIColor { Dyn(Hex(0x161615), .white) }
final class FeedCard: UIView {
  var item: Item
  let code: UILabel, sub: UILabel, price: UILabel, nameL = UILabel()
  var openState = false, setOpen = false; var inset: CGFloat = 0
  let heart = HeartBtn(); var cta: PButton!; let dock = UIView(), tint = UIView()
  let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
  init(item it: Item) {
    item = it
    code = Disp(it.code, 80, InnInk(), .left); sub = Cap(SubLine(it), 10, InnInk().withAlphaComponent(0.6), .left); price = Disp(Money(it.price), 38, cRed(), .right)
    super.init(frame: .zero)
    dock.backgroundColor = .clear; dock.layer.cornerRadius = 34; dock.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]; dock.clipsToBounds = true; addSubview(dock)
    dock.addSubview(blur)
    tint.isUserInteractionEnabled = false; tint.backgroundColor = cTint(); dock.addSubview(tint)
    code.adjustsFontSizeToFitWidth = true; code.minimumScaleFactor = 0.5; dock.addSubview(code)
    dock.addSubview(sub)
    price.adjustsFontSizeToFitWidth = true; price.minimumScaleFactor = 0.3; price.numberOfLines = 1; dock.addSubview(price)
    heart.backgroundColor = .clear; heart.addTarget(self, action: #selector(heartTap), for: .touchUpInside); dock.addSubview(heart)
    cta = Btn("", cRed(), .white, 11.5) { [weak self] in if let s = self { CTAAction(s.item) } }; dock.addSubview(cta)
    nameL.text = DescFor(it); nameL.font = .systemFont(ofSize: 15, weight: .medium); nameL.textColor = InnInk().withAlphaComponent(0.85); nameL.numberOfLines = 3; nameL.alpha = 0; dock.addSubview(nameL)
    refresh()
  }
  required init?(coder: NSCoder) { fatalError() }
  func showItem(_ it: Item) { item = it; code.text = it.code.uppercased(); SetCap(sub, SubLine(it), 10, InnInk().withAlphaComponent(0.6)); price.text = Money(it.price).uppercased(); nameL.text = DescFor(it); refresh() }
  @objc func heartTap() { ToggleSaved(item.iid) }
  func refresh() {
    let on = IsSaved(item.iid)
    heart.setImage(SymT(on ? "heart.fill" : "heart", 30, on ? cRed() : InnInk()), for: .normal)
    if IsLive(item) { cta.backgroundColor = cRed(); RetitleBtn(cta, "Add to bag", 11.5, .white) }
    else if RemItem(item) { cta.backgroundColor = Dyn(UIColor(white: 0, alpha: 0.1), UIColor(white: 1, alpha: 0.16)); RetitleBtn(cta, "Reminder set", 11.5, InnInk()) }
    else { cta.backgroundColor = cRed(); RetitleBtn(cta, "Remind me · \(DateShort(DropFor(item).date))", 11.5, .white) }
  }
  override func layoutSubviews() {
    let w = bounds.width; var h = bounds.height; let fullH = h; h -= inset; let cf = min(84, h * 0.17)
    if setOpen { dock.frame = R(0, 0, w, fullH); blur.frame = dock.bounds; tint.frame = dock.bounds; return }
    if openState {
      let eh = h, dw = w, P: CGFloat = 18, B: CGFloat = 48, by = eh - 24 - B, cs: CGFloat = 60, pw: CGFloat = 104, infoH = cs * 1.08 + 6 + 66
      let iy: CGFloat = 22, ih2 = max(100, by - 12 - infoH - iy), r = iy + ih2 + 4
      dock.frame = R(0, 0, dw, fullH); blur.frame = dock.bounds; tint.frame = dock.bounds
      code.font = Fd(cs); code.frame = R(P, r, dw - 2 * P - pw - 6, cs * 1.08); price.font = Fd(cs); price.frame = R(dw - P - pw, r, pw, cs * 1.08)
      nameL.frame = R(P + 2, r + cs * 1.08 + 6, dw - 2 * P - 4, 66); sub.frame = R(P + 2, r + cs * 1.08 + 38, dw - 2 * P, 16)
      heart.frame = R(dw - P - B, by, B, B); heart.layer.cornerRadius = B / 2; cta.frame = R(P, by, dw - 2 * P - B - 8, B); cta.layer.cornerRadius = B / 2
      return
    }
    nameL.frame = R(18, 0, 10, 10)
    let bottom = cf + 142, ih = max(80, h - 4 - bottom), top = 4 + ih + 4, bh = h - top
    dock.frame = R(0, top, w, fullH - top)
    let dw = w, P: CGFloat = 18, B: CGFloat = 48, by = bh - 24 - B
    blur.frame = dock.bounds; tint.frame = dock.bounds
    heart.frame = R(dw - P - B, by, B, B); heart.layer.cornerRadius = B / 2
    cta.frame = R(P, by, dw - 2 * P - B - 8, B); cta.layer.cornerRadius = B / 2
    let sy = by - 8 - 16; sub.frame = R(P + 2, sy, dw - 2 * P, 16)
    let pw: CGFloat = 104, ty: CGFloat = 12, ch = sy - 4 - ty, cs = min(cf, ch / 1.08)
    code.font = Fd(cs); code.frame = R(P, ty + (ch - cs * 1.08) / 2, dw - 2 * P - pw - 6, cs * 1.08)
    price.textAlignment = .right; price.font = Fd(cs); price.frame = R(dw - P - pw, ty + (ch - cs * 1.08) / 2, pw, cs * 1.08)
  }
}

func FeedImgRect(_ w: CGFloat, _ h: CGFloat, _ open: Bool) -> CGRect {
  let cf = min(84, h * 0.17)
  if open { let B: CGFloat = 48, by = h - 24 - B, cs: CGFloat = 60, infoH = cs * 1.08 + 6 + 66, iy: CGFloat = 22, ih2 = max(100, by - 12 - infoH - iy); return R(22, iy, w - 44, ih2) }
  let bottom = cf + 142, ih = max(80, h - 4 - bottom); return R(20, 4, w - 56, ih)
}
final class PassView: UIView { override func hitTest(_ p: CGPoint, with e: UIEvent?) -> UIView? { let v = super.hitTest(p, with: e); return v === self ? nil : v } }
final class PgScroll: UIScrollView {
  var passY: CGFloat = 0
  override func point(inside p: CGPoint, with e: UIEvent?) -> Bool { if passY > 0 && p.y - bounds.origin.y >= passY { return false }; return super.point(inside: p, with: e) }
}
final class FeedPage: UIView {
  let item: Item; let iv: UIImageView; var openState = false; var inset: CGFloat = 0; var onTap: (() -> Void)?
  init(item it: Item) {
    item = it; iv = UIImageView(image: TrimImg(Img(it.iid, "med"))); super.init(frame: .zero)
    iv.contentMode = .scaleAspectFit; iv.isUserInteractionEnabled = true; iv.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped))); addSubview(iv)
  }
  required init?(coder: NSCoder) { fatalError() }
  @objc func tapped() { onTap?() }
  override func layoutSubviews() { iv.frame = FeedImgRect(bounds.width, bounds.height - inset, openState) }
}

final class FeedView: UIView, UIScrollViewDelegate, SettingsHost {
  var card: FeedCard?; var exOpen = false; var bottomInset: CGFloat = 0; var cat = "All"; var list: [Item] = []; var chips: [UIButton] = []
  let bar = UIView(), barTint = UIView(), dot = UIView(), ticks = UIView(); let pages = PgScroll()
  var pgs: [FeedPage] = []; var cur = 0
  let hd = UIView(), win = PassView()
  let cats = ["All", "Tees", "Hoodies", "Pants"]
  override init(frame f: CGRect) {
    super.init(frame: f)
    for i in 0..<4 { let b = UIButton(type: .custom); b.tag = i; b.addTarget(self, action: #selector(chip(_:)), for: .touchUpInside); addSubview(b); chips.append(b) }
    bar.clipsToBounds = true; bar.isUserInteractionEnabled = false; insertSubview(bar, at: 0)
    barTint.backgroundColor = cPanel(); bar.addSubview(barTint)
    dot.layer.cornerRadius = 1.5; dot.isUserInteractionEnabled = false; insertSubview(dot, aboveSubview: bar)
    pages.isPagingEnabled = true; pages.showsVerticalScrollIndicator = false; pages.bounces = false; pages.delegate = self; pages.contentInsetAdjustmentBehavior = .never
    hd.clipsToBounds = true; addSubview(hd); win.clipsToBounds = true; hd.addSubview(win); win.addSubview(pages); pages.clipsToBounds = true
    ticks.isUserInteractionEnabled = false; ticks.isHidden = true; addSubview(ticks)
    rebuild()
  }
  required init?(coder: NSCoder) { fatalError() }
  @objc func chip(_ b: UIButton) {
    let c = cats[b.tag]; if c == cat { return }
    cat = c; cur = 0; Hap(1); let old = dot.frame; rebuild(); setNeedsLayout(); layoutIfNeeded(); let nf = dot.frame
    if old.width > 1 { dot.frame = old; spring(0.34, 0.82, { self.dot.frame = nf }) }
  }
  func rebuild() {
    var l = gItems.filter { cat == "All" || $0.cat == cat }
    if cat == "All" {
      var by: [String: [Item]] = ["Tees": [], "Hoodies": [], "Pants": []]
      for i in l { by[i.cat, default: []].append(i) }
      let maxN = by.values.map(\.count).max() ?? 0; var o: [Item] = []
      for k in 0..<maxN { for c in ["Hoodies", "Tees", "Pants"] { if let a = by[c], k < a.count { o.append(a[k]) } } }
      // anything in an unrecognised category still shows up at the end
      o.append(contentsOf: l.filter { !["Tees", "Hoodies", "Pants"].contains($0.cat) })
      l = o
    }
    list = l
    pgs.forEach { $0.removeFromSuperview() }; pgs.removeAll()
    for i in l { let p = FeedPage(item: i); p.onTap = { [weak self] in self?.toggleEx() }; pages.addSubview(p); pgs.append(p) }
    if card == nil, let first = l.first { let c = FeedCard(item: first); hd.insertSubview(c, belowSubview: win); card = c }
    exOpen = false; chips.forEach { $0.alpha = 1 }; dot.alpha = 1; pages.isScrollEnabled = true
    card?.openState = false; card?.nameL.alpha = 0; card?.sub.alpha = 1
    for k in 0..<chips.count {
      let b = chips[k]; let on = cats[k] == cat
      if k == 0 { styleAll() }
      else {
        var iv = b.viewWithTag(55) as? UIImageView
        if iv == nil { let n = UIImageView(); n.tag = 55; n.contentMode = .scaleAspectFit; n.isUserInteractionEnabled = false; b.addSubview(n); iv = n }
        iv?.image = SilImg(k); iv?.tintColor = on ? InnInk() : InnInk().withAlphaComponent(0.45)
      }
    }
    dot.backgroundColor = cRed()
  }
  func styleAll() {
    let on = cat == "All"
    chips[0].setAttributedTitle(NSAttributedString(string: "ALL", attributes: [.font: Fd(27), .foregroundColor: on ? InnInk() : InnInk().withAlphaComponent(0.45), .kern: 0.7]), for: .normal)
  }
  override func traitCollectionDidChange(_ p: UITraitCollection?) { super.traitCollectionDidChange(p); rebuildStyle() }
  func rebuildStyle() {
    styleAll()
    for k in 1..<chips.count { let on = cats[k] == cat; (chips[k].viewWithTag(55) as? UIImageView)?.tintColor = on ? InnInk() : InnInk().withAlphaComponent(0.45) }
    setNeedsLayout()
  }
  func showItem(_ iid: String) {
    if cat != "All" { cat = "All"; cur = 0; rebuild() }
    setNeedsLayout(); layoutIfNeeded()
    guard let idx = list.firstIndex(where: { $0.iid == iid }) else { return }
    let ph = pages.bounds.height
    if exOpen { if idx != cur { cur = idx; pages.setContentOffset(CGPoint(x: 0, y: ph * CGFloat(idx)), animated: false); updateMeta() }; return }
    pages.isScrollEnabled = true; cur = idx; pages.setContentOffset(CGPoint(x: 0, y: ph * CGFloat(idx)), animated: false); updateMeta()
    after(0.3) { [weak self] in self?.expandTo(true) }
  }
  func toggleEx() { Hap(1); expandTo(!exOpen) }
  func settingsPanel() -> UIView? { card?.dock }
  func applySettings(_ on: Bool) {
    guard let cd = card else { return }
    cd.setOpen = on; let ex = exOpen
    cd.setNeedsLayout(); cd.layoutIfNeeded(); cd.dock.transform = .identity
    pages.alpha = on ? 0 : 1; chips.forEach { $0.alpha = (on || ex) ? 0 : 1 }; dot.alpha = (on || ex) ? 0 : 1
    let a: CGFloat = on ? 0 : 1; cd.code.alpha = a; cd.price.alpha = a; cd.heart.alpha = a; cd.cta.alpha = a
    cd.sub.alpha = on ? 0 : (ex ? 0 : 1); cd.nameL.alpha = on ? 0 : (ex ? 1 : 0)
  }
  func settingsRestore() { applySettings(false) }
  func settingsMode(_ on: Bool) { spring(0.55, 0.86, opts: [.allowUserInteraction], { self.applySettings(on) }) }
  func updatePass() { let ph = pages.bounds.height; let r = FeedImgRect(pages.bounds.width, ph - bottomInset, exOpen); pages.passY = r.maxY + (exOpen ? 0 : 4) }
  func windowFrame(_ open: Bool) -> CGRect {
    let pwh = bounds.height - 66, wc = FeedImgRect(bounds.width, pwh - bottomInset, false).maxY + 4
    return R(0, 66, bounds.width, open ? pwh : wc)
  }
  func expandTo(_ o: Bool) {
    guard !pgs.isEmpty, let cd = card else { return }
    exOpen = o; pages.isScrollEnabled = !o; updatePass()
    let pg = pgs[max(0, min(cur, pgs.count - 1))]
    spring(0.78, 0.95, opts: [.allowUserInteraction], {
      self.win.frame = self.windowFrame(o)
      cd.openState = o; cd.setNeedsLayout(); cd.layoutIfNeeded(); pg.openState = o; pg.setNeedsLayout(); pg.layoutIfNeeded()
      self.chips.forEach { $0.alpha = o ? 0 : 1 }; self.dot.alpha = o ? 0 : 1
    })
    anim(0.4, delay: o ? 0.22 : 0, opts: [.curveEaseOut], { cd.nameL.alpha = o ? 1 : 0; cd.sub.alpha = o ? 0 : 1 })
  }
  func syncCard() {
    guard !list.isEmpty, let cd = card else { return }
    let it = list[max(0, min(cur, list.count - 1))]
    if cd.item.iid != it.iid { UIView.transition(with: cd, duration: 0.22, options: [.transitionCrossDissolve, .allowUserInteraction], animations: { cd.showItem(it) }) } else { cd.showItem(it) }
  }
  func reload() { card?.refresh(); updateMeta() }
  func updateMeta() { if list.isEmpty { return }; styleAll(); syncCard() }
  override func layoutSubviews() {
    super.layoutSubviews(); let w = bounds.width, h = bounds.height
    bar.frame = R(0, 0, w, h); barTint.frame = bar.bounds
    let cw = w / 4
    for k in 0..<chips.count {
      chips[k].frame = R(CGFloat(k) * cw, 14, cw, 48); let on = cats[k] == cat
      if k > 0 { let z = SilSize(k); (chips[k].viewWithTag(55) as? UIImageView)?.frame = R((cw - z.width) / 2, (52 - z.height) / 2 - 2, z.width, z.height) }
      if on { dot.frame = R(CGFloat(k) * cw + (cw - 30) / 2, 62 - 6, 30, 3) }
    }
    let py: CGFloat = 66, ph = h - py
    hd.frame = R(0, 0, w, h); pages.frame = R(0, 0, w, ph); win.frame = windowFrame(exOpen)
    chips.forEach { bringSubviewToFront($0) }; bringSubviewToFront(dot)
    pages.contentSize = CGSize(width: w, height: ph * CGFloat(pgs.count))
    card?.inset = bottomInset; card?.frame = R(0, py, w, ph)
    for (k, p) in pgs.enumerated() { p.inset = bottomInset; p.frame = R(0, ph * CGFloat(k), w, ph) }
    updatePass()
    pages.setContentOffset(CGPoint(x: 0, y: ph * CGFloat(cur)), animated: false)
    updateMeta()
  }
  func scrollViewDidScroll(_ s: UIScrollView) {
    let ph = s.bounds.height; if ph < 1 { return }
    let i = max(0, min(Int((s.contentOffset.y / ph).rounded()), list.count - 1))
    if i != cur { cur = i; Hap(1); updateMeta() }
  }
  /// Top of the collapsed product dock (used by the settings card so it grows out of the dock).
  func collapsedTop() -> CGFloat { let h = bounds.height, py: CGFloat = 66, ph = h - py, hEff = ph - bottomInset, cf = min(84, hEff * 0.17), ih = max(80, hEff - 4 - (cf + 142)); return py + 4 + ih + 4 }
}

// ---------- Index (deck, vertical pages) ----------
final class IndexView: UIView, UIScrollViewDelegate, SettingsHost {
  var ex = false; var pnl = UIView(); let dDesc = UILabel(); var vb: PButton!
  var gPY0: CGFloat = 0, gDTop: CGFloat = 0, gDh: CGFloat = 0, gDhE: CGFloat = 0, gTextY: CGFloat = 0, gTextYE: CGFloat = 0
  var bottomInset: CGFloat = 0, gBtnY: CGFloat = 0, gBtnYc: CGFloat = 0, gDTopE: CGFloat = 0, gPnlE: CGFloat = 0
  var sel = 0; var num = UILabel(), of = UILabel(); var heart: UIButton?; var built = CGSize.zero
  var deck: UIScrollView?; var code = UILabel(); var segs: [UIView] = []; var grp: [UILabel] = []; var curI = -1; var pageH: CGFloat = 1
  var count: Int { gItems.count }
  override init(frame f: CGRect) { super.init(frame: f) }
  required init?(coder: NSCoder) { fatalError() }
  func reload() {
    if count != deckCount { built = .zero; setNeedsLayout(); return }
    guard curI >= 0, curI < count, let heart = heart else { return }
    let it = gItems[curI]; StyleHeartL(heart, IsSaved(it.iid)); code.text = it.code.uppercased()
    if ex { StyleCTA(vb, it); dDesc.text = DescFor(it) }
  }
  var deckCount = 0
  func expandTo(_ o: Bool) {
    guard let deck = deck, curI >= 0, curI < count, o != ex else { return }
    ex = o; let it = gItems[curI]; let W = bounds.width, FH = bounds.height
    if o { dDesc.text = DescFor(it); StyleCTA(vb, it) } else { vb.backgroundColor = cRed(); RetitleBtn(vb, "View", 11.5, .white) }
    deck.isScrollEnabled = !o; code.textAlignment = o ? .left : .center; let dh = o ? gDhE : gDh; pageH = dh
    spring(0.78, 0.95, opts: [.allowUserInteraction], {
      self.pnl.frame = o ? R(0, self.gPnlE, W, FH - self.gPnlE) : R(0, self.gPY0, W, FH - self.gPY0)
      deck.frame = R(0, o ? self.gDTopE : self.gDTop, W, dh); deck.contentSize = CGSize(width: W, height: dh * CGFloat(self.deckCount))
      for v in deck.subviews where v is UIImageView { v.bounds = R(0, 0, W, dh); v.center = CGPoint(x: W / 2, y: CGFloat(v.tag) * dh + dh / 2) }
      deck.contentOffset = CGPoint(x: 0, y: CGFloat(max(0, min(self.deckCount - 1, self.curI))) * dh)
      self.code.frame = R(o ? 18 : 20, o ? self.gTextYE : self.gTextY, W - 40, o ? 65 : 60)
      self.heart?.frame = o ? R(W - 18 - 48, self.gBtnY, 48, 48) : R(W - 16 - 64, 13, 64, 64)
      self.vb.frame = o ? R(18, self.gBtnY, W - 36 - 56, 48) : R(20, self.gBtnYc, W - 40, 52)
    })
    anim(0.4, delay: o ? 0.22 : 0, opts: [.curveEaseOut], {
      self.dDesc.alpha = o ? 1 : 0; self.num.alpha = o ? 0 : 1; self.of.alpha = o ? 0 : 1
      self.grp.forEach { $0.alpha = o ? 0 : 1 }; self.segs.forEach { $0.superview?.alpha = o ? 0 : 1 }
    })
  }
  func settingsPanel() -> UIView? { pnl }
  func applySettings(_ on: Bool) {
    let W = bounds.width, FH = bounds.height
    pnl.frame = on ? R(0, 0, W, FH) : (ex ? R(0, gPnlE, W, FH - gPnlE) : R(0, gPY0, W, FH - gPY0)); pnl.transform = .identity
    for v in subviews where v !== pnl && v.tag != 991 { v.alpha = on ? 0 : 1 }
    if !on { dDesc.alpha = ex ? 1 : 0; num.alpha = ex ? 0 : 1; of.alpha = ex ? 0 : 1; grp.forEach { $0.alpha = ex ? 0 : 1 }; segs.forEach { $0.superview?.alpha = ex ? 0 : 1 } }
  }
  func settingsRestore() { applySettings(false) }
  func settingsMode(_ on: Bool) { spring(0.55, 0.86, opts: [.allowUserInteraction], { self.applySettings(on) }) }
  @objc func heartTap() { if curI >= 0 && curI < count { ToggleSaved(gItems[curI].iid) } }
  func deckGo(_ i: Int, _ a: Bool) { deck?.setContentOffset(CGPoint(x: 0, y: CGFloat(max(0, min(deckCount - 1, i))) * pageH), animated: a) }
  @objc func deckCard(_ g: UITapGestureRecognizer) { guard let k = g.view?.tag else { return }; if k == curI { Hap(1); expandTo(!ex) } else if !ex { Hap(1); deckGo(k, true) } }
  @objc func deckSeg(_ b: UIButton) { Hap(1); deckGo(b.tag - 900, true) }
  func deckOpen() { if curI < 0 || curI >= count { return }; if ex { CTAAction(gItems[curI]) } else { Hap(1); expandTo(true) } }
  func deckFx() {
    guard let deck = deck, pageH >= 1, deckCount > 0 else { return }
    let n = Int(Cl((deck.contentOffset.y / pageH).rounded(), 0, CGFloat(deckCount - 1))); if n == curI { return }
    let first = curI < 0; curI = n; sel = n; let it = gItems[n]
    if !first && (deck.isDragging || deck.isDecelerating) { Hap(1) }
    num.text = Pad(n + 1); if let h = heart { StyleHeartL(h, IsSaved(it.iid)) }
    code.text = it.code.uppercased()
    for (k, s) in segs.enumerated() { s.backgroundColor = k == n ? cRed() : (k / 5 == n / 5 ? cInk() : cLine()) }
    for (k, g) in grp.enumerated() { g.textColor = k == n / 5 ? cInk() : cMute() }
  }
  func buildDeck() {
    let W = bounds.width; var H = bounds.height; let FH = H; H -= bottomInset; backgroundColor = cPanel()
    let n = count; deckCount = n
    let keep = max(0, min(n - 1, sel)); ex = false; subviews.forEach { $0.removeFromSuperview() }; curI = -1; built = bounds.size
    num = Disp(Pad(keep + 1), 64, cInk(), .left); num.frame = R(20, 16, 90, 58); addSubview(num)
    of = Cap("/ \(n)", 11, cMute(), .left); of.frame = R(20 + num.sizeThatFits(CGSize(width: 200, height: 60)).width + 4, 50, 60, 16); addSubview(of)
    let ht = HeartBtn(); ht.backgroundColor = .clear; ht.layer.cornerRadius = 0; ht.frame = R(W - 16 - 64, 13, 64, 64); ht.addTarget(self, action: #selector(heartTap), for: .touchUpInside); addSubview(ht); heart = ht
    let bot = H - 14, btnY = bot - 52, tickY = btnY - 26, grpY = tickY - 18, dTop: CGFloat = 50, cfI = min(84, (H - 66) * 0.17), pyF = H - cfI - 138
    let textY = pyF + 22, dh = max(130, pyF - 4 - dTop)
    let pn = MakePanel(); pn.frame = R(0, pyF, W, FH - pyF); pnl = pn; gPY0 = pyF; insertSubview(pn, at: 0)
    pageH = dh
    let dk = UIScrollView(frame: R(0, dTop, W, dh)); deck = dk; dk.delegate = self; dk.isPagingEnabled = true; dk.showsVerticalScrollIndicator = false; dk.bounces = false; dk.clipsToBounds = true; clipsToBounds = true
    gDTop = dTop; gDh = dh; gTextY = textY; dk.contentInsetAdjustmentBehavior = .never; dk.contentSize = CGSize(width: W, height: dh * CGFloat(n)); addSubview(dk)
    bringSubviewToFront(num); bringSubviewToFront(of); bringSubviewToFront(ht)
    for k in 0..<n {
      let iv = UIImageView(image: TrimImg(Img(gItems[k].iid, "med"))); iv.contentMode = .scaleAspectFit; iv.tag = k; iv.frame = R(0, CGFloat(k) * dh, W, dh)
      iv.isUserInteractionEnabled = true; iv.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(deckCard(_:)))); dk.addSubview(iv)
    }
    code = Disp("", 56, cInk(), .center); code.adjustsFontSizeToFitWidth = true; code.frame = R(20, textY, W - 40, 60); addSubview(code)
    do {
      let py: CGFloat = 66, eh = H - py, B: CGFloat = 48, by = eh - 24 - B, cs: CGFloat = 60, infoH = cs * 1.08 + 6 + 66, iy: CGFloat = 22, ih2 = max(100, by - 12 - infoH - iy), r = iy + ih2 + 4
      gBtnY = py + by; gBtnYc = btnY; gDTopE = py + iy; gDhE = ih2; gTextYE = py + r; gPnlE = py
      dDesc.font = .systemFont(ofSize: 15, weight: .medium); dDesc.textColor = cInk().withAlphaComponent(0.8); dDesc.textAlignment = .left; dDesc.numberOfLines = 2
      dDesc.frame = R(20, py + r + cs * 1.08 + 6, W - 40, 66); dDesc.alpha = 0; addSubview(dDesc)
    }
    segs = []; grp = []
    let gg: CGFloat = 14, gw = (W - 40 - 2 * gg) / 3, sg: CGFloat = 3, sw = (gw - 4 * sg) / 5; let gn = ["Tees", "Hoodies", "Pants"]
    for g in 0..<3 {
      let gl = Cap(gn[g], 9, cMute(), .left); gl.frame = R(20 + CGFloat(g) * (gw + gg), grpY, gw, 14); addSubview(gl); grp.append(gl)
      for k in 0..<5 {
        let gi = g * 5 + k; if gi >= n { break }
        let hb = UIButton(type: .custom); hb.tag = 900 + gi; hb.frame = R(20 + CGFloat(g) * (gw + gg) + CGFloat(k) * (sw + sg), tickY - 12, sw + sg, 30)
        hb.addTarget(self, action: #selector(deckSeg(_:)), for: .touchUpInside); addSubview(hb)
        let sv = UIView(); sv.isUserInteractionEnabled = false; sv.frame = R(0, 13, sw, 3); sv.layer.cornerRadius = 1.5; hb.addSubview(sv); segs.append(sv)
      }
    }
    let b = Btn("View", cRed(), .white, 11.5) { [weak self] in self?.deckOpen() }; b.layer.cornerRadius = 26; b.frame = R(20, btnY, W - 40, 52); addSubview(b); vb = b
    sel = keep; refreshDeck()
    onMain { self.refreshDeck() }
  }
  func refreshDeck() {
    guard let deck = deck, !deck.isDragging, !deck.isDecelerating else { return }
    deck.setContentOffset(CGPoint(x: 0, y: CGFloat(max(0, min(deckCount - 1, sel))) * pageH), animated: false); curI = -1; deckFx()
  }
  override func didMoveToWindow() { super.didMoveToWindow(); if window != nil { refreshDeck() } }
  override func layoutSubviews() {
    super.layoutSubviews(); let b = bounds.size; if b.width < 10 || b.height < 10 { return }
    if abs(b.width - built.width) > 1 || abs(b.height - built.height) > 1 || deckCount != count { buildDeck() } else { refreshDeck() }
  }
  func scrollViewDidScroll(_ s: UIScrollView) { if s === deck { deckFx() } }
}
