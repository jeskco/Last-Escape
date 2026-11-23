import SceneKit

/// Binary STL reader that keeps per-face colours (VisCAM/SolidView and Materialise "COLOR=" variants),
/// which Model I/O drops. ASCII STL returns nil so the caller can fall back to Model I/O.
enum STLLoader {
    static func load(_ url: URL) -> SCNScene? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe), data.count >= 84 else { return nil }
        let count = Int(data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 80, as: UInt32.self) })
        guard count > 0, data.count >= 84 + count * 50 else { return nil }   // ASCII or truncated

        var defaultColor = SIMD4<Float>(0.82, 0.82, 0.84, 1)
        var hasColors = false
        var materialise = false
        let header = Data(data.prefix(80))
        if let r = header.range(of: Data("COLOR=".utf8)) {
            let o = r.upperBound - header.startIndex
            if o + 4 <= 80 {
                defaultColor = SIMD4(Float(header[o]) / 255, Float(header[o + 1]) / 255, Float(header[o + 2]) / 255, Float(header[o + 3]) / 255)
                hasColors = true; materialise = true
            }
        }

        var positions = [SIMD3<Float>](); positions.reserveCapacity(count * 3)
        var normals = [SIMD3<Float>](); normals.reserveCapacity(count * 3)
        var colors = [SIMD4<Float>](); colors.reserveCapacity(count * 3)
        data.withUnsafeBytes { raw in
            for f in 0..<count {
                let o = 84 + f * 50
                func v(_ i: Int) -> SIMD3<Float> {
                    SIMD3(raw.loadUnaligned(fromByteOffset: o + i * 12, as: Float.self),
                          raw.loadUnaligned(fromByteOffset: o + i * 12 + 4, as: Float.self),
                          raw.loadUnaligned(fromByteOffset: o + i * 12 + 8, as: Float.self))
                }
                let a = v(1), b = v(2), c = v(3)
                var n = v(0)
                if simd_length(n) < 0.5 || !n.x.isFinite { let x = simd_cross(b - a, c - a); n = simd_length(x) > 0 ? simd_normalize(x) : SIMD3(0, 1, 0) }
                let attr = raw.loadUnaligned(fromByteOffset: o + 48, as: UInt16.self)
                var col = defaultColor
                if materialise {
                    if attr & 0x8000 == 0 { col = SIMD4(Float(attr & 0x1F) / 31, Float((attr >> 5) & 0x1F) / 31, Float((attr >> 10) & 0x1F) / 31, 1) }
                } else if attr & 0x8000 != 0 {
                    // VisCAM/SolidView: bit 15 set = valid colour
                    col = SIMD4(Float((attr >> 10) & 0x1F) / 31, Float((attr >> 5) & 0x1F) / 31, Float(attr & 0x1F) / 31, 1); hasColors = true
                }
                positions += [a, b, c]; normals += [n, n, n]; colors += [col, col, col]
            }
        }
        guard !positions.isEmpty else { return nil }
        let vCount = positions.count
        let pos = SCNGeometrySource(data: Data(bytes: positions.map { [$0.x, $0.y, $0.z] }.flatMap { $0 }, count: vCount * 12), semantic: .vertex, vectorCount: vCount, usesFloatComponents: true, componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0, dataStride: 12)
        let nrm = SCNGeometrySource(data: Data(bytes: normals.map { [$0.x, $0.y, $0.z] }.flatMap { $0 }, count: vCount * 12), semantic: .normal, vectorCount: vCount, usesFloatComponents: true, componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0, dataStride: 12)
        var sources = [pos, nrm]
        if hasColors {
            sources.append(SCNGeometrySource(data: Data(bytes: colors.map { [$0.x, $0.y, $0.z, $0.w] }.flatMap { $0 }, count: vCount * 16), semantic: .color, vectorCount: vCount, usesFloatComponents: true, componentsPerVector: 4, bytesPerComponent: 4, dataOffset: 0, dataStride: 16))
        }
        let indices = (0..<UInt32(vCount)).map { $0 }
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        let geo = SCNGeometry(sources: sources, elements: [element])
        let m = SCNMaterial(); m.lightingModel = .physicallyBased
        m.diffuse.contents = hasColors ? UIColor.white : UIColor(white: 0.8, alpha: 1)
        m.roughness.contents = 0.55; m.metalness.contents = 0.0; m.isDoubleSided = true
        m.name = hasColors ? "Vertex colours" : "STL"
        geo.materials = [m]
        geo.name = url.deletingPathExtension().lastPathComponent
        let scene = SCNScene()
        let node = SCNNode(geometry: geo); node.name = geo.name
        scene.rootNode.addChildNode(node)
        return scene
    }
}
