import SwiftUI
import SceneKit
import SceneKit.ModelIO
import ModelIO
import GLTFKit2
import UniformTypeIdentifiers
import Combine

struct ClipInfo: Identifiable {
    let id = UUID()
    let name: String
    let duration: Double
    let players: [SCNAnimationPlayer]
}

struct BoneInfo: Identifiable, Hashable {
    let node: SCNNode
    let depth: Int
    var label: String? = nil
    var id: ObjectIdentifier { ObjectIdentifier(node) }
    var name: String { if let label { return label }; let n = node.name ?? "Bone"; return n.hasPrefix("joint:") ? String(n.dropFirst(6)) : n }
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
    var material: SCNMaterial? = nil
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
    static let fbx: Set<String> = ["fbx"]
    static var all: Set<String> { sceneKitNative.union(modelIO).union(gltf).union(fbx) }
    static let display: [(String, String)] = [
        (".fbx", "Autodesk FBX"), (".usdz .usd .usda .usdc", "Universal Scene Description"), (".glb .gltf", "glTF"), (".obj", "Wavefront OBJ"),
        (".stl", "STL"), (".ply", "Stanford PLY"), (".dae", "Collada"), (".abc", "Alembic"), (".scn", "SceneKit"),
    ]
    static func name(for ext: String) -> String {
        switch ext {
        case "glb", "gltf": return "glTF"
        case "fbx": return "FBX"
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

    // Scene outliner
    @Published private(set) var parts: [PartInfo] = []
    @Published private(set) var hiddenParts: Set<ObjectIdentifier> = []
    @Published private(set) var hiddenMaterials: Set<ObjectIdentifier> = []
    @Published var groupMode: PartGrouping = .smart
    @Published private(set) var disabledChannels: Set<TextureChannel> = []
    @Published var channelView: ChannelView = .final { didSet { applyShading() } }

    weak var view: SCNView?
    let cameraNode = SCNNode()
    lazy var orbit = OrbitCamera(node: cameraNode)
    private let floorNode = SCNNode()
    private let sunNode = SCNNode()
    private var topNodes: [SCNNode] = []
    private var originalMaterials: [ObjectIdentifier: [SCNMaterial]] = [:]
    private var boneMarker: SCNNode?
    private var toastTask: Task<Void, Never>?
    private(set) var radius: Float = 1
    private var settingsSinks = Set<AnyCancellable>()
    private var channelSnapshot: [ObjectIdentifier: [TextureChannel: Any]] = [:]
    private var transparencySnapshot: [ObjectIdentifier: CGFloat] = [:]
    private static let checker: UIImage = {
        let n = 8, cell: CGFloat = 32
        return UIGraphicsImageRenderer(size: CGSize(width: CGFloat(n) * cell, height: CGFloat(n) * cell)).image { ctx in
            for y in 0..<n { for x in 0..<n {
                let hue = CGFloat((x + y * n) % 12) / 12
                (((x + y) % 2 == 0) ? UIColor(hue: hue, saturation: 0.55, brightness: 0.95, alpha: 1) : UIColor(white: 0.12, alpha: 1)).setFill()
                ctx.fill(CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell, width: cell, height: cell))
            } }
        }
    }()
    private let settings = AppSettings.shared

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
        fov = settings.defaultFOV; cam.fieldOfView = CGFloat(fov)
        env = settings.defaultEnvironment
        showSkeleton = settings.defaultSkeleton
        groundShadow = settings.defaultGroundShadow
        speed = settings.defaultSpeed
        isPlaying = settings.autoplay
        observeSettings()
        applyRenderSettings()
        loadRecents()
        let m = Mannequin.make()
        install(scene: m.scene, gltfAnimations: [], extraClips: m.clips, url: nil, format: "Built in", name: "Mannequin", bytes: 0)
    }

    // MARK: - opening files

    /// Copies picked / shared files into the app (so they stay available as recents), unpacks ZIPs,
    /// checks the files are complete, then opens the best model among them.
    func importFiles(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        isLoading = true; loadingText = urls.count == 1 ? "Importing \(urls[0].lastPathComponent)" : "Importing \(urls.count) files"
        let dir = Self.recentsDir.appendingPathComponent(UUID().uuidString, isDirectory: true)
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Self.prepareImport(urls, into: dir)
            Task { @MainActor in
                switch result {
                case .failure(let message):
                    try? FileManager.default.removeItem(at: dir)
                    self.fail(message)
                case .success(let main):
                    self.open(url: main, remember: dir)
                }
            }
        }
    }

    enum ImportResult { case success(URL), failure(String) }

    nonisolated static func prepareImport(_ urls: [URL], into dir: URL) -> ImportResult {
        let fm = FileManager.default
        do { try fm.createDirectory(at: dir, withIntermediateDirectories: true) } catch { return .failure("Couldn’t prepare storage: \(error.localizedDescription)") }
        var problems: [String] = []
        for u in urls {
            let scoped = u.startAccessingSecurityScopedResource()
            defer { if scoped { u.stopAccessingSecurityScopedResource() } }
            let dest = dir.appendingPathComponent(u.lastPathComponent)
            // A coordinated read makes iCloud Drive / Google Drive / Dropbox finish downloading the real file first.
            var coordError: NSError?
            var copyError: Error?
            NSFileCoordinator().coordinate(readingItemAt: u, options: [.withoutChanges], error: &coordError) { readable in
                do { if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }; try fm.copyItem(at: readable, to: dest) } catch { copyError = error }
            }
            if let e = coordError ?? (copyError as NSError?) { problems.append("\(u.lastPathComponent): \(e.localizedDescription)"); continue }
            if dest.pathExtension.lowercased() == "zip" {
                do { _ = try ZipReader.extract(dest, to: dir.appendingPathComponent(dest.deletingPathExtension().lastPathComponent, isDirectory: true)); try? fm.removeItem(at: dest) }
                catch { problems.append("\(u.lastPathComponent): \(error.localizedDescription)") }
            }
        }

        var models: [URL] = []
        if let e = fm.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
            for case let f as URL in e where ModelFormats.all.contains(f.pathExtension.lowercased()) && !f.path.contains("__MACOSX") { models.append(f) }
        }
        let order = ["glb", "gltf", "fbx", "usdz", "usd", "usdc", "usda", "dae", "obj", "abc", "scn", "stl", "ply"]
        models.sort {
            let a = order.firstIndex(of: $0.pathExtension.lowercased()) ?? 99, b = order.firstIndex(of: $1.pathExtension.lowercased()) ?? 99
            return a != b ? a < b : $0.pathComponents.count < $1.pathComponents.count
        }
        guard let main = models.first else {
            if let p = problems.first { return .failure("Couldn’t import \(p)") }
            return .failure("No 3D model found. Rig Viewer opens FBX, glTF/GLB, USDZ, OBJ, STL, PLY, Collada, Alembic and SceneKit files, and ZIPs containing them.")
        }
        if let problem = checkComplete(main) { return .failure(problem) }
        return .success(main)
    }

    /// Catches empty or partially-downloaded files before a loader reports something cryptic.
    nonisolated static func checkComplete(_ url: URL) -> String? {
        let name = url.lastPathComponent
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if size == 0 { return "“\(name)” is empty (0 bytes). It probably didn’t finish downloading — open it once in the Files app to download it, then try again." }
        if url.pathExtension.lowercased() == "glb", let h = try? FileHandle(forReadingFrom: url) {
            defer { try? h.close() }
            let head = h.readData(ofLength: 12)
            if head.count < 12 || head.prefix(4) != Data("glTF".utf8) {
                return "“\(name)” isn’t a real GLB file (it may be a web page or a renamed file). Download it again from the original site."
            }
            let declared = Int(head[8]) | Int(head[9]) << 8 | Int(head[10]) << 16 | Int(head[11]) << 24
            if declared > size {
                return "“\(name)” is incomplete: it has \(Fmt.bytes(Double(size))) of \(Fmt.bytes(Double(declared))). It didn’t finish downloading — download it again, or open it once in Files first."
            }
        }
        return nil
    }

    /// Turns loader errors into something a person can act on.
    nonisolated static func friendly(_ error: Error?, name: String) -> String {
        let text = error?.localizedDescription ?? ""
        if text.contains("too short") { return "“\(name)” is incomplete or damaged — part of the file is missing. Download it again and re-open it." }
        if text.lowercased().contains("not found") || text.lowercased().contains("no such file") {
            return "“\(name)” refers to files that weren’t included (like a .bin or textures). Select them together, or open the ZIP it came in."
        }
        if text.contains("unknown format") || text.contains("invalid") { return "“\(name)” isn’t a valid glTF file. Try re-exporting it." }
        return "Couldn’t open “\(name)”. \(text)"
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
                        self.fail(Self.friendly(error, name: name))
                    }
                }
            }
            return
        }
        if ModelFormats.fbx.contains(ext) {
            DispatchQueue.global(qos: .userInitiated).async {
                var err: NSString? = nil
                let result = FBXImporter.load(url, error: &err)
                let message = err as String?
                Task { @MainActor in
                    guard let result, !result.scene.rootNode.childNodes.isEmpty else { self.fail("Couldn’t open “\(name)”. \(message ?? "")"); return }
                    let clips = result.clips.map { ClipInfo(name: $0.name, duration: $0.duration, players: $0.players) }
                    self.install(scene: result.scene, gltfAnimations: [], extraClips: clips, url: url, format: "FBX", name: name, bytes: bytes)
                    if let dir { self.saveRecent(dir: dir, main: url) }
                    if !result.missingTextures.isEmpty {
                        let list = result.missingTextures.prefix(3).joined(separator: ", ")
                        self.showToast("Some textures weren’t found (\(list)\(result.missingTextures.count > 3 ? "…" : "")). Pick them together with the FBX to include them.")
                    }
                }
            }
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            var scn: SCNScene? = nil
            if ModelFormats.sceneKitNative.contains(ext) { scn = try? SCNScene(url: url, options: [.checkConsistency: true, .convertToYUp: true]) }
            if ext == "stl" { scn = STLLoader.load(url) }
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
        hiddenParts = []; hiddenMaterials = []; disabledChannels = []; channelSnapshot = [:]
        if channelView != .final { channelView = .final }
        forEachModelGeometryNode { n in if let g = n.geometry { self.originalMaterials[ObjectIdentifier(g)] = g.materials } }
        computeStats(); collectBones(); collectMaterials(); collectParts()
        applyEnvironment()
        currentClip = nil
        isPlaying = settings.autoplay
        if !clips.isEmpty { play(0) }
        frame(animated: false)
        isLoading = false
    }

    // MARK: - Studio handoff

    struct LentModel { let nodes: [SCNNode]; let rootPlayers: [(String, SCNAnimationPlayer)]; let clips: [ClipInfo]; let name: String }
    private(set) var lent: LentModel?

    /// Gives the current model to Studio (it's moved, not copied, so rigs and animations stay intact).
    func lendToStudio() -> LentModel {
        clips.forEach { $0.players.forEach { $0.stop() } }
        selectedBone = nil
        boneMarker?.removeFromParentNode(); boneMarker = nil
        if shading != .lit { shading = .lit }
        if channelView != .final { channelView = .final }
        showAllParts()
        if zUp { zUpSilently(false) }
        var rootPlayers: [(String, SCNAnimationPlayer)] = []
        for k in scene.rootNode.animationKeys {
            if let p = scene.rootNode.animationPlayer(forKey: k) { rootPlayers.append((k, p)) }
            scene.rootNode.removeAnimation(forKey: k)
        }
        let nodes = topNodes
        nodes.forEach { $0.removeFromParentNode() }
        topNodes = []
        let l = LentModel(nodes: nodes, rootPlayers: rootPlayers, clips: clips, name: (stats.name as NSString).deletingPathExtension)
        lent = l
        return l
    }

    /// Shows whatever Studio produced (the edited model, new shapes, saved animations).
    func receiveFromStudio(scene scn: SCNScene?, newClips: [ClipInfo], name: String) {
        let l = lent; lent = nil
        guard let scn else {
            // Studio was emptied: put back the lent model if there was one, else keep a clean stage.
            if let l {
                let back = SCNScene(); l.nodes.forEach { back.rootNode.addChildNode($0) }
                for (k, p) in l.rootPlayers { back.rootNode.addAnimationPlayer(p, forKey: k) }
                install(scene: back, gltfAnimations: [], extraClips: l.clips, url: sourceURL, format: stats.format, name: stats.name, bytes: stats.fileBytes)
            }
            return
        }
        for (k, p) in l?.rootPlayers ?? [] { scn.rootNode.addAnimationPlayer(p, forKey: k); p.stop() }
        let clips = (l?.clips ?? []) + newClips
        install(scene: scn, gltfAnimations: [], extraClips: clips, url: nil, format: l == nil ? "Studio" : "Studio · \(stats.format)", name: name, bytes: 0)
        if !newClips.isEmpty, let i = self.clips.firstIndex(where: { $0.id == newClips.last!.id }) { play(i) }
    }

    // MARK: - settings

    private func observeSettings() {
        let s = settings
        // Live-apply settings that change rendering or the current view (dropFirst skips the initial value).
        Publishers.MergeMany(s.$hdr.map { _ in () }.eraseToAnyPublisher(), s.$bloom.map { _ in () }.eraseToAnyPublisher(),
                             s.$shadowQuality.map { _ in () }.eraseToAnyPublisher())
            .dropFirst(3)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.applyRenderSettings() }.store(in: &settingsSinks)
        s.$defaultFOV.dropFirst().sink { [weak self] v in self?.fov = v }.store(in: &settingsSinks)
        s.$defaultEnvironment.dropFirst().sink { [weak self] v in self?.env = v }.store(in: &settingsSinks)
        s.$defaultSkeleton.dropFirst().sink { [weak self] v in self?.showSkeleton = v }.store(in: &settingsSinks)
        s.$defaultGroundShadow.dropFirst().sink { [weak self] v in self?.groundShadow = v }.store(in: &settingsSinks)
        s.$defaultSpeed.dropFirst().sink { [weak self] v in self?.speed = v }.store(in: &settingsSinks)
        s.$loopAnimations.dropFirst().sink { [weak self] loop in
            guard let self, let i = self.currentClip else { return }
            self.clips[i].players.forEach { $0.animation.repeatCount = loop ? .greatestFiniteMagnitude : 1 }
        }.store(in: &settingsSinks)
        s.$maxRecents.dropFirst().receive(on: DispatchQueue.main).sink { [weak self] _ in self?.pruneRecents(); self?.loadRecents() }.store(in: &settingsSinks)
    }

    private func applyRenderSettings() {
        guard let cam = cameraNode.camera, let sun = sunNode.light else { return }
        cam.wantsHDR = settings.hdr
        cam.bloomIntensity = settings.bloom && settings.hdr ? 0.15 : 0
        switch settings.shadowQuality {
        case 0: sun.castsShadow = false
        case 1: sun.castsShadow = true; sun.shadowSampleCount = 4; sun.shadowMapSize = CGSize(width: 1024, height: 1024); sun.shadowRadius = 3
        default: sun.castsShadow = true; sun.shadowSampleCount = 12; sun.shadowMapSize = CGSize(width: 2048, height: 2048); sun.shadowRadius = 6
        }
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
        orbit.frame(center: b.center, radius: b.radius, distance: dist, animated: animated)
        floorNode.simdPosition = SIMD3(0, b.minY, 0)
        if let light = sunNode.light { light.orthographicScale = CGFloat(b.radius * 1.6) }
    }

    private func updateTurntable() { orbit.autoRotate = turntable }

    // MARK: - playback

    func play(_ index: Int) {
        guard clips.indices.contains(index) else { return }
        clips.forEach { $0.players.forEach { $0.stop() } }
        currentClip = index
        for p in clips[index].players {
            p.animation.repeatCount = settings.loopAnimations ? .greatestFiniteMagnitude : 1
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
            if channelView != .final {
                g.materials = originals.map { self.channelMaterial(from: $0) }
                return
            }
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
                out.append(MaterialInfo(name: m.name ?? "Material \(out.count + 1)", model: Self.lightingName(m.lightingModel), textures: texs, thumbnail: thumb, color: color, material: m))
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
    /// Writes just the model (no studio floor, lights, camera or bone marker) to a USDZ for AR Quick Look,
    /// scaled to a sensible real-world size when the file's units are far off.
    func usdzForAR() -> URL? {
        if let u = sourceURL, u.pathExtension.lowercased() == "usdz" { return u }
        let savedShading = shading
        if shading != .lit { shading = .lit }
        let extras = [cameraNode, floorNode, sunNode] + (boneMarker.map { [$0] } ?? [])
        let parents = extras.map { $0.parent }
        extras.forEach { $0.removeFromParentNode() }
        let bg = scene.background.contents; scene.background.contents = nil

        let wrapper = SCNNode(); wrapper.name = "Model"
        let maxDim = max(stats.size.x, stats.size.y, stats.size.z)
        if settings.arFitSize, maxDim > 4 || (maxDim > 0 && maxDim < 0.03) { wrapper.simdScale = SIMD3(repeating: 0.6 / maxDim) }
        let b = modelBounds()
        let models = topNodes
        models.forEach { wrapper.addChildNode($0) }
        wrapper.simdPosition = SIMD3(-b.center.x, -b.minY, -b.center.z) * wrapper.simdScale
        scene.rootNode.addChildNode(wrapper)

        let base = ((stats.name as NSString).deletingPathExtension as NSString).replacingOccurrences(of: "/", with: "-")
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("\(base)-\(Int(Date().timeIntervalSince1970)).usdz")
        let ok = scene.write(to: out, options: nil, delegate: nil, progressHandler: nil)

        models.forEach { scene.rootNode.addChildNode($0) }
        wrapper.removeFromParentNode()
        for (n, p) in zip(extras, parents) { (p ?? scene.rootNode).addChildNode(n) }
        scene.background.contents = bg
        if savedShading != .lit { shading = savedShading }
        return ok ? out : nil
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
        for r in sorted.dropFirst(settings.maxRecents) { try? FileManager.default.removeItem(at: Self.recentsDir.appendingPathComponent(r.id)) }
    }

    func openRecent(_ r: RecentItem) { open(url: r.mainURL, displayName: r.name) }
    func deleteRecent(_ r: RecentItem) { try? FileManager.default.removeItem(at: Self.recentsDir.appendingPathComponent(r.id)); loadRecents() }
    func clearRecents() { recents.forEach { try? FileManager.default.removeItem(at: Self.recentsDir.appendingPathComponent($0.id)) }; loadRecents() }

    // MARK: - toast

    func showToast(_ msg: String) {
        toastTask?.cancel()
        withAnimation(.spring(duration: 0.45, bounce: 0.3)) { toast = msg }
        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(min(9.0, max(3.5, Double(msg.count) / 14.0)) * 1_000_000_000))
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

    /// Full-size image from any SceneKit material contents (image, file URL, path or Model I/O texture).
    static func thumbnailFull(_ contents: Any?) -> UIImage? {
        switch contents {
        case let i as UIImage: return i
        case let u as URL: return UIImage(contentsOfFile: u.path)
        case let s as String: return UIImage(contentsOfFile: s) ?? UIImage(named: s)
        case let t as MDLTexture: return t.imageFromTexture().map { UIImage(cgImage: $0.takeUnretainedValue()) }
        default:
            if let c = contents, CFGetTypeID(c as CFTypeRef) == CGImage.typeID { return UIImage(cgImage: c as! CGImage) }
            return nil
        }
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


// MARK: - Scene outliner: parts, smart groups, texture channels

struct PartInfo: Identifiable, Hashable {
    let node: SCNNode
    let name: String
    let triangles: Int
    let materialName: String
    let topName: String
    var id: ObjectIdentifier { ObjectIdentifier(node) }
    static func == (a: PartInfo, b: PartInfo) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

struct PartGroup: Identifiable {
    let id: String
    let name: String
    let icon: String
    let color: Color
    let parts: [PartInfo]
    var triangles: Int { parts.reduce(0) { $0 + $1.triangles } }
}

enum PartGrouping: String, CaseIterable, Identifiable {
    case smart = "Smart", material = "Material", hierarchy = "Hierarchy"
    var id: String { rawValue }
}

enum TextureChannel: String, CaseIterable, Identifiable {
    case color = "Base Colour", normal = "Normal", roughness = "Roughness", metalness = "Metalness", emission = "Emission", occlusion = "Ambient Occlusion"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .color: return "paintpalette.fill"; case .normal: return "circle.hexagongrid.fill"; case .roughness: return "circle.dotted"
        case .metalness: return "sparkle"; case .emission: return "lightbulb.fill"; case .occlusion: return "circle.lefthalf.filled"
        }
    }
    var tint: Color {
        switch self {
        case .color: return .orange; case .normal: return .indigo; case .roughness: return .gray
        case .metalness: return .teal; case .emission: return .yellow; case .occlusion: return .brown
        }
    }
    func property(_ m: SCNMaterial) -> SCNMaterialProperty {
        switch self {
        case .color: return m.diffuse; case .normal: return m.normal; case .roughness: return m.roughness
        case .metalness: return m.metalness; case .emission: return m.emission; case .occlusion: return m.ambientOcclusion
        }
    }
    /// What the property shows when the channel is switched off.
    var neutral: Any? {
        switch self {
        case .color: return UIColor(white: 0.78, alpha: 1); case .normal: return nil; case .roughness: return NSNumber(value: 0.55)
        case .metalness: return NSNumber(value: 0.0); case .emission: return UIColor.black; case .occlusion: return nil
        }
    }
}

enum ChannelView: String, CaseIterable, Identifiable {
    case final = "Final", color = "Colour", normal = "Normal", roughness = "Rough", metalness = "Metal", occlusion = "AO", emission = "Emissive", uv = "UV Grid"
    var id: String { rawValue }
    var channel: TextureChannel? {
        switch self {
        case .color: return .color; case .normal: return .normal; case .roughness: return .roughness; case .metalness: return .metalness
        case .occlusion: return .occlusion; case .emission: return .emission; default: return nil
        }
    }
}

/// Keyword rules for smart grouping, checked in order (more specific first).
private let smartRules: [(id: String, name: String, icon: String, color: Color, words: [String])] = [
    ("weapons", "Weapons", "scope", .red, ["gun", "rifle", "pistol", "weapon", "sword", "knife", "blade", "shield", "bow", "arrow", "ammo", "magazine", "scope", "barrel", "trigger", "muzzle", "grenade", "axe", "spear", "katana", "handgun", "shotgun", "smg"]),
    ("hair", "Hair & Fur", "comb.fill", .brown, ["hair", "beard", "mustache", "moustache", "fur", "bang", "ponytail", "brow", "eyebrow", "lash", "eyelash", "scalp"]),
    ("accessories", "Accessories", "eyeglasses", .purple, ["glass", "goggle", "hat", "cap", "beanie", "hood", "watch", "ring", "necklace", "earring", "jewel", "bracelet", "chain", "badge", "scarf", "headphone", "headset", "accessor", "earring", "eyeglass", "sunglass"]),
    ("face", "Head & Face", "face.smiling", .pink, ["head", "face", "eye", "iris", "pupil", "cornea", "teeth", "tooth", "tongue", "mouth", "jaw", "ear", "nose", "lip", "cheek", "skull", "eyelayer"]),
    ("armor", "Armour & Gear", "shield.lefthalf.filled", .indigo, ["armor", "armour", "helmet", "visor", "plate", "pad", "kneepad", "elbowpad", "strap", "holster", "backpack", "bag", "pouch", "harness", "gear", "tactical", "mask", "respirator"]),
    ("clothing", "Clothing", "tshirt.fill", .blue, ["cloth", "shirt", "tshirt", "pant", "trouser", "jean", "short", "jacket", "coat", "hoodie", "sweater", "vest", "top", "bottom", "dress", "skirt", "suit", "uniform", "shoe", "boot", "sneaker", "sock", "glove", "belt", "outfit", "sleeve", "collar", "cape", "robe"]),
    ("body", "Body", "figure.stand", .orange, ["body", "skin", "torso", "chest", "arm", "leg", "hand", "finger", "foot", "feet", "toe", "neck", "hip", "spine", "shoulder", "naked", "nude", "limb", "thigh", "calf", "knee", "elbow", "wrist", "palm", "abdomen", "belly", "butt", "pelvis", "genesis", "character"]),
    ("vehicle", "Vehicle", "car.fill", .teal, ["wheel", "tire", "tyre", "car", "door", "window", "windshield", "engine", "chassis", "hull", "wing", "seat", "steering"]),
    ("environment", "Environment", "tree.fill", .green, ["ground", "floor", "terrain", "grass", "tree", "leaf", "leaves", "rock", "stone", "wall", "building", "roof", "plant", "water", "sky"]),
]

extension ViewerModel {

    /// Splits names into lowercase words: "CPD_EyeLayer" -> ["cpd", "eye", "layer"], "mesh-body2" -> ["mesh", "body"].
    private static func words(_ s: String) -> [String] {
        var out: [String] = []; var cur = ""
        var prevLower = false
        for ch in s {
            if ch.isLetter {
                if ch.isUppercase && prevLower { out.append(cur); cur = "" }
                cur.append(Character(ch.lowercased())); prevLower = ch.isLowercase
            } else {
                if !cur.isEmpty { out.append(cur); cur = "" }
                prevLower = false
            }
        }
        if !cur.isEmpty { out.append(cur) }
        return out.filter { $0.count > 1 }
    }

    fileprivate func collectParts() {
        var out: [PartInfo] = []
        var counter = 0
        for top in topNodes {
            top.enumerateHierarchy { n, _ in
                guard let g = n.geometry, !(n.name ?? "").hasPrefix("RigViewer.") else { return }
                counter += 1
                var tris = 0
                for e in g.elements where [.triangles, .triangleStrip, .polygon].contains(e.primitiveType) { tris += e.primitiveCount }
                var name = n.name ?? ""
                if name.isEmpty || name.hasPrefix("joint:") { name = g.name ?? "" }
                if name.isEmpty { name = "Part \(counter)" }
                // Name the hierarchy group after the highest named ancestor below the scene root.
                var a: SCNNode = n
                while let p = a.parent, p.parent != nil, !(p.name ?? "").isEmpty, p.name != "FBX Root" { a = p }
                out.append(PartInfo(node: n, name: name, triangles: tris,
                                    materialName: g.firstMaterial?.name ?? "Default",
                                    topName: (a === n ? (n.parent?.name ?? "Scene") : (a.name ?? "Scene"))))
            }
        }
        parts = out
    }

    /// Groups parts by the current mode. Smart mode reads part, material and parent names.
    var partGroups: [PartGroup] {
        switch groupMode {
        case .material:
            let d = Dictionary(grouping: parts, by: { $0.materialName })
            return d.keys.sorted().map { PartGroup(id: "m-\($0)", name: $0, icon: "paintpalette.fill", color: .orange, parts: d[$0]!) }
        case .hierarchy:
            let d = Dictionary(grouping: parts, by: { $0.topName })
            return d.keys.sorted().map { PartGroup(id: "h-\($0)", name: $0, icon: "list.bullet.indent", color: .blue, parts: d[$0]!) }
        case .smart:
            var buckets: [String: [PartInfo]] = [:]
            for p in parts {
                // The part's own name decides first; material and parent names break ties for generic names like "Mesh_12".
                let own = Self.words(p.name)
                let extra = Self.words(p.materialName) + Self.words(p.node.parent?.name ?? "")
                func match(_ ws: [String]) -> (id: String, name: String, icon: String, color: Color, words: [String])? {
                    smartRules.first { r in ws.contains { word in r.words.contains { word.hasPrefix($0) } } }
                }
                let rule = match(own) ?? match(extra)
                buckets[rule?.id ?? "other", default: []].append(p)
            }
            var groups: [PartGroup] = smartRules.compactMap { r in
                buckets[r.id].map { PartGroup(id: r.id, name: r.name, icon: r.icon, color: r.color, parts: $0) }
            }
            if let o = buckets["other"] { groups.append(PartGroup(id: "other", name: groups.isEmpty ? "Model" : "Other Parts", icon: "cube.fill", color: .gray, parts: o)) }
            return groups
        }
    }

    // MARK: visibility

    func isVisible(_ p: PartInfo) -> Bool { !hiddenParts.contains(p.id) }

    func setVisible(_ p: PartInfo, _ visible: Bool) {
        p.node.isHidden = !visible
        if visible { hiddenParts.remove(p.id) } else { hiddenParts.insert(p.id) }
    }

    func setVisible(_ g: PartGroup, _ visible: Bool) {
        var h = hiddenParts
        for p in g.parts { p.node.isHidden = !visible; if visible { h.remove(p.id) } else { h.insert(p.id) } }
        hiddenParts = h
    }

    func solo(_ g: PartGroup) {
        let keep = Set(g.parts.map(\.id))
        var h = Set<ObjectIdentifier>()
        for p in parts { let hide = !keep.contains(p.id); p.node.isHidden = hide; if hide { h.insert(p.id) } }
        hiddenParts = h
        showToast("Showing only \(g.name)")
    }

    func solo(_ p: PartInfo) { solo(PartGroup(id: "solo", name: p.name, icon: "", color: .clear, parts: [p])) }

    func showAllParts() { parts.forEach { $0.node.isHidden = false }; hiddenParts = [] }
    func hideAllParts() { parts.forEach { $0.node.isHidden = true }; hiddenParts = Set(parts.map(\.id)) }

    /// Moves the camera to frame just these parts, keeping the current viewing angle.
    func focus(_ ps: [PartInfo]) {
        var mn = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var mx = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        for p in ps {
            let (a, b) = p.node.boundingBox
            for i in 0..<8 {
                let c = SIMD3<Float>(i & 1 == 0 ? Float(a.x) : Float(b.x), i & 2 == 0 ? Float(a.y) : Float(b.y), i & 4 == 0 ? Float(a.z) : Float(b.z))
                let w = p.node.simdConvertPosition(c, to: nil); mn = simd_min(mn, w); mx = simd_max(mx, w)
            }
        }
        guard mn.x <= mx.x else { return }
        let r = max(simd_length(mx - mn) / 2, radius * 0.02)
        let half = Float(fov) * .pi / 360
        orbit.focus(center: (mn + mx) / 2, radius: r, distance: r / sinf(half) * 1.2)
    }

    // MARK: materials

    func isVisible(_ m: MaterialInfo) -> Bool { m.material.map { !hiddenMaterials.contains(ObjectIdentifier($0)) } ?? true }

    func setVisible(_ info: MaterialInfo, _ visible: Bool) {
        guard let m = info.material else { return }
        let key = ObjectIdentifier(m)
        if transparencySnapshot[key] == nil { transparencySnapshot[key] = m.transparency }
        m.transparency = visible ? (transparencySnapshot[key] ?? 1) : 0
        m.writesToDepthBuffer = visible
        if visible { hiddenMaterials.remove(key) } else { hiddenMaterials.insert(key) }
        if shading != .lit || channelView != .final { applyShading() }
    }

    // MARK: texture channels

    private var litMaterials: [SCNMaterial] {
        var seen = Set<ObjectIdentifier>(); var out: [SCNMaterial] = []
        for list in originalMaterials.values { for m in list where !seen.contains(ObjectIdentifier(m)) { seen.insert(ObjectIdentifier(m)); out.append(m) } }
        return out
    }

    /// How many materials actually use an image for this channel.
    func textureCount(_ c: TextureChannel) -> Int {
        litMaterials.filter { m in
            let contents = channelSnapshot[ObjectIdentifier(m)]?[c] ?? c.property(m).contents
            return Self.imageSize(contents) != nil
        }.count
    }

    func isEnabled(_ c: TextureChannel) -> Bool { !disabledChannels.contains(c) }

    func setChannel(_ c: TextureChannel, enabled: Bool) {
        for m in litMaterials {
            let key = ObjectIdentifier(m)
            var snap = channelSnapshot[key] ?? [:]
            if snap[c] == nil { snap[c] = c.property(m).contents ?? NSNull() }
            channelSnapshot[key] = snap
            let original = snap[c] is NSNull ? nil : snap[c]
            c.property(m).contents = enabled ? original : c.neutral
        }
        if enabled { disabledChannels.remove(c) } else { disabledChannels.insert(c) }
        if shading != .lit || channelView != .final { applyShading() }
    }

    func resetChannels() { for c in TextureChannel.allCases where !isEnabled(c) { setChannel(c, enabled: true) } }

    /// Unlit material that shows a single texture map (or a UV grid) so it can be inspected on the model.
    fileprivate func channelMaterial(from o: SCNMaterial) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.isDoubleSided = o.isDoubleSided
        m.transparency = hiddenMaterials.contains(ObjectIdentifier(o)) ? 0 : 1
        if channelView == .uv {
            m.diffuse.contents = Self.checker
            m.diffuse.wrapS = .repeat; m.diffuse.wrapT = .repeat
            m.diffuse.contentsTransform = SCNMatrix4MakeScale(6, 6, 1)
            m.diffuse.magnificationFilter = .nearest
            return m
        }
        guard let c = channelView.channel else { return m }
        let original = channelSnapshot[ObjectIdentifier(o)]?[c] ?? c.property(o).contents
        let src = c.property(o)
        switch original {
        case let n as NSNumber: m.diffuse.contents = UIColor(white: CGFloat(truncating: n), alpha: 1)
        case is NSNull, nil:
            m.diffuse.contents = c == .normal ? UIColor(red: 0.5, green: 0.5, blue: 1, alpha: 1) : c == .occlusion ? UIColor.white : UIColor(white: 0.15, alpha: 1)
        default: m.diffuse.contents = original
        }
        m.diffuse.contentsTransform = src.contentsTransform
        m.diffuse.wrapS = src.wrapS; m.diffuse.wrapT = src.wrapT
        m.diffuse.mappingChannel = src.mappingChannel
        if c == .roughness || c == .metalness || c == .occlusion {
            // glTF packs these into one ORM image; show the matching colour channel as greyscale.
            m.diffuse.textureComponents = c == .roughness ? .green : c == .metalness ? .blue : .red
            if Self.imageSize(original) == nil { m.diffuse.textureComponents = .all }
        }
        return m
    }
}
