import SwiftUI
import SceneKit

/// The SceneKit view: native Metal rendering, orbit / pinch / pan camera, single and double tap callbacks.
struct SceneViewer: UIViewRepresentable {
    @ObservedObject var model: ViewerModel
    @ObservedObject var settings = AppSettings.shared
    var onSingleTap: () -> Void
    var onDoubleTap: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> SCNView {
        let v = SCNView(frame: .zero, options: [SCNView.Option.preferredRenderingAPI.rawValue: SCNRenderingAPI.metal.rawValue])
        v.backgroundColor = .clear
        v.allowsCameraControl = false
        v.isJitteringEnabled = false
        v.scene = model.scene
        v.pointOfView = model.cameraNode
        model.orbit.attach(to: v)
        applySettings(v)
        let dbl = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTap)); dbl.numberOfTapsRequired = 2
        let sgl = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.singleTap)); sgl.require(toFail: dbl); dbl.delaysTouchesEnded = false
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
        applySettings(v)
    }

    private func applySettings(_ v: SCNView) {
        let fps = settings.batterySaver ? min(60, settings.fps) : settings.fps
        if v.preferredFramesPerSecond != fps { v.preferredFramesPerSecond = fps; model.orbit.setFrameRate(fps) }
        let aa: SCNAntialiasingMode = settings.antialiasing >= 4 ? .multisampling4X : settings.antialiasing >= 2 ? .multisampling2X : .none
        if v.antialiasingMode != aa { v.antialiasingMode = aa }
        if v.rendersContinuously == settings.batterySaver { v.rendersContinuously = !settings.batterySaver }
        if v.showsStatistics != settings.showStats { v.showsStatistics = settings.showStats }
    }

    final class Coordinator: NSObject {
        var parent: SceneViewer
        init(_ p: SceneViewer) { parent = p }
        @objc func singleTap() { parent.onSingleTap() }
        @objc func doubleTap() { parent.onDoubleTap() }
    }
}
