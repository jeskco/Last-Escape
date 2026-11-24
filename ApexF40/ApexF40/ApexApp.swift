import SwiftUI
import SceneKit

@main
struct ApexApp: App {
    @StateObject private var game = Game()
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(game)
                .environmentObject(game.settings)
                .preferredColorScheme(.dark)
                .statusBarHidden(true)
                .persistentSystemOverlays(.hidden)
        }
    }
}

/// Hosts the SceneKit view. A pan on empty screen space looks around the car.
struct GameSceneView: UIViewRepresentable {
    let game: Game
    func makeCoordinator() -> Coordinator { Coordinator(game) }
    func makeUIView(context: Context) -> SCNView {
        let v = SCNView(frame: .zero, options: [SCNView.Option.preferredRenderingAPI.rawValue: SCNRenderingAPI.metal.rawValue])
        game.attach(v)
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:)))
        pan.maximumNumberOfTouches = 1
        v.addGestureRecognizer(pan)
        return v
    }
    func updateUIView(_ v: SCNView, context: Context) {
        if let o = v.window?.windowScene?.interfaceOrientation { game.interfaceOrientation = o }
    }
    final class Coordinator: NSObject {
        let game: Game
        private var start: Float = 0
        init(_ g: Game) { game = g }
        @objc func pan(_ g: UIPanGestureRecognizer) {
            switch g.state {
            case .began: start = game.input.lookYaw; game.input.looking = true
            case .changed: game.input.lookYaw = max(-.pi, min(.pi, start - Float(g.translation(in: g.view).x) * 0.008))
            default: game.input.looking = false
            }
            if let o = g.view?.window?.windowScene?.interfaceOrientation { game.interfaceOrientation = o }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var game: Game
    @EnvironmentObject var settings: GameSettings
    @State private var showSettings = false

    var body: some View {
        ZStack {
            GameSceneView(game: game).ignoresSafeArea()
            switch game.phase {
            case .loading: LoadingView()
            case .menu: MenuView(showSettings: $showSettings)
            case .driving: DriveHUD()
            case .paused: PauseView(showSettings: $showSettings)
            case .map: WorldMapView()
            }
            if let e = game.errorText {
                Text(e).font(.headline).padding(20).glass(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
        .sheet(isPresented: $showSettings, onDismiss: { game.applyGraphics(); game.applyPaint() }) {
            SettingsView().environmentObject(game).environmentObject(settings)
        }
        .animation(.easeInOut(duration: 0.25), value: game.phase)
    }
}
