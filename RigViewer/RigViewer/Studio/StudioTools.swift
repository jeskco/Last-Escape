import SwiftUI
import SceneKit
import Metal
import simd

/// Studio 2 tools: adjustable operations, primitives, modifiers, booleans, remesh, origins, lights,
/// vertex paint, UVs, viewport shading, world and rendering.
extension StudioModel {

    // MARK: - Heavy work

    func perform(_ work: @escaping () -> Void) {
        let faces = primary?.mesh?.faceCount ?? 0
        guard faces > 40_000, busy == nil else { work(); return }
        busy = "Working…"
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 40_000_000)
            work()
            busy = nil
        }
    }

    // MARK: - Adjustable operations (Blender's "Adjust Last Operation")

    /// Runs an edit on the primary mesh and keeps it adjustable afterwards.
    func runAdjustable(_ title: String, params: [OpParam], _ body: @escaping (inout EditMesh, [Double]) -> Void) {
        guard let o = primary, let before = o.mesh else { return }
        pushUndo()
        var m = before
        body(&m, params.map(\.value))
        o.mesh = m
        rebuild(o); refreshOverlay(); buildGizmo(); touch()
        Haptics.tap()
        lastOp = LastOperation(title: title, params: params, objectID: o.id, before: before, run: body)
    }

    func adjustLastOp(_ index: Int, _ value: Double) {
        guard let op = lastOp, index < op.params.count, let o = objects.first(where: { $0.id == op.objectID }) else { return }
        var v = value
        if let st = op.params[index].step, st > 0 { v = (v / st).rounded() * st }
        op.params[index].value = min(max(v, op.params[index].range.lowerBound), op.params[index].range.upperBound)
        var m = op.before
        op.run(&m, op.params.map(\.value))
        o.mesh = m
        rebuild(o); refreshOverlay(); buildGizmo(); touch()
        objectWillChange.send()
    }

    private var meshSize: Float {
        guard let m = primary?.mesh else { return 1 }
        return max(simd_length(m.bounds.max - m.bounds.min), 0.01)
    }

    // MARK: - Primitives

    func addPrimitive(_ p: Primitive, text: String = "Text") {
        pushUndo()
        if mode != .object { mode = .object }
        let mesh = p.mesh([], text: text)
        let o = StudioObject(name: uniqueName(p == .text ? text : p.rawValue), mesh: mesh,
                             material: p == .clay ? MaterialRecord.presets[0].1 : MaterialRecord())
        let b = mesh.bounds
        var x: Float = 0
        let occupied = objects.filter { !$0.hidden }.map { $0.node.simdPosition.x }
        while occupied.contains(where: { abs($0 - x) < 0.6 }) && x < 20 { x += 1.2 }
        o.node.simdPosition = SIMD3(x, -b.min.y, 0)
        add(o)
        if objects.count == 1 { focusSelection() }
        Haptics.tap()
        let groundY = o.node.simdPosition.y + b.min.y
        lastOp = LastOperation(title: "Add \(p.rawValue)", params: p.params, objectID: o.id, before: mesh) { [weak o] m, v in
            m = p.mesh(v, text: text)
            // keep it resting on the floor as it grows
            if let o { o.node.simdPosition.y = groundY - m.bounds.min.y }
        }
    }

    // MARK: - Lights

    func addLight(_ kind: LightKind) {
        pushUndo()
        if mode != .object { mode = .object }
        let o = StudioObject(name: uniqueName("\(kind.rawValue) Light"), mesh: nil)
        var rec = LightRecord(); rec.kind = kind
        switch kind {
        case .point: rec.intensity = 900; o.node.simdPosition = [1.2, 2, 1.2]
        case .spot: rec.intensity = 2200; rec.angle = 50; o.node.simdPosition = [0, 3, 2]; o.node.simdLook(at: [0, 0.4, 0])
        case .sun: rec.intensity = 900; o.node.simdPosition = [0, 4, 0]; o.node.simdEulerAngles = [-1.0, 0.6, 0]
        case .area: rec.intensity = 1500; o.node.simdPosition = [0, 2.5, 1.5]; o.node.simdLook(at: [0, 0.5, 0])
        }
        o.light = rec
        configureLight(o)
        add(o)
        showToast("\(kind.rawValue) light added · see Properties")
    }

    func configureLight(_ o: StudioObject) {
        o.node.childNodes.filter { $0.name == "light-gizmo" }.forEach { $0.removeFromParentNode() }
        guard let rec = o.light else { o.node.light = nil; return }
        let l = o.node.light ?? SCNLight()
        switch rec.kind {
        case .point: l.type = .omni
        case .spot: l.type = .spot; l.spotOuterAngle = CGFloat(rec.angle); l.spotInnerAngle = CGFloat(rec.angle * 0.6)
        case .sun: l.type = .directional
        case .area: l.type = .area; l.areaType = .rectangle; l.areaExtents = simd_float3(1, 1, 0)
        }
        l.color = UIColor(red: CGFloat(rec.r), green: CGFloat(rec.g), blue: CGFloat(rec.b), alpha: 1)
        l.intensity = CGFloat(rec.intensity)
        l.castsShadow = rec.shadows && (rec.kind == .spot || rec.kind == .sun)
        l.shadowMode = .deferred; l.shadowSampleCount = 8; l.shadowRadius = 3
        l.shadowColor = UIColor(white: 0, alpha: 0.45)
        if rec.kind == .sun { l.automaticallyAdjustsShadowProjection = true }
        o.node.light = l
        // A small marker you can tap to select the light.
        let marker = SCNNode()
        marker.name = "light-gizmo"
        let m = SCNMaterial(); m.lightingModel = .constant
        m.diffuse.contents = UIColor(red: CGFloat(rec.r), green: CGFloat(rec.g), blue: CGFloat(rec.b), alpha: 1)
        let ball = SCNSphere(radius: 0.08); ball.materials = [m]
        let bn = SCNNode(geometry: ball)
        marker.addChildNode(bn)
        if rec.kind != .point {
            let cone = SCNCone(topRadius: 0.0, bottomRadius: 0.07, height: 0.3); cone.materials = [m]
            let cn = SCNNode(geometry: cone); cn.simdPosition = [0, 0, -0.2]; cn.simdEulerAngles = [-.pi / 2, 0, 0]
            marker.addChildNode(cn)
        }
        marker.enumerateHierarchy { n, _ in n.categoryBitMask = Self.objectMask; n.castsShadow = false }
        o.node.addChildNode(marker)
    }

    func updateLight(_ o: StudioObject, _ change: (inout LightRecord) -> Void) {
        guard var rec = o.light else { return }
        change(&rec)
        o.light = rec
        configureLight(o)
        touch()
    }

    // MARK: - Materials, shading, world

    func refreshAllMaterials() {
        for o in objects where o.mesh != nil { o.node.geometry?.materials = [material(for: o)] }
    }

    func applyWorld() {
        let w = world
        scene.lightingEnvironment.intensity = CGFloat(w.environment)
        switch w.background {
        case .studio:
            scene.lightingEnvironment.contents = ViewerModel.studioEnvironment
            scene.background.contents = nil
        case .sky, .sunset, .night:
            let img = Self.skyImage(w.background)
            scene.lightingEnvironment.contents = img
            scene.background.contents = img
        case .color:
            scene.lightingEnvironment.contents = ViewerModel.studioEnvironment
            scene.background.contents = UIColor(red: CGFloat(w.r), green: CGFloat(w.g), blue: CGFloat(w.b), alpha: 1)
        case .transparent:
            scene.lightingEnvironment.contents = ViewerModel.studioEnvironment
            scene.background.contents = nil
        }
        sunNode.light?.intensity = w.sun ? CGFloat(w.sunIntensity) : 0
        sunNode.light?.castsShadow = w.sun
        sunNode.simdEulerAngles = SIMD3(-w.sunElevation * .pi / 180, w.sunRotation * .pi / 180, 0)
        for c in grid.childNodes where c.geometry is SCNFloor { c.isHidden = !w.floorShadow }
    }

    static func skyImage(_ b: WorldBackground) -> UIImage {
        let (top, mid, bottom): (UIColor, UIColor, UIColor)
        switch b {
        case .sunset: (top, mid, bottom) = (UIColor(red: 0.18, green: 0.2, blue: 0.45, alpha: 1), UIColor(red: 1, green: 0.55, blue: 0.3, alpha: 1), UIColor(red: 0.25, green: 0.16, blue: 0.14, alpha: 1))
        case .night: (top, mid, bottom) = (UIColor(red: 0.01, green: 0.02, blue: 0.06, alpha: 1), UIColor(red: 0.06, green: 0.09, blue: 0.18, alpha: 1), UIColor(red: 0.02, green: 0.02, blue: 0.03, alpha: 1))
        default: (top, mid, bottom) = (UIColor(red: 0.2, green: 0.45, blue: 0.88, alpha: 1), UIColor(red: 0.75, green: 0.86, blue: 0.97, alpha: 1), UIColor(red: 0.36, green: 0.34, blue: 0.3, alpha: 1))
        }
        let size = CGSize(width: 8, height: 256)
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        return UIGraphicsImageRenderer(size: size, format: fmt).image { ctx in
            let cs = CGColorSpaceCreateDeviceRGB()
            let g = CGGradient(colorsSpace: cs, colors: [top.cgColor, mid.cgColor, mid.cgColor, bottom.cgColor] as CFArray, locations: [0, 0.48, 0.5, 0.56])!
            ctx.cgContext.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: size.height), options: [.drawsAfterEndLocation])
        }
    }

    func setProcedural(_ kind: ProceduralTexture, on o: StudioObject) {
        pushUndo()
        o.textureImage = Self.proceduralImage(kind)
        if o.material.tiling == nil { o.material.tiling = 1 }
        applyMaterial(o)
        showToast("\(kind.rawValue) texture")
    }

    // MARK: - Edit-mode selection tools

    func selectLinked() {
        guard let m = primary?.mesh else { return }
        switch selectMode {
        case .face: selFaces = m.linkedFaces(selFaces.isEmpty ? [] : selFaces)
        case .vertex: selVerts = m.linkedVertices(selVerts)
        case .edge:
            let v = m.linkedVertices(editVertices)
            selEdges = Set(m.edges().filter { v.contains($0.a) && v.contains($0.b) })
        }
        refreshOverlay(); buildGizmo(); Haptics.select()
    }

    func growSelection(_ grow: Bool) {
        guard let m = primary?.mesh else { return }
        switch selectMode {
        case .face: selFaces = grow ? m.growFaces(selFaces) : m.shrinkFaces(selFaces)
        case .vertex: selVerts = grow ? m.growVertices(selVerts) : m.shrinkVertices(selVerts)
        case .edge:
            let v = grow ? m.growVertices(editVertices) : m.shrinkVertices(editVertices)
            selEdges = Set(m.edges().filter { v.contains($0.a) && v.contains($0.b) })
        }
        refreshOverlay(); buildGizmo(); Haptics.select()
    }

    func selectEdgeLoop(ring: Bool = false) {
        guard let m = primary?.mesh else { return }
        if selectMode != .edge {
            selectMode = .edge
        }
        guard !selEdges.isEmpty else { showToast("Tap an edge first, then Loop"); return }
        var out = Set<EditMesh.Edge>()
        for e in selEdges { out.formUnion(ring ? Set(m.edgeRing(from: e).edges) : m.edgeLoop(from: e)) }
        selEdges = out
        refreshOverlay(); buildGizmo(); Haptics.select()
    }

    // MARK: - Edit-mode mesh tools

    func extrude() {
        if selectMode != .face { selectMode = .face }
        let faces = editFaces
        guard !faces.isEmpty else { showToast("Select faces to extrude"); return }
        let d = Double(meshSize * 0.12)
        runAdjustable("Extrude", params: [OpParam("Distance", d, -Double(meshSize)...Double(meshSize) * 2)]) { [unowned self] m, v in
            self.selFaces = m.extrude(faces: faces, distance: Float(v[0]))
        }
    }

    func inset() {
        if selectMode != .face { selectMode = .face }
        let faces = editFaces
        guard !faces.isEmpty else { showToast("Select faces to inset"); return }
        runAdjustable("Inset", params: [OpParam("Amount", 0.25, 0.01...0.95)]) { [unowned self] m, v in
            self.selFaces = m.inset(faces: faces, amount: Float(v[0]))
        }
    }

    func bevel() {
        if selectMode != .face { selectMode = .face }
        let faces = editFaces
        guard !faces.isEmpty else { showToast("Select faces to bevel"); return }
        let size = Double(meshSize)
        runAdjustable("Bevel", params: [OpParam("Width", size * 0.03, 0...size * 0.5), OpParam("Inset", 0.18, 0.01...0.9)]) { [unowned self] m, v in
            var s = m.inset(faces: faces, amount: Float(v[1]))
            s = m.extrude(faces: s, distance: Float(v[0]))
            self.selFaces = s
        }
    }

    func subdivide(smooth: Bool) {
        guard let m = primary?.mesh else { return }
        if m.faceCount * 4 > 220_000 { showToast("That would be too many faces for a phone"); return }
        clearEditSelection()
        runAdjustable(smooth ? "Subdivide (Smooth)" : "Subdivide", params: [OpParam("Levels", 1, 1...3, step: 1)]) { m, v in
            for _ in 0..<Int(v[0]) {
                if m.faceCount * 4 > 220_000 { break }
                m = smooth ? m.catmullClark() : m.subdivideFlat()
            }
        }
    }

    func smoothSelection() {
        let v = editVertices
        runAdjustable("Smooth", params: [OpParam("Factor", 0.5, 0...1), OpParam("Repeat", 2, 1...30, step: 1)]) { m, p in
            m.smoothVertices(v, factor: Float(p[0]), iterations: Int(p[1]))
        }
    }

    func loopCut() {
        guard let m = primary?.mesh else { return }
        if selectMode != .edge { selectMode = .edge; showToast("Tap an edge to cut across, then Loop Cut"); return }
        guard let e = selEdges.first else { showToast("Tap an edge to cut across"); return }
        guard !m.edgeRing(from: e).quads.isEmpty else { showToast("Loop cut needs quads around that edge"); return }
        runAdjustable("Loop Cut", params: [OpParam("Cuts", 1, 1...16, step: 1)]) { [unowned self] m, v in
            let new = m.loopCut(edge: e, cuts: Int(v[0]))
            let es = m.edges().filter { new.contains($0.a) && new.contains($0.b) }
            self.selEdges = Set(es)
        }
    }

    func dissolve() {
        switch selectMode {
        case .edge:
            let es = selEdges
            guard !es.isEmpty else { showToast("Select edges to dissolve"); return }
            clearEditSelection()
            editOp("Dissolved \(es.count) edges") { $0.dissolveEdges(es) }
        default:
            let f = editFaces
            guard f.count > 1 else { showToast("Select two or more neighbouring faces"); return }
            clearEditSelection()
            editOp("Dissolved faces") { $0.dissolveFaces(f) }
        }
        refreshOverlay()
    }

    func poke() {
        let f = editFaces
        guard !f.isEmpty else { showToast("Select faces to poke"); return }
        editOp("Poked \(f.count) faces") { [unowned self] m in self.selFaces = m.poke(f) }
        if selectMode != .face { selectMode = .face }
        refreshOverlay()
    }

    func trisToQuads() { clearEditSelection(); editOp("Triangles joined into quads") { $0.trisToQuads() } }
    func recalculateNormals() { editOp("Normals recalculated (outside)") { $0.recalculateNormals() } }

    func shrinkFatten() {
        let v = editVertices
        runAdjustable("Shrink/Fatten", params: [OpParam("Offset", Double(meshSize) * 0.03, -Double(meshSize) * 0.5...Double(meshSize) * 0.5)]) { m, p in
            m.shrinkFatten(v, amount: Float(p[0]))
        }
    }

    func toSphere() {
        let v = editVertices
        runAdjustable("To Sphere", params: [OpParam("Factor", 1, 0...1)]) { m, p in m.toSphere(v, factor: Float(p[0])) }
    }

    func randomize() {
        let v = editVertices
        runAdjustable("Randomize", params: [OpParam("Amount", Double(meshSize) * 0.02, 0...Double(meshSize) * 0.3), OpParam("Seed", 1, 1...100, step: 1)]) { m, p in
            m.randomize(v, amount: Float(p[0]), seed: UInt64(p[1]))
        }
    }

    func mirror(axis: Int) {
        clearEditSelection()
        editOp("Mirrored on \(["X", "Y", "Z"][axis])") { $0.mirror(axis: axis) }
    }

    func duplicateEditSelection() {
        let f = editFaces
        guard !f.isEmpty else { showToast("Select faces to duplicate"); return }
        if selectMode != .face { selectMode = .face }
        editOp("Duplicated — drag the arrows to move") { [unowned self] m in self.selFaces = m.duplicateFaces(f) }
        refreshOverlay()
    }

    /// Moves the selected faces into their own object.
    func separateSelection() {
        guard let o = primary, var m = o.mesh else { return }
        let f = editFaces
        guard !f.isEmpty, f.count < m.faceCount else { showToast(f.isEmpty ? "Select faces to separate" : "Select only part of the mesh"); return }
        pushUndo()
        let part = m.extract(f)
        m.deleteFaces(f)
        o.mesh = m
        clearEditSelection()
        rebuild(o)
        let n = StudioObject(name: uniqueName(o.name + " Part"), mesh: part, material: o.material)
        n.textureImage = o.textureImage
        n.node.simdTransform = o.node.simdTransform
        add(n, select: false)
        refreshOverlay(); buildGizmo(); touch()
        showToast("Separated into “\(n.name)”")
    }

    func projectUVs(_ p: UVProjection) {
        let f = mode == .edit ? editFaces : []
        editOp("\(p.rawValue) UV projection") { $0.projectUVs(p, faces: f) }
    }

    // MARK: - Object-mode tools

    func shadeSmooth(_ on: Bool) {
        let targets = selectedObjects.filter { $0.mesh != nil }
        guard !targets.isEmpty else { return }
        pushUndo()
        for o in targets { o.mesh?.smooth = on; rebuild(o) }
        touch(); showToast(on ? "Shade smooth" : "Shade flat")
    }

    enum OriginMode { case geometry, base, geometryToOrigin }

    func setOrigin(_ how: OriginMode) {
        let targets = selectedObjects.filter { $0.mesh != nil }
        guard !targets.isEmpty else { return }
        pushUndo()
        for o in targets {
            guard var m = o.mesh else { continue }
            let c = m.recentre(base: how == .base)
            if how != .geometryToOrigin {
                let t = o.node.simdTransform
                let wc = t * SIMD4(c, 0)
                o.node.simdPosition += SIMD3(wc.x, wc.y, wc.z)
            }
            o.mesh = m
            rebuild(o)
        }
        touch(); buildGizmo()
        showToast(how == .geometryToOrigin ? "Geometry moved to origin" : "Origin set")
    }

    func dropToFloor() {
        let targets = selectedObjects.filter { $0.mesh != nil }
        guard !targets.isEmpty else { return }
        pushUndo()
        for o in targets {
            let (a, b) = o.node.boundingBox
            var minY = Float.greatestFiniteMagnitude
            for i in 0..<8 {
                let c = SIMD3<Float>(i & 1 == 0 ? Float(a.x) : Float(b.x), i & 2 == 0 ? Float(a.y) : Float(b.y), i & 4 == 0 ? Float(a.z) : Float(b.z))
                minY = min(minY, o.node.simdConvertPosition(c, to: nil).y)
            }
            if minY.isFinite { o.node.simdPosition.y -= minY }
        }
        touch(); buildGizmo(); showToast("Dropped to the floor")
    }

    func resetTransform(rotation: Bool, scale: Bool, location: Bool) {
        guard !selectedObjects.isEmpty else { return }
        pushUndo()
        for o in selectedObjects {
            if rotation { o.node.simdOrientation = simd_quatf(angle: 0, axis: [0, 1, 0]) }
            if scale { o.node.simdScale = SIMD3(repeating: 1) }
            if location { o.node.simdPosition = .zero }
        }
        touch(); buildGizmo()
    }

    func separateLooseParts() {
        guard let o = primary, let m = o.mesh else { return }
        let parts = m.looseParts()
        guard parts.count > 1 else { showToast("It's already one piece"); return }
        pushUndo()
        o.mesh = parts[0]; rebuild(o)
        for (i, p) in parts.dropFirst().enumerated() {
            let n = StudioObject(name: uniqueName("\(o.name) \(i + 2)"), mesh: p, material: o.material)
            n.textureImage = o.textureImage; n.modifiers = o.modifiers
            n.node.simdTransform = o.node.simdTransform
            add(n, select: false)
        }
        touch(); showToast("Split into \(parts.count) objects")
    }

    // MARK: - Booleans and remesh (voxel based, run off the main thread)

    private func runBusy(_ label: String, work: @escaping () -> EditMesh?, done: @escaping (EditMesh?) -> Void) {
        busy = label
        Task.detached(priority: .userInitiated) { [weak self] in
            let result = work()
            await MainActor.run {
                self?.busy = nil
                done(result)
            }
        }
    }

    /// `target` keeps its place; `cutter` is hidden afterwards (like Blender).
    func boolean(_ op: BooleanOp, target: StudioObject, cutter: StudioObject) {
        guard var a = target.mesh, var b = cutter.mesh else { return }
        a = a.evaluated(target.modifiers); b = b.evaluated(cutter.modifiers)
        b.apply(target.node.simdWorldTransform.inverse * cutter.node.simdWorldTransform)
        let res = Int(voxelResolution)
        let aa = a, bb = b
        runBusy("\(op.rawValue)…", work: { Voxel.boolean(aa, bb, op, resolution: res) }) { [weak self] out in
            guard let self else { return }
            guard let out else { self.showToast("That didn't work — both shapes need to be closed solids"); return }
            self.pushUndo()
            target.mesh = out; target.modifiers = []
            self.rebuild(target)
            self.setHidden(cutter, true)
            self.selection = [target.id]
            self.showToast("\(op.rawValue) done · cutter hidden (Outliner)")
        }
    }

    func remeshPrimary() {
        guard let o = primary, let m = o.mesh else { return }
        let src = m.evaluated(o.modifiers)
        let res = Int(remeshResolution)
        runBusy("Remeshing…", work: { Voxel.remesh(src, resolution: res) }) { [weak self] out in
            guard let self else { return }
            guard let out else { self.showToast("Remesh needs a closed shape"); return }
            self.pushUndo()
            var mm = out; mm.smooth = true
            if let cols = src.colors, cols.count == src.vertexCount {
                // carry vertex paint across by nearest original vertex
                mm.colors = mm.positions.map { p in
                    var best = 0; var bd = Float.greatestFiniteMagnitude
                    for (i, q) in src.positions.enumerated() { let d = simd_length_squared(p - q); if d < bd { bd = d; best = i } }
                    return cols[best]
                }
            }
            o.mesh = mm; o.modifiers = []
            self.clearEditSelection()
            self.rebuild(o); self.touch()
            self.showToast("Remeshed · \(Fmt.count(mm.faceCount)) faces")
        }
    }

    // MARK: - Modifiers

    func addModifier(_ k: ModifierKind) {
        guard let o = primary, o.mesh != nil else { showToast("Select a shape first"); return }
        pushUndo()
        o.modifiers.append(k.make())
        rebuild(o); touch()
        showToast("\(k.title) added")
    }

    func updateModifier(_ o: StudioObject, _ id: UUID, _ change: (inout ModifierRecord) -> Void) {
        guard let i = o.modifiers.firstIndex(where: { $0.id == id }) else { return }
        change(&o.modifiers[i])
        rebuild(o); touch()
    }

    func removeModifier(_ o: StudioObject, _ id: UUID) {
        pushUndo()
        o.modifiers.removeAll { $0.id == id }
        rebuild(o); touch()
    }

    func moveModifier(_ o: StudioObject, _ id: UUID, up: Bool) {
        guard let i = o.modifiers.firstIndex(where: { $0.id == id }) else { return }
        let j = up ? i - 1 : i + 1
        guard j >= 0, j < o.modifiers.count else { return }
        pushUndo()
        o.modifiers.swapAt(i, j)
        rebuild(o); touch()
    }

    /// Bakes this modifier (and everything above it) into the mesh.
    func applyModifier(_ o: StudioObject, _ id: UUID) {
        guard let i = o.modifiers.firstIndex(where: { $0.id == id }), let m = o.mesh else { return }
        pushUndo()
        o.mesh = m.evaluated(Array(o.modifiers[0...i]))
        o.modifiers.removeFirst(i + 1)
        rebuild(o); touch()
        showToast("Applied")
    }

    func applyAllModifiers() {
        guard let o = primary, let m = o.mesh, !o.modifiers.isEmpty else { return }
        pushUndo()
        o.mesh = m.evaluated(o.modifiers)
        o.modifiers = []
        rebuild(o); touch()
        showToast("Modifiers applied")
    }

    // MARK: - Proportional editing

    func computeDragWeights() -> [(Int, Float)] {
        guard let m = primary?.mesh else { return [] }
        let sel = editVertices
        guard proportional else { return sel.map { ($0, 1) } }
        let r = Float(proportionalRadius) * max(simd_length(m.bounds.max - m.bounds.min), 0.01) * 0.5
        var out: [(Int, Float)] = sel.map { ($0, 1) }
        let selPts = sel.map { m.positions[$0] }
        for i in 0..<m.vertexCount where !sel.contains(i) {
            var d = Float.greatestFiniteMagnitude
            for q in selPts { d = min(d, simd_length(m.positions[i] - q)) }
            if d < r { let t = d / r; out.append((i, 1 - t * t * (3 - 2 * t))) }
        }
        return out
    }

    // MARK: - Vertex paint

    private var paintRGBA: SIMD4<Float> {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(paintColor).getRed(&r, green: &g, blue: &b, alpha: &a)
        return SIMD4(Float(r), Float(g), Float(b), 1)
    }

    func paintBegan(at p: CGPoint) {
        guard let o = primary, let m = o.mesh else { return }
        pushUndo()
        sculptNeighbors = m.neighbors()
        lastDab = CGPoint(x: -999, y: -999)
        paintStrokeActive = true
        paintChanged(at: p)
    }

    func paintChanged(at p: CGPoint) {
        guard let o = primary, var m = o.mesh else { return }
        if hypot(p.x - lastDab.x, p.y - lastDab.y) < 3 { return }
        lastDab = p
        guard let hit = sculptHit(at: p) else { brushRing.isHidden = true; return }
        if m.colors?.count != m.vertexCount { m.colors = [SIMD4<Float>](repeating: SIMD4(1, 1, 1, 1), count: m.vertexCount) }
        let r = brushWorldRadius, s = Float(brushStrength)
        let target = paintRGBA
        func dab(_ c: SIMD3<Float>) {
            let near = m.verticesNear(c, radius: r)
            if paintBlur {
                let old = m.colors!
                for (i, w) in near where i < sculptNeighbors.count && !sculptNeighbors[i].isEmpty {
                    var avg = SIMD4<Float>(repeating: 0); for n in sculptNeighbors[i] { avg += old[n] }; avg /= Float(sculptNeighbors[i].count)
                    m.colors![i] = old[i] + (avg - old[i]) * min(1, w * s)
                }
            } else {
                for (i, w) in near { m.colors![i] = m.colors![i] + (target - m.colors![i]) * min(1, w * s) }
            }
        }
        let local = hit.0
        dab(local)
        if symmetryX, abs(local.x) > r * 0.05 { dab(SIMD3(-local.x, local.y, local.z)) }
        o.mesh = m
        rebuild(o)
        showBrush(at: hit.2, normal: o.node.simdConvertVector(hit.1, to: nil), radius: r * simd_length(o.node.simdWorldTransform.columns.0))
    }

    func paintEnded() {
        paintStrokeActive = false
        brushRing.isHidden = true
        touch()
    }

    func fillPaint() {
        guard let o = primary, o.mesh != nil else { return }
        let c = paintRGBA
        editOp("Filled") { m in m.colors = [SIMD4<Float>](repeating: c, count: m.vertexCount) }
    }

    func clearPaint() {
        guard let o = primary, o.mesh != nil else { return }
        editOp("Paint cleared") { m in m.colors = [SIMD4<Float>](repeating: SIMD4(1, 1, 1, 1), count: m.vertexCount) }
    }

    /// Paints a vertical gradient from the paint colour (top) to white (bottom).
    func gradientPaint() {
        guard let o = primary, o.mesh != nil else { return }
        let c = paintRGBA
        editOp("Gradient") { m in
            let b = m.bounds; let h = max(b.max.y - b.min.y, 1e-5)
            m.colors = m.positions.map { p in let t = (p.y - b.min.y) / h; return SIMD4<Float>(1, 1, 1, 1) + (c - SIMD4<Float>(1, 1, 1, 1)) * t }
        }
    }

    // MARK: - Render

    /// An offscreen, higher-quality render of the current view (no grid, gizmos or overlays).
    func render(width: Int, height: Int, transparent: Bool) -> UIImage? {
        guard let device = view?.device ?? MTLCreateSystemDefaultDevice() else { return nil }
        let r = SCNRenderer(device: device, options: nil)
        r.scene = scene
        let cam = SCNNode()
        let c = (cameraNode.camera?.copy() as? SCNCamera) ?? SCNCamera()
        c.wantsHDR = true
        if world.ambientOcclusion { c.screenSpaceAmbientOcclusionIntensity = 1.4; c.screenSpaceAmbientOcclusionRadius = 0.25; c.screenSpaceAmbientOcclusionNormalThreshold = 0.3 }
        c.bloomIntensity = 0.25; c.bloomThreshold = 1.0
        cam.camera = c
        cam.simdTransform = cameraNode.simdWorldTransform
        scene.rootNode.addChildNode(cam)
        r.pointOfView = cam
        let helpers: [SCNNode] = [gizmo, overlay, jointsRoot, brushRing]
        let wasHidden = helpers.map(\.isHidden)
        helpers.forEach { $0.isHidden = true }
        let gridGeo = grid.geometry; grid.geometry = nil
        let lines = grid.childNodes.filter { !($0.geometry is SCNFloor) }
        let linesHidden = lines.map(\.isHidden)
        lines.forEach { $0.isHidden = true }
        var markers: [SCNNode] = []
        for o in objects where o.isLight { for n in o.node.childNodes where n.name == "light-gizmo" && !n.isHidden { n.isHidden = true; markers.append(n) } }
        let bg = scene.background.contents
        if transparent { scene.background.contents = UIColor.clear }
        else if bg == nil { scene.background.contents = UIColor(white: 0.16, alpha: 1) }
        let img = r.snapshot(atTime: 0, with: CGSize(width: width, height: height), antialiasingMode: .multisampling4X)
        scene.background.contents = bg
        markers.forEach { $0.isHidden = false }
        for (n, h) in zip(lines, linesHidden) { n.isHidden = h }
        grid.geometry = gridGeo
        for (n, h) in zip(helpers, wasHidden) { n.isHidden = h }
        cam.removeFromParentNode()
        return img
    }

    // MARK: - Procedural textures

    static func proceduralImage(_ kind: ProceduralTexture, size n: Int = 512) -> UIImage {
        var px = [UInt8](repeating: 255, count: n * n * 4)
        func put(_ x: Int, _ y: Int, _ c: SIMD3<Float>) {
            let i = (y * n + x) * 4
            px[i] = UInt8(max(0, min(255, c.x * 255))); px[i + 1] = UInt8(max(0, min(255, c.y * 255))); px[i + 2] = UInt8(max(0, min(255, c.z * 255))); px[i + 3] = 255
        }
        func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ t: Float) -> SIMD3<Float> { a + (b - a) * max(0, min(1, t)) }
        for y in 0..<n {
            for x in 0..<n {
                let u = Float(x) / Float(n), v = Float(y) / Float(n)
                var c = SIMD3<Float>(repeating: 1)
                switch kind {
                case .checker:
                    let k = (Int(u * 8) + Int(v * 8)) % 2
                    c = k == 0 ? SIMD3(0.92, 0.92, 0.92) : SIMD3(0.25, 0.25, 0.27)
                case .grid:
                    let k = (Int(u * 8) + Int(v * 8)) % 2
                    let hue = SIMD3<Float>(0.35 + 0.5 * u, 0.4 + 0.4 * v, 0.9 - 0.5 * u)
                    c = k == 0 ? hue : hue * 0.75
                    let fu = (u * 8).truncatingRemainder(dividingBy: 1), fv = (v * 8).truncatingRemainder(dividingBy: 1)
                    if fu < 0.03 || fv < 0.03 { c = SIMD3(1, 1, 1) }
                case .wood:
                    let p = SIMD3<Float>(u * 4, v * 0.6, 0)
                    let ring = sinf((u * 22 + Noise.fbm(p * 3) * 6) * .pi) * 0.5 + 0.5
                    c = mix(SIMD3(0.55, 0.34, 0.17), SIMD3(0.36, 0.2, 0.09), ring * 0.8 + Noise.fbm(SIMD3(u * 40, v * 2, 3)) * 0.3)
                case .marble:
                    let t = sinf((u * 6 + v * 3 + Noise.fbm(SIMD3(u * 5, v * 5, 1), octaves: 5) * 5) * .pi)
                    let vein = powf(1 - abs(t), 6)
                    c = mix(SIMD3(0.93, 0.92, 0.9), SIMD3(0.35, 0.36, 0.4), vein)
                case .brick:
                    let rows: Float = 8, cols: Float = 4
                    let row = floorf(v * rows)
                    let off: Float = Int(row) % 2 == 0 ? 0 : 0.5
                    let bu = (u * cols + off).truncatingRemainder(dividingBy: 1), bv = (v * rows).truncatingRemainder(dividingBy: 1)
                    let mortar = bu < 0.04 || bv < 0.08
                    let tone = Noise.value(SIMD3(floorf(u * cols + off) * 3.1, row * 1.7, 0)) * 0.25
                    c = mortar ? SIMD3(0.78, 0.76, 0.72) : SIMD3(0.62 + tone, 0.27 + tone * 0.5, 0.2) * (0.85 + Noise.fbm(SIMD3(u * 30, v * 30, 0)) * 0.3)
                case .noise:
                    let k = Noise.fbm(SIMD3(u * 8, v * 8, 0), octaves: 5)
                    c = SIMD3(repeating: 0.2 + k * 0.8)
                case .carbon:
                    let cu = Int(u * 32), cv = Int(v * 32)
                    let weave = ((cu + cv / 2) % 2 == 0) != ((cv + cu / 2) % 2 == 0)
                    let fu = (u * 32).truncatingRemainder(dividingBy: 1)
                    let sheen = 0.5 + 0.5 * sinf(fu * .pi)
                    c = weave ? SIMD3(repeating: 0.1 + 0.12 * sheen) : SIMD3(repeating: 0.05 + 0.07 * sheen)
                case .tiles:
                    let tu = (u * 6).truncatingRemainder(dividingBy: 1), tv = (v * 6).truncatingRemainder(dividingBy: 1)
                    let grout = tu < 0.05 || tv < 0.05
                    c = grout ? SIMD3(0.55, 0.55, 0.55) : SIMD3(0.9, 0.93, 0.95) * (0.92 + Noise.value(SIMD3(floorf(u * 6), floorf(v * 6), 2)) * 0.08)
                }
                put(x, y, c)
            }
        }
        let data = Data(px)
        guard let provider = CGDataProvider(data: data as CFData),
              let cg = CGImage(width: n, height: n, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: n * 4, space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { return UIImage() }
        return UIImage(cgImage: cg)
    }
}
