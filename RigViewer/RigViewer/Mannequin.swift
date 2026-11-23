import SceneKit
import UIKit

/// The built-in sample: an articulated ceramic mannequin with a walk and a wave.
enum Mannequin {
    static func make() -> (scene: SCNScene, clips: [ClipInfo]) {
        let scene = SCNScene()
        let body = SCNMaterial(); body.lightingModel = .physicallyBased; body.diffuse.contents = UIColor(red: 0.86, green: 0.87, blue: 0.9, alpha: 1); body.roughness.contents = 0.38; body.metalness.contents = 0.05
        let joint = SCNMaterial(); joint.lightingModel = .physicallyBased; joint.diffuse.contents = UIColor.systemBlue; joint.roughness.contents = 0.3; joint.metalness.contents = 0.2
        func node(_ name: String, _ parent: SCNNode, _ p: SIMD3<Float>) -> SCNNode { let n = SCNNode(); n.name = "joint:" + name; n.simdPosition = p; parent.addChildNode(n); return n }
        func capsule(_ on: SCNNode, len: Float, r: Float, down: Bool = true) {
            let g = SCNCapsule(capRadius: CGFloat(r), height: CGFloat(len)); g.materials = [body]
            let m = SCNNode(geometry: g); m.simdPosition = SIMD3(0, down ? -len / 2 : len / 2, 0); on.addChildNode(m)
            let s = SCNSphere(radius: CGFloat(r * 0.8)); s.materials = [joint]; on.addChildNode(SCNNode(geometry: s))
        }
        let root = SCNNode(); root.name = "Mannequin"; scene.rootNode.addChildNode(root)
        let hips = node("Hips", root, SIMD3(0, 0.98, 0))
        let spine = node("Spine", hips, SIMD3(0, 0.1, 0))
        let chest = node("Chest", spine, SIMD3(0, 0.2, 0))
        let neck = node("Neck", chest, SIMD3(0, 0.26, 0))
        let head = node("Head", neck, SIMD3(0, 0.1, 0))
        let torso = SCNNode(geometry: { let g = SCNCapsule(capRadius: 0.15, height: 0.56); g.materials = [body]; return g }()); torso.simdScale = SIMD3(1.15, 1, 0.75); torso.simdPosition = SIMD3(0, 0.1, 0); chest.addChildNode(torso)
        let pelvis = SCNNode(geometry: { let g = SCNCapsule(capRadius: 0.13, height: 0.32); g.materials = [body]; return g }()); pelvis.simdScale = SIMD3(1.25, 0.6, 0.8); hips.addChildNode(pelvis)
        let skull = SCNNode(geometry: { let g = SCNSphere(radius: 0.11); g.materials = [body]; return g }()); skull.simdScale = SIMD3(0.9, 1.1, 1); skull.simdPosition = SIMD3(0, 0.1, 0); head.addChildNode(skull)
        var limbs: [String: SCNNode] = [:]
        for (side, x) in [("Left", Float(0.21)), ("Right", Float(-0.21))] {
            let arm = node(side + "Arm", chest, SIMD3(x, 0.21, 0)); capsule(arm, len: 0.29, r: 0.05)
            let fore = node(side + "ForeArm", arm, SIMD3(0, -0.29, 0)); capsule(fore, len: 0.26, r: 0.042)
            let hand = node(side + "Hand", fore, SIMD3(0, -0.26, 0)); capsule(hand, len: 0.1, r: 0.035)
            let up = node(side + "UpLeg", hips, SIMD3(x * 0.5, -0.06, 0)); capsule(up, len: 0.43, r: 0.07)
            let leg = node(side + "Leg", up, SIMD3(0, -0.43, 0)); capsule(leg, len: 0.42, r: 0.055)
            let foot = node(side + "Foot", leg, SIMD3(0, -0.42, 0))
            let f = SCNNode(geometry: { let g = SCNBox(width: 0.09, height: 0.06, length: 0.22, chamferRadius: 0.025); g.materials = [body]; return g }()); f.simdPosition = SIMD3(0, -0.03, 0.06); foot.addChildNode(f)
            arm.eulerAngles.z = (side == "Left" ? 1 : -1) * 0.12
            limbs[side + "Arm"] = arm; limbs[side + "ForeArm"] = fore; limbs[side + "UpLeg"] = up; limbs[side + "Leg"] = leg
        }
        func swing(_ n: SCNNode, _ key: String, _ values: [Float], _ dur: Double) -> SCNAnimationPlayer {
            let a = CAKeyframeAnimation(keyPath: key)
            a.values = values.map { NSNumber(value: $0) }; a.duration = dur; a.calculationMode = .cubic
            let sa = SCNAnimation(caAnimation: a); sa.repeatCount = .greatestFiniteMagnitude; sa.isRemovedOnCompletion = false
            let p = SCNAnimationPlayer(animation: sa); p.stop(); n.addAnimationPlayer(p, forKey: key + (n.name ?? "")); return p
        }
        let T = 1.1
        let fwd: [Float] = [0, -0.45, 0, 0.45, 0], back: [Float] = [0, 0.45, 0, -0.45, 0]
        var walk: [SCNAnimationPlayer] = []
        walk.append(swing(limbs["LeftUpLeg"]!, "eulerAngles.x", fwd, T))
        walk.append(swing(limbs["RightUpLeg"]!, "eulerAngles.x", back, T))
        walk.append(swing(limbs["LeftLeg"]!, "eulerAngles.x", [0.08, 0.08, 0.5, 0.08, 0.08], T))
        walk.append(swing(limbs["RightLeg"]!, "eulerAngles.x", [0.5, 0.08, 0.08, 0.08, 0.5], T))
        walk.append(swing(limbs["LeftArm"]!, "eulerAngles.x", back.map { $0 * 0.8 }, T))
        walk.append(swing(limbs["RightArm"]!, "eulerAngles.x", fwd.map { $0 * 0.8 }, T))
        walk.append(swing(chest, "eulerAngles.y", [0, 0.14, 0, -0.14, 0], T))
        walk.append(swing(hips, "position.y", [0.98, 0.995, 0.98, 0.995, 0.98], T / 2))
        var wave: [SCNAnimationPlayer] = []
        wave.append(swing(limbs["RightArm"]!, "eulerAngles.z", [-2.5, -2.55, -2.5], 2))
        wave.append(swing(limbs["RightForeArm"]!, "eulerAngles.z", [0, -0.35, 0.35, -0.35, 0], 2))
        wave.append(swing(head, "eulerAngles.y", [-0.25, -0.2, -0.25], 2))
        return (scene, [ClipInfo(name: "Walk", duration: T, players: walk), ClipInfo(name: "Wave", duration: 2, players: wave)])
    }
}
