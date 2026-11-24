import Foundation
import simd
import UIKit
import MetalKit

// MARK: - World description (world.json written by the world builder)

struct WorldMeta: Decodable {
    struct Chunk: Decodable { let f: String; let cx: Int; let cz: Int; let x0: Float; let z0: Float }
    struct City: Decodable {
        let name: String; let region: String
        let cx: Float; let cz: Float; let w: Float; let d: Float; let base: Float
        let xs: [Float]; let zs: [Float]; let xw: [Float]; let zw: [Float]
        let style: String
        var minX: Float { xs.first ?? (cx - w / 2) }
        var maxX: Float { xs.last ?? (cx + w / 2) }
        var minZ: Float { zs.first ?? (cz - d / 2) }
        var maxZ: Float { zs.last ?? (cz + d / 2) }
        func contains(_ x: Float, _ z: Float, margin: Float = 0) -> Bool {
            x > minX - margin && x < maxX + margin && z > minZ - margin && z < maxZ + margin
        }
    }
    struct Highway: Decodable { let name: String; let pts: [[Float]]; let y: [Float]; let kind: String }
    struct Region: Decodable { let name: String; let x: Float; let z: Float }
    struct Spawn: Decodable { let name: String; let x: Float; let z: Float; let region: String }
    struct Landmark: Decodable { let kind: String; let x: Float; let z: Float; let text: String? }

    let walls: [[Float]]
    let bounds: [Float]
    let chunk: Float
    let chunks: [Chunk]
    let materials: [String]
    let cities: [City]
    let highways: [Highway]
    let buildings: [[Float]]
    let poles: [[Float]]
    let trees: [[Float]]
    let regions: [Region]
    let spawns: [Spawn]
    let landmarks: [Landmark]
}

enum WorldRegion: String, CaseIterable {
    case california = "California", arizona = "Arizona", texas = "Texas", florida = "Florida", newYork = "New York"
    static func at(x: Float, z: Float) -> WorldRegion {
        if x < -1650 { return .california }
        if x < -350 { return .arizona }
        if x < 900 { return .texas }
        return z < 150 ? .newYork : .florida
    }
    var tint: UIColor {
        switch self {
        case .california: return UIColor(red: 0.98, green: 0.62, blue: 0.25, alpha: 1)
        case .arizona: return UIColor(red: 0.90, green: 0.36, blue: 0.20, alpha: 1)
        case .texas: return UIColor(red: 0.30, green: 0.52, blue: 0.95, alpha: 1)
        case .florida: return UIColor(red: 0.13, green: 0.80, blue: 0.75, alpha: 1)
        case .newYork: return UIColor(red: 0.70, green: 0.72, blue: 0.80, alpha: 1)
        }
    }
    var symbol: String {
        switch self {
        case .california: return "sun.max.fill"
        case .arizona: return "mountain.2.fill"
        case .texas: return "star.fill"
        case .florida: return "beach.umbrella.fill"
        case .newYork: return "building.2.fill"
        }
    }
}

extension Data {
    @inline(__always) func u32(_ o: Int) -> UInt32 { withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: o, as: UInt32.self)) } }
    @inline(__always) func i32(_ o: Int) -> Int32 { Int32(bitPattern: u32(o)) }
    @inline(__always) func f32(_ o: Int) -> Float { Float(bitPattern: u32(o)) }
}

enum Res {
    static func url(_ name: String, _ dir: String) -> URL? {
        let base = (name as NSString).deletingPathExtension, ext = (name as NSString).pathExtension
        return Bundle.main.url(forResource: base, withExtension: ext, subdirectory: dir)
    }
    static var device: MTLDevice?
    private static var cache: [String: Any] = [:]
    private static let cacheLock = NSLock()

    /// GPU texture with mipmaps straight from the file (no CPU-side bitmap kept around); falls back to UIImage.
    static func texture(_ name: String, srgb: Bool = true) -> Any? {
        let key = name + (srgb ? "" : "#lin")
        cacheLock.lock(); defer { cacheLock.unlock() }
        if let c = cache[key] { return c }
        guard let u = url(name, "Textures") else { return nil }
        var out: Any? = nil
        if let device, let t = try? MTKTextureLoader(device: device).newTexture(URL: u, options: [.SRGB: srgb, .generateMipmaps: true]) {
            out = t
        } else {
            out = UIImage(contentsOfFile: u.path)
        }
        cache[key] = out
        return out
    }

    static func image(_ name: String, _ dir: String = "Textures") -> UIImage? {
        guard let u = url(name, dir) else { return nil }
        return UIImage(contentsOfFile: u.path)
    }
}

// MARK: - Heightfield

final class Heightfield {
    let nx: Int, nz: Int, x0: Float, z0: Float, cell: Float
    private let h: [Float]

    init(data d: Data) {
        nx = Int(d.i32(0)); nz = Int(d.i32(4)); x0 = d.f32(8); z0 = d.f32(12); cell = d.f32(16)
        let n = Int(d.i32(0)) * Int(d.i32(4))
        var arr = [Float](repeating: 0, count: n)
        d.withUnsafeBytes { raw in
            for k in 0..<n { arr[k] = Float(bitPattern: UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: 24 + k * 4, as: UInt32.self))) }
        }
        h = arr
    }

    func height(_ x: Float, _ z: Float) -> Float {
        let fx = min(max((x - x0) / cell, 0), Float(nx) - 1.001)
        let fz = min(max((z - z0) / cell, 0), Float(nz) - 1.001)
        let i = Int(fx), j = Int(fz), tx = fx - Float(i), tz = fz - Float(j)
        let a = h[j * nx + i], b = h[j * nx + i + 1], c = h[(j + 1) * nx + i], d = h[(j + 1) * nx + i + 1]
        return (a * (1 - tx) + b * tx) * (1 - tz) + (c * (1 - tx) + d * tx) * tz
    }
}

// MARK: - Road samples (exact road surface heights and widths)

struct RoadHit { var y: Float; var dist: Float; var halfWidth: Float; var kind: Int; var tangent: SIMD2<Float> }

final class RoadIndex {
    private var px: [Float] = [], pz: [Float] = [], py: [Float] = [], hw: [Float] = [], kd: [UInt8] = []
    private let gx0: Float = -3400, gz0: Float = -2400, cs: Float = 16
    private let gw: Int, gh: Int
    private var start: [Int32], items: [Int32]

    init(data d: Data) {
        let n = Int(d.i32(0))
        px.reserveCapacity(n)
        for k in 0..<n {
            let o = 4 + k * 20
            px.append(d.f32(o)); pz.append(d.f32(o + 4)); py.append(d.f32(o + 8)); hw.append(d.f32(o + 12)); kd.append(UInt8(d.f32(o + 16)))
        }
        gw = Int(6800 / cs) + 1; gh = Int(4800 / cs) + 1
        var count = [Int32](repeating: 0, count: gw * gh + 1)
        var cellOf = [Int](repeating: 0, count: n)
        for k in 0..<n {
            let ci = min(max(Int((px[k] - gx0) / cs), 0), gw - 1), cj = min(max(Int((pz[k] - gz0) / cs), 0), gh - 1)
            cellOf[k] = cj * gw + ci; count[cellOf[k] + 1] += 1
        }
        for c in 0..<(gw * gh) { count[c + 1] += count[c] }
        start = count
        var fill = count
        items = [Int32](repeating: 0, count: n)
        for k in 0..<n { let c = cellOf[k]; items[Int(fill[c])] = Int32(k); fill[c] += 1 }
    }

    func query(_ x: Float, _ z: Float) -> RoadHit? {
        let ci = Int((x - gx0) / cs), cj = Int((z - gz0) / cs)
        var best = -1; var bd: Float = 40 * 40
        for j in (cj - 2)...(cj + 2) where j >= 0 && j < gh {
            for i in (ci - 2)...(ci + 2) where i >= 0 && i < gw {
                let c = j * gw + i
                var s = Int(start[c]); let e = Int(start[c + 1])
                while s < e {
                    let k = Int(items[s]); s += 1
                    let dx = px[k] - x, dz = pz[k] - z, dd = dx * dx + dz * dz
                    if dd < bd { bd = dd; best = k }
                }
            }
        }
        guard best >= 0 else { return nil }
        // Refine on the neighbouring segments so heights are continuous along the road.
        var hit = RoadHit(y: py[best], dist: bd.squareRoot(), halfWidth: hw[best], kind: Int(kd[best]), tangent: SIMD2(1, 0))
        var bestSeg: Float = .greatestFiniteMagnitude
        for (a, b) in [(best - 1, best), (best, best + 1)] where a >= 0 && b < px.count {
            let ax = px[a], az = pz[a], bx = px[b], bz = pz[b]
            let sx = bx - ax, sz = bz - az, len2 = sx * sx + sz * sz
            if len2 > 64 || len2 < 1e-4 { continue }
            let t = min(max(((x - ax) * sx + (z - az) * sz) / len2, 0), 1)
            let qx = ax + sx * t, qz = az + sz * t
            let d = ((x - qx) * (x - qx) + (z - qz) * (z - qz)).squareRoot()
            if d < bestSeg {
                bestSeg = d
                let l = len2.squareRoot()
                hit = RoadHit(y: py[a] + (py[b] - py[a]) * t, dist: d, halfWidth: hw[a] + (hw[b] - hw[a]) * t, kind: Int(kd[a]), tangent: SIMD2(sx / l, sz / l))
            }
        }
        return hit
    }
}

// MARK: - Obstacles

enum ObstacleKind { case building, tree, pole, barrier, car }

struct Contact {
    var normal: SIMD2<Float>     // points away from the obstacle
    var depth: Float
    var point: SIMD2<Float>
    var kind: ObstacleKind
}

final class CollisionWorld {
    private struct Box { var x0, z0, x1, z1, h: Float }
    private struct Circle { var x, z, r: Float; var kind: ObstacleKind }
    private struct Seg { var ax, az, bx, bz: Float }
    private var boxes: [Box] = [], circles: [Circle] = [], segs: [Seg] = []
    private let gx0: Float = -3400, gz0: Float = -2400, cs: Float = 40
    private let gw: Int = 171, gh: Int = 121
    private var cells: [[Int32]]       // encoded: kind in top bits
    private var stamp: [Int32] = []
    private var stampID: Int32 = 0

    init(meta: WorldMeta) {
        cells = Array(repeating: [], count: gw * gh)
        for b in meta.buildings where b.count >= 5 { boxes.append(Box(x0: b[0], z0: b[1], x1: b[2], z1: b[3], h: b[4])) }
        for t in meta.trees where t.count >= 3 { circles.append(Circle(x: t[0], z: t[1], r: max(0.3, t[2]), kind: .tree)) }
        for p in meta.poles where p.count >= 3 { circles.append(Circle(x: p[0], z: p[1], r: max(0.15, p[2]), kind: .pole)) }
        for w in meta.walls where w.count >= 4 { segs.append(Seg(ax: w[0], az: w[1], bx: w[2], bz: w[3])) }
        for (k, b) in boxes.enumerated() { insert(Int32(k), b.x0, b.z0, b.x1, b.z1) }
        for (k, c) in circles.enumerated() { insert(Int32(k) | (1 << 28), c.x - c.r, c.z - c.r, c.x + c.r, c.z + c.r) }
        for (k, s) in segs.enumerated() { insert(Int32(k) | (2 << 28), min(s.ax, s.bx), min(s.az, s.bz), max(s.ax, s.bx), max(s.az, s.bz)) }
        stamp = [Int32](repeating: -1, count: max(boxes.count, circles.count, segs.count) * 3 + 3)
    }

    private func insert(_ id: Int32, _ x0: Float, _ z0: Float, _ x1: Float, _ z1: Float) {
        let i0 = max(0, Int((x0 - gx0) / cs)), i1 = min(gw - 1, Int((x1 - gx0) / cs))
        let j0 = max(0, Int((z0 - gz0) / cs)), j1 = min(gh - 1, Int((z1 - gz0) / cs))
        if i1 < i0 || j1 < j0 { return }
        for j in j0...j1 { for i in i0...i1 { cells[j * gw + i].append(id) } }
    }

    /// Deepest contact for a circle on the ground plane.
    func collide(_ c: SIMD2<Float>, r: Float) -> Contact? {
        stampID &+= 1
        var best: Contact? = nil
        let i0 = max(0, Int((c.x - r - gx0) / cs)), i1 = min(gw - 1, Int((c.x + r - gx0) / cs))
        let j0 = max(0, Int((c.y - r - gz0) / cs)), j1 = min(gh - 1, Int((c.y + r - gz0) / cs))
        if i1 < i0 || j1 < j0 { return nil }
        for j in j0...j1 {
            for i in i0...i1 {
                for id in cells[j * gw + i] {
                    let kind = Int(id >> 28), k = Int(id & 0x0FFF_FFFF)
                    let sidx = k * 3 + kind
                    if stamp[sidx] == stampID { continue }
                    stamp[sidx] = stampID
                    var con: Contact? = nil
                    switch kind {
                    case 0:
                        let b = boxes[k]
                        let qx = min(max(c.x, b.x0), b.x1), qz = min(max(c.y, b.z0), b.z1)
                        let dx = c.x - qx, dz = c.y - qz, d2 = dx * dx + dz * dz
                        if d2 < r * r {
                            if d2 > 1e-6 {
                                let d = d2.squareRoot()
                                con = Contact(normal: SIMD2(dx / d, dz / d), depth: r - d, point: SIMD2(qx, qz), kind: .building)
                            } else {
                                // centre inside: leave by the nearest face
                                let opts: [(Float, SIMD2<Float>)] = [(c.x - b.x0, SIMD2(-1, 0)), (b.x1 - c.x, SIMD2(1, 0)), (c.y - b.z0, SIMD2(0, -1)), (b.z1 - c.y, SIMD2(0, 1))]
                                let m = opts.min { $0.0 < $1.0 }!
                                con = Contact(normal: m.1, depth: m.0 + r, point: c, kind: .building)
                            }
                        }
                    case 1:
                        let o = circles[k]
                        let dx = c.x - o.x, dz = c.y - o.z, d2 = dx * dx + dz * dz, rr = r + o.r
                        if d2 < rr * rr {
                            let d = max(d2.squareRoot(), 1e-4)
                            con = Contact(normal: SIMD2(dx / d, dz / d), depth: rr - d, point: SIMD2(o.x, o.z) + SIMD2(dx / d, dz / d) * o.r, kind: o.kind)
                        }
                    default:
                        let s = segs[k]
                        let sx = s.bx - s.ax, sz = s.bz - s.az, len2 = max(sx * sx + sz * sz, 1e-6)
                        let t = min(max(((c.x - s.ax) * sx + (c.y - s.az) * sz) / len2, 0), 1)
                        let qx = s.ax + sx * t, qz = s.az + sz * t
                        let dx = c.x - qx, dz = c.y - qz, d2 = dx * dx + dz * dz, rr = r + 0.3
                        if d2 < rr * rr {
                            let d = max(d2.squareRoot(), 1e-4)
                            con = Contact(normal: SIMD2(dx / d, dz / d), depth: rr - d, point: SIMD2(qx, qz), kind: .barrier)
                        }
                    }
                    if let con, con.depth > (best?.depth ?? 0) { best = con }
                }
            }
        }
        return best
    }
}

// MARK: - Ground

struct Ground { var y: Float; var grip: Float; var rollRes: Float; var road: Bool; var water: Bool }

final class WorldData {
    let meta: WorldMeta
    let terrain: Heightfield
    let roads: RoadIndex
    let collision: CollisionWorld
    var minX: Float { meta.bounds[0] }
    var minZ: Float { meta.bounds[1] }
    var maxX: Float { meta.bounds[2] }
    var maxZ: Float { meta.bounds[3] }

    init() throws {
        guard let mu = Res.url("world.json", "World"), let tu = Res.url("terrain.bin", "World"), let ru = Res.url("roads.bin", "World") else {
            throw NSError(domain: "Apex", code: 1, userInfo: [NSLocalizedDescriptionKey: "World data is missing from the app."])
        }
        meta = try JSONDecoder().decode(WorldMeta.self, from: Data(contentsOf: mu))
        terrain = Heightfield(data: try Data(contentsOf: tu))
        roads = RoadIndex(data: try Data(contentsOf: ru))
        collision = CollisionWorld(meta: meta)
    }

    func city(at x: Float, _ z: Float, margin: Float = 0) -> WorldMeta.City? {
        meta.cities.first { $0.contains(x, z, margin: margin) }
    }

    func ground(_ x: Float, _ z: Float) -> Ground {
        if let r = roads.query(x, z), r.dist <= r.halfWidth + 0.4 {
            return Ground(y: r.y + 0.05, grip: 1, rollRes: 13, road: true, water: false)
        }
        if let c = city(at: x, z) {
            return Ground(y: c.base + 0.18, grip: 0.95, rollRes: 16, road: true, water: false)
        }
        let t = terrain.height(x, z)
        if t < -0.4 { return Ground(y: t, grip: 0.3, rollRes: 900, road: false, water: true) }
        return Ground(y: t, grip: 0.74, rollRes: 170, road: false, water: false)
    }

    func groundY(_ x: Float, _ z: Float) -> Float { ground(x, z).y }
}
