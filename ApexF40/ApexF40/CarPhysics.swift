import Foundation
import simd

struct DriveInput {
    var steer: Float = 0        // +1 = full left
    var throttle: Float = 0
    var brake: Float = 0
    var handbrake = false
    var analog = false
    var hold = false
}

enum Assist: String, CaseIterable, Identifiable { case full, sport, off; var id: String { rawValue }
    var label: String { switch self { case .full: return "Full"; case .sport: return "Sport"; case .off: return "Off" } }
}

enum CarEvent {
    case upshift, downshift, blowoff, backfire, limiter, reverse
    case landed(Float)
    case splash
}

/// Ferrari F40 driving model (bicycle model with weight transfer, turbo lag, ESC/TC), ported from the web build
/// and extended with jumps (airborne flight and landings) for the open world.
final class CarPhysics {
    static let MASS: Float = 1250, INERTIA: Float = 1650, A: Float = 1.24, B: Float = 1.22, WHEEL_R: Float = 0.32
    static let GEARS: [Float] = [0, 3.35, 2.24, 1.64, 1.27, 0.97]
    static let FINAL: Float = 2.73, REDLINE: Float = 7750, IDLE: Float = 1000, EFF: Float = 0.88

    var x: Float = 0, z: Float = 0, y: Float = 0, vy: Float = 0, heading: Float = 0
    var vx: Float = 0, vz: Float = 0, yawRate: Float = 0
    var steer: Float = 0, throttle: Float = 0, brake: Float = 0, handbrake: Float = 0
    var gear = 1, rpm: Float = 1000, boost: Float = 0, auto = true, reverse = false
    var longAccel: Float = 0, latAccel: Float = 0, slip: Float = 0, wheelspin: Float = 0, locked = false
    var pitch: Float = 0, roll: Float = 0
    var shiftTimer: Float = 0, revHold: Float = 0, prevThr: Float = 0
    var airborne = false, airTime: Float = 0
    var assist: Assist = .full
    var onRoad = true, tcActive = false, escActive = false
    var events: [CarEvent] = []

    var speed: Float { (vx * vx + vz * vz).squareRoot() }
    var forwardSpeed: Float { vx * sin(heading) + vz * cos(heading) }
    var forward: SIMD2<Float> { SIMD2(sin(heading), cos(heading)) }

    func place(x: Float, z: Float, heading: Float, ground: (Float, Float) -> Ground) {
        self.x = x; self.z = z; self.heading = heading
        vx = 0; vz = 0; vy = 0; yawRate = 0; gear = 1; reverse = false; rpm = CarPhysics.IDLE; airborne = false
        y = ground(x, z).y; pitch = 0; roll = 0; steer = 0
    }

    func shift(_ d: Int) {
        if reverse { return }
        let g = max(1, min(5, gear + d))
        if g != gear { gear = g; shiftTimer = 0.18; events.append(d > 0 ? .upshift : .downshift) }
    }

    static func torque(_ rpm: Float) -> Float {
        let x = rpm / 1000
        return max(120, 577 - 28 * (x - 4) * (x - 4)) * (rpm > REDLINE ? 0.1 : 1)
    }

    static func maxSteer(_ v: Float, _ assist: Assist) -> Float {
        let gripLock = (A + B) * 1.7 * 9.81 / max(v * v, 1) * 1.15 + 0.03
        return min(0.62 / (1 + v * 0.02), assist == .off ? gripLock * 1.6 : gripLock)
    }

    func step(_ dt: Float, _ input: DriveInput, ground: (Float, Float) -> Ground) {
        typealias C = CarPhysics
        if input.hold {
            vx = 0; vz = 0; yawRate = 0; steer *= 0.9; throttle = 0; brake = 1; reverse = false
            y = ground(x, z).y; vy = 0; airborne = false
            rpm += (1000 - rpm) * min(1, dt * 3); longAccel = 0; latAccel = 0; slip = 0; wheelspin = 0
            return
        }
        let v = speed
        let maxS = C.maxSteer(v, assist)
        let target = input.steer * maxS
        let rate = (input.analog ? 6 : 3) / (1 + v * 0.035)
        steer += max(-rate * dt, min(rate * dt, target - steer))
        var thr = input.throttle, brk = input.brake
        let fwd = forwardSpeed
        if !reverse && brk > 0.5 && fwd < 0.6 && thr < 0.1 { revHold += dt; if revHold > 0.35 { reverse = true; events.append(.reverse) } } else { revHold = 0 }
        if reverse && thr > 0.1 && fwd > -0.5 { reverse = false; gear = 1 }
        if reverse { swap(&thr, &brk) }
        throttle = thr; brake = brk; handbrake = input.handbrake ? 1 : 0

        let sinH = sin(heading), cosH = cos(heading)
        var vLong = vx * sinH + vz * cosH
        var vLat = vx * cosH - vz * sinH

        let g = ground(x, z)
        onRoad = g.road
        let contact: Float = airborne ? 0 : 1
        let grip = g.grip * contact
        let rollRes = g.rollRes * contact

        // Engine & gearbox
        let wheelRpm = abs(vLong) / C.WHEEL_R * 60 / (2 * .pi)
        let ratio = reverse ? 3.0 * C.FINAL : C.GEARS[gear] * C.FINAL
        var rpmNow = max(C.IDLE, wheelRpm * ratio)
        if airborne { rpmNow = max(rpmNow, C.IDLE + thr * 6000) }
        if shiftTimer > 0 { shiftTimer -= dt }
        let boostTarget: Float = thr > 0.6 && rpmNow > 2600 ? 1 : 0
        let prevBoost = boost
        boost += (boostTarget - boost) * min(1, dt * (boostTarget > boost ? 1.6 : 6))
        if prevBoost > 0.55 && boost < 0.5 && thr < 0.2 { events.append(.blowoff) }
        var engineForce: Float = 0
        if shiftTimer <= 0 {
            let tq = C.torque(rpmNow) * (0.55 + 0.45 * boost)
            engineForce = thr * tq * ratio * C.EFF / C.WHEEL_R
        }
        if reverse { engineForce = -engineForce * 0.6 }
        if rpmNow >= C.REDLINE { engineForce *= 0.15; if Float.random(in: 0...1) < 0.05 { events.append(.limiter) } }
        if auto && !reverse && shiftTimer <= 0 && !airborne {
            if rpmNow > 7350 && gear < 5 && thr > 0.1 { shift(1) }
            else if rpmNow < 3300 && gear > 1 { shift(-1) }
            else if brk > 0.3 && rpmNow < 4600 && gear > 2 { shift(-1) }
        }
        if prevThr > 0.7 && thr < 0.2 && rpmNow > 4800 { events.append(.backfire) }
        prevThr = thr
        engineForce *= contact

        // Tyres
        let absV = max(abs(vLong), 0.5)
        let yawF = C.A * yawRate, yawR = -C.B * yawRate
        let dir: Float = vLong >= 0 ? 1 : -1
        let slipF = atan2(vLat + yawF, absV) - steer * dir
        let slipR = atan2(vLat + yawR, absV)
        let loadF = C.MASS * 9.81 * C.B / (C.A + C.B) - longAccel * C.MASS * 0.33 / (C.A + C.B) * 0.45
        let loadR = C.MASS * 9.81 * C.A / (C.A + C.B) + longAccel * C.MASS * 0.33 / (C.A + C.B) * 0.45
        let mu = 1.65 * grip, muR = mu * 1.1
        let CF: Float = 9.5, CR: Float = 10.0
        var FlatF = clampf(-CF * slipF, -mu, mu) * loadF
        var FlatR = clampf(-CR * slipR, -muR, muR) * loadR
        let brakeForce = brk * 13500 * grip
        var FlongR = engineForce - (handbrake > 0 ? 6000 * sgn(vLong) * contact : 0)
        var FlongF: Float = 0
        if abs(vLong) > 0.3 { FlongF -= brakeForce * 0.62 * dir; FlongR -= brakeForce * 0.38 * dir }
        else if brk > 0 && !reverse && !airborne { vLong *= 0.8 }
        let rearMax = muR * loadR
        tcActive = false
        if assist != .off && handbrake == 0 && FlongR > 0 {
            let room = max(0, (rearMax * 0.92) * (rearMax * 0.92) - FlatR * FlatR).squareRoot()
            let cap = assist == .full ? room : room * 1.25 + rearMax * 0.1
            if FlongR > cap { FlongR = cap; tcActive = true }
        }
        let rearUse = (FlongR * FlongR + FlatR * FlatR).squareRoot()
        wheelspin = 0
        if rearUse > rearMax && rearMax > 0 {
            let k = rearMax / rearUse
            if abs(FlongR) > rearMax * 0.8 && handbrake == 0 { wheelspin = min(25, (abs(FlongR) / rearMax - 0.8) * 30) }
            FlongR *= k; FlatR *= k
        } else if rearMax <= 0 { FlongR = 0; FlatR = 0 }
        if handbrake > 0 { FlatR *= 0.42 }
        let frontMax = mu * loadF
        let fu = (FlongF * FlongF + FlatF * FlatF).squareRoot()
        locked = false
        if fu > frontMax { let k = frontMax / max(fu, 1e-3); FlongF *= k; FlatF *= k; locked = brk > 0.85 && abs(vLong) > 8 }

        let drag = 0.40 * vLong * abs(vLong) + rollRes * vLong
        let downforce = min(0.35, (v / 70) * (v / 70) * 0.3)
        FlatF *= 1 + downforce; FlatR *= 1 + downforce
        let cs = cos(steer), sn = sin(steer)
        let Flong = FlongR + FlongF * cs - FlatF * sn - drag
        let offLat: Float = g.road || airborne ? 0 : vLat * 120
        let Flat = FlatR + FlatF * cs + FlongF * sn - offLat
        var torqueZ = C.A * (FlatF * cs + FlongF * sn) - C.B * FlatR
        escActive = false
        if assist != .off && handbrake == 0 && abs(vLong) > 8 && !airborne {
            let maxYaw = muR * 9.81 / abs(vLong)
            let want = clampf(vLong * tan(steer) / (C.A + C.B), -maxYaw, maxYaw)
            let excess = yawRate - want
            let strength: Float = assist == .full ? 1 : 0.4
            let beta = atan2(vLat, abs(vLong))
            if abs(excess) > 0.04 || abs(beta) > 0.06 {
                torqueZ -= excess * C.INERTIA * 9 * strength
                vLat -= vLat * min(1, dt * 4.5 * strength) * min(1, abs(beta) * 6)
                escActive = true
            }
        }
        let aLong = Flong / C.MASS + yawRate * vLat
        let aLat = Flat / C.MASS - yawRate * vLong
        vLong += aLong * dt; vLat += aLat * dt
        yawRate += torqueZ / C.INERTIA * dt
        if abs(vLong) < 4 && !airborne {
            let k = 1 - abs(vLong) / 4
            let kinYaw = vLong * tan(steer) / (C.A + C.B)
            yawRate += (kinYaw - yawRate) * k * min(1, dt * 12)
            vLat *= 1 - k * min(1, dt * 10)
        }
        yawRate *= 1 - min(1, dt * (airborne ? 0.1 : (g.road ? 0.35 : 1.2)))
        if abs(vLong) < 0.05 && thr == 0 && !airborne { vLong = 0; yawRate *= 0.9 }

        heading += yawRate * dt
        let s2 = sin(heading), c2 = cos(heading)
        vx = vLong * s2 + vLat * c2; vz = vLong * c2 - vLat * s2
        x += vx * dt; z += vz * dt
        longAccel = longAccel * 0.85 + aLong * contact * 0.15
        latAccel = latAccel * 0.85 + (vLong * yawRate) * contact * 0.15
        slip = max(abs(slipR) * min(1, v / 8) * contact, wheelspin / 25, locked ? 0.6 : 0, handbrake > 0 && v > 5 && !airborne ? 0.5 : 0)
        let targetRpm = wheelspin > 0 ? min(C.REDLINE + 150, rpmNow + wheelspin * 250) : rpmNow
        rpm += (targetRpm - rpm) * min(1, dt * 14)
        if shiftTimer > 0 { rpm *= 0.985 }
        if thr > 0 && abs(vLong) < 1 { rpm = max(rpm, C.IDLE + thr * 5200) }

        // Vertical: follow the ground under the axles, leave it over crests, land again.
        let fx = x + s2 * C.A, fz = z + c2 * C.A, rx = x - s2 * C.B, rz = z - c2 * C.B
        let hf = ground(fx, fz).y, hr = ground(rx, rz).y
        let lx = x + c2 * 0.8, lz = z - s2 * 0.8, qx = x - c2 * 0.8, qz = z + s2 * 0.8
        let hl = ground(lx, lz).y, hq = ground(qx, qz).y
        let gy = (hf + hr) / 2
        if airborne {
            vy -= 9.81 * dt
            y += vy * dt
            airTime += dt
            pitch += (atan2(-vy, max(v, 5)) * 0.35 - pitch) * min(1, dt * 2)
            if y <= gy {
                let impact = -vy
                y = gy; vy = 0; airborne = false
                if airTime > 0.25 { events.append(.landed(impact)) }
                airTime = 0
            }
        } else {
            let ballistic = y + vy * dt - 4.9 * dt * dt
            if v > 14 && ballistic > gy + 0.12 && vy > -40 {
                airborne = true; airTime = 0
                vy -= 9.81 * dt; y = ballistic
            } else {
                let newVy = (gy - y) / max(dt, 1e-3)
                vy = clampf(newVy, -30, 30)
                y = gy
            }
            let targetPitch = atan2(hr - hf, C.A + C.B)
            pitch += (targetPitch - pitch) * min(1, dt * 10)
        }
        let targetRoll = airborne ? roll : atan2(hl - hq, 1.6)
        roll += (targetRoll - roll) * min(1, dt * 8)
        if g.water && y < 0.2 && !airborne { events.append(.splash) }
    }
}

@inline(__always) func clampf(_ v: Float, _ a: Float, _ b: Float) -> Float { v < a ? a : (v > b ? b : v) }
@inline(__always) func sgn(_ v: Float) -> Float { v > 0 ? 1 : (v < 0 ? -1 : 0) }
