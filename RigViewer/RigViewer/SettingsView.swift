import SwiftUI

/// Coloured rounded-square icon, like the system Settings app.
struct SettingIcon: View {
    let symbol: String, color: Color
    var body: some View {
        Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
            .frame(width: 29, height: 29).background(color.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

struct SettingLabel: View {
    let title: String, symbol: String, color: Color
    var body: some View { Label { Text(title) } icon: { SettingIcon(symbol: symbol, color: color) } }
}

struct SliderRow: View {
    let title: String, symbol: String, color: Color
    @Binding var value: Double
    let range: ClosedRange<Double>
    var low: String, high: String
    var format: (Double) -> String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SettingLabel(title: title, symbol: symbol, color: color)
                Spacer()
                Text(format(value)).foregroundStyle(.secondary).monospacedDigit()
            }
            HStack(spacing: 10) {
                Text(low).font(.caption2).foregroundStyle(.secondary)
                Slider(value: $value, in: range)
                Text(high).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var model: ViewerModel
    @AppStorage("accentIndex") private var accentIndex = 0
    @Environment(\.dismiss) private var dismiss
    @State private var confirmReset = false
    @State private var confirmClear = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(selection: $settings.fps) {
                        Text("30 fps").tag(30); Text("60 fps").tag(60); Text("120 fps (ProMotion)").tag(120)
                    } label: { SettingLabel(title: "Frame Rate", symbol: "speedometer", color: .red) }
                    Picker(selection: $settings.antialiasing) {
                        Text("Off").tag(0); Text("2×").tag(2); Text("4×").tag(4)
                    } label: { SettingLabel(title: "Anti-aliasing", symbol: "square.grid.3x3.middle.filled", color: .orange) }
                    Picker(selection: $settings.shadowQuality) {
                        Text("Off").tag(0); Text("Low").tag(1); Text("High").tag(2)
                    } label: { SettingLabel(title: "Shadows", symbol: "shadow", color: .gray) }
                    Toggle(isOn: $settings.hdr) { SettingLabel(title: "HDR Rendering", symbol: "sun.max.fill", color: .yellow) }
                    Toggle(isOn: $settings.bloom) { SettingLabel(title: "Glow (Bloom)", symbol: "sparkles", color: .pink) }
                    Toggle(isOn: $settings.batterySaver) { SettingLabel(title: "Battery Saver", symbol: "battery.75percent", color: .green) }
                    Toggle(isOn: $settings.showStats) { SettingLabel(title: "Show FPS & Stats", symbol: "chart.bar.xaxis", color: .indigo) }
                } header: { Text("Performance") } footer: {
                    Text("Battery Saver only redraws when something moves and caps the frame rate at 60. Lower anti-aliasing and shadows if large models feel slow.")
                }

                Section {
                    SliderRow(title: "Rotation Speed", symbol: "rotate.3d", color: .blue, value: $settings.orbitSpeed, range: 0.3...2.5,
                              low: "Slow", high: "Fast", format: { String(format: "%.1f×", $0) })
                    SliderRow(title: "Smoothness", symbol: "water.waves", color: .teal, value: $settings.smoothness, range: 0...1,
                              low: "Direct", high: "Silky", format: { "\(Int($0 * 100))%" })
                    SliderRow(title: "Zoom Speed", symbol: "plus.magnifyingglass", color: .cyan, value: $settings.zoomSpeed, range: 0.4...2.5,
                              low: "Gentle", high: "Fast", format: { String(format: "%.1f×", $0) })
                    Toggle(isOn: $settings.momentum) { SettingLabel(title: "Momentum", symbol: "wind", color: .mint) }
                    if settings.momentum {
                        SliderRow(title: "Glide Length", symbol: "arrow.right.to.line", color: .mint, value: Binding(get: { 1 - settings.momentumFriction }, set: { settings.momentumFriction = 1 - $0 }),
                                  range: 0...1, low: "Short", high: "Long", format: { "\(Int($0 * 100))%" })
                    }
                } header: { Text("Touch Controls") } footer: {
                    Text("Smoothness eases the camera between your finger movements. Lower it for a direct feel, raise it for a cinematic glide.")
                }

                Section {
                    Toggle(isOn: $settings.zoomToFingers) { SettingLabel(title: "Zoom Toward Fingers", symbol: "hand.pinch.fill", color: .blue) }
                    Toggle(isOn: $settings.twoFingerPan) { SettingLabel(title: "Two-Finger Pan", symbol: "hand.draw.fill", color: .purple) }
                    Toggle(isOn: $settings.twistToRotate) { SettingLabel(title: "Twist to Rotate", symbol: "arrow.triangle.2.circlepath", color: .orange) }
                    Toggle(isOn: $settings.invertX) { SettingLabel(title: "Invert Horizontal", symbol: "arrow.left.and.right", color: .gray) }
                    Toggle(isOn: $settings.invertY) { SettingLabel(title: "Invert Vertical", symbol: "arrow.up.and.down", color: .gray) }
                    Toggle(isOn: $settings.allowBelow) { SettingLabel(title: "Look From Below", symbol: "arrow.down.to.line", color: .brown) }
                    Toggle(isOn: $settings.doubleTapReset) { SettingLabel(title: "Double-Tap to Reset View", symbol: "hand.tap.fill", color: .pink) }
                    SliderRow(title: "Turntable Speed", symbol: "arrow.clockwise.circle", color: .green, value: $settings.turntableSpeed, range: 0.2...3,
                              low: "Slow", high: "Fast", format: { String(format: "%.1f×", $0) })
                } header: { Text("Gestures") }

                Section {
                    SliderRow(title: "Field of View", symbol: "camera.viewfinder", color: .indigo, value: $settings.defaultFOV, range: 15...90,
                              low: "Tele", high: "Wide", format: { "\(Int($0))°" })
                    Picker(selection: $settings.defaultEnvironment) {
                        ForEach(EnvPreset.all) { Text($0.name).tag($0.id) }
                    } label: { SettingLabel(title: "Lighting", symbol: "lightbulb.fill", color: .yellow) }
                    Toggle(isOn: $settings.defaultSkeleton) { SettingLabel(title: "Show Skeleton", symbol: "figure.stand", color: .blue) }
                    Toggle(isOn: $settings.defaultGroundShadow) { SettingLabel(title: "Ground Shadow", symbol: "square.bottomhalf.filled", color: .gray) }
                    Picker(selection: $settings.units) {
                        Text("Metres").tag("m"); Text("Centimetres").tag("cm"); Text("Inches").tag("in"); Text("Feet").tag("ft")
                    } label: { SettingLabel(title: "Units", symbol: "ruler.fill", color: .orange) }
                } header: { Text("Viewer") } footer: { Text("Applied to the current model and every model you open.") }

                Section {
                    Toggle(isOn: $settings.autoplay) { SettingLabel(title: "Play on Open", symbol: "play.fill", color: .green) }
                    Toggle(isOn: $settings.loopAnimations) { SettingLabel(title: "Loop Animations", symbol: "repeat", color: .teal) }
                    Picker(selection: $settings.defaultSpeed) {
                        ForEach([0.25, 0.5, 1.0, 1.5, 2.0], id: \.self) { Text("\(Fmt.speed($0))×").tag($0) }
                    } label: { SettingLabel(title: "Default Speed", symbol: "gauge.with.dots.needle.50percent", color: .red) }
                } header: { Text("Animation") }

                Section {
                    Picker(selection: $settings.appearance) {
                        Text("System").tag(0); Text("Light").tag(1); Text("Dark").tag(2)
                    } label: { SettingLabel(title: "Appearance", symbol: "circle.lefthalf.filled", color: .black) }
                    Picker(selection: $settings.backgroundStyle) {
                        Text("Colour Gradient").tag(0); Text("Plain").tag(1); Text("Black").tag(2); Text("White").tag(3)
                    } label: { SettingLabel(title: "Background", symbol: "photo.fill", color: .purple) }
                    VStack(alignment: .leading, spacing: 10) {
                        SettingLabel(title: "Accent Colour", symbol: "paintpalette.fill", color: Accent.all[min(accentIndex, Accent.all.count - 1)].color)
                        HStack(spacing: 0) {
                            ForEach(Array(Accent.all.enumerated()), id: \.offset) { i, a in
                                Button { accentIndex = i; Haptics.select() } label: {
                                    Circle().fill(a.color.gradient).frame(width: 26, height: 26)
                                        .overlay(Circle().stroke(Color.primary.opacity(accentIndex == i ? 0.9 : 0), lineWidth: 2).padding(-4))
                                        .frame(maxWidth: .infinity, minHeight: 36)
                                }
                                .buttonStyle(.plain).accessibilityLabel(a.name)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    Toggle(isOn: $settings.solidPanels) { SettingLabel(title: "Solid Panels (No Glass)", symbol: "rectangle.fill", color: .gray) }
                } header: { Text("Appearance") }

                Section {
                    Toggle(isOn: $settings.haptics) { SettingLabel(title: "Haptics", symbol: "iphone.radiowaves.left.and.right", color: .pink) }
                    Toggle(isOn: $settings.showHints) { SettingLabel(title: "Show Tips", symbol: "lightbulb.max.fill", color: .yellow) }
                    Toggle(isOn: $settings.libraryOnLaunch) { SettingLabel(title: "Open Library at Launch", symbol: "square.grid.2x2.fill", color: .blue) }
                    Toggle(isOn: $settings.startExpanded) { SettingLabel(title: "Start With Inspector Open", symbol: "rectangle.bottomhalf.inset.filled", color: .indigo) }
                } header: { Text("Interface") }

                Section {
                    Picker(selection: $settings.maxRecents) {
                        Text("10").tag(10); Text("25").tag(25); Text("50").tag(50); Text("100").tag(100)
                    } label: { SettingLabel(title: "Recent Files Kept", symbol: "clock.fill", color: .blue) }
                    LabeledContent { Text(Fmt.bytes(Double(ViewerModel.folderSize(ViewerModel.recentsDir)))).monospacedDigit() } label: {
                        SettingLabel(title: "Storage Used", symbol: "internaldrive.fill", color: .gray)
                    }
                    Button(role: .destructive) { confirmClear = true } label: { SettingLabel(title: "Clear Recent Files", symbol: "trash.fill", color: .red) }
                        .disabled(model.recents.isEmpty)
                    Toggle(isOn: $settings.arFitSize) { SettingLabel(title: "Fit Huge or Tiny Models in AR", symbol: "arkit", color: .teal) }
                } header: { Text("Files & AR") } footer: {
                    Text("When fitting is off, AR shows models at the size stored in the file, which can be very large for STL files measured in millimetres.")
                }

                Section {
                    Button(role: .destructive) { confirmReset = true } label: {
                        Text("Reset All Settings").frame(maxWidth: .infinity)
                    }
                } footer: {
                    Text("Rig Viewer \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")").frame(maxWidth: .infinity).padding(.top, 8)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.fontWeight(.semibold) } }
            .confirmationDialog("Reset every setting to its default?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Reset All Settings", role: .destructive) { settings.resetAll(); accentIndex = 0; Haptics.tap(.medium) }
            }
            .confirmationDialog("Remove all recent files from this iPhone?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Clear Recent Files", role: .destructive) { model.clearRecents() }
            }
        }
        .tint(Accent.all[min(accentIndex, Accent.all.count - 1)].color)
        .preferredColorScheme(settings.colorScheme)
    }
}
