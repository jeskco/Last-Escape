import Foundation
import simd

/// Non-destructive modifiers, evaluated top to bottom like Blender's modifier stack.
enum ModifierKind: String, Codable, CaseIterable, Identifiable {
    case mirror, subdivision, array, solidify, smooth, displace, decimate, triangulate, weld, wireframe, screw, twist, taper, bend, remesh
    var id: String { rawValue }
    var title: String {
        switch self {
        case .mirror: return "Mirror"; case .subdivision: return "Subdivision Surface"; case .array: return "Array"; case .solidify: return "Solidify"
        case .smooth: return "Smooth"; case .displace: return "Displace"; case .decimate: return "Decimate"; case .triangulate: return "Triangulate"
        case .weld: return "Weld"; case .wireframe: return "Wireframe"; case .screw: return "Screw (Lathe)"; case .twist: return "Twist"
        case .taper: return "Taper"; case .bend: return "Bend"; case .remesh: return "Remesh"
        }
    }
    var icon: String {
        switch self {
        case .mirror: return "arrow.left.and.right.righttriangle.left.righttriangle.right"; case .subdivision: return "circle.grid.cross"
        case .array: return "square.grid.3x1.below.line.grid.1x2"; case .solidify: return "square.stack.3d.down.forward"
        case .smooth: return "drop"; case .displace: return "waveform.path"; case .decimate: return "triangle.lefthalf.filled"
        case .triangulate: return "triangle"; case .weld: return "arrow.triangle.merge"; case .wireframe: return "square.grid.3x3"
        case .screw: return "arrow.triangle.2.circlepath"; case .twist: return "tornado"; case .taper: return "trapezoid.and.line.vertical"
        case .bend: return "point.topleft.down.to.point.bottomright.curvepath"; case .remesh: return "cube.transparent"
        }
    }
    var group: String {
        switch self {
        case .mirror, .array, .solidify, .wireframe, .screw, .subdivision, .remesh, .decimate, .triangulate, .weld: return "Generate"
        case .smooth, .displace, .twist, .taper, .bend: return "Deform"
        }
    }
    /// Defaults per kind.
    func make() -> ModifierRecord {
        var r = ModifierRecord(kind: self)
        switch self {
        case .mirror: r.axis = 0; r.flag = true
        case .subdivision: r.count = 2
        case .array: r.count = 3; r.offset = [1.1, 0, 0]; r.flag = false
        case .solidify: r.amount = 0.05; r.flag = true
        case .smooth: r.count = 5; r.amount = 0.5
        case .displace: r.amount = 0.08; r.count = 3
        case .decimate: r.amount = 0.5
        case .triangulate: break
        case .weld: r.amount = 0.001
        case .wireframe: r.amount = 0.02
        case .screw: r.axis = 1; r.count = 32; r.amount = 360
        case .twist: r.axis = 1; r.amount = 90
        case .taper: r.axis = 1; r.amount = 0.5
        case .bend: r.axis = 1; r.amount = 45
        case .remesh: r.count = 64; r.flag = true
        }
        return r
    }
}

struct ModifierRecord: Codable, Identifiable, Equatable {
    var id = UUID()
    var kind: ModifierKind
    var enabled = true
    var axis = 0
    var count = 2
    var amount: Float = 0.5
    var offset = SIMD3<Float>(1.1, 0, 0)
    var flag = true
}

extension EditMesh {
    /// Runs a whole stack. Stops early if the result would get too heavy for a phone.
    func evaluated(_ stack: [ModifierRecord], limit: Int = 400_000) -> EditMesh {
        var m = self
        for r in stack where r.enabled {
            let next = m.applying(r)
            if next.triangleCount > limit { break }
            m = next
        }
        return m
    }

    func applying(_ r: ModifierRecord) -> EditMesh {
        var m = self
        let size = max(simd_reduce_max(bounds.max - bounds.min), 1e-4)
        switch r.kind {
        case .mirror:
            m.mirror(axis: max(0, min(2, r.axis)), merge: r.flag)
        case .subdivision:
            for _ in 0..<max(0, min(r.count, 4)) { if m.faceCount * 4 > 300_000 { break }; m = m.catmullClark() }
            m.smooth = true
        case .array:
            let base = m
            let step = (bounds.max - bounds.min) * r.offset
            m = EditMesh(); m.smooth = base.smooth
            for i in 0..<max(1, min(r.count, 64)) {
                var c = base
                c.positions = c.positions.map { $0 + step * Float(i) }
                m.append(c)
            }
            if r.flag { m.weld(distance: size * 1e-3) }
        case .solidify:
            m = solidified(thickness: r.amount * size, even: r.flag)
        case .smooth:
            m.smoothVertices([], factor: max(0, min(1, r.amount)), iterations: max(1, min(r.count, 50)))
        case .displace:
            let vn = vertexNormals()
            let freq = Float(max(1, r.count)) / size
            m.positions = positions.enumerated().map { i, p in p + vn[i] * (Noise.fbm(p * freq) - 0.5) * 2 * r.amount * size }
        case .decimate:
            m = decimated(ratio: max(0.02, min(1, r.amount)))
        case .triangulate:
            m.triangulate()
        case .weld:
            m.weld(distance: max(1e-6, r.amount * size))
        case .wireframe:
            m = wireframed(thickness: max(1e-4, r.amount * size))
        case .screw:
            m = screwed(axis: max(0, min(2, r.axis)), steps: max(3, min(r.count, 256)), degrees: r.amount)
        case .twist, .taper, .bend:
            m.simpleDeform(r.kind, axis: max(0, min(2, r.axis)), amount: r.amount)
        case .remesh:
            if let out = Voxel.remesh(m, resolution: max(16, min(r.count, 200)), smoothing: r.flag ? 1 : 0) { m = out }
        }
        return m
    }

    /// Gives a surface thickness: an inner offset shell plus rim faces along open edges.
    func solidified(thickness t: Float, even: Bool) -> EditMesh {
        var m = self
        let n = positions.count
        let vn = vertexNormals()
        if let c = colors, c.count == n { m.colors = c + c }
        m.positions += positions.enumerated().map { i, p in p - vn[i] * t }
        m.normalizeUVs()
        m.faces += faces.map { f in Array(f.map { $0 + n }.reversed()) }
        m.faceUVs += Array(repeating: [], count: faces.count)
        // rims on boundary edges, following the original winding
        let ef = edgeFaces()
        for f in faces {
            for i in 0..<f.count {
                let a = f[i], b = f[(i + 1) % f.count]
                if (ef[Edge(a, b)]?.count ?? 0) == 1 { m.faces.append([b, a, a + n, b + n]); m.faceUVs.append([]) }
            }
        }
        if even { m.recalculateNormals() }
        return m
    }

    /// Vertex-clustering decimation.
    func decimated(ratio: Float) -> EditMesh {
        let target = max(8, Int(Float(positions.count) * ratio))
        let b = bounds
        let size = simd_max(b.max - b.min, SIMD3(repeating: 1e-4))
        let res = max(2, Int(cbrtf(Float(target)) * 1.6))
        let cell = simd_reduce_max(size) / Float(res)
        var map = [Int](repeating: 0, count: positions.count)
        var cellIndex: [SIMD3<Int32>: Int] = [:]
        var sums: [SIMD3<Float>] = [], counts: [Float] = []
        for (i, p) in positions.enumerated() {
            let k = SIMD3<Int32>(Int32(((p.x - b.min.x) / cell).rounded(.down)), Int32(((p.y - b.min.y) / cell).rounded(.down)), Int32(((p.z - b.min.z) / cell).rounded(.down)))
            if let c = cellIndex[k] { map[i] = c; sums[c] += p; counts[c] += 1 }
            else { cellIndex[k] = sums.count; map[i] = sums.count; sums.append(p); counts.append(1) }
        }
        var m = EditMesh(); m.smooth = smooth
        m.positions = zip(sums, counts).map { $0 / $1 }
        for f in faces {
            var g: [Int] = []
            for v in f { let c = map[v]; if g.last != c && !g.contains(c) { g.append(c) } }
            if g.count >= 3 { m.faces.append(g) }
        }
        m.removeUnusedVertices()
        return m
    }

    /// Turns every edge into a thin square strut.
    func wireframed(thickness t: Float) -> EditMesh {
        var m = EditMesh()
        let es = edges()
        guard es.count < 40_000 else { return self }
        for e in es {
            let a = positions[e.a], b = positions[e.b]
            let d = b - a; let l = simd_length(d); guard l > 1e-6 else { continue }
            let dir = d / l
            let ref: SIMD3<Float> = abs(dir.y) < 0.9 ? [0, 1, 0] : [1, 0, 0]
            let u = simd_normalize(simd_cross(dir, ref)) * t, w = simd_normalize(simd_cross(dir, u)) * t
            let base = m.positions.count
            for p in [a, b] { m.positions += [p + u + w, p - u + w, p - u - w, p + u - w] }
            for i in 0..<4 { let j = (i + 1) % 4; m.faces.append([base + i, base + j, base + 4 + j, base + 4 + i]) }
        }
        m.recalculateNormals()
        return m
    }

    /// Spins every edge around an axis through the origin (lathe).
    func screwed(axis: Int, steps: Int, degrees: Float) -> EditMesh {
        var m = EditMesh(); m.smooth = true
        let es = edges()
        guard !es.isEmpty else { return self }
        var ax = SIMD3<Float>(0, 0, 0); ax[axis] = 1
        let full = abs(degrees - 360) < 0.01
        let rings = full ? steps : steps + 1
        let n = positions.count
        for s in 0..<rings {
            let q = simd_quatf(angle: degrees * .pi / 180 * Float(s) / Float(steps), axis: ax)
            m.positions += positions.map { q.act($0) }
        }
        for s in 0..<steps {
            let r0 = s * n, r1 = ((s + 1) % rings) * n
            for e in es { m.faces.append([r0 + e.a, r0 + e.b, r1 + e.b, r1 + e.a]) }
        }
        m.weld(distance: max(simd_reduce_max(bounds.max - bounds.min), 1e-3) * 1e-4)
        m.recalculateNormals()
        return m
    }

    /// Blender's Simple Deform: twist (degrees), taper (factor) or bend (degrees) along an axis.
    mutating func simpleDeform(_ kind: ModifierKind, axis: Int, amount: Float) {
        let b = bounds
        let lo = b.min[axis], hi = b.max[axis], len = max(hi - lo, 1e-5)
        let u = (axis + 1) % 3, w = (axis + 2) % 3
        positions = positions.map { p in
            var q = p
            let t = (p[axis] - lo) / len          // 0…1 along the axis
            switch kind {
            case .twist:
                let a = (t - 0.5) * amount * .pi / 180
                let c = cosf(a), s = sinf(a)
                q[u] = p[u] * c - p[w] * s; q[w] = p[u] * s + p[w] * c
            case .taper:
                let k = 1 + (t - 0.5) * 2 * amount
                q[u] = p[u] * max(0, k); q[w] = p[w] * max(0, k)
            case .bend:
                let total = amount * .pi / 180
                guard abs(total) > 1e-4 else { return p }
                let r = len / total
                let theta = (p[axis] - lo) / len * total
                let d = p[u]
                q[axis] = lo + (r - d) * sinf(theta)
                q[u] = r - (r - d) * cosf(theta)
            default: break
            }
            return q
        }
    }
}
