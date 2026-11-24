import SwiftUI
import SceneKit
import simd

enum StudioMode: String, CaseIterable, Identifiable {
    case object = "Object", edit = "Edit", sculpt = "Sculpt", paint = "Paint", pose = "Pose"
    var id: String { rawValue }
    var title: String { self == .pose ? "Animate" : rawValue }
    var icon: String {
        switch self {
        case .object: return "cube"; case .edit: return "square.on.square.dashed"; case .sculpt: return "hand.point.up.braille"
        case .paint: return "paintbrush.fill"; case .pose: return "figure.wave"
        }
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
    case cube = "Cube", sphere = "UV Sphere", icosphere = "Ico Sphere", cylinder = "Cylinder", cone = "Cone", torus = "Torus", plane = "Plane", circle = "Circle", grid = "Grid"
    case capsule = "Capsule", pyramid = "Pyramid", tube = "Tube", roundedCube = "Rounded Cube", stairs = "Stairs", gear = "Gear", spring = "Spring", text = "Text"
    case clay = "Clay Ball"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .cube: return "cube"; case .sphere: return "circle"; case .icosphere: return "circle.hexagongrid"; case .cylinder: return "cylinder"
        case .cone: return "cone"; case .torus: return "circle.circle"; case .plane: return "square"; case .clay: return "hand.point.up.braille"
        case .circle: return "circle.dashed"; case .grid: return "grid"; case .capsule: return "capsule.portrait"; case .pyramid: return "pyramid"
        case .tube: return "smallcircle.circle"; case .roundedCube: return "app"; case .stairs: return "stairs"; case .gear: return "gearshape"
        case .spring: return "point.3.connected.trianglepath.dotted"; case .text: return "textformat"
        }
    }
    static let basic: [Primitive] = [.cube, .sphere, .icosphere, .cylinder, .cone, .torus, .plane, .circle, .grid]
    static let extra: [Primitive] = [.capsule, .pyramid, .tube, .roundedCube, .stairs, .gear, .spring, .text, .clay]

    /// Adjustable settings shown after adding (Blender's "Adjust Last Operation").
    var params: [OpParam] {
        switch self {
        case .cube: return [OpParam("Size", 1, 0.05...10)]
        case .sphere: return [OpParam("Radius", 0.5, 0.02...10), OpParam("Segments", 32, 3...128, step: 1), OpParam("Rings", 16, 2...64, step: 1)]
        case .icosphere: return [OpParam("Radius", 0.5, 0.02...10), OpParam("Subdivisions", 2, 0...5, step: 1)]
        case .cylinder: return [OpParam("Radius", 0.5, 0.02...10), OpParam("Depth", 1, 0.02...10), OpParam("Vertices", 32, 3...128, step: 1)]
        case .cone: return [OpParam("Radius", 0.5, 0.02...10), OpParam("Depth", 1, 0.02...10), OpParam("Vertices", 32, 3...128, step: 1)]
        case .torus: return [OpParam("Major Radius", 0.4, 0.05...10), OpParam("Minor Radius", 0.15, 0.01...5), OpParam("Segments", 32, 3...128, step: 1), OpParam("Sides", 16, 3...64, step: 1)]
        case .plane: return [OpParam("Size", 2, 0.05...50), OpParam("Subdivisions", 4, 1...64, step: 1)]
        case .circle: return [OpParam("Radius", 0.5, 0.02...10), OpParam("Vertices", 32, 3...128, step: 1)]
        case .grid: return [OpParam("Size", 2, 0.05...50), OpParam("Subdivisions", 10, 1...100, step: 1)]
        case .capsule: return [OpParam("Radius", 0.3, 0.02...5), OpParam("Height", 1.2, 0.05...10), OpParam("Segments", 24, 4...96, step: 1)]
        case .pyramid: return [OpParam("Size", 1, 0.05...10), OpParam("Height", 1, 0.05...10)]
        case .tube: return [OpParam("Outer Radius", 0.5, 0.02...10), OpParam("Inner Radius", 0.35, 0.01...10), OpParam("Height", 1, 0.02...10), OpParam("Vertices", 32, 3...128, step: 1)]
        case .roundedCube: return [OpParam("Size", 1, 0.05...10), OpParam("Corner Radius", 0.15, 0.01...2)]
        case .stairs: return [OpParam("Steps", 8, 1...40, step: 1), OpParam("Width", 1, 0.1...10), OpParam("Depth", 2, 0.1...20), OpParam("Height", 1.5, 0.1...20)]
        case .gear: return [OpParam("Teeth", 16, 6...64, step: 1), OpParam("Radius", 0.5, 0.05...10), OpParam("Tooth Depth", 0.08, 0.005...2), OpParam("Thickness", 0.15, 0.01...5)]
        case .spring: return [OpParam("Radius", 0.4, 0.02...5), OpParam("Wire", 0.06, 0.005...1), OpParam("Turns", 4, 0.5...30), OpParam("Height", 1.2, 0.05...20)]
        case .text: return [OpParam("Depth", 0.15, 0.0...2)]
        case .clay: return [OpParam("Radius", 0.5, 0.05...10), OpParam("Detail", 5, 3...6, step: 1)]
        }
    }

    func mesh(_ v: [Double] = [], text: String = "Text") -> EditMesh {
        let d = v.isEmpty ? params.map(\.value) : v
        func f(_ i: Int) -> Float { Float(i < d.count ? d[i] : params[i].value) }
        func n(_ i: Int) -> Int { Int((i < d.count ? d[i] : params[i].value).rounded()) }
        switch self {
        case .cube: return .cube(size: f(0))
        case .sphere: return .uvSphere(radius: f(0), segments: max(3, n(1)), rings: max(2, n(2)))
        case .icosphere: return .icosphere(radius: f(0), subdivisions: max(0, min(5, n(1))))
        case .cylinder: return .cylinder(radius: f(0), height: f(1), segments: max(3, n(2)))
        case .cone: return .cone(radius: f(0), height: f(1), segments: max(3, n(2)))
        case .torus: return .torus(major: f(0), minor: f(1), segments: max(3, n(2)), sides: max(3, n(3)))
        case .plane: return .plane(size: f(0), divisions: max(1, n(1)))
        case .circle: return .circle(radius: f(0), segments: max(3, n(1)))
        case .grid: return .grid(size: f(0), divisions: max(1, n(1)))
        case .capsule: return .capsule(radius: f(0), height: max(f(1), f(0) * 2), segments: max(4, n(2)))
        case .pyramid: return .pyramid(size: f(0), height: f(1))
        case .tube: return .tube(outer: max(f(0), f(1) + 0.005), inner: min(f(1), f(0) - 0.005), height: f(2), segments: max(3, n(3)))
        case .roundedCube: return .roundedCube(size: f(0), radius: min(f(1), f(0) / 2))
        case .stairs: return .stairs(steps: max(1, n(0)), width: f(1), depth: f(2), height: f(3))
        case .gear: return .gear(teeth: max(6, n(0)), radius: f(1), toothDepth: min(f(2), f(1) * 0.5), thickness: f(3), hole: f(1) * 0.25)
        case .spring: return .spring(radius: f(0), wire: f(1), turns: f(2), height: f(3))
        case .text: return .text(text, depth: max(0.001, f(0)))
        case .clay: return .clayBall(radius: f(0), level: max(3, min(6, n(1))))
        }
    }
}

/// One adjustable number of the last operation.
struct OpParam: Identifiable {
    var id: String { name }
    var name: String
    var value: Double
    var range: ClosedRange<Double>
    var step: Double? = nil
    init(_ name: String, _ value: Double, _ range: ClosedRange<Double>, step: Double? = nil) {
        self.name = name; self.value = value; self.range = range; self.step = step
    }
}

/// The last operation, kept so its numbers can be tweaked afterwards.
final class LastOperation {
    let title: String
    var params: [OpParam]
    let objectID: UUID
    let before: EditMesh
    let run: (inout EditMesh, [Double]) -> Void
    init(title: String, params: [OpParam], objectID: UUID, before: EditMesh, run: @escaping (inout EditMesh, [Double]) -> Void) {
        self.title = title; self.params = params; self.objectID = objectID; self.before = before; self.run = run
    }
}

enum LightKind: String, Codable, CaseIterable, Identifiable {
    case point = "Point", spot = "Spot", sun = "Sun", area = "Area"
    var id: String { rawValue }
    var icon: String { switch self { case .point: return "lightbulb.fill"; case .spot: return "flashlight.on.fill"; case .sun: return "sun.max.fill"; case .area: return "rectangle.inset.filled" } }
}

struct LightRecord: Codable, Equatable {
    var kind: LightKind = .point
    var r: Float = 1, g: Float = 0.96, b: Float = 0.9
    var intensity: Float = 1000
    var angle: Float = 45
    var shadows = true
    var color: Color {
        get { Color(red: Double(r), green: Double(g), blue: Double(b)) }
        set {
            let c = UIColor(newValue); var rr: CGFloat = 0, gg: CGFloat = 0, bb: CGFloat = 0, aa: CGFloat = 0
            c.getRed(&rr, green: &gg, blue: &bb, alpha: &aa)
            r = Float(min(max(rr, 0), 1)); g = Float(min(max(gg, 0), 1)); b = Float(min(max(bb, 0), 1))
        }
    }
}

enum ViewShading: String, CaseIterable, Identifiable {
    case solid = "Solid", material = "Material", wireframe = "Wireframe"
    var id: String { rawValue }
    var icon: String { switch self { case .solid: return "circle.fill"; case .material: return "circle.lefthalf.striped.horizontal"; case .wireframe: return "circle.dashed" } }
}

enum WorldBackground: String, Codable, CaseIterable, Identifiable {
    case studio = "Studio", sky = "Sky", sunset = "Sunset", night = "Night", color = "Colour", transparent = "Transparent"
    var id: String { rawValue }
}

struct WorldSettings: Codable, Equatable {
    var background: WorldBackground = .studio
    var r: Float = 0.12, g: Float = 0.12, b: Float = 0.14
    var environment: Float = 1.2
    var sun = true
    var sunIntensity: Float = 800
    var sunElevation: Float = 60
    var sunRotation: Float = 36
    var floorShadow = true
    var ambientOcclusion = true
}

enum ProceduralTexture: String, CaseIterable, Identifiable {
    case checker = "Checker", grid = "UV Grid", wood = "Wood", marble = "Marble", brick = "Brick", noise = "Noise", carbon = "Carbon", tiles = "Tiles"
    var id: String { rawValue }
}

struct MaterialRecord: Codable, Equatable {
    var r: Float = 0.82, g: Float = 0.82, b: Float = 0.84
    var roughness: Float = 0.5
    var metalness: Float = 0
    var emission: Float = 0
    var opacity: Float = 1
    var doubleSided = false
    var texture: String? = nil
    var tiling: Float? = nil

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
    var modifiers: [ModifierRecord] = []
    var light: LightRecord?
    var isImported: Bool { mesh == nil && light == nil }
    var isLight: Bool { light != nil }

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
    var modifiers: [ModifierRecord]? = nil
    var light: LightRecord? = nil
}

struct StudioProjectFile: Codable {
    var version = 2
    var name: String
    var objects: [ObjectRecord]
    var world: WorldSettings? = nil
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
