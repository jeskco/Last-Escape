import SwiftUI
import SceneKit
import ModelIO
import SceneKit.ModelIO
import simd

/// The Studio engine: scene, objects, modes, gizmo interaction, editing, sculpting, posing, undo and files.
@MainActor
final class StudioModel: ObservableObject {
    // Category masks so taps only hit what they should.
    static let objectMask = 1 << 1
    static let helperMask = 1 << 4

    let scene = SCNScene()
    let cameraNode = SCNNode()
    lazy var orbit = OrbitCamera(node: cameraNode)
    weak var view: SCNView?

    let contentRoot = SCNNode()
    let grid = SCNNode()
    let gizmo = SCNNode()
    let overlay = SCNNode()
    let jointsRoot = SCNNode()
    let brushRing = SCNNode()
    let sunNode = SCNNode()

    // MARK: published state
    @Published private(set) var objects: [StudioObject] = []
    @Published var selection: Set<UUID> = [] { didSet { selectionChanged() } }
    @Published private(set) var primaryID: UUID?
    @Published var mode: StudioMode = .object { didSet { modeChanged(from: oldValue) } }
    @Published var gizmoKind: GizmoKind = .move { didSet { buildGizmo() } }
    @Published var selectMode: SelectMode = .face { didSet { convertSelection(from: oldValue); refreshOverlay() } }
    @Published var multiSelect = false
    @Published var snapping = false
    @Published var showGrid = true { didSet { grid.isHidden = !showGrid } }
    @Published var xray = false { didSet { applyXray() } }
    @Published var projectName = "Untitled Model"
    @Published private(set) var revision = 0
    @Published var toast: String?

    // Edit-mode selection (indices into the primary object's mesh)
    @Published private(set) var selVerts: Set<Int> = []
    @Published private(set) var selEdges: Set<EditMesh.Edge> = []
    @Published private(set) var selFaces: Set<Int> = []

    // Sculpt
    @Published var brush: SculptBrush = .draw
    @Published var brushRadius: Double = 0.12
    @Published var brushStrength: Double = 0.5
    @Published var brushInvert = false
    @Published var symmetryX = true

    // Pose
    @Published private(set) var bones: [BoneInfo] = []
    @Published var selectedBone: BoneInfo?
    @Published private(set) var keys: [PoseKey] = []
    @Published var poseTime: Double = 0 { didSet { if !posePlaying { applyPose(at: poseTime) } } }
    @Published var poseDuration: Double = 2
    @Published var posePlaying = false
    @Published var loopPose = true
    private var restPose: [ObjectIdentifier: PoseTransform] = [:]
    private var savedClipCount = 0
    private(set) var savedClips: [ClipInfo] = []

    private var undoStack: [StudioSnapshot] = []
    private var redoStack: [StudioSnapshot] = []
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false

    let projectID: String
    var dirty = false
    private var link: CADisplayLink?
    private var lastTick: CFTimeInterval = 0
    private var toastTask: Task<Void, Never>?

    var primary: StudioObject? { objects.first { $0.id == primaryID } }
    var selectedObjects: [StudioObject] { objects.filter { selection.contains($0.id) } }

    // MARK: setup

    init(projectID: String? = nil) {
        self.projectID = projectID ?? UUID().uuidString
        let cam = SCNCamera(); cam.fieldOfView = 45; cam.wantsHDR = true; cam.zNear = 0.01; cam.zFar = 500
        cam.wantsExposureAdaptation = false
        cameraNode.camera = cam
        scene.rootNode.addChildNode(cameraNode)
        scene.lightingEnvironment.contents = ViewerModel.studioEnvironment
        scene.lightingEnvironment.intensity = 1.2
        let sun = SCNLight(); sun.type = .directional; sun.intensity = 800; sun.castsShadow = true; sun.shadowMode = .deferred
        sun.shadowColor = UIColor(white: 0, alpha: 0.3); sun.shadowSampleCount = 8; sun.shadowRadius = 4; sun.automaticallyAdjustsShadowProjection = true
        sunNode.light = sun; sunNode.eulerAngles = SCNVector3(-Float.pi / 3, Float.pi / 5, 0)
        scene.rootNode.addChildNode(sunNode)
        scene.rootNode.addChildNode(contentRoot)
        buildGrid()
        for n in [grid, gizmo, overlay, jointsRoot, brushRing] { scene.rootNode.addChildNode(n) }
        overlay.removeFromParentNode()
        buildGizmo()
        let ring = SCNTorus(ringRadius: 1, pipeRadius: 0.015)
        let rm = SCNMaterial(); rm.lightingModel = .constant; rm.diffuse.contents = UIColor.white; rm.readsFromDepthBuffer = false
        ring.materials = [rm]; brushRing.geometry = ring; brushRing.isHidden = true; brushRing.renderingOrder = 3000
        brushRing.categoryBitMask = Self.helperMask
    }

    func attach(_ v: SCNView) {
        view = v
        orbit.attach(to: v)
        orbit.allowOneFingerOrbit = { [weak self] p in self?.dragTarget(at: p) == nil }
        orbit.frame(center: SIMD3(0, 0.5, 0), radius: 1.2, distance: 3.6, animated: false)
        link?.invalidate()
        let proxy = DisplayLinkProxy { [weak self] l in self?.tick(l) }
        let l = CADisplayLink(target: proxy, selector: #selector(DisplayLinkProxy.step(_:)))
        l.add(to: .main, forMode: .common); link = l
    }

    func detach() { link?.invalidate(); link = nil; orbit.detach() }

    private func buildGrid() {
        var pts: [SIMD3<Float>] = []; var idx: [UInt32] = []
        let n = 10; let step: Float = 0.5
        for i in -n...n {
            let f = Float(i) * step, e = Float(n) * step
            pts += [[f, 0, -e], [f, 0, e], [-e, 0, f], [e, 0, f]]
        }
        for i in 0..<pts.count { idx.append(UInt32(i)) }
        let src = SCNGeometrySource(vertices: pts.map { SCNVector3($0) })
        let el = SCNGeometryElement(indices: idx, primitiveType: .line)
        let g = SCNGeometry(sources: [src], elements: [el])
        let m = SCNMaterial(); m.lightingModel = .constant; m.diffuse.contents = UIColor.label.withAlphaComponent(0.16); m.writesToDepthBuffer = false
        g.materials = [m]
        grid.geometry = g
        grid.categoryBitMask = Self.helperMask
        // Coloured X and Z axes.
        for (axis, color) in [(SIMD3<Float>(1, 0, 0), UIColor.systemRed), (SIMD3<Float>(0, 0, 1), UIColor.systemBlue)] {
            let s = SCNGeometrySource(vertices: [SCNVector3(-axis * 5), SCNVector3(axis * 5)])
            let line = SCNGeometry(sources: [s], elements: [SCNGeometryElement(indices: [UInt32(0), 1], primitiveType: .line)])
            let lm = SCNMaterial(); lm.lightingModel = .constant; lm.diffuse.contents = color.withAlphaComponent(0.7); line.materials = [lm]
            let ln = SCNNode(geometry: line); ln.categoryBitMask = Self.helperMask; ln.position.y = 0.001
            grid.addChildNode(ln)
        }
        let floor = SCNFloor(); floor.reflectivity = 0
        let fm = SCNMaterial(); fm.lightingModel = .shadowOnly; floor.materials = [fm]
        let fn = SCNNode(geometry: floor); fn.categoryBitMask = Self.helperMask
        grid.addChildNode(fn)
    }

    // MARK: objects

    func showToast(_ s: String) {
        toastTask?.cancel()
        withAnimation(.spring(duration: 0.4)) { toast = s }
        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            if !Task.isCancelled { withAnimation(.easeOut) { self.toast = nil } }
        }
    }

    private func touch() { revision &+= 1; dirty = true }

    func material(for o: StudioObject) -> SCNMaterial {
        let r = o.material
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = o.textureImage ?? UIColor(red: CGFloat(r.r), green: CGFloat(r.g), blue: CGFloat(r.b), alpha: 1)
        if o.textureImage != nil { m.diffuse.wrapS = .repeat; m.diffuse.wrapT = .repeat }
        m.roughness.contents = NSNumber(value: max(0.03, r.roughness))
        m.metalness.contents = NSNumber(value: r.metalness)
        if r.emission > 0.01 { m.emission.contents = UIColor(red: CGFloat(r.r * r.emission), green: CGFloat(r.g * r.emission), blue: CGFloat(r.b * r.emission), alpha: 1) }
        if r.opacity < 0.999 { m.transparency = CGFloat(r.opacity); m.blendMode = .alpha; m.transparencyMode = .dualLayer }
        m.isDoubleSided = r.doubleSided
        return m
    }

    /// Rebuilds an object's geometry from its mesh (after any edit).
    func rebuild(_ o: StudioObject, keepMaterial: Bool = true) {
        guard let mesh = o.mesh else { return }
        let (g, tf) = mesh.makeGeometry()
        g.materials = [keepMaterial ? (o.node.geometry?.firstMaterial ?? material(for: o)) : material(for: o)]
        o.node.geometry = g
        o.triangleFace = tf
        o.node.castsShadow = true
        o.node.categoryBitMask = Self.objectMask
        if o.id == primaryID && mode == .edit { refreshOverlay() }
    }

    func applyMaterial(_ o: StudioObject) {
        guard !o.isImported else { return }
        o.node.geometry?.materials = [material(for: o)]
        applyXray()
        touch()
    }

    @discardableResult
    func add(_ o: StudioObject, select: Bool = true) -> StudioObject {
        objects.append(o)
        contentRoot.addChildNode(o.node)
        if o.mesh != nil { rebuild(o, keepMaterial: false) }
        if select { selection = [o.id] }
        touch()
        return o
    }

    func addPrimitive(_ p: Primitive) {
        pushUndo()
        if mode != .object { mode = .object }
        let mesh = p.mesh()
        let o = StudioObject(name: uniqueName(p.rawValue), mesh: mesh,
                             material: p == .clay ? MaterialRecord.presets[0].1 : MaterialRecord())
        let b = mesh.bounds
        // Sit new shapes on the floor, slightly offset if something is already at the centre.
        var x: Float = 0
        let occupied = objects.filter { !$0.hidden }.map { $0.node.simdPosition.x }
        while occupied.contains(where: { abs($0 - x) < 0.6 }) && x < 20 { x += 1.2 }
        o.node.simdPosition = SIMD3(x, -b.min.y, 0)
        add(o)
        if objects.count == 1 { focusSelection() }
        Haptics.tap()
    }

    private func uniqueName(_ base: String) -> String {
        let names = Set(objects.map(\.name))
        if !names.contains(base) { return base }
        var i = 2; while names.contains("\(base) \(i)") { i += 1 }
        return "\(base) \(i)"
    }

    func duplicateSelection() {
        guard !selectedObjects.isEmpty else { return }
        pushUndo()
        var newIDs: Set<UUID> = []
        for o in selectedObjects where !o.isImported {
            let c = StudioObject(name: uniqueName(o.name), mesh: o.mesh, material: o.material)
            c.textureImage = o.textureImage
            c.node.simdTransform = o.node.simdTransform
            c.node.simdPosition += SIMD3(0.35, 0, 0.35)
            add(c, select: false)
            newIDs.insert(c.id)
        }
        if !newIDs.isEmpty { selection = newIDs; showToast("Duplicated") }
    }

    func deleteSelection() {
        guard !selectedObjects.isEmpty else { return }
        pushUndo()
        for o in selectedObjects { o.node.removeFromParentNode() }
        objects.removeAll { selection.contains($0.id) }
        selection = []
        touch()
    }

    func setHidden(_ o: StudioObject, _ hidden: Bool) {
        o.hidden = hidden; o.node.isHidden = hidden
        if hidden { selection.remove(o.id) }
        touch()
    }

    func rename(_ o: StudioObject, _ name: String) { o.name = name.isEmpty ? o.name : name; touch() }

    /// Joins the selected meshes into the primary one.
    func joinSelection() {
        guard let p = primary, var mesh = p.mesh else { return }
        let others = selectedObjects.filter { $0.id != p.id && !$0.isImported }
        guard !others.isEmpty else { showToast("Select two or more shapes to join"); return }
        pushUndo()
        let inv = p.node.simdWorldTransform.inverse
        for o in others {
            guard var m = o.mesh else { continue }
            m.apply(inv * o.node.simdWorldTransform)
            mesh.append(m)
            o.node.removeFromParentNode()
        }
        objects.removeAll { o in others.contains { $0.id == o.id } }
        p.mesh = mesh
        rebuild(p)
        selection = [p.id]
        showToast("Joined \(others.count + 1) shapes")
    }

    /// Bakes position/rotation/scale into the mesh so the object's transform becomes identity at its origin.
    func applyTransform() {
        guard let p = primary, var mesh = p.mesh else { return }
        pushUndo()
        let pos = p.node.simdPosition
        var m = p.node.simdTransform; m.columns.3 = SIMD4(0, 0, 0, 1)
        mesh.apply(m)
        p.mesh = mesh
        p.node.simdOrientation = simd_quatf(angle: 0, axis: [0, 1, 0]); p.node.simdScale = SIMD3(repeating: 1); p.node.simdPosition = pos
        rebuild(p)
        showToast("Transform applied")
    }

    /// Turns the static meshes of an imported model into editable Studio shapes (keeps their textures).
    func convertToEditable(_ o: StudioObject) {
        guard o.isImported else { return }
        pushUndo()
        var made = 0, skipped = 0
        var geoNodes: [SCNNode] = []
        o.node.enumerateHierarchy { n, _ in if n.geometry != nil { geoNodes.append(n) } }
        for n in geoNodes {
            guard let g = n.geometry else { continue }
            if n.skinner != nil || n.morpher != nil { skipped += 1; continue }
            for ei in 0..<g.elements.count {
                guard var mesh = EditMesh.from(geometry: g, element: ei), mesh.faceCount > 0 else { continue }
                mesh.apply(contentRoot.simdWorldTransform.inverse * n.simdWorldTransform)
                let mat = g.materials.isEmpty ? nil : g.materials[ei % g.materials.count]
                var rec = MaterialRecord()
                if let c = mat?.diffuse.contents as? UIColor {
                    var r: CGFloat = 0, gg: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0; c.getRed(&r, green: &gg, blue: &b, alpha: &a)
                    rec.r = Float(r); rec.g = Float(gg); rec.b = Float(b)
                }
                if let rv = mat?.roughness.contents as? NSNumber { rec.roughness = rv.floatValue }
                if let mv = mat?.metalness.contents as? NSNumber { rec.metalness = mv.floatValue }
                rec.doubleSided = mat?.isDoubleSided ?? false
                let name = (n.name?.isEmpty == false ? n.name! : "Part") + (g.elements.count > 1 ? " \(ei + 1)" : "")
                let s = StudioObject(name: uniqueName(name), mesh: mesh, material: rec)
                s.textureImage = ViewerModel.thumbnailFull(mat?.diffuse.contents)
                add(s, select: false)
                made += 1
            }
            n.geometry = nil
        }
        if made > 0 { showToast("Made \(made) editable \(made == 1 ? "shape" : "shapes")" + (skipped > 0 ? " · \(skipped) rigged kept for posing" : "")) }
        else { showToast(skipped > 0 ? "Rigged meshes stay as they are so they can be posed" : "Nothing to convert") }
        touch()
    }

    // MARK: selection

    private func selectionChanged() {
        if let p = primaryID, selection.contains(p) {} else { primaryID = selection.first }
        if selection.isEmpty { primaryID = nil }
        clearEditSelection()
        if mode == .edit || mode == .sculpt {
            if primary?.mesh == nil { mode = .object }
        }
        refreshOverlay()
        buildGizmo()
    }

    func setPrimary(_ id: UUID) { primaryID = id }

    private func clearEditSelection() { selVerts = []; selEdges = []; selFaces = [] }

    func selectAll() {
        if mode == .edit, let m = primary?.mesh {
            switch selectMode {
            case .vertex: selVerts = Set(0..<m.vertexCount)
            case .edge: selEdges = Set(m.edges())
            case .face: selFaces = Set(0..<m.faceCount)
            }
            refreshOverlay()
        } else {
            selection = Set(objects.filter { !$0.hidden }.map(\.id))
        }
    }

    func selectNone() {
        if mode == .edit { clearEditSelection(); refreshOverlay() } else { selection = [] }
    }

    func invertSelection() {
        guard mode == .edit, let m = primary?.mesh else { return }
        switch selectMode {
        case .vertex: selVerts = Set(0..<m.vertexCount).subtracting(selVerts)
        case .edge: selEdges = Set(m.edges()).subtracting(selEdges)
        case .face: selFaces = Set(0..<m.faceCount).subtracting(selFaces)
        }
        refreshOverlay()
    }

    /// Vertices affected by the current edit selection.
    var editVertices: Set<Int> {
        guard let m = primary?.mesh else { return [] }
        switch selectMode {
        case .vertex: return selVerts
        case .edge: var s = Set<Int>(); for e in selEdges { s.insert(e.a); s.insert(e.b) }; return s
        case .face: var s = Set<Int>(); for f in selFaces where f < m.faceCount { s.formUnion(m.faces[f]) }; return s
        }
    }

    /// Faces fully covered by the selection (used by face tools in any select mode).
    var editFaces: Set<Int> {
        guard let m = primary?.mesh else { return [] }
        if selectMode == .face { return selFaces }
        let v = editVertices
        return Set(m.faces.indices.filter { m.faces[$0].allSatisfy(v.contains) })
    }

    private func convertSelection(from old: SelectMode) {
        guard let m = primary?.mesh else { return }
        let verts: Set<Int>
        switch old {
        case .vertex: verts = selVerts
        case .edge: var s = Set<Int>(); for e in selEdges { s.insert(e.a); s.insert(e.b) }; verts = s
        case .face: var s = Set<Int>(); for f in selFaces where f < m.faceCount { s.formUnion(m.faces[f]) }; verts = s
        }
        clearEditSelection()
        switch selectMode {
        case .vertex: selVerts = verts
        case .edge: selEdges = Set(m.edges().filter { verts.contains($0.a) && verts.contains($0.b) })
        case .face: selFaces = Set(m.faces.indices.filter { m.faces[$0].allSatisfy(verts.contains) })
        }
    }

    // MARK: taps

    func handleTap(at p: CGPoint) {
        guard let v = view else { return }
        switch mode {
        case .object, .sculpt:
            let hits = v.hitTest(p, options: [.categoryBitMask: Self.objectMask, .searchMode: SCNHitTestSearchMode.closest.rawValue, .ignoreHiddenNodes: true])
            if let hit = hits.first, let o = owner(of: hit.node) {
                if multiSelect {
                    if selection.contains(o.id) { selection.remove(o.id) } else { selection.insert(o.id); primaryID = o.id }
                } else { selection = [o.id] }
                Haptics.select()
            } else if mode == .object && !multiSelect {
                selection = []
            }
        case .edit:
            editTap(at: p)
        case .pose:
            poseTap(at: p)
        }
    }

    private func owner(of node: SCNNode) -> StudioObject? {
        var n: SCNNode? = node
        while let c = n {
            if let o = objects.first(where: { $0.node === c }) { return o }
            n = c.parent
        }
        return nil
    }

    private func project(_ w: SIMD3<Float>) -> SIMD3<Float> {
        guard let v = view else { return .zero }
        let p = v.projectPoint(SCNVector3(w))
        return SIMD3(Float(p.x), Float(p.y), Float(p.z))
    }

    private func editTap(at p: CGPoint) {
        guard let o = primary, let mesh = o.mesh, let v = view else { return }
        let world = o.node.simdWorldTransform
        func w(_ i: Int) -> SIMD3<Float> { let q = world * SIMD4(mesh.positions[i], 1); return SIMD3(q.x, q.y, q.z) }
        let tp = SIMD2<Float>(Float(p.x), Float(p.y))
        switch selectMode {
        case .face:
            let hits = v.hitTest(p, options: [.rootNode: o.node, .searchMode: SCNHitTestSearchMode.closest.rawValue, .ignoreHiddenNodes: true])
            if let h = hits.first(where: { $0.node === o.node }), h.faceIndex < o.triangleFace.count {
                let f = Int(o.triangleFace[h.faceIndex])
                if multiSelect { if selFaces.contains(f) { selFaces.remove(f) } else { selFaces.insert(f) } } else { selFaces = [f] }
                Haptics.select()
            } else if !multiSelect { selFaces = [] }
        case .vertex:
            var best: (Int, Float)? = nil
            for i in 0..<mesh.vertexCount {
                let s = project(w(i))
                let d = simd_length(SIMD2(s.x, s.y) - tp)
                guard d < 30, s.z > 0, s.z < 1 else { continue }
                if let b = best, s.z >= b.1 { continue }
                best = (i, s.z)
            }
            if let found = best {
                let i = found.0
                if multiSelect { if selVerts.contains(i) { selVerts.remove(i) } else { selVerts.insert(i) } } else { selVerts = [i] }
                Haptics.select()
            } else if !multiSelect { selVerts = [] }
        case .edge:
            var best: (EditMesh.Edge, Float)? = nil
            for e in mesh.edges() {
                let a = project(w(e.a)), b = project(w(e.b))
                let a2 = SIMD2(a.x, a.y), b2 = SIMD2(b.x, b.y)
                let ab = b2 - a2; let len2 = simd_length_squared(ab)
                let t = len2 > 0 ? max(0, min(1, simd_dot(tp - a2, ab) / len2)) : 0
                let d = simd_length(a2 + ab * t - tp)
                let z = (a.z + b.z) / 2
                guard d < 22, z > 0, z < 1 else { continue }
                if let b = best, z >= b.1 { continue }
                best = (e, z)
            }
            if let found = best {
                let e = found.0
                if multiSelect { if selEdges.contains(e) { selEdges.remove(e) } else { selEdges.insert(e) } } else { selEdges = [e] }
                Haptics.select()
            } else if !multiSelect { selEdges = [] }
        }
        refreshOverlay(); buildGizmo()
    }

    // MARK: edit overlay (wireframe, points, selected faces)

    func refreshOverlay() {
        overlay.removeFromParentNode()
        overlay.childNodes.forEach { $0.removeFromParentNode() }
        guard mode == .edit, let o = primary, let mesh = o.mesh else { return }
        o.node.addChildNode(overlay)
        overlay.simdTransform = matrix_identity_float4x4
        let size = simd_length(mesh.bounds.max - mesh.bounds.min)
        let eps = max(size * 0.0015, 0.0005)
        let vn = mesh.vertexNormals()
        let lifted = mesh.positions.enumerated().map { $0.element + vn[$0.offset] * eps }
        let src = SCNGeometrySource(vertices: lifted.map { SCNVector3($0) })
        let accent = UIColor.tintColor
        func mat(_ c: UIColor, depth: Bool = true) -> SCNMaterial {
            let m = SCNMaterial(); m.lightingModel = .constant; m.diffuse.contents = c; m.readsFromDepthBuffer = depth && !xray; m.isDoubleSided = true; return m
        }
        // Wireframe
        let edges = mesh.edges()
        let selE: Set<EditMesh.Edge> = selectMode == .edge ? selEdges : Set(edges.filter { editVertices.contains($0.a) && editVertices.contains($0.b) })
        var normal: [UInt32] = [], picked: [UInt32] = []
        for e in edges { if selE.contains(e) { picked += [UInt32(e.a), UInt32(e.b)] } else { normal += [UInt32(e.a), UInt32(e.b)] } }
        var els: [SCNGeometryElement] = []; var mats: [SCNMaterial] = []
        if !normal.isEmpty { els.append(SCNGeometryElement(indices: normal, primitiveType: .line)); mats.append(mat(UIColor.black.withAlphaComponent(0.55))) }
        if !picked.isEmpty { els.append(SCNGeometryElement(indices: picked, primitiveType: .line)); mats.append(mat(accent)) }
        if !els.isEmpty {
            let g = SCNGeometry(sources: [src], elements: els); g.materials = mats
            let n = SCNNode(geometry: g); n.renderingOrder = 2000; n.categoryBitMask = Self.helperMask; overlay.addChildNode(n)
        }
        // Points in vertex mode
        if selectMode == .vertex {
            var a: [UInt32] = [], b: [UInt32] = []
            for i in 0..<mesh.vertexCount { if selVerts.contains(i) { b.append(UInt32(i)) } else { a.append(UInt32(i)) } }
            var pe: [SCNGeometryElement] = []; var pm: [SCNMaterial] = []
            for (list, color, size) in [(a, UIColor.black, CGFloat(5)), (b, accent, CGFloat(9))] where !list.isEmpty {
                let e = SCNGeometryElement(indices: list, primitiveType: .point)
                e.pointSize = size; e.minimumPointScreenSpaceRadius = size / 2; e.maximumPointScreenSpaceRadius = size / 2
                pe.append(e); pm.append(mat(color))
            }
            let g = SCNGeometry(sources: [src], elements: pe); g.materials = pm
            let n = SCNNode(geometry: g); n.renderingOrder = 2001; n.categoryBitMask = Self.helperMask; overlay.addChildNode(n)
        }
        // Highlight selected faces
        let faces = selectMode == .face ? selFaces : editFaces
        if !faces.isEmpty {
            var idx: [UInt32] = []
            for f in faces where f < mesh.faceCount { let fv = mesh.faces[f]; for i in 1..<max(1, fv.count - 1) { idx += [UInt32(fv[0]), UInt32(fv[i]), UInt32(fv[i + 1])] } }
            if !idx.isEmpty {
                let g = SCNGeometry(sources: [src], elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
                let m = mat(accent.withAlphaComponent(0.35)); m.writesToDepthBuffer = false; m.blendMode = .alpha
                g.materials = [m]
                let n = SCNNode(geometry: g); n.renderingOrder = 1999; n.categoryBitMask = Self.helperMask; overlay.addChildNode(n)
            }
        }
    }

    private func applyXray() {
        for o in objects { o.node.opacity = (xray && mode == .edit && o.id == primaryID) ? 0.45 : 1 }
        if mode == .edit { refreshOverlay() }
    }

    // MARK: modes

    private func modeChanged(from old: StudioMode) {
        if old == .pose { posePlaying = false; jointsRoot.childNodes.forEach { $0.removeFromParentNode() } }
        switch mode {
        case .edit, .sculpt:
            if primary?.mesh == nil {
                if let first = objects.first(where: { $0.mesh != nil && !$0.hidden }) { selection = [first.id] }
                else { showToast("Add or convert a shape first"); mode = .object; return }
            }
            if mode == .sculpt, let p = primary, var m = p.mesh, !m.smooth { m.smooth = true; p.mesh = m; rebuild(p) }
            if mode == .sculpt, let m = primary?.mesh, m.vertexCount < 1500 { showToast("Tip: tap Add Detail for smoother sculpting") }
        case .pose:
            collectBones()
            if bones.isEmpty { showToast("Pose needs a rigged model. Open one in the viewer, then tap Studio."); mode = .object; return }
        case .object: break
        }
        clearEditSelection()
        applyXray()
        refreshOverlay()
        buildGizmo()
        if mode == .pose { buildJoints() }
    }

    // MARK: gizmo

    private enum Handle: Equatable { case axis(Int), center }
    private var dragHandle: Handle?
    private var dragStart = CGPoint.zero
    private var dragStartAngle: Float = 0
    private var startTransforms: [UUID: (SIMD3<Float>, simd_quatf, SIMD3<Float>)] = [:]
    private var startPositions: [SIMD3<Float>] = []
    private var startBone: (SIMD3<Float>, simd_quatf, SIMD3<Float>)?
    private var startPivot = SIMD3<Float>(repeating: 0)
    private let axes: [SIMD3<Float>] = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]

    var gizmoVisible: Bool {
        switch mode {
        case .object: return !selection.isEmpty
        case .edit: return !editVertices.isEmpty
        case .pose: return selectedBone != nil
        case .sculpt: return false
        }
    }

    private var pivot: SIMD3<Float>? {
        switch mode {
        case .object:
            guard let p = primary else { return nil }
            return p.node.simdWorldPosition
        case .edit:
            guard let o = primary, let m = o.mesh else { return nil }
            let vs = editVertices; guard !vs.isEmpty else { return nil }
            var c = SIMD3<Float>(repeating: 0); for v in vs { c += m.positions[v] }; c /= Float(vs.count)
            return o.node.simdConvertPosition(c, to: nil)
        case .pose: return selectedBone?.node.simdWorldPosition
        case .sculpt: return nil
        }
    }

    func buildGizmo() {
        gizmo.childNodes.forEach { $0.removeFromParentNode() }
        let colors: [UIColor] = [.systemRed, .systemGreen, .systemBlue]
        func mat(_ c: UIColor) -> SCNMaterial { let m = SCNMaterial(); m.lightingModel = .constant; m.diffuse.contents = c; m.readsFromDepthBuffer = false; m.writesToDepthBuffer = false; return m }
        let kind: GizmoKind = (mode == .pose && gizmoKind == .scale) ? GizmoKind.rotate : gizmoKind
        for i in 0..<3 {
            let axisNode = SCNNode()
            switch kind {
            case .move, .scale:
                let shaft = SCNCylinder(radius: 0.012, height: 0.8); shaft.materials = [mat(colors[i])]
                let sn = SCNNode(geometry: shaft); sn.position.y = 0.4
                let tipGeo: SCNGeometry
                if kind == .move { tipGeo = SCNCone(topRadius: 0, bottomRadius: 0.05, height: 0.16) }
                else { tipGeo = SCNBox(width: 0.09, height: 0.09, length: 0.09, chamferRadius: 0.01) }
                tipGeo.materials = [mat(colors[i])]
                let tn = SCNNode(geometry: tipGeo); tn.position.y = 0.88
                axisNode.addChildNode(sn); axisNode.addChildNode(tn)
                if i == 0 { axisNode.eulerAngles.z = -.pi / 2 } else if i == 2 { axisNode.eulerAngles.x = .pi / 2 }
            case .rotate:
                let ring = SCNTorus(ringRadius: 0.8, pipeRadius: 0.012); ring.materials = [mat(colors[i])]
                axisNode.geometry = ring
                if i == 0 { axisNode.eulerAngles.z = .pi / 2 } else if i == 2 { axisNode.eulerAngles.x = .pi / 2 }
            }
            axisNode.enumerateHierarchy { n, _ in n.renderingOrder = 3000 + i; n.categoryBitMask = Self.helperMask }
            gizmo.addChildNode(axisNode)
        }
        let c = SCNSphere(radius: kind == .rotate ? 0.07 : 0.06); c.materials = [mat(UIColor.white.withAlphaComponent(0.9))]
        let cn = SCNNode(geometry: c); cn.renderingOrder = 3010; cn.categoryBitMask = Self.helperMask
        gizmo.addChildNode(cn)
        updateGizmo()
    }

    private var gizmoScale: Float {
        guard let v = view, let p = pivot else { return 1 }
        let d = simd_length(cameraNode.simdWorldPosition - p)
        let fov = Float(cameraNode.camera?.fieldOfView ?? 45) * .pi / 180
        return d * tanf(fov / 2) * 2 * (110 / Float(max(v.bounds.height, 300)))
    }

    private func updateGizmo() {
        guard gizmoVisible, let p = pivot else { gizmo.isHidden = true; return }
        gizmo.isHidden = false
        gizmo.simdPosition = p
        gizmo.simdScale = SIMD3(repeating: gizmoScale)
    }

    /// What a one-finger drag starting here would do (nil = orbit the camera).
    func dragTarget(at p: CGPoint) -> String? {
        if mode == .sculpt {
            guard let o = primary, let v = view else { return nil }
            let hits = v.hitTest(p, options: [.rootNode: o.node, .searchMode: SCNHitTestSearchMode.closest.rawValue])
            return hits.contains { $0.node === o.node } ? "sculpt" : nil
        }
        return handle(at: p) != nil ? "gizmo" : nil
    }

    private func handle(at p: CGPoint) -> Handle? {
        guard gizmoVisible, let piv = pivot else { return nil }
        let s = gizmoScale
        let tp = SIMD2<Float>(Float(p.x), Float(p.y))
        let c3 = project(piv); let c = SIMD2(c3.x, c3.y)
        if simd_length(tp - c) < 26 { return .center }
        let kind: GizmoKind = (mode == .pose && gizmoKind == .scale) ? GizmoKind.rotate : gizmoKind
        var best: (Handle, Float)? = nil
        for i in 0..<3 {
            var d: Float = .greatestFiniteMagnitude
            if kind == .rotate {
                // Distance to the projected ring.
                let a = axes[i]
                let ref: SIMD3<Float> = abs(a.y) < 0.9 ? SIMD3<Float>(0, 1, 0) : SIMD3<Float>(1, 0, 0)
                let u = simd_normalize(simd_cross(a, ref)); let w = simd_cross(a, u)
                for k in 0..<48 {
                    let t = Float(k) / 48 * 2 * .pi
                    let q = project(piv + (u * cosf(t) + w * sinf(t)) * 0.8 * s)
                    d = min(d, simd_length(SIMD2(q.x, q.y) - tp))
                }
            } else {
                let e3 = project(piv + axes[i] * s * 0.95); let e = SIMD2(e3.x, e3.y)
                let ab = e - c; let l2 = simd_length_squared(ab)
                let t = l2 > 0 ? max(0.15, min(1, simd_dot(tp - c, ab) / l2)) : 0
                d = simd_length(c + ab * t - tp)
            }
            guard d < 26 else { continue }
            if let b = best, d >= b.1 { continue }
            best = (.axis(i), d)
        }
        return best?.0
    }

    func dragBegan(at p: CGPoint) {
        if mode == .sculpt { sculptBegan(at: p); return }
        guard let h = handle(at: p), let piv = pivot else { return }
        pushUndo()
        dragHandle = h; dragStart = p; startPivot = piv
        let c = project(piv); dragStartAngle = atan2f(Float(p.y) - c.y, Float(p.x) - c.x)
        switch mode {
        case .object:
            startTransforms = [:]
            for o in selectedObjects { startTransforms[o.id] = (o.node.simdPosition, o.node.simdOrientation, o.node.simdScale) }
        case .edit:
            startPositions = primary?.mesh?.positions ?? []
        case .pose:
            if let b = selectedBone?.node { startBone = (b.simdWorldPosition, b.simdWorldOrientation, b.simdScale) }
        case .sculpt: break
        }
    }

    func dragChanged(at p: CGPoint, translation t: CGPoint) {
        if mode == .sculpt { sculptChanged(at: p, translation: t); return }
        guard let h = dragHandle, let v = view else { return }
        let piv = startPivot
        let camRight = cameraNode.simdWorldRight, camUp = cameraNode.simdWorldUp
        let d = simd_length(cameraNode.simdWorldPosition - piv)
        let fov = Float(cameraNode.camera?.fieldOfView ?? 45) * .pi / 180
        let wpp = 2 * d * tanf(fov / 2) / Float(max(v.bounds.height, 1))
        let kind: GizmoKind = (mode == .pose && gizmoKind == .scale) ? GizmoKind.rotate : gizmoKind

        switch (kind, h) {
        case (.move, .center):
            var delta = (camRight * Float(t.x) - camUp * Float(t.y)) * wpp
            if snapping { delta = (delta / 0.1).rounded() * 0.1 }
            applyMove(delta)
        case (.move, .axis(let i)):
            let along = axisDelta(i, translation: t)
            applyMove(axes[i] * (snapping ? (along / 0.1).rounded() * 0.1 : along))
        case (.rotate, .center):
            let q = simd_quatf(angle: Float(t.x) * 0.012, axis: camUp) * simd_quatf(angle: Float(t.y) * 0.012, axis: camRight)
            applyRotate(q)
        case (.rotate, .axis(let i)):
            let c = project(piv)
            let a = atan2f(Float(p.y) - c.y, Float(p.x) - c.x)
            var ang = a - dragStartAngle
            let toCam = cameraNode.simdWorldPosition - piv
            if simd_dot(axes[i], toCam) > 0 { ang = -ang }
            if snapping { let step = Float.pi / 12; ang = (ang / step).rounded() * step }
            applyRotate(simd_quatf(angle: ang, axis: axes[i]))
        case (.scale, .center):
            applyScale(SIMD3(repeating: expf(-Float(t.y) / 160)))
        case (.scale, .axis(let i)):
            let along = axisDelta(i, translation: t)
            var f = SIMD3<Float>(repeating: 1); f[i] = max(0.01, expf(along / max(gizmoScale, 1e-4)))
            applyScale(f)
        }
    }

    func dragEnded() {
        if mode == .sculpt { sculptEnded(); return }
        dragHandle = nil
        startBone = nil
        touch()
        refreshOverlay()
    }

    private func axisDelta(_ i: Int, translation t: CGPoint) -> Float {
        let c = project(startPivot), e = project(startPivot + axes[i])
        let dir = SIMD2(e.x - c.x, e.y - c.y); let ppu = simd_length(dir)
        guard ppu > 0.5 else { return 0 }
        return simd_dot(SIMD2(Float(t.x), Float(t.y)), dir / ppu) / ppu
    }

    private func applyMove(_ delta: SIMD3<Float>) {
        switch mode {
        case .object:
            for o in selectedObjects { if let s = startTransforms[o.id] { o.node.simdPosition = s.0 + delta } }
        case .edit:
            guard let o = primary, var m = o.mesh, !startPositions.isEmpty else { return }
            let inv = o.node.simdWorldTransform.inverse
            let ld4 = inv * SIMD4(delta, 0); let ld = SIMD3(ld4.x, ld4.y, ld4.z)
            m.positions = startPositions
            for v in editVertices where v < m.positions.count { m.positions[v] += ld }
            o.mesh = m; rebuild(o)
        case .pose:
            if let b = selectedBone?.node, let s = startBone { b.simdWorldPosition = s.0 + delta }
        case .sculpt: break
        }
    }

    private func applyRotate(_ q: simd_quatf) {
        switch mode {
        case .object:
            for o in selectedObjects {
                guard let s = startTransforms[o.id] else { continue }
                o.node.simdOrientation = q * s.1
                o.node.simdPosition = startPivot + q.act(s.0 - startPivot)
            }
        case .edit:
            guard let o = primary, var m = o.mesh, !startPositions.isEmpty else { return }
            let inv = o.node.simdWorldTransform.inverse
            let lp4 = inv * SIMD4(startPivot, 1); let lp = SIMD3(lp4.x, lp4.y, lp4.z)
            let la4 = inv * SIMD4(q.axis, 0); let la = simd_length(SIMD3(la4.x, la4.y, la4.z)) > 0 ? simd_normalize(SIMD3(la4.x, la4.y, la4.z)) : SIMD3<Float>(0, 1, 0)
            let lq = simd_quatf(angle: q.angle, axis: la)
            m.positions = startPositions
            for v in editVertices where v < m.positions.count { m.positions[v] = lp + lq.act(startPositions[v] - lp) }
            o.mesh = m; rebuild(o)
        case .pose:
            if let b = selectedBone?.node, let s = startBone { b.simdWorldOrientation = q * s.1 }
        case .sculpt: break
        }
    }

    private func applyScale(_ f: SIMD3<Float>) {
        switch mode {
        case .object:
            for o in selectedObjects {
                guard let s = startTransforms[o.id] else { continue }
                o.node.simdScale = s.2 * f
                if selection.count > 1 { o.node.simdPosition = startPivot + (s.0 - startPivot) * f }
            }
        case .edit:
            guard let o = primary, var m = o.mesh, !startPositions.isEmpty else { return }
            let inv = o.node.simdWorldTransform.inverse
            let lp4 = inv * SIMD4(startPivot, 1); let lp = SIMD3(lp4.x, lp4.y, lp4.z)
            m.positions = startPositions
            for v in editVertices where v < m.positions.count {
                var d = startPositions[v] - lp
                for i in 0..<3 where f[i] != 1 {
                    let a4 = inv * SIMD4(axes[i], 0); let a = simd_normalize(SIMD3(a4.x, a4.y, a4.z))
                    d += a * simd_dot(d, a) * (f[i] - 1)
                }
                m.positions[v] = lp + d
            }
            o.mesh = m; rebuild(o)
        case .pose:
            if let b = selectedBone?.node, let s = startBone { b.simdScale = s.2 * f }
        case .sculpt: break
        }
    }

    // MARK: numeric transform (properties panel)

    func setTransform(position: SIMD3<Float>? = nil, rotationDegrees: SIMD3<Float>? = nil, scale: SIMD3<Float>? = nil) {
        guard let o = primary else { return }
        if let position { o.node.simdPosition = position }
        if let r = rotationDegrees { o.node.simdEulerAngles = r * (.pi / 180) }
        if let scale { o.node.simdScale = simd_max(scale, SIMD3(repeating: 0.001)) }
        touch()
    }

    // MARK: edit operations

    private func editOp(_ name: String, _ body: (inout EditMesh) -> Void) {
        guard let o = primary, var m = o.mesh else { return }
        pushUndo()
        body(&m)
        o.mesh = m
        rebuild(o)
        buildGizmo()
        touch()
        Haptics.tap()
        showToast(name)
    }

    func extrude() {
        if selectMode != .face { selectMode = .face }
        let faces = editFaces
        guard !faces.isEmpty, let m = primary?.mesh else { showToast("Select faces to extrude"); return }
        let size = simd_length(m.bounds.max - m.bounds.min)
        editOp("Extruded — drag the arrows to adjust") { mesh in selFaces = mesh.extrude(faces: faces, distance: size * 0.12) }
        refreshOverlay(); buildGizmo()
    }

    func inset() {
        if selectMode != .face { selectMode = .face }
        let faces = editFaces
        guard !faces.isEmpty else { showToast("Select faces to inset"); return }
        editOp("Inset") { mesh in selFaces = mesh.inset(faces: faces, amount: 0.25) }
        refreshOverlay(); buildGizmo()
    }

    func bevel() {
        if selectMode != .face { selectMode = .face }
        let faces = editFaces
        guard !faces.isEmpty, let m = primary?.mesh else { showToast("Select faces to bevel"); return }
        let size = simd_length(m.bounds.max - m.bounds.min)
        editOp("Bevelled") { mesh in selFaces = mesh.bevel(faces: faces, width: size * 0.03) }
        refreshOverlay(); buildGizmo()
    }

    func subdivide(smooth: Bool) {
        guard let m = primary?.mesh else { return }
        if m.faceCount * 4 > 220_000 { showToast("That would be too many faces for a phone"); return }
        clearEditSelection()
        editOp(smooth ? "Subdivided (smooth)" : "Subdivided") { mesh in mesh = smooth ? mesh.catmullClark() : mesh.subdivideFlat() }
    }

    func smoothSelection() {
        let v = editVertices
        editOp(v.isEmpty ? "Smoothed whole mesh" : "Smoothed") { mesh in mesh.smoothVertices(v) }
    }

    func mergeSelection() {
        let v = editVertices
        guard v.count > 1 else { showToast("Select two or more vertices"); return }
        clearEditSelection()
        editOp("Merged \(v.count) vertices") { mesh in mesh.merge(v) }
    }

    func deleteEditSelection() {
        let f = editFaces, v = editVertices
        guard !v.isEmpty else { showToast("Nothing selected"); return }
        clearEditSelection()
        editOp("Deleted") { mesh in if selectMode == .face { mesh.deleteFaces(f) } else { mesh.deleteVertices(v) } }
    }

    func makeFace() {
        let v = Array(editVertices)
        guard v.count >= 3 else { showToast("Select 3 or more vertices"); return }
        editOp("Face created") { mesh in _ = mesh.makeFace(v) }
        refreshOverlay()
    }

    func flipNormals() { let f = editFaces; editOp(f.isEmpty ? "Flipped all normals" : "Flipped normals") { $0.flip(f) } }
    func mirrorX() { clearEditSelection(); editOp("Mirrored on X") { $0.mirrorX() } }
    func triangulate() { clearEditSelection(); editOp("Triangulated") { $0.triangulate() } }
    func toggleSmoothShading() {
        guard let m = primary?.mesh else { return }
        editOp(m.smooth ? "Flat shading" : "Smooth shading") { $0.smooth.toggle() }
    }
    func addDetail() {
        guard let m = primary?.mesh else { return }
        if m.faceCount * 4 > 120_000 { showToast("Already very detailed"); return }
        editOp("More detail added") { mesh in mesh = mesh.catmullClark(); mesh.smooth = true }
    }

    // MARK: sculpt

    private var sculptNeighbors: [[Int]] = []
    private var grabCaptured: [(Int, Float)] = []
    private var grabStart: [SIMD3<Float>] = []
    private var grabDepth: Float = 0
    private var grabStartWorld = SIMD3<Float>(repeating: 0)
    private var lastDab = CGPoint(x: -999, y: -999)

    private func sculptHit(at p: CGPoint) -> (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)? {
        guard let o = primary, let v = view else { return nil }
        let hits = v.hitTest(p, options: [.rootNode: o.node, .searchMode: SCNHitTestSearchMode.closest.rawValue])
        guard let h = hits.first(where: { $0.node === o.node }) else { return nil }
        return (SIMD3(h.localCoordinates), simd_normalize(SIMD3(h.localNormal)), SIMD3(h.worldCoordinates))
    }

    private var brushWorldRadius: Float {
        guard let m = primary?.mesh else { return 0.1 }
        return simd_length(m.bounds.max - m.bounds.min) * Float(brushRadius) * 0.5
    }

    private func sculptBegan(at p: CGPoint) {
        guard let o = primary, let m = o.mesh else { return }
        pushUndo()
        sculptNeighbors = m.neighbors()
        lastDab = CGPoint(x: -999, y: -999)
        if brush == .grab, let hit = sculptHit(at: p) {
            let local = hit.0, world = hit.2
            grabCaptured = m.verticesNear(local, radius: brushWorldRadius)
            if symmetryX, abs(local.x) > brushWorldRadius * 0.2 {
                let mirrored = m.verticesNear(SIMD3(-local.x, local.y, local.z), radius: brushWorldRadius)
                grabCaptured += mirrored.map { ($0.0, -$0.1) }   // negative weight marks mirrored X
            }
            grabStart = grabCaptured.map { m.positions[$0.0] }
            grabDepth = project(world).z
            grabStartWorld = world
        }
        sculptChanged(at: p, translation: .zero)
    }

    private func sculptChanged(at p: CGPoint, translation t: CGPoint) {
        guard let o = primary, var m = o.mesh, let v = view else { return }
        if brush == .grab {
            guard !grabCaptured.isEmpty else { return }
            let w = v.unprojectPoint(SCNVector3(Float(p.x), Float(p.y), grabDepth))
            let worldDelta = SIMD3<Float>(w) - grabStartWorld
            let inv = o.node.simdWorldTransform.inverse
            let l4 = inv * SIMD4(worldDelta, 0); let ld = SIMD3(l4.x, l4.y, l4.z)
            for (k, (i, wgt)) in grabCaptured.enumerated() {
                let d = wgt >= 0 ? ld * wgt : SIMD3(-ld.x, ld.y, ld.z) * (-wgt)
                m.positions[i] = grabStart[k] + d
            }
        } else {
            if hypot(p.x - lastDab.x, p.y - lastDab.y) < 3 { return }
            lastDab = p
            guard let hit = sculptHit(at: p) else { brushRing.isHidden = true; return }
            let local = hit.0, normal = hit.1, world = hit.2
            let vn = m.vertexNormals()
            let s = Float(brushStrength) * (brush == .smooth ? 1 : 0.6)
            m.sculpt(brush, at: local, normal: normal, radius: brushWorldRadius, strength: s, invert: brushInvert, neighbors: sculptNeighbors, vertexNormals: vn)
            if symmetryX, abs(local.x) > brushWorldRadius * 0.05 {
                let vn2 = m.vertexNormals()
                m.sculpt(brush, at: SIMD3(-local.x, local.y, local.z), normal: SIMD3(-normal.x, normal.y, normal.z), radius: brushWorldRadius, strength: s,
                         invert: brushInvert, neighbors: sculptNeighbors, vertexNormals: vn2)
            }
            showBrush(at: world, normal: o.node.simdConvertVector(normal, to: nil), radius: brushWorldRadius * simd_length(o.node.simdWorldTransform.columns.0))
        }
        o.mesh = m
        rebuild(o)
    }

    private func sculptEnded() {
        grabCaptured = []; grabStart = []
        brushRing.isHidden = true
        touch()
    }

    private func showBrush(at p: SIMD3<Float>, normal n: SIMD3<Float>, radius r: Float) {
        brushRing.isHidden = false
        brushRing.simdPosition = p
        let up = SIMD3<Float>(0, 1, 0)
        let nn = simd_length(n) > 0 ? simd_normalize(n) : up
        brushRing.simdOrientation = simd_quatf(from: up, to: nn)
        brushRing.simdScale = SIMD3(repeating: r)
    }

    // MARK: pose

    private func collectBones() {
        var set = Set<ObjectIdentifier>(); var boneNodes: [SCNNode] = []
        for o in objects where !o.hidden {
            o.node.enumerateHierarchy { n, _ in
                for b in n.skinner?.bones ?? [] where !set.contains(ObjectIdentifier(b)) { set.insert(ObjectIdentifier(b)); boneNodes.append(b) }
            }
        }
        if boneNodes.isEmpty {
            for o in objects { o.node.enumerateHierarchy { n, _ in if n.name?.hasPrefix("joint:") == true { set.insert(ObjectIdentifier(n)); boneNodes.append(n) } } }
        }
        var out: [BoneInfo] = []
        func walk(_ n: SCNNode, _ depth: Int) {
            let isBone = set.contains(ObjectIdentifier(n))
            if isBone { out.append(BoneInfo(node: n, depth: depth)) }
            for c in n.childNodes { walk(c, isBone ? depth + 1 : depth) }
        }
        walk(contentRoot, 0)
        bones = out
        for b in out where restPose[ObjectIdentifier(b.node)] == nil { restPose[ObjectIdentifier(b.node)] = currentTransform(b.node) }
    }

    private func currentTransform(_ n: SCNNode) -> PoseTransform { PoseTransform(p: n.simdPosition, q: n.simdOrientation, s: n.simdScale) }
    private func set(_ n: SCNNode, _ t: PoseTransform) { n.simdPosition = t.p; n.simdOrientation = t.q; n.simdScale = t.s }

    private func buildJoints() {
        jointsRoot.childNodes.forEach { $0.removeFromParentNode() }
        let r = max(0.008, (primaryRadius ?? 1) * 0.018)
        for b in bones {
            let s = SCNSphere(radius: CGFloat(r))
            let m = SCNMaterial(); m.lightingModel = .constant; m.readsFromDepthBuffer = false
            m.diffuse.contents = selectedBone == b ? UIColor.tintColor : UIColor.white.withAlphaComponent(0.85)
            s.materials = [m]
            let n = SCNNode(geometry: s); n.renderingOrder = 2500; n.categoryBitMask = Self.helperMask
            n.name = "joint-marker"
            jointsRoot.addChildNode(n)
        }
        updateJoints()
    }

    private var primaryRadius: Float? {
        var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var hi = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        for b in bones { let p = b.node.simdWorldPosition; lo = simd_min(lo, p); hi = simd_max(hi, p) }
        return bones.isEmpty ? nil : simd_length(hi - lo) / 2
    }

    private func updateJoints() {
        guard mode == .pose else { return }
        for (i, n) in jointsRoot.childNodes.enumerated() where i < bones.count { n.simdPosition = bones[i].node.simdWorldPosition }
    }

    private func poseTap(at p: CGPoint) {
        let tp = SIMD2<Float>(Float(p.x), Float(p.y))
        var best: (BoneInfo, Float)? = nil
        for b in bones {
            let s = project(b.node.simdWorldPosition)
            let d = simd_length(SIMD2(s.x, s.y) - tp)
            guard d < 32, s.z > 0, s.z < 1 else { continue }
            if let bb = best, d >= bb.1 { continue }
            best = (b, d)
        }
        if let b = best?.0 { selectBone(b) }
    }

    func selectBone(_ b: BoneInfo?) {
        selectedBone = b
        buildJoints(); buildGizmo()
        if b != nil { Haptics.select() }
    }

    func resetBone() {
        guard let b = selectedBone, let r = restPose[ObjectIdentifier(b.node)] else { return }
        pushUndo(); set(b.node, r); touch()
    }

    func resetPose() {
        pushUndo()
        for b in bones { if let r = restPose[ObjectIdentifier(b.node)] { set(b.node, r) } }
        touch(); showToast("Rest pose")
    }

    /// Copies each left bone's rotation onto its right twin (or the other way if a right bone is selected).
    func mirrorPose() {
        pushUndo()
        let byName = Dictionary(bones.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        let fromLeft = !(selectedBone.map { Self.side($0.name) == "R" } ?? false)
        var count = 0
        for b in bones where Self.side(b.name) == (fromLeft ? "L" : "R") {
            guard let twinName = Self.twin(b.name), let twin = byName[twinName] else { continue }
            let q = b.node.simdOrientation
            twin.node.simdOrientation = simd_quatf(ix: q.imag.x, iy: -q.imag.y, iz: -q.imag.z, r: q.real)
            count += 1
        }
        touch(); showToast(count > 0 ? "Mirrored \(count) bones" : "No left/right bone names found")
    }

    private static func side(_ n: String) -> String? {
        let l = n.lowercased()
        if l.contains("left") || l.hasSuffix("_l") || l.hasSuffix(".l") || l.hasPrefix("l_") || l.contains("_l_") { return "L" }
        if l.contains("right") || l.hasSuffix("_r") || l.hasSuffix(".r") || l.hasPrefix("r_") || l.contains("_r_") { return "R" }
        return nil
    }

    private static func twin(_ n: String) -> String? {
        let pairs = [("Left", "Right"), ("left", "right"), ("LEFT", "RIGHT"), ("_L", "_R"), (".L", ".R"), ("_l", "_r"), (".l", ".r"), ("L_", "R_"), ("l_", "r_")]
        for (a, b) in pairs {
            if n.contains(a) { return n.replacingOccurrences(of: a, with: b) }
            if n.contains(b) { return n.replacingOccurrences(of: b, with: a) }
        }
        return nil
    }

    func addKey() {
        let t = (poseTime * 100).rounded() / 100
        var transforms: [ObjectIdentifier: PoseTransform] = [:]
        for b in bones { transforms[ObjectIdentifier(b.node)] = currentTransform(b.node) }
        keys.removeAll { abs($0.time - t) < 0.005 }
        keys.append(PoseKey(time: t, transforms: transforms))
        keys.sort { $0.time < $1.time }
        Haptics.tap(.medium)
        showToast("Key at \(String(format: "%.2f", t)) s")
    }

    func deleteKey() {
        let before = keys.count
        keys.removeAll { abs($0.time - poseTime) < 0.03 }
        showToast(keys.count < before ? "Key removed" : "No key here")
    }

    func applyPose(at t: Double) {
        guard mode == .pose, !keys.isEmpty else { return }
        let next = keys.firstIndex { $0.time >= t } ?? keys.count - 1
        let prev = max(0, keys.lastIndex { $0.time <= t } ?? 0)
        let a = keys[prev], b = keys[next]
        let span = b.time - a.time
        let f = Float(span > 0 ? (t - a.time) / span : 0)
        for bone in bones {
            let k = ObjectIdentifier(bone.node)
            guard let ta = a.transforms[k], let tb = b.transforms[k] else { continue }
            var qb = tb.q; if simd_dot(ta.q.vector, qb.vector) < 0 { qb = simd_quatf(vector: -qb.vector) }
            set(bone.node, PoseTransform(p: ta.p + (tb.p - ta.p) * f, q: simd_slerp(ta.q, qb, f), s: ta.s + (tb.s - ta.s) * f))
        }
    }

    /// Turns the keys into a real animation clip attached to the bones (plays in the viewer and exports with USDZ).
    func saveAnimation(name: String) -> ClipInfo? {
        guard keys.count >= 2 else { showToast("Add at least two keys first"); return nil }
        let dur = max(poseDuration, keys.last!.time)
        savedClipCount += 1
        var players: [SCNAnimationPlayer] = []
        for bone in bones {
            let k = ObjectIdentifier(bone.node)
            let tr = keys.compactMap { $0.transforms[k] }
            guard tr.count == keys.count else { continue }
            let moved = tr.contains { simd_length($0.p - tr[0].p) > 1e-5 }
            let turned = tr.contains { abs(simd_dot($0.q.vector, tr[0].q.vector)) < 0.99999 }
            let scaled = tr.contains { simd_length($0.s - tr[0].s) > 1e-5 }
            guard moved || turned || scaled else { continue }
            let times = keys.map { NSNumber(value: $0.time / dur) }
            var anims: [CAAnimation] = []
            func kf(_ path: String, _ values: [NSValue]) -> CAKeyframeAnimation {
                var v = values; var t = times
                if t.first!.doubleValue > 0 { t.insert(0, at: 0); v.insert(v.first!, at: 0) }
                if t.last!.doubleValue < 1 { t.append(1); v.append(v.last!) }
                let a = CAKeyframeAnimation(keyPath: path); a.values = v; a.keyTimes = t; a.duration = dur; return a
            }
            var prev = tr[0].q
            let qs: [NSValue] = tr.map { t in
                var q = t.q; if simd_dot(q.vector, prev.vector) < 0 { q = simd_quatf(vector: -q.vector) }; prev = q
                return NSValue(scnVector4: SCNVector4(q.imag.x, q.imag.y, q.imag.z, q.real))
            }
            anims.append(kf("orientation", qs))
            if moved { anims.append(kf("position", tr.map { NSValue(scnVector3: SCNVector3($0.p)) })) }
            if scaled { anims.append(kf("scale", tr.map { NSValue(scnVector3: SCNVector3($0.s)) })) }
            let g = CAAnimationGroup(); g.animations = anims; g.duration = dur
            let sa = SCNAnimation(caAnimation: g); sa.repeatCount = .greatestFiniteMagnitude; sa.isRemovedOnCompletion = false
            let p = SCNAnimationPlayer(animation: sa)
            bone.node.addAnimationPlayer(p, forKey: "studio-\(savedClipCount)")
            p.stop()
            players.append(p)
        }
        guard !players.isEmpty else { showToast("The keys don't change any bones"); return nil }
        let clip = ClipInfo(name: name.isEmpty ? "Studio Animation \(savedClipCount)" : name, duration: dur, players: players)
        savedClips.append(clip)
        showToast("Saved “\(clip.name)”")
        return clip
    }

    // MARK: per-frame

    private func tick(_ l: CADisplayLink) {
        let dt = lastTick == 0 ? 0 : l.timestamp - lastTick
        lastTick = l.timestamp
        if posePlaying, mode == .pose, keys.count >= 2 {
            var t = poseTime + dt
            let end = max(poseDuration, keys.last!.time)
            if t > end { if loopPose { t = 0 } else { t = end; posePlaying = false } }
            poseTime = t
            applyPose(at: t)
        }
        updateGizmo()
        updateJoints()
    }

    // MARK: undo

    private func snapshot() -> StudioSnapshot {
        var pose: [ObjectIdentifier: PoseTransform] = [:]
        for b in bones { pose[ObjectIdentifier(b.node)] = currentTransform(b.node) }
        return StudioSnapshot(objects: objects.map(record), order: objects.map(\.id), pose: pose)
    }

    private func record(_ o: StudioObject) -> ObjectRecord {
        ObjectRecord(id: o.id, name: o.name, mesh: o.mesh, material: o.material, transform: TransformRecord(o.node), hidden: o.hidden)
    }

    func pushUndo() {
        undoStack.append(snapshot())
        if undoStack.count > 40 { undoStack.removeFirst() }
        redoStack = []
        canUndo = true; canRedo = false
    }

    private var graveyard: [UUID: StudioObject] = [:]

    private func restore(_ s: StudioSnapshot) {
        var byID: [UUID: StudioObject] = [:]
        for o in objects { byID[o.id] = o }
        for (id, o) in graveyard { byID[id] = byID[id] ?? o }
        var result: [StudioObject] = []
        for r in s.objects {
            let o = byID[r.id] ?? StudioObject(id: r.id, name: r.name, mesh: r.mesh, material: r.material)
            o.name = r.name; o.mesh = r.mesh; o.material = r.material; o.hidden = r.hidden
            r.transform.apply(to: o.node)
            o.node.isHidden = r.hidden
            if o.node.parent == nil { contentRoot.addChildNode(o.node) }
            if o.mesh != nil { rebuild(o, keepMaterial: false) }
            result.append(o)
        }
        for o in objects where !s.order.contains(o.id) { o.node.removeFromParentNode(); graveyard[o.id] = o }
        objects = result
        for b in bones { if let t = s.pose[ObjectIdentifier(b.node)] { set(b.node, t) } }
        selection = selection.filter { id in objects.contains { $0.id == id } }
        clearEditSelection()
        refreshOverlay(); buildGizmo(); touch()
    }

    func undo() {
        guard let s = undoStack.popLast() else { return }
        redoStack.append(snapshot())
        restore(s)
        canUndo = !undoStack.isEmpty; canRedo = true
        Haptics.tap()
    }

    func redo() {
        guard let s = redoStack.popLast() else { return }
        undoStack.append(snapshot())
        restore(s)
        canUndo = true; canRedo = !redoStack.isEmpty
        Haptics.tap()
    }

    func focusSelection() {
        let targets = selectedObjects.isEmpty ? objects.filter { !$0.hidden } : selectedObjects
        var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var hi = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        for o in targets {
            o.node.enumerateHierarchy { n, _ in
                guard n.geometry != nil, n.categoryBitMask & Self.helperMask == 0 else { return }
                let (a, b) = n.boundingBox
                for i in 0..<8 {
                    let c = SIMD3<Float>(i & 1 == 0 ? Float(a.x) : Float(b.x), i & 2 == 0 ? Float(a.y) : Float(b.y), i & 4 == 0 ? Float(a.z) : Float(b.z))
                    let w = n.simdConvertPosition(c, to: nil); lo = simd_min(lo, w); hi = simd_max(hi, w)
                }
            }
        }
        guard lo.x <= hi.x else { orbit.frame(center: SIMD3(0, 0.5, 0), radius: 1.2, distance: 3.6, animated: true); return }
        let r = max(simd_length(hi - lo) / 2, 0.05)
        orbit.frame(center: (lo + hi) / 2, radius: r, distance: r / sinf(22.5 * .pi / 180) * 1.25, animated: true)
    }
}


/// Lets a CADisplayLink call back into a non-NSObject class.
final class DisplayLinkProxy: NSObject {
    let callback: (CADisplayLink) -> Void
    init(_ cb: @escaping (CADisplayLink) -> Void) { callback = cb }
    @objc func step(_ l: CADisplayLink) { callback(l) }
}
