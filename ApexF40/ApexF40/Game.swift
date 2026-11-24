import SceneKit
import SwiftUI
import GLTFKit2
import GameController
import CoreMotion
import simd

enum Phase { case loading, menu, driving, paused, map }

struct HUDState {
    var speed: Float = 0
    var gear = "N"
    var rpm: Float = 0
    var boost: Float = 0
    var tc = false
    var esc = false
    var x: Float = 0
    var z: Float = 0
    var heading: Float = 0
    var region: WorldRegion = .california
    var place = ""
    var crashed = false
    var airborne = false
    var drift: Int = 0
    var driftCombo: Float = 0
    var bestDrift: Int = 0
    var topSpeed: Float = 0
    var odometer: Float = 0
    var airTime: Float = 0
    var night: Float = 0
    var clock = "12:00"
    var lights = false
}

struct Banner: Equatable { var id = UUID(); var title: String; var subtitle: String; var region: WorldRegion }

/// Touch / tilt / controller state written by the UI.
final class InputState {
    var left = false, right = false, gas = false, brake = false, handbrake = false, horn = false
    var lookYaw: Float = 0, looking = false
    var shiftUp = false, shiftDown = false
    var lightsOverride: Bool? = nil
}

final class Game: NSObject, ObservableObject, SCNSceneRendererDelegate {
    @Published var phase: Phase = .loading
    @Published var hud = HUDState()
    @Published var loadText = "Loading the world…"
    @Published var loadProgress: Double = 0
    @Published var streaming: Double = 0
    @Published var banner: Banner?
    @Published var errorText: String?

    let settings = GameSettings()
    let input = InputState()
    let audio = GameAudio()
    let scene = SCNScene()
    weak var view: SCNView?

    private(set) var world: WorldData?
    private var worldRenderer: WorldRenderer?
    private var carTemplate: SCNNode?
    private var trafficTemplate: SCNNode?
    private var rig: CarRig?
    let car = CarPhysics()
    private var box: RigidBox?
    private var traffic: Traffic?
    private let debris = DebrisField()
    private let cameraNode = SCNNode()
    private let sunNode = SCNNode()
    private let ambientNode = SCNNode()
    private let motion = CMMotionManager()
    var interfaceOrientation: UIInterfaceOrientation = .landscapeRight

    private var ready = false
    private var lastTime: TimeInterval = 0
    private var camYaw: Float = 0
    private var camPos = SIMD3<Float>(0, 5, 0)
    private var orbit: Float = 0
    private var shake: Float = 0
    private var hour: Float = 16.5
    private var lastSkyHour: Float = -100
    private var lastNight: Float = -1
    private var streamTimer: Float = 0
    private var hudTimer: Float = 0
    private var recoverTimer: Float = 0
    private var splashTimer: Float = 0
    private var crashCooldown: Float = 0
    private var lastPlace = ""
    private var lastRegion: WorldRegion?
    private var driftScore: Float = 0
    private var driftHold: Float = 0
    private var bestDrift: Float = 0
    private var topSpeed: Float = 0
    private var odometer: Float = 0
    private var time: Float = 0
    private var backfireFlag = false
    private var pendingHaptic: Float = 0

    // MARK: Setup

    func attach(_ v: SCNView) {
        guard view == nil else { return }
        CrashLog.step("attach view")
        view = v
        v.scene = scene
        v.delegate = self
        v.isPlaying = true
        v.rendersContinuously = true
        v.antialiasingMode = .multisampling4X
        v.preferredFramesPerSecond = settings.fps
        v.backgroundColor = .black
        let cam = SCNCamera()
        cam.zNear = 0.1; cam.zFar = 3200
        cam.fieldOfView = 62
        cam.wantsHDR = true
        cam.bloomIntensity = 0.4; cam.bloomThreshold = 0.85; cam.bloomBlurRadius = 10
        cam.vignettingIntensity = 0.35; cam.vignettingPower = 0.6
        cam.wantsExposureAdaptation = false
        cam.averageGray = 0.18
        cameraNode.camera = cam
        cameraNode.simdPosition = [0, 50, 0]
        scene.rootNode.addChildNode(cameraNode)
        v.pointOfView = cameraNode

        let sun = SCNLight(); sun.type = .directional; sun.intensity = 1500
        sun.castsShadow = true; sun.shadowMode = .forward; sun.shadowMapSize = CGSize(width: 2048, height: 2048)
        sun.orthographicScale = 18; sun.automaticallyAdjustsShadowProjection = false
        sun.zNear = 1; sun.zFar = 500; sun.shadowRadius = 2.5; sun.shadowSampleCount = 8
        sun.shadowColor = UIColor(white: 0, alpha: 0.6)
        sunNode.light = sun
        scene.rootNode.addChildNode(sunNode)
        let amb = SCNLight(); amb.type = .ambient; amb.intensity = 250
        ambientNode.light = amb
        scene.rootNode.addChildNode(ambientNode)
        scene.rootNode.addChildNode(debris.root)
        scene.fogStartDistance = 500; scene.fogEndDistance = 1500; scene.fogDensityExponent = 1.4
        hour = Float(settings.hour)
        applySky(force: true)

        let device = v.device
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                CrashLog.step("load world data")
                let w = try WorldData()
                CrashLog.step("world data ok: \(w.meta.chunks.count) chunks")
                self.progress(0.35, "Building materials…")
                let r = WorldRenderer(meta: w.meta, device: device)
                CrashLog.step("materials ok")
                r.view = v
                self.progress(0.5, "Loading the Ferrari F40…")
                self.loadModels { hi, lo in
                    DispatchQueue.main.async { self.finishSetup(world: w, renderer: r, hi: hi, lo: lo) }
                }
                self.world = w
            } catch {
                DispatchQueue.main.async { self.errorText = error.localizedDescription }
            }
        }
    }

    private func progress(_ p: Double, _ t: String) { DispatchQueue.main.async { self.loadProgress = p; self.loadText = t } }

    private func loadGLB(_ name: String, _ done: @escaping (SCNNode?) -> Void) {
        guard let url = Res.url(name, "Models") else { done(nil); return }
        var finished = false
        GLTFAsset.load(with: url, options: [:]) { _, status, asset, error, _ in
            if finished { return }
            if status == .complete, let asset {
                finished = true
                DispatchQueue.main.async {
                    CrashLog.step("glb parsed: \(name)")
                    let src = GLTFSCNSceneSource(asset: asset)
                    let holder = SCNNode()
                    for c in src.defaultScene?.rootNode.childNodes ?? [] { holder.addChildNode(c) }
                    CrashLog.step("glb scene ok: \(name)")
                    done(holder)
                }
            } else if status == .error || error != nil {
                finished = true
                CrashLog.step("glb failed: \(name) \(error?.localizedDescription ?? "")")
                DispatchQueue.main.async { done(nil) }
            }
        }
    }

    private func loadModels(_ done: @escaping (SCNNode?, SCNNode?) -> Void) {
        loadGLB("f40_hi.glb") { hi in
            self.progress(0.75, "Loading traffic…")
            self.loadGLB("f40_traffic.glb") { lo in done(hi, lo) }
        }
    }

    private func finishSetup(world w: WorldData, renderer r: WorldRenderer, hi: SCNNode?, lo: SCNNode?) {
        CrashLog.step("finish setup")
        world = w
        worldRenderer = r
        scene.rootNode.addChildNode(r.root)
        guard let hi else { errorText = "Couldn't load the car model."; return }
        CarRig.prepareTemplate(hi)
        carTemplate = hi
        CrashLog.step("player rig")
        let rg = CarRig(template: hi, lite: false)
        scene.rootNode.addChildNode(rg.root)
        rig = rg
        applyPaint()
        if let lo {
            CarRig.prepareTemplate(lo)
            trafficTemplate = lo
            CrashLog.step("traffic lanes")
            let t = Traffic(meta: w.meta, template: lo)
            CrashLog.step("traffic ok: \(t.lanes.count) lanes")
            scene.rootNode.addChildNode(t.root)
            traffic = t
        }
        sunNode.light?.categoryBitMask = -1
        loadProgress = 1
        let sp = min(max(settings.spawn, 0), w.meta.spawns.count - 1)
        placeAt(spawn: sp)
        CrashLog.step("audio")
        audio.volume = Float(settings.volume)
        audio.start()
        CrashLog.step("ready")
        ready = true
        phase = .menu
    }

    func applyPaint() {
        let p = PAINTS[min(max(settings.paint, 0), PAINTS.count - 1)]
        rig?.setPaint(p.color, metal: p.metal, rough: p.rough)
        let r = RIMS[min(max(settings.rims, 0), RIMS.count - 1)]
        rig?.setRims(r.color, metal: r.metal)
    }

    // MARK: Placement

    func placeAt(spawn i: Int) {
        guard let w = world, i < w.meta.spawns.count else { return }
        let s = w.meta.spawns[i]
        // spawn on the avenue just south of the centre intersection, facing north
        place(x: s.x + 4.5, z: s.z + 30, heading: .pi)
        banner = Banner(title: s.name, subtitle: s.region, region: WorldRegion.at(x: s.x, z: s.z))
        lastPlace = s.name
    }

    private var pendingPlace: SIMD3<Float>?
    private var pendingReset = false

    /// Thread-safe: applied at the start of the next frame on the render thread.
    func place(x: Float, z: Float, heading: Float) {
        if ready { pendingPlace = SIMD3(x, z, heading) } else { doPlace(x: x, z: z, heading: heading) }
        streaming = 0
    }

    func resetCar() { pendingReset = true }

    private func doPlace(x: Float, z: Float, heading: Float) {
        guard let w = world else { return }
        car.place(x: x, z: z, heading: heading, ground: w.ground)
        box = nil
        recoverTimer = 0; splashTimer = 0
        camYaw = heading
        traffic?.clear()
        debris.clear()
        rig?.root.simdPosition = [x, car.y, z]
        rig?.root.simdOrientation = simd_quatf(angle: heading, axis: [0, 1, 0])
    }

    /// Fast travel to any point: snaps to the closest road.
    func teleport(x: Float, z: Float) {
        guard let w = world else { return }
        var best: (Float, Float, Float)? = nil
        outer: for r in stride(from: Float(0), through: 400, by: 20) {
            let n = max(1, Int(r / 8))
            for k in 0..<n {
                let a = Float(k) / Float(n) * 2 * .pi
                let px = x + cos(a) * r, pz = z + sin(a) * r
                if let h = w.roads.query(px, pz), h.dist < 4 {
                    best = (px, pz, atan2(h.tangent.x, h.tangent.y)); break outer
                }
            }
        }
        if let b = best { place(x: b.0, z: b.1, heading: b.2) } else { place(x: x, z: z, heading: 0) }
        let reg = WorldRegion.at(x: x, z: z)
        banner = Banner(title: w.city(at: x, z, margin: 80)?.name ?? reg.rawValue, subtitle: reg.rawValue, region: reg)
    }

    private func performReset() {
        guard let w = world else { return }
        let p = box?.rootPosition ?? SIMD3(car.x, car.y, car.z)
        var heading = car.heading
        if let b = box { let f = b.forward; heading = atan2(f.x, f.z) }
        if let h = w.roads.query(p.x, p.z), h.dist < 60 {
            var th = atan2(h.tangent.x, h.tangent.y)
            var dh = th - heading; while dh > .pi { dh -= 2 * .pi }; while dh < -.pi { dh += 2 * .pi }
            if abs(dh) > .pi / 2 { th += .pi }
            // move onto the road (towards its centre line when we ended up beside it)
            let n = SIMD2<Float>(-h.tangent.y, h.tangent.x)
            var pt = SIMD2<Float>(p.x, p.z)
            if h.dist > h.halfWidth - 3 {
                let k = h.dist - max(0, h.halfWidth - 4)
                let c1 = pt + n * k, c2 = pt - n * k
                let d1 = w.roads.query(c1.x, c1.y)?.dist ?? 99, d2 = w.roads.query(c2.x, c2.y)?.dist ?? 99
                pt = d1 < d2 ? c1 : c2
            }
            car.place(x: pt.x, z: pt.y, heading: th, ground: w.ground)
        } else {
            car.place(x: p.x, z: p.z, heading: heading, ground: w.ground)
        }
        box = nil
        recoverTimer = 0
        camYaw = car.heading
        audio.chime()
    }

    // MARK: Loop

    func renderer(_ r: SCNSceneRenderer, updateAtTime t: TimeInterval) {
        var dt = Float(t - lastTime)
        lastTime = t
        if dt <= 0 || dt > 0.1 { dt = 1 / 60 }
        guard ready, let w = world else { return }
        if let e = ApexTryCatch({ self.frame(dt, w) }) {
            let msg = "\(e.name.rawValue): \(e.reason ?? "")"
            CrashLog.step("frame exception: " + msg)
            if !reportedFrameError {
                reportedFrameError = true
                DispatchQueue.main.async { self.errorText = "Error (please send to Claude): " + msg }
            }
        }
    }
    private var reportedFrameError = false

    private var frameCount = 0
    private func frame(_ dt: Float, _ w: WorldData) {
        time += dt
        frameCount += 1
        if frameCount == 1 || frameCount == 60 || frameCount == 600 { CrashLog.step("frame \(frameCount)") }
        if let p = pendingPlace { pendingPlace = nil; doPlace(x: p.x, z: p.y, heading: p.z) }
        if pendingReset { pendingReset = false; performReset() }
        let s = settings
        let active = phase == .driving
        let frozen = phase == .paused || phase == .map
        if !frozen {
            let di = gatherInput()
            simulate(dt, di, w)
            let night = Sky.palette(hour: hour).night
            let camF = SIMD2<Float>(sin(camYaw), cos(camYaw))
            let pv = playerVelocity
            traffic?.update(dt, player: playerPosition, playerVel: pv, camForward: camF, density: Int(s.traffic), night: night,
                            ground: { w.groundY($0, $1) }, collide: { w.collision.collide($0, r: $1) })
            if active { collideTraffic(w) }
            debris.update(dt) { w.groundY($0, $1) }
        }
        updateRig(dt)
        updateCamera(dt, w)
        updateEnvironment(frozen ? 0 : dt)
        streamTimer -= dt
        if streamTimer <= 0, let r = worldRenderer {
            streamTimer = 0.2
            let c = SIMD2<Float>(camPos.x, camPos.z)
            r.update(center: c, radius: Float(s.drawDistance), detail: Float(s.vegetationDistance))
            let st = Double(r.readiness(around: c, radius: 450))
            if abs(st - streaming) > 0.01 || (st >= 1 && streaming < 1) { DispatchQueue.main.async { self.streaming = st } }
        }
        // Audio
        audio.active = phase == .driving || phase == .menu
        audio.rpm = car.rpm
        audio.throttle = active ? car.throttle : 0
        audio.boost = car.boost
        audio.slip = box == nil ? car.slip : 0
        audio.speed = box == nil ? car.speed : simd_length(box!.vel)
        audio.offroad = !car.onRoad
        audio.horn = input.horn && active
        audio.volume = frozen ? 0 : Float(s.volume)
        if let tr = traffic {
            let p = playerPosition
            let nearest = tr.cars.map { simd_distance($0.pos, p) }.min() ?? 999
            audio.trafficLevel = max(0, 1 - nearest / 40)
        }
        // HUD
        hudTimer -= dt
        if hudTimer <= 0 { hudTimer = 0.1; publishHUD(w) }
    }

    var playerPosition: SIMD3<Float> { box?.rootPosition ?? SIMD3(car.x, car.y, car.z) }
    var playerVelocity: SIMD3<Float> { box?.vel ?? SIMD3(car.vx, car.vy, car.vz) }

    private func gatherInput() -> DriveInput {
        var d = DriveInput()
        d.hold = phase != .driving
        if settings.steering == .tilt {
            if !motion.isDeviceMotionActive && motion.isDeviceMotionAvailable { motion.deviceMotionUpdateInterval = 1 / 60; motion.startDeviceMotionUpdates() }
            if let g = motion.deviceMotion?.gravity {
                let sgnO: Float = interfaceOrientation == .landscapeLeft ? -1 : 1
                let inv: Float = settings.invertTilt ? -1 : 1
                d.steer = clampf(Float(g.y) * 2.6 * Float(settings.tiltSensitivity) * sgnO * inv, -1, 1)
                if abs(d.steer) < 0.03 { d.steer = 0 }
                d.analog = true
            }
        } else {
            if motion.isDeviceMotionActive { motion.stopDeviceMotionUpdates() }
            d.steer = (input.left ? 1 : 0) - (input.right ? 1 : 0)
        }
        d.throttle = input.gas ? 1 : 0
        d.brake = input.brake ? 1 : 0
        d.handbrake = input.handbrake
        if let pad = GCController.current?.extendedGamepad {
            let sx = pad.leftThumbstick.xAxis.value
            if abs(sx) > 0.08 { d.steer = -sx; d.analog = true }
            d.throttle = max(d.throttle, pad.rightTrigger.value)
            d.brake = max(d.brake, pad.leftTrigger.value)
            if pad.buttonX.isPressed || pad.buttonB.isPressed { d.handbrake = true }
            if pad.buttonA.isPressed { d.throttle = 1 }
        }
        if let kb = GCKeyboard.coalesced?.keyboardInput {
            func k(_ c: GCKeyCode) -> Bool { kb.button(forKeyCode: c)?.isPressed ?? false }
            if k(.leftArrow) || k(.keyA) { d.steer = 1 }
            if k(.rightArrow) || k(.keyD) { d.steer = -1 }
            if k(.upArrow) || k(.keyW) { d.throttle = 1 }
            if k(.downArrow) || k(.keyS) { d.brake = 1 }
            if k(.spacebar) { d.handbrake = true }
        }
        car.assist = settings.assist
        car.auto = settings.autoGearbox
        if input.shiftUp { input.shiftUp = false; car.shift(1) }
        if input.shiftDown { input.shiftDown = false; car.shift(-1) }
        return d
    }

    private func simulate(_ dt: Float, _ di: DriveInput, _ w: WorldData) {
        crashCooldown = max(0, crashCooldown - dt)
        let steps = max(1, Int((dt / (1.0 / 120.0)).rounded(.up)))
        let h = dt / Float(steps)
        for _ in 0..<steps {
            if var b = box {
                let imp = b.step(h, ground: { w.groundY($0, $1) }, collide: { w.collision.collide($0, r: $1) })
                box = b
                if imp > 3 && crashCooldown <= 0 {
                    crashCooldown = 0.18
                    audio.thud(min(1, imp / 12))
                    if imp > 6 { sparks(at: b.pos - SIMD3(0, 0.5, 0)); addShake(min(1, imp / 14)) }
                    if imp > 8 && settings.debris { debris.burst(at: b.pos, velocity: b.vel, paint: currentPaint, power: min(1, imp / 20)) }
                }
                continue
            }
            car.step(h, di, ground: w.ground)
            if phase == .driving { collideWorld(w) }
            if box != nil { break }
        }
        if !di.hold && box == nil {
            // clamp to the world
            car.x = min(max(car.x, w.minX + 30), w.maxX - 30)
            car.z = min(max(car.z, w.minZ + 30), w.maxZ - 30)
        }
        // Events
        for e in car.events {
            switch e {
            case .upshift, .downshift: audio.shiftClick()
            case .blowoff: audio.blowoff()
            case .backfire: audio.backfire(); backfireFlag = true
            case .limiter, .reverse: break
            case .landed(let p):
                audio.thud(min(1, p / 10)); addShake(min(1, p / 12))
                if p > 6 { dust(at: SIMD3(car.x, car.y, car.z)) }
                if p > 16 && settings.crash == .wild { tumble(normal: SIMD2(0, 0), impact: p * 0.6, point: SIMD2(car.x, car.z), kind: .building) }
            case .splash:
                if splashTimer == 0 { splashTimer = 0.001; audio.splash() }
            }
        }
        car.events.removeAll()
        // Recover
        if var b = box {
            if b.settle > 0.9 {
                if b.up.y > 0.82 {
                    let f = b.forward
                    let rp = b.rootPosition
                    car.place(x: rp.x, z: rp.z, heading: atan2(f.x, f.z), ground: w.ground)
                    box = nil; recoverTimer = 0
                } else {
                    recoverTimer += dt
                    if recoverTimer > 2.6 { performReset() }
                }
            }
            if b.age > 14 { performReset() }
            if b.pos.y < -3 { b.vel *= 0.5; box = b; if splashTimer == 0 { splashTimer = 0.001; audio.splash() } }
        }
        if splashTimer > 0 {
            splashTimer += dt
            car.vx *= 0.9; car.vz *= 0.9
            if splashTimer > 1.6 { splashTimer = 0; performReset() }
        }
        // Stats
        let v = box == nil ? car.speed : simd_length(box!.vel)
        if phase == .driving {
            odometer += v * dt
            topSpeed = max(topSpeed, v)
            let beta = abs(atan2(car.vx * cos(car.heading) - car.vz * sin(car.heading), abs(car.forwardSpeed)))
            if box == nil && !car.airborne && car.speed > 11 && beta > 0.22 {
                driftScore += dt * car.speed * beta * 22
                driftHold = 1.2
            } else {
                driftHold -= dt
                if driftHold <= 0 && driftScore > 0 { bestDrift = max(bestDrift, driftScore); driftScore = 0 }
            }
            if box != nil { driftScore = 0 }
        }
    }

    private var currentPaint: UIColor { PAINTS[min(max(settings.paint, 0), PAINTS.count - 1)].color }

    // MARK: Collisions

    private func collideWorld(_ w: WorldData) {
        let f = car.forward
        for off: Float in [1.35, 0, -1.35] {
            let c = SIMD2<Float>(car.x, car.z) + f * off
            guard let con = w.collision.collide(c, r: 1.0) else { continue }
            if con.kind == .barrier && car.airborne && car.y > (w.roads.query(car.x, car.z)?.y ?? car.y) + 1.0 { continue }
            car.x += con.normal.x * con.depth; car.z += con.normal.y * con.depth
            var v = SIMD2<Float>(car.vx, car.vz)
            let vn = simd_dot(v, con.normal)
            guard vn < 0 else { continue }
            let impact = -vn
            let threshold = settings.crash.threshold * (con.kind == .barrier ? 1.15 : 1)
            if impact > threshold {
                tumble(normal: con.normal, impact: impact, point: con.point, kind: con.kind)
                return
            }
            let e: Float = con.kind == .tree || con.kind == .pole ? 0.15 : 0.25
            v -= (1 + e) * vn * con.normal
            let tangent = SIMD2<Float>(-con.normal.y, con.normal.x)
            let vt = simd_dot(v, tangent)
            v -= tangent * vt * (con.kind == .barrier ? 0.05 : 0.15)
            car.vx = v.x; car.vz = v.y
            let arm = f * off
            let J = -(1 + e) * vn * con.normal
            let cross = arm.x * J.y - arm.y * J.x
            car.yawRate += -cross * 0.35
            if impact > 2.5 {
                if crashCooldown <= 0 {
                    crashCooldown = 0.25
                    audio.crash(min(1, impact / 18)); addShake(min(1, impact / 16))
                    sparks(at: SIMD3(con.point.x, car.y + 0.4, con.point.y))
                    if impact > 9 && settings.debris { debris.burst(at: SIMD3(car.x, car.y + 0.5, car.z), velocity: SIMD3(car.vx, 0, car.vz), paint: currentPaint, power: min(1, impact / 24)) }
                    haptic(min(1, impact / 15))
                }
            } else if car.speed > 3 && crashCooldown <= 0 {
                crashCooldown = 0.15
                audio.scrape(min(1, car.speed / 30))
            }
        }
    }

    /// Big hit: hand the car over to the rigid-body tumble.
    private func tumble(normal n: SIMD2<Float>, impact: Float, point: SIMD2<Float>, kind: ObstacleKind) {
        let q = simd_quatf(angle: car.heading, axis: [0, 1, 0]) * simd_quatf(angle: car.pitch, axis: [1, 0, 0]) * simd_quatf(angle: car.roll, axis: [0, 0, 1])
        var b = RigidBox(rootPos: SIMD3(car.x, car.y, car.z), q: q, vel: SIMD3(car.vx, max(0, car.vy), car.vz), w: SIMD3(0, car.yawRate, 0))
        let n3 = SIMD3<Float>(n.x, 0, n.y)
        let up: Float = kind == .barrier ? 0.55 : Float.random(in: 0.18...0.42)
        var j = (n3 * 1.1 + SIMD3(0, up, 0)) * impact * b.mass * 0.9
        if simd_length(n3) < 0.1 { j = SIMD3(0, impact * b.mass * 0.4, 0) }
        let side = SIMD3<Float>(cos(car.heading), 0, -sin(car.heading)) * Float.random(in: -0.6...0.6)
        let hit = SIMD3<Float>(point.x, car.y + 0.15, point.y) + side
        b.applyImpulse(j, at: hit)
        b.w += SIMD3(Float.random(in: -1...1), Float.random(in: -1.5...1.5), Float.random(in: -1...1)) * min(3, impact / 10)
        box = b
        audio.crash(1); addShake(1); haptic(1)
        sparks(at: hit)
        dust(at: SIMD3(car.x, car.y, car.z))
        if settings.debris { debris.burst(at: b.pos, velocity: b.vel, paint: currentPaint, power: min(1, impact / 22)) }
    }

    private func collideTraffic(_ w: WorldData) {
        guard let tr = traffic else { return }
        let pp = playerPosition
        let pf: SIMD2<Float>
        if let b = box { let f = b.forward; pf = simd_normalize(SIMD2(f.x, f.z) + SIMD2(1e-4, 0)) } else { pf = car.forward }
        for t in tr.cars {
            let tp = SIMD2<Float>(t.pos.x, t.pos.z)
            let p2 = SIMD2<Float>(pp.x, pp.z)
            if simd_distance(tp, p2) > 6.5 || abs(t.pos.y - pp.y) > 3 { continue }
            let tf = SIMD2<Float>(sin(t.heading), cos(t.heading))
            var best: (Float, SIMD2<Float>, SIMD2<Float>)? = nil   // depth, normal (to player), point
            for a: Float in [1.3, 0, -1.3] { for c: Float in [1.3, 0, -1.3] {
                let pa = p2 + pf * a, pb = tp + tf * c
                let d = simd_distance(pa, pb)
                if d < 2.0 && (2.0 - d) > (best?.0 ?? 0) {
                    let n = d > 1e-4 ? (pa - pb) / d : SIMD2<Float>(1, 0)
                    best = (2.0 - d, n, (pa + pb) * 0.5)
                }
            } }
            guard let hit = best else { continue }
            let (depth, n, pt) = hit
            let pv = playerVelocity, tv = t.velocity
            let rel = SIMD2<Float>(pv.x - tv.x, pv.z - tv.z)
            let vn = simd_dot(rel, n)
            // separate
            if box == nil { car.x += n.x * depth * 0.6; car.z += n.y * depth * 0.6 } else { box!.pos.x += n.x * depth * 0.6; box!.pos.z += n.y * depth * 0.6 }
            if t.crash != nil { t.crash!.pos.x -= n.x * depth * 0.4; t.crash!.pos.z -= n.y * depth * 0.4 }
            guard vn < 0 else { continue }
            let impact = -vn
            let jm = -(1 + 0.3) * vn / 2          // per unit mass (equal masses)
            let n3 = SIMD3<Float>(n.x, 0, n.y)
            let p3 = SIMD3<Float>(pt.x, pp.y + 0.35, pt.y)
            // the other car
            if impact > 6.5 || t.crash != nil {
                let lift: Float = min(0.5, impact / 40)
                tr.launch(t, impulse: (-n3 + SIMD3(0, lift, 0)) * jm * 1250, at: p3 - SIMD3(0, 0.1, 0))
            } else {
                t.speed = max(0, t.speed - impact * 0.8)
            }
            // the player
            if var b = box {
                b.applyImpulse(n3 * jm * 1250, at: p3); box = b
            } else if impact > settings.crash.threshold * 1.1 {
                car.vx += n.x * jm; car.vz += n.y * jm
                tumble(normal: n, impact: impact * 0.7, point: pt, kind: .car)
            } else {
                car.vx += n.x * jm; car.vz += n.y * jm
                let arm = SIMD2<Float>(pt.x - car.x, pt.y - car.z)
                car.yawRate += -(arm.x * n.y - arm.y * n.x) * jm * 0.25
            }
            if crashCooldown <= 0 && impact > 1.5 {
                crashCooldown = 0.2
                audio.crash(min(1, impact / 16)); addShake(min(1, impact / 14)); haptic(min(1, impact / 14))
                if impact > 5 { sparks(at: p3) }
                if impact > 8 && settings.debris { debris.burst(at: p3, velocity: (pv + tv) * 0.5, paint: t.paint, power: min(1, impact / 22)) }
            }
        }
    }

    // MARK: Effects

    private func sparks(at p: SIMD3<Float>) {
        scene.addParticleSystem(FX.sparks(), transform: SCNMatrix4MakeTranslation(p.x, p.y, p.z))
    }

    private func dust(at p: SIMD3<Float>) {
        scene.addParticleSystem(FX.dustBurst(), transform: SCNMatrix4MakeTranslation(p.x, p.y + 0.2, p.z))
    }

    private func addShake(_ k: Float) { if settings.cameraShake { shake = max(shake, k) } }

    private func haptic(_ k: Float) {
        guard settings.haptics else { return }
        DispatchQueue.main.async {
            let g = UIImpactFeedbackGenerator(style: k > 0.6 ? .heavy : .medium)
            g.impactOccurred(intensity: CGFloat(min(1, max(0.3, k))))
        }
    }

    // MARK: Car visuals

    private func updateRig(_ dt: Float) {
        guard let rig else { return }
        let pal = Sky.palette(hour: hour)
        let headlights: Float = input.lightsOverride.map { $0 ? 1 : 0 } ?? (pal.night > 0.4 ? 1 : 0)
        if let b = box {
            rig.root.simdPosition = b.rootPosition
            rig.root.simdOrientation = b.q
            rig.update(dt, RigState(steer: 0, wheelSpeed: simd_length(b.vel) * 0.4, braking: true, headlights: headlights, night: pal.night, hazard: true))
            return
        }
        rig.root.simdPosition = [car.x, car.y, car.z]
        rig.root.simdOrientation = simd_quatf(angle: car.heading, axis: [0, 1, 0]) * simd_quatf(angle: car.pitch, axis: [1, 0, 0]) * simd_quatf(angle: car.roll, axis: [0, 0, 1])
        var st = RigState()
        st.steer = car.steer
        st.wheelSpeed = car.airborne ? car.forwardSpeed + car.throttle * 20 : car.forwardSpeed
        st.wheelspin = car.wheelspin
        st.locked = car.locked
        st.braking = car.brake > 0.05 && phase == .driving
        st.reverse = car.reverse
        st.longAccel = car.longAccel
        st.latAccel = car.latAccel
        st.headlights = headlights
        st.night = pal.night
        st.backfire = backfireFlag; backfireFlag = false
        st.bump = car.onRoad ? 0 : Float.random(in: -0.008...0.008) * min(1, car.speed / 10)
        st.smoke = car.onRoad && !car.airborne ? max(0, car.slip - 0.22) * 2 : 0
        st.dust = !car.onRoad && !car.airborne ? min(1, car.speed / 25) : 0
        rig.update(dt, st)
    }

    // MARK: Camera

    private func updateCamera(_ dt: Float, _ w: WorldData) {
        guard let cam = cameraNode.camera else { return }
        let target = playerPosition
        var yawSrc = car.heading
        if let b = box {
            let v = SIMD2<Float>(b.vel.x, b.vel.z)
            if simd_length(v) > 2 { yawSrc = atan2(v.x, v.y) } else { yawSrc = camYaw }
        } else if car.reverse && car.forwardSpeed < -2 {
            yawSrc = car.heading
        }
        var d = yawSrc - camYaw
        while d > .pi { d -= 2 * .pi }; while d < -.pi { d += 2 * .pi }
        camYaw += d * min(1, dt * (box == nil ? 5.5 : 2.5))
        if !input.looking { input.lookYaw *= 1 - min(1, dt * 2.5) }
        let mode: CameraMode = phase == .menu ? .cinematic : settings.camera
        let speed = box == nil ? car.speed : simd_length(box!.vel)
        var fov = Float(settings.fov)
        if settings.speedFov && phase == .driving { fov += min(16, speed * 0.16) }
        var pos: SIMD3<Float>
        var look: SIMD3<Float>
        switch mode {
        case .chase, .far:
            let yaw = camYaw + input.lookYaw
            let dist: Float = mode == .far ? Float(settings.camDistance) * 1.55 : Float(settings.camDistance)
            let ht: Float = mode == .far ? 3.0 : 1.95
            let f = SIMD3<Float>(sin(yaw), 0, cos(yaw))
            pos = target - f * dist + SIMD3(0, ht, 0)
            look = target + SIMD3(0, 1.0, 0) + f * 1.8
        case .hood, .bumper:
            if box == nil && abs(input.lookYaw) < 0.05, let rig {
                let local: SIMD3<Float> = mode == .hood ? [0, 1.1, 0.15] : [0, 0.62, 2.3]
                pos = rig.root.simdConvertPosition(local, to: nil)
                look = rig.root.simdConvertPosition(local + [0, -0.02, 10], to: nil)
            } else {
                let yaw = camYaw + input.lookYaw
                let f = SIMD3<Float>(sin(yaw), 0, cos(yaw))
                pos = target - f * 6 + SIMD3(0, 2, 0)
                look = target + SIMD3(0, 1, 0)
            }
        case .cinematic:
            orbit += dt * (phase == .menu ? 0.16 : 0.3)
            let r: Float = phase == .menu ? 7.5 : 9
            pos = target + SIMD3(sin(orbit) * r, phase == .menu ? 1.6 : 2.4, cos(orbit) * r)
            look = target + SIMD3(0, 0.65, 0)
        }
        // keep the camera out of the ground
        let gy = w.groundY(pos.x, pos.z) + 0.45
        if pos.y < gy { pos.y = gy }
        if shake > 0.001 {
            pos += SIMD3(Float.random(in: -1...1), Float.random(in: -1...1), Float.random(in: -1...1)) * shake * 0.12
            shake *= 1 - min(1, dt * 4)
        }
        camPos = pos
        cameraNode.simdPosition = pos
        cameraNode.simdLook(at: look, up: SIMD3(0, 1, 0), localFront: SIMD3(0, 0, -1))
        cam.fieldOfView = CGFloat(fov)
        cam.zFar = Double(settings.drawDistance) + 900
        cam.motionBlurIntensity = settings.motionBlur && phase == .driving ? CGFloat(min(0.6, speed / 120)) : 0
    }

    // MARK: Sky, sun, lights

    private func updateEnvironment(_ dt: Float) {
        if settings.timeMode == .cycle {
            hour += dt * 24 / Float(max(1, settings.dayLength) * 60)
            if hour >= 24 { hour -= 24 }
        } else {
            hour = Float(settings.hour)
        }
        applySky(force: false)
        worldRenderer?.animateWater(time * 0.01)
    }

    func applySky(force: Bool) {
        let pal = Sky.palette(hour: hour)
        // Sun / moon direction
        let az = hour / 24 * 2 * .pi + 0.6
        let el = pal.elevation > -0.05 ? max(asin(max(pal.elevation, 0.05)), 0.05) : 0.75
        let dir = simd_normalize(SIMD3<Float>(cos(az) * cos(el), sin(el), sin(az) * cos(el)))
        let c = playerPosition
        sunNode.simdPosition = c + dir * 220
        sunNode.simdLook(at: c, up: SIMD3(0, 1, 0), localFront: SIMD3(0, 0, -1))
        if let l = sunNode.light {
            l.intensity = CGFloat(pal.sunI)
            l.color = UIColor(red: CGFloat(pal.sun.x), green: CGFloat(pal.sun.y), blue: CGFloat(pal.sun.z), alpha: 1)
            l.castsShadow = settings.shadows && pal.elevation > 0.02
        }
        if let a = ambientNode.light {
            a.intensity = CGFloat(pal.ambI)
            a.color = UIColor(red: CGFloat(0.55 + pal.horizon.x * 0.45), green: CGFloat(0.55 + pal.horizon.y * 0.45), blue: CGFloat(0.6 + pal.horizon.z * 0.4), alpha: 1)
        }
        let draw = Float(settings.drawDistance)
        scene.fogStartDistance = CGFloat(draw * 0.3)
        scene.fogEndDistance = CGFloat(draw * 1.05)
        scene.fogColor = UIColor(red: CGFloat(pal.fog.x), green: CGFloat(pal.fog.y), blue: CGFloat(pal.fog.z), alpha: 1)
        if force || abs(hour - lastSkyHour) > 0.04 {
            lastSkyHour = hour
            let img = Sky.image(pal)
            scene.background.contents = img
            scene.lightingEnvironment.contents = img
            scene.lightingEnvironment.intensity = CGFloat(pal.envI)
        }
        if abs(pal.night - lastNight) > 0.02 || force {
            lastNight = pal.night
            worldRenderer?.setNight(pal.night)
        }
        if let cam = cameraNode.camera {
            cam.bloomIntensity = settings.bloom ? CGFloat(0.25 + 0.9 * pal.night) : 0
            cam.exposureOffset = CGFloat(-0.2 + 0.5 * pal.night)
        }
    }

    // MARK: HUD

    private func publishHUD(_ w: WorldData) {
        var h = HUDState()
        let p = playerPosition
        let v = box == nil ? car.speed : simd_length(box!.vel)
        h.speed = v
        h.gear = car.reverse ? "R" : (v < 0.5 && car.throttle == 0 ? "N" : "\(car.gear)")
        h.rpm = car.rpm / CarPhysics.REDLINE
        h.boost = car.boost
        h.tc = car.tcActive; h.esc = car.escActive
        h.x = p.x; h.z = p.z
        if let b = box { let f = b.forward; h.heading = atan2(f.x, f.z) } else { h.heading = car.heading }
        let reg = WorldRegion.at(x: p.x, z: p.z)
        h.region = reg
        let city = w.city(at: p.x, p.z, margin: 60)
        h.place = city?.name ?? reg.rawValue
        h.crashed = box != nil && recoverTimer > 0.3
        h.airborne = car.airborne
        h.airTime = car.airTime
        h.drift = Int(driftScore)
        h.driftCombo = driftHold
        h.bestDrift = Int(max(bestDrift, driftScore))
        h.topSpeed = topSpeed
        h.odometer = odometer
        let pal = Sky.palette(hour: hour)
        h.night = pal.night
        let hh = Int(hour) % 24, mm = Int((hour - Float(Int(hour))) * 60)
        h.clock = String(format: "%02d:%02d", hh, mm)
        h.lights = input.lightsOverride ?? (pal.night > 0.4)
        var newBanner: Banner? = nil
        if phase == .driving {
            if let city, city.name != lastPlace { newBanner = Banner(title: city.name, subtitle: city.region, region: reg) }
            else if city == nil && lastRegion != nil && lastRegion != reg { newBanner = Banner(title: reg.rawValue, subtitle: "Welcome to", region: reg) }
        }
        lastPlace = city?.name ?? ""
        lastRegion = reg
        DispatchQueue.main.async {
            self.hud = h
            if let newBanner { self.banner = newBanner }
        }
    }

    // MARK: UI actions

    func start() { phase = .driving; audio.resume() }
    func pause() { if phase == .driving { phase = .paused } }
    func resume() { phase = .driving }
    func openMap() { if phase == .driving || phase == .paused { phase = .map } }
    func quitToMenu() { phase = .menu; input.gas = false; input.brake = false }
    func cycleCamera() {
        let all = CameraMode.allCases
        settings.camera = all[(settings.camera.rawValue + 1) % all.count]
    }
    func toggleLights() {
        let pal = Sky.palette(hour: hour)
        let cur = input.lightsOverride ?? (pal.night > 0.4)
        input.lightsOverride = !cur
    }
    func setHour(_ h: Double) { hour = Float(h); lastSkyHour = -100 }
    var currentHour: Double { Double(hour) }
    func applyGraphics() {
        view?.preferredFramesPerSecond = settings.fps
        view?.showsStatistics = settings.showFPS
    }
}
