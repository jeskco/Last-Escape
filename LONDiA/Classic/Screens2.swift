// ===== screens part 2: Drops, Saved, Bag (classic) =====
import UIKit

// a plain-text scroll wheel (labels in a scroll view), used instead of UIPickerView so there's no system highlight capsule
final class PlainWheel: UIView, UIScrollViewDelegate {
  let sv = UIScrollView(); var items: [String] = []; var rowH: CGFloat = 40; var selectedIndex = 0
  var fg: UIColor?; var fontSel: UIFont?, fontDim: UIFont?; var rowAlign: NSTextAlignment = .center
  override init(frame f: CGRect) {
    super.init(frame: f); clipsToBounds = true; backgroundColor = .clear
    sv.showsVerticalScrollIndicator = false; sv.decelerationRate = .fast; sv.delegate = self; sv.backgroundColor = .clear; addSubview(sv)
  }
  required init?(coder: NSCoder) { fatalError() }
  override func layoutSubviews() { super.layoutSubviews(); sv.frame = bounds; relayoutRows(); applyOffset(false) }
  func relayoutRows() {
    let w = bounds.width
    for i in 0..<items.count { sv.viewWithTag(2000 + i)?.frame = R(0, CGFloat(i) * rowH, w, rowH) }
    sv.contentSize = CGSize(width: w, height: CGFloat(items.count) * rowH)
  }
  func applyOffset(_ animated: Bool) {
    let inset = max(0, (bounds.height - rowH) / 2); sv.contentInset = UIEdgeInsets(top: inset, left: 0, bottom: inset, right: 0)
    let off = CGPoint(x: 0, y: CGFloat(selectedIndex) * rowH - inset)
    if animated { sv.setContentOffset(off, animated: true) } else { sv.contentOffset = off }
  }
  func setItems(_ items: [String], rowHeight h: CGFloat, selected idx: Int) {
    rowH = h; sv.subviews.forEach { $0.removeFromSuperview() }; self.items = items
    for (i, t) in items.enumerated() { let l = UILabel(); l.text = t; l.textAlignment = rowAlign; l.backgroundColor = .clear; l.tag = 2000 + i; sv.addSubview(l) }
    selectedIndex = max(0, min(items.count - 1, idx)); setNeedsLayout(); layoutIfNeeded(); styleRows()
  }
  func style(fg: UIColor, sel: UIFont, dim: UIFont) { self.fg = fg; fontSel = sel; fontDim = dim; styleRows() }
  func restyle(rowHeight h: CGFloat, sel: UIFont, dim: UIFont) { rowH = h; fontSel = sel; fontDim = dim; relayoutRows(); applyOffset(false); styleRows() }
  func styleRows() {
    for i in 0..<items.count {
      guard let l = sv.viewWithTag(2000 + i) as? UILabel else { continue }
      let on = i == selectedIndex, base = fg ?? .black
      l.textColor = on ? base : base.withAlphaComponent(0.28); l.font = on ? (fontSel ?? Fd(30)) : (fontDim ?? Fd(20))
    }
  }
  func scrollViewDidScroll(_ s: UIScrollView) {
    let idx = max(0, min(items.count - 1, Int(((s.contentOffset.y + s.contentInset.top) / rowH).rounded())))
    if idx != selectedIndex { selectedIndex = idx; styleRows(); Hap(1) }
  }
  func scrollViewWillEndDragging(_ s: UIScrollView, withVelocity v: CGPoint, targetContentOffset t: UnsafeMutablePointer<CGPoint>) {
    let inset = s.contentInset.top; let idx = max(0, min(items.count - 1, Int(((t.pointee.y + inset) / rowH).rounded())))
    t.pointee.y = CGFloat(idx) * rowH - inset
  }
}

final class DropsView: UIView, UIScrollViewDelegate, SettingsHost {
  var pagers: [UIScrollView] = []; let sv = UIView(); var timer: Timer?; var sorted: [Drop] = []
  var slabs: [UIView] = [], ccs: [UIView] = [], ecs: [UIView] = []; var codes: [UILabel] = []; var builtLive: [Bool] = [], pageIdx: [Int] = []
  var expanded = 0; var bottomInset: CGFloat = 0; let pnl = MakePanel(); var selInit = false
  var gM: CGFloat = 0, gW: CGFloat = 0, gCH: CGFloat = 0, gEH: CGFloat = 0, gG: CGFloat = 0
  #if LD_ADMIN
  var editingSlab = -1; var dayWheel: PlainWheel?, monthWheel: PlainWheel?, timeWheel: PlainWheel?; var delBGs: [UIView] = []
  #endif
  override init(frame f: CGRect) {
    super.init(frame: f); backgroundColor = cPanel()
    addSubview(pnl); addSubview(sv)
    timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] t in guard let s = self else { t.invalidate(); return }; s.tick() }
    reload()
  }
  required init?(coder: NSCoder) { fatalError() }
  deinit { timer?.invalidate() }
  override func layoutSubviews() {
    super.layoutSubviews()
    let want = R(0, 20, bounds.width, bounds.height - 20 - bottomInset); pnl.frame = R(0, 8, bounds.width, bounds.height - 8)
    if abs(sv.frame.width - want.width) > 1 || abs(sv.frame.height - want.height) > 1 { sv.frame = want; reload() }
  }
  func itemsFor(_ d: Drop) -> [Item] { gItems.filter { $0.drop == d.did } }
  func tick() { for (q, d) in sorted.enumerated() where q < builtLive.count { if (d.date.timeIntervalSinceNow <= 0) != builtLive[q] { reload(); return } } }
  func applyLayout(_ animated: Bool) {
    var frames: [CGRect] = []; var y: CGFloat = 4
    for q in 0..<slabs.count { let f = R(gM, y, gW, q == expanded ? gEH : gCH); frames.append(f); y += f.height + gG }
    for q in 0..<slabs.count { let e = q == expanded; ccs[q].isUserInteractionEnabled = !e; ecs[q].isUserInteractionEnabled = e }
    let setFrames = {
      for q in 0..<self.slabs.count {
        self.slabs[q].frame = frames[q]
        #if LD_ADMIN
        if q < self.delBGs.count { self.delBGs[q].frame = frames[q] }
        #endif
      }
    }
    if !animated { setFrames(); for q in 0..<slabs.count { let e = q == expanded; ccs[q].alpha = e ? 0 : 1; ecs[q].alpha = e ? 1 : 0 }; return }
    // frame spring and text cross-fade run separately so the fade doesn't ride the spring's bounce
    spring(0.62, 0.86, opts: [.allowUserInteraction], setFrames)
    for q in 0..<slabs.count {
      let e = q == expanded, cc = ccs[q], ec = ecs[q]
      anim(0.22, delay: e ? 0.16 : 0, opts: [.allowUserInteraction], { cc.alpha = e ? 0 : 1; ec.alpha = e ? 1 : 0 })
    }
  }
  func settingsPanel() -> UIView? { pnl }
  func settingsRestore() { sv.alpha = 1; pnl.transform = .identity }
  func settingsMode(_ on: Bool) { anim(0.4, opts: [.allowUserInteraction], { self.sv.alpha = on ? 0 : 1; self.pnl.transform = .identity }) }
  @objc func slabTap(_ g: UITapGestureRecognizer) {
    guard let q = g.view?.tag, q != expanded else { return }; Hap(1)
    #if LD_ADMIN
    closeSwipedSlabs()
    if editingSlab != -1 && editingSlab != q { editingSlab = -1; expanded = q; reload(); return }
    #endif
    expanded = q; applyLayout(true)
  }
  @objc func bellTap(_ g: UITapGestureRecognizer) { guard let q = g.view?.tag, q < sorted.count else { return }; Hap(1); ToggleRemDrop(sorted[q]); reload() }
  @objc func chipTap(_ g: UITapGestureRecognizer) {
    guard let v = g.view, let q = Int(v.accessibilityLabel ?? ""), q < sorted.count else { return }
    let its = itemsFor(sorted[q]); let i = v.tag; guard i < its.count else { return }; Hap(1)
    anim(0.1, { v.transform = CGAffineTransform(scaleX: 0.93, y: 0.93) }, done: { _ in spring(0.3, 0.55, { v.transform = .identity }); OpenItem(its[i]) })
  }
  #if LD_ADMIN
  func closeSwipedSlabs() { for sl in slabs { anim(0.2, { sl.transform = .identity }) } }
  @objc func handleSlabPan(_ g: UIPanGestureRecognizer) {
    guard let sl = g.view else { return }; let q = sl.tag; guard q >= 0 && q < slabs.count else { return }
    let t = g.translation(in: sv)
    switch g.state {
    case .began: for o in slabs where o !== sl { anim(0.2, { o.transform = .identity }) }
    case .changed: if abs(t.x) < abs(t.y) { return }; sl.transform = CGAffineTransform(translationX: min(0, max(-84, t.x)), y: 0)
    case .ended, .cancelled: let open = sl.transform.tx < -50; spring(0.25, 0.9, { sl.transform = open ? CGAffineTransform(translationX: -84, y: 0) : .identity })
    default: break
    }
  }
  @objc func confirmDeleteSlab(_ b: UIButton) {
    let q = b.tag; guard q >= 0 && q < sorted.count, let tv = TopVC() else { return }; Hap(1)
    let d = sorted[q]
    let a = UIAlertController(title: "Delete this drop?", message: "“\(d.nick.isEmpty ? d.name : d.nick)” will be removed. This can't be undone.", preferredStyle: .alert)
    a.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in self?.closeSwipedSlabs() })
    a.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in self?.doDeleteDrop(d) })
    tv.present(a, animated: true)
  }
  func doDeleteDrop(_ d: Drop) {
    let tok = Token(); if tok.isEmpty { Hap(2); closeSwipedSlabs(); return }
    FSDeleteAuth("catalog_drops", d.did, tok) { [weak self] ok in
      guard let s = self else { return }
      if !ok { Hap(2); s.closeSwipedSlabs(); return }
      gDrops.removeAll { $0 === d }; Hap(2); s.editingSlab = -1; s.selInit = false; SyncCatalog(); s.reload()
    }
  }
  @objc func adminToggleDropEdit(_ b: UIButton) {
    let q = b.tag; guard q >= 0 && q < sorted.count else { return }; Hap(1)
    let d = sorted[q]
    if editingSlab != q {
      if dayWheel == nil { dayWheel = PlainWheel() }
      if monthWheel == nil { let m = PlainWheel(); m.rowAlign = .left; monthWheel = m }
      if timeWheel == nil { timeWheel = PlainWheel() }
      let c = Calendar.current.dateComponents([.day, .month, .hour, .minute], from: d.date)
      let mons = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
      let days = (1...31).map { String(format: "%02d", $0) }
      let times: [String] = (0..<96).map { i in let h24 = i / 4, m = (i % 4) * 15; var h12 = h24 % 12; if h12 == 0 { h12 = 12 }; return String(format: "%d:%02d %@", h12, m, h24 < 12 ? "AM" : "PM") }
      dayWheel?.setItems(days, rowHeight: 90, selected: max(0, (c.day ?? 1) - 1))
      monthWheel?.setItems(mons, rowHeight: 56, selected: max(0, (c.month ?? 1) - 1))
      let tIdx = max(0, min(95, Int((Double((c.hour ?? 0) * 60 + (c.minute ?? 0)) / 15).rounded())))
      timeWheel?.setItems(times, rowHeight: 40, selected: tIdx)
      editingSlab = q; reload(); return
    }
    let dayIdx = dayWheel?.selectedIndex ?? 0, monIdx = monthWheel?.selectedIndex ?? 0, tIdx = timeWheel?.selectedIndex ?? 0
    let cal = Calendar.current, now = Date(), year0 = cal.component(.year, from: now)
    // the wheels say nothing about year: try this year, and roll to next year if that moment has already passed
    var newDate: Date?
    for off in 0..<2 {
      let year = year0 + off
      let first = cal.date(from: DateComponents(year: year, month: monIdx + 1, day: 1)) ?? now
      let dim = cal.range(of: .day, in: .month, for: first)?.count ?? 31
      if let cand = cal.date(from: DateComponents(year: year, month: monIdx + 1, day: min(dayIdx + 1, dim), hour: (tIdx * 15) / 60, minute: (tIdx * 15) % 60, second: 0)), cand > now || off == 1 { newDate = cand; break }
    }
    let nd = newDate ?? d.date
    let tok = Token(); if tok.isEmpty { Hap(2); editingSlab = -1; reload(); return }
    FSUpsertAuth("catalog_drops", d.did, ["name": d.name, "nick": d.nick, "date": ISOFromDate(nd)], tok) { [weak self] ok in
      guard let s = self else { return }
      if ok { d.date = nd; Hap(2); SyncCatalog() } else { Hap(2) }
      s.editingSlab = -1; s.reload()
    }
  }
  @objc func adminFullEditDrop(_ g: UILongPressGestureRecognizer) {
    guard g.state == .began, let q = g.view?.tag, q >= 0 && q < sorted.count else { return }; Hap(1)
    editingSlab = -1; gDropTapOverride?(sorted[q])
  }
  @objc func adminAddDropTap() { Hap(1); editingSlab = -1; gDropAddOverride?() }
  #endif
  func reload() {
    let w = sv.bounds.width, H = sv.bounds.height; if w < 10 || H < 100 { return }
    sv.subviews.forEach { $0.removeFromSuperview() }
    sorted = gDrops.sorted { $0.date < $1.date }; let N = sorted.count; if N == 0 { return }
    if !selInit { let ix = NextDrop().flatMap { nd in sorted.firstIndex { $0 === nd } } ?? (N - 1); expanded = max(0, ix); selInit = true }
    expanded = min(expanded, N - 1)
    slabs = []; ccs = []; ecs = []; pagers = []; codes = []; builtLive = []; while pageIdx.count < N { pageIdx.append(0) }
    #if LD_ADMIN
    delBGs = []
    #endif
    let red = cRed(), tc = traitCollection
    let M: CGFloat = 16, g: CGFloat = 10, bot: CGFloat = 12, iw = w - 2 * M
    var ch: CGFloat = 100, eh = H - 4 - bot - CGFloat(N - 1) * ch - CGFloat(N - 1) * g
    if eh < 300 && N > 1 { ch = max(80, ch - (300 - eh) / CGFloat(N - 1)); eh = H - 4 - bot - CGFloat(N - 1) * ch - CGFloat(N - 1) * g }
    // with few drops, cap the expanded card so its piece grid stays proportioned
    let maxEh = max(420, H * 0.62); if eh > maxEh { eh = maxEh }
    #if LD_ADMIN
    if N > 1 { let used = eh + CGFloat(N - 1) * ch + CGFloat(N - 1) * g, avail = H - 4 - bot; if avail > used { ch += (avail - used) / CGFloat(N - 1) } }
    #endif
    let P: CGFloat = 18; gM = M; gW = iw; gCH = ch; gEH = eh; gG = g
    let bgs: [UIColor] = [Hex(0xD8D7D2), Hex(0x75746F), .black], fgs: [UIColor] = [.black, .white, .white]
    for q in 0..<N {
      let d = sorted[q], its = itemsFor(d), up = d.date.timeIntervalSinceNow > 0, ci = q % 3, fg = fgs[ci], mt = fg.withAlphaComponent(0.65)
      builtLive.append(!up)
      #if LD_ADMIN
      do {
        let dbg = UIButton(type: .custom); dbg.backgroundColor = cRed(); dbg.layer.cornerRadius = 28; dbg.clipsToBounds = true; dbg.tag = q
        dbg.setImage(SymT("trash", 24, .white), for: .normal); dbg.contentHorizontalAlignment = .right
        var cfg = UIButton.Configuration.plain(); cfg.image = SymT("trash", 24, .white); cfg.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 30); dbg.configuration = cfg
        dbg.addTarget(self, action: #selector(confirmDeleteSlab(_:)), for: .touchUpInside); sv.addSubview(dbg); delBGs.append(dbg)
      }
      #endif
      let sl = UIView(); sl.backgroundColor = bgs[ci]; sl.layer.cornerRadius = 28; sl.clipsToBounds = true; sl.tag = q; sv.addSubview(sl); slabs.append(sl)
      #if LD_ADMIN
      sl.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(handleSlabPan(_:))))
      #endif
      let mon = up ? Fmt("MMM", d.date).uppercased() : "LIVE", day = up ? Fmt("d", d.date) : "NOW", tm = Fmt("h:mm a", d.date)
      // collapsed: giant date
      let cc = UIView(); cc.frame = R(0, 0, iw, ch); cc.tag = q; cc.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(slabTap(_:)))); sl.addSubview(cc); ccs.append(cc)
      let cn = Cap("\(d.nick)  ·  \(tm)", 9.5, mt, .left); cn.frame = R(P, 14, iw - 2 * P - 90, 14); cc.addSubview(cn)
      let cd = Disp("\(mon) \(day)", ch - 42, fg, .left); cd.adjustsFontSizeToFitWidth = true; cd.minimumScaleFactor = 0.5; cd.frame = R(P, 26, iw - 2 * P - 70, ch - 34); cc.addSubview(cd)
      // expanded: big date + piece codes
      let ec = UIView(); ec.frame = R(0, 0, iw, eh); ec.tag = q; sl.addSubview(ec); ecs.append(ec)
      let nmc = Cap("\(d.nick)  ·  \(up ? tm : "Shop now")", 10, mt, .left); nmc.frame = R(P, P, iw - 2 * P - 56, 14); ec.addSubview(nmc)
      let ml = Disp(mon, 54, fg, .left); ml.frame = R(P, P + 18, iw - 2 * P - 56, 56); ec.addSubview(ml)
      let chipH: CGFloat = 66, cg: CGFloat = 8, chipsH = chipH * 2 + cg, chipsY = eh - P - chipsH
      let areaT = P + 18 + 54, areaB = chipsY - 12, areaH = max(60, areaB - areaT)
      let f100 = Fd(100), capR = f100.capHeight / 100, w100 = max(10, (day as NSString).size(withAttributes: [.font: f100]).width)
      let ds = min(areaH * 0.94 / capR, 100 * (iw - 2 * P) / w100), gf = Fd(ds), gdelta = (gf.ascender - gf.capHeight / 2) - (gf.ascender - gf.descender) / 2
      let dl = Disp(day, ds, fg, .center); dl.frame = R(0, areaT + areaH / 2 - ds / 2 - gdelta, iw, ds); ec.addSubview(dl)
      #if LD_ADMIN
      let isEditingThis = editingSlab == q
      #else
      let isEditingThis = false
      #endif
      if !isEditingThis {
        let nc = min(5, its.count), accC: UIColor = ci == 2 ? .white : red, accTxt: UIColor = ci == 2 ? red : .white
        for k in 0..<nc {
          let r0 = k < 3 ? 0 : 1, inRow = r0 == 0 ? min(3, nc) : nc - 3, col = r0 == 0 ? k : k - 3
          let cwid = (iw - 2 * P - CGFloat(inRow - 1) * cg) / CGFloat(inRow), cx = P + CGFloat(col) * (cwid + cg), cy = chipsY + CGFloat(r0) * (chipH + cg)
          let remOn = RemItem(its[k]); let chip = UIView(); chip.layer.cornerRadius = chipH / 2; chip.backgroundColor = remOn ? accC : fg.withAlphaComponent(0.14); chip.frame = R(cx, cy, cwid, chipH)
          chip.tag = k; chip.accessibilityLabel = "\(q)"; chip.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(chipTap(_:))))
          let cl = Disp(its[k].code, 30, remOn ? accTxt : fg, .center); cl.adjustsFontSizeToFitWidth = true; cl.minimumScaleFactor = 0.5; cl.frame = R(6, 0, cwid - 12, chipH); chip.addSubview(cl); ec.addSubview(chip)
        }
        if nc == 0 { let emp = Cap("No pieces assigned to this drop yet", 10, mt, .center); emp.numberOfLines = 0; emp.frame = R(P, chipsY + 4, iw - 2 * P, chipsH - 4); ec.addSubview(emp) }
      }
      #if LD_ADMIN
      if isEditingThis, let dw = dayWheel, let mw = monthWheel, let tw = timeWheel {
        ml.isHidden = true; dl.isHidden = true
        // the wheels sit exactly over the labels they replace, at the same size, so at rest edit mode looks identical
        dw.frame = R(0, areaT, iw, areaH); ec.addSubview(dw)
        mw.frame = ml.frame; ec.addSubview(mw)
        tw.frame = R(P, chipsY, iw - 2 * P, chipsH); ec.addSubview(tw)
        dw.fg = fg; mw.fg = fg
        dw.restyle(rowHeight: areaH, sel: Fd(ds), dim: Fd(max(34, ds * 0.42)))
        mw.restyle(rowHeight: ml.frame.height, sel: Fd(54), dim: Fd(34))
        tw.style(fg: fg, sel: Fd(26), dim: Fd(18))
      }
      do {
        let B: CGFloat = 48, ey = ml.frame.origin.y + (ml.frame.height - B) / 2
        let edit = UIButton(type: .custom); edit.tag = q; edit.setImage(SymT(isEditingThis ? "checkmark" : "pencil", 17, fg), for: .normal)
        edit.backgroundColor = fg.withAlphaComponent(0.14); edit.layer.cornerRadius = B / 2; edit.frame = R(iw - P - B, ey, B, B)
        edit.addTarget(self, action: #selector(adminToggleDropEdit(_:)), for: .touchUpInside)
        edit.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(adminFullEditDrop(_:)))); ec.addSubview(edit)
        let addB = UIButton(type: .custom); addB.setImage(SymT("plus", 17, fg), for: .normal); addB.backgroundColor = fg.withAlphaComponent(0.14); addB.layer.cornerRadius = B / 2
        addB.frame = R(iw - P - B - 8 - B, ey, B, B); addB.addTarget(self, action: #selector(adminAddDropTap), for: .touchUpInside); ec.addSubview(addB)
      }
      #else
      if up {
        let on = RemDrop(d), bs: CGFloat = 40; let bb = UIView(); bb.tag = q; bb.layer.cornerRadius = bs / 2; bb.frame = R(iw - P - bs, P - 4, bs, bs)
        let acc: UIColor = ci == 2 ? .white : red, onf: UIColor = ci == 2 ? red : .white; var bfg = onf
        if on { bb.backgroundColor = .clear; bb.layer.borderWidth = 2.5; bb.layer.borderColor = acc.resolvedColor(with: tc).cgColor; bfg = acc } else { bb.backgroundColor = acc }
        let bi = UIImageView(image: UIImage(systemName: on ? "bell.fill" : "bell")); bi.tintColor = bfg; bi.contentMode = .scaleAspectFit; bi.frame = R(bs * 0.27, bs * 0.27, bs * 0.46, bs * 0.46); bb.addSubview(bi)
        bb.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(bellTap(_:)))); ec.addSubview(bb)
      }
      #endif
      _ = tc
    }
    applyLayout(false)
  }
}

// ---------- Saved ----------
final class SavedView: UIView, SettingsHost {
  let sv = UIScrollView(); let pnl = MakePanel(); var bottomInset: CGFloat = 0
  override init(frame f: CGRect) {
    super.init(frame: f); backgroundColor = cPanel(); addSubview(pnl)
    sv.showsVerticalScrollIndicator = false; sv.bounces = false; sv.contentInsetAdjustmentBehavior = .never; addSubview(sv); reload()
  }
  required init?(coder: NSCoder) { fatalError() }
  var isEmpty: Bool { !gItems.contains { IsSaved($0.iid) } }
  func wantSV() -> CGRect { let w = bounds.width, h = bounds.height; if isEmpty { let ph = bottomInset + 280; return R(0, h - ph + 16, w, ph - 16) }; return R(0, 24, w, h - 24) }
  func wantPnl() -> CGRect { let w = bounds.width, h = bounds.height; if isEmpty { let ph = bottomInset + 280; return R(0, h - ph, w, ph) }; return R(0, 8, w, h - 8) }
  override func layoutSubviews() { super.layoutSubviews(); let want = wantSV(); pnl.frame = wantPnl(); if abs(sv.frame.width - want.width) > 1 || abs(sv.frame.height - want.height) > 1 { sv.frame = want; reload() } }
  func settingsPanel() -> UIView? { pnl }
  func settingsRestore() { sv.alpha = 1; pnl.transform = .identity }
  func settingsMode(_ on: Bool) { anim(0.4, opts: [.allowUserInteraction], { self.sv.alpha = on ? 0 : 1; self.pnl.transform = .identity }) }
  @objc func openCell(_ c: UIControl) { if let i = ItemById(c.accessibilityIdentifier) { OpenItem(i) } }
  @objc func unheart(_ b: UIButton) { if let i = b.accessibilityIdentifier { ToggleSaved(i) } }
  func reload() {
    let w = bounds.width; if w < 10 { return }
    sv.subviews.forEach { $0.removeFromSuperview() }
    let want = wantSV(), wp = wantPnl(); sv.isScrollEnabled = false; sv.contentInset = .zero
    if sv.frame != want { if sv.frame.height > 1 && window != nil { spring(0.55, 0.86, { self.sv.frame = want; self.pnl.frame = wp }) } else { sv.frame = want; pnl.frame = wp } }
    let its = gItems.filter { IsSaved($0.iid) }; let n = its.count, compact = n > 4
    var y: CGFloat = 0
    let a = Disp("Saved", compact ? 44 : 76, cInk(), .left), b = Disp(Pad(n), compact ? 44 : 76, cRed(), .left)
    if n == 0 {
      let h = want.height - bottomInset, y0 = max(10, (h - 224) / 2)
      a.textAlignment = .center; b.textAlignment = .center; a.frame = R(20, y0, w - 40, 66); b.frame = R(20, y0 + 66, w - 40, 66); sv.addSubview(a); sv.addSubview(b)
      let e = UILabel(); e.numberOfLines = 0; e.textAlignment = .center; e.text = "Tap the heart on any piece\nto keep it here."; e.font = Fm(15); e.textColor = cMute(); e.frame = R(30, y0 + 146, w - 60, 56); sv.addSubview(e)
      sv.contentSize = want.size; return
    }
    if compact { a.frame = R(20, 0, w - 40, 50); b.frame = R(20, 0, w - 40, 50); b.textAlignment = .right; y = 58 } else { a.frame = R(20, 0, w - 40, 66); b.frame = R(20, 66, w - 40, 66); y = 140 }
    sv.addSubview(a); sv.addSubview(b)
    let AH = want.height - bottomInset - 8 - y; var cols = 5; var cw: CGFloat = 0, cellH: CGFloat = 0; let gap: CGFloat = 10
    for c in 2...5 {
      let cwc = (w - 40 - CGFloat(c - 1) * gap) / CGFloat(c), lh: CGFloat = cwc >= 110 ? 58 : 32, chh = cwc * 0.9 + lh + 8, rows = (n + c - 1) / c
      if CGFloat(rows) * chh - 8 <= AH || c == 5 { cols = c; cw = cwc; cellH = chh; break }
    }
    let full = cw >= 110, lh: CGFloat = full ? 58 : 32
    // more than fits: let it scroll instead of clipping
    let rowsTotal = (n + cols - 1) / cols; let contentH = y + CGFloat(rowsTotal) * cellH + bottomInset + 8
    for (k, i) in its.enumerated() {
      let x = 20 + CGFloat(k % cols) * (cw + gap), cy = y + CGFloat(k / cols) * cellH
      let c = UIControl(frame: R(x, cy, cw, cw * 0.9 + lh)); c.accessibilityIdentifier = i.iid; c.addTarget(self, action: #selector(openCell(_:)), for: .touchUpInside)
      let iv = UIImageView(image: TrimImg(Img(i.iid, "med"))); iv.contentMode = .scaleAspectFit; iv.frame = R(0, 0, cw, cw * 0.9); iv.isUserInteractionEnabled = false; c.addSubview(iv)
      let fs = min(26, cw * 0.24); let cd = Disp(i.code, fs, cInk(), .left); cd.frame = R(0, cw * 0.9 + 2, cw, fs + 4); c.addSubview(cd)
      if full { let s = Cap("\(Kind(i)) · \(Money(i.price)) · \(IsLive(i) ? "Out now" : "Drops \(DateShort(DropFor(i).date))")", 8.5, cMute(), .left); s.numberOfLines = 2; s.frame = R(0, cw * 0.9 + 32, cw, 24); c.addSubview(s) }
      let hs = min(36, cw * 0.3); let hb = UIButton(type: .custom); hb.accessibilityIdentifier = i.iid; hb.frame = R(cw - hs, 0, hs, hs); StyleHeart(hb, true)
      hb.addTarget(self, action: #selector(unheart(_:)), for: .touchUpInside); c.addSubview(hb)
      sv.addSubview(c)
    }
    sv.contentSize = CGSize(width: w, height: max(want.height, contentH)); sv.isScrollEnabled = contentH > want.height + 1
  }
}

// ---------- Bag ----------
final class BagView: UIView, SettingsHost {
  var built = CGSize.zero; let sv = UIScrollView(); let pnl = MakePanel(); var bottomInset: CGFloat = 0
  override init(frame f: CGRect) {
    super.init(frame: f); backgroundColor = cPanel(); addSubview(pnl)
    sv.showsVerticalScrollIndicator = false; sv.bounces = false; sv.contentInsetAdjustmentBehavior = .never; addSubview(sv); reload()
  }
  required init?(coder: NSCoder) { fatalError() }
  func wantPnl() -> CGRect { let w = bounds.width, h = bounds.height; if gBag.isEmpty { let ph = bottomInset + 280; return R(0, h - ph, w, ph) }; return R(0, 8, w, h - 8) }
  override func layoutSubviews() { super.layoutSubviews(); pnl.frame = wantPnl(); let b = bounds.size; if abs(b.width - built.width) > 1 || abs(b.height - built.height) > 1 { reload() } }
  func settingsPanel() -> UIView? { pnl }
  func settingsRestore() { for v in subviews where v !== pnl && v.tag != 991 { v.alpha = 1 }; pnl.transform = .identity }
  func settingsMode(_ on: Bool) { anim(0.4, opts: [.allowUserInteraction], { for v in self.subviews where v !== self.pnl && v.tag != 991 { v.alpha = on ? 0 : 1 }; self.pnl.transform = .identity }) }
  func reload() {
    let w = bounds.width, H = bounds.height; if w < 10 || H < 100 { return }
    let off = sv.contentOffset
    for v in subviews where v.tag == 800 { v.removeFromSuperview() }; sv.subviews.forEach { $0.removeFromSuperview() }; built = bounds.size; sv.contentInset = .zero
    let top: CGFloat = 26, empty = gBag.isEmpty, wp = wantPnl()
    if pnl.frame != wp { if pnl.frame.height > 1 && window != nil { spring(0.55, 0.86, { self.pnl.frame = wp }) } else { pnl.frame = wp } }
    let hs = NSMutableAttributedString(string: "YOUR ", attributes: [.font: Fd(56), .foregroundColor: cInk()]); hs.append(NSAttributedString(string: "BAG", attributes: [.font: Fd(56), .foregroundColor: cRed()]))
    let hl = UILabel(); hl.tag = 800; hl.attributedText = hs; hl.frame = R(20, top, w - 40, 62); addSubview(hl)
    if empty {
      sv.isHidden = true; hl.textAlignment = .center; let cy = wp.origin.y + (280 - 110) / 2; hl.frame = R(20, cy, w - 40, 62)
      let e = UILabel(); e.tag = 800; e.numberOfLines = 0; e.textAlignment = .center; e.text = "Pieces you add will wait here."; e.font = Fm(15); e.textColor = cMute(); e.frame = R(30, cy + 70, w - 60, 40); addSubview(e)
      if let cwv = viewWithTag(991) { bringSubviewToFront(cwv) }; return
    }
    sv.isHidden = false; let footH: CGFloat = 150, fb = H - bottomInset - 8, fy = fb - footH, st = top + 66
    let ln = Line(); ln.tag = 800; ln.frame = R(20, fy, w - 40, 0.5); addSubview(ln)
    let sc = Cap("Subtotal", 10, cMute(), .left); sc.tag = 800; sc.frame = R(20, fy + 36, 120, 16); addSubview(sc)
    let sp = Disp(Money(BagTotal()), 48, cInk(), .right); sp.tag = 800; sp.frame = R(w - 20 - 200, fy + 14, 200, 52); addSubview(sp)
    let co = Btn("Checkout", cRed(), .white, 12) { Toast("Checkout connects next"); Hap(2) }; co.tag = 800; co.layer.cornerRadius = 28; co.frame = R(20, fb - 56, w - 40, 56); addSubview(co)
    sv.frame = R(0, st, w, fy - st - 4); var y: CGFloat = 0; let nB = gBag.count, AH = sv.bounds.height
    let rh = max(56, min(100, AH / CGFloat(max(1, nB)))), rs = rh / 100, im = min(84, rh - 14), tx = 20 + im + 12, bs = max(24, 30 * rs)
    for (k, d) in gBag.enumerated() {
      guard let it = ItemById(d.id) else { continue }; let q = d.q
      let iv = UIImageView(image: Img(it.iid, "thumb")); iv.contentMode = .scaleAspectFit; iv.frame = R(20, y + (rh - im) / 2, im, im); sv.addSubview(iv)
      let c = Disp(it.code, 30 * rs + 2, cInk(), .left); c.frame = R(tx, y + (rh - bs - 34 * rs) / 2, w - tx - 100, 32 * rs + 4); sv.addSubview(c)
      let s2 = Cap("\(Kind(it)) · size \(d.size)", 9.5, cMute(), .left); s2.frame = R(tx, c.frame.maxY, w - tx - 100, 14); sv.addSubview(s2)
      let p = Disp(Money(it.price * q), 28 * rs + 2, cInk(), .right); p.frame = R(w - 20 - 90, c.frame.origin.y, 90, 32 * rs + 4); sv.addSubview(p)
      let by = s2.frame.maxY + 4
      let m = Btn("−", cSoft(), cInk(), 16) { BagQty(k, -1) }; m.layer.cornerRadius = bs / 2; m.frame = R(tx, by, bs, bs); sv.addSubview(m)
      let ql = Disp("\(q)", 20 * rs + 2, cInk(), .center); ql.frame = R(tx + bs + 2, by, bs, bs); sv.addSubview(ql)
      let pl = Btn("+", cSoft(), cInk(), 16) { BagQty(k, 1) }; pl.layer.cornerRadius = bs / 2; pl.frame = R(tx + 2 * bs + 4, by, bs, bs); sv.addSubview(pl)
      y += rh
    }
    sv.contentSize = CGSize(width: w, height: y); sv.isScrollEnabled = y > AH + 1
    let mx = max(0, sv.contentSize.height - sv.bounds.height); sv.contentOffset = CGPoint(x: 0, y: min(off.y, mx))
    if let cwv = viewWithTag(991) { bringSubviewToFront(cwv) }
  }
}
