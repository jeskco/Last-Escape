import SwiftUI
import SceneKit

/// Studio's 3D view: taps select, one-finger drags on a gizmo/mesh edit or sculpt, everything else moves the camera.
struct StudioSceneView: UIViewRepresentable {
    @ObservedObject var model: StudioModel
    @ObservedObject var settings = AppSettings.shared

    func makeCoordinator() -> Coordinator { Coordinator(model) }

    func makeUIView(context: Context) -> SCNView {
        let v = SCNView(frame: .zero, options: [SCNView.Option.preferredRenderingAPI.rawValue: SCNRenderingAPI.metal.rawValue])
        v.backgroundColor = .clear
        v.scene = model.scene
        v.pointOfView = model.cameraNode
        v.allowsCameraControl = false
        v.rendersContinuously = true
        v.antialiasingMode = settings.antialiasing >= 4 ? .multisampling4X : settings.antialiasing >= 2 ? .multisampling2X : .none
        v.preferredFramesPerSecond = settings.fps
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:)))
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:)))
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator
        context.coordinator.pan = pan
        v.addGestureRecognizer(tap); v.addGestureRecognizer(pan)
        model.attach(v)
        return v
    }

    func updateUIView(_ v: SCNView, context: Context) {
        v.showsStatistics = settings.showStats
    }

    static func dismantleUIView(_ v: SCNView, coordinator: Coordinator) { coordinator.model.detach() }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let model: StudioModel
        weak var pan: UIPanGestureRecognizer?
        init(_ m: StudioModel) { model = m }

        @MainActor @objc func tap(_ g: UITapGestureRecognizer) { model.handleTap(at: g.location(in: g.view)) }

        @MainActor @objc func pan(_ g: UIPanGestureRecognizer) {
            let p = g.location(in: g.view), t = g.translation(in: g.view)
            switch g.state {
            case .began: model.dragBegan(at: p)
            case .changed: model.dragChanged(at: p, translation: t)
            case .ended, .cancelled, .failed: model.dragEnded()
            default: break
            }
        }

        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            guard g === pan, let v = g.view else { return true }
            let p = g.location(in: v)
            return MainActor.assumeIsolated { model.dragTarget(at: p) != nil }
        }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { false }
    }
}

/// Presents a share sheet for exported files.
@MainActor
enum SharePresenter {
    static func share(_ url: URL) {
        let windows = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }
        guard var top = windows.first?.rootViewController else { return }
        while let p = top.presentedViewController, !p.isBeingDismissed { top = p }
        let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        vc.popoverPresentationController?.sourceView = top.view
        vc.popoverPresentationController?.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 1, height: 1)
        top.present(vc, animated: true)
    }
}
