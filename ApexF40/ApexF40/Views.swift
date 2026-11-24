import SwiftUI

let mapImage: UIImage? = Res.image("map.jpg", "World")
let appVersion: String = "v" + ((Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "?") + " (" + ((Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "?") + ")"

// MARK: - Building blocks

/// A button that reports press and release (multi-touch friendly).
struct HoldButton<Label: View>: View {
    var onChange: (Bool) -> Void
    @ViewBuilder var label: (Bool) -> Label
    @State private var pressed = false
    var body: some View {
        label(pressed)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in if !pressed { pressed = true; onChange(true) } }
                .onEnded { _ in pressed = false; onChange(false) })
    }
}

struct PedalLabel: View {
    let symbol: String
    let text: String
    let tint: Color
    let pressed: Bool
    var w: CGFloat = 86, h: CGFloat = 86
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 26, weight: .bold))
            Text(text).font(.system(size: 11, weight: .heavy)).tracking(1)
        }
        .foregroundStyle(.white)
        .frame(width: w, height: h)
        .background(tint.opacity(pressed ? 0.55 : 0.22), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .glass(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .scaleEffect(pressed ? 0.93 : 1)
        .animation(.spring(response: 0.2, dampingFraction: 0.6), value: pressed)
    }
}

struct RoundIcon: View {
    let symbol: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 17, weight: .semibold)).frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .glass(Circle(), interactive: true)
    }
}

// MARK: - Loading

struct LoadingView: View {
    @EnvironmentObject var game: Game
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.05, green: 0.05, blue: 0.08), Color(red: 0.18, green: 0.03, blue: 0.02)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            VStack(spacing: 18) {
                Text("APEX F40").font(.system(size: 54, weight: .black, design: .rounded)).italic()
                Text("OPEN WORLD").font(.system(size: 15, weight: .bold)).tracking(8).foregroundStyle(.secondary)
                ProgressView(value: game.loadProgress).tint(.red).frame(width: 260)
                Text(game.loadText).font(.footnote).foregroundStyle(.secondary)
                Text(appVersion).font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Menu

struct MenuView: View {
    @EnvironmentObject var game: Game
    @EnvironmentObject var settings: GameSettings
    @Binding var showSettings: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("APEX F40").font(.system(size: 44, weight: .black, design: .rounded)).italic()
                    Text("OPEN WORLD · CA · AZ · TX · FL · NY").font(.system(size: 11, weight: .bold)).tracking(3).foregroundStyle(.secondary)
                    Text(appVersion).font(.caption2).foregroundStyle(.tertiary)
                }
                Text("Start in").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 8) {
                        ForEach(Array((game.world?.meta.spawns ?? []).enumerated()), id: \.offset) { i, s in
                            let reg = WorldRegion.at(x: s.x, z: s.z)
                            Button {
                                settings.spawn = i
                                game.placeAt(spawn: i)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: reg.symbol).font(.title3).foregroundStyle(Color(reg.tint)).frame(width: 30)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(s.name).font(.headline)
                                        Text(s.region).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if settings.spawn == i { Image(systemName: "checkmark.circle.fill").foregroundStyle(.red) }
                                }
                                .padding(.horizontal, 14).padding(.vertical, 9)
                                .background(Color.white.opacity(settings.spawn == i ? 0.14 : 0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 250)
                HStack(spacing: 10) {
                    Button { game.start() } label: {
                        Label(game.streaming < 0.95 ? "Streaming \(Int(game.streaming * 100))%" : "Drive", systemImage: "flag.checkered")
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .glassButton(prominent: true)
                    .tint(.red)
                    .disabled(game.streaming < 0.6)
                    Button { showSettings = true } label: { Image(systemName: "gearshape.fill").padding(.vertical, 6) }
                        .glassButton()
                }
            }
            .padding(22)
            .frame(width: 330)
            .glass(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .padding(.leading, 18).padding(.vertical, 14)
            Spacer()
            VStack(alignment: .trailing, spacing: 10) {
                Spacer()
                VStack(alignment: .leading, spacing: 8) {
                    Text(PAINTS[min(settings.paint, PAINTS.count - 1)].name).font(.subheadline.weight(.semibold))
                    HStack(spacing: 8) {
                        ForEach(PAINTS) { p in
                            Circle().fill(Color(p.color)).frame(width: 26, height: 26)
                                .overlay(Circle().stroke(.white, lineWidth: settings.paint == p.id ? 2.5 : 0.5))
                                .onTapGesture { settings.paint = p.id; game.applyPaint() }
                        }
                    }
                    HStack(spacing: 8) {
                        Text("Wheels").font(.caption).foregroundStyle(.secondary)
                        ForEach(RIMS) { r in
                            Circle().fill(Color(r.color)).frame(width: 20, height: 20)
                                .overlay(Circle().stroke(.white, lineWidth: settings.rims == r.id ? 2 : 0.5))
                                .onTapGesture { settings.rims = r.id; game.applyPaint() }
                        }
                    }
                }
                .padding(14)
                .glass(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .padding(18)
        }
    }
}

// MARK: - Driving HUD

struct DriveHUD: View {
    @EnvironmentObject var game: Game
    @EnvironmentObject var settings: GameSettings
    @State private var bannerVisible = false

    var body: some View {
        let h = game.hud
        ZStack {
            // Top left: minimap + place
            VStack(alignment: .leading, spacing: 8) {
                if settings.minimap { MiniMap(hud: h).frame(width: 138, height: 138) }
                HStack(spacing: 6) {
                    Image(systemName: h.region.symbol).foregroundStyle(Color(h.region.tint))
                    Text(h.place).font(.caption.weight(.semibold))
                    Text(h.clock).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .glass(Capsule())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.leading, 14).padding(.top, 10)

            // Top right: buttons
            HStack(spacing: 8) {
                RoundIcon(symbol: h.lights ? "headlight.high.beam.fill" : "headlight.low.beam") { game.toggleLights() }
                RoundIcon(symbol: settings.camera.symbol) { game.cycleCamera() }
                RoundIcon(symbol: "map.fill") { game.openMap() }
                RoundIcon(symbol: "pause.fill") { game.pause() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(.trailing, 14).padding(.top, 10)

            // Banner
            if let b = game.banner, bannerVisible {
                VStack(spacing: 2) {
                    Text(b.subtitle.uppercased()).font(.system(size: 11, weight: .bold)).tracking(4).foregroundStyle(Color(b.region.tint))
                    Text(b.title).font(.system(size: 30, weight: .black, design: .rounded)).italic()
                }
                .padding(.horizontal, 26).padding(.vertical, 10)
                .glass(Capsule())
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, 14)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Centre messages
            VStack(spacing: 8) {
                if h.drift > 0 {
                    Text("DRIFT \(h.drift)").font(.system(size: 26, weight: .black, design: .rounded)).italic().foregroundStyle(.orange)
                        .shadow(radius: 6)
                }
                if h.airborne && h.airTime > 0.4 {
                    Text(String(format: "AIR %.1fs", h.airTime)).font(.system(size: 22, weight: .black, design: .rounded)).foregroundStyle(.cyan).shadow(radius: 6)
                }
                if h.crashed {
                    Button { game.resetCar() } label: { Label("Reset car", systemImage: "arrow.uturn.backward.circle.fill").font(.headline).padding(.vertical, 4) }
                        .glassButton(prominent: true).tint(.red)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(.bottom, 80)

            // Speedometer
            Speedo(hud: h, mph: settings.mph)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 8)

            Controls()

            if game.streaming < 0.75 {
                VStack(spacing: 10) {
                    ProgressView().tint(.white)
                    Text("Arriving… \(Int(game.streaming * 100))%").font(.headline)
                }
                .padding(24).glass(RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
        }
        .onChange(of: game.banner) { _, b in
            guard b != nil else { return }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { bannerVisible = true }
            let id = b?.id
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) {
                if game.banner?.id == id { withAnimation(.easeInOut(duration: 0.4)) { bannerVisible = false } }
            }
        }
        .onAppear {
            if game.banner != nil {
                bannerVisible = true
                let id = game.banner?.id
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) { if game.banner?.id == id { withAnimation { bannerVisible = false } } }
            }
        }
    }
}

struct Controls: View {
    @EnvironmentObject var game: Game
    @EnvironmentObject var settings: GameSettings
    var body: some View {
        ZStack {
            if settings.steering == .buttons {
                HStack(spacing: 14) {
                    HoldButton(onChange: { game.input.left = $0 }) { PedalLabel(symbol: "arrowtriangle.left.fill", text: "LEFT", tint: .white, pressed: $0, w: 96, h: 96) }
                    HoldButton(onChange: { game.input.right = $0 }) { PedalLabel(symbol: "arrowtriangle.right.fill", text: "RIGHT", tint: .white, pressed: $0, w: 96, h: 96) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.leading, 22).padding(.bottom, 18)
            } else {
                HoldButton(onChange: { game.input.horn = $0 }) { PedalLabel(symbol: "speaker.wave.3.fill", text: "HORN", tint: .yellow, pressed: $0, w: 70, h: 70) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(.leading, 22).padding(.bottom, 18)
            }
            HStack(alignment: .bottom, spacing: 12) {
                VStack(spacing: 12) {
                    HoldButton(onChange: { game.input.handbrake = $0 }) { PedalLabel(symbol: "exclamationmark.brakesignal", text: "E-BRAKE", tint: .orange, pressed: $0, w: 80, h: 62) }
                    HoldButton(onChange: { game.input.brake = $0 }) { PedalLabel(symbol: "chevron.down.2", text: "BRAKE", tint: .blue, pressed: $0, w: 80, h: 92) }
                }
                VStack(spacing: 12) {
                    if !settings.autoGearbox {
                        HStack(spacing: 8) {
                            Button { game.input.shiftDown = true } label: { Image(systemName: "minus").frame(width: 36, height: 36) }.buttonStyle(.plain).glass(Circle(), interactive: true)
                            Button { game.input.shiftUp = true } label: { Image(systemName: "plus").frame(width: 36, height: 36) }.buttonStyle(.plain).glass(Circle(), interactive: true)
                        }
                    } else if settings.steering == .buttons {
                        HoldButton(onChange: { game.input.horn = $0 }) { PedalLabel(symbol: "speaker.wave.3.fill", text: "HORN", tint: .yellow, pressed: $0, w: 92, h: 44) }
                    }
                    HoldButton(onChange: { game.input.gas = $0 }) { PedalLabel(symbol: "chevron.up.2", text: "GAS", tint: .green, pressed: $0, w: 92, h: 128) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(.trailing, 22).padding(.bottom, 18)
        }
    }
}

struct Speedo: View {
    let hud: HUDState
    let mph: Bool
    var body: some View {
        let v = hud.speed * (mph ? 2.23694 : 3.6)
        ZStack {
            Circle().trim(from: 0, to: 0.72).stroke(Color.white.opacity(0.18), style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(144))
            Circle().trim(from: 0, to: CGFloat(min(1, max(0, hud.rpm))) * 0.72)
                .stroke(AngularGradient(colors: [.white, .orange, .red], center: .center, startAngle: .degrees(0), endAngle: .degrees(260)), style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(144))
            VStack(spacing: -2) {
                Text("\(Int(v.rounded()))").font(.system(size: 34, weight: .heavy, design: .rounded)).monospacedDigit()
                Text(mph ? "MPH" : "KM/H").font(.system(size: 9, weight: .bold)).tracking(2).foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    Text(hud.gear).font(.system(size: 17, weight: .black, design: .rounded)).foregroundStyle(hud.rpm > 0.93 ? .red : .white)
                    if hud.boost > 0.5 { Image(systemName: "tornado").font(.system(size: 11, weight: .bold)).foregroundStyle(.cyan) }
                    if hud.tc || hud.esc { Image(systemName: "car.side.rear.and.collision.and.car.side.front").font(.system(size: 10)).foregroundStyle(.yellow) }
                }
            }
        }
        .frame(width: 120, height: 120)
        .padding(6)
        .glass(Circle())
    }
}

struct MiniMap: View {
    let hud: HUDState
    var body: some View {
        GeometryReader { geo in
            let s: CGFloat = 0.21
            let W: CGFloat = 6400 * s, H: CGFloat = 4400 * s
            let px = CGFloat(hud.x + 3200) * s, pz = CGFloat(hud.z + 2200) * s
            ZStack {
                if let mapImage {
                    Image(uiImage: mapImage).resizable().interpolation(.medium)
                        .frame(width: W, height: H)
                        .offset(x: W / 2 - px, y: H / 2 - pz)
                        .rotationEffect(.radians(Double.pi + Double(hud.heading)))
                }
                Image(systemName: "location.north.fill").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 2)
                Text("N").font(.system(size: 10, weight: .heavy)).foregroundStyle(.red)
                    .offset(y: -geo.size.height / 2 + 9)
                    .rotationEffect(.radians(Double.pi + Double(hud.heading)))
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipShape(Circle())
            .overlay(Circle().stroke(.white.opacity(0.5), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.3), radius: 8)
        }
    }
}

// MARK: - Pause

struct PauseView: View {
    @EnvironmentObject var game: Game
    @EnvironmentObject var settings: GameSettings
    @Binding var showSettings: Bool
    var body: some View {
        let h = game.hud
        let k: Float = settings.mph ? 2.23694 : 3.6
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Paused").font(.system(size: 34, weight: .black, design: .rounded))
                    Text("\(h.place) · \(h.region.rawValue) · \(h.clock)").foregroundStyle(.secondary)
                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                        GridRow { Text("Top speed").foregroundStyle(.secondary); Text("\(Int(h.topSpeed * k)) \(settings.mph ? "mph" : "km/h")").monospacedDigit() }
                        GridRow { Text("Distance").foregroundStyle(.secondary); Text(String(format: "%.1f %@", h.odometer / (settings.mph ? 1609 : 1000), settings.mph ? "mi" : "km")).monospacedDigit() }
                        GridRow { Text("Best drift").foregroundStyle(.secondary); Text("\(h.bestDrift)").monospacedDigit() }
                    }
                    .font(.subheadline)
                }
                .frame(width: 260, alignment: .leading)
                VStack(spacing: 10) {
                    Button { game.resume() } label: { Label("Resume", systemImage: "play.fill").frame(maxWidth: .infinity) }.glassButton(prominent: true).tint(.red)
                    Button { game.openMap() } label: { Label("Map & fast travel", systemImage: "map").frame(maxWidth: .infinity) }.glassButton()
                    Button { game.resetCar(); game.resume() } label: { Label("Reset car", systemImage: "arrow.counterclockwise").frame(maxWidth: .infinity) }.glassButton()
                    Button { showSettings = true } label: { Label("Settings", systemImage: "gearshape").frame(maxWidth: .infinity) }.glassButton()
                    Button { game.quitToMenu() } label: { Label("Main menu", systemImage: "house").frame(maxWidth: .infinity) }.glassButton()
                }
                .frame(width: 240)
                .controlSize(.large)
            }
            .padding(26)
            .glass(RoundedRectangle(cornerRadius: 32, style: .continuous))
        }
    }
}

// MARK: - World map

struct WorldMapView: View {
    @EnvironmentObject var game: Game
    @State private var zoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @GestureState private var dragNow: CGSize = .zero
    @GestureState private var pinch: CGFloat = 1

    var body: some View {
        let h = game.hud
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()
            GeometryReader { geo in
                let aspect: CGFloat = 6400 / 4400
                let baseW = min(geo.size.width, geo.size.height * aspect)
                let z = min(5, max(1, zoom * pinch))
                let w = baseW * z, hgt = w / aspect
                let off = CGSize(width: pan.width + dragNow.width, height: pan.height + dragNow.height)
                ZStack(alignment: .topLeading) {
                    if let mapImage { Image(uiImage: mapImage).resizable().frame(width: w, height: hgt) }
                    ForEach(Array((game.world?.meta.cities ?? []).enumerated()), id: \.offset) { _, c in
                        let reg = WorldRegion.at(x: c.cx, z: c.cz)
                        Button { game.teleport(x: c.cx + 4.5, z: c.cz); game.resume() } label: {
                            Label(c.name, systemImage: reg.symbol).font(.caption.weight(.bold))
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .glass(Capsule(), tint: Color(reg.tint).opacity(0.35), interactive: true)
                        }
                        .buttonStyle(.plain)
                        .position(x: CGFloat(c.cx + 3200) / 6400 * w, y: CGFloat(c.cz - c.d / 2 + 2200) / 4400 * hgt - 16)
                    }
                    ForEach(Array((game.world?.meta.regions ?? []).enumerated()), id: \.offset) { _, r in
                        Text(r.name.uppercased()).font(.system(size: 12 + 4 * z, weight: .black)).tracking(4).foregroundStyle(.white.opacity(0.35))
                            .position(x: CGFloat(r.x + 3200) / 6400 * w, y: CGFloat(r.z + 2200) / 4400 * hgt + (r.name == "Texas" || r.name == "Arizona" || r.name == "California" ? 120 * z : 0))
                            .allowsHitTesting(false)
                    }
                    Image(systemName: "location.north.circle.fill").font(.system(size: 26)).foregroundStyle(.white, .red)
                        .rotationEffect(.radians(Double.pi - Double(h.heading)))
                        .position(x: CGFloat(h.x + 3200) / 6400 * w, y: CGFloat(h.z + 2200) / 4400 * hgt)
                        .allowsHitTesting(false)
                }
                .frame(width: w, height: hgt)
                .contentShape(Rectangle())
                .onTapGesture(count: 2, coordinateSpace: .local) { p in
                    let x = Float(p.x / w * 6400 - 3200), zz = Float(p.y / hgt * 4400 - 2200)
                    game.teleport(x: x, z: zz); game.resume()
                }
                .offset(off)
                .frame(width: geo.size.width, height: geo.size.height)
                .gesture(DragGesture().updating($dragNow) { v, s, _ in s = v.translation }.onEnded { v in pan.width += v.translation.width; pan.height += v.translation.height })
                .simultaneousGesture(MagnificationGesture().updating($pinch) { v, s, _ in s = v }.onEnded { v in zoom = min(5, max(1, zoom * v)); if zoom == 1 { pan = .zero } })
            }
            .clipped()
            VStack {
                HStack {
                    Text("Tap a city to fast travel · double-tap anywhere to go there").font(.footnote.weight(.semibold))
                        .padding(.horizontal, 14).padding(.vertical, 8).glass(Capsule())
                    Spacer()
                    RoundIcon(symbol: "xmark") { game.resume() }
                }
                Spacer()
            }
            .padding(14)
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject var game: Game
    @EnvironmentObject var s: GameSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Driving") {
                    Picker("Assists", selection: $s.assist) { ForEach(Assist.allCases) { Text($0.label).tag($0) } }.pickerStyle(.segmented)
                    Picker("Steering", selection: $s.steering) { ForEach(SteeringMode.allCases) { Text($0.label).tag($0) } }
                    if s.steering == .tilt {
                        LabeledContent("Tilt sensitivity") { Slider(value: $s.tiltSensitivity, in: 0.4...2) }
                        Toggle("Invert tilt", isOn: $s.invertTilt)
                    }
                    Toggle("Automatic gearbox", isOn: $s.autoGearbox)
                    Toggle("Miles per hour", isOn: $s.mph)
                }
                Section("Camera") {
                    Picker("View", selection: $s.camera) { ForEach(CameraMode.allCases, id: \.self) { Text($0.label).tag($0) } }
                    LabeledContent("Field of view \(Int(s.fov))°") { Slider(value: $s.fov, in: 45...90) }
                    LabeledContent("Distance") { Slider(value: $s.camDistance, in: 4.5...10) }
                    Toggle("Widen with speed", isOn: $s.speedFov)
                    Toggle("Crash shake", isOn: $s.cameraShake)
                }
                Section("Graphics") {
                    Picker("Preset", selection: Binding(get: { s.quality }, set: { s.applyQuality($0); game.applyGraphics() })) { ForEach(Quality.allCases) { Text($0.label).tag($0) } }.pickerStyle(.segmented)
                    LabeledContent("Draw distance \(Int(s.drawDistance)) m") { Slider(value: $s.drawDistance, in: 700...2600, step: 100) }
                    LabeledContent("Vegetation \(Int(s.vegetationDistance)) m") { Slider(value: $s.vegetationDistance, in: 200...1200, step: 50) }
                    Toggle("Shadows", isOn: $s.shadows)
                    Toggle("Bloom & glow", isOn: $s.bloom)
                    Toggle("Motion blur", isOn: $s.motionBlur)
                    Picker("Frame rate", selection: $s.fps) { Text("30").tag(30); Text("60").tag(60); Text("120").tag(120) }.pickerStyle(.segmented)
                    Toggle("Show performance stats", isOn: $s.showFPS)
                }
                Section("World") {
                    LabeledContent("Traffic \(Int(s.traffic)) cars") { Slider(value: $s.traffic, in: 0...40, step: 1) }
                    Picker("Crash physics", selection: $s.crash) { ForEach(CrashMode.allCases) { Text($0.label).tag($0) } }.pickerStyle(.segmented)
                    Toggle("Flying debris", isOn: $s.debris)
                    Picker("Time of day", selection: $s.timeMode) { Text("Day/night cycle").tag(TimeMode.cycle); Text("Fixed").tag(TimeMode.fixed) }
                    if s.timeMode == .fixed {
                        LabeledContent(String(format: "Hour %02d:%02d", Int(s.hour), Int((s.hour - Double(Int(s.hour))) * 60))) {
                            Slider(value: $s.hour, in: 0...23.9)
                        }
                    } else {
                        LabeledContent("Day length \(Int(s.dayLength)) min") { Slider(value: $s.dayLength, in: 4...120, step: 1) }
                        Button("Jump to night") { game.setHour(21.5) }
                        Button("Jump to sunrise") { game.setHour(6.2) }
                        Button("Jump to noon") { game.setHour(12.5) }
                    }
                }
                Section("Sound & feel") {
                    LabeledContent("Volume") { Slider(value: $s.volume, in: 0...1) }
                    Toggle("Haptics", isOn: $s.haptics)
                    Toggle("Minimap", isOn: $s.minimap)
                }
                Section("Car") {
                    Picker("Paint", selection: $s.paint) { ForEach(PAINTS) { p in Text(p.name).tag(p.id) } }
                    Picker("Wheels", selection: $s.rims) { ForEach(RIMS) { r in Text(r.name).tag(r.id) } }
                }
                Section {
                    Text("Ferrari F40 model: “LB-Works F40” by vecarz. World, textures, physics and sound are generated for this game.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
