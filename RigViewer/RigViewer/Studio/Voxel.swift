import Foundation
import simd

/// Voxel tools: inside/outside sampling of closed meshes, booleans and remeshing (surface nets).
struct VoxelGrid {
    let nx: Int, ny: Int, nz: Int
    let origin: SIMD3<Float>      // centre of voxel (0,0,0)
    let cell: Float
    var v: [Float]                // 1 = inside, 0 = outside

    init(min lo: SIMD3<Float>, max hi: SIMD3<Float>, resolution: Int) {
        let size = hi - lo
        let c = max(simd_reduce_max(size), 1e-4) / Float(max(8, resolution))
        cell = c
        // One empty voxel of padding on every side so surfaces close.
        nx = Int((size.x / c).rounded(.up)) + 4
        ny = Int((size.y / c).rounded(.up)) + 4
        nz = Int((size.z / c).rounded(.up)) + 4
        origin = lo - SIMD3(repeating: c * 1.5)
        v = [Float](repeating: 0, count: nx * ny * nz)
    }

    @inline(__always) func idx(_ i: Int, _ j: Int, _ k: Int) -> Int { (k * ny + j) * nx + i }
    @inline(__always) func pos(_ i: Int, _ j: Int, _ k: Int) -> SIMD3<Float> { origin + SIMD3(Float(i), Float(j), Float(k)) * cell }

    /// Fills `v` with the inside/outside of a closed mesh (given in grid space) by ray parity along X.
    mutating func fill(with mesh: EditMesh) {
        var tris: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)] = []
        for f in mesh.faces where f.count >= 3 {
            for i in 1..<(f.count - 1) { tris.append((mesh.positions[f[0]], mesh.positions[f[i]], mesh.positions[f[i + 1]])) }
        }
        var columns = [[Float]](repeating: [], count: ny * nz)
        let jitter = SIMD2<Float>(0.000137, 0.000291) * cell
        for (a, b, c) in tris {
            let ylo = min(a.y, b.y, c.y), yhi = max(a.y, b.y, c.y), zlo = min(a.z, b.z, c.z), zhi = max(a.z, b.z, c.z)
            let j0 = max(0, Int(((ylo - origin.y) / cell).rounded(.down))), j1 = min(ny - 1, Int(((yhi - origin.y) / cell).rounded(.up)))
            let k0 = max(0, Int(((zlo - origin.z) / cell).rounded(.down))), k1 = min(nz - 1, Int(((zhi - origin.z) / cell).rounded(.up)))
            if j1 < j0 || k1 < k0 { continue }
            // 2D barycentric in the YZ plane
            let d = (b.y - a.y) * (c.z - a.z) - (c.y - a.y) * (b.z - a.z)
            if abs(d) < 1e-12 { continue }
            for k in k0...k1 {
                for j in j0...j1 {
                    let py = origin.y + Float(j) * cell + jitter.x, pz = origin.z + Float(k) * cell + jitter.y
                    let w1 = ((py - a.y) * (c.z - a.z) - (c.y - a.y) * (pz - a.z)) / d
                    let w2 = ((b.y - a.y) * (pz - a.z) - (py - a.y) * (b.z - a.z)) / d
                    let w0 = 1 - w1 - w2
                    if w0 < 0 || w1 < 0 || w2 < 0 { continue }
                    columns[k * ny + j].append(a.x * w0 + b.x * w1 + c.x * w2)
                }
            }
        }
        for k in 0..<nz {
            for j in 0..<ny {
                var xs = columns[k * ny + j]
                guard xs.count >= 2 else { continue }
                xs.sort()
                var p = 0
                while p + 1 < xs.count {
                    let i0 = max(0, Int(((xs[p] - origin.x) / cell).rounded(.up)))
                    let i1 = min(nx - 1, Int(((xs[p + 1] - origin.x) / cell).rounded(.down)))
                    if i1 >= i0 { for i in i0...i1 { v[idx(i, j, k)] = 1 } }
                    p += 2
                }
            }
        }
    }

    /// Separable box blur (softens the stair-steps before meshing).
    mutating func blur(passes: Int = 1) {
        for _ in 0..<passes {
            for axis in 0..<3 {
                var out = v
                for k in 1..<(nz - 1) { for j in 1..<(ny - 1) { for i in 1..<(nx - 1) {
                    let c = idx(i, j, k)
                    let o = axis == 0 ? 1 : (axis == 1 ? nx : nx * ny)
                    out[c] = (v[c - o] + v[c] * 2 + v[c + o]) / 4
                } } }
                v = out
            }
        }
    }

    /// Naive surface nets: one vertex per surface-crossing cell, one quad per crossing edge.
    func surfaceNets(iso: Float = 0.5) -> EditMesh {
        var vertexOf = [Int32](repeating: -1, count: nx * ny * nz)
        var m = EditMesh(); m.smooth = true
        // corner offsets of a cell
        let corners: [SIMD3<Int>] = [[0, 0, 0], [1, 0, 0], [0, 1, 0], [1, 1, 0], [0, 0, 1], [1, 0, 1], [0, 1, 1], [1, 1, 1]]
        let edges: [(Int, Int)] = [(0, 1), (2, 3), (4, 5), (6, 7), (0, 2), (1, 3), (4, 6), (5, 7), (0, 4), (1, 5), (2, 6), (3, 7)]
        for k in 0..<(nz - 1) { for j in 0..<(ny - 1) { for i in 0..<(nx - 1) {
            let b0 = idx(i, j, k), sy = nx, sz = nx * ny
            let vals = SIMD8<Float>(v[b0], v[b0 + 1], v[b0 + sy], v[b0 + sy + 1], v[b0 + sz], v[b0 + sz + 1], v[b0 + sy + sz], v[b0 + sy + sz + 1])
            let mx = vals.max(), mn = vals.min()
            if mn > iso || mx <= iso { continue }
            var sum = SIMD3<Float>(repeating: 0); var n: Float = 0
            for (a, b) in edges {
                let va = vals[a], vb = vals[b]
                if (va > iso) == (vb > iso) { continue }
                let t = (iso - va) / (vb - va)
                let pa = SIMD3<Float>(corners[a]), pb = SIMD3<Float>(corners[b])
                sum += pa + (pb - pa) * t; n += 1
            }
            let local = n > 0 ? sum / n : SIMD3(repeating: 0.5)
            vertexOf[idx(i, j, k)] = Int32(m.positions.count)
            m.positions.append(origin + (SIMD3(Float(i), Float(j), Float(k)) + local) * cell)
        } } }
        // Quads across each grid edge that crosses the surface.
        for k in 1..<(nz - 1) { for j in 1..<(ny - 1) { for i in 1..<(nx - 1) {
            let a = v[idx(i, j, k)] > iso
            // X edge (i,j,k)-(i+1,j,k): cells sharing it vary in j-1..j, k-1..k
            if i + 1 < nx, a != (v[idx(i + 1, j, k)] > iso) {
                quad([idx(i, j - 1, k - 1), idx(i, j, k - 1), idx(i, j, k), idx(i, j - 1, k)], dir: SIMD3(a ? 1 : -1, 0, 0), vertexOf, &m)
            }
            if j + 1 < ny, a != (v[idx(i, j + 1, k)] > iso) {
                quad([idx(i - 1, j, k - 1), idx(i, j, k - 1), idx(i, j, k), idx(i - 1, j, k)], dir: SIMD3(0, a ? 1 : -1, 0), vertexOf, &m)
            }
            if k + 1 < nz, a != (v[idx(i, j, k + 1)] > iso) {
                quad([idx(i - 1, j - 1, k), idx(i, j - 1, k), idx(i, j, k), idx(i - 1, j, k)], dir: SIMD3(0, 0, a ? 1 : -1), vertexOf, &m)
            }
        } } }
        return m
    }

    private func quad(_ cells: [Int], dir: SIMD3<Float>, _ map: [Int32], _ m: inout EditMesh) {
        let vs = cells.map { Int(map[$0]) }
        guard vs.allSatisfy({ $0 >= 0 }) else { return }
        var f = vs
        let p = f.map { m.positions[$0] }
        let n = simd_cross(p[1] - p[0], p[2] - p[0]) + simd_cross(p[2] - p[0], p[3] - p[0])
        if simd_dot(n, dir) < 0 { f.reverse() }
        m.faces.append(f)
    }
}

enum BooleanOp: String, CaseIterable, Identifiable {
    case union = "Union", difference = "Difference", intersect = "Intersect"
    var id: String { rawValue }
    var icon: String { switch self { case .union: return "plus.square.on.square"; case .difference: return "minus.square"; case .intersect: return "square.on.square.intersection.dashed" } }
}

enum Voxel {
    static func bounds(_ ms: [EditMesh]) -> (SIMD3<Float>, SIMD3<Float>) {
        var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude), hi = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        for m in ms { let b = m.bounds; lo = simd_min(lo, b.min); hi = simd_max(hi, b.max) }
        return (lo, hi)
    }

    /// Rebuilds a closed mesh as an even quad surface (Blender's voxel remesh).
    static func remesh(_ mesh: EditMesh, resolution: Int, smoothing: Int = 1) -> EditMesh? {
        guard mesh.faceCount > 0 else { return nil }
        let (lo, hi) = bounds([mesh])
        var g = VoxelGrid(min: lo, max: hi, resolution: resolution)
        guard g.nx * g.ny * g.nz < 12_000_000 else { return nil }
        g.fill(with: mesh)
        g.blur(passes: smoothing)
        var out = g.surfaceNets()
        guard out.faceCount > 0 else { return nil }
        out.smoothVertices([], factor: 0.5, iterations: 1)
        return out
    }

    /// CSG on two closed meshes given in the same space.
    static func boolean(_ a: EditMesh, _ b: EditMesh, _ op: BooleanOp, resolution: Int) -> EditMesh? {
        let (lo, hi) = bounds(op == .difference ? [a] : [a, b])
        var ga = VoxelGrid(min: lo, max: hi, resolution: resolution)
        guard ga.nx * ga.ny * ga.nz < 12_000_000 else { return nil }
        var gb = ga
        gb.v = [Float](repeating: 0, count: gb.v.count)
        ga.fill(with: a); gb.fill(with: b)
        ga.blur(passes: 1); gb.blur(passes: 1)
        for i in ga.v.indices {
            switch op {
            case .union: ga.v[i] = max(ga.v[i], gb.v[i])
            case .intersect: ga.v[i] = min(ga.v[i], gb.v[i])
            case .difference: ga.v[i] = min(ga.v[i], 1 - gb.v[i])
            }
        }
        var out = ga.surfaceNets()
        guard out.faceCount > 0 else { return nil }
        out.smoothVertices([], factor: 0.4, iterations: 1)
        return out
    }
}
