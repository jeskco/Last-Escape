import SwiftUI
import PhotosUI
import SceneKit

enum PropertiesTab: String, CaseIterable, Identifiable {
    case object = "Object", modifiers = "Modifiers", material = "Material", world = "World"
    var id: String { rawValue }
    var icon: String { switch self { case .object: return "cube"; case .modifiers: return "wrench.and.screwdriver"; case .material: return "paintpalette"; case .world: return "globe" } }
}

// MARK: - Properties editor (Blender's Properties panel)

struct StudioPropertiesView: View {
    @ObservedObject var model: StudioModel
    @Binding var tab: PropertiesTab
    @Environment(\.dismiss) private var dismiss
    @State private var photo: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Tab", selection: $tab) {
                    ForEach(PropertiesTab.allCases) { Label($0.rawValue, systemImage: $0.icon).tag($0) }
                }
                .pickerStyle(.segmented).padding(.horizontal, 16).padding(.vertical, 8)
                Group {
                    switch tab {
                    case .object: objectTab
                    case .modifiers: modifiersTab
                    case .material: materialTab
                    case .world: WorldForm(model: model)
                    }
                }
            }
            .navigationTitle(model.primary?.name ?? "Properties").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.fontWeight(.semibold) } }
        }
        .onChange(of: photo) { _, item in
            guard let item, let o = model.primary else { return }
            Task { @MainActor in
                if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                    model.pushUndo(); o.textureImage = img; model.applyMaterial(o)
                }
                photo = nil
            }
        }
    }

    private var nothing: some View {
        ContentUnavailableView("Nothing Selected", systemImage: "cube.transparent", description: Text("Tap an object to see its properties."))
    }

    // MARK: Object

    @ViewBuilder private var objectTab: some View {
        if let o = model.primary {
            Form {
                Section("Object") {
                    TextField("Name", text: Binding(get: { o.name }, set: { model.rename(o, $0) }))
                    if let m = o.mesh {
                        LabeledContent("Vertices", value: "\(m.vertexCount)")
                        LabeledContent("Faces", value: "\(m.faceCount)")
                        LabeledContent("Triangles", value: Fmt.count(m.triangleCount))
                        if !o.modifiers.isEmpty {
                            LabeledContent("With modifiers", value: Fmt.count(m.evaluated(o.modifiers).triangleCount) + " tris")
                        }
                        Toggle("Smooth Shading", isOn: Binding(get: { o.mesh?.smooth ?? false }, set: { v in model.selection = [o.id]; model.shadeSmooth(v) }))
                    } else if !o.isLight {
                        Text("Imported model. Use Make Editable to turn its static meshes into shapes, or Animate to pose its rig.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section("Transform") {
                    VectorRow(title: "Location", value: o.node.simdPosition, step: 0.1) { model.pushUndo(); model.setTransform(position: $0) }
                    VectorRow(title: "Rotation°", value: o.node.simdEulerAngles * (180 / .pi), step: 15) { model.pushUndo(); model.setTransform(rotationDegrees: $0) }
                    VectorRow(title: "Scale", value: o.node.simdScale, step: 0.1) { model.pushUndo(); model.setTransform(scale: $0) }
                    if let m = o.mesh {
                        let size = (m.bounds.max - m.bounds.min)
                        VectorRow(title: "Dimensions", value: size * o.node.simdScale, step: 0.1) { d in
                            model.pushUndo()
                            model.setTransform(scale: SIMD3(size.x > 1e-6 ? d.x / size.x : 1, size.y > 1e-6 ? d.y / size.y : 1, size.z > 1e-6 ? d.z / size.z : 1))
                        }
                    }
                }
                if let l = o.light { lightSection(o, l) }
            }
        } else { nothing }
    }

    @ViewBuilder private func lightSection(_ o: StudioObject, _ l: LightRecord) -> some View {
        Section("Light") {
            Picker("Type", selection: Binding(get: { l.kind }, set: { k in model.updateLight(o) { $0.kind = k } })) {
                ForEach(LightKind.allCases) { Label($0.rawValue, systemImage: $0.icon).tag($0) }
            }
            ColorPicker("Colour", selection: Binding(get: { l.color }, set: { c in model.updateLight(o) { $0.color = c } }), supportsOpacity: false)
            VStack(alignment: .leading) {
                HStack { Text("Power"); Spacer(); Text("\(Int(l.intensity))").foregroundStyle(.secondary).monospacedDigit() }
                Slider(value: Binding(get: { Double(l.intensity) }, set: { v in model.updateLight(o) { $0.intensity = Float(v) } }), in: 0...5000)
            }
            if l.kind == .spot {
                VStack(alignment: .leading) {
                    HStack { Text("Spot Size"); Spacer(); Text("\(Int(l.angle))°").foregroundStyle(.secondary).monospacedDigit() }
                    Slider(value: Binding(get: { Double(l.angle) }, set: { v in model.updateLight(o) { $0.angle = Float(v) } }), in: 5...150)
                }
            }
            Toggle("Shadows", isOn: Binding(get: { l.shadows }, set: { v in model.updateLight(o) { $0.shadows = v } }))
                .disabled(l.kind == .point || l.kind == .area)
        }
    }

    // MARK: Modifiers

    @ViewBuilder private var modifiersTab: some View {
        if let o = model.primary, o.mesh != nil {
            Form {
                Section {
                    Menu {
                        Section("Generate") { ForEach(ModifierKind.allCases.filter { $0.group == "Generate" }) { k in Button(k.title, systemImage: k.icon) { model.addModifier(k) } } }
                        Section("Deform") { ForEach(ModifierKind.allCases.filter { $0.group == "Deform" }) { k in Button(k.title, systemImage: k.icon) { model.addModifier(k) } } }
                    } label: { Label("Add Modifier", systemImage: "plus.circle.fill").font(.headline) }
                    if o.modifiers.isEmpty {
                        Text("Modifiers change the shape without touching your mesh — mirror, subdivide, array, solidify and more. Apply one to make it permanent.")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else {
                        Button("Apply All", systemImage: "checkmark.rectangle.stack") { model.applyAllModifiers() }
                    }
                }
                ForEach(Array(o.modifiers.enumerated()), id: \.element.id) { i, r in
                    Section {
                        ModifierEditor(record: r) { change in model.updateModifier(o, r.id, change) }
                    } header: {
                        HStack(spacing: 8) {
                            Image(systemName: r.kind.icon)
                            Text(r.kind.title)
                            Spacer()
                            Toggle("", isOn: Binding(get: { r.enabled }, set: { v in model.updateModifier(o, r.id) { $0.enabled = v } })).labelsHidden().controlSize(.mini)
                            Menu {
                                Button("Apply", systemImage: "checkmark") { model.applyModifier(o, r.id) }
                                Button("Move Up", systemImage: "arrow.up") { model.moveModifier(o, r.id, up: true) }.disabled(i == 0)
                                Button("Move Down", systemImage: "arrow.down") { model.moveModifier(o, r.id, up: false) }.disabled(i == o.modifiers.count - 1)
                                Button("Remove", systemImage: "trash", role: .destructive) { model.removeModifier(o, r.id) }
                            } label: { Image(systemName: "ellipsis.circle").font(.body) }
                        }
                    }
                }
            }
        } else { nothing }
    }

    // MARK: Material

    @ViewBuilder private var materialTab: some View {
        if let o = model.primary, o.mesh != nil {
            Form {
                Section("Presets") {
                    ScrollView(.horizontal) {
                        HStack(spacing: 12) {
                            ForEach(MaterialRecord.presets, id: \.0) { name, rec in
                                Button { model.pushUndo(); o.material = rec; model.applyMaterial(o) } label: {
                                    VStack(spacing: 4) {
                                        Circle().fill(RadialGradient(colors: [Color(red: Double(min(1, rec.r + 0.25)), green: Double(min(1, rec.g + 0.25)), blue: Double(min(1, rec.b + 0.25))),
                                                                              Color(red: Double(rec.r * 0.55), green: Double(rec.g * 0.55), blue: Double(rec.b * 0.55))],
                                                                     center: .init(x: 0.35, y: 0.3), startRadius: 1, endRadius: 26))
                                            .opacity(Double(max(rec.opacity, 0.45)))
                                            .frame(width: 44, height: 44)
                                            .overlay(Circle().stroke(o.material == rec ? Color.accentColor : .clear, lineWidth: 2.5).padding(-3))
                                        Text(name).font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .scrollIndicators(.hidden)
                }
                Section("Surface") {
                    ColorPicker("Base Colour", selection: Binding(get: { o.material.color }, set: { o.material.color = $0; model.applyMaterial(o) }), supportsOpacity: false)
                    MaterialSlider(title: "Roughness", value: Binding(get: { o.material.roughness }, set: { o.material.roughness = $0; model.applyMaterial(o) }))
                    MaterialSlider(title: "Metallic", value: Binding(get: { o.material.metalness }, set: { o.material.metalness = $0; model.applyMaterial(o) }))
                    MaterialSlider(title: "Emission", value: Binding(get: { o.material.emission / 3 }, set: { o.material.emission = $0 * 3; model.applyMaterial(o) }))
                    MaterialSlider(title: "Alpha", value: Binding(get: { o.material.opacity }, set: { o.material.opacity = max(0.05, $0); model.applyMaterial(o) }))
                    Toggle("Double-Sided", isOn: Binding(get: { o.material.doubleSided }, set: { o.material.doubleSided = $0; model.applyMaterial(o) }))
                }
                Section {
                    ScrollView(.horizontal) {
                        HStack(spacing: 10) {
                            ForEach(ProceduralTexture.allCases) { k in
                                Button { model.setProcedural(k, on: o) } label: {
                                    VStack(spacing: 4) {
                                        Image(uiImage: ProceduralThumbs.shared.image(k)).resizable().frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 10))
                                        Text(k.rawValue).font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .scrollIndicators(.hidden)
                    PhotosPicker(selection: $photo, matching: .images) {
                        Label(o.textureImage == nil ? "Image Texture from Photos" : "Replace with a Photo", systemImage: "photo.on.rectangle")
                    }
                    if let img = o.textureImage {
                        HStack {
                            Image(uiImage: img).resizable().scaledToFill().frame(width: 52, height: 52).clipShape(RoundedRectangle(cornerRadius: 10))
                            Text("\(Int(img.size.width * img.scale))×\(Int(img.size.height * img.scale))").foregroundStyle(.secondary).monospacedDigit()
                            Spacer()
                            Button("Remove", role: .destructive) { model.pushUndo(); o.textureImage = nil; model.applyMaterial(o) }
                        }
                        VStack(alignment: .leading) {
                            HStack { Text("Tiling"); Spacer(); Text(String(format: "%.1f×", o.material.tiling ?? 1)).foregroundStyle(.secondary).monospacedDigit() }
                            Slider(value: Binding(get: { Double(o.material.tiling ?? 1) }, set: { o.material.tiling = Float($0); model.applyMaterial(o) }), in: 0.25...16)
                        }
                    }
                } header: { Text("Texture") } footer: {
                    Text("For tidy texture placement use Edit ▸ Normals & UV ▸ UV Cube/Cylinder/Sphere. Vertex paint (Paint mode) mixes with the colour and texture.")
                }
            }
        } else if model.primary?.isLight == true {
            ContentUnavailableView("Lights have no material", systemImage: "lightbulb", description: Text("Change its colour and power on the Object tab."))
        } else { nothing }
    }
}

/// Parameter editor for one modifier.
struct ModifierEditor: View {
    let record: ModifierRecord
    let update: ((inout ModifierRecord) -> Void) -> Void

    var body: some View {
        switch record.kind {
        case .mirror:
            axis
            toggle("Merge Seam", record.flag) { r, v in r.flag = v }
        case .subdivision:
            stepper("Levels", record.count, 0...4) { r, v in r.count = v }
        case .array:
            stepper("Count", record.count, 1...64) { r, v in r.count = v }
            slider("Offset X", record.offset.x, -3...3) { r, v in r.offset.x = v }
            slider("Offset Y", record.offset.y, -3...3) { r, v in r.offset.y = v }
            slider("Offset Z", record.offset.z, -3...3) { r, v in r.offset.z = v }
            toggle("Merge", record.flag) { r, v in r.flag = v }
        case .solidify:
            slider("Thickness", record.amount, 0.001...0.5) { r, v in r.amount = v }
            toggle("Fix Normals", record.flag) { r, v in r.flag = v }
        case .smooth:
            slider("Factor", record.amount, 0...1) { r, v in r.amount = v }
            stepper("Repeat", record.count, 1...50) { r, v in r.count = v }
        case .displace:
            slider("Strength", record.amount, 0...0.5) { r, v in r.amount = v }
            stepper("Noise Scale", record.count, 1...30) { r, v in r.count = v }
        case .decimate:
            slider("Ratio", record.amount, 0.02...1) { r, v in r.amount = v }
        case .triangulate:
            Text("Splits every face into triangles.").font(.footnote).foregroundStyle(.secondary)
        case .weld:
            slider("Distance", record.amount, 0...0.05) { r, v in r.amount = v }
        case .wireframe:
            slider("Thickness", record.amount, 0.001...0.1) { r, v in r.amount = v }
        case .screw:
            axis
            stepper("Steps", record.count, 3...128) { r, v in r.count = v }
            slider("Angle", record.amount, 1...360) { r, v in r.amount = v }
            Text("Spins the edges around the axis through the origin — draw a profile with a Circle or Plane, then screw it into a vase.").font(.footnote).foregroundStyle(.secondary)
        case .twist:
            axis
            slider("Angle", record.amount, -720...720) { r, v in r.amount = v }
        case .taper:
            axis
            slider("Factor", record.amount, -1...1) { r, v in r.amount = v }
        case .bend:
            axis
            slider("Angle", record.amount, -360...360) { r, v in r.amount = v }
        case .remesh:
            stepper("Resolution", record.count, 16...200, step: 8) { r, v in r.count = v }
            toggle("Smooth", record.flag) { r, v in r.flag = v }
        }
    }

    private var axis: some View {
        Picker("Axis", selection: Binding(get: { record.axis }, set: { v in update { $0.axis = v } })) {
            Text("X").tag(0); Text("Y").tag(1); Text("Z").tag(2)
        }
        .pickerStyle(.segmented)
    }

    private func toggle(_ title: String, _ value: Bool, _ set: @escaping (inout ModifierRecord, Bool) -> Void) -> some View {
        Toggle(title, isOn: Binding(get: { value }, set: { v in update { set(&$0, v) } }))
    }

    private func stepper(_ title: String, _ value: Int, _ range: ClosedRange<Int>, step: Int = 1, _ set: @escaping (inout ModifierRecord, Int) -> Void) -> some View {
        Stepper(value: Binding(get: { value }, set: { v in update { set(&$0, v) } }), in: range, step: step) {
            HStack { Text(title); Spacer(); Text("\(value)").foregroundStyle(.secondary).monospacedDigit() }
        }
    }

    private func slider(_ title: String, _ value: Float, _ range: ClosedRange<Float>, _ set: @escaping (inout ModifierRecord, Float) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { Text(title); Spacer(); Text(String(format: "%.3f", value)).foregroundStyle(.secondary).monospacedDigit() }
            Slider(value: Binding(get: { value }, set: { v in update { set(&$0, v) } }), in: range)
        }
    }
}

final class ProceduralThumbs {
    @MainActor static let shared = ProceduralThumbs()
    private var cache: [ProceduralTexture: UIImage] = [:]
    @MainActor func image(_ k: ProceduralTexture) -> UIImage {
        if let i = cache[k] { return i }
        let i = StudioModel.proceduralImage(k, size: 96)
        cache[k] = i
        return i
    }
}

// MARK: - World / render settings

struct WorldForm: View {
    @ObservedObject var model: StudioModel
    var body: some View {
        Form {
            Section("Background & Lighting") {
                Picker("World", selection: $model.world.background) {
                    ForEach(WorldBackground.allCases) { Text($0.rawValue).tag($0) }
                }
                if model.world.background == .color {
                    ColorPicker("Colour", selection: Binding(get: { Color(red: Double(model.world.r), green: Double(model.world.g), blue: Double(model.world.b)) },
                                                            set: { c in
                                                                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                                                                UIColor(c).getRed(&r, green: &g, blue: &b, alpha: &a)
                                                                model.world.r = Float(r); model.world.g = Float(g); model.world.b = Float(b)
                                                            }), supportsOpacity: false)
                }
                MaterialSlider(title: "Environment Light", value: Binding(get: { model.world.environment / 3 }, set: { model.world.environment = $0 * 3 }))
            }
            Section("Sun") {
                Toggle("Sun Light", isOn: $model.world.sun)
                MaterialSlider(title: "Strength", value: Binding(get: { model.world.sunIntensity / 3000 }, set: { model.world.sunIntensity = $0 * 3000 }))
                MaterialSlider(title: "Elevation", value: Binding(get: { model.world.sunElevation / 90 }, set: { model.world.sunElevation = max(1, $0 * 90) }))
                MaterialSlider(title: "Rotation", value: Binding(get: { model.world.sunRotation / 360 }, set: { model.world.sunRotation = $0 * 360 }))
            }
            Section("Render") {
                Toggle("Floor Shadow", isOn: $model.world.floorShadow)
                Toggle("Ambient Occlusion (renders)", isOn: $model.world.ambientOcclusion)
            }
            Section {
                VStack(alignment: .leading) {
                    HStack { Text("Boolean Resolution"); Spacer(); Text("\(Int(model.voxelResolution))").foregroundStyle(.secondary).monospacedDigit() }
                    Slider(value: $model.voxelResolution, in: 32...200, step: 8)
                }
                VStack(alignment: .leading) {
                    HStack { Text("Remesh Resolution"); Spacer(); Text("\(Int(model.remeshResolution))").foregroundStyle(.secondary).monospacedDigit() }
                    Slider(value: $model.remeshResolution, in: 16...200, step: 8)
                }
            } header: { Text("Voxel Tools") } footer: { Text("Higher values keep more detail but take longer.") }
        }
    }
}

// MARK: - Add menu (Shift-A)

struct AddObjectSheet: View {
    @ObservedObject var model: StudioModel
    @Environment(\.dismiss) private var dismiss
    @State private var text = "Hello"
    private let cols = [GridItem(.adaptive(minimum: 88), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    section("Mesh", Primitive.basic)
                    section("More Shapes", Primitive.extra.filter { $0 != .text })
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Text").font(.headline)
                        HStack(spacing: 10) {
                            TextField("Your text", text: $text).textFieldStyle(.roundedBorder)
                            Button("Add") { model.addPrimitive(.text, text: text.isEmpty ? "Text" : text); dismiss() }
                                .buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
                        }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Light").font(.headline)
                        LazyVGrid(columns: cols, spacing: 12) {
                            ForEach(LightKind.allCases) { k in
                                tile(k.rawValue, k.icon) { model.addLight(k); dismiss() }
                            }
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle("Add").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }

    private func section(_ title: String, _ items: [Primitive]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            LazyVGrid(columns: cols, spacing: 12) {
                ForEach(items) { p in tile(p.rawValue, p.icon) { model.addPrimitive(p); dismiss() } }
            }
        }
    }

    private func tile(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 24, weight: .semibold)).foregroundStyle(.tint).frame(height: 30)
                Text(title).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity).frame(height: 78)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Render (F12)

struct RenderSheet: View {
    @ObservedObject var model: StudioModel
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var size = 1
    @State private var transparent = false
    @State private var working = false
    @State private var saved = false
    private let sizes: [(String, Int, Int)] = [("HD 1280×720", 1280, 720), ("Full HD 1920×1080", 1920, 1080), ("Square 2048", 2048, 2048), ("Portrait 1080×1920", 1080, 1920), ("4K 3840×2160", 3840, 2160)]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16).fill(Color.primary.opacity(0.06))
                        if let image {
                            Image(uiImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 12)).padding(6)
                        } else if working {
                            ProgressView()
                        } else {
                            Label("Renders the current view without the grid and gizmos", systemImage: "camera.aperture").font(.footnote).foregroundStyle(.secondary).padding()
                        }
                    }
                    .frame(minHeight: 200)
                }
                Section("Output") {
                    Picker("Resolution", selection: $size) { ForEach(sizes.indices, id: \.self) { Text(sizes[$0].0).tag($0) } }
                    Toggle("Transparent Background", isOn: $transparent)
                    Toggle("Ambient Occlusion", isOn: $model.world.ambientOcclusion)
                }
                Section {
                    Button { render() } label: { Label(image == nil ? "Render Image" : "Render Again", systemImage: "camera.aperture").frame(maxWidth: .infinity) }
                        .disabled(working)
                    if let image {
                        Button { saveToPhotos(image) } label: { Label(saved ? "Saved to Photos" : "Save to Photos", systemImage: saved ? "checkmark" : "square.and.arrow.down").frame(maxWidth: .infinity) }
                        Button { share(image) } label: { Label("Share…", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity) }
                    }
                }
            }
            .navigationTitle("Render").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }

    private func render() {
        working = true; saved = false
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000)
            let s = sizes[size]
            image = model.render(width: s.1, height: s.2, transparent: transparent)
            working = false
            Haptics.tap(.medium)
        }
    }

    private func saveToPhotos(_ img: UIImage) {
        let out = transparent ? (img.pngData().flatMap { UIImage(data: $0) } ?? img) : img
        UIImageWriteToSavedPhotosAlbum(out, nil, nil, nil)
        saved = true
    }

    private func share(_ img: UIImage) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(model.projectName.isEmpty ? "Render" : model.projectName).png")
        try? img.pngData()?.write(to: url)
        dismiss()
        Task { @MainActor in try? await Task.sleep(nanoseconds: 450_000_000); SharePresenter.share(url) }
    }
}
