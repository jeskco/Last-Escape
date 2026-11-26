// ===== LONDiA ADMIN (classic): catalog editor on the same Firebase backend =====
#if LD_ADMIN
import UIKit
import PhotosUI

func AField(_ ph: String) -> UITextField {
  let f = UITextField(); f.backgroundColor = cSoft(); f.layer.cornerRadius = 14; f.font = Fm(16); f.textColor = cInk(); f.tintColor = cRed()
  f.attributedPlaceholder = NSAttributedString(string: ph, attributes: [.foregroundColor: cMute(), .font: Fm(16)])
  f.leftView = UIView(frame: R(0, 0, 16, 10)); f.leftViewMode = .always; f.autocorrectionType = .no; f.autocapitalizationType = .none
  return f
}
func AHead(_ t: String) -> UILabel { let l = UILabel(); l.text = t.uppercased(); l.font = Fc(11); l.textColor = cMute(); return l }
func AChips(_ opts: [String], _ target: Any, _ sel: Selector) -> [UIButton] {
  opts.enumerated().map { i, o in let b = UIButton(type: .custom); b.tag = i; b.accessibilityLabel = o; b.layer.cornerRadius = 14; b.titleLabel?.font = Fm(13); b.addTarget(target, action: sel, for: .touchUpInside); return b }
}
func StyleChips(_ bs: [UIButton], _ sel: Int) {
  for b in bs { let on = b.tag == sel; b.backgroundColor = on ? cRed() : cSoft(); b.setTitleColor(on ? .white : cInk(), for: .normal); b.setTitle((b.accessibilityLabel ?? "").uppercased(), for: .normal) }
}
// the font size UILabel's adjustsFontSizeToFitWidth would land on, so a wheel can match a static label exactly
func FitDispFontSize(_ text: String, _ maxPt: CGFloat, _ minScale: CGFloat, _ maxW: CGFloat) -> CGFloat {
  let t = text.uppercased() as NSString, minPt = maxPt * minScale; var s = maxPt
  while s >= minPt { if t.size(withAttributes: [.font: Fd(s)]).width <= maxW { return s }; s -= 0.5 }
  return minPt
}
func LoadPicked(_ results: [PHPickerResult], _ cb: @escaping (UIImage?, String?) -> Void) {
  guard let r = results.first else { return }
  guard r.itemProvider.canLoadObject(ofClass: UIImage.self) else { cb(nil, "That file isn't a photo this app can use."); return }
  r.itemProvider.loadObject(ofClass: UIImage.self) { obj, err in
    let im = obj as? UIImage
    onMain { if let im = im { cb(im, nil) } else { cb(nil, (err?.localizedDescription).flatMap { $0.isEmpty ? nil : $0 } ?? "Couldn't load that photo — try a different one (or a non-iCloud copy).") } }
  }
}
func PhotoPicker(_ delegate: PHPickerViewControllerDelegate) -> PHPickerViewController {
  var cfg = PHPickerConfiguration(); cfg.selectionLimit = 1; cfg.filter = .images
  let p = PHPickerViewController(configuration: cfg); p.delegate = delegate; return p
}

// ---------- sign in ----------
final class AdminSignInVC: UIViewController, UITextFieldDelegate {
  var signup = false; let sv = UIScrollView(); let t1 = Disp("LONDiA", 54, cInk(), .left), t2 = Disp("ADMIN", 54, cRed(), .left), err = UILabel()
  var fields: [UITextField] = []; var go: PButton!; let swap = UIButton(type: .custom)
  override func viewDidLoad() {
    super.viewDidLoad(); view.backgroundColor = cBG()
    sv.keyboardDismissMode = .interactive; sv.contentInsetAdjustmentBehavior = .never; view.addSubview(sv); sv.addSubview(t1); sv.addSubview(t2)
    for (i, ph) in ["Email", "Password (6+ characters)"].enumerated() {
      let f = AField(ph); f.delegate = self; f.tag = i; if i == 0 { f.keyboardType = .emailAddress } else { f.isSecureTextEntry = true }
      f.returnKeyType = i == 0 ? .next : .go; sv.addSubview(f); fields.append(f)
    }
    err.font = Fm(13); err.textColor = cRed(); err.numberOfLines = 2; sv.addSubview(err)
    go = Btn("Sign in", cRed(), .white, 12) { [weak self] in self?.submit() }; go.layer.cornerRadius = 28; sv.addSubview(go)
    swap.addTarget(self, action: #selector(toggle), for: .touchUpInside); sv.addSubview(swap); mode()
    NotificationCenter.default.addObserver(self, selector: #selector(kb(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
  }
  deinit { NotificationCenter.default.removeObserver(self) }
  @objc func kb(_ n: Notification) { guard let f = (n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else { return }; sv.contentInset.bottom = max(0, view.bounds.height - view.convert(f, from: nil).origin.y) }
  @objc func toggle() { signup.toggle(); err.text = ""; Hap(1); mode() }
  func mode() {
    RetitleBtn(go, signup ? "Create admin account" : "Sign in", 12, .white)
    swap.setAttributedTitle(NSAttributedString(string: signup ? "Already have it? Sign in" : "First time? Create the account", attributes: [.font: Fc(12), .foregroundColor: cRed()]), for: .normal)
  }
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews(); let w = view.bounds.width, T = view.safeAreaInsets.top; sv.frame = R(0, 0, w, view.bounds.height)
    var y = T + 40; t1.frame = R(20, y, w - 40, 60); y += 52; t2.frame = R(20, y, w - 40, 60); y += 78
    fields[0].frame = R(20, y, w - 40, 52); y += 62; fields[1].frame = R(20, y, w - 40, 52); y += 62
    err.frame = R(20, y, w - 40, 34); y += 38; go.frame = R(20, y, w - 40, 56); y += 64; swap.frame = R(20, y, w - 40, 40); y += 48; sv.contentSize = CGSize(width: w, height: y + 20)
  }
  func textFieldShouldReturn(_ f: UITextField) -> Bool { if f.tag == 0 { fields[1].becomeFirstResponder() } else { submit() }; return true }
  func fail(_ m: String) { err.text = m; Hap(2); go.isEnabled = true; go.alpha = 1; mode() }
  func submit() {
    if !go.isEnabled { return }
    let email = (fields[0].text ?? "").trimmingCharacters(in: .whitespaces).lowercased(), pw = fields[1].text ?? ""
    if !email.contains("@") { fail("Enter a valid email."); return }; if pw.count < 6 { fail("Password needs 6+ characters."); return }
    err.text = ""; go.isEnabled = false; go.alpha = 0.5; RetitleBtn(go, "Please wait…", 12, .white)
    let handle: (JSON?, String?) -> Void = { [weak self] json, e in
      guard let s = self else { return }; if let e = e { s.fail(e); return }; guard let j = json else { return }
      let (_, uid) = StoreAuth(j); gUser = ["name": "Admin", "email": email, "uid": uid]; Changed(); Hap(2); s.view.endEditing(true)
    }
    if signup { FBSignUp(email, pw, handle) } else { FBSignIn(email, pw, handle) }
  }
}

// ---------- item edit (full form; opened from taps inside reused storefront views) ----------
final class AdminItemEditVC: EdgeBackVC, UITextFieldDelegate, PHPickerViewControllerDelegate {
  var item = Item(); var isNew = false
  let sv = UIScrollView(); var back: UIButton!; var title_ = UILabel(); let photo = UIImageView(); let photoHint = Cap("TAP TO CHANGE PHOTO", 9, cMute(), .center)
  let fCode = AField("HD-01"), fColor = AField("black"), fPrice = AField("95"); let fDesc = UITextView()
  var catChips: [UIButton] = [], dropChips: [UIButton] = []; var save: PButton!
  var pickedImage: UIImage?; let status = UILabel(); var catSel = 0, dropSel = 0; var removePhoto = false; let removeBtn = UIButton(type: .custom)
  let hCode = AHead("Code"), hCat = AHead("Category"), hColor = AHead("Color (optional)"), hPrice = AHead("Price (USD)"), hDrop = AHead("Drop"), hDesc = AHead("Description (optional — blank uses the default for this category)")
  var delBtn: UIButton?
  override func viewDidLoad() {
    super.viewDidLoad(); view.backgroundColor = cBG(); addEdgeBack(); back = CircleBtn("chevron.left", self, #selector(goBack))
    sv.keyboardDismissMode = .interactive; sv.contentInsetAdjustmentBehavior = .never; view.addSubview(sv); view.addSubview(back)
    title_ = Disp(isNew ? "New item" : "Edit item", 40, cInk(), .left); sv.addSubview(title_)
    photo.contentMode = .scaleAspectFit; photo.backgroundColor = cSoft(); photo.layer.cornerRadius = 18; photo.layer.masksToBounds = true; photo.isUserInteractionEnabled = true
    photo.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(photoTap))); sv.addSubview(photo); photo.image = Img(item.iid, "med")
    sv.addSubview(photoHint)
    removeBtn.setAttributedTitle(NSAttributedString(string: "REMOVE CUSTOM PHOTO (USE DEFAULT)", attributes: [.font: Fc(9), .foregroundColor: cRed()]), for: .normal)
    removeBtn.addTarget(self, action: #selector(removePhotoTap), for: .touchUpInside); removeBtn.isHidden = (item.imgURL ?? "").isEmpty; sv.addSubview(removeBtn)
    for v in [hCode, hCat, hColor, hPrice, hDrop, hDesc] { sv.addSubview(v) }; hDesc.numberOfLines = 2
    fCode.text = item.code; fCode.autocapitalizationType = .allCharacters; sv.addSubview(fCode)
    catChips = AChips(["Tees", "Hoodies", "Pants"], self, #selector(catTap(_:))); catChips.forEach { sv.addSubview($0) }
    catSel = ["Tees", "Hoodies", "Pants"].firstIndex(of: item.cat) ?? 0; StyleChips(catChips, catSel)
    fColor.text = item.color; sv.addSubview(fColor)
    fPrice.keyboardType = .numberPad; fPrice.text = item.price > 0 ? "\(item.price)" : ""; sv.addSubview(fPrice)
    dropChips = AChips(gDrops.map { $0.nick.isEmpty ? $0.name : $0.nick }, self, #selector(dropTap(_:))); dropChips.forEach { sv.addSubview($0) }
    dropSel = gDrops.firstIndex { $0.did == item.drop } ?? 0; StyleChips(dropChips, dropSel)
    fDesc.backgroundColor = cSoft(); fDesc.layer.cornerRadius = 14; fDesc.font = Fm(14); fDesc.textColor = cInk(); fDesc.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12); fDesc.text = item.desc; sv.addSubview(fDesc)
    status.font = Fm(13); status.textColor = cMute(); status.numberOfLines = 2; status.textAlignment = .center; sv.addSubview(status)
    save = Btn("Save", cRed(), .white, 12) { [weak self] in self?.saveTap() }; save.layer.cornerRadius = 28; sv.addSubview(save)
    if !isNew { let d = UIButton(type: .custom); d.setAttributedTitle(NSAttributedString(string: "DELETE THIS PRODUCT", attributes: [.font: Fc(11), .foregroundColor: cRed()]), for: .normal); d.addTarget(self, action: #selector(deleteTap), for: .touchUpInside); sv.addSubview(d); delBtn = d }
    watchKeyboard(sv)
  }
  deinit { NotificationCenter.default.removeObserver(self) }
  @objc func goBack() { view.endEditing(true); dismiss(animated: true) }
  func setStatus(_ t: String, _ c: UIColor) { status.textColor = c; status.text = t }
  @objc func deleteTap() {
    let a = UIAlertController(title: "Delete this product?", message: "\(item.code.isEmpty ? "This item" : item.code) will be removed for everyone. This can't be undone.", preferredStyle: .alert)
    a.addAction(UIAlertAction(title: "Cancel", style: .cancel)); a.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in self?.doDelete() }); present(a, animated: true)
  }
  func doDelete() {
    let tok = Token(); if tok.isEmpty { setStatus("You're signed out — sign in again.", cRed()); return }
    save.isEnabled = false; delBtn?.isEnabled = false; setStatus("Deleting…", cMute())
    FSDeleteAuth("catalog_items", item.iid, tok) { [weak self] ok in
      guard let s = self else { return }
      if !ok { s.save.isEnabled = true; s.delBtn?.isEnabled = true; s.setStatus("Couldn't delete. Check your internet and try again.", cRed()); Hap(2); return }
      gItems.removeAll { $0 === s.item }; ClearItemImageOverride(s.item); Hap(2); SyncCatalog(); after(0.3) { s.goBack() }
    }
  }
  @objc func catTap(_ b: UIButton) { catSel = b.tag; StyleChips(catChips, b.tag); Hap(1) }
  @objc func dropTap(_ b: UIButton) { dropSel = b.tag; StyleChips(dropChips, b.tag); Hap(1) }
  @objc func photoTap() { present(PhotoPicker(self), animated: true) }
  func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
    picker.dismiss(animated: true)
    LoadPicked(results) { [weak self] im, e in
      guard let s = self else { return }
      if let e = e { s.setStatus(e, cRed()); Hap(2); return }
      s.pickedImage = im; s.removePhoto = false; s.photo.image = im; s.removeBtn.isHidden = false; Hap(2)
    }
  }
  @objc func removePhotoTap() { Hap(1); pickedImage = nil; removePhoto = true; photo.image = Img(item.iid, "med"); removeBtn.isHidden = true }
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews(); let w = view.bounds.width, T = view.safeAreaInsets.top; back.frame = R(16, T + 6, 44, 44); sv.frame = R(0, 0, w, view.bounds.height)
    var y = T + 60; title_.frame = R(20, y, w - 40, 46); y += 56
    let ph = w - 40; photo.frame = R(20, y, ph, ph * 0.82); y += ph * 0.82 + 6; photoHint.frame = R(20, y, w - 40, 14); y += 18; removeBtn.frame = R(20, y, w - 40, 16); y += 24
    let rowH: CGFloat = 52, gap: CGFloat = 6, lh: CGFloat = 16
    hCode.frame = R(20, y, w - 40, lh); y += lh + 4; fCode.frame = R(20, y, w - 40, rowH); y += rowH + gap * 3
    hCat.frame = R(20, y, w - 40, lh); y += lh + 4; let cw = (w - 40 - 16) / 3; for (k, b) in catChips.enumerated() { b.frame = R(20 + CGFloat(k) * (cw + 8), y, cw, 40) }; y += 40 + gap * 3
    hColor.frame = R(20, y, w - 40, lh); y += lh + 4; fColor.frame = R(20, y, w - 40, rowH); y += rowH + gap * 3
    hPrice.frame = R(20, y, w - 40, lh); y += lh + 4; fPrice.frame = R(20, y, w - 40, rowH); y += rowH + gap * 3
    hDrop.frame = R(20, y, w - 40, lh); y += lh + 4
    var cx: CGFloat = 20; for b in dropChips { let tw = ((b.titleLabel?.text ?? "") as NSString).size(withAttributes: [.font: Fm(13)]).width + 28; b.frame = R(cx, y, tw, 36); cx += tw + 8 }; y += 36 + gap * 3
    hDesc.frame = R(20, y, w - 40, 32); y += 36; fDesc.frame = R(20, y, w - 40, 90); y += 104
    status.frame = R(20, y, w - 40, 18); y += 22; save.frame = R(20, y, w - 40, 56); y += 64
    if let d = delBtn { d.frame = R(20, y, w - 40, 20); y += 36 }
    sv.contentSize = CGSize(width: w, height: y + 30)
  }
  func saveTap() {
    let code = (fCode.text ?? "").trimmingCharacters(in: .whitespaces); if code.isEmpty { setStatus("Add a code (like HD-06).", cRed()); Hap(2); return }
    let cat = ["Tees", "Hoodies", "Pants"][catSel], drop = dropSel < gDrops.count ? gDrops[dropSel].did : "d1", price = Int(fPrice.text ?? "") ?? 0
    let color = (fColor.text ?? "").trimmingCharacters(in: .whitespaces), desc = fDesc.text ?? ""
    let tok = Token(); if tok.isEmpty { setStatus("You're signed out — sign in again.", cRed()); return }
    save.isEnabled = false; save.alpha = 0.5; RetitleBtn(save, "Saving…", 12, .white); setStatus("", cMute())
    let resetSave = { [weak self] in guard let s = self else { return }; s.save.isEnabled = true; s.save.alpha = 1; RetitleBtn(s.save, "Save", 12, .white) }
    let finishSave: (String?) -> Void = { [weak self] newURL in
      guard let s = self else { return }
      var f: JSON = ["code": code, "cat": cat, "color": color, "drop": drop, "price": price, "desc": desc]
      let finalImg: String? = s.removePhoto ? nil : ((newURL ?? "").isEmpty ? s.item.imgURL : newURL)
      if let fi = finalImg, !fi.isEmpty { f["img"] = fi }
      FSUpsertAuth("catalog_items", s.item.iid, f, tok) { ok in
        if !ok { resetSave(); s.setStatus("Couldn't save. Check your internet and try again.", cRed()); Hap(2); return }
        s.item.imgURL = finalImg
        // cache the picked photo locally right away so the next refresh doesn't come up blank
        if let p = s.pickedImage, !(finalImg ?? "").isEmpty { StoreItemImageData(s.item, p.pngData()) } else if s.removePhoto { ClearItemImageOverride(s.item) }
        s.setStatus("Saved.", cInk()); Hap(2); SyncCatalog(); after(0.5) { s.goBack() }
      }
    }
    if let p = pickedImage {
      setStatus("Uploading photo…", cMute())
      CloudinaryUpload(p) { [weak self] url, e in guard let s = self else { return }; if let e = e { resetSave(); s.setStatus(e, cRed()); Hap(2); return }; finishSave(url) }
    } else { finishSave(nil) }
  }
}

// ---------- products: one full-screen card at a time, edited in place ----------
final class AdminProductsVC: UIViewController, PHPickerViewControllerDelegate {
  var idx = 0; var editingItem = false; var editCat = "Tees"
  var numLbl = UILabel(), ofLbl = UILabel(); let add = UIButton(type: .custom), del = UIButton(type: .custom)
  let photo = UIImageView(); var photoIcon = UIImageView(); var editBtn: UIButton!
  var nameLbl = UILabel(), priceLbl = UILabel(), descLbl = UILabel(), prefixLbl = UILabel()
  let codeWheel = PlainWheel(), priceWheel = PlainWheel()
  let tagWrap = UIView(), tagLeft = UIControl(), tagRight = UIControl(), tagLabel = UILabel(); var tagLeftIc = UIImageView(), tagRightIc = UIImageView()
  var empty = UILabel(), statusLbl = UILabel(); var obs: NSObjectProtocol?; let dock = MakePanel(); var topInset: CGFloat = 0
  override func viewDidLoad() {
    super.viewDidLoad(); view.backgroundColor = cPanel(); view.insertSubview(dock, at: 0)
    numLbl = Disp("01", 64, cInk(), .left); view.addSubview(numLbl); ofLbl = Cap("/ 1", 11, cMute(), .left); view.addSubview(ofLbl)
    add.setImage(SymT("plus", 32, cRed()), for: .normal); add.addTarget(self, action: #selector(addTap), for: .touchUpInside); view.addSubview(add)
    del.setImage(SymT("trash", 26, cRed()), for: .normal); del.addTarget(self, action: #selector(deleteTap), for: .touchUpInside); view.addSubview(del)
    photo.contentMode = .scaleAspectFit; photo.backgroundColor = .clear; photo.layer.cornerRadius = 28; photo.layer.masksToBounds = true; photo.isUserInteractionEnabled = true
    photo.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(photoTap))); view.addSubview(photo)
    photoIcon = UIImageView(image: SymT("photo.badge.plus", 30, cMute())); photoIcon.contentMode = .center; photoIcon.isUserInteractionEnabled = false; photoIcon.isHidden = true; view.addSubview(photoIcon)
    nameLbl = Disp("", 60, cInk(), .left); nameLbl.adjustsFontSizeToFitWidth = true; nameLbl.minimumScaleFactor = 0.4; view.addSubview(nameLbl)
    priceLbl = Disp("", 60, cRed(), .right); priceLbl.adjustsFontSizeToFitWidth = true; priceLbl.minimumScaleFactor = 0.3; view.addSubview(priceLbl)
    prefixLbl = Disp("", 34, cInk(), .left); prefixLbl.isHidden = true; prefixLbl.isUserInteractionEnabled = true; prefixLbl.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(catTap))); view.addSubview(prefixLbl)
    codeWheel.rowAlign = .left; codeWheel.isHidden = true; view.addSubview(codeWheel); priceWheel.rowAlign = .right; priceWheel.isHidden = true; view.addSubview(priceWheel)
    descLbl.font = .systemFont(ofSize: 15, weight: .medium); descLbl.textColor = cInk().withAlphaComponent(0.85); descLbl.numberOfLines = 3; view.addSubview(descLbl)
    tagWrap.backgroundColor = cRed(); view.addSubview(tagWrap); tagLabel.textAlignment = .center; tagWrap.addSubview(tagLabel)
    tagLeft.addTarget(self, action: #selector(tagPrev), for: .touchUpInside); tagWrap.addSubview(tagLeft)
    tagLeftIc = UIImageView(image: SymT("chevron.left", 14, .white)); tagLeftIc.contentMode = .center; tagLeftIc.isUserInteractionEnabled = false; tagLeft.addSubview(tagLeftIc)
    tagRight.addTarget(self, action: #selector(tagNext), for: .touchUpInside); tagWrap.addSubview(tagRight)
    tagRightIc = UIImageView(image: SymT("chevron.right", 14, .white)); tagRightIc.contentMode = .center; tagRightIc.isUserInteractionEnabled = false; tagRight.addSubview(tagRightIc)
    editBtn = CircleBtn("pencil", self, #selector(editTap)); view.addSubview(editBtn)
    empty = Cap("No products yet — tap + to add your first one", 10, cMute(), .center); empty.numberOfLines = 0; empty.isHidden = true; view.addSubview(empty)
    statusLbl = Cap("", 9, cRed(), .center); statusLbl.alpha = 0; view.addSubview(statusLbl)
    let sl = UISwipeGestureRecognizer(target: self, action: #selector(nextTap)); sl.direction = .left; view.addGestureRecognizer(sl)
    let sr = UISwipeGestureRecognizer(target: self, action: #selector(prevTap)); sr.direction = .right; view.addGestureRecognizer(sr)
    obs = NotificationCenter.default.addObserver(forName: kChange, object: nil, queue: .main) { [weak self] _ in if self?.editingItem == false { self?.reload() } }
    reload()
  }
  deinit { if let o = obs { NotificationCenter.default.removeObserver(o) } }
  var cur: Item? { gItems.isEmpty ? nil : gItems[max(0, min(idx, gItems.count - 1))] }
  func reload() { idx = gItems.isEmpty ? 0 : max(0, min(idx, gItems.count - 1)); refresh() }
  func codeNum(_ it: Item) -> Int { let p = it.code.components(separatedBy: "-"); return p.count == 2 ? max(1, Int(p[1]) ?? 1) : 1 }
  @objc func addTap() {
    let it = Item(); it.iid = "item-\(Int(Date().timeIntervalSince1970))"; it.code = ""; it.cat = "Tees"; it.price = 0; it.desc = ""; it.drop = gDrops.first?.did ?? ""
    gItems.append(it); idx = gItems.count - 1; Hap(1); slideInNew()
  }
  func slideInNew() {
    let views: [UIView] = [photo, nameLbl, priceLbl, descLbl, tagWrap, editBtn!]; refresh(); view.layoutIfNeeded(); let w = view.bounds.width
    views.forEach { $0.transform = CGAffineTransform(translationX: w * 0.5, y: 0); $0.alpha = 0 }
    spring(0.46, 0.84, opts: [.allowUserInteraction], { views.forEach { $0.transform = .identity; $0.alpha = 1 } })
  }
  @objc func deleteTap() {
    guard let it = cur, !editingItem else { return }; Hap(1)
    let a = UIAlertController(title: "Delete \(it.code.isEmpty ? "this product" : it.code)?", message: "This can't be undone.", preferredStyle: .alert)
    a.addAction(UIAlertAction(title: "Cancel", style: .cancel)); a.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in self?.doDelete(it) }); present(a, animated: true)
  }
  func doDelete(_ it: Item) {
    let tok = Token(); if tok.isEmpty { flashError("Signed out — sign in again to delete."); return }
    FSDeleteAuth("catalog_items", it.iid, tok) { [weak self] ok in
      guard let s = self else { return }
      if !ok { Hap(2); s.flashError("Couldn't delete — check your connection and try again."); return }
      gItems.removeAll { $0 === it }; ClearItemImageOverride(it); Hap(2); SyncCatalog(); s.idx = max(0, min(s.idx, gItems.count - 1)); s.refresh()
    }
  }
  @objc func photoTap() { guard editingItem, cur != nil else { return }; present(PhotoPicker(self), animated: true) }
  func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
    picker.dismiss(animated: true)
    LoadPicked(results) { [weak self] im, e in
      guard let s = self, let it = s.cur else { return }
      guard let im = im else { s.flashError(e ?? "Couldn't load that photo."); return }
      Hap(2); s.photo.image = im; s.photoIcon.isHidden = true
      let tok = Token(); if tok.isEmpty { s.flashError("Signed out — sign in again to upload a photo."); return }
      CloudinaryUpload(im) { url, e2 in
        guard let url = url else { s.flashError(e2 ?? "Couldn't upload that photo — check your connection and try again."); return }
        FSUpsertAuth("catalog_items", it.iid, ItemFields(it, ["img": url]), tok) { ok in
          // cache the photo in hand before syncing so the refresh doesn't blank it while the re-download lands
          if ok { it.imgURL = url; StoreItemImageData(it, im.pngData()); SyncCatalog() } else { s.flashError("Couldn't save the photo — check your connection and try again.") }
        }
      }
    }
  }
  @objc func nextTap() { if editingItem || gItems.count < 2 { return }; Hap(1); idx = (idx + 1) % gItems.count; refresh() }
  @objc func prevTap() { if editingItem || gItems.count < 2 { return }; Hap(1); idx = (idx - 1 + gItems.count) % gItems.count; refresh() }
  func curDropIdx(_ it: Item) -> Int { gDrops.firstIndex { $0.did == it.drop } ?? 0 }
  func tagCycleBlocked() -> Bool {
    if !editingItem && gDrops.count >= 2 { return false }; Hap(1)
    if editingItem { flashError("Finish editing first.") } else if gDrops.isEmpty { flashError("No drops yet — add one in the Drops tab first.") } else { flashError("Only one drop exists — add another to switch tags.") }
    return true
  }
  @objc func tagPrev() { guard let it = cur, !tagCycleBlocked() else { return }; Hap(1); let n = gDrops.count; applyDrop(gDrops[(curDropIdx(it) - 1 + n) % n], it) }
  @objc func tagNext() { guard let it = cur, !tagCycleBlocked() else { return }; Hap(1); applyDrop(gDrops[(curDropIdx(it) + 1) % gDrops.count], it) }
  func flashError(_ msg: String) {
    SetCap(statusLbl, msg, 9, cRed()); statusLbl.layer.removeAllAnimations(); statusLbl.alpha = 1
    anim(0.3, delay: 1.8, opts: [.beginFromCurrentState], { self.statusLbl.alpha = 0 })
  }
  func applyDrop(_ d: Drop, _ it: Item) {
    SetCap(tagLabel, d.nick.isEmpty ? d.name : d.nick, 11.5, .white)
    let newCat = CatForDropName(d.nick.isEmpty ? d.name : d.nick) ?? it.cat, newCode = String(format: "%@-%02d", CodePrefixForCat(newCat), codeNum(it))
    if !editingItem { nameLbl.text = newCode.uppercased() }
    let tok = Token(); if tok.isEmpty { flashError("Signed out — sign in again to tag items."); refresh(); return }
    FSUpsertAuth("catalog_items", it.iid, ItemFields(it, ["drop": d.did, "cat": newCat, "code": newCode]), tok) { [weak self] ok in
      guard let s = self else { return }
      if ok { it.drop = d.did; it.cat = newCat; it.code = newCode; Hap(2); SyncCatalog() } else { Hap(2); s.flashError("Couldn't save the tag — check your connection and try again."); s.refresh() }
    }
  }
  @objc func editTap() {
    guard let it = cur else { return }; Hap(1)
    if !editingItem {
      editingItem = true; editCat = it.cat
      // seed with the real row height so the wheel lands on the current code/price the instant it appears
      let seedRowH: CGFloat = 60 * 1.08
      codeWheel.setItems((1...60).map { String(format: "%02d", $0) }, rowHeight: seedRowH, selected: max(0, min(59, codeNum(it) - 1)))
      priceWheel.setItems((0..<200).map { Money($0 * 5) }, rowHeight: seedRowH, selected: max(0, min(199, (it.price + 2) / 5)))
      codeWheel.style(fg: cInk(), sel: Fd(26), dim: Fd(16)); priceWheel.style(fg: cRed(), sel: Fd(26), dim: Fd(16))
      refresh(); return
    }
    let newCat = editCat, newCode = String(format: "%@-%02d", CodePrefixForCat(newCat), codeWheel.selectedIndex + 1), newPrice = priceWheel.selectedIndex * 5
    let tok = Token(); if tok.isEmpty { flashError("Signed out — sign in again to save changes."); editingItem = false; refresh(); return }
    FSUpsertAuth("catalog_items", it.iid, ItemFields(it, ["code": newCode, "price": newPrice, "cat": newCat]), tok) { [weak self] ok in
      guard let s = self else { return }
      if ok { it.code = newCode; it.price = newPrice; it.cat = newCat; Hap(2); SyncCatalog() } else { Hap(2); s.flashError("Couldn't save — check your connection and try again.") }
      s.editingItem = false; s.refresh()
    }
  }
  @objc func catTap() {
    guard editingItem else { return }; Hap(1)
    let cats = ["Tees", "Hoodies", "Pants"], i = cats.firstIndex(of: editCat) ?? 0; editCat = cats[(i + 1) % 3]; refresh()
  }
  func refresh() {
    let it = cur, has = it != nil
    empty.isHidden = has
    for v in [photo, descLbl, tagWrap, editBtn!, numLbl, ofLbl, del, dock] as [UIView] { v.isHidden = !has }
    guard let item = it else { photoIcon.isHidden = true; nameLbl.isHidden = true; priceLbl.isHidden = true; view.setNeedsLayout(); return }
    numLbl.text = Pad(idx + 1); SetCap(ofLbl, "/ \(gItems.count)", 11, cMute())
    let curImg = TrimImg(Img(item.iid, "med")); photo.image = curImg; photoIcon.isHidden = !(editingItem && curImg == nil)
    nameLbl.text = (item.code.isEmpty ? "—" : item.code).uppercased(); priceLbl.text = Money(item.price); descLbl.text = DescFor(item)
    let hasDrops = !gDrops.isEmpty, dr = DropFor(item)
    tagLabel.attributedText = CapStr(hasDrops ? (dr.nick.isEmpty ? dr.name : dr.nick) : "No drops yet", 11.5, .white)
    tagWrap.backgroundColor = hasDrops ? cRed() : cMute(); tagLeft.isHidden = !hasDrops; tagRight.isHidden = !hasDrops
    editBtn.setImage(SymT(editingItem ? "checkmark" : "pencil", 16, cInk()), for: .normal)
    if editingItem { prefixLbl.text = CodePrefixForCat(editCat) + "-" }
    nameLbl.isHidden = editingItem; priceLbl.isHidden = editingItem
    prefixLbl.isHidden = !editingItem; codeWheel.isHidden = !editingItem; priceWheel.isHidden = !editingItem
    tagWrap.isUserInteractionEnabled = !editingItem; tagWrap.alpha = editingItem ? 0.4 : 1
    add.isEnabled = !editingItem; del.isEnabled = !editingItem; add.alpha = editingItem ? 0.3 : 1; del.alpha = editingItem ? 0.3 : 1
    view.setNeedsLayout()
  }
  override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); layoutCard() }
  func layoutCard() {
    let w = view.bounds.width, h = view.bounds.height; if w < 10 || h < 10 { return }
    let TT = topInset
    numLbl.frame = R(18, TT, 90, 58); ofLbl.frame = R(18 + numLbl.sizeThatFits(CGSize(width: 200, height: 60)).width + 4, TT + 34, 60, 16)
    add.frame = R(w - 20 - 44, TT + 2, 44, 44); del.frame = R(w - 20 - 44 - 44 - 6, TT + 2, 44, 44)
    if cur == nil { empty.frame = R(24, TT + 70, w - 48, 60); return }
    let P: CGFloat = 18, B: CGFloat = 48, cs: CGFloat = 60, pw: CGFloat = 104
    let by = h - 24 - B, infoH = cs * 1.08 + 6 + 66, iy = TT + 78, ih2 = max(100, by - 12 - infoH - iy), r = iy + ih2 + 4
    photo.frame = R(0, iy, w, ih2); photoIcon.frame = photo.frame
    // same split point the storefront product page uses for its dock card
    let cfI = min(84, (h - 66) * 0.17), py0 = h - cfI - 138, dockY = max(iy, py0); dock.frame = R(0, dockY, w, h - dockY)
    let codeBoxW = w - 2 * P - pw - 6, codeBoxH = cs * 1.08, prefW = min(90, codeBoxW * 0.42)
    nameLbl.frame = R(P, r, codeBoxW, codeBoxH); priceLbl.frame = R(w - P - pw, r, pw, codeBoxH)
    prefixLbl.frame = R(P, r, prefW, codeBoxH); codeWheel.frame = R(P + prefW + 4, r, codeBoxW - prefW - 4, codeBoxH); priceWheel.frame = R(w - P - pw, r, pw, codeBoxH)
    // at rest the edit view renders pixel-identical to the static "SH-01 / $95" display
    if editingItem && !codeWheel.items.isEmpty && !priceWheel.items.isEmpty {
      let pfx = CodePrefixForCat(editCat), ci = max(0, min(codeWheel.selectedIndex, codeWheel.items.count - 1))
      let codeFont = FitDispFontSize("\(pfx)-\(codeWheel.items[ci])", 60, 0.4, codeBoxW); prefixLbl.font = Fd(codeFont)
      let prefTextW = ((pfx + "-") as NSString).size(withAttributes: [.font: Fd(codeFont)]).width
      prefixLbl.frame = R(P, r, prefTextW, codeBoxH); codeWheel.frame = R(P + prefTextW, r, max(10, codeBoxW - prefTextW), codeBoxH)
      codeWheel.restyle(rowHeight: codeBoxH, sel: Fd(codeFont), dim: Fd(max(16, codeFont * 0.45)))
      let pi = max(0, min(priceWheel.selectedIndex, priceWheel.items.count - 1)), priceFont = FitDispFontSize(priceWheel.items[pi], 60, 0.3, pw)
      priceWheel.restyle(rowHeight: codeBoxH, sel: Fd(priceFont), dim: Fd(max(16, priceFont * 0.45)))
    }
    descLbl.frame = R(P + 2, r + cs * 1.08 + 6, w - 2 * P - 4, 66)
    let tagW = w - 2 * P - B - 8
    tagWrap.frame = R(P, by, tagW, B); tagWrap.layer.cornerRadius = B / 2; tagWrap.clipsToBounds = true
    tagLeft.frame = R(0, 0, 52, B); tagLeftIc.frame = tagLeft.bounds; tagRight.frame = R(tagW - 52, 0, 52, B); tagRightIc.frame = tagRight.bounds
    tagLabel.frame = R(52, 0, max(10, tagW - 104), B)
    editBtn.frame = R(w - P - B, by, B, B); editBtn.layer.cornerRadius = B / 2
    statusLbl.frame = R(P, by - 20, w - 2 * P, 16)
  }
}

// ---------- drop edit ----------
final class AdminDropEditVC: EdgeBackVC, UITextFieldDelegate {
  var drop = Drop(); var isNew = false
  let sv = UIScrollView(); var back: UIButton!; let title_ = Disp("Edit drop", 40, cInk(), .left)
  let fName = AField("Drop 01 · The Tees"), fNick = AField("The Tees"); var fID: UITextField?; let dp = UIDatePicker(); var save: PButton!; let status = UILabel()
  let hName = AHead("Name"), hNick = AHead("Short name"), hDate = AHead("Drop date & time"); var hID: UILabel?; var delBtn: UIButton?
  override func viewDidLoad() {
    super.viewDidLoad(); view.backgroundColor = cBG(); addEdgeBack(); back = CircleBtn("chevron.left", self, #selector(goBack))
    sv.keyboardDismissMode = .interactive; sv.contentInsetAdjustmentBehavior = .never; view.addSubview(sv); view.addSubview(back)
    title_.text = (isNew ? "New drop" : "Edit drop").uppercased()
    for v in [title_, hName, fName, hNick, fNick, hDate] as [UIView] { sv.addSubview(v) }
    fName.text = drop.name; fNick.text = drop.nick
    dp.datePickerMode = .dateAndTime; dp.preferredDatePickerStyle = .wheels; dp.date = drop.date; sv.addSubview(dp)
    if isNew {
      let h = AHead("ID (advanced — only set this to restore a deleted drop with its items)"); h.numberOfLines = 2; sv.addSubview(h); hID = h
      let f = AField("leave blank for a new drop"); sv.addSubview(f); fID = f
    }
    status.font = Fm(13); status.textColor = cMute(); status.numberOfLines = 2; status.textAlignment = .center; sv.addSubview(status)
    save = Btn("Save", cRed(), .white, 12) { [weak self] in self?.saveTap() }; save.layer.cornerRadius = 28; sv.addSubview(save)
    if !isNew { let d = UIButton(type: .custom); d.setAttributedTitle(NSAttributedString(string: "DELETE THIS DROP", attributes: [.font: Fc(11), .foregroundColor: cRed()]), for: .normal); d.addTarget(self, action: #selector(deleteTap), for: .touchUpInside); sv.addSubview(d); delBtn = d }
    watchKeyboard(sv)
  }
  deinit { NotificationCenter.default.removeObserver(self) }
  @objc func goBack() { view.endEditing(true); dismiss(animated: true) }
  func setStatus(_ t: String, _ c: UIColor) { status.textColor = c; status.text = t }
  @objc func deleteTap() {
    let n = gItems.filter { $0.drop == drop.did }.count
    let msg = n > 0 ? "\(n) item\(n == 1 ? "" : "s") still use this drop and will need to be moved first. Delete anyway?" : "This can't be undone."
    let a = UIAlertController(title: "Delete this drop?", message: msg, preferredStyle: .alert)
    a.addAction(UIAlertAction(title: "Cancel", style: .cancel)); a.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in self?.doDelete() }); present(a, animated: true)
  }
  func doDelete() {
    let tok = Token(); if tok.isEmpty { setStatus("You're signed out — sign in again.", cRed()); return }
    save.isEnabled = false; delBtn?.isEnabled = false; setStatus("Deleting…", cMute())
    FSDeleteAuth("catalog_drops", drop.did, tok) { [weak self] ok in
      guard let s = self else { return }
      if !ok { s.save.isEnabled = true; s.delBtn?.isEnabled = true; s.setStatus("Couldn't delete. Check your internet and try again.", cRed()); Hap(2); return }
      gDrops.removeAll { $0 === s.drop }; Hap(2); SyncCatalog(); after(0.3) { s.goBack() }
    }
  }
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews(); let w = view.bounds.width, T = view.safeAreaInsets.top; back.frame = R(16, T + 6, 44, 44); sv.frame = R(0, 0, w, view.bounds.height)
    var y = T + 60; title_.frame = R(20, y, w - 40, 46); y += 56
    hName.frame = R(20, y, w - 40, 16); y += 20; fName.frame = R(20, y, w - 40, 52); y += 70
    hNick.frame = R(20, y, w - 40, 16); y += 20; fNick.frame = R(20, y, w - 40, 52); y += 70
    hDate.frame = R(20, y, w - 40, 16); y += 20; dp.frame = R(10, y, w - 20, 180); y += 190
    if let h = hID, let f = fID { h.frame = R(20, y, w - 40, 30); y += 34; f.frame = R(20, y, w - 40, 52); y += 70 }
    status.frame = R(20, y, w - 40, 18); y += 22; save.frame = R(20, y, w - 40, 56); y += 64
    if let d = delBtn { d.frame = R(20, y, w - 40, 20); y += 36 }
    sv.contentSize = CGSize(width: w, height: y + 30)
  }
  func saveTap() {
    let name = (fName.text ?? "").trimmingCharacters(in: .whitespaces); if name.isEmpty { setStatus("Add a name for this drop.", cRed()); Hap(2); return }
    let nick = (fNick.text ?? "").trimmingCharacters(in: .whitespaces), tok = Token()
    if tok.isEmpty { setStatus("You're signed out — sign in again.", cRed()); return }
    if let cid = fID?.text?.trimmingCharacters(in: .whitespaces), !cid.isEmpty { drop.did = cid }
    save.isEnabled = false; save.alpha = 0.5; RetitleBtn(save, "Saving…", 12, .white)
    FSUpsertAuth("catalog_drops", drop.did, ["name": name, "nick": nick.isEmpty ? name : nick, "date": ISOFromDate(dp.date)], tok) { [weak self] ok in
      guard let s = self else { return }
      if !ok { s.save.isEnabled = true; s.save.alpha = 1; RetitleBtn(s.save, "Save", 12, .white); s.setStatus("Couldn't save. Check your internet and try again.", cRed()); Hap(2); return }
      s.setStatus("Saved.", cInk()); Hap(2); SyncCatalog(); after(0.5) { s.goBack() }
    }
  }
}

// ---------- drops: the real storefront DropsView with admin edit controls ----------
final class AdminDropsVC: UIViewController {
  var dv: DropsView!
  override func viewDidLoad() {
    super.viewDidLoad(); view.backgroundColor = cBG(); view.clipsToBounds = true; view.layer.cornerRadius = 32; view.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
    dv = DropsView(frame: view.bounds); dv.pnl.isHidden = true; dv.backgroundColor = cBG(); view.addSubview(dv)
  }
  override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); dv.frame = view.bounds }
}

func PresentFull(_ vc: UIViewController) { vc.modalPresentationStyle = .overFullScreen; TopVC()?.present(vc, animated: true) }
func AdminOpenItemTap(_ it: Item) { let e = AdminItemEditVC(); e.item = it; e.isNew = false; PresentFull(e) }
func AdminOpenDropTap(_ d: Drop) { let e = AdminDropEditVC(); e.drop = d; e.isNew = false; PresentFull(e) }
func AdminAddDropTap() {
  if gDrops.count >= 3 {
    let a = UIAlertController(title: "3 drop max", message: "The Drops tab is designed for up to 3 drops at once. Delete one first if you need to add another.", preferredStyle: .alert)
    a.addAction(UIAlertAction(title: "OK", style: .default)); TopVC()?.present(a, animated: true); return
  }
  let d = Drop(); d.did = "drop-\(Int(Date().timeIntervalSince1970))"; d.name = "New drop"; d.nick = "New drop"; d.date = Date().addingTimeInterval(86400 * 30)
  let e = AdminDropEditVC(); e.drop = d; e.isNew = true; PresentFull(e)
}

// ---------- admin shell ----------
final class AdminRootVC: UIViewController {
  var logo = UIView(); let tabBar = UIView(); var tabBtns: [UIButton] = [], tabIcons: [UIImageView] = [], tabLbls: [UILabel] = []; var sel = 0; var content: UIViewController?
  override func viewDidLoad() {
    super.viewDidLoad(); view.backgroundColor = cBG()
    logo = Lockup(140); view.addSubview(logo)
    tabBar.backgroundColor = cBG(); view.addSubview(tabBar); let tl = Line(); tl.tag = 3; tabBar.addSubview(tl)
    for i in 0..<2 {
      let b = UIButton(type: .custom); b.tag = i; b.addTarget(self, action: #selector(tabTap(_:)), for: .touchUpInside); tabBar.addSubview(b); tabBtns.append(b)
      let iv = UIImageView(); iv.contentMode = .center; iv.isUserInteractionEnabled = false; b.addSubview(iv); tabIcons.append(iv)
      let l = UILabel(); l.textAlignment = .center; l.isUserInteractionEnabled = false; b.addSubview(l); tabLbls.append(l)
    }
    styleTabs(0); showTab(0)
  }
  @objc func tabTap(_ b: UIButton) { if b.tag == sel { return }; Hap(1); styleTabs(b.tag); showTab(b.tag) }
  func styleTabs(_ s: Int) {
    sel = s; let names = ["house", "drop"], fills = ["house.fill", "drop.fill"], lb = ["Products", "Drops"]
    for i in 0..<2 { let on = i == s, c = on ? cInk() : cMute(); tabIcons[i].image = SymT(on ? fills[i] : names[i], 19, c); tabLbls[i].attributedText = NSAttributedString(string: lb[i].uppercased(), attributes: [.font: Fd(11.5), .foregroundColor: c, .kern: 1.2]) }
    view.setNeedsLayout()
  }
  func showTab(_ i: Int) {
    if let c = content { c.willMove(toParent: nil); c.view.removeFromSuperview(); c.removeFromParent() }
    let c: UIViewController = i == 0 ? AdminProductsVC() : AdminDropsVC(); addChild(c); view.insertSubview(c.view, belowSubview: tabBar); c.didMove(toParent: self); content = c; view.setNeedsLayout()
  }
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews(); let w = view.bounds.width, h = view.bounds.height, T = view.safeAreaInsets.top, B = view.safeAreaInsets.bottom
    let logoW: CGFloat = 140, logoH = logoW * kLogoRatio; logo.frame = R((w - logoW) / 2, T + 8 + (40 - logoH) / 2, logoW, logoH)
    let topH = T + 58, tabH = 56 + B; tabBar.frame = R(0, h - tabH, w, tabH); tabBar.viewWithTag(3)?.frame = R(0, 0, w, 0.5)
    let bw = w / 2; for i in 0..<2 { tabBtns[i].frame = R(CGFloat(i) * bw, 0, bw, 56); tabIcons[i].frame = R(0, 9, bw, 24); tabLbls[i].frame = R(0, 34, bw, 16) }
    if let d = content as? AdminDropsVC { d.view.frame = R(0, topH, w, h - topH); d.dv?.bottomInset = tabH; d.dv?.setNeedsLayout() }
    else if let p = content as? AdminProductsVC { p.view.frame = R(0, 0, w, h - tabH); p.topInset = topH; p.view.setNeedsLayout() }
    view.bringSubviewToFront(logo); view.bringSubviewToFront(tabBar)
  }
}

// ---------- gate: sign-in until there's an admin session ----------
final class AdminGateVC: UIViewController {
  var obs: NSObjectProtocol?; var child: UIViewController?
  override func viewDidLoad() {
    super.viewDidLoad(); view.backgroundColor = cBG()
    gItemTapOverride = AdminOpenItemTap; gDropTapOverride = AdminOpenDropTap; gDropAddOverride = AdminAddDropTap
    show(); obs = NotificationCenter.default.addObserver(forName: kChange, object: nil, queue: .main) { [weak self] _ in self?.show() }
  }
  func show() {
    let wantAuth = gUser == nil, haveAuth = child is AdminSignInVC
    if child != nil && wantAuth == haveAuth { return }
    if let c = child { c.willMove(toParent: nil); c.view.removeFromSuperview(); c.removeFromParent() }
    let c: UIViewController = wantAuth ? AdminSignInVC() : AdminRootVC()
    addChild(c); c.view.frame = view.bounds; c.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]; view.addSubview(c.view); c.didMove(toParent: self); child = c
  }
}
#endif
