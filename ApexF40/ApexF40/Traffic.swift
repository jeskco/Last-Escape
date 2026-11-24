import SceneKit
import UIKit
import simd

struct Lane {
    var pts: [SIMD3<Float>]
    var cum: [Float]
    var length: Float
    var speed: Float
    var minX: Float, minZ: Float, maxX: Float, maxZ: Float

    init(_ p: [SIMD3<Float>], speed: Float) {
        pts = p; self.speed = speed
        var c: [Float] = [0]; c.reserveCapacity(p.count)
        for k in 1..<max(1, p.count) { c.append(c[k - 1] + simd_distance(SIMD2(p[k].x, p[k].z), SIMD2(p[k - 1].x, p[k - 1].z))) }
        cum = c; length = c.last ?? 0
        minX = p.map(\.x).min() ?? 0; maxX = p.map(\.x).max() ?? 0; minZ = p.map(\.z).min() ?? 0; maxZ = p.map(\.z).max() ?? 0
    }

    func distance(to c: SIMD2<Float>) -> Float {
        let dx = max(minX - c.x, 0, c.x - maxX), dz = max(minZ - c.y, 0, c.y - maxZ)
        return (dx * dx + dz * dz).squareRoot()
    }

    /// Position and heading at distance s; `seg` is a cursor kept by the caller.
    func sample(_ s: Float, seg: inout Int) -> (SIMD3<Float>, Float) {
        seg = max(0, min(seg, pts.count - 2))
        while seg < pts.count - 2 && cum[seg + 1] < s { seg += 1 }
        while seg > 0 && cum[seg] > s { seg -= 1 }
        let a = pts[seg], b = pts[seg + 1]
        let l = max(cum[seg + 1] - cum[seg], 1e-3)
        let t = min(max((s - cum[seg]) / l, 0), 1)
        let p = a + (b - a) * t
        return (p, atan2(b.x - a.x, b.z - a.z))
    }
}

final class TrafficCar {
    let rig: CarRig
    var lane: Int
    var s: Float
    var seg = 0
    var speed: Float
    var pos = SIMD3<Float>(0, 0, 0)
    var heading: Float = 0
    var crash: RigidBox?
    var blocked: Float = 0
    var braking = false
    var paint: UIColor
    init(rig: CarRig, lane: Int, s: Float, speed: Float, paint: UIColor) { self.rig = rig; self.lane = lane; self.s = s; self.speed = speed; self.paint = paint }
    var velocity: SIMD3<Float> {
        if let c = crash { return c.vel }
        return SIMD3(sin(heading), 0, cos(heading)) * speed
    }
}

/// Cars driving the highways and city grids around the player.
final class Traffic {
    private(set) var lanes: [Lane] = []
    private(set) var cars: [TrafficCar] = []
    let root = SCNNode()
    private let template: SCNNode
    private var paintMats: [(UIColor, SCNMaterial)] = []
    private var nearby: [Int] = []
    private var nearbyTimer: Float = 0
    private var spawnTimer: Float = 0

    static let palette: [UIColor] = [
        UIColor(red: 0.72, green: 0.05, blue: 0.03, alpha: 1), UIColor(white: 0.93, alpha: 1), UIColor(white: 0.06, alpha: 1),
        UIColor(red: 0.96, green: 0.77, blue: 0, alpha: 1), UIColor(red: 0.07, green: 0.23, blue: 0.55, alpha: 1), UIColor(red: 0.43, green: 0.45, blue: 0.47, alpha: 1),
        UIColor(red: 0.06, green: 0.29, blue: 0.17, alpha: 1), UIColor(red: 1, green: 0.35, blue: 0.05, alpha: 1), UIColor(red: 0.37, green: 0.71, blue: 0.9, alpha: 1),
        UIColor(red: 0.75, green: 0.75, blue: 0.78, alpha: 1),
    ]

    init(meta: WorldMeta, template: SCNNode) {
        self.template = template
        root.name = "TrafficRoot"
        for c in Traffic.palette {
            let m = SCNMaterial(); m.name = "Paint"; m.lightingModel = .physicallyBased
            m.diffuse.contents = c; m.metalness.contents = NSNumber(value: 0.45); m.roughness.contents = NSNumber(value: 0.25)
            m.clearCoat.contents = NSNumber(value: 1); m.clearCoatRoughness.contents = NSNumber(value: 0.05)
            paintMats.append((c, m))
        }
        buildLanes(meta)
    }

    private static func offsetLine(_ p: [SIMD3<Float>], right off: Float) -> [SIMD3<Float>] {
        var out: [SIMD3<Float>] = []
        out.reserveCapacity(p.count)
        for k in 0..<p.count {
            let a = p[max(0, k - 1)], b = p[min(p.count - 1, k + 1)]
            var t = SIMD2<Float>(b.x - a.x, b.z - a.z)
            let l = simd_length(t); if l > 1e-4 { t /= l }
            let right = SIMD2<Float>(-t.y, t.x)
            out.append(SIMD3(p[k].x + right.x * off, p[k].y + 0.05, p[k].z + right.y * off))
        }
        return out
    }

    private func buildLanes(_ meta: WorldMeta) {
        for h in meta.highways {
            guard h.pts.count >= 2, h.y.count == h.pts.count else { continue }
            let p = zip(h.pts, h.y).map { SIMD3<Float>($0[0], $1, $0[1]) }
            let offs: [Float] = h.kind == "highway" ? [3.2, 7.5, 11.8] : [3.0]
            let speed: Float = h.kind == "highway" ? 31 : 22
            for o in offs {
                lanes.append(Lane(Traffic.offsetLine(p, right: o), speed: speed + Float.random(in: -2...2)))
                lanes.append(Lane(Traffic.offsetLine(p.reversed(), right: o), speed: speed + Float.random(in: -2...2)))
            }
        }
        for c in meta.cities {
            guard let z0 = c.zs.first, let z1 = c.zs.last, let x0 = c.xs.first, let x1 = c.xs.last else { continue }
            let y = c.base
            for (i, x) in c.xs.enumerated() {
                let w = i < c.xw.count ? c.xw[i] : 12
                let line = stride(from: z0, through: z1, by: 10).map { SIMD3<Float>(x, y, $0) }
                guard line.count >= 2 else { continue }
                lanes.append(Lane(Traffic.offsetLine(line, right: w / 4), speed: 15))
                lanes.append(Lane(Traffic.offsetLine(line.reversed(), right: w / 4), speed: 15))
            }
            for (j, z) in c.zs.enumerated() {
                let w = j < c.zw.count ? c.zw[j] : 12
                let line = stride(from: x0, through: x1, by: 10).map { SIMD3<Float>($0, y, z) }
                guard line.count >= 2 else { continue }
                lanes.append(Lane(Traffic.offsetLine(line, right: w / 4), speed: 15))
                lanes.append(Lane(Traffic.offsetLine(line.reversed(), right: w / 4), speed: 15))
            }
        }
    }

    private var fill = true

    func clear() {
        for c in cars { c.rig.root.removeFromParentNode() }
        cars.removeAll()
        fill = true; nearbyTimer = 0
    }

    private func spawn(player p: SIMD2<Float>, camForward: SIMD2<Float>, initial: Bool) {
        guard !nearby.isEmpty else { return }
        for _ in 0..<12 {
            let li = nearby.randomElement()!
            let lane = lanes[li]
            guard lane.pts.count > 2 else { continue }
            let k = Int.random(in: 0..<(lane.pts.count - 1))
            let q = lane.pts[k]
            let d = simd_distance(SIMD2(q.x, q.z), p)
            let minD: Float = initial ? 40 : 140
            if d < minD || d > 480 { continue }
            let dir = simd_normalize(SIMD2(q.x, q.z) - p)
            if !initial && d < 260 && simd_dot(dir, camForward) > 0.2 { continue }   // don't pop in where the player is looking
            // keep clear of other cars on the same lane
            let s = lane.cum[k]
            if cars.contains(where: { $0.lane == li && abs($0.s - s) < 25 }) { continue }
            let (c, m) = paintMats.randomElement()!
            let rig = CarRig(template: template, lite: true, paint: m)
            let car = TrafficCar(rig: rig, lane: li, s: s, speed: lane.speed * 0.8, paint: c)
            car.seg = k
            root.addChildNode(rig.root)
            cars.append(car)
            return
        }
    }

    /// Advances every car. `obstacles` are other moving things (the player) the AI should not drive into.
    func update(_ dt: Float, player p: SIMD3<Float>, playerVel: SIMD3<Float>, camForward: SIMD2<Float>, density: Int, night: Float,
                ground: (Float, Float) -> Float, collide: (SIMD2<Float>, Float) -> Contact?) {
        let p2 = SIMD2(p.x, p.z)
        nearbyTimer -= dt
        if nearbyTimer <= 0 {
            nearbyTimer = 1.5
            nearby = lanes.indices.filter { lanes[$0].distance(to: p2) < 450 }
        }
        // Spawn / despawn
        spawnTimer -= dt
        if fill {
            for _ in 0..<4 where cars.count < density { spawn(player: p2, camForward: camForward, initial: true) }
            if cars.count >= density || nearby.isEmpty { fill = false }
        } else if cars.count < density && spawnTimer <= 0 {
            spawn(player: p2, camForward: camForward, initial: false)
            spawnTimer = 0.15
        }
        let n = cars.count
        cars.removeAll { car in
            let d = simd_distance(SIMD2(car.pos.x, car.pos.z), p2)
            let gone = d > 560 || (car.crash != nil && car.crash!.age > 14 && d > 60) || n > density + 4 && d > 200
            if gone { car.rig.root.removeFromParentNode() }
            return gone
        }
        let pf = SIMD2<Float>(playerVel.x, playerVel.z)
        for car in cars {
            if var box = car.crash {
                for _ in 0..<2 { box.step(dt / 2, ground: ground, collide: collide) }
                car.crash = box
                car.pos = box.rootPosition
                car.rig.root.simdPosition = box.rootPosition
                car.rig.root.simdOrientation = box.q
                car.speed = simd_length(box.vel)
                car.rig.update(dt, RigState(wheelSpeed: simd_length(box.vel) * 0.5, braking: false, headlights: night > 0.5 ? 1 : 0, night: night, hazard: true))
                continue
            }
            let lane = lanes[car.lane]
            let fwd = SIMD2<Float>(sin(car.heading), cos(car.heading))
            // Look ahead for anything in our path
            var gap: Float = 1000
            let me = SIMD2(car.pos.x, car.pos.z)
            for o in cars where o !== car {
                let r = SIMD2(o.pos.x, o.pos.z) - me
                let along = simd_dot(r, fwd)
                if along <= 0 || along > 30 { continue }
                let lat = abs(r.x * fwd.y - r.y * fwd.x)
                if lat < 2.4 { gap = min(gap, along) }
            }
            do {
                let r = p2 - me
                let along = simd_dot(r, fwd), lat = abs(r.x * fwd.y - r.y * fwd.x)
                if along > 0 && along < 34 && lat < 2.8 && simd_dot(pf, fwd) < car.speed + 2 { gap = min(gap, along) }
            }
            var target = lane.speed * min(1, max(0, (gap - 7) / 16))
            if gap < 900 && target < 0.5 { car.blocked += dt } else { car.blocked = 0 }
            if car.blocked > 5 { target = lane.speed * 0.4 }       // unstick crossing deadlocks
            let accel: Float = target > car.speed ? 2.8 : 9
            car.speed += max(-accel * dt, min(accel * dt, target - car.speed))
            car.braking = target < car.speed - 0.5 || car.speed < 0.5
            car.s += car.speed * dt
            if car.s >= lane.length - 1 {
                car.rig.root.removeFromParentNode()
                car.s = -1            // flagged for removal below
            }
            if car.s < 0 { continue }
            let (pos, h) = lane.sample(car.s, seg: &car.seg)
            car.pos = pos
            var dh = h - car.heading
            while dh > .pi { dh -= 2 * .pi }; while dh < -.pi { dh += 2 * .pi }
            car.heading += dh * min(1, dt * 8)
            car.rig.root.simdPosition = pos
            car.rig.root.simdOrientation = simd_quatf(angle: car.heading, axis: [0, 1, 0])
            car.rig.update(dt, RigState(steer: clampf(dh * 2, -0.5, 0.5), wheelSpeed: car.speed, braking: car.braking, headlights: night > 0.45 ? 1 : 0, night: night))
        }
        cars.removeAll { $0.s < 0 && $0.crash == nil }
    }

    /// Knock a traffic car into a tumble.
    func launch(_ car: TrafficCar, impulse: SIMD3<Float>, at point: SIMD3<Float>) {
        if car.crash == nil {
            let q = simd_quatf(angle: car.heading, axis: [0, 1, 0])
            car.crash = RigidBox(rootPos: car.pos, q: q, vel: car.velocity, w: .zero)
        }
        car.crash!.applyImpulse(impulse, at: point)
    }
}
