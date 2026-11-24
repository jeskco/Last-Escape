import SwiftUI

enum SteeringMode: String, CaseIterable, Identifiable { case buttons, tilt; var id: String { rawValue }
    var label: String { self == .buttons ? "Buttons" : "Tilt" } }
enum CameraMode: Int, CaseIterable { case chase, far, hood, bumper, cinematic
    var label: String { ["Chase", "Far chase", "Hood", "Bumper", "Cinematic"][rawValue] }
    var symbol: String { ["car.rear", "camera.viewfinder", "steeringwheel", "eye", "movieclapper"][rawValue] } }
enum TimeMode: String, CaseIterable, Identifiable { case cycle, fixed; var id: String { rawValue } }
enum CrashMode: String, CaseIterable, Identifiable { case off, normal, wild; var id: String { rawValue }
    var label: String { switch self { case .off: return "Off"; case .normal: return "Realistic"; case .wild: return "Wild" } }
    /// impact speed (m/s) needed to send the player's car tumbling
    var threshold: Float { switch self { case .off: return 999; case .normal: return 24; case .wild: return 13 } } }
enum Quality: String, CaseIterable, Identifiable { case battery, balanced, high, ultra; var id: String { rawValue }
    var label: String { rawValue.capitalized } }

struct Paint: Identifiable { let id: Int; let name: String; let color: UIColor; let metal: Float; let rough: Float }
let PAINTS: [Paint] = [
    Paint(id: 0, name: "Rosso Corsa", color: UIColor(red: 0.72, green: 0.05, blue: 0.03, alpha: 1), metal: 0.05, rough: 0.28),
    Paint(id: 1, name: "Bianco Avus", color: UIColor(red: 0.95, green: 0.95, blue: 0.94, alpha: 1), metal: 0.05, rough: 0.25),
    Paint(id: 2, name: "Nero Daytona", color: UIColor(red: 0.05, green: 0.05, blue: 0.06, alpha: 1), metal: 0.6, rough: 0.18),
    Paint(id: 3, name: "Giallo Modena", color: UIColor(red: 0.96, green: 0.77, blue: 0, alpha: 1), metal: 0.05, rough: 0.25),
    Paint(id: 4, name: "Blu Tour de France", color: UIColor(red: 0.07, green: 0.23, blue: 0.55, alpha: 1), metal: 0.7, rough: 0.2),
    Paint(id: 5, name: "Verde Abetone", color: UIColor(red: 0.06, green: 0.29, blue: 0.17, alpha: 1), metal: 0.7, rough: 0.2),
    Paint(id: 6, name: "Arancio Borealis", color: UIColor(red: 1, green: 0.35, blue: 0.05, alpha: 1), metal: 0.5, rough: 0.2),
    Paint(id: 7, name: "Grigio Titanio", color: UIColor(red: 0.44, green: 0.45, blue: 0.47, alpha: 1), metal: 0.85, rough: 0.25),
    Paint(id: 8, name: "Viola Hong Kong", color: UIColor(red: 0.29, green: 0.12, blue: 0.45, alpha: 1), metal: 0.8, rough: 0.2),
    Paint(id: 9, name: "Azzurro California", color: UIColor(red: 0.37, green: 0.71, blue: 0.9, alpha: 1), metal: 0.5, rough: 0.2),
]
struct Rim: Identifiable { let id: Int; let name: String; let color: UIColor; let metal: Float }
let RIMS: [Rim] = [
    Rim(id: 0, name: "Gloss Black", color: UIColor(white: 0.04, alpha: 1), metal: 0.66),
    Rim(id: 1, name: "Silver", color: UIColor(red: 0.79, green: 0.8, blue: 0.81, alpha: 1), metal: 1),
    Rim(id: 2, name: "Gold", color: UIColor(red: 0.79, green: 0.6, blue: 0.23, alpha: 1), metal: 1),
    Rim(id: 3, name: "Gunmetal", color: UIColor(red: 0.23, green: 0.24, blue: 0.27, alpha: 1), metal: 0.9),
    Rim(id: 4, name: "Bronze", color: UIColor(red: 0.48, green: 0.33, blue: 0.2, alpha: 1), metal: 1),
]

/// Persistent player settings.
final class GameSettings: ObservableObject {
    private let d = UserDefaults.standard
    private func save(_ v: Any, _ k: String) { d.set(v, forKey: k) }

    @Published var assist: Assist { didSet { save(assist.rawValue, "assist") } }
    @Published var steering: SteeringMode { didSet { save(steering.rawValue, "steering") } }
    @Published var tiltSensitivity: Double { didSet { save(tiltSensitivity, "tiltSens") } }
    @Published var invertTilt: Bool { didSet { save(invertTilt, "invertTilt") } }
    @Published var autoGearbox: Bool { didSet { save(autoGearbox, "autoGear") } }
    @Published var mph: Bool { didSet { save(mph, "mph") } }
    @Published var camera: CameraMode { didSet { save(camera.rawValue, "camera") } }
    @Published var fov: Double { didSet { save(fov, "fov") } }
    @Published var camDistance: Double { didSet { save(camDistance, "camDist") } }
    @Published var speedFov: Bool { didSet { save(speedFov, "speedFov") } }
    @Published var cameraShake: Bool { didSet { save(cameraShake, "camShake") } }
    @Published var quality: Quality { didSet { save(quality.rawValue, "quality") } }
    @Published var drawDistance: Double { didSet { save(drawDistance, "drawDist") } }
    @Published var vegetationDistance: Double { didSet { save(vegetationDistance, "vegDist") } }
    @Published var shadows: Bool { didSet { save(shadows, "shadows") } }
    @Published var bloom: Bool { didSet { save(bloom, "bloom") } }
    @Published var motionBlur: Bool { didSet { save(motionBlur, "motionBlur") } }
    @Published var fps: Int { didSet { save(fps, "fps") } }
    @Published var showFPS: Bool { didSet { save(showFPS, "showFPS") } }
    @Published var traffic: Double { didSet { save(traffic, "traffic") } }
    @Published var crash: CrashMode { didSet { save(crash.rawValue, "crash") } }
    @Published var debris: Bool { didSet { save(debris, "debris") } }
    @Published var timeMode: TimeMode { didSet { save(timeMode.rawValue, "timeMode") } }
    @Published var hour: Double { didSet { save(hour, "hour") } }
    @Published var dayLength: Double { didSet { save(dayLength, "dayLen") } }
    @Published var volume: Double { didSet { save(volume, "volume") } }
    @Published var minimap: Bool { didSet { save(minimap, "minimap") } }
    @Published var haptics: Bool { didSet { save(haptics, "haptics") } }
    @Published var paint: Int { didSet { save(paint, "paint") } }
    @Published var rims: Int { didSet { save(rims, "rims") } }
    @Published var spawn: Int { didSet { save(spawn, "spawn") } }

    init() {
        let d = UserDefaults.standard
        func s(_ k: String, _ def: String) -> String { d.string(forKey: k) ?? def }
        func b(_ k: String, _ def: Bool) -> Bool { d.object(forKey: k) == nil ? def : d.bool(forKey: k) }
        func n(_ k: String, _ def: Double) -> Double { d.object(forKey: k) == nil ? def : d.double(forKey: k) }
        func i(_ k: String, _ def: Int) -> Int { d.object(forKey: k) == nil ? def : d.integer(forKey: k) }
        assist = Assist(rawValue: s("assist", "full")) ?? .full
        steering = SteeringMode(rawValue: s("steering", "buttons")) ?? .buttons
        tiltSensitivity = n("tiltSens", 1.0)
        invertTilt = b("invertTilt", false)
        autoGearbox = b("autoGear", true)
        mph = b("mph", Locale.current.measurementSystem == .us)
        camera = CameraMode(rawValue: i("camera", 0)) ?? .chase
        fov = n("fov", 62)
        camDistance = n("camDist", 6.3)
        speedFov = b("speedFov", true)
        cameraShake = b("camShake", true)
        quality = Quality(rawValue: s("quality", "high")) ?? .high
        drawDistance = n("drawDist", 1500)
        vegetationDistance = n("vegDist", 650)
        shadows = b("shadows", true)
        bloom = b("bloom", true)
        motionBlur = b("motionBlur", false)
        fps = i("fps", 60)
        showFPS = b("showFPS", false)
        traffic = n("traffic", 18)
        crash = CrashMode(rawValue: s("crash", "normal")) ?? .normal
        debris = b("debris", true)
        timeMode = TimeMode(rawValue: s("timeMode", "cycle")) ?? .cycle
        hour = n("hour", 16.5)
        dayLength = n("dayLen", 24)
        volume = n("volume", 0.8)
        minimap = b("minimap", true)
        haptics = b("haptics", true)
        paint = i("paint", 0)
        rims = i("rims", 0)
        spawn = i("spawn", 0)
    }

    func applyQuality(_ q: Quality) {
        quality = q
        switch q {
        case .battery: drawDistance = 900; vegetationDistance = 350; shadows = false; bloom = false; fps = 30; traffic = 10
        case .balanced: drawDistance = 1200; vegetationDistance = 500; shadows = true; bloom = true; fps = 60; traffic = 14
        case .high: drawDistance = 1500; vegetationDistance = 650; shadows = true; bloom = true; fps = 60; traffic = 18
        case .ultra: drawDistance = 2200; vegetationDistance = 900; shadows = true; bloom = true; fps = 120; traffic = 28
        }
    }
}
