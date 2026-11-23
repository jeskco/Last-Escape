import SwiftUI
import SceneKit

/// The SceneKit view: native Metal rendering, orbit / pinch / pan camera, single and double tap callbacks.
struct SceneViewer: UIViewRepresentable {
    @ObservedObject var model: ViewerModel
    var onSingleTap: () -> Void
    var onDoubleTap: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> SCNView {
        let v = SCNView(frame: .zero, options: [SCNView.Option.preferredRenderingAPI.rawValue: SCNRenderingAPI.metal.rawValue])
        v.backgroundColor = .clear
        v.allowsCameraControl = true
        v.antialiasingMode = .multisampling4X
        v.rendersContinuously = true
        v.preferredFramesPerSecond = 120
        v.isJitteringEnabled = false
        v.scene = model.scene
        v.pointOfView = model.cameraNode
        v.defaultCameraController.interactionMode = .orbitTurntable
        v.defaultCameraController.inertiaEnabled = true
        v.defaultCameraController.inertiaFriction = 0.08
        let dbl = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTap)); dbl.numberOfTapsRequired = 2
        let sgl = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.singleTap)); sgl.require(toFail: dbl)
        v.addGestureRecognizer(dbl); v.addGestureRecognizer(sgl)
        model.view = v
        Task { @MainActor in model.frame(animated: false) }
        return v
    }

    func updateUIView(_ v: SCNView, context: Context) {
        context.coordinator.parent = self
        if v.scene !== model.scene { v.scene = model.scene; v.pointOfView = model.cameraNode }
        let opts = model.debugOptions()
        if v.debugOptions != opts { v.debugOptions = opts }
    }

    final class Coordinator: NSObject {
        var parent: SceneViewer
        init(_ p: SceneViewer) { parent = p }
        @objc func singleTap() { parent.onSingleTap() }
        @objc func doubleTap() { parent.onDoubleTap() }
    }
}
