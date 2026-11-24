import SceneKit
import UIKit
import simd

// MARK: - More primitives

extension EditMesh {
    static func grid(size s: Float = 2, divisions n: Int = 10) -> EditMesh { plane(size: s, divisions: max(1, n)) }

    /// A flat disc (one n-gon) lying on the floor, facing up.
    static func circle(radius r: Float = 0.5, segments seg: Int = 32) -> EditMesh {
        var m = EditMesh()
        for s in 0..<max(3, seg) { let a = 2 * Float.pi * Float(s) / Float(max(3, seg)); m.positions.append([r * cosf(a), 0, r * sinf(a)]) }
        m.faces = [Array((0..<m.positions.count).reversed())]
        if m.faceNormal(m.faces[0]).y < 0 { m.faces[0].reverse() }
        return m
    }

    static func capsule(radius r: Float = 0.3, height h: Float = 1.2, segments seg: Int = 24, rings: Int = 8) -> EditMesh {
        var m = EditMesh(); m.smooth = true
        let half = max(0, h / 2 - r)
        let rr = max(2, rings)
        m.positions.append([0, half + r, 0])
        var ringsY: [(Float, Float)] = []   // (y, radius)
        for i in 1...rr { let t = Float.pi / 2 * Float(i) / Float(rr); ringsY.append((half + r * cosf(t), r * sinf(t))) }
        for i in 0..<rr { let t = Float.pi / 2 + Float.pi / 2 * Float(i + 1) / Float(rr); ringsY.append((-half + r * cosf(t), r * sinf(t))) }
        ringsY.removeLast()   // the bottom pole is added separately
        for (y, rad) in ringsY { for s in 0..<seg { let a = 2 * Float.pi * Float(s) / Float(seg); m.positions.append([rad * cosf(a), y, rad * sinf(a)]) } }
        m.positions.append([0, -half - r, 0]); let bottom = m.positions.count - 1
        func idx(_ ring: Int, _ s: Int) -> Int { 1 + ring * seg + (s % seg) }
        for s in 0..<seg { m.faces.append([0, idx(0, s + 1), idx(0, s)]) }
        for ring in 0..<(ringsY.count - 1) { for s in 0..<seg { m.faces.append([idx(ring, s), idx(ring, s + 1), idx(ring + 1, s + 1), idx(ring + 1, s)]) } }
        let last = ringsY.count - 1
        for s in 0..<seg { m.faces.append([bottom, idx(last, s), idx(last, s + 1)]) }
        if m.signedVolume() < 0 { m.faces = m.faces.map { Array($0.reversed()) } }
        return m
    }

    static func pyramid(size s: Float = 1, height h: Float = 1) -> EditMesh {
        let a = s / 2
        var m = EditMesh(positions: [[-a, -h / 2, -a], [a, -h / 2, -a], [a, -h / 2, a], [-a, -h / 2, a], [0, h / 2, 0]],
                         faces: [[0, 1, 2, 3], [3, 2, 4], [2, 1, 4], [1, 0, 4], [0, 3, 4]])
        if m.signedVolume() < 0 { m.faces = m.faces.map { Array($0.reversed()) } }
        return m
    }

    /// A pipe: outer and inner walls joined by rings at both ends.
    static func tube(outer R: Float = 0.5, inner r: Float = 0.35, height h: Float = 1, segments seg: Int = 32) -> EditMesh {
        var m = EditMesh()
        for (rad, y) in [(R, -h / 2), (R, h / 2), (r, -h / 2), (r, h / 2)] {
            for s in 0..<seg { let a = 2 * Float.pi * Float(s) / Float(seg); m.positions.append([rad * cosf(a), y, rad * sinf(a)]) }
        }
        func v(_ ring: Int, _ s: Int) -> Int { ring * seg + (s % seg) }
        for s in 0..<seg {
            m.faces.append([v(0, s), v(1, s), v(1, s + 1), v(0, s + 1)])        // outer
            m.faces.append([v(2, s + 1), v(3, s + 1), v(3, s), v(2, s)])        // inner
            m.faces.append([v(1, s), v(3, s), v(3, s + 1), v(1, s + 1)])        // top
            m.faces.append([v(0, s + 1), v(2, s + 1), v(2, s), v(0, s)])        // bottom
        }
        if m.signedVolume() < 0 { m.faces = m.faces.map { Array($0.reversed()) } }
        return m
    }

    /// A cube with rounded edges and corners.
    static func roundedCube(size s: Float = 1, radius rad: Float = 0.15, segments n: Int = 6) -> EditMesh {
        var m = cube(size: 1)
        let levels = max(1, min(4, Int(log2(Float(max(n, 2)))) + 1))
        for _ in 0..<levels { m = m.subdivideFlat() }
        m.weld(distance: 1e-5)
        let h = s / 2, r = min(max(rad, 0.001), h * 0.99), inner = h - r
        m.positions = m.positions.map { p in
            let q = p * s
            let c = simd_clamp(q, SIMD3(repeating: -inner), SIMD3(repeating: inner))
            let d = q - c
            let l = simd_length(d)
            return l > 1e-6 ? c + d / l * r : q
        }
        m.smooth = true
        return m
    }

    static func stairs(steps n: Int = 8, width w: Float = 1, depth d: Float = 2, height h: Float = 1.5) -> EditMesh {
        var m = EditMesh()
        let sd = d / Float(max(n, 1)), sh = h / Float(max(n, 1))
        for i in 0..<max(1, n) {
            var step = EditMesh.cube(size: 1)
            let top = sh * Float(i + 1)
            step.apply(simd_float4x4(diagonal: SIMD4(w, top, sd, 1)))
            step.positions = step.positions.map { $0 + SIMD3(0, top / 2 - h / 2, -d / 2 + sd * (Float(i) + 0.5)) }
            m.append(step)
        }
        return m
    }

    static func gear(teeth n: Int = 16, radius r: Float = 0.5, toothDepth td: Float = 0.08, thickness t: Float = 0.15, hole: Float = 0.12) -> EditMesh {
        var outline: [SIMD2<Float>] = []
        let k = max(6, n)
        for i in 0..<k {
            let a0 = 2 * Float.pi * Float(i) / Float(k), step = 2 * Float.pi / Float(k)
            for (f, rr) in [(0.0, r - td), (0.2, r - td), (0.3, r), (0.7, r), (0.8, r - td)] as [(Float, Float)] {
                let a = a0 + step * f; outline.append([rr * cosf(a), rr * sinf(a)])
            }
        }
        var m = EditMesh()
        let seg = outline.count
        let holeSeg = max(12, k)
        for y in [-t / 2, t / 2] { for p in outline { m.positions.append([p.x, y, p.y]) } }
        for y in [-t / 2, t / 2] { for s in 0..<holeSeg { let a = 2 * Float.pi * Float(s) / Float(holeSeg); m.positions.append([hole * cosf(a), y, hole * sinf(a)]) } }
        let ob = 0, ot = seg, hb = 2 * seg, ht = 2 * seg + holeSeg
        for s in 0..<seg { m.faces.append([ob + s, ot + s, ot + (s + 1) % seg, ob + (s + 1) % seg]) }
        for s in 0..<holeSeg { m.faces.append([hb + (s + 1) % holeSeg, ht + (s + 1) % holeSeg, ht + s, hb + s]) }
        // Caps: connect the outline to the hole with quads/tris by angle.
        for (outer, inner, up) in [(ot, ht, true), (ob, hb, false)] {
            for s in 0..<seg {
                let a = Float(s) / Float(seg), b = Float(s + 1) / Float(seg)
                let ia = Int((a * Float(holeSeg)).rounded()) % holeSeg, ib = Int((b * Float(holeSeg)).rounded()) % holeSeg
                var f = ia == ib ? [outer + s, outer + (s + 1) % seg, inner + ia] : [outer + s, outer + (s + 1) % seg, inner + ib, inner + ia]
                if !up { f.reverse() }
                m.faces.append(f)
            }
        }
        m.recalculateNormals()
        return m
    }

    static func spring(radius R: Float = 0.4, wire r: Float = 0.06, turns: Float = 4, height h: Float = 1.2, segments seg: Int = 120, sides: Int = 10) -> EditMesh {
        var m = EditMesh(); m.smooth = true
        let n = max(8, seg)
        for i in 0...n {
            let t = Float(i) / Float(n)
            let a = t * turns * 2 * .pi
            let c = SIMD3<Float>(R * cosf(a), -h / 2 + h * t, R * sinf(a))
            let tangent = simd_normalize(SIMD3<Float>(-R * sinf(a) * turns * 2 * .pi, h, R * cosf(a) * turns * 2 * .pi))
            let radial = simd_normalize(SIMD3<Float>(cosf(a), 0, sinf(a)))
            let bin = simd_normalize(simd_cross(tangent, radial))
            for j in 0..<sides {
                let b = 2 * Float.pi * Float(j) / Float(sides)
                m.positions.append(c + (radial * cosf(b) + bin * sinf(b)) * r)
            }
        }
        for i in 0..<n { for j in 0..<sides {
            let a = i * sides + j, b = i * sides + (j + 1) % sides, c = (i + 1) * sides + (j + 1) % sides, d = (i + 1) * sides + j
            m.faces.append([a, b, c, d])
        } }
        m.faces.append(Array((0..<sides).reversed()))
        m.faces.append(Array((0..<sides).map { n * sides + $0 }))
        if m.signedVolume() < 0 { m.faces = m.faces.map { Array($0.reversed()) } }
        return m
    }

    /// Extruded 3D text built with Core Text via SceneKit.
    static func text(_ s: String, depth: Float = 0.15, bold: Bool = true) -> EditMesh {
        let str = s.isEmpty ? "Text" : s
        let t = SCNText(string: str, extrusionDepth: CGFloat(depth * 10))
        t.font = UIFont.systemFont(ofSize: 10, weight: bold ? .heavy : .regular)
        t.flatness = 0.08
        t.chamferRadius = 0
        var out = EditMesh()
        for ei in 0..<t.elements.count {
            if let m = EditMesh.from(geometry: t, element: ei) { out.append(m) }
        }
        out.weld(distance: 1e-3)
        out.apply(simd_float4x4(diagonal: SIMD4(0.1, 0.1, 0.1, 1)))
        let b = out.bounds
        let c = (b.min + b.max) / 2
        out.positions = out.positions.map { $0 - SIMD3(c.x, b.min.y, c.z) }
        if out.signedVolume() < 0 { out.faces = out.faces.map { Array($0.reversed()) } }
        out.faceUVs = []
        return out
    }
}

// MARK: - Selection helpers

extension EditMesh {
    func vertexFaces() -> [[Int]] {
        var vf = [[Int]](repeating: [], count: positions.count)
        for (fi, f) in faces.enumerated() { for v in f where v < vf.count { vf[v].append(fi) } }
        return vf
    }

    /// Faces connected (through shared vertices) to the seed faces.
    func linkedFaces(_ seeds: Set<Int>) -> Set<Int> {
        let vf = vertexFaces()
        var out = seeds, stack = Array(seeds)
        while let f = stack.popLast() {
            for v in faces[f] { for g in vf[v] where !out.contains(g) { out.insert(g); stack.append(g) } }
        }
        return out
    }

    func linkedVertices(_ seeds: Set<Int>) -> Set<Int> {
        let nb = neighbors()
        var out = seeds, stack = Array(seeds)
        while let v = stack.popLast() { for n in nb[v] where !out.contains(n) { out.insert(n); stack.append(n) } }
        return out
    }

    func growVertices(_ s: Set<Int>) -> Set<Int> {
        let nb = neighbors(); var out = s
        for v in s { out.formUnion(nb[v]) }
        return out
    }

    func shrinkVertices(_ s: Set<Int>) -> Set<Int> {
        let nb = neighbors()
        return s.filter { v in nb[v].allSatisfy(s.contains) }
    }

    func growFaces(_ s: Set<Int>) -> Set<Int> {
        let vf = vertexFaces(); var out = s
        for f in s { for v in faces[f] { out.formUnion(vf[v]) } }
        return out
    }

    func shrinkFaces(_ s: Set<Int>) -> Set<Int> {
        let vf = vertexFaces()
        return s.filter { f in faces[f].allSatisfy { v in vf[v].allSatisfy(s.contains) } }
    }

    /// Edge loop through 4-valence vertices (Blender's Alt-click loop select).
    func edgeLoop(from start: Edge) -> Set<Edge> {
        let ef = edgeFaces()
        var vEdges = [[Edge]](repeating: [], count: positions.count)
        for e in ef.keys { vEdges[e.a].append(e); vEdges[e.b].append(e) }
        var loop: Set<Edge> = [start]
        for startVert in [start.a, start.b] {
            var cur = start, v = startVert
            for _ in 0..<10_000 {
                let incident = vEdges[v]
                guard incident.count == 4 else { break }
                let curFaces = Set(ef[cur] ?? [])
                guard let next = incident.first(where: { $0 != cur && Set(ef[$0] ?? []).isDisjoint(with: curFaces) }) else { break }
                if loop.contains(next) { break }
                loop.insert(next)
                cur = next
                v = next.a == v ? next.b : next.a
            }
        }
        return loop
    }

    /// Quads crossed by a ring starting at an edge, and the ring's edges.
    func edgeRing(from start: Edge) -> (quads: [Int], edges: [Edge]) {
        let ef = edgeFaces()
        var quads: [Int] = [], edges: [Edge] = [start]
        var seen = Set<Int>()
        for first in ef[start] ?? [] {
            var face = first, entry = start
            for _ in 0..<10_000 {
                guard faces[face].count == 4, !seen.contains(face) else { break }
                seen.insert(face); quads.append(face)
                let f = faces[face]
                guard let i = (0..<4).first(where: { Edge(f[$0], f[($0 + 1) % 4]) == entry }) else { break }
                let exit = Edge(f[(i + 2) % 4], f[(i + 3) % 4])
                if !edges.contains(exit) { edges.append(exit) }
                guard let nf = (ef[exit] ?? []).first(where: { $0 != face }) else { break }
                face = nf; entry = exit
            }
        }
        return (quads, edges)
    }
}

// MARK: - Topology tools

extension EditMesh {
    /// Blender's loop cut: splits the quad ring through `edge` with `cuts` evenly spaced loops.
    mutating func loopCut(edge: Edge, cuts n: Int = 1) -> Set<Int> {
        let (quads, ringEdges) = edgeRing(from: edge)
        guard !quads.isEmpty else { return [] }
        normalizeUVs()
        let cuts = max(1, min(n, 32))
        var edgePts: [Edge: [Int]] = [:]   // ordered from edge.a to edge.b
        var newVerts = Set<Int>()
        let hasColors = colors?.count == positions.count
        for e in ringEdges {
            var pts: [Int] = []
            for k in 1...cuts {
                let t = Float(k) / Float(cuts + 1)
                positions.append(positions[e.a] + (positions[e.b] - positions[e.a]) * t)
                if hasColors { colors!.append(colors![e.a] + (colors![e.b] - colors![e.a]) * t) }
                pts.append(positions.count - 1); newVerts.insert(positions.count - 1)
            }
            edgePts[e] = pts
        }
        func along(_ from: Int, _ to: Int) -> [Int] {
            let e = Edge(from, to); guard let p = edgePts[e] else { return [] }
            return e.a == from ? p : p.reversed()
        }
        let quadSet = Set(quads)
        var newFaces: [[Int]] = []
        for (fi, f) in faces.enumerated() {
            if quadSet.contains(fi) {
                guard let i = (0..<4).first(where: { edgePts[Edge(f[$0], f[($0 + 1) % 4])] != nil && edgePts[Edge(f[($0 + 2) % 4], f[($0 + 3) % 4])] != nil }) else { newFaces.append(f); continue }
                let vi = f[i], vi1 = f[(i + 1) % 4], vi2 = f[(i + 2) % 4], vi3 = f[(i + 3) % 4]
                let E = [vi] + along(vi, vi1) + [vi1]
                let X = [vi3] + along(vi3, vi2) + [vi2]
                for k in 0...cuts { newFaces.append([E[k], E[k + 1], X[k + 1], X[k]]) }
            } else {
                // Keep neighbours watertight: insert the new points into any edge they share.
                var g: [Int] = []
                for j in 0..<f.count {
                    g.append(f[j])
                    g += along(f[j], f[(j + 1) % f.count])
                }
                newFaces.append(g)
            }
        }
        faces = newFaces; faceUVs = Array(repeating: [], count: faces.count)
        return newVerts
    }

    /// Merges the two faces on each side of these edges.
    mutating func dissolveEdges(_ edges: Set<Edge>) {
        normalizeUVs()
        var alive = [Bool](repeating: true, count: faces.count)
        for e in edges {
            var found: [Int] = []
            for (fi, f) in faces.enumerated() where alive[fi] && f.count >= 3 {
                for i in 0..<f.count where Edge(f[i], f[(i + 1) % f.count]) == e { found.append(fi); break }
                if found.count == 2 { break }
            }
            guard found.count == 2 else { continue }
            let f1 = faces[found[0]], f2 = faces[found[1]]
            guard let i1 = (0..<f1.count).first(where: { f1[$0] == e.a && f1[($0 + 1) % f1.count] == e.b || f1[$0] == e.b && f1[($0 + 1) % f1.count] == e.a }) else { continue }
            let p = f1[i1], q = f1[(i1 + 1) % f1.count]      // f1 runs p → q, so f2 runs q → p
            guard let j = f2.firstIndex(of: p) else { continue }
            let r1 = Array(f1[((i1 + 1) % f1.count)...] + f1[..<((i1 + 1) % f1.count)])    // starts at q, ends at p
            let r2 = Array(f2[j...] + f2[..<j])                                                // starts at p, ends at q
            guard r2.last == q else { continue }
            var merged = r1 + r2.dropFirst().dropLast()
            // remove immediate repeats
            var clean: [Int] = []; for v in merged where clean.last != v { clean.append(v) }
            if clean.count > 1, clean.first == clean.last { clean.removeLast() }
            merged = clean
            guard Set(merged).count >= 3 else { continue }
            faces[found[0]] = merged; faceUVs[found[0]] = []
            alive[found[1]] = false
        }
        var nf: [[Int]] = [], nu: [[SIMD2<Float>]] = []
        for (i, f) in faces.enumerated() where alive[i] { nf.append(f); nu.append(faceUVs[i]) }
        faces = nf; faceUVs = nu
        removeUnusedVertices()
    }

    /// Dissolves the edges shared between selected faces, making one face per connected region.
    mutating func dissolveFaces(_ sel: Set<Int>) {
        var inner = Set<Edge>()
        for (e, fs) in edgeFaces() where fs.count == 2 && sel.contains(fs[0]) && sel.contains(fs[1]) { inner.insert(e) }
        dissolveEdges(inner)
    }

    /// Splits each selected face into a fan around its centre.
    mutating func poke(_ sel: Set<Int>) -> Set<Int> {
        normalizeUVs()
        var out = Set<Int>()
        var nf: [[Int]] = [], nu: [[SIMD2<Float>]] = []
        let hasColors = colors?.count == positions.count
        for (fi, f) in faces.enumerated() {
            guard sel.contains(fi) else { nf.append(f); nu.append(faceUVs[fi]); continue }
            positions.append(faceCenter(f))
            if hasColors { var c = SIMD4<Float>(repeating: 0); for v in f { c += colors![v] }; colors!.append(c / Float(f.count)) }
            let c = positions.count - 1
            for i in 0..<f.count { out.insert(nf.count); nf.append([f[i], f[(i + 1) % f.count], c]); nu.append([]) }
        }
        faces = nf; faceUVs = nu
        return out
    }

    /// Joins pairs of neighbouring triangles into quads where they're nearly flat.
    mutating func trisToQuads(maxAngle: Float = 0.7) {
        normalizeUVs()
        var used = Set<Int>()
        var nf: [[Int]] = []
        let ef = edgeFaces()
        var candidates: [(Float, Int, Int, Edge)] = []
        for (e, fs) in ef where fs.count == 2 && faces[fs[0]].count == 3 && faces[fs[1]].count == 3 {
            let a = faceNormal(faces[fs[0]]), b = faceNormal(faces[fs[1]])
            let ang = acosf(max(-1, min(1, simd_dot(a, b))))
            if ang < maxAngle { candidates.append((ang, fs[0], fs[1], e)) }
        }
        candidates.sort { $0.0 < $1.0 }
        for (_, f1, f2, e) in candidates where !used.contains(f1) && !used.contains(f2) {
            let t1 = faces[f1], t2 = faces[f2]
            guard let i = (0..<3).first(where: { Edge(t1[$0], t1[($0 + 1) % 3]) == e }),
                  let other = t2.first(where: { $0 != e.a && $0 != e.b }) else { continue }
            // t1 = [x, y, z] with edge x→y shared; quad = x, other, y, z
            let x = t1[i], y = t1[(i + 1) % 3], z = t1[(i + 2) % 3]
            nf.append([x, other, y, z])
            used.insert(f1); used.insert(f2)
        }
        for (fi, f) in faces.enumerated() where !used.contains(fi) { nf.append(f) }
        faces = nf; faceUVs = Array(repeating: [], count: nf.count)
    }

    /// Makes face windings consistent and pointing outward (per connected part).
    mutating func recalculateNormals() {
        normalizeUVs()
        var visited = [Bool](repeating: false, count: faces.count)
        let ef = edgeFaces()
        for seed in faces.indices where !visited[seed] {
            var comp: [Int] = [seed]; visited[seed] = true
            var stack = [seed]
            while let f = stack.popLast() {
                let fv = faces[f]
                for i in 0..<fv.count {
                    let a = fv[i], b = fv[(i + 1) % fv.count]
                    for g in ef[Edge(a, b)] ?? [] where !visited[g] {
                        let gv = faces[g]
                        // Consistent neighbours traverse the shared edge in the opposite direction.
                        let same = (0..<gv.count).contains { gv[$0] == a && gv[($0 + 1) % gv.count] == b }
                        if same { faces[g].reverse(); faceUVs[g].reverse() }
                        visited[g] = true; comp.append(g); stack.append(g)
                    }
                }
            }
            // Outward: positive signed volume about the part's centre.
            var c = SIMD3<Float>(repeating: 0); var n: Float = 0
            for f in comp { for v in faces[f] { c += positions[v]; n += 1 } }
            c /= max(n, 1)
            var vol: Float = 0
            for f in comp {
                let fv = faces[f]; guard fv.count >= 3 else { continue }
                let a = positions[fv[0]] - c
                for i in 1..<(fv.count - 1) { vol += simd_dot(a, simd_cross(positions[fv[i]] - c, positions[fv[i + 1]] - c)) }
            }
            if vol < 0 { for f in comp { faces[f].reverse(); faceUVs[f].reverse() } }
        }
    }

    mutating func shrinkFatten(_ verts: Set<Int>, amount: Float) {
        let vn = vertexNormals()
        for v in (verts.isEmpty ? Set(positions.indices) : verts) { positions[v] += vn[v] * amount }
    }

    mutating func toSphere(_ verts: Set<Int>, factor: Float) {
        let vs = verts.isEmpty ? Set(positions.indices) : verts
        guard !vs.isEmpty else { return }
        var c = SIMD3<Float>(repeating: 0); for v in vs { c += positions[v] }; c /= Float(vs.count)
        var r: Float = 0; for v in vs { r += simd_length(positions[v] - c) }; r /= Float(vs.count)
        for v in vs {
            let d = positions[v] - c; let l = simd_length(d)
            guard l > 1e-6 else { continue }
            positions[v] = positions[v] + (c + d / l * r - positions[v]) * factor
        }
    }

    mutating func randomize(_ verts: Set<Int>, amount: Float, seed: UInt64 = 1) {
        var g = SplitMix(seed: seed)
        let vn = vertexNormals()
        for v in (verts.isEmpty ? Set(positions.indices) : verts).sorted() {
            positions[v] += vn[v] * (g.nextFloat() * 2 - 1) * amount
        }
    }

    /// Copies the given faces (with their own vertices). Returns the new faces.
    mutating func duplicateFaces(_ sel: Set<Int>) -> Set<Int> {
        normalizeUVs()
        var map: [Int: Int] = [:]
        var out = Set<Int>()
        let hasColors = colors?.count == positions.count
        for fi in sel.sorted() {
            let f = faces[fi]
            let g = f.map { v -> Int in
                if let m = map[v] { return m }
                positions.append(positions[v]); if hasColors { colors!.append(colors![v]) }
                map[v] = positions.count - 1; return positions.count - 1
            }
            faces.append(g); faceUVs.append(faceUVs[fi]); out.insert(faces.count - 1)
        }
        return out
    }

    /// Mesh made of just these faces (for Separate).
    func extract(_ sel: Set<Int>) -> EditMesh {
        var m = EditMesh(); m.smooth = smooth
        var map: [Int: Int] = [:]
        let hasColors = colors?.count == positions.count
        if hasColors { m.colors = [] }
        for fi in sel.sorted() where fi < faces.count {
            m.faces.append(faces[fi].map { v in
                if let i = map[v] { return i }
                m.positions.append(positions[v]); if hasColors { m.colors!.append(colors![v]) }
                map[v] = m.positions.count - 1; return m.positions.count - 1
            })
            m.faceUVs.append(fi < faceUVs.count ? faceUVs[fi] : [])
        }
        return m
    }

    /// Splits a mesh into its connected parts.
    func looseParts() -> [EditMesh] {
        var remaining = Set(faces.indices)
        var parts: [EditMesh] = []
        while let seed = remaining.first {
            let comp = linkedFaces([seed])
            remaining.subtract(comp)
            parts.append(extract(comp))
        }
        return parts
    }

    /// Mirrors across an axis (0 = X, 1 = Y, 2 = Z) and welds the seam.
    mutating func mirror(axis: Int, merge: Bool = true) {
        let n = positions.count
        if let c = colors, c.count == n { colors = c + c }
        var s = SIMD3<Float>(repeating: 1); s[axis] = -1
        normalizeUVs()
        positions += positions.map { $0 * s }
        faces += faces.map { f in Array(f.map { $0 + n }.reversed()) }
        faceUVs += faceUVs.map { Array($0.reversed()) }
        if merge {
            let size = simd_length(bounds.max - bounds.min)
            for i in positions.indices where abs(positions[i][axis]) < size * 1e-4 { positions[i][axis] = 0 }
            weld(distance: max(size * 1e-4, 1e-5))
        }
    }

    /// Moves the mesh so its bounding-box centre (or base) sits at the origin. Returns the offset applied.
    mutating func recentre(base: Bool = false) -> SIMD3<Float> {
        let b = bounds
        var c = (b.min + b.max) / 2
        if base { c.y = b.min.y }
        positions = positions.map { $0 - c }
        return c
    }
}

// MARK: - UV projection

enum UVProjection: String, CaseIterable, Identifiable {
    case cube = "Cube", cylinder = "Cylinder", sphere = "Sphere", top = "Top", front = "Front"
    var id: String { rawValue }
    var icon: String {
        switch self { case .cube: return "cube"; case .cylinder: return "cylinder"; case .sphere: return "globe"; case .top: return "square.grid.3x3.topleft.filled"; case .front: return "rectangle.portrait" }
    }
}

extension EditMesh {
    mutating func projectUVs(_ p: UVProjection, faces sel: Set<Int> = [], scale: Float = 1) {
        normalizeUVs()
        let b = bounds
        let size = max(simd_reduce_max(b.max - b.min), 1e-5)
        let c = (b.min + b.max) / 2
        let targets = sel.isEmpty ? Set(faces.indices) : sel
        for fi in targets where fi < faces.count {
            let f = faces[fi]
            let n = faceNormal(f), a = simd_abs(n)
            var uvs: [SIMD2<Float>] = []
            for v in f {
                let q = (positions[v] - c) / size
                var uv: SIMD2<Float>
                switch p {
                case .cube:
                    if a.x >= a.y && a.x >= a.z { uv = [q.z * (n.x > 0 ? -1 : 1), q.y] }
                    else if a.y >= a.z { uv = [q.x, q.z * (n.y > 0 ? 1 : -1)] }
                    else { uv = [q.x * (n.z > 0 ? 1 : -1), q.y] }
                    uv = uv + 0.5
                case .cylinder:
                    uv = [atan2f(q.z, q.x) / (2 * .pi) + 0.5, q.y + 0.5]
                case .sphere:
                    let l = max(simd_length(q), 1e-6)
                    uv = [atan2f(q.z, q.x) / (2 * .pi) + 0.5, acosf(max(-1, min(1, q.y / l))) / .pi]
                case .top: uv = [q.x + 0.5, q.z + 0.5]
                case .front: uv = [q.x + 0.5, 0.5 - q.y]
                }
                uvs.append(uv * scale)
            }
            // Fix the seam for wrapped projections.
            if p == .cylinder || p == .sphere {
                let us = uvs.map(\.x)
                if let mx = us.max(), let mn = us.min(), mx - mn > 0.5 * scale {
                    uvs = uvs.map { $0.x < 0.5 * scale ? SIMD2($0.x + scale, $0.y) : $0 }
                }
            }
            faceUVs[fi] = uvs
        }
    }
}

// MARK: - Deterministic noise

struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func nextFloat() -> Float { Float(next() >> 40) / Float(1 << 24) }
}

enum Noise {
    @inline(__always) static func hash(_ x: Int32, _ y: Int32, _ z: Int32) -> Float {
        var h = UInt32(bitPattern: x) &* 374761393 &+ UInt32(bitPattern: y) &* 668265263 &+ UInt32(bitPattern: z) &* 2147483647
        h = (h ^ (h >> 13)) &* 1274126177
        return Float(h ^ (h >> 16)) / Float(UInt32.max)
    }
    /// Smooth value noise in 0…1.
    static func value(_ p: SIMD3<Float>) -> Float {
        let f = SIMD3<Float>(floorf(p.x), floorf(p.y), floorf(p.z))
        let t = p - f
        let u = t * t * (3 - 2 * t)
        let x = Int32(f.x), y = Int32(f.y), z = Int32(f.z)
        func h(_ a: Int32, _ b: Int32, _ c: Int32) -> Float { hash(x + a, y + b, z + c) }
        let x00 = h(0, 0, 0) + (h(1, 0, 0) - h(0, 0, 0)) * u.x
        let x10 = h(0, 1, 0) + (h(1, 1, 0) - h(0, 1, 0)) * u.x
        let x01 = h(0, 0, 1) + (h(1, 0, 1) - h(0, 0, 1)) * u.x
        let x11 = h(0, 1, 1) + (h(1, 1, 1) - h(0, 1, 1)) * u.x
        let y0 = x00 + (x10 - x00) * u.y, y1 = x01 + (x11 - x01) * u.y
        return y0 + (y1 - y0) * u.z
    }
    static func fbm(_ p: SIMD3<Float>, octaves: Int = 4) -> Float {
        var s: Float = 0, a: Float = 0.5, q = p, norm: Float = 0
        for _ in 0..<octaves { s += value(q) * a; norm += a; a *= 0.5; q *= 2.03 }
        return s / norm
    }
}
