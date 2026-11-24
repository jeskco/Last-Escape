import SceneKit
import simd

/// Writes static meshes (with PBR materials and base-colour textures) to a binary glTF 2.0 file.
/// Transforms are baked into the vertices so any engine shows the scene exactly as it looks here.
@MainActor
enum GLBWriter {
    static func write(roots: [SCNNode], relativeTo base: SCNNode) -> Data? {
        var bin = Data()
        var bufferViews: [[String: Any]] = [], accessors: [[String: Any]] = [], meshes: [[String: Any]] = [], nodes: [[String: Any]] = []
        var materials: [[String: Any]] = [], images: [[String: Any]] = [], textures: [[String: Any]] = []
        var materialIndex: [ObjectIdentifier: Int] = [:]

        func align() { while bin.count % 4 != 0 { bin.append(0) } }
        func addView(_ d: Data, target: Int?) -> Int {
            align()
            var v: [String: Any] = ["buffer": 0, "byteOffset": bin.count, "byteLength": d.count]
            if let target { v["target"] = target }
            bin.append(d); bufferViews.append(v); return bufferViews.count - 1
        }
        func floats(_ a: [Float]) -> Data { a.withUnsafeBufferPointer { Data(buffer: $0) } }

        func materialFor(_ m: SCNMaterial?) -> Int {
            guard let m else {
                if let i = materialIndex[ObjectIdentifier(SCNMaterial.self)] { return i }
                materials.append(["name": "Default", "pbrMetallicRoughness": ["baseColorFactor": [0.8, 0.8, 0.8, 1.0], "metallicFactor": 0.0, "roughnessFactor": 0.6]])
                materialIndex[ObjectIdentifier(SCNMaterial.self)] = materials.count - 1; return materials.count - 1
            }
            if let i = materialIndex[ObjectIdentifier(m)] { return i }
            var pbr: [String: Any] = [:]
            var color: [Double] = [1, 1, 1, Double(m.transparency)]
            if let c = m.diffuse.contents as? UIColor {
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0; c.getRed(&r, green: &g, blue: &b, alpha: &a)
                color = [Double(r), Double(g), Double(b), Double(a * m.transparency)]
            } else if let img = ViewerModel.thumbnailFull(m.diffuse.contents), let png = img.pngData() {
                let view = addView(png, target: nil)
                images.append(["bufferView": view, "mimeType": "image/png"])
                textures.append(["source": images.count - 1, "sampler": 0])
                pbr["baseColorTexture"] = ["index": textures.count - 1]
            }
            pbr["baseColorFactor"] = color
            pbr["metallicFactor"] = (m.metalness.contents as? NSNumber)?.doubleValue ?? 0
            pbr["roughnessFactor"] = (m.roughness.contents as? NSNumber)?.doubleValue ?? 0.6
            var mat: [String: Any] = ["name": m.name ?? "Material \(materials.count + 1)", "pbrMetallicRoughness": pbr, "doubleSided": m.isDoubleSided]
            if let e = m.emission.contents as? UIColor {
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0; e.getRed(&r, green: &g, blue: &b, alpha: &a)
                if r + g + b > 0.01 { mat["emissiveFactor"] = [min(1, Double(r)), min(1, Double(g)), min(1, Double(b))] }
            }
            if color[3] < 0.999 { mat["alphaMode"] = "BLEND" }
            materials.append(mat)
            materialIndex[ObjectIdentifier(m)] = materials.count - 1
            return materials.count - 1
        }

        var geoNodes: [SCNNode] = []
        for r in roots where !r.isHidden {
            r.enumerateHierarchy { n, stop in
                if n.isHidden { return }
                if n.geometry != nil, n.categoryBitMask & StudioModel.helperMask == 0, n.name != "joint-marker" { geoNodes.append(n) }
            }
        }
        let baseInv = base.simdWorldTransform.inverse
        for n in geoNodes {
            guard let g = n.geometry, let vs = g.sources(for: .vertex).first else { continue }
            let m = baseInv * n.simdWorldTransform
            let nm = simd_float3x3(SIMD3(m.columns.0.x, m.columns.0.y, m.columns.0.z), SIMD3(m.columns.1.x, m.columns.1.y, m.columns.1.z), SIMD3(m.columns.2.x, m.columns.2.y, m.columns.2.z)).inverse.transpose
            let pos = EditMesh.readVectors(vs, 3).map { v -> SIMD3<Float> in let p = m * SIMD4(v[0], v[1], v[2], 1); return SIMD3(p.x, p.y, p.z) }
            guard !pos.isEmpty else { continue }
            let nrm = g.sources(for: .normal).first.map { EditMesh.readVectors($0, 3).map { v -> SIMD3<Float> in let q = nm * SIMD3(v[0], v[1], v[2]); return simd_length(q) > 0 ? simd_normalize(q) : SIMD3(0, 1, 0) } }
            let uv = g.sources(for: .texcoord).first.map { EditMesh.readVectors($0, 2) }
            var lo = pos[0], hi = pos[0]; for p in pos { lo = simd_min(lo, p); hi = simd_max(hi, p) }

            var flat: [Float] = []; flat.reserveCapacity(pos.count * 3); for p in pos { flat += [p.x, p.y, p.z] }
            accessors.append(["bufferView": addView(floats(flat), target: 34962), "componentType": 5126, "count": pos.count, "type": "VEC3",
                              "min": [Double(lo.x), Double(lo.y), Double(lo.z)], "max": [Double(hi.x), Double(hi.y), Double(hi.z)]])
            var attributes: [String: Int] = ["POSITION": accessors.count - 1]
            if let nrm, nrm.count == pos.count {
                var f: [Float] = []; f.reserveCapacity(nrm.count * 3); for v in nrm { f += [v.x, v.y, v.z] }
                accessors.append(["bufferView": addView(floats(f), target: 34962), "componentType": 5126, "count": nrm.count, "type": "VEC3"])
                attributes["NORMAL"] = accessors.count - 1
            }
            if let uv, uv.count == pos.count {
                var f: [Float] = []; f.reserveCapacity(uv.count * 2); for v in uv { f += [v[0], v[1]] }
                accessors.append(["bufferView": addView(floats(f), target: 34962), "componentType": 5126, "count": uv.count, "type": "VEC2"])
                attributes["TEXCOORD_0"] = accessors.count - 1
            }
            var prims: [[String: Any]] = []
            let flipped = simd_determinant(m) < 0
            for (ei, e) in g.elements.enumerated() {
                let idx = EditMesh.readIndices(e)
                var tris: [UInt32] = []
                switch e.primitiveType {
                case .triangles: tris = idx.map { UInt32($0) }
                case .triangleStrip:
                    if idx.count >= 3 { for i in 0..<(idx.count - 2) { tris += (i % 2 == 0 ? [idx[i], idx[i + 1], idx[i + 2]] : [idx[i + 1], idx[i], idx[i + 2]]).map { UInt32($0) } } }
                default: continue
                }
                tris = tris.filter { Int($0) < pos.count }
                tris = Array(tris.prefix(tris.count - tris.count % 3))
                guard !tris.isEmpty else { continue }
                if flipped { for t in stride(from: 0, to: tris.count, by: 3) { tris.swapAt(t + 1, t + 2) } }
                let d = tris.withUnsafeBufferPointer { Data(buffer: $0) }
                accessors.append(["bufferView": addView(d, target: 34963), "componentType": 5125, "count": tris.count, "type": "SCALAR"])
                let mat = g.materials.isEmpty ? nil : g.materials[ei % g.materials.count]
                prims.append(["attributes": attributes, "indices": accessors.count - 1, "material": materialFor(mat)])
            }
            guard !prims.isEmpty else { continue }
            meshes.append(["name": n.name ?? "Mesh", "primitives": prims])
            nodes.append(["name": (n.name ?? "Mesh").replacingOccurrences(of: "studio:", with: "Object-"), "mesh": meshes.count - 1])
        }
        guard !nodes.isEmpty else { return nil }
        align()
        var json: [String: Any] = [
            "asset": ["version": "2.0", "generator": "Rig Viewer Studio"],
            "scene": 0, "scenes": [["nodes": Array(0..<nodes.count)]],
            "nodes": nodes, "meshes": meshes, "accessors": accessors, "bufferViews": bufferViews,
            "buffers": [["byteLength": bin.count]], "materials": materials,
        ]
        if !images.isEmpty { json["images"] = images; json["textures"] = textures; json["samplers"] = [["wrapS": 10497, "wrapT": 10497]] }
        guard var j = try? JSONSerialization.data(withJSONObject: json, options: []) else { return nil }
        while j.count % 4 != 0 { j.append(0x20) }
        var out = Data()
        func u32(_ v: Int) { var x = UInt32(v).littleEndian; withUnsafeBytes(of: &x) { out.append(contentsOf: $0) } }
        u32(0x46546C67); u32(2); u32(12 + 8 + j.count + 8 + bin.count)
        u32(j.count); u32(0x4E4F534A); out.append(j)
        u32(bin.count); u32(0x004E4942); out.append(bin)
        return out
    }
}
