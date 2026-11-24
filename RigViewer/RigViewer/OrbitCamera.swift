import UIKit
import SceneKit

/// Touch camera tuned for inspecting models:
/// - one finger orbits around the model (with momentum),
/// - pinch zooms toward the point between your fingers,
/// - two fingers drag to pan, twist to spin,
/// - everything eases with critically-damped smoothing on a 120 Hz display link, so it never jumps or stutters.
@MainActor
final class OrbitCamera: NSObject, UIGestureRecognizerDelegate {
    let node: SCNNode
    private weak var view: SCNView?

    // Where the camera is heading (gestures write here)…
    private var yaw: Float = 0.48, pitch: Float = 0.2, distance: Float = 3
    private var target = SIMD3<Float>(0, 1, 0)
    // …and where it is right now (eased toward the goal every frame).
    private var cYaw: Float = 0.48, cPitch: Float = 0.2, cDistance: Float = 3
    private var cTarget = SIMD3<Float>(0, 1, 0)

    private var yawVelocity: Float = 0, pitchVelocity: Float = 0
    private var panVelocity = SIMD3<Float>(repeating: 0)
    private var minDistance: Float = 0.05, maxDistance: Float = 100
    private var modelRadius: Float = 1
    private var touching = 0
    private var multiTouch = 0                     // active two-finger gestures (orbit pauses while > 0)
    private var glide = false                      // slower easing for reset / framing
    private var lastTime: CFTimeInterval = 0
    private var link: CADisplayLink?
    private var pinchStartDistance: Float = 3
    private var lastPinchCenter: CGPoint?

    var autoRotate = false

    init(node: SCNNode) { self.node = node; super.init() }

    // MARK: setup

    func attach(to view: SCNView) {
        self.view = view
        view.allowsCameraControl = false

        let orbit = UIPanGestureRecognizer(target: self, action: #selector(handleOrbit(_:)))
        orbit.maximumNumberOfTouches = 1
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.minimumNumberOfTouches = 2; pan.maximumNumberOfTouches = 2
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        let twist = UIRotationGestureRecognizer(target: self, action: #selector(handleTwist(_:)))
        for g in [orbit, pan, pinch, twist] as [UIGestureRecognizer] {
            g.delegate = self
            g.cancelsTouchesInView = false
            view.addGestureRecognizer(g)
        }

        link?.invalidate()
        let l = CADisplayLink(target: self, selector: #selector(step(_:)))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        l.add(to: .main, forMode: .common)
        link = l
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        // Everything runs together so you can go from orbiting straight into a pinch without lifting.
        g.view === other.view && !(other is UITapGestureRecognizer)
    }

    // MARK: framing

    /// Points the camera at a model. `animated` glides there; otherwise it snaps.
    func frame(center: SIMD3<Float>, radius: Float, distance d: Float, animated: Bool) {
        modelRadius = max(radius, 0.001)
        minDistance = modelRadius * 0.12
        maxDistance = modelRadius * 40
        target = center; distance = d
        yaw = 0.48; pitch = 0.2
        yawVelocity = 0; pitchVelocity = 0; panVelocity = .zero
        if animated {
            // Take the short way round so the reset never spins several turns.
            let twoPi = Float.pi * 2
            cYaw = cYaw.truncatingRemainder(dividingBy: twoPi)
            if cYaw - yaw > .pi { cYaw -= twoPi } else if yaw - cYaw > .pi { cYaw += twoPi }
            glide = true
        } else {
            cYaw = yaw; cPitch = pitch; cDistance = d; cTarget = center; glide = false
        }
        apply()
    }

    // MARK: gestures

    private var sensitivity: Float {
        // About one full turn for a swipe across the screen width, whatever the device size.
        let w = Float(view?.bounds.width ?? 390)
        return (2 * .pi) / max(w, 300) * 0.85 * Float(AppSettings.shared.orbitSpeed)
    }

    @objc private func handleOrbit(_ g: UIPanGestureRecognizer) {
        guard let v = view else { return }
        switch g.state {
        case .began:
            touching += 1; glide = false; yawVelocity = 0; pitchVelocity = 0; panVelocity = .zero
        case .changed:
            let t = g.translation(in: v); g.setTranslation(.zero, in: v)
            guard multiTouch == 0, g.numberOfTouches == 1 else { return }
            let sx: Float = AppSettings.shared.invertX ? -1 : 1, sy: Float = AppSettings.shared.invertY ? -1 : 1
            yaw -= Float(t.x) * sensitivity * sx
            pitch = clampPitch(pitch + Float(t.y) * sensitivity * sy)
        case .ended, .cancelled, .failed:
            touching = max(0, touching - 1)
            guard multiTouch == 0 else { return }
            let vel = g.velocity(in: v)
            // Ignore the tiny flick at the end of a slow, careful drag.
            let speed = hypot(vel.x, vel.y)
            if speed > 120, AppSettings.shared.momentum {
                let sx: Float = AppSettings.shared.invertX ? -1 : 1, sy: Float = AppSettings.shared.invertY ? -1 : 1
                yawVelocity = -Float(vel.x) * sensitivity * sx
                pitchVelocity = Float(vel.y) * sensitivity * sy
                let cap: Float = 9
                yawVelocity = max(-cap, min(cap, yawVelocity)); pitchVelocity = max(-cap, min(cap, pitchVelocity))
            }
        default: break
        }
    }

    @objc private func handlePinch(_ g: UIPinchGestureRecognizer) {
        guard let v = view else { return }
        switch g.state {
        case .began:
            touching += 1; multiTouch += 1; glide = false; yawVelocity = 0; pitchVelocity = 0
            pinchStartDistance = distance; lastPinchCenter = g.location(in: v)
        case .changed:
            let scale = powf(Float(max(g.scale, 0.01)), Float(AppSettings.shared.zoomSpeed))
            let newDistance = clampDistance(pinchStartDistance / scale)
            // Zoom toward the point between the fingers: slide the target that way as we move in.
            let p = g.location(in: v)
            let zoomIn = newDistance < distance
            if zoomIn, g.numberOfTouches >= 2, AppSettings.shared.zoomToFingers {
                let factor = (distance - newDistance) / max(distance, 0.0001)
                target += worldOffset(fromCenterTo: p) * factor
            }
            distance = newDistance
            lastPinchCenter = p
        case .ended, .cancelled, .failed:
            touching = max(0, touching - 1); multiTouch = max(0, multiTouch - 1); lastPinchCenter = nil
        default: break
        }
    }

    @objc private func handlePan(_ g: UIPanGestureRecognizer) {
        guard let v = view else { return }
        switch g.state {
        case .began:
            touching += 1; multiTouch += 1; glide = false; panVelocity = .zero; yawVelocity = 0; pitchVelocity = 0
        case .changed:
            let t = g.translation(in: v); g.setTranslation(.zero, in: v)
            guard AppSettings.shared.twoFingerPan else { return }
            target += panDelta(dx: Float(t.x), dy: Float(t.y))
        case .ended, .cancelled, .failed:
            touching = max(0, touching - 1); multiTouch = max(0, multiTouch - 1)
            let vel = g.velocity(in: v)
            if hypot(vel.x, vel.y) > 150, AppSettings.shared.twoFingerPan, AppSettings.shared.momentum { panVelocity = panDelta(dx: Float(vel.x), dy: Float(vel.y)) * 0.6 }
        default: break
        }
    }

    @objc private func handleTwist(_ g: UIRotationGestureRecognizer) {
        switch g.state {
        case .began: touching += 1; multiTouch += 1; glide = false
        case .changed: if AppSettings.shared.twistToRotate { yaw -= Float(g.rotation) }; g.rotation = 0
        case .ended, .cancelled, .failed: touching = max(0, touching - 1); multiTouch = max(0, multiTouch - 1)
        default: break
        }
    }

    // MARK: per-frame update

    @objc private func step(_ l: CADisplayLink) {
        let now = l.timestamp
        var elapsed: Double = 1.0 / 120.0
        if lastTime != 0 { elapsed = min(max(now - lastTime, 1.0 / 240.0), 1.0 / 20.0) }
        let dt = Float(elapsed)
        lastTime = now

        if touching == 0 {
            // Momentum after a flick, fading smoothly.
            if abs(yawVelocity) > 0.0005 || abs(pitchVelocity) > 0.0005 {
                yaw += yawVelocity * dt
                pitch = clampPitch(pitch + pitchVelocity * dt)
                let decay: Float = expf(-AppSettings.shared.momentumDecay * dt)
                yawVelocity *= decay; pitchVelocity *= decay
            }
            if simd_length(panVelocity) > 1e-6 {
                target += panVelocity * dt
                panVelocity *= expf(-6.0 * dt)
            }
            if autoRotate { yaw -= 0.45 * Float(AppSettings.shared.turntableSpeed) * dt }
        }

        // Critically-damped easing: quick while touching (feels direct), softer when gliding to a reset.
        let base = AppSettings.shared.cameraTau
        let tau: Float = glide ? max(0.12, base * 1.5) : (touching > 0 ? base : base * 1.4)
        let a: Float = 1.0 - expf(-dt / tau)
        cYaw += (yaw - cYaw) * a
        cPitch += (pitch - cPitch) * a
        // Ease distance in log space so zoom feels even at every scale.
        let logC: Float = logf(cDistance), logG: Float = logf(distance)
        cDistance = expf(logC + (logG - logC) * a)
        cTarget += (target - cTarget) * a
        if glide, abs(yaw - cYaw) < 0.001, abs(distance - cDistance) / distance < 0.001, simd_length(target - cTarget) < modelRadius * 0.001 { glide = false }
        apply()
    }

    private func apply() {
        let cp: Float = cosf(cPitch), sp: Float = sinf(cPitch), cy: Float = cosf(cYaw), sy: Float = sinf(cYaw)
        let dir = SIMD3<Float>(cp * sy, sp, cp * cy)
        node.simdPosition = cTarget + dir * cDistance
        node.simdLook(at: cTarget, up: SIMD3(0, 1, 0), localFront: SIMD3(0, 0, -1))
        if let cam = node.camera {
            cam.zNear = Double(max(cDistance * 0.005, modelRadius * 0.0005))
            cam.zFar = Double(cDistance + modelRadius * 60)
        }
    }

    // MARK: helpers

    private func clampPitch(_ p: Float) -> Float { max(AppSettings.shared.allowBelow ? -1.48 : -0.02, min(1.48, p)) }

    func setFrameRate(_ fps: Int) {
        let f = Float(fps)
        link?.preferredFrameRateRange = CAFrameRateRange(minimum: min(30, f), maximum: f, preferred: f)
    }
    private func clampDistance(_ d: Float) -> Float { max(minDistance, min(maxDistance, d)) }

    /// World units per screen point at the target's depth.
    private var worldPerPoint: Float {
        let h = Float(view?.bounds.height ?? 844)
        let fov = Float(node.camera?.fieldOfView ?? 38) * .pi / 180
        let half: Float = tanf(fov / 2)
        return 2 * cDistance * half / max(h, 1)
    }

    private func panDelta(dx: Float, dy: Float) -> SIMD3<Float> {
        let right = node.simdWorldRight, up = node.simdWorldUp
        return (-right * dx + up * dy) * worldPerPoint
    }

    private func worldOffset(fromCenterTo p: CGPoint) -> SIMD3<Float> {
        guard let v = view else { return .zero }
        let dx = Float(p.x - v.bounds.midX), dy = Float(p.y - v.bounds.midY)
        return (node.simdWorldRight * dx - node.simdWorldUp * dy) * worldPerPoint
    }
}
