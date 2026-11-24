import SwiftUI
import Combine

/// Every user preference, saved to UserDefaults and observed by the viewer, camera and UI.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let d = UserDefaults.standard
    private func load<T>(_ key: String, _ def: T) -> T { d.object(forKey: key) as? T ?? def }

    // Performance
    @Published var fps: Int { didSet { d.set(fps, forKey: "fps") } }
    @Published var antialiasing: Int { didSet { d.set(antialiasing, forKey: "antialiasing") } }        // 0, 2, 4
    @Published var hdr: Bool { didSet { d.set(hdr, forKey: "hdr") } }
    @Published var bloom: Bool { didSet { d.set(bloom, forKey: "bloom") } }
    @Published var shadowQuality: Int { didSet { d.set(shadowQuality, forKey: "shadowQuality") } }      // 0 off, 1 low, 2 high
    @Published var batterySaver: Bool { didSet { d.set(batterySaver, forKey: "batterySaver") } }
    @Published var showStats: Bool { didSet { d.set(showStats, forKey: "showStats") } }

    // Controls
    @Published var orbitSpeed: Double { didSet { d.set(orbitSpeed, forKey: "orbitSpeed") } }
    @Published var smoothness: Double { didSet { d.set(smoothness, forKey: "smoothness") } }          // 0 = direct, 1 = very smooth
    @Published var momentum: Bool { didSet { d.set(momentum, forKey: "momentum") } }
    @Published var momentumFriction: Double { didSet { d.set(momentumFriction, forKey: "momentumFriction") } } // 0 long glide, 1 quick stop
    @Published var zoomSpeed: Double { didSet { d.set(zoomSpeed, forKey: "zoomSpeed") } }
    @Published var zoomToFingers: Bool { didSet { d.set(zoomToFingers, forKey: "zoomToFingers") } }
    @Published var twistToRotate: Bool { didSet { d.set(twistToRotate, forKey: "twistToRotate") } }
    @Published var twoFingerPan: Bool { didSet { d.set(twoFingerPan, forKey: "twoFingerPan") } }
    @Published var invertX: Bool { didSet { d.set(invertX, forKey: "invertX") } }
    @Published var invertY: Bool { didSet { d.set(invertY, forKey: "invertY") } }
    @Published var allowBelow: Bool { didSet { d.set(allowBelow, forKey: "allowBelow") } }
    @Published var doubleTapReset: Bool { didSet { d.set(doubleTapReset, forKey: "doubleTapReset") } }
    @Published var turntableSpeed: Double { didSet { d.set(turntableSpeed, forKey: "turntableSpeed") } }

    // Viewer defaults
    @Published var defaultFOV: Double { didSet { d.set(defaultFOV, forKey: "defaultFOV") } }
    @Published var defaultEnvironment: String { didSet { d.set(defaultEnvironment, forKey: "defaultEnvironment") } }
    @Published var defaultSkeleton: Bool { didSet { d.set(defaultSkeleton, forKey: "defaultSkeleton") } }
    @Published var defaultGroundShadow: Bool { didSet { d.set(defaultGroundShadow, forKey: "defaultGroundShadow") } }
    @Published var units: String { didSet { d.set(units, forKey: "units") } }                        // m, cm, in, ft

    // Animation
    @Published var autoplay: Bool { didSet { d.set(autoplay, forKey: "autoplay") } }
    @Published var loopAnimations: Bool { didSet { d.set(loopAnimations, forKey: "loopAnimations") } }
    @Published var defaultSpeed: Double { didSet { d.set(defaultSpeed, forKey: "defaultSpeed") } }

    // Appearance & interface
    @Published var appearance: Int { didSet { d.set(appearance, forKey: "appearance") } }              // 0 system, 1 light, 2 dark
    @Published var backgroundStyle: Int { didSet { d.set(backgroundStyle, forKey: "backgroundStyle") } } // 0 gradient, 1 plain, 2 black, 3 white
    @Published var solidPanels: Bool { didSet { d.set(solidPanels, forKey: "solidPanels") } }
    @Published var haptics: Bool { didSet { d.set(haptics, forKey: "haptics") } }
    @Published var showHints: Bool { didSet { d.set(showHints, forKey: "showHints") } }
    @Published var libraryOnLaunch: Bool { didSet { d.set(libraryOnLaunch, forKey: "libraryOnLaunch") } }
    @Published var startExpanded: Bool { didSet { d.set(startExpanded, forKey: "startExpanded") } }

    // Files & AR
    @Published var maxRecents: Int { didSet { d.set(maxRecents, forKey: "maxRecents") } }
    @Published var arFitSize: Bool { didSet { d.set(arFitSize, forKey: "arFitSize") } }

    private init() {
        let d = UserDefaults.standard
        func l<T>(_ k: String, _ v: T) -> T { d.object(forKey: k) as? T ?? v }
        fps = l("fps", 120); antialiasing = l("antialiasing", 4); hdr = l("hdr", true); bloom = l("bloom", true)
        shadowQuality = l("shadowQuality", 2); batterySaver = l("batterySaver", false); showStats = l("showStats", false)
        orbitSpeed = l("orbitSpeed", 1.0); smoothness = l("smoothness", 0.5); momentum = l("momentum", true)
        momentumFriction = l("momentumFriction", 0.5); zoomSpeed = l("zoomSpeed", 1.0); zoomToFingers = l("zoomToFingers", true)
        twistToRotate = l("twistToRotate", true); twoFingerPan = l("twoFingerPan", true); invertX = l("invertX", false); invertY = l("invertY", false)
        allowBelow = l("allowBelow", true); doubleTapReset = l("doubleTapReset", true); turntableSpeed = l("turntableSpeed", 1.0)
        defaultFOV = l("defaultFOV", 38.0); defaultEnvironment = l("defaultEnvironment", "studio"); defaultSkeleton = l("defaultSkeleton", true)
        defaultGroundShadow = l("defaultGroundShadow", true); units = l("units", "m")
        autoplay = l("autoplay", true); loopAnimations = l("loopAnimations", true); defaultSpeed = l("defaultSpeed", 1.0)
        appearance = l("appearance", 0); backgroundStyle = l("backgroundStyle", 0); solidPanels = l("solidPanels", false)
        haptics = l("haptics", true); showHints = l("showHints", true); libraryOnLaunch = l("libraryOnLaunch", true); startExpanded = l("startExpanded", false)
        maxRecents = l("maxRecents", 25); arFitSize = l("arFitSize", true)
    }

    /// Easing time constant in seconds for the camera, from the Smoothness slider.
    var cameraTau: Float { Float(0.012 + smoothness * smoothness * 0.22) }
    /// Momentum decay rate per second, from the friction slider.
    var momentumDecay: Float { Float(1.5 + momentumFriction * 9) }

    var colorScheme: ColorScheme? { appearance == 1 ? .light : appearance == 2 ? .dark : nil }

    func formatLength(_ meters: Float) -> String {
        switch units {
        case "cm": return Fmt.len(meters * 100) + " cm"
        case "in": return Fmt.len(meters * 39.3701) + " in"
        case "ft": return Fmt.len(meters * 3.28084) + " ft"
        default: return Fmt.len(meters) + " m"
        }
    }

    func resetAll() {
        for k in ["fps", "antialiasing", "hdr", "bloom", "shadowQuality", "batterySaver", "showStats", "orbitSpeed", "smoothness", "momentum",
                  "momentumFriction", "zoomSpeed", "zoomToFingers", "twistToRotate", "twoFingerPan", "invertX", "invertY", "allowBelow",
                  "doubleTapReset", "turntableSpeed", "defaultFOV", "defaultEnvironment", "defaultSkeleton", "defaultGroundShadow", "units",
                  "autoplay", "loopAnimations", "defaultSpeed", "appearance", "backgroundStyle", "solidPanels", "haptics", "showHints",
                  "libraryOnLaunch", "startExpanded", "maxRecents", "arFitSize", "accentIndex"] { d.removeObject(forKey: k) }
        let fresh = AppSettings(resetting: ())
        fps = fresh.fps; antialiasing = fresh.antialiasing; hdr = fresh.hdr; bloom = fresh.bloom; shadowQuality = fresh.shadowQuality
        batterySaver = fresh.batterySaver; showStats = fresh.showStats; orbitSpeed = fresh.orbitSpeed; smoothness = fresh.smoothness
        momentum = fresh.momentum; momentumFriction = fresh.momentumFriction; zoomSpeed = fresh.zoomSpeed; zoomToFingers = fresh.zoomToFingers
        twistToRotate = fresh.twistToRotate; twoFingerPan = fresh.twoFingerPan; invertX = fresh.invertX; invertY = fresh.invertY
        allowBelow = fresh.allowBelow; doubleTapReset = fresh.doubleTapReset; turntableSpeed = fresh.turntableSpeed; defaultFOV = fresh.defaultFOV
        defaultEnvironment = fresh.defaultEnvironment; defaultSkeleton = fresh.defaultSkeleton; defaultGroundShadow = fresh.defaultGroundShadow
        units = fresh.units; autoplay = fresh.autoplay; loopAnimations = fresh.loopAnimations; defaultSpeed = fresh.defaultSpeed
        appearance = fresh.appearance; backgroundStyle = fresh.backgroundStyle; solidPanels = fresh.solidPanels; haptics = fresh.haptics
        showHints = fresh.showHints; libraryOnLaunch = fresh.libraryOnLaunch; startExpanded = fresh.startExpanded; maxRecents = fresh.maxRecents
        arFitSize = fresh.arFitSize
    }
    private convenience init(resetting: Void) { self.init() }
}

@MainActor
enum Haptics {
    static func tap(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        guard AppSettings.shared.haptics else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
    static func select() {
        guard AppSettings.shared.haptics else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
