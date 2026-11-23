import SwiftUI
import SceneKit

struct InspectorContent: View {
    @ObservedObject var model: ViewerModel
    let tab: InspectorTab
    @Binding var accentIndex: Int
    var onFullScreen: () -> Void
    var onSnapshot: () -> Void
    var onAR: () -> Void

    var body: some View {
        switch tab {
        case .info: InfoTab(model: model)
        case .scene: MaterialsTab(model: model)
        case .clips: ClipsTab(model: model)
        case .bones: BonesTab(model: model)
        case .look: LookTab(model: model)
        case .view: ViewTab(model: model, accentIndex: $accentIndex, onFullScreen: onFullScreen, onSnapshot: onSnapshot, onAR: onAR)
        }
    }
}

// MARK: Info
struct InfoTab: View {
    @ObservedObject var model: ViewerModel
    var body: some View {
        let s = model.stats
        VStack(spacing: 18) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                StatTile(icon: "triangle", value: Fmt.count(s.triangles), label: "Triangles")
                StatTile(icon: "circle.grid.3x3", value: Fmt.count(s.vertices), label: "Vertices")
                StatTile(icon: "figure.stand", value: "\(s.bones)", label: "Bones")
                StatTile(icon: "film.stack", value: "\(model.clips.count)", label: "Animations")
            }
            Section2(title: "File") {
                Row("Name", value: s.name)
                Row("Format", value: s.format)
                Row("Size", value: s.fileBytes > 0 ? Fmt.bytes(Double(s.fileBytes)) : "Built in", showDivider: false)
            }
            Section2(title: "Geometry") {
                Row("Meshes", value: "\(s.meshes)")
                Row("Materials", value: "\(s.materials)")
                Row("Textures", value: s.textures > 0 ? "\(s.textures) · \(Fmt.bytes(s.textureBytes)) in memory" : "None")
                Row("Blend shapes", value: "\(s.morphs)")
                Row("Dimensions", value: "\(Fmt.len(s.size.x)) × \(Fmt.len(s.size.y)) × \(Fmt.len(s.size.z))", showDivider: false)
            }
        }
    }
}

struct StatTile: View {
    let icon: String, value: String, label: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon).font(.subheadline.weight(.semibold)).foregroundStyle(.tint)
            Text(value).font(.system(size: 24, weight: .bold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(14)
        .background(Color(uiColor: .secondarySystemBackground).opacity(0.62), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

// MARK: Materials
struct MaterialsTab: View {
    @ObservedObject var model: ViewerModel
    var body: some View {
        VStack(spacing: 18) {
            if model.materials.isEmpty {
                Empty(icon: "paintpalette", title: "No materials", text: "This model has no materials to show.")
            } else {
                Section2(title: "Materials", footer: "Textures are shown at their full resolution.") {
                    ForEach(Array(model.materials.enumerated()), id: \.element.id) { i, m in
                        VStack(spacing: 0) {
                            HStack(spacing: 12) {
                                Group {
                                    if let t = m.thumbnail { Image(uiImage: t).resizable().scaledToFill() }
                                    else { Color(uiColor: m.color) }
                                }
                                .frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(.white.opacity(0.25), lineWidth: 0.5))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(m.name).font(.body.weight(.medium)).lineLimit(1)
                                    Text(m.textures.isEmpty ? m.model : m.textures.map { "\($0.slot) \($0.width)²" }.joined(separator: " · "))
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            if i < model.materials.count - 1 { Divider().padding(.leading, 70) }
                        }
                    }
                }
            }
        }
    }
}

// MARK: Clips
struct ClipsTab: View {
    @ObservedObject var model: ViewerModel
    @State private var morphValues: [Int: Double] = [:]
    var body: some View {
        VStack(spacing: 18) {
            if model.clips.isEmpty {
                Empty(icon: "film", title: "No animations", text: "This file doesn’t contain any animation clips.")
            } else {
                Section2(title: "Animations") {
                    ForEach(Array(model.clips.enumerated()), id: \.element.id) { i, c in
                        Button { model.play(i) } label: {
                            Row(label: c.name, showDivider: i < model.clips.count - 1) {
                                Text(String(format: "%.1f s", c.duration)).foregroundStyle(.secondary).monospacedDigit()
                                Image(systemName: i == model.currentClip ? (model.isPlaying ? "speaker.wave.2.fill" : "pause.fill") : "play.fill")
                                    .foregroundStyle(i == model.currentClip ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary)).frame(width: 22)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                Section2(title: "Playback") {
                    Row(label: "Speed", showDivider: false) {
                        Slider(value: $model.speed, in: 0.1...2.5).frame(maxWidth: 170)
                        Text("\(String(format: "%.2f", model.speed))×").monospacedDigit().foregroundStyle(.secondary).frame(width: 48, alignment: .trailing)
                    }
                }
            }
            if !model.morphs.isEmpty {
                Section2(title: "Blend Shapes", footer: "Drag to preview facial expressions and shape keys.") {
                    ForEach(Array(model.morphs.enumerated()), id: \.offset) { i, m in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(m.2).font(.subheadline).lineLimit(1)
                            Slider(value: Binding(get: { morphValues[i] ?? Double(m.0.weight(forTargetAt: m.1)) },
                                                  set: { morphValues[i] = $0; model.setMorph(i, value: $0) }), in: 0...1)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        if i < model.morphs.count - 1 { Divider().padding(.leading, 16) }
                    }
                }
            }
        }
        .onChange(of: model.stats.name) { _, _ in morphValues = [:] }
    }
}

// MARK: Bones
struct BonesTab: View {
    @ObservedObject var model: ViewerModel
    @State private var query = ""
    @State private var tick = 0
    private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var filtered: [BoneInfo] { query.isEmpty ? model.bones : model.bones.filter { $0.name.localizedCaseInsensitiveContains(query) } }

    var body: some View {
        VStack(spacing: 14) {
            if model.bones.isEmpty {
                Empty(icon: "figure.stand", title: "No skeleton", text: "This model isn’t rigged, so there are no bones to inspect.")
            } else {
                Toggle(isOn: $model.showSkeleton) { Label("Show skeleton", systemImage: "figure.stand") }
                    .padding(.horizontal, 16).frame(height: 48)
                    .background(Color(uiColor: .secondarySystemBackground).opacity(0.62), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search \(model.bones.count) bones", text: $query).textInputAutocapitalization(.never).autocorrectionDisabled()
                    if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain) }
                }
                .padding(.horizontal, 14).frame(height: 44)
                .background(Color(uiColor: .secondarySystemBackground).opacity(0.62), in: Capsule())

                if let b = model.selectedBone {
                    let p = model.worldPosition(of: b)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(b.name).font(.headline).lineLimit(1)
                            Spacer()
                            Button { model.selectedBone = nil } label: { Image(systemName: "xmark").font(.caption.weight(.bold)).frame(width: 28, height: 28) }
                                .buttonStyle(.plain).glass(Circle(), interactive: true)
                        }
                        HStack(spacing: 8) {
                            Axis(label: "X", value: p.x, color: .red); Axis(label: "Y", value: p.y, color: .green); Axis(label: "Z", value: p.z, color: .blue)
                        }
                        Text("Parent: \(b.node.parent?.name.map { $0.hasPrefix("joint:") ? String($0.dropFirst(6)) : $0 } ?? "—") · \(b.node.childNodes.count) children")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .id(tick)
                }

                LazyVStack(spacing: 0) {
                    ForEach(filtered.prefix(400)) { b in
                        Button { model.selectedBone = (model.selectedBone == b ? nil : b) } label: {
                            HStack(spacing: 8) {
                                if query.isEmpty { Color.clear.frame(width: CGFloat(min(b.depth, 12)) * 10, height: 1) }
                                Image(systemName: "circle.fill").font(.system(size: 6)).foregroundStyle(model.selectedBone == b ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                                Text(b.name).font(.subheadline).lineLimit(1)
                                Spacer()
                                if model.selectedBone == b { Image(systemName: "scope").foregroundStyle(.tint) }
                            }
                            .padding(.horizontal, 14).frame(height: 38).contentShape(Rectangle())
                            .background(model.selectedBone == b ? Color.accentColor.opacity(0.12) : .clear)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(Color(uiColor: .secondarySystemBackground).opacity(0.62), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
        }
        .onReceive(timer) { _ in if model.selectedBone != nil { tick &+= 1 } }
    }
}

struct Axis: View {
    let label: String; let value: Float; let color: Color
    var body: some View {
        HStack(spacing: 4) {
            Text(label).font(.caption.weight(.bold)).foregroundStyle(color)
            Text(String(format: "%.3f", value)).font(.caption).monospacedDigit()
        }
        .padding(.horizontal, 10).frame(height: 28).frame(maxWidth: .infinity)
        .background(Color(uiColor: .tertiarySystemBackground).opacity(0.7), in: Capsule())
    }
}

// MARK: Look
struct LookTab: View {
    @ObservedObject var model: ViewerModel
    var body: some View {
        VStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Shading").font(.headline).padding(.horizontal, 6)
                Picker("Shading", selection: $model.shading) { ForEach(Shading.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Environment").font(.headline).padding(.horizontal, 6)
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(EnvPreset.all) { e in
                            Button { model.env = e.id } label: {
                                VStack(spacing: 6) {
                                    EnvThumb(id: e.id).frame(width: 92, height: 62)
                                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(model.env == e.id ? Color.accentColor : .white.opacity(0.2), lineWidth: model.env == e.id ? 3 : 0.5))
                                    Text(e.name).font(.caption).foregroundStyle(model.env == e.id ? .primary : .secondary).lineLimit(1)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 2).padding(.vertical, 3)
                }
                .scrollIndicators(.hidden)
            }
            Section2(footer: "Lighting comes from real HDR photographs of each place.") {
                Row(label: "Show as background") { Toggle("", isOn: $model.envBackground).labelsHidden() }
                Row(label: "Ground shadow") { Toggle("", isOn: $model.groundShadow).labelsHidden() }
                Row(label: "Exposure", showDivider: false) {
                    Slider(value: $model.exposure, in: -2...2).frame(maxWidth: 160)
                    Text(String(format: "%+.1f", model.exposure)).monospacedDigit().foregroundStyle(.secondary).frame(width: 40, alignment: .trailing)
                }
            }
        }
    }
}

struct EnvThumb: View {
    let id: String
    var body: some View {
        if id == "studio" {
            LinearGradient(colors: [Color(white: 0.95), Color(white: 0.7), Color(white: 0.45)], startPoint: .top, endPoint: .bottom)
                .overlay(Image(systemName: "light.max").font(.title3).foregroundStyle(.white.opacity(0.9)))
        } else if let u = Bundle.main.url(forResource: "\(id)_thumb", withExtension: "jpg"), let img = UIImage(contentsOfFile: u.path) {
            Image(uiImage: img).resizable().scaledToFill()
        } else {
            Color.gray
        }
    }
}

// MARK: View
struct ViewTab: View {
    @ObservedObject var model: ViewerModel
    @Binding var accentIndex: Int
    var onFullScreen: () -> Void
    var onSnapshot: () -> Void
    var onAR: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            GlassGroup(spacing: 8) {
                HStack(spacing: 8) {
                    ActionButton(icon: "arkit", title: "AR", action: onAR)
                    ActionButton(icon: "camera.aperture", title: "Snapshot", action: onSnapshot)
                    ActionButton(icon: "arrow.up.left.and.arrow.down.right", title: "Full Screen", action: onFullScreen)
                    ActionButton(icon: "scope", title: "Recenter") { model.frame() }
                }
            }
            Section2(title: "Display") {
                Row(label: "Skeleton") { Toggle("", isOn: $model.showSkeleton).labelsHidden() }
                Row(label: "Wireframe") { Toggle("", isOn: $model.wireframe).labelsHidden() }
                Row(label: "Bounding boxes") { Toggle("", isOn: $model.boundingBoxes).labelsHidden() }
                Row(label: "Turntable") { Toggle("", isOn: $model.turntable).labelsHidden() }
                Row(label: "Z-up model", showDivider: false) { Toggle("", isOn: $model.zUp).labelsHidden() }
            }
            Section2(title: "Camera") {
                Row(label: "Field of view", showDivider: false) {
                    Slider(value: $model.fov, in: 15...90).frame(maxWidth: 160)
                    Text("\(Int(model.fov))°").monospacedDigit().foregroundStyle(.secondary).frame(width: 40, alignment: .trailing)
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("Accent").font(.headline).padding(.horizontal, 6)
                HStack(spacing: 0) {
                    ForEach(Array(Accent.all.enumerated()), id: \.offset) { i, a in
                        Button { withAnimation(.snappy) { accentIndex = i } } label: {
                            Circle().fill(a.color.gradient).frame(width: 28, height: 28)
                                .overlay(Circle().stroke(.white, lineWidth: accentIndex == i ? 3 : 0).padding(-1))
                                .overlay(Circle().stroke(a.color, lineWidth: accentIndex == i ? 2 : 0).padding(-5))
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.plain).accessibilityLabel(a.name)
                    }
                }
                .padding(.vertical, 4)
                .background(Color(uiColor: .secondarySystemBackground).opacity(0.62), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
        }
    }
}

struct ActionButton: View {
    let icon: String, title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 20, weight: .semibold)).frame(height: 24)
                Text(title).font(.caption2.weight(.medium)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity).frame(height: 70).contentShape(RoundedRectangle(cornerRadius: 22))
        }
        .buttonStyle(.plain).glass(RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: true)
    }
}

struct Empty: View {
    let icon: String, title: String, text: String
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 34, weight: .light)).foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(text).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 30)
    }
}
