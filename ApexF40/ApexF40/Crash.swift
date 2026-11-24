import SceneKit
import UIKit
import simd

/// A car-sized rigid box that tumbles, rolls and bounces after a big hit ("ragdoll" crash physics).
struct RigidBox {
    var pos: SIMD3<Float>          // centre of mass (world)
    var vel: SIMD3<Float>
    var q: simd_quatf
    var w: SIMD3<Float>            // angular velocity (world)
    let half = SIMD3<Float>(0.95, 0.52, 2.15)
    let mass: Float = 1250
    let comHeight: Float = 0.58    // centre of mass above the car's ground origin
    private let invI: SIMD3<Float>
    var settle: Float = 0
    var age: Float = 0

    init(rootPos: SIMD3<Float>, q: simd_quatf, vel: SIMD3<Float>, w: SIMD3<Float>) {
        self.q = q
        self.pos = rootPos + q.act(SIMD3(0, 0.58, 0))
        self.vel = vel; self.w = w
        let m: Float = 1250, a: Float = 0.95, b: Float = 0.52, c: Float = 2.15
        invI = SIMD3(1 / (m / 3 * (b * b + c * c)), 1 / (m / 3 * (a * a + c * c)), 1 / (m / 3 * (a * a + b * b)))
    }

    var rootPosition: SIMD3<Float> { pos - q.act(SIMD3(0, comHeight, 0)) }
    var up: SIMD3<Float> { q.act(SIMD3(0, 1, 0)) }
    var forward: SIMD3<Float> { q.act(SIMD3(0, 0, 1)) }

    func invIWorld(_ v: SIMD3<Float>) -> SIMD3<Float> { q.act(q.inverse.act(v) * invI) }

    mutating func applyImpulse(_ j: SIMD3<Float>, at p: SIMD3<Float>) {
        vel += j / mass
        w += invIWorld(simd_cross(p - pos, j))
    }

    /// Returns the hardest impact speed this step.
    @discardableResult
    mutating func step(_ dt: Float, ground: (Float, Float) -> Float, collide: (SIMD2<Float>, Float) -> Contact?) -> Float {
        age += dt
        vel.y -= 9.81 * dt
        pos += vel * dt
        let wl = simd_length(w)
        if wl > 1e-5 { q = simd_normalize(simd_quatf(angle: wl * dt, axis: w / wl) * q) }
        var impact: Float = 0
        var maxPen: Float = 0
        let n = SIMD3<Float>(0, 1, 0)
        for sx: Float in [-1, 1] { for sy: Float in [-1, 1] { for sz: Float in [-1, 1] {
            let p = pos + q.act(SIMD3(sx, sy, sz) * half)
            let g = ground(p.x, p.z)
            let pen = g - p.y
            if pen <= 0 { continue }
            maxPen = max(maxPen, pen)
            let r = p - pos
            let vc = vel + simd_cross(w, r)
            let vn = simd_dot(vc, n)
            if vn < 0 {
                let k = 1 / mass + simd_dot(n, simd_cross(invIWorld(simd_cross(r, n)), r))
                let jn = -(1 + 0.22) * vn / k
                applyImpulse(n * jn, at: p)
                impact = max(impact, -vn)
                let vc2 = vel + simd_cross(w, r)
                let vt = vc2 - simd_dot(vc2, n) * n
                let vtl = simd_length(vt)
                if vtl > 1e-4 {
                    let t = vt / vtl
                    let kt = 1 / mass + simd_dot(t, simd_cross(invIWorld(simd_cross(r, t)), r))
                    let jt = min(vtl / kt, 0.65 * jn)
                    applyImpulse(-t * jt, at: p)
                }
            }
        } } }
        if maxPen > 0 { pos.y += maxPen * 0.8 }
        // Walls, buildings, trees
        if let c = collide(SIMD2(pos.x, pos.z), 1.35) {
            pos.x += c.normal.x * c.depth; pos.z += c.normal.y * c.depth
            let n3 = SIMD3<Float>(c.normal.x, 0, c.normal.y)
            let vn = simd_dot(vel, n3)
            if vn < 0 {
                let cp = SIMD3<Float>(c.point.x, pos.y, c.point.y)
                applyImpulse(n3 * (-(1.3) * vn * mass * 0.7), at: cp)
                impact = max(impact, -vn)
            }
        }
        vel *= 1 - 0.04 * dt
        w *= 1 - 0.35 * dt
        if simd_length(vel) < 0.7 && simd_length(w) < 0.7 { settle += dt } else { settle = 0 }
        return impact
    }
}

/// Small bits that fly off in a crash: body panels, glass, carbon.
final class DebrisField {
    private struct Piece { let node: SCNNode; var p: SIMD3<Float>; var v: SIMD3<Float>; var w: SIMD3<Float>; var life: Float }
    private var pieces: [Piece] = []
    let root = SCNNode()
    private lazy var glassMat: SCNMaterial = {
        let m = SCNMaterial(); m.lightingModel = .physicallyBased
        m.diffuse.contents = UIColor(white: 0.85, alpha: 0.55); m.roughness.contents = NSNumber(value: 0.05); m.metalness.contents = NSNumber(value: 0.2)
        m.transparency = 0.6; return m
    }()
    private lazy var carbonMat: SCNMaterial = {
        let m = SCNMaterial(); m.lightingModel = .physicallyBased
        m.diffuse.contents = UIColor(white: 0.06, alpha: 1); m.roughness.contents = NSNumber(value: 0.35); return m
    }()

    func burst(at p: SIMD3<Float>, velocity v: SIMD3<Float>, paint: UIColor, power: Float) {
        let n = Int(4 + power * 14)
        for k in 0..<n {
            let kind = k % 3
            let size = SIMD3<Float>(Float.random(in: 0.08...0.45), Float.random(in: 0.02...0.06), Float.random(in: 0.08...0.4)) * (kind == 1 ? 0.6 : 1)
            let g = SCNBox(width: CGFloat(size.x), height: CGFloat(size.y), length: CGFloat(size.z), chamferRadius: 0)
            if kind == 0 {
                let m = SCNMaterial(); m.lightingModel = .physicallyBased; m.diffuse.contents = paint; m.roughness.contents = NSNumber(value: 0.3)
                g.materials = [m]
            } else { g.materials = [kind == 1 ? glassMat : carbonMat] }
            let node = SCNNode(geometry: g); node.castsShadow = false
            root.addChildNode(node)
            let spread = SIMD3<Float>(Float.random(in: -1...1), Float.random(in: 0.3...1.4), Float.random(in: -1...1)) * (3 + power * 7)
            pieces.append(Piece(node: node, p: p + SIMD3(Float.random(in: -0.6...0.6), 0.4, Float.random(in: -0.6...0.6)), v: v * 0.6 + spread,
                                w: SIMD3(Float.random(in: -12...12), Float.random(in: -12...12), Float.random(in: -12...12)), life: Float.random(in: 7...11)))
        }
        if pieces.count > 90 {
            for p in pieces.prefix(pieces.count - 90) { p.node.removeFromParentNode() }
            pieces.removeFirst(pieces.count - 90)
        }
    }

    func update(_ dt: Float, ground: (Float, Float) -> Float) {
        var k = 0
        while k < pieces.count {
            var p = pieces[k]
            p.life -= dt
            if p.life <= 0 { p.node.removeFromParentNode(); pieces.remove(at: k); continue }
            p.v.y -= 9.81 * dt
            p.p += p.v * dt
            let g = ground(p.p.x, p.p.z) + 0.03
            if p.p.y < g { p.p.y = g; p.v.y = abs(p.v.y) * 0.3; p.v.x *= 0.6; p.v.z *= 0.6; p.w *= 0.6 }
            p.node.simdPosition = p.p
            let wl = simd_length(p.w)
            if wl > 1e-3 { p.node.simdOrientation = simd_quatf(angle: wl * dt, axis: p.w / wl) * p.node.simdOrientation }
            p.node.opacity = CGFloat(min(1, p.life))
            pieces[k] = p
            k += 1
        }
    }

    func clear() { for p in pieces { p.node.removeFromParentNode() }; pieces.removeAll() }
}
