import SwiftUI
import SceneKit
import ModelIO
import SceneKit.ModelIO

extension StudioModel {

    // MARK: projects

    static var projectsDir: URL {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Projects", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    var projectDir: URL { Self.projectsDir.appendingPathComponent(projectID, isDirectory: true) }

    var hasSavableContent: Bool { objects.contains { !$0.isImported } }

    /// Saves editable shapes (imported models stay in the viewer) plus a thumbnail.
    func saveProject() {
        guard hasSavableContent else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: projectDir.appendingPathComponent("textures"), withIntermediateDirectories: true)
        var records: [ObjectRecord] = []
        for o in objects where !o.isImported {
            var m = o.material
            if let img = o.textureImage, let png = img.pngData() {
                let name = "\(o.id.uuidString).png"
                try? png.write(to: projectDir.appendingPathComponent("textures").appendingPathComponent(name))
                m.texture = name
            } else { m.texture = nil }
            records.append(ObjectRecord(id: o.id, name: o.name, mesh: o.mesh, material: m, transform: TransformRecord(o.node), hidden: o.hidden, modifiers: o.modifiers, light: o.light))
        }
        let file = StudioProjectFile(name: projectName, objects: records, world: world)
        if let data = try? JSONEncoder().encode(file) { try? data.write(to: projectDir.appendingPathComponent("project.json"), options: .atomic) }
        if let img = cleanSnapshot(), let jpg = ViewerModel.squareThumb(img)?.jpegData(compressionQuality: 0.8) {
            try? jpg.write(to: projectDir.appendingPathComponent("thumb.jpg"))
        }
        dirty = false
    }

    static func listProjects() -> [StudioProjectSummary] {
        let fm = FileManager.default
        let dirs = (try? fm.contentsOfDirectory(at: projectsDir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        var out: [StudioProjectSummary] = []
        for d in dirs {
            let json = d.appendingPathComponent("project.json")
            guard let data = try? Data(contentsOf: json), let file = try? JSONDecoder().decode(StudioProjectFile.self, from: data) else { continue }
            let date = (try? json.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            out.append(StudioProjectSummary(id: d.lastPathComponent, name: file.name, date: date,
                                            thumbnail: UIImage(contentsOfFile: d.appendingPathComponent("thumb.jpg").path), objectCount: file.objects.count))
        }
        return out.sorted { $0.date > $1.date }
    }

    static func deleteProject(_ id: String) { try? FileManager.default.removeItem(at: projectsDir.appendingPathComponent(id)) }

    static func open(projectID id: String) -> StudioModel? {
        let dir = projectsDir.appendingPathComponent(id)
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("project.json")),
              let file = try? JSONDecoder().decode(StudioProjectFile.self, from: data) else { return nil }
        let m = StudioModel(projectID: id)
        m.projectName = file.name
        if let w = file.world { m.world = w }
        for r in file.objects {
            let o = StudioObject(id: r.id, name: r.name, mesh: r.mesh, material: r.material)
            o.modifiers = r.modifiers ?? []
            o.light = r.light
            if let t = r.material.texture { o.textureImage = UIImage(contentsOfFile: dir.appendingPathComponent("textures").appendingPathComponent(t).path) }
            r.transform.apply(to: o.node)
            o.hidden = r.hidden; o.node.isHidden = r.hidden
            if o.light != nil { m.configureLight(o) }
            m.add(o, select: false)
        }
        m.dirty = false
        return m
    }

    // MARK: bringing a model in from the viewer

    func importLent(nodes: [SCNNode], name: String) {
        let wrapper = SCNNode()
        let o = StudioObject(name: name, mesh: nil, node: wrapper)
        for n in nodes { wrapper.addChildNode(n) }
        wrapper.enumerateHierarchy { n, _ in n.categoryBitMask |= Self.objectMask }
        add(o, select: true)
        projectName = name
        focusSelection()
    }

    /// Hands every visible object to a new scene for the viewer (Studio's helpers are left behind).
    func makeViewerScene() -> SCNScene? {
        let visible = objects.filter { !$0.hidden }
        guard !visible.isEmpty else { return nil }
        overlay.removeFromParentNode()
        let scene = SCNScene()
        for o in visible {
            if o.isImported {
                // Keep the imported model's own hierarchy (bones, animations); bake the wrapper's move into its children.
                for c in o.node.childNodes {
                    let t = c.simdWorldTransform
                    c.removeFromParentNode()
                    scene.rootNode.addChildNode(c)
                    c.simdWorldTransform = t
                }
                o.node.removeFromParentNode()
            } else {
                o.node.removeFromParentNode()
                o.node.childNodes.filter { $0.name == "light-gizmo" }.forEach { $0.removeFromParentNode() }
                o.node.name = o.name
                o.node.opacity = 1
                scene.rootNode.addChildNode(o.node)
            }
        }
        return scene
    }

    // MARK: export

    /// Temporarily removes Studio's helpers and hidden objects so exporters only see the model.
    private func withExportScene<T>(_ body: (SCNScene) -> T) -> T {
        let helpers: [SCNNode] = [grid, gizmo, jointsRoot, brushRing, cameraNode, sunNode]
        let parents = helpers.map { $0.parent }
        helpers.forEach { $0.removeFromParentNode() }
        let overlayParent = overlay.parent; overlay.removeFromParentNode()
        let hidden = objects.filter { $0.hidden }
        hidden.forEach { $0.node.removeFromParentNode() }
        var markers: [(SCNNode, SCNNode)] = []
        for o in objects where o.isLight { for c in o.node.childNodes where c.name == "light-gizmo" { markers.append((c, o.node)); c.removeFromParentNode() } }
        defer { for (c, p) in markers { p.addChildNode(c) } }
        let bg = scene.background.contents; scene.background.contents = nil
        let result = body(scene)
        scene.background.contents = bg
        hidden.forEach { contentRoot.addChildNode($0.node) }
        for (n, p) in zip(helpers, parents) { (p ?? scene.rootNode).addChildNode(n) }
        overlayParent?.addChildNode(overlay)
        return result
    }

    func export(_ format: ExportFormat) -> (URL?, String?) {
        let safe = projectName.replacingOccurrences(of: "/", with: "-").trimmingCharacters(in: .whitespaces)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Export-\(UUID().uuidString.prefix(6))", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(safe.isEmpty ? "Model" : safe).\(format.ext)")
        guard objects.contains(where: { !$0.hidden }) else { return (nil, "There's nothing visible to export.") }
        switch format {
        case .usdz:
            let ok = withExportScene { $0.write(to: url, options: nil, delegate: nil, progressHandler: nil) }
            return ok ? (url, nil) : (nil, "USDZ export failed.")
        case .glb:
            guard let data = GLBWriter.write(roots: objects.filter { !$0.hidden }.map(\.node), relativeTo: contentRoot) else { return (nil, "Nothing could be written to GLB.") }
            do { try data.write(to: url); return (url, nil) } catch { return (nil, error.localizedDescription) }
        case .obj, .stl, .ply, .usda:
            guard MDLAsset.canExportFileExtension(format.ext) else { return (nil, "\(format.rawValue) export isn't available on this device.") }
            return withExportScene { s in
                let asset = MDLAsset(scnScene: s)
                do { try asset.export(to: url); return (url, nil) } catch { return (nil, error.localizedDescription) }
            }
        }
    }

    /// A clean render of the scene (no grid, gizmo or overlays) for thumbnails and sharing.
    func cleanSnapshot() -> UIImage? {
        guard let v = view else { return nil }
        let hidden = [grid, gizmo, overlay, jointsRoot, brushRing].map { ($0, $0.isHidden) }
        hidden.forEach { $0.0.isHidden = true }
        let img = v.snapshot()
        hidden.forEach { $0.0.isHidden = $0.1 }
        return img
    }
}
