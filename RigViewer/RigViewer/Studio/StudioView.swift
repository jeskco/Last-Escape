import SwiftUI
import SceneKit

struct StudioView: View {
    @ObservedObject var model: StudioModel
    /// Called when the person taps Done: hands the result to the viewer.
    var onDone: (StudioModel) -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var showProperties = false
    @State private var showOutliner = false
    @State private var showExport = false
    @State private var showBones = false
    @State private var renaming = false
    @State private var newName = ""
    @State private var savingAnimation = false
    @State private var animationName = ""

    var body: some View {
        ZStack {
            LinearGradient(colors: scheme == .dark ? [Color(white: 0.16), Color(white: 0.07)] : [Color(white: 0.96), Color(white: 0.84)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            StudioSceneView(model: model).ignoresSafeArea()

            VStack(spacing: 10) {
                topBar
                hint
                Spacer(minLength: 0)
                bottomArea
            }
            .padding(.horizontal, 12).padding(.top, 4).padding(.bottom, 6)

            if let t = model.toast {
                VStack {
                    Text(t).font(.subheadline.weight(.medium)).padding(.horizontal, 18).padding(.vertical, 11)
                        .glass(Capsule()).padding(.top, 70)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity)).allowsHitTesting(false)
            }
        }
        .sheet(isPresented: $showProperties) { StudioPropertiesView(model: model).presentationDetents([.medium, .large]).presentationBackgroundInteraction(.enabled(upThrough: .medium)) }
        .sheet(isPresented: $showOutliner) { StudioOutlinerView(model: model).presentationDetents([.medium, .large]) }
        .sheet(isPresented: $showExport) { StudioExportView(model: model).presentationDetents([.medium, .large]) }
        .sheet(isPresented: $showBones) { BonePickerView(model: model).presentationDetents([.medium, .large]) }
        .alert("Rename Model", isPresented: $renaming) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Save") { if !newName.trimmingCharacters(in: .whitespaces).isEmpty { model.projectName = newName } }
        }
        .alert("Save Animation", isPresented: $savingAnimation) {
            TextField("Name", text: $animationName)
            Button("Cancel", role: .cancel) {}
            Button("Save") { _ = model.saveAnimation(name: animationName) }
        } message: { Text("It will appear in the viewer's animation list when you tap Done.") }
    }

    // MARK: top bar

    private var topBar: some View {
        GlassGroup(spacing: 8) {
            HStack(spacing: 8) {
                Button { onDone(model) } label: {
                    Text("Done").font(.system(size: 16, weight: .semibold)).padding(.horizontal, 16).frame(height: 44)
                }
                .buttonStyle(.plain).glass(Capsule(), interactive: true)

                Menu {
                    Button("Rename", systemImage: "pencil") { newName = model.projectName; renaming = true }
                    Button("Save Project", systemImage: "square.and.arrow.down") { model.saveProject(); model.showToast(model.hasSavableContent ? "Saved" : "Add a shape to save a project") }
                    Button("Outliner", systemImage: "list.bullet.indent") { showOutliner = true }
                    Divider()
                    Toggle(isOn: $model.showGrid) { Label("Grid", systemImage: "grid") }
                    Toggle(isOn: $model.snapping) { Label("Snapping", systemImage: "ruler") }
                    Button("Frame All", systemImage: "scope") { model.selection = []; model.focusSelection() }
                } label: {
                    VStack(spacing: 0) {
                        Text(model.projectName).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                        Text(stats).font(.caption2).foregroundStyle(.secondary).lineLimit(1).monospacedDigit()
                    }
                    .padding(.horizontal, 14).frame(maxWidth: .infinity).frame(height: 44)
                }
                .buttonStyle(.plain).glass(Capsule(), interactive: true)

                circle("arrow.uturn.backward", enabled: model.canUndo) { model.undo() }.accessibilityLabel("Undo")
                circle("arrow.uturn.forward", enabled: model.canRedo) { model.redo() }.accessibilityLabel("Redo")
                Button { showExport = true } label: {
                    Image(systemName: "square.and.arrow.up").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white).frame(width: 44, height: 44)
                }
                .buttonStyle(.plain).glass(Circle(), tint: .accentColor, interactive: true).accessibilityLabel("Export")
            }
        }
    }

    private var stats: String {
        _ = model.revision
        let meshes = model.objects.compactMap(\.mesh)
        let tris = meshes.reduce(0) { $0 + $1.triangleCount }
        let n = model.objects.count
        return "\(n) \(n == 1 ? "object" : "objects")" + (tris > 0 ? " · \(Fmt.count(tris)) tris" : "")
    }

    private func circle(_ icon: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 15, weight: .semibold)).frame(width: 44, height: 44).contentShape(Circle())
        }
        .buttonStyle(.plain).glass(Circle(), interactive: true).disabled(!enabled).opacity(enabled ? 1 : 0.45)
    }

    @ViewBuilder private var hint: some View {
        let text: String? = {
            if model.objects.isEmpty { return "Tap Add to place your first shape" }
            switch model.mode {
            case .object: return model.selection.isEmpty ? "Tap a shape to select it · drag empty space to orbit" : nil
            case .edit: return model.editVertices.isEmpty ? "Tap \(model.selectMode.rawValue.lowercased())s to select them" : nil
            case .sculpt: return "Drag on the shape to sculpt · two fingers to move the view"
            case .pose: return model.selectedBone == nil ? "Tap a joint (dot) to pose it" : nil
            }
        }()
        if let text {
            Text(text).font(.footnote.weight(.medium)).foregroundStyle(.secondary)
                .padding(.horizontal, 14).padding(.vertical, 7).background(.ultraThinMaterial, in: Capsule())
                .transition(.opacity)
        }
    }

    // MARK: bottom: tools + mode switcher

    private var bottomArea: some View {
        VStack(spacing: 10) {
            Group {
                switch model.mode {
                case .object: objectTools
                case .edit: editTools
                case .sculpt: sculptTools
                case .pose: poseTools
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .glass(RoundedRectangle(cornerRadius: 28, style: .continuous))
            modeSwitcher
        }
    }

    private var modeSwitcher: some View {
        HStack(spacing: 4) {
            ForEach(StudioMode.allCases) { m in
                let on = model.mode == m
                Button { withAnimation(.snappy) { model.mode = m }; Haptics.select() } label: {
                    VStack(spacing: 2) {
                        Image(systemName: m.icon).font(.system(size: 16, weight: .semibold))
                        Text(m.rawValue).font(.caption2.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity).frame(height: 50)
                    .foregroundStyle(on ? Color.white : Color.primary)
                    .background { if on { Capsule().fill(Color.accentColor) } }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .glass(Capsule())
    }

    // MARK: object tools

    private var objectTools: some View {
        ToolStrip {
            Menu {
                ForEach(Primitive.allCases) { p in Button(p.rawValue, systemImage: p.icon) { model.addPrimitive(p) } }
            } label: { ToolLabel(icon: "plus", title: "Add", tint: .accentColor) }
            GizmoPicker(model: model)
            ToolButton(icon: "checkmark.circle", title: "Multi", on: model.multiSelect) { model.multiSelect.toggle() }
            ToolButton(icon: "slider.horizontal.3", title: "Properties", enabled: !model.selection.isEmpty) { showProperties = true }
            ToolButton(icon: "plus.square.on.square", title: "Duplicate", enabled: !model.selection.isEmpty) { model.duplicateSelection() }
            ToolButton(icon: "trash", title: "Delete", enabled: !model.selection.isEmpty, destructive: true) { model.deleteSelection() }
            ToolButton(icon: "link", title: "Join", enabled: model.selection.count > 1) { model.joinSelection() }
            ToolButton(icon: "checkmark.seal", title: "Apply", enabled: model.primary?.mesh != nil) { model.applyTransform() }
            if model.primary?.isImported == true {
                ToolButton(icon: "wand.and.stars", title: "Make Editable") { if let p = model.primary { model.convertToEditable(p) } }
            }
            ToolButton(icon: "scope", title: "Focus") { model.focusSelection() }
            ToolButton(icon: "list.bullet.indent", title: "Outliner") { showOutliner = true }
            ToolButton(icon: "ruler", title: "Snap", on: model.snapping) { model.snapping.toggle() }
        }
    }

    // MARK: edit tools

    private var editTools: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Picker("Select", selection: $model.selectMode) {
                    ForEach(SelectMode.allCases) { Image(systemName: $0.icon).tag($0).accessibilityLabel($0.rawValue) }
                }
                .pickerStyle(.segmented).frame(maxWidth: 150)
                GizmoPicker(model: model, compact: true)
                Spacer(minLength: 0)
                SmallToggle(icon: "checkmark.circle", on: model.multiSelect) { model.multiSelect.toggle() }.accessibilityLabel("Multi-select")
                SmallToggle(icon: "eye.trianglebadge.exclamationmark", on: model.xray) { model.xray.toggle() }.accessibilityLabel("X-ray")
            }
            ToolStrip {
                ToolButton(icon: "checkmark.square", title: "All") { model.selectAll() }
                ToolButton(icon: "square", title: "None") { model.selectNone() }
                ToolButton(icon: "arrow.left.arrow.right.square", title: "Invert") { model.invertSelection() }
                ToolButton(icon: "square.stack.3d.up.fill", title: "Extrude", tint: .accentColor) { model.extrude() }
                ToolButton(icon: "square.inset.filled", title: "Inset") { model.inset() }
                ToolButton(icon: "square.on.square.squareshape.controlhandles", title: "Bevel") { model.bevel() }
                Menu {
                    Button("Smooth (Catmull–Clark)", systemImage: "circle.grid.cross") { model.subdivide(smooth: true) }
                    Button("Simple", systemImage: "square.grid.2x2") { model.subdivide(smooth: false) }
                } label: { ToolLabel(icon: "square.grid.3x3", title: "Subdivide") }
                ToolButton(icon: "drop", title: "Smooth") { model.smoothSelection() }
                ToolButton(icon: "arrow.triangle.merge", title: "Merge") { model.mergeSelection() }
                ToolButton(icon: "square.dashed", title: "Make Face") { model.makeFace() }
                ToolButton(icon: "trash", title: "Delete", destructive: true) { model.deleteEditSelection() }
                ToolButton(icon: "arrow.left.and.right.righttriangle.left.righttriangle.right", title: "Mirror X") { model.mirrorX() }
                ToolButton(icon: "arrow.uturn.up.square", title: "Flip") { model.flipNormals() }
                ToolButton(icon: "triangle", title: "Triangulate") { model.triangulate() }
                ToolButton(icon: model.primary?.mesh?.smooth == true ? "circle.fill" : "hexagon", title: model.primary?.mesh?.smooth == true ? "Smooth Shade" : "Flat Shade") { model.toggleSmoothShading() }
            }
        }
    }

    // MARK: sculpt tools

    private var sculptTools: some View {
        VStack(spacing: 10) {
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(SculptBrush.allCases) { b in
                        let on = model.brush == b
                        Button { model.brush = b; Haptics.select() } label: {
                            VStack(spacing: 3) {
                                Image(systemName: b.icon).font(.system(size: 17, weight: .semibold)).frame(height: 22)
                                Text(b.rawValue).font(.caption2.weight(.semibold))
                            }
                            .frame(width: 62, height: 54)
                            .foregroundStyle(on ? Color.white : Color.primary)
                            .background(on ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.primary.opacity(0.07)), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.hidden)
            HStack(spacing: 14) {
                LabeledSlider(icon: "circle.dashed", value: $model.brushRadius, range: 0.03...0.5)
                LabeledSlider(icon: "bolt.fill", value: $model.brushStrength, range: 0.05...1)
            }
            HStack(spacing: 8) {
                SmallToggle(icon: "minus.circle", title: "Invert", on: model.brushInvert) { model.brushInvert.toggle() }
                SmallToggle(icon: "arrow.left.and.right", title: "Mirror X", on: model.symmetryX) { model.symmetryX.toggle() }
                Spacer(minLength: 0)
                Button { model.addDetail() } label: { Label("Add Detail", systemImage: "plus.magnifyingglass").font(.footnote.weight(.semibold)) }
                    .buttonStyle(.plain).padding(.horizontal, 12).frame(height: 34).background(Color.primary.opacity(0.08), in: Capsule())
            }
        }
    }

    // MARK: pose tools

    private var poseTools: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Button { showBones = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "figure.stand").font(.footnote.weight(.semibold))
                        Text(model.selectedBone?.name ?? "Choose Bone").font(.footnote.weight(.semibold)).lineLimit(1)
                        Image(systemName: "chevron.down").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12).frame(height: 34).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.08), in: Capsule())
                }
                .buttonStyle(.plain)
                Picker("Tool", selection: $model.gizmoKind) {
                    Image(systemName: GizmoKind.rotate.icon).tag(GizmoKind.rotate)
                    Image(systemName: GizmoKind.move.icon).tag(GizmoKind.move)
                }
                .pickerStyle(.segmented).frame(width: 96)
                Menu {
                    Button("Reset Bone", systemImage: "arrow.counterclockwise") { model.resetBone() }.disabled(model.selectedBone == nil)
                    Button("Reset Whole Pose", systemImage: "figure.stand") { model.resetPose() }
                    Button("Mirror Pose", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right") { model.mirrorPose() }
                } label: { Image(systemName: "ellipsis").font(.body.weight(.semibold)).frame(width: 34, height: 34).background(Color.primary.opacity(0.08), in: Circle()) }
            }
            PoseTimeline(model: model)
            HStack(spacing: 8) {
                Button { model.addKey() } label: { Label("Key", systemImage: "diamond.fill").font(.footnote.weight(.semibold)) }
                    .buttonStyle(.plain).foregroundStyle(.white).padding(.horizontal, 14).frame(height: 34).background(Color.accentColor, in: Capsule())
                Button { model.deleteKey() } label: { Image(systemName: "diamond.slash") .font(.footnote.weight(.semibold)).frame(width: 34, height: 34) }
                    .buttonStyle(.plain).background(Color.primary.opacity(0.08), in: Circle()).disabled(model.keys.isEmpty)
                Menu {
                    ForEach([1.0, 2.0, 3.0, 5.0, 10.0], id: \.self) { d in Button("\(Int(d)) seconds") { model.poseDuration = d; if model.poseTime > d { model.poseTime = d } } }
                } label: { Text("\(Int(model.poseDuration)) s").font(.footnote.weight(.semibold)).monospacedDigit().padding(.horizontal, 12).frame(height: 34).background(Color.primary.opacity(0.08), in: Capsule()) }
                SmallToggle(icon: "repeat", on: model.loopPose) { model.loopPose.toggle() }
                Spacer(minLength: 0)
                Button { animationName = ""; savingAnimation = true } label: { Label("Save", systemImage: "film.stack").font(.footnote.weight(.semibold)) }
                    .buttonStyle(.plain).padding(.horizontal, 12).frame(height: 34).background(Color.primary.opacity(0.08), in: Capsule())
                    .disabled(model.keys.count < 2)
            }
        }
    }
}

// MARK: - Small building blocks

struct ToolStrip<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        ScrollView(.horizontal) { HStack(spacing: 4) { content() }.padding(.horizontal, 2) }
            .scrollIndicators(.hidden)
    }
}

struct ToolLabel: View {
    let icon: String, title: String
    var tint: Color? = nil
    var on = false
    var destructive = false
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 18, weight: .semibold)).frame(height: 24)
                .foregroundStyle(on ? Color.white : destructive ? Color.red : (tint ?? Color.primary))
            Text(title).font(.caption2.weight(.medium)).lineLimit(1).foregroundStyle(on ? Color.white : Color.primary)
        }
        .frame(minWidth: 62).frame(height: 56).padding(.horizontal, 2)
        .background { if on { RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.accentColor) } }
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct ToolButton: View {
    let icon: String, title: String
    var enabled = true
    var on = false
    var destructive = false
    var tint: Color? = nil
    let action: () -> Void
    var body: some View {
        Button { action(); Haptics.select() } label: { ToolLabel(icon: icon, title: title, tint: tint, on: on, destructive: destructive) }
            .buttonStyle(.plain).disabled(!enabled).opacity(enabled ? 1 : 0.35)
    }
}

struct SmallToggle: View {
    let icon: String
    var title: String? = nil
    let on: Bool
    let action: () -> Void
    var body: some View {
        Button { action(); Haptics.select() } label: {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.footnote.weight(.semibold))
                if let title { Text(title).font(.footnote.weight(.semibold)) }
            }
            .padding(.horizontal, title == nil ? 0 : 12).frame(minWidth: 34).frame(height: 34)
            .foregroundStyle(on ? Color.white : Color.primary)
            .background(on ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.primary.opacity(0.08)), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct LabeledSlider: View {
    let icon: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.footnote.weight(.semibold)).foregroundStyle(.secondary).frame(width: 18)
            Slider(value: $value, in: range)
        }
    }
}

struct GizmoPicker: View {
    @ObservedObject var model: StudioModel
    var compact = false
    var body: some View {
        HStack(spacing: compact ? 0 : 2) {
            ForEach(GizmoKind.allCases) { k in
                let on = model.gizmoKind == k
                Button { model.gizmoKind = k; Haptics.select() } label: {
                    if compact {
                        Image(systemName: k.icon).font(.footnote.weight(.semibold)).frame(width: 36, height: 32)
                            .foregroundStyle(on ? Color.white : Color.primary)
                            .background { if on { Capsule().fill(Color.accentColor) } }
                    } else {
                        ToolLabel(icon: k.icon, title: k.rawValue, on: on)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(compact ? 2 : 0)
        .background { if compact { Capsule().fill(Color.primary.opacity(0.08)) } }
    }
}

struct PoseTimeline: View {
    @ObservedObject var model: StudioModel
    var body: some View {
        HStack(spacing: 10) {
            Button { model.posePlaying.toggle(); Haptics.tap() } label: {
                Image(systemName: model.posePlaying ? "pause.fill" : "play.fill").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 38, height: 38).background(Color.accentColor, in: Circle())
            }
            .buttonStyle(.plain).disabled(model.keys.count < 2).opacity(model.keys.count < 2 ? 0.5 : 1)
            VStack(spacing: 2) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        ForEach(model.keys) { k in
                            Image(systemName: "diamond.fill").font(.system(size: 9)).foregroundStyle(.tint)
                                .position(x: CGFloat(k.time / max(model.poseDuration, 0.01)) * (geo.size.width - 20) + 10, y: 6)
                        }
                    }
                }
                .frame(height: 12)
                Slider(value: $model.poseTime, in: 0...max(model.poseDuration, 0.1))
            }
            Text(String(format: "%.2f", model.poseTime)).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 36)
        }
    }
}
