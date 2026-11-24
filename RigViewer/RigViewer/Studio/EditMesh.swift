import SceneKit
import simd

/// Editable polygon mesh (n-gons, counter-clockwise from outside), the core of Studio.
struct EditMesh: Codable {
    var positions: [SIMD3<Float>] = []
    var faces: [[Int]] = []
    /// Optional per-face-corner UVs (empty array = generated box mapping for that face).
    var faceUVs: [[SIMD2<Float>]] = []
    var smooth = false
    /// Optional per-vertex colours (vertex paint). Same count as `positions` when present.
    var colors: [SIMD4<Float>]? = nil

    var vertexCount: Int { positions.count }
    var faceCount: Int { faces.count }
    var triangleCount: Int { faces.reduce(0) { $0 + max(0, $1.count - 2) } }

    mutating func normalizeUVs() {
        if faceUVs.count != faces.count { faceUVs = Array(repeating: [], count: faces.count) }
    }

    // MARK: - analysis

    func faceNormal(_ f: [Int]) -> SIMD3<Float> {
        // Newell's method: robust for any polygon.
        var n = SIMD3<Float>(repeating: 0)
        for i in 0..<f.count {
            let a = positions[f[i]], b = positions[f[(i + 1) % f.count]]
            n.x += (a.y - b.y) * (a.z + b.z)
            n.y += (a.z - b.z) * (a.x + b.x)
            n.z += (a.x - b.x) * (a.y + b.y)
        }
        let l = simd_length(n)
        return l > 1e-12 ? n / l : SIMD3(0, 1, 0)
    }

    func faceCenter(_ f: [Int]) -> SIMD3<Float> {
        var c = SIMD3<Float>(repeating: 0)
        for v in f { c += positions[v] }
        return c / Float(max(f.count, 1))
    }

    func vertexNormals() -> [SIMD3<Float>] {
        var n = [SIMD3<Float>](repeating: .zero, count: positions.count)
        for f in faces where f.count >= 3 {
            var fn = SIMD3<Float>(repeating: 0)
            for i in 0..<f.count {
                let a = positions[f[i]], b = positions[f[(i + 1) % f.count]]
                fn.x += (a.y - b.y) * (a.z + b.z); fn.y += (a.z - b.z) * (a.x + b.x); fn.z += (a.x - b.x) * (a.y + b.y)
            }
            for v in f { n[v] += fn }
        }
        return n.map { let l = simd_length($0); return l > 1e-12 ? $0 / l : SIMD3(0, 1, 0) }
    }

    struct Edge: Hashable { let a: Int, b: Int
        init(_ x: Int, _ y: Int) { a = min(x, y); b = max(x, y) }
    }

    func edges() -> [Edge] {
        var set = Set<Edge>(); var out: [Edge] = []
        for f in faces { for i in 0..<f.count { let e = Edge(f[i], f[(i + 1) % f.count]); if set.insert(e).inserted { out.append(e) } } }
        return out
    }

    func edgeFaces() -> [Edge: [Int]] {
        var d: [Edge: [Int]] = [:]
        for (fi, f) in faces.enumerated() { for i in 0..<f.count { d[Edge(f[i], f[(i + 1) % f.count]), default: []].append(fi) } }
        return d
    }

    func neighbors() -> [[Int]] {
        var sets = [Set<Int>](repeating: [], count: positions.count)
        for f in faces { for i in 0..<f.count { let a = f[i], b = f[(i + 1) % f.count]; sets[a].insert(b); sets[b].insert(a) } }
        return sets.map { Array($0) }
    }

    var bounds: (min: SIMD3<Float>, max: SIMD3<Float>) {
        guard let first = positions.first else { return (.zero, .zero) }
        var lo = first, hi = first
        for p in positions { lo = simd_min(lo, p); hi = simd_max(hi, p) }
        return (lo, hi)
    }

    // MARK: - SceneKit geometry

    /// Builds renderable geometry. `triangleFace[t]` maps each triangle back to its polygon (for tap selection).
    func makeGeometry() -> (geometry: SCNGeometry, triangleFace: [Int32]) {
        var pos: [Float] = [], nrm: [Float] = [], uv: [Float] = []
        var idx: [UInt32] = []; var triFace: [Int32] = []
        let vn = smooth ? vertexNormals() : []
        let vcol: [SIMD4<Float>]? = (colors?.count == positions.count) ? colors : nil
        var col: [Float] = []
        pos.reserveCapacity(faces.count * 12); nrm.reserveCapacity(faces.count * 12); uv.reserveCapacity(faces.count * 8)
        for (fi, f) in faces.enumerated() where f.count >= 3 {
            let n = faceNormal(f)
            let base = UInt32(pos.count / 3)
            let uvs = fi < faceUVs.count && faceUVs[fi].count == f.count ? faceUVs[fi] : nil
            let a = simd_abs(n)
            for (ci, v) in f.enumerated() {
                let p = positions[v]
                pos += [p.x, p.y, p.z]
                let nn = smooth ? vn[v] : n
                nrm += [nn.x, nn.y, nn.z]
                if let vcol { let c = vcol[v]; col += [c.x, c.y, c.z, c.w] }
                if let uvs { uv += [uvs[ci].x, uvs[ci].y] }
                else if a.x >= a.y && a.x >= a.z { uv += [p.z, -p.y] }
                else if a.y >= a.z { uv += [p.x, -p.z] }
                else { uv += [p.x, -p.y] }
            }
            for i in 1..<(f.count - 1) {
                idx += [base, base + UInt32(i), base + UInt32(i + 1)]
                triFace.append(Int32(fi))
            }
        }
        let count = pos.count / 3
        let ps = SCNGeometrySource(data: pos.withUnsafeBufferPointer { Data(buffer: $0) }, semantic: .vertex, vectorCount: count, usesFloatComponents: true, componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0, dataStride: 12)
        let ns = SCNGeometrySource(data: nrm.withUnsafeBufferPointer { Data(buffer: $0) }, semantic: .normal, vectorCount: count, usesFloatComponents: true, componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0, dataStride: 12)
        let ts = SCNGeometrySource(data: uv.withUnsafeBufferPointer { Data(buffer: $0) }, semantic: .texcoord, vectorCount: count, usesFloatComponents: true, componentsPerVector: 2, bytesPerComponent: 4, dataOffset: 0, dataStride: 8)
        let el = SCNGeometryElement(data: idx.withUnsafeBufferPointer { Data(buffer: $0) }, primitiveType: .triangles, primitiveCount: idx.count / 3, bytesPerIndex: 4)
        var sources = [ps, ns, ts]
        if vcol != nil, col.count == count * 4 {
            sources.append(SCNGeometrySource(data: col.withUnsafeBufferPointer { Data(buffer: $0) }, semantic: .color, vectorCount: count, usesFloatComponents: true, componentsPerVector: 4, bytesPerComponent: 4, dataOffset: 0, dataStride: 16))
        }
        return (SCNGeometry(sources: sources, elements: [el]), triFace)
    }

    // MARK: - primitives

    static func cube(size s: Float = 1) -> EditMesh {
        let h = s / 2
        let p: [SIMD3<Float>] = [[-h, -h, -h], [h, -h, -h], [h, h, -h], [-h, h, -h], [-h, -h, h], [h, -h, h], [h, h, h], [-h, h, h]]
        return EditMesh(positions: p, faces: [[4, 5, 6, 7], [1, 0, 3, 2], [5, 1, 2, 6], [0, 4, 7, 3], [7, 6, 2, 3], [0, 1, 5, 4]])
    }

    static func plane(size s: Float = 1, divisions n: Int = 1) -> EditMesh {
        var m = EditMesh()
        for z in 0...n { for x in 0...n { m.positions.append([(Float(x) / Float(n) - 0.5) * s, 0, (Float(z) / Float(n) - 0.5) * s]) } }
        for z in 0..<n { for x in 0..<n {
            let a = z * (n + 1) + x
            m.faces.append([a + n + 1, a + n + 2, a + 1, a])
        } }
        return m
    }

    static func uvSphere(radius r: Float = 0.5, segments seg: Int = 32, rings: Int = 16) -> EditMesh {
        var m = EditMesh(); m.smooth = true
        m.positions.append([0, r, 0])
        for i in 1..<rings {
            let t = Float.pi * Float(i) / Float(rings)
            for s in 0..<seg {
                let ph = 2 * Float.pi * Float(s) / Float(seg)
                m.positions.append([r * sinf(t) * cosf(ph), r * cosf(t), r * sinf(t) * sinf(ph)])
            }
        }
        m.positions.append([0, -r, 0]); let b = m.positions.count - 1
        func idx(_ i: Int, _ s: Int) -> Int { 1 + (i - 1) * seg + (s % seg) }
        for s in 0..<seg { m.faces.append([0, idx(1, s + 1), idx(1, s)]) }
        for i in 1..<(rings - 1) { for s in 0..<seg { m.faces.append([idx(i, s), idx(i, s + 1), idx(i + 1, s + 1), idx(i + 1, s)]) } }
        for s in 0..<seg { m.faces.append([b, idx(rings - 1, s), idx(rings - 1, s + 1)]) }
        return m
    }

    static func cylinder(radius r: Float = 0.5, height h: Float = 1, segments seg: Int = 32) -> EditMesh {
        var m = EditMesh()
        for y in [-h / 2, h / 2] { for s in 0..<seg { let ph = 2 * Float.pi * Float(s) / Float(seg); m.positions.append([r * cosf(ph), y, r * sinf(ph)]) } }
        for s in 0..<seg { let n = (s + 1) % seg; m.faces.append([s, seg + s, seg + n, n]) }
        m.faces.append(Array((0..<seg).map { seg + $0 }.reversed()))
        m.faces.append(Array(0..<seg))
        return m
    }

    static func cone(radius r: Float = 0.5, height h: Float = 1, segments seg: Int = 32) -> EditMesh {
        var m = EditMesh()
        for s in 0..<seg { let ph = 2 * Float.pi * Float(s) / Float(seg); m.positions.append([r * cosf(ph), -h / 2, r * sinf(ph)]) }
        m.positions.append([0, h / 2, 0])
        for s in 0..<seg { m.faces.append([s, seg, (s + 1) % seg]) }
        m.faces.append(Array(0..<seg))
        return m
    }

    static func torus(major R: Float = 0.4, minor r: Float = 0.15, segments seg: Int = 32, sides: Int = 16) -> EditMesh {
        var m = EditMesh(); m.smooth = true
        for i in 0..<seg {
            let u = 2 * Float.pi * Float(i) / Float(seg)
            for j in 0..<sides {
                let v = 2 * Float.pi * Float(j) / Float(sides)
                m.positions.append([(R + r * cosf(v)) * cosf(u), r * sinf(v), (R + r * cosf(v)) * sinf(u)])
            }
        }
        for i in 0..<seg { for j in 0..<sides {
            let a = i * sides + j, b = ((i + 1) % seg) * sides + j, c = ((i + 1) % seg) * sides + (j + 1) % sides, d = i * sides + (j + 1) % sides
            m.faces.append([a, d, c, b])
        } }
        return m
    }

    static func icosphere(radius r: Float = 0.5, subdivisions: Int = 2) -> EditMesh {
        let t = (1 + sqrtf(5)) / 2
        var p: [SIMD3<Float>] = [[-1, t, 0], [1, t, 0], [-1, -t, 0], [1, -t, 0], [0, -1, t], [0, 1, t], [0, -1, -t], [0, 1, -t], [t, 0, -1], [t, 0, 1], [-t, 0, -1], [-t, 0, 1]]
        var f: [[Int]] = [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
                          [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]
        p = p.map { simd_normalize($0) * r }
        for _ in 0..<subdivisions {
            var cache: [Edge: Int] = [:]; var nf: [[Int]] = []
            func mid(_ a: Int, _ b: Int) -> Int {
                let e = Edge(a, b)
                if let i = cache[e] { return i }
                p.append(simd_normalize((p[a] + p[b]) / 2) * r); cache[e] = p.count - 1; return p.count - 1
            }
            for tri in f {
                let a = mid(tri[0], tri[1]), b = mid(tri[1], tri[2]), c = mid(tri[2], tri[0])
                nf += [[tri[0], a, c], [tri[1], b, a], [tri[2], c, b], [a, b, c]]
            }
            f = nf
        }
        // Icosahedron table above winds clockwise in SceneKit's convention, so flip.
        var m = EditMesh(positions: p, faces: f.map { Array($0.reversed()) }); m.smooth = true
        if m.signedVolume() < 0 { m.faces = m.faces.map { Array($0.reversed()) } }
        return m
    }

    /// A smooth, evenly-dense ball that's ideal for sculpting.
    static func clayBall(radius r: Float = 0.5, level: Int = 5) -> EditMesh {
        var m = cube(size: 1)
        for _ in 0..<level { m = m.catmullClark() }
        m.positions = m.positions.map { simd_normalize($0) * r }
        m.smooth = true
        return m
    }

    func signedVolume() -> Float {
        var v: Float = 0
        for f in faces where f.count >= 3 {
            let a = positions[f[0]]
            for i in 1..<(f.count - 1) { v += simd_dot(a, simd_cross(positions[f[i]], positions[f[i + 1]])) / 6 }
        }
        return v
    }

    // MARK: - topology operations

    /// Extrudes connected regions of the selected faces. New faces stay selected; returns their indices.
    mutating func extrude(faces sel: Set<Int>, distance: Float) -> Set<Int> {
        guard !sel.isEmpty else { return [] }
        normalizeUVs()
        var count: [Edge: Int] = [:]
        for fi in sel { let f = faces[fi]; for i in 0..<f.count { count[Edge(f[i], f[(i + 1) % f.count]), default: 0] += 1 } }
        var map: [Int: Int] = [:]
        var avgN = SIMD3<Float>(repeating: 0)
        for fi in sel { avgN += faceNormal(faces[fi]); for v in faces[fi] where map[v] == nil { map[v] = positions.count; positions.append(positions[v]) } }
        avgN = simd_length(avgN) > 1e-6 ? simd_normalize(avgN) : SIMD3(0, 1, 0)
        var side: [[Int]] = []
        for fi in sel {
            let f = faces[fi]
            for i in 0..<f.count {
                let a = f[i], b = f[(i + 1) % f.count]
                if count[Edge(a, b)] == 1 { side.append([a, b, map[b]!, map[a]!]) }
            }
            faces[fi] = f.map { map[$0]! }
        }
        // Individual normals for single faces, averaged for regions.
        for (_, nv) in map { positions[nv] += avgN * distance }
        faces += side; faceUVs += Array(repeating: [], count: side.count)
        return sel
    }

    /// Insets each selected face; returns the new inner faces.
    mutating func inset(faces sel: Set<Int>, amount t: Float) -> Set<Int> {
        normalizeUVs()
        var newFaces: [[Int]] = []; var newUVs: [[SIMD2<Float>]] = []
        for fi in sel.sorted() {
            let f = faces[fi]; let n = f.count
            let c = faceCenter(f)
            let uvs = faceUVs[fi]
            var inner: [Int] = []
            for v in f { inner.append(positions.count); positions.append(positions[v] + (c - positions[v]) * t) }
            var innerUV: [SIMD2<Float>] = []
            if uvs.count == n {
                let uc = uvs.reduce(SIMD2<Float>(0, 0), +) / Float(n)
                innerUV = uvs.map { $0 + (uc - $0) * t }
            }
            for i in 0..<n {
                let j = (i + 1) % n
                newFaces.append([f[i], f[j], inner[j], inner[i]])
                newUVs.append(innerUV.isEmpty ? [] : [uvs[i], uvs[j], innerUV[j], innerUV[i]])
            }
            faces[fi] = inner; faceUVs[fi] = innerUV
        }
        faces += newFaces; faceUVs += newUVs
        return sel
    }

    /// Bevel for faces: a small inset plus a short extrusion, rounding off the selected faces' edges.
    mutating func bevel(faces sel: Set<Int>, width: Float) -> Set<Int> {
        var s = inset(faces: sel, amount: 0.18)
        s = extrude(faces: s, distance: width)
        return s
    }

    /// Catmull–Clark subdivision of the whole mesh (UVs fall back to generated mapping).
    func catmullClark() -> EditMesh {
        let ef = edgeFaces()
        let fp = faces.map { faceCenter($0) }
        var vf = [[Int]](repeating: [], count: positions.count)
        var ve = [[Edge]](repeating: [], count: positions.count)
        for (fi, f) in faces.enumerated() { for v in f { vf[v].append(fi) } }
        for e in ef.keys { ve[e.a].append(e); ve[e.b].append(e) }
        var out = EditMesh(); out.smooth = smooth
        out.positions.reserveCapacity(positions.count + faces.count + ef.count)
        for v in 0..<positions.count {
            let n = vf[v].count
            let boundary = ve[v].filter { (ef[$0]?.count ?? 0) == 1 }
            if !boundary.isEmpty {
                if boundary.count == 2 {
                    let m0 = (positions[boundary[0].a] + positions[boundary[0].b]) / 2
                    let m1 = (positions[boundary[1].a] + positions[boundary[1].b]) / 2
                    out.positions.append((m0 + m1) / 4 + positions[v] / 2)
                } else { out.positions.append(positions[v]) }
            } else if n > 0 {
                var F = SIMD3<Float>(repeating: 0); for f in vf[v] { F += fp[f] }; F /= Float(n)
                var R = SIMD3<Float>(repeating: 0); for e in ve[v] { R += (positions[e.a] + positions[e.b]) / 2 }; R /= Float(max(ve[v].count, 1))
                out.positions.append((F + 2 * R + Float(n - 3) * positions[v]) / Float(n))
            } else { out.positions.append(positions[v]) }
        }
        let fBase = out.positions.count
        out.positions += fp
        var eIndex: [Edge: Int] = [:]
        for (e, fs) in ef {
            eIndex[e] = out.positions.count
            if fs.count == 2 { out.positions.append((positions[e.a] + positions[e.b] + fp[fs[0]] + fp[fs[1]]) / 4) }
            else { out.positions.append((positions[e.a] + positions[e.b]) / 2) }
        }
        for (fi, f) in faces.enumerated() {
            let n = f.count
            for i in 0..<n {
                let v = f[i], nx = f[(i + 1) % n], pv = f[(i + n - 1) % n]
                out.faces.append([v, eIndex[Edge(v, nx)]!, fBase + fi, eIndex[Edge(pv, v)]!])
            }
        }
        if let c = colors, c.count == positions.count {
            var oc = c
            for f in faces { var s = SIMD4<Float>(repeating: 0); for v in f { s += c[v] }; oc.append(s / Float(max(f.count, 1))) }
            var ec = [SIMD4<Float>](repeating: SIMD4(1, 1, 1, 1), count: eIndex.count)
            for (e, i) in eIndex { ec[i - fBase - faces.count] = (c[e.a] + c[e.b]) / 2 }
            out.colors = oc + ec
        }
        return out
    }

    /// Splits every face into quads/triangles at edge midpoints without smoothing.
    func subdivideFlat() -> EditMesh {
        var out = EditMesh(positions: positions, faces: []); out.smooth = smooth
        var eIndex: [Edge: Int] = [:]
        func mid(_ a: Int, _ b: Int) -> Int {
            let e = Edge(a, b); if let i = eIndex[e] { return i }
            out.positions.append((positions[a] + positions[b]) / 2); eIndex[e] = out.positions.count - 1; return out.positions.count - 1
        }
        for f in faces {
            let n = f.count
            if n == 3 {
                let a = mid(f[0], f[1]), b = mid(f[1], f[2]), c = mid(f[2], f[0])
                out.faces += [[f[0], a, c], [f[1], b, a], [f[2], c, b], [a, b, c]]
            } else {
                out.positions.append(faceCenter(f)); let c = out.positions.count - 1
                for i in 0..<n { out.faces.append([f[i], mid(f[i], f[(i + 1) % n]), c, mid(f[(i + n - 1) % n], f[i])]) }
            }
        }
        return out
    }

    /// Laplacian smoothing of the given vertices (or all when empty).
    mutating func smoothVertices(_ verts: Set<Int>, factor: Float = 0.5, iterations: Int = 2) {
        let nb = neighbors()
        let targets = verts.isEmpty ? Set(0..<positions.count) : verts
        let ef = edgeFaces()
        var boundary = Set<Int>()
        for (e, fs) in ef where fs.count == 1 { boundary.insert(e.a); boundary.insert(e.b) }
        for _ in 0..<iterations {
            let old = positions
            for v in targets where !nb[v].isEmpty && !boundary.contains(v) {
                var avg = SIMD3<Float>(repeating: 0); for n in nb[v] { avg += old[n] }; avg /= Float(nb[v].count)
                positions[v] = old[v] + (avg - old[v]) * factor
            }
        }
    }

    /// Removes faces; vertices that are no longer used are dropped too.
    mutating func deleteFaces(_ sel: Set<Int>) {
        normalizeUVs()
        var keepF: [[Int]] = [], keepUV: [[SIMD2<Float>]] = []
        for (i, f) in faces.enumerated() where !sel.contains(i) { keepF.append(f); keepUV.append(faceUVs[i]) }
        faces = keepF; faceUVs = keepUV
        removeUnusedVertices()
    }

    mutating func deleteVertices(_ verts: Set<Int>) {
        let sel = Set(faces.indices.filter { faces[$0].contains(where: verts.contains) })
        deleteFaces(sel)
    }

    mutating func removeUnusedVertices() {
        var used = [Bool](repeating: false, count: positions.count)
        for f in faces { for v in f { used[v] = true } }
        var remap = [Int](repeating: -1, count: positions.count); var np: [SIMD3<Float>] = []
        let oldColors = colors?.count == positions.count ? colors : nil
        var nc: [SIMD4<Float>] = []
        for (i, u) in used.enumerated() where u { remap[i] = np.count; np.append(positions[i]); if let oldColors { nc.append(oldColors[i]) } }
        positions = np
        colors = oldColors == nil ? nil : nc
        faces = faces.map { $0.map { remap[$0] } }
    }

    /// Collapses the vertices to their centre.
    mutating func merge(_ verts: Set<Int>) {
        guard verts.count > 1, let keep = verts.min() else { return }
        normalizeUVs()
        var c = SIMD3<Float>(repeating: 0); for v in verts { c += positions[v] }; c /= Float(verts.count)
        positions[keep] = c
        var nf: [[Int]] = [], nuv: [[SIMD2<Float>]] = []
        for (fi, f) in faces.enumerated() {
            var g: [Int] = []; var guv: [SIMD2<Float>] = []
            let uvs = faceUVs[fi]
            for (ci, v) in f.enumerated() {
                let m = verts.contains(v) ? keep : v
                if g.last != m { g.append(m); if uvs.count == f.count { guv.append(uvs[ci]) } }
            }
            if g.count > 1, g.first == g.last { g.removeLast(); if !guv.isEmpty { guv.removeLast() } }
            if Set(g).count >= 3 { nf.append(g); nuv.append(guv.count == g.count ? guv : []) }
        }
        faces = nf; faceUVs = nuv
        removeUnusedVertices()
    }

    /// Merges vertices closer than `distance` (cleans up after mirroring or imports).
    mutating func weld(distance: Float = 1e-4) {
        var map = [Int](repeating: -1, count: positions.count)
        var grid: [SIMD3<Int32>: [Int]] = [:]
        let inv = 1 / max(distance, 1e-7)
        for (i, p) in positions.enumerated() {
            let k = SIMD3<Int32>(Int32((p.x * inv).rounded()), Int32((p.y * inv).rounded()), Int32((p.z * inv).rounded()))
            if let j = grid[k]?.first { map[i] = j } else { grid[k] = [i]; map[i] = i }
        }
        faces = faces.compactMap { f in
            var g: [Int] = []
            for v in f { let m = map[v]; if g.last != m { g.append(m) } }
            if g.count > 1, g.first == g.last { g.removeLast() }
            return Set(g).count >= 3 ? g : nil
        }
        faceUVs = []
        removeUnusedVertices()
    }

    mutating func flip(_ sel: Set<Int>) {
        normalizeUVs()
        for fi in (sel.isEmpty ? Set(faces.indices) : sel) { faces[fi].reverse(); faceUVs[fi].reverse() }
    }

    /// Mirrors across X (local) and welds the seam, for symmetric modelling.
    mutating func mirrorX() {
        let n = positions.count
        if let c = colors, c.count == n { colors = c + c }
        positions += positions.map { SIMD3(-$0.x, $0.y, $0.z) }
        faces += faces.map { f in Array(f.map { $0 + n }.reversed()) }
        weld(distance: max(simd_length(bounds.max - bounds.min) * 1e-4, 1e-5))
    }

    mutating func triangulate() {
        normalizeUVs()
        var nf: [[Int]] = [], nuv: [[SIMD2<Float>]] = []
        for (fi, f) in faces.enumerated() {
            let uvs = faceUVs[fi]
            if f.count <= 3 { nf.append(f); nuv.append(uvs); continue }
            for i in 1..<(f.count - 1) {
                nf.append([f[0], f[i], f[i + 1]])
                nuv.append(uvs.count == f.count ? [uvs[0], uvs[i], uvs[i + 1]] : [])
            }
        }
        faces = nf; faceUVs = nuv
    }

    /// Creates a face from the selected vertices, ordered around their centre and facing outward.
    mutating func makeFace(_ verts: [Int]) -> Int? {
        guard verts.count >= 3 else { return nil }
        normalizeUVs()
        let pts = verts.map { positions[$0] }
        let c = pts.reduce(SIMD3<Float>(repeating: 0), +) / Float(pts.count)
        // Best-fit normal from the polygon fan.
        var n = SIMD3<Float>(repeating: 0)
        for i in 0..<pts.count { n += simd_cross(pts[i] - c, pts[(i + 1) % pts.count] - c) }
        if simd_length(n) < 1e-9 { n = SIMD3(0, 1, 0) } else { n = simd_normalize(n) }
        let u = simd_normalize(simd_length(simd_cross(n, [0, 1, 0])) > 0.1 ? simd_cross(n, [0, 1, 0]) : simd_cross(n, [1, 0, 0]))
        let w = simd_cross(n, u)
        var ordered = verts.sorted { atan2(simd_dot(positions[$0] - c, w), simd_dot(positions[$0] - c, u)) < atan2(simd_dot(positions[$1] - c, w), simd_dot(positions[$1] - c, u)) }
        // Face away from the mesh centre.
        let meshC = (bounds.min + bounds.max) / 2
        faces.append(ordered); faceUVs.append([])
        if simd_dot(faceNormal(ordered), c - meshC) < 0 { ordered.reverse(); faces[faces.count - 1] = ordered }
        return faces.count - 1
    }

    /// Bakes a transform into the vertices.
    mutating func apply(_ m: simd_float4x4) {
        positions = positions.map { let p = m * SIMD4($0, 1); return SIMD3(p.x, p.y, p.z) }
        if simd_determinant(m) < 0 { faces = faces.map { Array($0.reversed()) }; faceUVs = faceUVs.map { Array($0.reversed()) } }
    }

    /// Appends another mesh (already in this mesh's space).
    mutating func append(_ o: EditMesh) {
        normalizeUVs()
        let n = positions.count
        if colors != nil || o.colors != nil {
            let a = colors?.count == n ? colors! : [SIMD4<Float>](repeating: SIMD4(1, 1, 1, 1), count: n)
            let b = o.colors?.count == o.positions.count ? o.colors! : [SIMD4<Float>](repeating: SIMD4(1, 1, 1, 1), count: o.positions.count)
            colors = a + b
        }
        positions += o.positions
        faces += o.faces.map { $0.map { $0 + n } }
        var ouv = o.faceUVs; if ouv.count != o.faces.count { ouv = Array(repeating: [], count: o.faces.count) }
        faceUVs += ouv
    }

    /// Builds an editable mesh from SceneKit geometry (one element), welding split vertices.
    static func from(geometry g: SCNGeometry, element ei: Int) -> EditMesh? {
        guard let vs = g.sources(for: .vertex).first, ei < g.elements.count else { return nil }
        let pos = readVectors(vs, 3)
        let uvSrc = g.sources(for: .texcoord).first.map { readVectors($0, 2) }
        let e = g.elements[ei]
        let idx = readIndices(e)
        var tris: [Int] = []
        switch e.primitiveType {
        case .triangles: tris = idx
        case .triangleStrip:
            if idx.count >= 3 { for i in 0..<(idx.count - 2) { tris += i % 2 == 0 ? [idx[i], idx[i + 1], idx[i + 2]] : [idx[i + 1], idx[i], idx[i + 2]] } }
        default: return nil
        }
        var m = EditMesh()
        m.positions = pos.map { SIMD3($0[0], $0[1], $0[2]) }
        var i = 0
        while i + 2 < tris.count {
            let f = [tris[i], tris[i + 1], tris[i + 2]]
            if Set(f).count == 3, f.allSatisfy({ $0 < m.positions.count }) {
                m.faces.append(f)
                if let uv = uvSrc, f.allSatisfy({ $0 < uv.count }) { m.faceUVs.append(f.map { SIMD2(uv[$0][0], uv[$0][1]) }) } else { m.faceUVs.append([]) }
            }
            i += 3
        }
        // Weld duplicated vertices (split for normals/UVs) so editing keeps the surface closed; UVs are kept per corner.
        let uvs = m.faceUVs
        var map = [Int](repeating: -1, count: m.positions.count); var grid: [SIMD3<Int32>: Int] = [:]
        let size = simd_length(m.bounds.max - m.bounds.min); let inv = 1 / max(size * 1e-5, 1e-7)
        for (k, p) in m.positions.enumerated() {
            let key = SIMD3<Int32>(Int32((p.x * inv).rounded()), Int32((p.y * inv).rounded()), Int32((p.z * inv).rounded()))
            if let j = grid[key] { map[k] = j } else { grid[key] = k; map[k] = k }
        }
        m.faces = m.faces.map { $0.map { map[$0] } }
        m.faceUVs = uvs
        m.removeUnusedVertices()
        m.smooth = true
        return m
    }

    static func readVectors(_ s: SCNGeometrySource, _ comps: Int) -> [[Float]] {
        var out: [[Float]] = []; out.reserveCapacity(s.vectorCount)
        let n = min(comps, s.componentsPerVector)
        s.data.withUnsafeBytes { raw in
            for i in 0..<s.vectorCount {
                var v = [Float](repeating: 0, count: comps)
                for c in 0..<n {
                    let o = s.dataOffset + i * s.dataStride + c * s.bytesPerComponent
                    guard o + s.bytesPerComponent <= raw.count else { continue }
                    if s.usesFloatComponents {
                        v[c] = s.bytesPerComponent == 8 ? Float(raw.loadUnaligned(fromByteOffset: o, as: Double.self)) : raw.loadUnaligned(fromByteOffset: o, as: Float.self)
                    } else {
                        v[c] = s.bytesPerComponent == 1 ? Float(raw.load(fromByteOffset: o, as: UInt8.self)) : s.bytesPerComponent == 2 ? Float(raw.loadUnaligned(fromByteOffset: o, as: UInt16.self)) : Float(raw.loadUnaligned(fromByteOffset: o, as: UInt32.self))
                    }
                }
                out.append(v)
            }
        }
        return out
    }

    static func readIndices(_ e: SCNGeometryElement) -> [Int] {
        var out: [Int] = []
        let b = e.bytesPerIndex
        let count = e.data.count / max(b, 1)
        out.reserveCapacity(count)
        e.data.withUnsafeBytes { raw in
            for i in 0..<count {
                switch b {
                case 1: out.append(Int(raw.load(fromByteOffset: i, as: UInt8.self)))
                case 2: out.append(Int(raw.loadUnaligned(fromByteOffset: i * 2, as: UInt16.self)))
                default: out.append(Int(raw.loadUnaligned(fromByteOffset: i * 4, as: UInt32.self)))
                }
            }
        }
        return out
    }
}

// MARK: - Sculpting

enum SculptBrush: String, CaseIterable, Identifiable {
    case draw = "Draw", clay = "Clay", smooth = "Smooth", inflate = "Inflate", grab = "Grab", flatten = "Flatten", pinch = "Pinch"
    case crease = "Crease", layer = "Layer", scrape = "Scrape", blob = "Blob"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .draw: return "paintbrush.pointed.fill"; case .clay: return "hand.point.up.fill"; case .smooth: return "drop.fill"
        case .inflate: return "circle.circle.fill"; case .grab: return "hand.draw.fill"; case .flatten: return "rectangle.compress.vertical"
        case .pinch: return "arrow.down.right.and.arrow.up.left"
        case .crease: return "chevron.compact.down"; case .layer: return "square.3.layers.3d.top.filled"
        case .scrape: return "eraser.line.dashed"; case .blob: return "circle.hexagongrid.circle"
        }
    }
}

extension EditMesh {
    /// Applies one dab of a brush at `center` (mesh space). `normal` is the surface normal at the hit.
    mutating func sculpt(_ brush: SculptBrush, at center: SIMD3<Float>, normal: SIMD3<Float>, radius r: Float, strength s: Float,
                         invert: Bool, neighbors nb: [[Int]], vertexNormals vn: [SIMD3<Float>]) {
        let r2 = r * r
        let sign: Float = invert ? -1 : 1
        var affected: [(Int, Float)] = []
        for i in 0..<positions.count {
            let d2 = simd_length_squared(positions[i] - center)
            if d2 < r2 {
                let t = sqrtf(d2) / r
                let f = 1 - t * t * (3 - 2 * t)          // smooth falloff
                affected.append((i, f))
            }
        }
        guard !affected.isEmpty else { return }
        // Average normal and plane of the brush area.
        var areaN = SIMD3<Float>(repeating: 0), areaC = SIMD3<Float>(repeating: 0), wsum: Float = 0
        for (i, f) in affected { areaN += vn[i] * f; areaC += positions[i] * f; wsum += f }
        areaN = simd_length(areaN) > 1e-6 ? simd_normalize(areaN) : normal
        areaC /= max(wsum, 1e-6)
        let old = positions
        for (i, f) in affected {
            let k = f * s
            switch brush {
            case .draw:
                positions[i] += areaN * (k * r * 0.12 * sign)
            case .clay:
                // Builds up toward a plane slightly above the surface, like adding clay.
                let plane = areaC + areaN * (r * 0.15 * sign)
                let dist = simd_dot(plane - old[i], areaN)
                if dist * sign > 0 { positions[i] += areaN * dist * k * 0.5 }
            case .inflate:
                positions[i] += vn[i] * (k * r * 0.1 * sign)
            case .smooth:
                guard !nb[i].isEmpty else { continue }
                var avg = SIMD3<Float>(repeating: 0); for n in nb[i] { avg += old[n] }; avg /= Float(nb[i].count)
                positions[i] = old[i] + (avg - old[i]) * min(1, k * 1.2)
            case .flatten:
                let dist = simd_dot(old[i] - areaC, areaN)
                positions[i] -= areaN * dist * k * 0.6 * sign
            case .pinch:
                let toward = center - old[i]
                let tangential = toward - areaN * simd_dot(toward, areaN)
                positions[i] += tangential * (k * 0.25 * sign)
            case .crease:
                let toward = center - old[i]
                let tangential = toward - areaN * simd_dot(toward, areaN)
                positions[i] += tangential * (k * 0.3) - areaN * (k * r * 0.1 * sign)
            case .layer:
                let plane = areaC + areaN * (r * 0.06 * sign)
                let dist = simd_dot(plane - old[i], areaN)
                if dist * sign > 0 { positions[i] += areaN * dist * min(1, k * 1.5) }
            case .scrape:
                let dist = simd_dot(old[i] - areaC, areaN)
                if dist * sign > 0 { positions[i] -= areaN * dist * k * 0.8 }
            case .blob:
                positions[i] += (vn[i] * 0.6 + areaN * 0.4) * (k * r * 0.12 * sign)
            case .grab:
                break   // handled by `grab(…)`
            }
        }
    }

    /// Grab brush: moves captured vertices by `delta` scaled by their weights, from their positions at stroke start.
    mutating func grab(captured: [(Int, Float)], start: [SIMD3<Float>], delta: SIMD3<Float>) {
        for (k, (i, w)) in captured.enumerated() { positions[i] = start[k] + delta * w }
    }

    func verticesNear(_ center: SIMD3<Float>, radius r: Float) -> [(Int, Float)] {
        var out: [(Int, Float)] = []
        for (i, p) in positions.enumerated() {
            let d = simd_length(p - center)
            if d < r { let t = d / r; out.append((i, 1 - t * t * (3 - 2 * t))) }
        }
        return out
    }
}
