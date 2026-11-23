import SwiftUI
import SceneKit
import SceneKit.ModelIO
import ModelIO
import GLTFKit2
import UniformTypeIdentifiers

struct ClipInfo: Identifiable {
    let id = UUID()
    let name: String
    let duration: Double
    let players: [SCNAnimationPlayer]
}

struct BoneInfo: Identifiable, Hashable {
    let node: SCNNode
    let depth: Int
    var id: ObjectIdentifier { ObjectIdentifier(node) }
    var name: String { let n = node.name ?? "Bone"; return n.hasPrefix("joint:") ? String(n.dropFirst(6)) : n }
    static func == (a: BoneInfo, b: BoneInfo) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

struct TextureInfo: Hashable { let slot: String; let width: Int; let height: Int }

struct MaterialInfo: Identifiable {
    let id = UUID()
    let name: String
    let model: String
    let textures: [TextureInfo]
    let thumbnail: UIImage?
    let color: UIColor
}

struct ModelStats {
    var name = ""
    var format = ""
    var fileBytes: Int64 = 0
    var triangles = 0
    var vertices = 0
    var meshes = 0
    var bones = 0
    var materials = 0
    var textures = 0
    var textureBytes: Double = 0
    var morphs = 0
    var size = SIMD3<Float>(repeating: 0)
}

enum Shading: String, CaseIterable, Identifiable {
    case lit = "Lit", clay = "Clay", unlit = "Unlit", xray = "X-Ray"
    var id: String { rawValue }
}

struct EnvPreset: Identifiable, Hashable {
    let id: String
    let name: String
    static let all: [EnvPreset] = [
        .init(id: "studio", name: "Studio"),
        .init(id: "venice_sunset_1k", name: "Sunset"),
        .init(id: "royal_esplanade_1k", name: "Esplanade"),
        .init(id: "blouberg_sunrise_2_1k", name: "Beach Sunrise"),
        .init(id: "quarry_01_1k", name: "Quarry"),
        .init(id: "pedestrian_overpass_1k", name: "Overpass"),
        .init(id: "san_giuseppe_bridge_2k", name: "River Bridge"),
        .init(id: "moonless_golf_1k", name: "Night"),
    ]
}

struct RecentItem: Identifiable {
    let id: String
    let name: String
    let format: String
    let date: Date
    let mainURL: URL
    let thumbnail: UIImage?
}

enum ModelFormats {
    static let sceneKitNative: Set<String> = ["usdz", "usd", "usda", "usdc", "dae", "scn", "abc"]
    static let modelIO: Set<String> = ["obj", "stl", "ply"]
    static let gltf: Set<String> = ["glb", "gltf"]
    static var all: Set<String> { sceneKitNative.union(modelIO).union(gltf) }
    static let display: [(String, String)] = [
        (".usdz .usd .usda .usdc", "Universal Scene Description"), (".glb .gltf", "glTF"), (".obj", "Wavefront OBJ"),
        (".stl", "STL"), (".ply", "Stanford PLY"), (".dae", "Collada"), (".abc", "Alembic"), (".scn", "SceneKit"),
    ]
    static func name(for ext: String) -> String {
        switch ext {
        case "glb", "gltf": return "glTF"
        case "usdz": return "USDZ"
        case "usd", "usda", "usdc": return "USD"
        case "obj": return "Wavefront OBJ"
        case "stl": return "STL"
        case "ply": return "Stanford PLY"
        case "dae": return "Collada"
        case "abc": return "Alembic"
        case "scn": return "SceneKit"
        default: return ext.uppercased()
        }
    }
}

@MainActor
final class ViewerModel: ObservableObject {
    // scene
    @Published private(set) var scene = SCNScene()
    @Published private(set) var stats = ModelStats()
    @Published private(set) var clips: [ClipInfo] = []
    @Published private(set) var currentClip: Int? = nil
    @Published private(set) var bones: [BoneInfo] = []
    @Published private(set) var materials: [MaterialInfo] = []
    @Published private(set) var morphs: [(SCNMorpher, Int, String)] = []
    @Published private(set) var recents: [RecentItem] = []
    @Published private(set) var sourceURL: URL? = nil

    // playback
    @Published var isPlaying = true { didSet { applyPlayState() } }
    @Published var speed: Double = 1 { didSet { applySpeed() } }

    // display
    @Published var showSkeleton = true
    @Published var wireframe = false
    @Published var boundingBoxes = false
    @Published var groundShadow = true { didSet { floorNode.isHidden = !groundShadow } }
    @Published var turntable = false { didSet { updateTurntable() } }
    @Published var shading: Shading = .lit { didSet { applyShading() } }
    @Published var env: String = "studio" { didSet { applyEnvironment() } }
    @Published var envBackground = false { didSet { applyEnvironment() } }
    @Published var exposure: Double = 0 { didSet { cameraNode.camera?.exposureOffset = CGFloat(exposure) } }
    @Published var fov: Double = 38 { didSet { cameraNode.camera?.fieldOfView = CGFloat(fov) } }
    @Published var zUp = false { didSet { if zUp != oldValue { applyUpAxis(toZ: zUp) } } }
    @Published var selectedBone: BoneInfo? = nil { didSet { markBone() } }

    // status
    @Published var isLoading = false
    @Published var loadingText = ""
    @Published var toast: String? = nil

    weak var view: SCNView?
    let cameraNode = SCNNode()
    private let floorNode = SCNNode()
    private let sunNode = SCNNode()
    private var topNodes: [SCNNode] = []
    private var originalMaterials: [ObjectIdentifier: [SCNMaterial]] = [:]
    private var boneMarker: SCNNode?
    private var turntableTimer: Timer?
    private var toastTask: Task<Void, Never>?
    private(set) var radius: Float = 1

    init() {
        let cam = SCNCamera()
        cam.fieldOfView = 38; cam.wantsHDR = true; cam.wantsExposureAdaptation = false; cam.zNear = 0.01; cam.zFar = 1000
        cam.bloomIntensity = 0.15; cam.bloomThreshold = 1.2
        cameraNode.camera = cam; cameraNode.name = "RigViewer.Camera"
        let floor = SCNFloor(); floor.reflectivity = 0
        let fm = SCNMaterial(); fm.lightingModel = .shadowOnly; floor.materials = [fm]
        floorNode.geometry = floor; floorNode.name = "RigViewer.Floor"; floorNode.castsShadow = false
        let sun = SCNLight(); sun.type = .directional; sun.intensity = 900; sun.castsShadow = true; sun.shadowMode = .deferred
        sun.shadowColor = UIColor(white: 0, alpha: 0.32); sun.shadowRadius = 6; sun.shadowSampleCount = 12; sun.automaticallyAdjustsShadowProjection = true
        sunNode.light = sun; sunNode.name = "RigViewer.Sun"; sunNode.eulerAngles = SCNVector3(-Float.pi / 3, Float.pi / 5, 0)
        loadRecents()
        let m = Mannequin.make()
        install(scene: m.scene, gltfAnimations: [], extraClips: m.clips, url: nil, format: "Built in", name: "Mannequin", bytes: 0)
    }

    // MARK: - opening files

    /// Copies picked / shared files into the app (so they stay available as recents) and opens the model among them.
    func importFiles(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let fm = FileManager.default
        let id = UUID().uuidString
        let dir = Self.recentsDir.appendingPathComponent(id, isDirectory: true)
        do { try fm.createDirectory(at: dir, withIntermediateDirectories: true) } catch { showToast("Couldn’t prepare storage: \(error.localizedDescription)"); return }
        var copied: [URL] = []
        for u in urls {
            let scoped = u.startAccessingSecurityScopedResource()
            defer { if scoped { u.stopAccessingSecurityScopedResource() } }
            let dest = dir.appendingPathComponent(u.lastPathComponent)
            do { if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }; try fm.copyItem(at: u, to: dest); copied.append(dest) } catch { continue }
        }
        let order = ["glb", "gltf", "usdz", "usd", "usdc", "usda", "dae", "fbx", "obj", "abc", "scn", "stl", "ply"]
        let models = copied.filter { ModelFormats.all.contains($0.pathExtension.lowercased()) }
            .sorted { (order.firstIndex(of: $0.pathExtension.lowercased()) ?? 99) < (order.firstIndex(of: $1.pathExtension.lowercased()) ?? 99) }
        guard let main = models.first else {
            try? fm.removeItem(at: dir)
            let ext = urls.first?.pathExtension.lowercased() ?? ""
            if ext == "fbx" { showToast("FBX isn’t supported by Apple’s 3D frameworks. Convert it to USDZ or glTF (Reality Converter or Blender can).") }
            else { showToast("Rig Viewer opens USDZ, USD, glTF/GLB, OBJ, STL, PLY, Collada, Alembic and SceneKit files.") }
            return
        }
        open(url: main, remember: dir)
    }

    func open(url: URL, displayName: String? = nil, remember dir: URL? = nil) {
        isLoading = true; loadingText = "Opening \(displayName ?? url.lastPathComponent)"
        let ext = url.pathExtension.lowercased()
        let bytes = Self.folderSize(dir ?? url)
        let name = displayName ?? url.lastPathComponent
        if ModelFormats.gltf.contains(ext) {
            GLTFAsset.load(with: url, options: [:]) { _, status, asset, error, _ in
                Task { @MainActor in
                    if status == .complete, let asset {
                        let source = GLTFSCNSceneSource(asset: asset)
                        guard let scn = source.defaultScene else { self.fail("“\(name)” has no scene to show."); return }
                        self.install(scene: scn, gltfAnimations: source.animations, extraClips: [], url: url, format: "glTF", name: name, bytes: bytes)
                        if let dir { self.saveRecent(dir: dir, main: url) }
                    } else if status == .error || error != nil {
                        self.fail("Couldn’t open “\(name)”. \(error?.localizedDescription ?? "")")
                    }
                }
            }
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            var scn: SCNScene? = nil
            if ModelFormats.sceneKitNative.contains(ext) { scn = try? SCNScene(url: url, options: [.checkConsistency: true, .convertToYUp: true]) }
            if scn == nil || scn!.rootNode.childNodes.isEmpty {
                let asset = MDLAsset(url: url)
                asset.loadTextures()
                if asset.count > 0 { scn = SCNScene(mdlAsset: asset) }
            }
            Task { @MainActor in
                guard let scn, !scn.rootNode.childNodes.isEmpty else { self.fail("Couldn’t read any geometry from “\(name)”."); return }
                self.install(scene: scn, gltfAnimations: [], extraClips: [], url: url, format: ModelFormats.name(for: ext), name: name, bytes: bytes)
                if ["stl", "ply"].contains(ext) { self.zUp = true }
                if let dir { self.saveRecent(dir: dir, main: url) }
            }
        }
    }

    func openSample(_ key: String) {
        if key == "mannequin" {
            let m = Mannequin.make()
            install(scene: m.scene, gltfAnimations: [], extraClips: m.clips, url: nil, format: "Built in", name: "Mannequin", bytes: 0)
            return
        }
        let parts = key.split(separator: ".")
        guard parts.count == 2, let url = Bundle.main.url(forResource: String(parts[0]), withExtension: String(parts[1])) else { showToast("Sample missing from the app bundle."); return }
        open(url: url, displayName: key == "RobotExpressive.glb" ? "Expressive Robot" : "Coloured STL")
    }

    private func fail(_ msg: String) { isLoading = false; showToast(msg) }

    // MARK: - stage

    private func install(scene scn: SCNScene, gltfAnimations: [GLTFSCNAnimation], extraClips: [ClipInfo], url: URL?, format: String, name: String, bytes: Int64) {
        turntable = false; selectedBone = nil; zUpSilently(false); shading = .lit
        clips.forEach { $0.players.forEach { $0.stop() } }
        originalMaterials = [:]
        topNodes = scn.rootNode.childNodes
        for n in [cameraNode, floorNode, sunNode] { n.removeFromParentNode(); scn.rootNode.addChildNode(n) }
        topNodes.forEach { n in n.enumerateHierarchy { c, _ in if c.geometry != nil { c.castsShadow = true } } }

        var list = extraClips
        for (i, a) in gltfAnimations.enumerated() {
            let p = a.animationPlayer
            p.stop()
            scn.rootNode.addAnimationPlayer(p, forKey: "clip-\(i)")
            list.append(ClipInfo(name: a.name.isEmpty ? "Clip \(i + 1)" : a.name, duration: p.animation.duration, players: [p]))
        }
        if gltfAnimations.isEmpty && extraClips.isEmpty {
            var players: [SCNAnimationPlayer] = []; var dur = 0.0
            scn.rootNode.enumerateHierarchy { n, _ in
                for k in n.animationKeys { if let p = n.animationPlayer(forKey: k) { players.append(p); dur = max(dur, p.animation.duration) } }
            }
            if !players.isEmpty { list.append(ClipInfo(name: "Animation", duration: dur, players: players)) }
        }
        clips = list
        sourceURL = url
        scene = scn
        view?.scene = scn
        view?.pointOfView = cameraNode
        stats = ModelStats(name: name, format: format, fileBytes: bytes)
        computeStats(); collectBones(); collectMaterials()
        applyEnvironment()
        currentClip = nil
        if !clips.isEmpty { play(0) }
        frame(animated: false)
        isLoading = false
    }

    // MARK: - camera

    private func modelBounds() -> (center: SIMD3<Float>, radius: Float, minY: Float, size: SIMD3<Float>) {
        var mn = SIMD3<Float>(repeating: .greatestFiniteMagnitude), mx = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        var any = false
        for n in topNodes {
            n.enumerateHierarchy { c, _ in
                guard c.geometry != nil else { return }
                let (a, b) = c.boundingBox
                let lo = SIMD3<Float>(Float(a.x), Float(a.y), Float(a.z)), hi = SIMD3<Float>(Float(b.x), Float(b.y), Float(b.z))
                if lo.x > hi.x { return }
                for i in 0..<8 {
                    let p = SIMD3<Float>(i & 1 == 0 ? lo.x : hi.x, i & 2 == 0 ? lo.y : hi.y, i & 4 == 0 ? lo.z : hi.z)
                    let w = c.simdConvertPosition(p, to: nil)
                    mn = simd_min(mn, w); mx = simd_max(mx, w); any = true
                }
            }
        }
        if !any { return (SIMD3(0, 0.5, 0), 1, 0, SIMD3(1, 1, 1)) }
        let size = mx - mn
        return ((mn + mx) / 2, max(simd_length(size) / 2, 0.001), mn.y, size)
    }

    func frame(animated: Bool = true) {
        let b = modelBounds()
        radius = b.radius
        stats.size = b.size
        let cam = cameraNode.camera!
        let bounds = view?.bounds.size ?? CGSize(width: 390, height: 844)
        let aspect = Float(bounds.width / max(1, bounds.height))
        let vHalf = Float(cam.fieldOfView) * .pi / 360
        let half = min(vHalf, atan(tan(vHalf) * aspect))
        let dist = b.radius / sin(half) * 1.15
        let dir = simd_normalize(SIMD3<Float>(0.45, 0.2, 0.87))
        cam.zNear = Double(dist / 300); cam.zFar = Double(dist * 60)
        SCNTransaction.begin()
        SCNTransaction.animationDuration = animated ? 0.6 : 0
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        cameraNode.simdPosition = b.center + dir * dist
        cameraNode.simdLook(at: b.center)
        SCNTransaction.commit()
        view?.defaultCameraController.target = SCNVector3(b.center)
        floorNode.simdPosition = SIMD3(0, b.minY, 0)
        if let light = sunNode.light { light.orthographicScale = CGFloat(b.radius * 1.6) }
    }

    private func updateTurntable() {
        turntableTimer?.invalidate(); turntableTimer = nil
        guard turntable else { return }
        turntableTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.view?.defaultCameraController.rotateBy(x: 0.35, y: 0) }
        }
    }

    // MARK: - playback

    func play(_ index: Int) {
        guard clips.indices.contains(index) else { return }
        clips.forEach { $0.players.forEach { $0.stop() } }
        currentClip = index
        for p in clips[index].players {
            p.animation.repeatCount = .greatestFiniteMagnitude
            p.speed = CGFloat(speed)
            p.play()
            p.paused = !isPlaying
        }
    }
    private func applyPlayState() { if let i = currentClip { clips[i].players.forEach { $0.paused = !isPlaying } } }
    private func applySpeed() { if let i = currentClip { clips[i].players.forEach { $0.speed = CGFloat(speed) } } }

    func setMorph(_ index: Int, value: Double) {
        guard morphs.indices.contains(index) else { return }
        let name = morphs[index].2
        for (m, i, n) in morphs where n == name { m.setWeight(CGFloat(value), forTargetAt: i) }
    }

    // MARK: - display

    func debugOptions() -> SCNDebugOptions {
        var o: SCNDebugOptions = []
        if showSkeleton { o.insert(.showSkeletons) }
        if wireframe { o.insert(.renderAsWireframe) }
        if boundingBoxes { o.insert(.showBoundingBoxes) }
        return o
    }

    private func forEachModelGeometryNode(_ body: (SCNNode) -> Void) {
        for n in topNodes { n.enumerateHierarchy { c, _ in if c.geometry != nil { body(c) } } }
    }

    private func applyShading() {
        forEachModelGeometryNode { n in
            guard let g = n.geometry else { return }
            let key = ObjectIdentifier(g)
            if originalMaterials[key] == nil { originalMaterials[key] = g.materials }
            let originals = originalMaterials[key] ?? []
            switch shading {
            case .lit: g.materials = originals
            case .clay:
                g.materials = originals.map { _ in
                    let m = SCNMaterial(); m.lightingModel = .physicallyBased
                    m.diffuse.contents = UIColor(red: 0.85, green: 0.84, blue: 0.82, alpha: 1); m.roughness.contents = 0.7; m.metalness.contents = 0.0; m.isDoubleSided = true
                    return m
                }
            case .unlit:
                g.materials = originals.map { o in let m = o.copy() as! SCNMaterial; m.lightingModel = .constant; return m }
            case .xray:
                g.materials = originals.map { o in let m = o.copy() as! SCNMaterial; m.transparency = 0.32; m.blendMode = .alpha; m.writesToDepthBuffer = false; m.isDoubleSided = true; return m }
            }
        }
    }

    private func applyEnvironment() {
        if env == "studio" {
            scene.lightingEnvironment.contents = Self.studioEnvironment
            scene.lightingEnvironment.intensity = 1.25
            scene.background.contents = nil
            sunNode.light?.intensity = 900
        } else {
            scene.lightingEnvironment.contents = Bundle.main.url(forResource: env, withExtension: "exr")
            scene.lightingEnvironment.intensity = 1.0
            scene.background.contents = envBackground ? Bundle.main.url(forResource: env + "_bg", withExtension: "jpg") : nil
            sunNode.light?.intensity = 350
        }
    }

    private func applyUpAxis(toZ: Bool) {
        let r = SCNMatrix4MakeRotation((toZ ? -1 : 1) * Float.pi / 2, 1, 0, 0)
        for n in topNodes { n.transform = SCNMatrix4Mult(n.transform, r) }
        frame()
    }
    private func zUpSilently(_ v: Bool) {
        if zUp { let r = SCNMatrix4MakeRotation(Float.pi / 2, 1, 0, 0); for n in topNodes { n.transform = SCNMatrix4Mult(n.transform, r) } }
        _zUpWithoutSideEffects(v)
    }
    private func _zUpWithoutSideEffects(_ v: Bool) { let saved = topNodes; topNodes = []; zUp = v; topNodes = saved }

    private func markBone() {
        boneMarker?.removeFromParentNode(); boneMarker = nil
        guard let b = selectedBone else { return }
        let len = CGFloat(radius * 0.12)
        let marker = SCNNode()
        for (axis, color) in [(SIMD3<Float>(1, 0, 0), UIColor.systemRed), (SIMD3<Float>(0, 1, 0), UIColor.systemGreen), (SIMD3<Float>(0, 0, 1), UIColor.systemBlue)] {
            let c = SCNCylinder(radius: len * 0.06, height: len)
            let m = SCNMaterial(); m.diffuse.contents = color; m.lightingModel = .constant; m.readsFromDepthBuffer = false; c.materials = [m]
            let n = SCNNode(geometry: c); n.renderingOrder = 1000
            n.simdPosition = axis * Float(len / 2)
            if axis.x > 0 { n.eulerAngles.z = -Float.pi / 2 } else if axis.z > 0 { n.eulerAngles.x = Float.pi / 2 }
            marker.addChildNode(n)
        }
        let ws = b.node.simdWorldTransform.columns.0
        let scale = simd_length(SIMD3(ws.x, ws.y, ws.z))
        if scale > 0 { marker.simdScale = SIMD3(repeating: 1 / scale) }
        b.node.addChildNode(marker); boneMarker = marker
    }

    func worldPosition(of bone: BoneInfo) -> SIMD3<Float> { bone.node.simdWorldPosition }

    // MARK: - inspection

    private func computeStats() {
        var tris = 0, verts = 0, meshes = 0, morphCount = 0
        var morphList: [(SCNMorpher, Int, String)] = []
        forEachModelGeometryNode { n in
            guard let g = n.geometry else { return }
            meshes += 1
            verts += g.sources(for: .vertex).first?.vectorCount ?? 0
            for e in g.elements {
                switch e.primitiveType { case .triangles, .triangleStrip, .polygon: tris += e.primitiveCount; default: break }
            }
            if let m = n.morpher {
                for (i, t) in m.targets.enumerated() { morphList.append((m, i, t.name ?? "Shape \(i + 1)")) }
                morphCount += m.targets.count
            }
        }
        stats.triangles = tris; stats.vertices = verts; stats.meshes = meshes
        morphs = morphList; stats.morphs = Set(morphList.map { $0.2 }).count
        _ = morphCount
    }

    private func collectBones() {
        var set = Set<ObjectIdentifier>(); var boneNodes: [SCNNode] = []
        forEachModelGeometryNode { n in
            for b in n.skinner?.bones ?? [] where !set.contains(ObjectIdentifier(b)) { set.insert(ObjectIdentifier(b)); boneNodes.append(b) }
        }
        if boneNodes.isEmpty {   // rigid rigs (e.g. the built-in mannequin) name their joints
            for n in topNodes { n.enumerateHierarchy { c, _ in if c.name?.hasPrefix("joint:") == true { set.insert(ObjectIdentifier(c)); boneNodes.append(c) } } }
        }
        var out: [BoneInfo] = []
        func walk(_ n: SCNNode, _ depth: Int) {
            let isBone = set.contains(ObjectIdentifier(n))
            if isBone { out.append(BoneInfo(node: n, depth: depth)) }
            for c in n.childNodes { walk(c, isBone ? depth + 1 : depth) }
        }
        topNodes.forEach { walk($0, 0) }
        bones = out; stats.bones = out.count
    }

    private func collectMaterials() {
        var seen = Set<ObjectIdentifier>(); var out: [MaterialInfo] = []; var texCount = 0; var texBytes = 0.0
        var seenTex = Set<String>()
        forEachModelGeometryNode { n in
            for m in n.geometry?.materials ?? [] where !seen.contains(ObjectIdentifier(m)) {
                seen.insert(ObjectIdentifier(m))
                var texs: [TextureInfo] = []
                let slots: [(String, SCNMaterialProperty)] = [("Color", m.diffuse), ("Normal", m.normal), ("Rough", m.roughness), ("Metal", m.metalness), ("AO", m.ambientOcclusion), ("Emissive", m.emission)]
                var thumb: UIImage? = nil
                for (slot, prop) in slots {
                    guard let size = Self.imageSize(prop.contents) else { continue }
                    texs.append(TextureInfo(slot: slot, width: size.0, height: size.1))
                    let key = "\(ObjectIdentifier(m))-\(slot)"
                    if !seenTex.contains(key) { seenTex.insert(key); texCount += 1; texBytes += Double(size.0 * size.1) * 4 * 1.333 }
                    if slot == "Color" { thumb = Self.thumbnail(prop.contents) }
                }
                let color = (m.diffuse.contents as? UIColor) ?? .systemGray3
                out.append(MaterialInfo(name: m.name ?? "Material \(out.count + 1)", model: Self.lightingName(m.lightingModel), textures: texs, thumbnail: thumb, color: color))
            }
        }
        materials = out; stats.materials = out.count; stats.textures = texCount; stats.textureBytes = texBytes
    }

    // MARK: - snapshots & AR

    func snapshot() -> UIImage? {
        guard let v = view else { return nil }
        let opts = v.debugOptions; v.debugOptions = []
        boneMarker?.isHidden = true
        let img = v.snapshot()
        v.debugOptions = opts; boneMarker?.isHidden = false
        return img
    }

    /// A USDZ for AR Quick Look: the original file when it already is one, otherwise an export of the model.
    func usdzForAR() -> URL? {
        if let u = sourceURL, u.pathExtension.lowercased() == "usdz" { return u }
        let s = SCNScene()
        for n in topNodes { s.rootNode.addChildNode(n.clone()) }
        let out = FileManager.default.temporaryDirectory.appendingPathComponent((stats.name as NSString).deletingPathExtension + ".usdz")
        try? FileManager.default.removeItem(at: out)
        return s.write(to: out, options: nil, delegate: nil, progressHandler: nil) ? out : nil
    }

    // MARK: - recents

    static var recentsDir: URL {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Recents", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    private func saveRecent(dir: URL, main: URL) {
        let meta: [String: Any] = ["name": stats.name, "format": stats.format, "main": main.lastPathComponent, "date": Date().timeIntervalSince1970]
        if let data = try? JSONSerialization.data(withJSONObject: meta) { try? data.write(to: dir.appendingPathComponent("meta.json")) }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            if let img = self.snapshot(), let jpg = Self.squareThumb(img)?.jpegData(compressionQuality: 0.75) { try? jpg.write(to: dir.appendingPathComponent("thumb.jpg")) }
            self.pruneRecents(); self.loadRecents()
        }
    }

    func loadRecents() {
        let fm = FileManager.default
        let dirs = (try? fm.contentsOfDirectory(at: Self.recentsDir, includingPropertiesForKeys: nil)) ?? []
        var items: [RecentItem] = []
        for d in dirs {
            guard let data = try? Data(contentsOf: d.appendingPathComponent("meta.json")),
                  let meta = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let main = meta["main"] as? String else { continue }
            let thumb = UIImage(contentsOfFile: d.appendingPathComponent("thumb.jpg").path)
            items.append(RecentItem(id: d.lastPathComponent, name: meta["name"] as? String ?? main, format: meta["format"] as? String ?? "",
                                    date: Date(timeIntervalSince1970: meta["date"] as? Double ?? 0), mainURL: d.appendingPathComponent(main), thumbnail: thumb))
        }
        recents = items.sorted { $0.date > $1.date }
    }

    private func pruneRecents() {
        let sorted = recents.sorted { $0.date > $1.date }
        for r in sorted.dropFirst(12) { try? FileManager.default.removeItem(at: Self.recentsDir.appendingPathComponent(r.id)) }
    }

    func openRecent(_ r: RecentItem) { open(url: r.mainURL, displayName: r.name) }
    func deleteRecent(_ r: RecentItem) { try? FileManager.default.removeItem(at: Self.recentsDir.appendingPathComponent(r.id)); loadRecents() }
    func clearRecents() { recents.forEach { try? FileManager.default.removeItem(at: Self.recentsDir.appendingPathComponent($0.id)) }; loadRecents() }

    // MARK: - toast

    func showToast(_ msg: String) {
        toastTask?.cancel()
        withAnimation(.spring(duration: 0.45, bounce: 0.3)) { toast = msg }
        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if !Task.isCancelled { withAnimation(.easeOut(duration: 0.3)) { self.toast = nil } }
        }
    }

    // MARK: - helpers

    static func folderSize(_ url: URL) -> Int64 {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue { return (try? fm.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0 }
        var total: Int64 = 0
        if let e = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let f as URL in e where f.lastPathComponent != "thumb.jpg" && f.lastPathComponent != "meta.json" {
                total += Int64((try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
        }
        return total
    }

    static func imageSize(_ contents: Any?) -> (Int, Int)? {
        switch contents {
        case let i as UIImage: return (Int(i.size.width * i.scale), Int(i.size.height * i.scale))
        case let u as URL: if let i = UIImage(contentsOfFile: u.path) { return (Int(i.size.width * i.scale), Int(i.size.height * i.scale)) }; return nil
        case let s as String: if let i = UIImage(contentsOfFile: s) ?? UIImage(named: s) { return (Int(i.size.width * i.scale), Int(i.size.height * i.scale)) }; return nil
        case let t as MDLTexture: return (Int(t.dimensions.x), Int(t.dimensions.y))
        default:
            if let c = contents, CFGetTypeID(c as CFTypeRef) == CGImage.typeID { let cg = c as! CGImage; return (cg.width, cg.height) }
            return nil
        }
    }

    static func thumbnail(_ contents: Any?) -> UIImage? {
        var img: UIImage? = nil
        switch contents {
        case let i as UIImage: img = i
        case let u as URL: img = UIImage(contentsOfFile: u.path)
        case let s as String: img = UIImage(contentsOfFile: s) ?? UIImage(named: s)
        default:
            if let c = contents, CFGetTypeID(c as CFTypeRef) == CGImage.typeID { img = UIImage(cgImage: c as! CGImage) }
        }
        guard let img else { return nil }
        return UIGraphicsImageRenderer(size: CGSize(width: 88, height: 88)).image { _ in img.draw(in: CGRect(x: 0, y: 0, width: 88, height: 88)) }
    }

    static func squareThumb(_ img: UIImage) -> UIImage? {
        let s = min(img.size.width, img.size.height)
        let r = CGRect(x: (img.size.width - s) / 2, y: (img.size.height - s) / 2 - s * 0.05, width: s, height: s)
        return UIGraphicsImageRenderer(size: CGSize(width: 240, height: 240)).image { _ in img.draw(in: CGRect(x: -r.minX * 240 / s, y: -r.minY * 240 / s, width: img.size.width * 240 / s, height: img.size.height * 240 / s)) }
    }

    static func lightingName(_ m: SCNMaterial.LightingModel) -> String {
        switch m {
        case .physicallyBased: return "Physically based"
        case .blinn: return "Blinn"
        case .phong: return "Phong"
        case .lambert: return "Lambert"
        case .constant: return "Unlit"
        case .shadowOnly: return "Shadow only"
        default: return "Standard"
        }
    }

    /// A soft studio panorama (bright top, warm key, cool fill) used as image-based light.
    static let studioEnvironment: UIImage = {
        let size = CGSize(width: 512, height: 256)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let c = ctx.cgContext
            let colors = [UIColor(white: 1.0, alpha: 1).cgColor, UIColor(white: 0.78, alpha: 1).cgColor, UIColor(white: 0.35, alpha: 1).cgColor] as CFArray
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.5, 1])!
            c.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            for (x, col) in [(0.25, UIColor(red: 1, green: 0.95, blue: 0.88, alpha: 1)), (0.75, UIColor(red: 0.85, green: 0.92, blue: 1, alpha: 1))] {
                c.setFillColor(col.cgColor)
                c.fillEllipse(in: CGRect(x: size.width * CGFloat(x) - 50, y: 40, width: 100, height: 70))
            }
        }
    }()
}
