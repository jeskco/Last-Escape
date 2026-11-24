import SwiftUI
import SceneKit
import simd

enum StudioMode: String, CaseIterable, Identifiable {
    case object = "Object", edit = "Edit", sculpt = "Sculpt", pose = "Pose"
    var id: String { rawValue }
    var icon: String {
        switch self { case .object: return "cube"; case .edit: return "square.on.square.dashed"; case .sculpt: return "hand.point.up.braille"; case .pose: return "figure.wave" }
    }
}

enum GizmoKind: String, CaseIterable, Identifiable {
    case move = "Move", rotate = "Rotate", scale = "Scale"
    var id: String { rawValue }
    var icon: String { switch self { case .move: return "arrow.up.and.down.and.arrow.left.and.right"; case .rotate: return "arrow.triangle.2.circlepath"; case .scale: return "arrow.up.left.and.arrow.down.right" } }
}

enum SelectMode: String, CaseIterable, Identifiable {
    case vertex = "Vertex", edge = "Edge", face = "Face"
    var id: String { rawValue }
    var icon: String { switch self { case .vertex: return "circle.grid.2x2.fill"; case .edge: return "line.diagonal"; case .face: return "square.fill" } }
}

enum Primitive: String, CaseIterable, Identifiable {
    case cube = "Cube", sphere = "Sphere", icosphere = "Ico Sphere", cylinder = "Cylinder", cone = "Cone", torus = "Torus", plane = "Plane", clay = "Clay Ball"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .cube: return "cube"; case .sphere: return "circle"; case .icosphere: return "circle.hexagongrid"; case .cylinder: return "cylinder"
        case .cone: return "cone"; case .torus: return "circle.circle"; case .plane: return "square"; case .clay: return "hand.point.up.braille"
        }
    }
    func mesh() -> EditMesh {
        switch self {
        case .cube: return .cube()
        case .sphere: return .uvSphere()
        case .icosphere: return .icosphere()
        case .cylinder: return .cylinder()
        case .cone: return .cone()
        case .torus: return .torus()
        case .plane: return .plane(size: 2, divisions: 4)
        case .clay: return .clayBall()
        }
    }
}

struct MaterialRecord: Codable, Equatable {
    var r: Float = 0.82, g: Float = 0.82, b: Float = 0.84
    var roughness: Float = 0.5
    var metalness: Float = 0
    var emission: Float = 0
    var opacity: Float = 1
    var doubleSided = false
    var texture: String? = nil

    var color: Color {
        get { Color(red: Double(r), green: Double(g), blue: Double(b)) }
        set {
            let c = UIColor(newValue); var rr: CGFloat = 0, gg: CGFloat = 0, bb: CGFloat = 0, aa: CGFloat = 0
            c.getRed(&rr, green: &gg, blue: &bb, alpha: &aa)
            r = Float(min(max(rr, 0), 1)); g = Float(min(max(gg, 0), 1)); b = Float(min(max(bb, 0), 1))
        }
    }

    static let presets: [(String, MaterialRecord)] = [
        ("Clay", MaterialRecord(r: 0.82, g: 0.76, b: 0.70, roughness: 0.75)),
        ("Plastic", MaterialRecord(r: 0.95, g: 0.95, b: 0.96, roughness: 0.35)),
        ("Red", MaterialRecord(r: 0.86, g: 0.16, b: 0.18, roughness: 0.4)),
        ("Blue", MaterialRecord(r: 0.14, g: 0.42, b: 0.95, roughness: 0.4)),
        ("Rubber", MaterialRecord(r: 0.08, g: 0.08, b: 0.09, roughness: 0.92)),
        ("Steel", MaterialRecord(r: 0.78, g: 0.79, b: 0.80, roughness: 0.28, metalness: 1)),
        ("Gold", MaterialRecord(r: 1.0, g: 0.77, b: 0.34, roughness: 0.25, metalness: 1)),
        ("Copper", MaterialRecord(r: 0.95, g: 0.55, b: 0.38, roughness: 0.3, metalness: 1)),
        ("Wood", MaterialRecord(r: 0.55, g: 0.36, b: 0.20, roughness: 0.7)),
        ("Ceramic", MaterialRecord(r: 0.97, g: 0.96, b: 0.93, roughness: 0.12)),
        ("Glass", MaterialRecord(r: 0.85, g: 0.93, b: 1.0, roughness: 0.04, opacity: 0.25, doubleSided: true)),
        ("Neon", MaterialRecord(r: 0.2, g: 1.0, b: 0.85, roughness: 0.3, emission: 1.6)),
    ]
}

struct TransformRecord: Codable {
    var position: SIMD3<Float>
    var orientation: SIMD4<Float>     // quaternion x y z w
    var scale: SIMD3<Float>

    init(_ n: SCNNode) {
        position = n.simdPosition
        let q = n.simdOrientation
        orientation = SIMD4(q.imag.x, q.imag.y, q.imag.z, q.real)
        scale = n.simdScale
    }
    func apply(to n: SCNNode) {
        n.simdPosition = position
        n.simdOrientation = simd_quatf(ix: orientation.x, iy: orientation.y, iz: orientation.z, r: orientation.w)
        n.simdScale = scale
    }
}

/// One thing in the Studio scene: an editable mesh, or a model brought in from the viewer.
final class StudioObject: Identifiable {
    let id: UUID
    var name: String
    var mesh: EditMesh?
    var material: MaterialRecord
    var textureImage: UIImage?
    let node: SCNNode
    var triangleFace: [Int32] = []
    var hidden = false
    var isImported: Bool { mesh == nil }

    init(id: UUID = UUID(), name: String, mesh: EditMesh?, material: MaterialRecord = MaterialRecord(), node: SCNNode = SCNNode()) {
        self.id = id; self.name = name; self.mesh = mesh; self.material = material; self.node = node
        node.name = "studio:" + id.uuidString
    }
}

struct ObjectRecord: Codable {
    var id: UUID
    var name: String
    var mesh: EditMesh?
    var material: MaterialRecord
    var transform: TransformRecord
    var hidden: Bool
}

struct StudioProjectFile: Codable {
    var version = 1
    var name: String
    var objects: [ObjectRecord]
}

struct StudioProjectSummary: Identifiable {
    let id: String
    let name: String
    let date: Date
    let thumbnail: UIImage?
    let objectCount: Int
}

struct PoseTransform { var p: SIMD3<Float>; var q: simd_quatf; var s: SIMD3<Float> }

struct PoseKey: Identifiable {
    let id = UUID()
    var time: Double
    var transforms: [ObjectIdentifier: PoseTransform]
}

/// Everything needed to undo one step.
struct StudioSnapshot {
    var objects: [ObjectRecord]
    var order: [UUID]
    var pose: [ObjectIdentifier: PoseTransform]
}

enum ExportFormat: String, CaseIterable, Identifiable {
    case usdz = "USDZ", glb = "GLB", obj = "OBJ", stl = "STL", ply = "PLY", usda = "USDA"
    var id: String { rawValue }
    var ext: String { rawValue.lowercased() }
    var detail: String {
        switch self {
        case .usdz: return "AR, Apple apps, Reality Composer"
        case .glb: return "Game engines, Blender, the web"
        case .obj: return "Universal mesh format"
        case .stl: return "3D printing"
        case .ply: return "Scanning and point tools"
        case .usda: return "Readable USD text for pipelines"
        }
    }
}
