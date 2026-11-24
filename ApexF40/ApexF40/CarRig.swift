import SceneKit
import UIKit
import simd

struct RigState {
    var steer: Float = 0
    var wheelSpeed: Float = 0
    var wheelspin: Float = 0
    var locked = false
    var braking = false
    var reverse = false
    var longAccel: Float = 0
    var latAccel: Float = 0
    var headlights: Float = 0
    var night: Float = 0
    var indicator = 0          // -1 left, 1 right
    var hazard = false
    var backfire = false
    var bump: Float = 0
    var smoke: Float = 0
    var dust: Float = 0
}

enum FX {
    static let glowImage: UIImage = {
        let s = 128
        let r = UIGraphicsImageRenderer(size: CGSize(width: s, height: s), format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; f.opaque = false; return f }())
        return r.image { ctx in
            let cs = CGColorSpaceCreateDeviceRGB()
            let colors = [UIColor(white: 1, alpha: 1).cgColor, UIColor(white: 1, alpha: 0.85).cgColor, UIColor(white: 1, alpha: 0.25).cgColor, UIColor(white: 1, alpha: 0).cgColor] as CFArray
            let g = CGGradient(colorsSpace: cs, colors: colors, locations: [0, 0.18, 0.45, 1])!
            ctx.cgContext.drawRadialGradient(g, startCenter: CGPoint(x: s / 2, y: s / 2), startRadius: 0, endCenter: CGPoint(x: s / 2, y: s / 2), endRadius: CGFloat(s / 2), options: [])
        }
    }()

    static func glow(_ color: UIColor, size: CGFloat) -> SCNNode {
        let p = SCNPlane(width: size, height: size)
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = glowImage
        m.multiply.contents = color
        m.blendMode = .add
        m.writesToDepthBuffer = false
        m.isDoubleSided = true
        p.materials = [m]
        let n = SCNNode(geometry: p)
        n.constraints = [SCNBillboardConstraint()]
        n.renderingOrder = 20
        n.castsShadow = false
        n.opacity = 0
        return n
    }

    static func smoke() -> SCNParticleSystem {
        let ps = SCNParticleSystem()
        ps.particleImage = glowImage
        ps.birthRate = 0
        ps.particleLifeSpan = 1.7
        ps.particleLifeSpanVariation = 0.5
        ps.particleSize = 0.55
        ps.particleColor = UIColor(white: 0.88, alpha: 0.28)
        ps.spreadingAngle = 50
        ps.emittingDirection = SCNVector3(0, 1, 0)
        ps.particleVelocity = 1.4
        ps.particleVelocityVariation = 0.8
        ps.acceleration = SCNVector3(0, 0.5, 0)
        ps.blendMode = .alpha
        ps.isLightingEnabled = false
        ps.sortingMode = .distance
        let grow = CAKeyframeAnimation(); grow.values = [0.4, 1.6, 3.6]; grow.keyTimes = [0, 0.3, 1]
        let fade = CAKeyframeAnimation(); fade.values = [0.0, 1.0, 0.0]; fade.keyTimes = [0, 0.12, 1]
        ps.propertyControllers = [.size: SCNParticlePropertyController(animation: grow), .opacity: SCNParticlePropertyController(animation: fade)]
        return ps
    }

    static func sparks() -> SCNParticleSystem {
        let ps = SCNParticleSystem()
        ps.particleImage = glowImage
        ps.birthRate = 2600
        ps.emissionDuration = 0.08
        ps.loops = false
        ps.particleLifeSpan = 0.55
        ps.particleLifeSpanVariation = 0.3
        ps.particleSize = 0.09
        ps.particleColor = UIColor(red: 1, green: 0.7, blue: 0.3, alpha: 1)
        ps.spreadingAngle = 80
        ps.particleVelocity = 9
        ps.particleVelocityVariation = 6
        ps.isAffectedByGravity = true
        ps.blendMode = .additive
        ps.isLightingEnabled = false
        ps.stretchFactor = 0.04
        return ps
    }

    static func dustBurst() -> SCNParticleSystem {
        let ps = smoke()
        ps.birthRate = 400
        ps.emissionDuration = 0.15
        ps.loops = false
        ps.particleVelocity = 4
        ps.particleColor = UIColor(red: 0.55, green: 0.48, blue: 0.4, alpha: 0.4)
        return ps
    }
}

/// One car's visuals: steering and spinning wheels, sprung body, every lamp, smoke.
final class CarRig {
    let root = SCNNode()
    let lite: Bool
    private(set) var body: SCNNode?
    private var bodyBase = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
    private var bodyBaseY: Float = 0.3
    private struct Wheel { let pivot: SCNNode?; let spin: SCNNode?; let pivotBase: simd_quatf; let spinBase: simd_quatf; var angle: Float }
    private var wheels: [Wheel] = []
    private(set) var paintMats: [SCNMaterial] = []
    private var rimMats: [SCNMaterial] = []
    private var tailMats: [SCNMaterial] = []
    private var headMats: [SCNMaterial] = []
    private var discMats: [SCNMaterial] = []
    private var glowTail: [SCNNode] = [], glowRev: [SCNNode] = [], glowHead: [SCNNode] = [], glowIndL: [SCNNode] = [], glowIndR: [SCNNode] = [], glowFlame: [SCNNode] = []
    private var spots: [SCNLight] = []
    private var brakeLamp: SCNLight?
    private var smokeSystems: [SCNParticleSystem] = []
    private var pitch: Float = 0, roll: Float = 0, pitchV: Float = 0, rollV: Float = 0
    private var heat: Float = 0, blink: Float = 0, flameT: Float = 0
    private var brakeL: Float = 0, headL: Float = 0

    static let tailShader = """
    #pragma arguments
    float uTail;
    float uBrake;
    float uRev;
    float uIndL;
    float uIndR;
    #pragma body
    float3 lc = _surface.emission.rgb;
    float red = step(0.12, lc.r) * step(lc.g, lc.r * 0.42);
    float orange = step(0.35, lc.r) * step(lc.r * 0.42, lc.g) * step(lc.g, lc.r * 0.9) * (1.0 - step(0.55, lc.b));
    float white = step(0.55, min(lc.r, min(lc.g, lc.b)));
    float3 wp = (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz;
    float3 lp = (scn_node.inverseModelTransform * float4(wp, 1.0)).xyz;
    float ind = lp.x > 0.0 ? uIndL : uIndR;
    float3 e = lc * red * (uTail * 2.0 + uBrake * 9.0) + lc * orange * ind * 9.0 + float3(1.0, 0.97, 0.92) * white * uRev * 5.0 + lc * 0.03;
    _surface.emission = float4(e, 1.0);
    """

    /// Prepares a freshly loaded template once (shared by every clone).
    static func prepareTemplate(_ t: SCNNode) {
        t.enumerateHierarchy { n, _ in
            guard let g = n.geometry else { return }
            for m in g.materials {
                let name = m.name ?? ""
                if name == "RearLights" {
                    m.emission.intensity = 1
                    m.shaderModifiers = [.surface: tailShader]
                    for (k, v) in [("uTail", 0.3), ("uBrake", 0.0), ("uRev", 0.0), ("uIndL", 0.0), ("uIndR", 0.0)] { m.setValue(NSNumber(value: v), forKey: k) }
                }
                if name == "Headlight" || name == "hl_inside" {
                    m.emission.contents = UIColor(red: 1, green: 0.97, blue: 0.88, alpha: 1)
                    m.emission.intensity = 0
                }
                if m.transparency < 1 || name.lowercased().contains("glass") { n.castsShadow = false }
            }
        }
    }

    init(template: SCNNode, lite: Bool, paint: SCNMaterial? = nil) {
        self.lite = lite
        let model = template.clone()
        root.addChildNode(model)
        root.name = lite ? "Traffic" : "Player"
        // Per-instance materials where they change per car.
        model.enumerateHierarchy { n, _ in
            guard let g0 = n.geometry else { return }
            let names = g0.materials.map { $0.name ?? "" }
            let wantsOwn = lite ? names.contains("Paint") : names.contains { ["Paint", "material", "RearLights", "Headlight", "hl_inside", "BrakeDisc1"].contains($0) }
            if wantsOwn, let g = g0.copy() as? SCNGeometry {
                g.materials = g0.materials.map { m in
                    let nm = m.name ?? ""
                    if nm == "Paint", let paint { return paint }
                    if !lite && ["Paint", "material", "RearLights", "Headlight", "hl_inside", "BrakeDisc1"].contains(nm) { return (m.copy() as? SCNMaterial) ?? m }
                    return m
                }
                n.geometry = g
            }
            for m in n.geometry?.materials ?? [] {
                switch m.name ?? "" {
                case "Paint": if !paintMats.contains(m) { paintMats.append(m) }
                case "material": if !rimMats.contains(m) { rimMats.append(m) }
                case "RearLights": if !tailMats.contains(m) { tailMats.append(m) }
                case "Headlight", "hl_inside": if !headMats.contains(m) { headMats.append(m) }
                case "BrakeDisc1": if !discMats.contains(m) { discMats.append(m) }
                default: break
                }
            }
            if lite { n.castsShadow = false }
        }
        body = model.childNode(withName: "Body", recursively: true)
        if let body { bodyBase = body.simdOrientation; bodyBaseY = body.simdPosition.y }
        for k in ["FL", "FR", "RL", "RR"] {
            let p = model.childNode(withName: "Wheel_" + k, recursively: true)
            let s = model.childNode(withName: "Wheel_" + k + "_Spin", recursively: true)
            wheels.append(Wheel(pivot: p, spin: s, pivotBase: p?.simdOrientation ?? simd_quatf(ix: 0, iy: 0, iz: 0, r: 1), spinBase: s?.simdOrientation ?? simd_quatf(ix: 0, iy: 0, iz: 0, r: 1), angle: 0))
        }
        buildGlows(model)
    }

    private func buildGlows(_ model: SCNNode) {
        let host = body ?? root
        let hostPos = body?.simdPosition ?? .zero
        var tx: Float = 0.75, ty: Float = 0.6, tz: Float = -2.17
        if let tail = model.childNode(withName: "TailLamps", recursively: true) {
            let (mn, mx) = tail.boundingBox
            var minZ: Float = .greatestFiniteMagnitude, maxY: Float = -.greatestFiniteMagnitude, maxX: Float = -.greatestFiniteMagnitude
            for cx in [mn.x, mx.x] { for cy in [mn.y, mx.y] { for cz in [mn.z, mx.z] {
                let p = tail.simdConvertPosition(SIMD3(Float(cx), Float(cy), Float(cz)), to: root)
                minZ = min(minZ, p.z); maxY = max(maxY, p.y); maxX = max(maxX, p.x)
            } } }
            if minZ.isFinite && minZ < -1 { tx = maxX; ty = maxY - 0.08; tz = minZ - 0.02 }
        }
        func add(_ n: SCNNode, _ p: SIMD3<Float>) { n.simdPosition = p - hostPos; host.addChildNode(n) }
        for s: Float in [1, -1] {
            let t = FX.glow(UIColor(red: 1, green: 0.1, blue: 0.06, alpha: 1), size: 0.55); add(t, [s * (tx - 0.12), ty, tz]); glowTail.append(t)
            let ind = FX.glow(UIColor(red: 1, green: 0.54, blue: 0, alpha: 1), size: 0.42); add(ind, [s * (tx - 0.32), ty, tz]); if s > 0 { glowIndL.append(ind) } else { glowIndR.append(ind) }
            if !lite {
                let rv = FX.glow(.white, size: 0.3); add(rv, [s * (tx - 0.32), ty, tz]); glowRev.append(rv)
                let fi = FX.glow(UIColor(red: 1, green: 0.54, blue: 0, alpha: 1), size: 0.35); add(fi, [s * 0.82, 0.5, 1.68]); if s > 0 { glowIndL.append(fi) } else { glowIndR.append(fi) }
            }
            let h = FX.glow(UIColor(red: 1, green: 0.96, blue: 0.86, alpha: 1), size: lite ? 0.7 : 0.9); add(h, [s * 0.62, 0.43, 1.74]); glowHead.append(h)
        }
        if !lite {
            for x: Float in [-0.13, 0, 0.13] { let f = FX.glow(UIColor(red: 1, green: 0.48, blue: 0.12, alpha: 1), size: 0.32); add(f, [x, 0.36, -2.3]); glowFlame.append(f) }
            for s: Float in [1, -1] {
                let l = SCNLight(); l.type = .spot; l.color = UIColor(red: 1, green: 0.95, blue: 0.84, alpha: 1)
                l.spotInnerAngle = 18; l.spotOuterAngle = 58; l.attenuationStartDistance = 0; l.attenuationEndDistance = 95; l.attenuationFalloffExponent = 1.6
                l.intensity = 0; l.castsShadow = false
                let n = SCNNode(); n.light = l
                n.simdPosition = [s * 0.62, 0.55, 1.6]
                n.simdOrientation = simd_quatf(angle: .pi, axis: [0, 1, 0]) * simd_quatf(angle: -0.06, axis: [1, 0, 0])
                root.addChildNode(n); spots.append(l)
            }
            let bl = SCNLight(); bl.type = .omni; bl.color = UIColor(red: 1, green: 0.12, blue: 0.06, alpha: 1)
            bl.attenuationStartDistance = 0; bl.attenuationEndDistance = 8; bl.intensity = 0
            let bn = SCNNode(); bn.light = bl; bn.simdPosition = [0, 0.7, -2.7]; root.addChildNode(bn); brakeLamp = bl
            for s: Float in [1, -1] {
                let n = SCNNode(); n.simdPosition = [s * 0.8, 0.15, -1.25]
                let ps = FX.smoke(); n.addParticleSystem(ps); root.addChildNode(n); smokeSystems.append(ps)
            }
        }
    }

    func setPaint(_ color: UIColor, metal: Float, rough: Float) {
        for m in paintMats {
            m.lightingModel = .physicallyBased
            m.diffuse.contents = color
            m.metalness.contents = NSNumber(value: metal)
            m.roughness.contents = NSNumber(value: rough)
            m.clearCoat.contents = NSNumber(value: 1)
            m.clearCoatRoughness.contents = NSNumber(value: 0.04)
        }
    }

    func setRims(_ color: UIColor, metal: Float) {
        for m in rimMats { m.diffuse.contents = color; m.metalness.contents = NSNumber(value: metal); m.roughness.contents = NSNumber(value: 0.22) }
    }

    func update(_ dt: Float, _ s: RigState) {
        // Steering
        for k in 0..<2 { if let p = wheels[k].pivot { p.simdOrientation = wheels[k].pivotBase * simd_quatf(angle: s.steer, axis: [0, 1, 0]) } }
        // Spin
        for k in 0..<4 {
            var speed = s.wheelSpeed
            if k >= 2 { speed += s.wheelspin }
            if s.locked && k < 2 { speed *= 0.15 }
            wheels[k].angle += speed / 0.32 * dt
            if wheels[k].angle > 1000 { wheels[k].angle -= 2 * .pi * 159 }
            if let sp = wheels[k].spin { sp.simdOrientation = wheels[k].spinBase * simd_quatf(angle: wheels[k].angle, axis: [1, 0, 0]) }
        }
        // Body on springs
        let tp = clampf(-s.longAccel * 0.0055, -0.05, 0.05), tr = clampf(s.latAccel * 0.0045, -0.06, 0.06)
        pitchV += ((tp - pitch) * 90 - pitchV * 11) * dt; pitch += pitchV * dt
        rollV += ((tr - roll) * 80 - rollV * 10) * dt; roll += rollV * dt
        if let body {
            body.simdOrientation = bodyBase * simd_quatf(angle: pitch, axis: [1, 0, 0]) * simd_quatf(angle: roll, axis: [0, 0, 1])
            var p = body.simdPosition; p.y = bodyBaseY - abs(pitch) * 0.4 + s.bump; body.simdPosition = p
        }
        // Lights
        blink += dt
        let blinkOn: Float = blink.truncatingRemainder(dividingBy: 0.8) < 0.42 ? 1 : 0
        let indL: Float = (s.hazard || s.indicator < 0) ? blinkOn : 0, indR: Float = (s.hazard || s.indicator > 0) ? blinkOn : 0
        brakeL += ((s.braking ? 1 : 0) - brakeL) * min(1, dt * 25)
        headL += (s.headlights - headL) * min(1, dt * 10)
        let tail: Float = s.headlights > 0.5 ? 1 : 0.3
        for m in tailMats {
            m.setValue(NSNumber(value: tail), forKey: "uTail"); m.setValue(NSNumber(value: brakeL), forKey: "uBrake")
            m.setValue(NSNumber(value: s.reverse ? 1 : 0), forKey: "uRev"); m.setValue(NSNumber(value: indL), forKey: "uIndL"); m.setValue(NSNumber(value: indR), forKey: "uIndR")
        }
        let nightK: Float = 0.3 + 0.7 * s.night
        for g in glowTail { g.opacity = CGFloat((tail * 0.35 + brakeL * 0.9) * nightK) }
        for g in glowRev { g.opacity = CGFloat((s.reverse ? 0.9 : 0) * nightK) }
        for g in glowIndL { g.opacity = CGFloat(indL * 0.85 * nightK) }
        for g in glowIndR { g.opacity = CGFloat(indR * 0.85 * nightK) }
        for g in glowHead { g.opacity = CGFloat(headL * (0.35 + 0.65 * s.night)) }
        for m in headMats { m.emission.intensity = CGFloat(headL * 2.5) }
        for l in spots { l.intensity = CGFloat(headL * (300 + 2600 * s.night)) }
        brakeLamp?.intensity = CGFloat(brakeL * (40 + 260 * s.night))
        // Brake discs glow when hot
        let heatIn: Float = s.braking ? min(1, abs(s.wheelSpeed) / 40) * 0.35 : 0
        heat = max(0, min(1, heat + (heatIn - 0.06) * dt))
        for m in discMats { m.emission.contents = UIColor(red: 1, green: 0.28, blue: 0.05, alpha: 1); m.emission.intensity = CGFloat(max(0, heat - 0.35) * 3) }
        // Exhaust flames
        if s.backfire { flameT = 0.12 }
        flameT = max(0, flameT - dt)
        for f in glowFlame { f.opacity = flameT > 0 ? CGFloat(Float.random(in: 0.6...1)) : 0; f.scale = SCNVector3(repeating: Float.random(in: 0.7...1.4)) }
        // Smoke / dust
        let rate = CGFloat(s.smoke * 160 + s.dust * 110)
        for ps in smokeSystems {
            ps.birthRate = rate
            ps.particleColor = s.dust > s.smoke ? UIColor(red: 0.62, green: 0.53, blue: 0.42, alpha: 0.32) : UIColor(white: 0.9, alpha: 0.3)
        }
    }
}

extension SCNVector3 {
    init(repeating v: Float) { self.init(v, v, v) }
}
