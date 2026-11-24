import SceneKit
import MetalKit
import UIKit
import simd

/// Builds materials and streams the world chunks in and out around the camera.
final class WorldRenderer {
    let meta: WorldMeta
    let root = SCNNode()
    private(set) var materials: [SCNMaterial] = []
    private var detailIDs = Set<Int>()
    private var loaded: [Int: (base: SCNNode, detail: SCNNode)] = [:]
    private var pending = Set<Int>()
    private var ready: [(Int, SCNNode, SCNNode)] = []
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "apex.chunks", qos: .userInitiated, attributes: .concurrent)
    weak var view: SCNView?

    private(set) var facadeMats: [SCNMaterial] = []
    private(set) var lampMats: [SCNMaterial] = []
    private(set) var waterMat: SCNMaterial!
    let ocean: SCNNode

    init(meta: WorldMeta, device: MTLDevice?) {
        self.meta = meta
        Res.device = device
        root.name = "World"
        let water = WorldRenderer.makeWater()
        waterMat = water
        let plane = SCNPlane(width: 24000, height: 24000)
        plane.materials = [water]
        ocean = SCNNode(geometry: plane)
        ocean.eulerAngles.x = -.pi / 2
        ocean.position = SCNVector3(0, -0.05, 0)
        ocean.castsShadow = false
        ocean.renderingOrder = -5
        root.addChildNode(ocean)
        buildMaterials(device: device)
    }

    // MARK: Materials

    private static func prop(_ p: SCNMaterialProperty, _ contents: Any?, repeatWrap: Bool = true) {
        p.contents = contents
        if repeatWrap { p.wrapS = .repeat; p.wrapT = .repeat }
        p.mipFilter = .linear
        p.minificationFilter = .linear
        p.magnificationFilter = .linear
        p.maxAnisotropy = 8
    }

    private static func pbr(_ color: UIColor? = nil, tex: String? = nil, rough: CGFloat = 0.8, metal: CGFloat = 0, doubleSided: Bool = false) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        if let tex, let img = Res.texture(tex) { prop(m.diffuse, img) } else { m.diffuse.contents = color ?? UIColor.gray }
        m.roughness.contents = NSNumber(value: Double(rough))
        m.metalness.contents = NSNumber(value: Double(metal))
        m.isDoubleSided = doubleSided
        return m
    }

    private static func foliage(_ tex: String, tint: UIColor? = nil) -> SCNMaterial {
        let m = pbr(tex: tex, rough: 0.9, doubleSided: true)
        if let tint { m.multiply.contents = tint }
        m.blendMode = .replace
        m.writesToDepthBuffer = true
        m.shaderModifiers = [.surface: "if (_surface.diffuse.a < 0.45) discard_fragment();\n_surface.diffuse.a = 1.0;"]
        return m
    }

    private static func makeWater() -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = UIColor(red: 0.07, green: 0.25, blue: 0.36, alpha: 1)
        m.roughness.contents = NSNumber(value: 0.06)
        m.metalness.contents = NSNumber(value: 0.15)
        if let n = Res.texture("water_n_1k.jpg", srgb: false) {
            prop(m.normal, n)
            m.normal.intensity = 0.55
            m.normal.contentsTransform = SCNMatrix4MakeScale(600, 600, 1)
        }
        return m
    }

    private func buildMaterials(device: MTLDevice?) {
        let asphaltN = Res.texture("asphalt_n_2k.jpg", srgb: false)
        func road(_ tex: String) -> SCNMaterial {
            let m = WorldRenderer.pbr(tex: tex, rough: 0.82)
            if let asphaltN { WorldRenderer.prop(m.normal, asphaltN); m.normal.intensity = 0.5 }
            return m
        }
        func facade(_ n: String) -> SCNMaterial {
            let glassy = n.contains("glass") || n.contains("office")
            let m = WorldRenderer.pbr(tex: n + "_2k.jpg", rough: glassy ? 0.3 : 0.6, metal: glassy ? 0.35 : 0)
            if let em = Res.texture(n + "_em.jpg") { WorldRenderer.prop(m.emission, em); m.emission.intensity = 0 }
            facadeMats.append(m)
            return m
        }
        let lamp = WorldRenderer.pbr(UIColor(red: 1, green: 0.97, blue: 0.88, alpha: 1), rough: 0.4)
        lamp.emission.contents = UIColor(red: 1, green: 0.85, blue: 0.6, alpha: 1)
        lamp.emission.intensity = 0
        lampMats.append(lamp)
        let shrub = WorldRenderer.foliage("leaves_green.png", tint: UIColor(red: 0.85, green: 0.82, blue: 0.55, alpha: 1))
        let concrete = WorldRenderer.pbr(tex: "concrete_2k.jpg", rough: 0.9, doubleSided: true)
        let table: [String: SCNMaterial] = [
            "terrain": terrainMaterial(device: device),
            "road_street": road("road_street_2k.jpg"), "road_avenue": road("road_avenue_2k.jpg"), "road_highway": road("road_highway_2k.jpg"),
            "sidewalk": WorldRenderer.pbr(tex: "sidewalk_2k.jpg", rough: 0.9),
            "fac_nyglass": facade("fac_nyglass"), "fac_nybrick": facade("fac_nybrick"), "fac_lastucco": facade("fac_lastucco"),
            "fac_miami": facade("fac_miami"), "fac_miami2": facade("fac_miami2"), "fac_txstone": facade("fac_txstone"),
            "fac_adobe": facade("fac_adobe"), "fac_office": facade("fac_office"),
            "roof": WorldRenderer.pbr(tex: "roof_1k.jpg", rough: 0.9), "asphalt": road("asphalt_4k.jpg"),
            "bark": WorldRenderer.pbr(UIColor(red: 0.35, green: 0.27, blue: 0.2, alpha: 1), rough: 0.95),
            "palm_frond": WorldRenderer.foliage("palm_frond.png"), "leaves_green": WorldRenderer.foliage("leaves_green.png"),
            "leaves_maple": WorldRenderer.foliage("leaves_maple.png"), "leaves_dark": WorldRenderer.foliage("leaves_dark.png"),
            "cactus": WorldRenderer.pbr(UIColor(red: 0.31, green: 0.48, blue: 0.23, alpha: 1), rough: 0.7),
            "metal": WorldRenderer.pbr(UIColor(red: 0.72, green: 0.74, blue: 0.76, alpha: 1), rough: 0.35, metal: 0.7),
            "concrete": concrete,
            "white": WorldRenderer.pbr(UIColor(white: 0.95, alpha: 1), rough: 0.6, doubleSided: true),
            "red_paint": WorldRenderer.pbr(UIColor(red: 0.75, green: 0.22, blue: 0.17, alpha: 1), rough: 0.5, doubleSided: true),
            "grass_tuft": WorldRenderer.foliage("grass_tuft.png"),
            "water": waterMat, "lamp": lamp,
            "wood": WorldRenderer.pbr(UIColor(red: 0.48, green: 0.35, blue: 0.23, alpha: 1), rough: 0.85),
            "rock": WorldRenderer.pbr(tex: "rock_2k.jpg", rough: 0.95),
            "dark_metal": WorldRenderer.pbr(UIColor(red: 0.23, green: 0.24, blue: 0.26, alpha: 1), rough: 0.4, metal: 0.6),
            "yellow": WorldRenderer.pbr(UIColor(red: 0.95, green: 0.76, blue: 0, alpha: 1), rough: 0.5),
            "park_grass": WorldRenderer.pbr(tex: "grass_2k.jpg", rough: 0.95),
            "shrub": shrub,
        ]
        materials = meta.materials.map { table[$0] ?? WorldRenderer.pbr(.magenta) }
        let detailNames: Set<String> = ["bark", "palm_frond", "leaves_green", "leaves_maple", "leaves_dark", "cactus", "grass_tuft", "shrub", "lamp"]
        for (i, n) in meta.materials.enumerated() where detailNames.contains(n) { detailIDs.insert(i) }
    }

    /// Terrain: blends sand / grass / desert / rock / dirt using a world-space splat map (no visible tiling seams between chunks).
    private func terrainMaterial(device: MTLDevice?) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = UIColor(white: 0.6, alpha: 1)
        m.roughness.contents = NSNumber(value: 0.95)
        m.metalness.contents = NSNumber(value: 0)
        func p(_ f: String) -> SCNMaterialProperty {
            let pr = SCNMaterialProperty(contents: Res.texture(f) ?? UIColor.gray)
            pr.wrapS = .repeat; pr.wrapT = .repeat; pr.mipFilter = .linear; pr.maxAnisotropy = 8
            return pr
        }
        func linear(_ name: String) -> SCNMaterialProperty {
            var c: Any = UIColor.black
            if let device, let url = Res.url(name, "World"),
               let t = try? MTKTextureLoader(device: device).newTexture(URL: url, options: [.SRGB: false, .generateMipmaps: false]) { c = t }
            let sp = SCNMaterialProperty(contents: c)
            sp.wrapS = .clamp; sp.wrapT = .clamp
            return sp
        }
        m.setValue(linear("splat.png"), forKey: "splatTex")
        m.setValue(linear("splat_rock.png"), forKey: "splatRock")
        m.setValue(p("sand_2k.jpg"), forKey: "sandTex")
        m.setValue(p("grass_2k.jpg"), forKey: "grassTex")
        m.setValue(p("desert_2k.jpg"), forKey: "desertTex")
        m.setValue(p("rock_2k.jpg"), forKey: "rockTex")
        m.setValue(p("dirt_2k.jpg"), forKey: "dirtTex")
        // splat texel (i, j) sits at world (x0 + i*10, z0 + j*10)
        let nx: Float = 641, nz: Float = 441, cell: Float = 10
        m.setValue(NSValue(scnVector4: SCNVector4(meta.bounds[0] - cell / 2, meta.bounds[1] - cell / 2, 1 / (cell * nx), 1 / (cell * nz))), forKey: "splatXform")
        m.shaderModifiers = [.surface: """
        #pragma arguments
        texture2d<float> splatTex;
        texture2d<float> splatRock;
        texture2d<float> sandTex;
        texture2d<float> grassTex;
        texture2d<float> desertTex;
        texture2d<float> rockTex;
        texture2d<float> dirtTex;
        float4 splatXform;
        #pragma body
        constexpr sampler rs(filter::linear, mip_filter::linear, address::repeat, max_anisotropy(8));
        constexpr sampler cs(filter::linear, address::clamp_to_edge);
        float3 wp = (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz;
        float2 suv = float2((wp.x - splatXform.x) * splatXform.z, (wp.z - splatXform.y) * splatXform.w);
        float4 w = float4(splatTex.sample(cs, suv).rgb, splatRock.sample(cs, suv).r);
        float rest = max(0.0, 1.0 - w.r - w.g - w.b - w.a);
        float2 t1 = wp.xz / 24.0;
        float2 t2 = wp.xz / 97.0;
        float3 sand = mix(sandTex.sample(rs, t1).rgb, sandTex.sample(rs, t2).rgb, 0.35);
        float3 grass = mix(grassTex.sample(rs, t1).rgb, grassTex.sample(rs, t2).rgb, 0.4);
        float3 desert = mix(desertTex.sample(rs, t1).rgb, desertTex.sample(rs, t2).rgb, 0.35);
        float3 rock = rockTex.sample(rs, float2((wp.x + wp.z) / 60.0, wp.y / 40.0)).rgb;
        float3 dirt = dirtTex.sample(rs, t1).rgb;
        float3 c = sand * w.r + grass * w.g + desert * w.b + rock * w.a + dirt * rest;
        _surface.diffuse = float4(c, 1.0);
        """]
        return m
    }

    // MARK: Day / night

    func setNight(_ k: Float) {
        for m in facadeMats { m.emission.intensity = CGFloat(k) * 1.15 }
        for m in lampMats { m.emission.intensity = CGFloat(k) * 6 }
    }

    func animateWater(_ t: Float) {
        let s: Float = 600
        var tr = SCNMatrix4MakeScale(s, s, 1)
        tr = SCNMatrix4Translate(tr, t * 0.6, t * 0.25, 0)
        waterMat.normal.contentsTransform = tr
    }

    // MARK: Streaming

    var loadedCount: Int { loaded.count }

    /// Fraction of the chunks within `radius` of the point that are on screen.
    func readiness(around c: SIMD2<Float>, radius: Float) -> Float {
        var need = 0, have = 0
        for (i, ch) in meta.chunks.enumerated() {
            if distToChunk(ch, c) < radius { need += 1; if loaded[i] != nil { have += 1 } }
        }
        return need == 0 ? 1 : Float(have) / Float(need)
    }

    private func distToChunk(_ ch: WorldMeta.Chunk, _ c: SIMD2<Float>) -> Float {
        let dx = max(ch.x0 - c.x, 0, c.x - (ch.x0 + meta.chunk))
        let dz = max(ch.z0 - c.y, 0, c.y - (ch.z0 + meta.chunk))
        return (dx * dx + dz * dz).squareRoot()
    }

    /// Call from the render loop.
    func update(center c: SIMD2<Float>, radius: Float, detail: Float) {
        lock.lock(); let fresh = ready; ready.removeAll(); lock.unlock()
        for (i, b, d) in fresh {
            pending.remove(i)
            if loaded[i] == nil && distToChunk(meta.chunks[i], c) < radius + 300 {
                root.addChildNode(b); root.addChildNode(d)
                loaded[i] = (b, d)
            }
        }
        var want: [(Int, Float)] = []
        for (i, ch) in meta.chunks.enumerated() {
            let d = distToChunk(ch, c)
            if let l = loaded[i] {
                if d > radius + 300 {
                    l.base.removeFromParentNode(); l.detail.removeFromParentNode(); loaded[i] = nil
                } else {
                    l.detail.isHidden = d > detail
                }
            } else if d < radius && !pending.contains(i) {
                want.append((i, d))
            }
        }
        want.sort { $0.1 < $1.1 }
        for (i, _) in want.prefix(max(0, 4 - pending.count)) {
            pending.insert(i)
            let file = meta.chunks[i].f, mats = materials, det = detailIDs
            queue.async { [weak self] in
                guard let url = Res.url(file, "World/chunks"), let data = try? Data(contentsOf: url) else {
                    self?.lock.lock(); self?.ready.append((i, SCNNode(), SCNNode())); self?.lock.unlock(); return
                }
                let (b, d) = WorldRenderer.parse(data, materials: mats, detail: det)
                self?.lock.lock(); self?.ready.append((i, b, d)); self?.lock.unlock()
            }
        }
    }

    static func parse(_ d: Data, materials: [SCNMaterial], detail: Set<Int>) -> (SCNNode, SCNNode) {
        let base = SCNNode(), det = SCNNode()
        base.castsShadow = false; det.castsShadow = false
        d.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard raw.count > 6, let ptr = raw.baseAddress else { return }
            var o = 4
            let n = Int(raw.loadUnaligned(fromByteOffset: o, as: UInt16.self)); o += 2
            for _ in 0..<n {
                guard o + 11 <= raw.count else { break }
                let mat = Int(raw.loadUnaligned(fromByteOffset: o, as: UInt16.self))
                let nv = Int(raw.loadUnaligned(fromByteOffset: o + 2, as: UInt32.self))
                let ni = Int(raw.loadUnaligned(fromByteOffset: o + 6, as: UInt32.self))
                let fl = raw.load(fromByteOffset: o + 10, as: UInt8.self)
                o += 11
                let big = (fl & 2) != 0
                let need = nv * (12 + 6 + 8 + ((fl & 1) != 0 ? 4 : 0)) + ni * (big ? 4 : 2)
                guard o + need <= raw.count else { break }
                let pos = Data(bytes: ptr + o, count: nv * 12); o += nv * 12
                var nrm = [Float](repeating: 0, count: nv * 3)
                for k in 0..<(nv * 3) {
                    let h = raw.loadUnaligned(fromByteOffset: o + k * 2, as: UInt16.self)
                    nrm[k] = Float(Float16(bitPattern: h))
                }
                o += nv * 6
                let uv = Data(bytes: ptr + o, count: nv * 8); o += nv * 8
                if (fl & 1) != 0 { o += nv * 4 }
                let idx = Data(bytes: ptr + o, count: ni * (big ? 4 : 2)); o += ni * (big ? 4 : 2)
                if nv == 0 || ni < 3 { continue }
                if ni % 3 != 0 || pos.count != nv * 12 || uv.count != nv * 8 { continue }
                var node: SCNNode? = nil
                let err = ApexTryCatch {
                    let vs = SCNGeometrySource(data: pos, semantic: .vertex, vectorCount: nv, usesFloatComponents: true, componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0, dataStride: 12)
                    let ns = SCNGeometrySource(data: nrm.withUnsafeBufferPointer { Data(buffer: $0) }, semantic: .normal, vectorCount: nv, usesFloatComponents: true, componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0, dataStride: 12)
                    let ts = SCNGeometrySource(data: uv, semantic: .texcoord, vectorCount: nv, usesFloatComponents: true, componentsPerVector: 2, bytesPerComponent: 4, dataOffset: 0, dataStride: 8)
                    let el = SCNGeometryElement(data: idx, primitiveType: .triangles, primitiveCount: ni / 3, bytesPerIndex: big ? 4 : 2)
                    let g = SCNGeometry(sources: [vs, ns, ts], elements: [el])
                    g.materials = [mat < materials.count ? materials[mat] : SCNMaterial()]
                    let n = SCNNode(geometry: g)
                    n.castsShadow = false
                    node = n

                }
                if let err { CrashLog.step("mesh skipped (mat \(mat), nv \(nv), ni \(ni)): \(err.name.rawValue) \(err.reason ?? "")"); continue }
                if let node { (detail.contains(mat) ? det : base).addChildNode(node) }
            }
        }
        return (base, det)
    }
}

// MARK: - Sky

enum Sky {
    struct Palette { var zenith: SIMD3<Float>; var horizon: SIMD3<Float>; var ground: SIMD3<Float>; var sun: SIMD3<Float>; var sunI: Float; var ambI: Float; var envI: Float; var night: Float; var elevation: Float; var fog: SIMD3<Float> }

    static func palette(hour: Float) -> Palette {
        let e = sin((hour - 6) / 12 * .pi)   // -1 … 1
        func ss(_ a: Float, _ b: Float, _ x: Float) -> Float { let t = min(max((x - a) / (b - a), 0), 1); return t * t * (3 - 2 * t) }
        let day = ss(-0.05, 0.35, e)           // 0 night → 1 day
        let golden = ss(-0.18, 0.02, e) * (1 - ss(0.05, 0.35, e))
        let nightZ = SIMD3<Float>(0.015, 0.025, 0.07), nightH = SIMD3<Float>(0.05, 0.07, 0.14)
        let dayZ = SIMD3<Float>(0.18, 0.42, 0.86), dayH = SIMD3<Float>(0.68, 0.80, 0.94)
        let dusk = SIMD3<Float>(1.0, 0.52, 0.28)
        var zen = nightZ + (dayZ - nightZ) * day
        var hor = nightH + (dayH - nightH) * day
        hor = hor + (dusk - hor) * golden * 0.85
        zen = zen + (SIMD3<Float>(0.32, 0.30, 0.55) - zen) * golden * 0.4
        let sunCol = SIMD3<Float>(1, 0.96, 0.9) + (SIMD3<Float>(1, 0.6, 0.35) - SIMD3<Float>(1, 0.96, 0.9)) * golden
        let night = 1 - ss(-0.12, 0.08, e)
        let moon = SIMD3<Float>(0.55, 0.65, 1.0)
        return Palette(zenith: zen, horizon: hor, ground: hor * 0.55,
                       sun: e > -0.05 ? sunCol : moon,
                       sunI: e > -0.05 ? 400 + 1700 * day : 140,
                       ambI: 90 + 260 * day, envI: 0.35 + 1.2 * day,
                       night: night, elevation: e, fog: hor)
    }

    /// Equirectangular gradient image: works both as background and as lighting environment.
    static func image(_ p: Palette) -> UIImage {
        let w = 4, h = 128
        let r = UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }())
        return r.image { ctx in
            for y in 0..<h {
                let v = Float(y) / Float(h - 1)          // 0 top (zenith) … 1 bottom
                var c: SIMD3<Float>
                if v < 0.5 {
                    let t = pow(v / 0.5, 2.2)
                    c = p.zenith + (p.horizon - p.zenith) * t
                } else {
                    let t = min(1, (v - 0.5) / 0.08)
                    c = p.horizon + (p.ground - p.horizon) * t
                }
                UIColor(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: 1).setFill()
                ctx.fill(CGRect(x: 0, y: y, width: w, height: 1))
            }
        }
    }
}
