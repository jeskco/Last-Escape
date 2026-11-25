import SwiftUI
import SceneKit

enum ObjectCategory: String, CaseIterable, Identifiable { case transform = "Transform", object = "Object", modify = "Modify"; var id: String { rawValue } }
enum EditCategory: String, CaseIterable, Identifiable { case select = "Select", mesh = "Mesh", faces = "Faces", edges = "Edges", normals = "Normals & UV"; var id: String { rawValue } }

struct StudioView: View {
    @ObservedObject var model: StudioModel
    /// Called when the person taps Done: hands the result to the viewer.
    /// True for models made from Home: Done asks to save new work, then returns Home.
    var savesAsProject = false
    var onDone: () -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var showProperties = false
    @State private var propertiesTab: PropertiesTab = .object
    @State private var showOutliner = false
    @State private var showExport = false
    @State private var showBones = false
    @State private var showAdd = false
    @State private var showRender = false
    @State private var renaming = false
    @State private var newName = ""
    @State private var savingAnimation = false
    @State private var animationName = ""
    @State private var objectCategory: ObjectCategory = .transform
    @State private var editCategory: EditCategory = .select
    @State private var lastOpOpen = true
    @State private var askSave = false
    @Namespace private var modeNS
    @Namespace private var chipNS
    /// True when the tools live in the landscape sidebar.
    @State private var verticalTools = false

    var body: some View {
        ZStack {
            Aurora(accent: .accentColor, intensity: 0.55, animated: !AppSettings.shared.batterySaver)
            StudioSceneView(model: model).ignoresSafeArea()

            GeometryReader { geo in
                Group {
                if geo.size.width > geo.size.height {
                    landscapeLayout(width: geo.size.width)
                } else {
                    VStack(spacing: 10) {
                        topBar
                        statusLine
                        Spacer(minLength: 0)
                        if let op = model.lastOp { lastOpPanel(op).id(op.title) }
                        bottomArea
                    }
                    .padding(.horizontal, 12).padding(.top, 4).padding(.bottom, 6)
                }
                }
                .onAppear { verticalTools = geo.size.width > geo.size.height }
                .onChange(of: geo.size) { _, sz in verticalTools = sz.width > sz.height }
            }
            .animation(Theme.spring, value: model.lastOp?.title)
            .animation(Theme.snappy, value: model.dragReadout == nil)
            .animation(Theme.spring, value: model.mode)

            if let t = model.toast {
                VStack {
                    Text(t).font(.subheadline.weight(.medium)).padding(.horizontal, 18).padding(.vertical, 11)
                        .glass(Capsule()).padding(.top, 70)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity)).allowsHitTesting(false)
            }
            if let b = model.busy {
                VStack(spacing: 12) { ProgressView().controlSize(.large); Text(b).font(.subheadline.weight(.semibold)) }
                    .padding(26).glass(RoundedRectangle(cornerRadius: 26, style: .continuous))
            }
            shortcuts
        }
        .sheet(isPresented: $showProperties) {
            StudioPropertiesView(model: model, tab: $propertiesTab).presentationDetents([.medium, .large]).presentationBackgroundInteraction(.enabled(upThrough: .medium))
        }
        .sheet(isPresented: $showOutliner) { StudioOutlinerView(model: model).presentationDetents([.medium, .large]) }
        .sheet(isPresented: $showExport) { StudioExportView(model: model).presentationDetents([.medium, .large]) }
        .sheet(isPresented: $showBones) { BonePickerView(model: model).presentationDetents([.medium, .large]) }
        .sheet(isPresented: $showAdd) { AddObjectSheet(model: model).presentationDetents([.medium, .large]) }
        .sheet(isPresented: $showRender) { RenderSheet(model: model).presentationDetents([.large]) }
        .confirmationDialog("Save “\(model.projectName)”?", isPresented: $askSave, titleVisibility: .visible) {
            Button("Save Project") { model.saveProject(); Haptics.tap(.medium); onDone() }
            Button("Save & Export…") { model.saveProject(); showExport = true }
            Button("Save & Render Image…") { model.saveProject(); showRender = true }
            Button("Don't Save", role: .destructive) { model.dirty = false; onDone() }
            Button("Keep Editing", role: .cancel) {}
        } message: { Text("This model hasn't been saved yet.") }
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

    private func openProperties(_ tab: PropertiesTab) { propertiesTab = tab; showProperties = true }

    /// Runs a mesh tool; on big meshes it shows "Working…" first so the app never looks frozen.
    private func run(_ work: @escaping () -> Void) { model.perform(work) }

    /// ✓ button: new unsaved work asks first; saved projects save their changes and leave.
    private func finish() {
        Haptics.tap()
        guard savesAsProject, model.hasSavableContent else { onDone(); return }
        if model.isSavedProject {
            if model.dirty { model.saveProject(); model.showToast("Saved") }
            onDone()
        } else {
            askSave = true
        }
    }

    // MARK: keyboard shortcuts (iPad / Mac keyboards), Blender-style

    private var shortcuts: some View {
        ZStack {
            Group {
                Button("") { model.gizmoKind = .move }.keyboardShortcut("g", modifiers: [])
                Button("") { model.gizmoKind = .rotate }.keyboardShortcut("r", modifiers: [])
                Button("") { model.gizmoKind = .scale }.keyboardShortcut("s", modifiers: [])
                Button("") { model.mode = model.mode == .edit ? .object : .edit }.keyboardShortcut(.tab, modifiers: [])
                Button("") { if model.mode == .edit { model.deleteEditSelection() } else { model.deleteSelection() } }.keyboardShortcut("x", modifiers: [])
                Button("") { if model.mode == .edit { model.deleteEditSelection() } else { model.deleteSelection() } }.keyboardShortcut(.delete, modifiers: [])
                Button("") { model.undo() }.keyboardShortcut("z", modifiers: .command)
                Button("") { model.redo() }.keyboardShortcut("z", modifiers: [.command, .shift])
            }
            Group {
                Button("") { if model.mode == .edit { model.duplicateEditSelection() } else { model.duplicateSelection() } }.keyboardShortcut("d", modifiers: .shift)
                Button("") { model.selectAll() }.keyboardShortcut("a", modifiers: [])
                Button("") { model.selectNone() }.keyboardShortcut("a", modifiers: .option)
                Button("") { if model.mode == .edit { model.extrude() } }.keyboardShortcut("e", modifiers: [])
                Button("") { if model.mode == .edit { model.inset() } }.keyboardShortcut("i", modifiers: [])
                Button("") { if model.mode == .edit { model.loopCut() } }.keyboardShortcut("r", modifiers: .command)
                Button("") { if model.mode == .edit { model.selectLinked() } }.keyboardShortcut("l", modifiers: [])
                Button("") { model.selectMode = .vertex }.keyboardShortcut("1", modifiers: [])
            }
            Group {
                Button("") { model.selectMode = .edge }.keyboardShortcut("2", modifiers: [])
                Button("") { model.selectMode = .face }.keyboardShortcut("3", modifiers: [])
                Button("") { model.focusSelection() }.keyboardShortcut("f", modifiers: [])
                Button("") { showAdd = true }.keyboardShortcut("a", modifiers: .shift)
                Button("") { openProperties(.object) }.keyboardShortcut("n", modifiers: [])
                Button("") { model.proportional.toggle() }.keyboardShortcut("o", modifiers: [])
                Button("") { showRender = true }.keyboardShortcut("r", modifiers: [.command, .shift])
                Button("") { model.xray.toggle() }.keyboardShortcut("z", modifiers: .option)
            }
        }
        .opacity(0).frame(width: 0, height: 0).allowsHitTesting(false).accessibilityHidden(true)
    }

    // MARK: top bar

    private var topBar: some View {
        GlassGroup(spacing: 8) {
            HStack(spacing: 8) {
                Button { finish() } label: {
                    Image(systemName: "checkmark").font(.system(size: 16, weight: .heavy)).foregroundStyle(.white)
                        .frame(width: 44, height: 44).contentShape(Circle())
                }
                .buttonStyle(.pressable).glass(Circle(), tint: .accentColor, interactive: true).accessibilityLabel("Done")

                Menu {
                    Button("Rename", systemImage: "pencil") { newName = model.projectName; renaming = true }
                    Button("Save Project", systemImage: "square.and.arrow.down") { model.saveProject(); model.showToast(model.hasSavableContent ? "Saved" : "Add a shape to save a project") }
                    Button("Outliner", systemImage: "list.bullet.indent") { showOutliner = true }
                    Button("Scene & World", systemImage: "globe") { openProperties(.world) }
                    Divider()
                    Toggle(isOn: $model.showGrid) { Label("Grid & Floor", systemImage: "grid") }
                    Toggle(isOn: $model.snapping) { Label("Snapping", systemImage: "ruler") }
                    Button("Frame All", systemImage: "scope") { model.selection = []; model.focusSelection() }
                } label: {
                    VStack(spacing: 0) {
                        Text(model.projectName).font(.system(size: 15, weight: .bold, design: .rounded)).lineLimit(1).truncationMode(.middle)
                        Text(stats).font(.caption2).foregroundStyle(.secondary).lineLimit(1).monospacedDigit()
                    }
                    .padding(.horizontal, 12).frame(maxWidth: .infinity).frame(height: 44)
                }
                .buttonStyle(.plain).glass(Capsule(), interactive: true)

                HStack(spacing: 0) {
                    Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward").frame(width: 40, height: 44).contentShape(Rectangle()) }
                        .disabled(!model.canUndo).opacity(model.canUndo ? 1 : 0.4).accessibilityLabel("Undo")
                    Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward").frame(width: 40, height: 44).contentShape(Rectangle()) }
                        .disabled(!model.canRedo).opacity(model.canRedo ? 1 : 0.4).accessibilityLabel("Redo")
                }
                .font(.system(size: 15, weight: .semibold))
                .buttonStyle(.pressable)
                .glass(Capsule(), interactive: true)

                Menu {
                    Picker("Shading", selection: $model.shading) {
                        ForEach(ViewShading.allCases) { Label($0.rawValue, systemImage: $0.icon).tag($0) }
                    }
                    Toggle(isOn: $model.xray) { Label("X-Ray", systemImage: "eye.trianglebadge.exclamationmark") }
                    Toggle(isOn: $model.showGrid) { Label("Grid & Floor", systemImage: "grid") }
                } label: {
                    Image(systemName: model.shading.icon).font(.system(size: 15, weight: .semibold)).frame(width: 44, height: 44).contentShape(Circle())
                }
                .buttonStyle(.plain).glass(Circle(), interactive: true).accessibilityLabel("Viewport shading")

                Menu {
                    Button("Export Model…", systemImage: "square.and.arrow.up") { showExport = true }
                    Button("Render Image…", systemImage: "camera.aperture") { showRender = true }
                } label: {
                    Image(systemName: "square.and.arrow.up").font(.system(size: 15, weight: .semibold)).frame(width: 44, height: 44).contentShape(Circle())
                }
                .buttonStyle(.plain).glass(Circle(), interactive: true).accessibilityLabel("Export or render")
            }
        }
    }

    private var stats: String { model.statsText }

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
            case .paint: return "Drag on the shape to paint · two fingers to move the view"
            case .pose: return model.selectedBone == nil ? "Tap a dot to choose what to animate" : nil
            }
        }()
        if let text {
            Text(text).font(.footnote.weight(.medium)).foregroundStyle(.secondary)
                .padding(.horizontal, 14).padding(.vertical, 7).background(.ultraThinMaterial, in: Capsule())
                .transition(.opacity)
        }
    }

    // MARK: adjust last operation

    private func lastOpPanel(_ op: LastOperation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { withAnimation(.snappy) { lastOpOpen.toggle() } } label: {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.below.rectangle").font(.footnote.weight(.semibold))
                    Text(op.title).font(.footnote.weight(.semibold))
                    Spacer()
                    Image(systemName: lastOpOpen ? "chevron.down" : "chevron.up").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    Button { model.lastOp = nil } label: { Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(.secondary).frame(width: 26, height: 26) }
                        .buttonStyle(.plain)
                }
            }
            .buttonStyle(.plain)
            if lastOpOpen {
                ForEach(Array(op.params.enumerated()), id: \.offset) { i, p in
                    HStack(spacing: 10) {
                        Text(p.name).font(.caption).frame(width: 92, alignment: .leading).lineLimit(1)
                        Slider(value: Binding(get: { op.params[i].value }, set: { model.adjustLastOp(i, $0) }), in: p.range)
                        Text(p.step != nil ? String(format: "%.0f", p.value) : String(format: "%.3f", p.value))
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 52, alignment: .trailing)
                    }
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: 520)
        .glass(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: bottom: tools + mode switcher

    private var toolsContent: some View {
        Group {
            switch model.mode {
            case .object: objectTools
            case .edit: editTools
            case .sculpt: sculptTools
            case .paint: paintTools
            case .pose: poseTools
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .id(model.mode)
        .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
    }

    private var bottomArea: some View {
        VStack(spacing: 10) {
            toolsContent
                .glass(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .animation(Theme.spring, value: model.mode)
            modeSwitcher
        }
    }

    @ViewBuilder private var statusLine: some View {
        if let r = model.dragReadout {
            Text(r).font(.system(size: 15, weight: .bold, design: .rounded)).monospacedDigit()
                .padding(.horizontal, 16).padding(.vertical, 8)
                .glass(Capsule())
                .transition(.scale(scale: 0.8).combined(with: .opacity))
        } else {
            hint
        }
    }

    // MARK: landscape — modes on the left, the model in the middle, tools in a sidebar on the right

    private func landscapeLayout(width: CGFloat) -> some View {
        VStack(spacing: 8) {
            topBar
            HStack(alignment: .top, spacing: 10) {
                modeRail
                VStack { statusLine; Spacer(minLength: 0) }.frame(maxWidth: .infinity)
                VStack(spacing: 8) {
                    if let op = model.lastOp { lastOpPanel(op).id(op.title) }
                    toolsContent
                        .environment(\.verticalTools, true)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .glass(RoundedRectangle(cornerRadius: 26, style: .continuous))
                }
                .frame(width: min(420, width * 0.42))
            }
        }
        .padding(.horizontal, 10).padding(.top, 2).padding(.bottom, 6)
    }

    private var modeRail: some View {
        VStack(spacing: 4) {
            ForEach(StudioMode.allCases) { m in
                let on = model.mode == m
                Button { withAnimation(Theme.snappy) { model.mode = m }; Haptics.select() } label: {
                    VStack(spacing: 2) {
                        Image(systemName: m.icon).font(.system(size: 16, weight: .semibold))
                        Text(m.title).font(.system(size: 9, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .frame(width: 60, height: 50)
                    .foregroundStyle(on ? Color.white : Color.primary)
                    .background { if on { RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.accentColor.gradient).matchedGeometryEffect(id: "mode", in: modeNS) } }
                    .contentShape(RoundedRectangle(cornerRadius: 18))
                }
                .buttonStyle(.pressable(0.92))
            }
        }
        .padding(5)
        .glass(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var modeSwitcher: some View {
        HStack(spacing: 4) {
            ForEach(StudioMode.allCases) { m in
                let on = model.mode == m
                Button { withAnimation(Theme.snappy) { model.mode = m }; Haptics.select() } label: {
                    VStack(spacing: 2) {
                        Image(systemName: m.icon).font(.system(size: 16, weight: .semibold))
                        Text(m.title).font(.caption2.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity).frame(height: 50)
                    .foregroundStyle(on ? Color.white : Color.primary)
                    .background { if on { Capsule().fill(Color.accentColor.gradient).matchedGeometryEffect(id: "mode", in: modeNS) } }
                    .contentShape(Capsule())
                }
                .buttonStyle(.pressable(0.92))
            }
        }
        .padding(5)
        .glass(Capsule())
    }

    private func chips<T: Hashable & Identifiable & RawRepresentable>(_ all: [T], _ sel: Binding<T>) -> some View where T.RawValue == String {
        ChipsContainer {
                ForEach(all) { c in
                    let on = sel.wrappedValue == c
                    Button { withAnimation(Theme.snappy) { sel.wrappedValue = c }; Haptics.select() } label: {
                        Text(c.rawValue).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.75).padding(.horizontal, 12).frame(maxWidth: verticalTools ? .infinity : nil).frame(height: 30)
                            .foregroundStyle(on ? Color.white : Color.primary)
                            .background {
                                if on { Capsule().fill(Color.accentColor.gradient).matchedGeometryEffect(id: "chip", in: chipNS) }
                                else { Capsule().fill(Color.primary.opacity(0.07)) }
                            }
                    }
                    .buttonStyle(.pressable(0.93))
                }
        }
    }

    // MARK: object tools

    private var objectTools: some View {
        VStack(spacing: 8) {
            if verticalTools {
                addButton.frame(maxWidth: .infinity)
                chips(ObjectCategory.allCases, $objectCategory)
            } else {
                HStack(spacing: 8) {
                    addButton
                    chips(ObjectCategory.allCases, $objectCategory)
                }
            }
            ToolStrip {
                switch objectCategory {
                case .transform:
                    ForEach(GizmoKind.allCases) { k in
                        ToolButton(icon: k.icon, title: k.rawValue, on: model.gizmoKind == k) { model.gizmoKind = k }
                    }
                    ToolButton(icon: "checkmark.circle", title: "Multi", on: model.multiSelect) { model.multiSelect.toggle() }
                    ToolButton(icon: "square.on.square.dashed", title: "Parts", on: model.selectParts) {
                        model.selectParts.toggle()
                        model.showToast(model.selectParts ? "Tap picks single parts" : "Tap picks the whole model")
                    }
                    ToolButton(icon: "checkmark.square", title: "Select All") { model.selectAll() }
                    ToolButton(icon: "ruler", title: "Snap", on: model.snapping) { model.snapping.toggle() }
                    ToolButton(icon: "slider.horizontal.3", title: "Numbers", enabled: !model.selection.isEmpty) { openProperties(.object) }
                    ToolButton(icon: "arrow.down.to.line", title: "To Floor", enabled: !model.selection.isEmpty) { model.dropToFloor() }
                    Menu {
                        Button("Clear Location") { model.resetTransform(rotation: false, scale: false, location: true) }
                        Button("Clear Rotation") { model.resetTransform(rotation: true, scale: false, location: false) }
                        Button("Clear Scale") { model.resetTransform(rotation: false, scale: true, location: false) }
                        Button("Clear All") { model.resetTransform(rotation: true, scale: true, location: true) }
                    } label: { ToolLabel(icon: "arrow.counterclockwise", title: "Clear") }
                    .disabled(model.selection.isEmpty)
                    ToolButton(icon: "checkmark.seal", title: "Apply", enabled: model.primary?.mesh != nil) { model.applyTransform() }
                    ToolButton(icon: "scope", title: "Focus") { model.focusSelection() }
                case .object:
                    ToolButton(icon: "plus.square.on.square", title: "Duplicate", enabled: !model.selection.isEmpty) { model.duplicateSelection() }
                    ToolButton(icon: "trash", title: "Delete", enabled: !model.selection.isEmpty, destructive: true) { model.deleteSelection() }
                    ToolButton(icon: "link", title: "Join", enabled: model.selection.count > 1) { model.joinSelection() }
                    ToolButton(icon: "square.split.2x2", title: "Split Parts", enabled: model.primary?.mesh != nil) { model.separateLooseParts() }
                    Menu {
                        Button("Origin to Geometry") { model.setOrigin(.geometry) }
                        Button("Origin to Base") { model.setOrigin(.base) }
                        Button("Geometry to Origin") { model.setOrigin(.geometryToOrigin) }
                    } label: { ToolLabel(icon: "smallcircle.filled.circle", title: "Origin") }
                    .disabled(model.primary?.mesh == nil)
                    ToolButton(icon: "circle.fill", title: "Smooth", enabled: model.primary?.mesh != nil) { model.shadeSmooth(true) }
                    ToolButton(icon: "hexagon", title: "Flat", enabled: model.primary?.mesh != nil) { model.shadeSmooth(false) }
                    ToolButton(icon: "paintpalette", title: "Material", enabled: model.primary?.mesh != nil) { openProperties(.material) }
                    if model.primary?.isImported == true {
                        ToolButton(icon: "wand.and.stars", title: "Make Editable") { if let p = model.primary { model.convertToEditable(p) } }
                    }
                    ToolButton(icon: "list.bullet.indent", title: "Outliner") { showOutliner = true }
                case .modify:
                    ToolButton(icon: "wrench.and.screwdriver", title: "Modifiers", enabled: model.primary?.mesh != nil) { openProperties(.modifiers) }
                    Menu {
                        ForEach(ModifierKind.allCases) { k in Button(k.title, systemImage: k.icon) { model.addModifier(k) } }
                    } label: { ToolLabel(icon: "plus.rectangle.on.rectangle", title: "Add Modifier") }
                    .disabled(model.primary?.mesh == nil)
                    booleanMenu
                    ToolButton(icon: "cube.transparent", title: "Remesh", enabled: model.primary?.mesh != nil) { model.remeshPrimary() }
                    ToolButton(icon: "checkmark.rectangle.stack", title: "Apply Mods", enabled: !(model.primary?.modifiers.isEmpty ?? true)) { model.applyAllModifiers() }
                }
            }
        }
    }

    private var addButton: some View {
        Button { showAdd = true } label: {
            Label("Add", systemImage: "plus").font(.footnote.weight(.bold)).foregroundStyle(.white)
                .padding(.horizontal, 14).frame(maxWidth: verticalTools ? .infinity : nil).frame(height: 32).background(Color.accentColor.gradient, in: Capsule())
        }
        .buttonStyle(.pressable)
    }

    @ViewBuilder private var booleanMenu: some View {
        let sel = model.selectedObjects.filter { $0.mesh != nil }
        Menu {
            if sel.count == 2 {
                let a = sel[0], b = sel[1]
                Button("Union", systemImage: BooleanOp.union.icon) { model.boolean(.union, target: a, cutter: b) }
                Button("\(a.name) minus \(b.name)", systemImage: BooleanOp.difference.icon) { model.boolean(.difference, target: a, cutter: b) }
                Button("\(b.name) minus \(a.name)", systemImage: BooleanOp.difference.icon) { model.boolean(.difference, target: b, cutter: a) }
                Button("Intersect", systemImage: BooleanOp.intersect.icon) { model.boolean(.intersect, target: a, cutter: b) }
            } else {
                Text("Turn on Multi and select exactly two shapes")
            }
        } label: { ToolLabel(icon: "square.on.square.intersection.dashed", title: "Boolean") }
    }

    // MARK: edit tools

    private var editTools: some View {
        VStack(spacing: 8) {
            if verticalTools {
                Picker("Select", selection: $model.selectMode) {
                    ForEach(SelectMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                HStack(spacing: 8) {
                    GizmoPicker(model: model, compact: true)
                    Spacer(minLength: 0)
                    SmallToggle(icon: "circle.dotted.circle", title: "Soft", on: model.proportional) { model.proportional.toggle() }.accessibilityLabel("Proportional editing")
                    SmallToggle(icon: "checkmark.circle", on: model.multiSelect) { model.multiSelect.toggle() }.accessibilityLabel("Multi-select")
                }
            } else {
                HStack(spacing: 8) {
                    Picker("Select", selection: $model.selectMode) {
                        ForEach(SelectMode.allCases) { Image(systemName: $0.icon).tag($0).accessibilityLabel($0.rawValue) }
                    }
                    .pickerStyle(.segmented).frame(maxWidth: 124)
                    GizmoPicker(model: model, compact: true)
                    Spacer(minLength: 0)
                    SmallToggle(icon: "circle.dotted.circle", on: model.proportional) { model.proportional.toggle() }.accessibilityLabel("Proportional editing")
                    SmallToggle(icon: "checkmark.circle", on: model.multiSelect) { model.multiSelect.toggle() }.accessibilityLabel("Multi-select")
                }
            }
            if model.proportional {
                LabeledSlider(icon: "circle.dotted.circle", value: $model.proportionalRadius, range: 0.05...2)
            }
            chips(EditCategory.allCases, $editCategory)
            ToolStrip {
                switch editCategory {
                case .select:
                    ToolButton(icon: "checkmark.square", title: "All") { model.selectAll() }
                    ToolButton(icon: "square", title: "None") { model.selectNone() }
                    ToolButton(icon: "arrow.left.arrow.right.square", title: "Invert") { model.invertSelection() }
                    ToolButton(icon: "link", title: "Linked") { run { model.selectLinked() } }
                    ToolButton(icon: "plus.circle", title: "Grow") { run { model.growSelection(true) } }
                    ToolButton(icon: "minus.circle", title: "Shrink") { run { model.growSelection(false) } }
                    ToolButton(icon: "point.topleft.down.to.point.bottomright.curvepath", title: "Edge Loop") { run { model.selectEdgeLoop() } }
                    ToolButton(icon: "circle.circle", title: "Edge Ring") { run { model.selectEdgeLoop(ring: true) } }
                case .mesh:
                    Group {
                    ToolButton(icon: "plus.square.on.square", title: "Duplicate") { run { model.duplicateEditSelection() } }
                    ToolButton(icon: "rectangle.split.2x1", title: "Separate") { run { model.separateSelection() } }
                    ToolButton(icon: "trash", title: "Delete", destructive: true) { run { model.deleteEditSelection() } }
                    ToolButton(icon: "arrow.triangle.merge", title: "Merge") { run { model.mergeSelection() } }
                    Menu {
                        Button("Smooth (Catmull–Clark)", systemImage: "circle.grid.cross") { run { model.subdivide(smooth: true) } }
                        Button("Simple", systemImage: "square.grid.2x2") { run { model.subdivide(smooth: false) } }
                    } label: { ToolLabel(icon: "square.grid.3x3", title: "Subdivide") }
                    ToolButton(icon: "drop", title: "Smooth") { run { model.smoothSelection() } }
                    Menu {
                        Button("Mirror X") { run { model.mirror(axis: 0) } }
                        Button("Mirror Y") { run { model.mirror(axis: 1) } }
                        Button("Mirror Z") { run { model.mirror(axis: 2) } }
                    } label: { ToolLabel(icon: "arrow.left.and.right.righttriangle.left.righttriangle.right", title: "Mirror") }
                    }
                    Group {
                    ToolButton(icon: "arrow.up.left.and.arrow.down.right", title: "Fatten") { run { model.shrinkFatten() } }
                    ToolButton(icon: "circle", title: "To Sphere") { run { model.toSphere() } }
                    ToolButton(icon: "dice", title: "Randomize") { run { model.randomize() } }
                    ToolButton(icon: "triangle", title: "Triangulate") { run { model.triangulate() } }
                    ToolButton(icon: "square", title: "Tris → Quads") { run { model.trisToQuads() } }
                    }
                case .faces:
                    ToolButton(icon: "square.stack.3d.up.fill", title: "Extrude", tint: .accentColor) { run { model.extrude() } }
                    ToolButton(icon: "square.inset.filled", title: "Inset") { run { model.inset() } }
                    ToolButton(icon: "square.on.square.squareshape.controlhandles", title: "Bevel") { run { model.bevel() } }
                    ToolButton(icon: "asterisk", title: "Poke") { run { model.poke() } }
                    ToolButton(icon: "square.dashed", title: "Make Face") { run { model.makeFace() } }
                    ToolButton(icon: "square.dashed.inset.filled", title: "Dissolve") { run { model.dissolve() } }
                case .edges:
                    ToolButton(icon: "scissors", title: "Loop Cut", tint: .accentColor) { run { model.loopCut() } }
                    ToolButton(icon: "point.topleft.down.to.point.bottomright.curvepath", title: "Select Loop") { run { model.selectEdgeLoop() } }
                    ToolButton(icon: "circle.circle", title: "Select Ring") { run { model.selectEdgeLoop(ring: true) } }
                    ToolButton(icon: "line.diagonal", title: "Dissolve") { if model.selectMode != .edge { model.selectMode = .edge }; model.dissolve() }
                    ToolButton(icon: "arrow.triangle.merge", title: "Merge") { run { model.mergeSelection() } }
                case .normals:
                    ToolButton(icon: "arrow.uturn.up.square", title: "Flip") { run { model.flipNormals() } }
                    ToolButton(icon: "arrow.up.and.down.square", title: "Recalculate") { run { model.recalculateNormals() } }
                    ToolButton(icon: model.primary?.mesh?.smooth == true ? "circle.fill" : "hexagon", title: model.primary?.mesh?.smooth == true ? "Smooth Shade" : "Flat Shade") { run { model.toggleSmoothShading() } }
                    ForEach(UVProjection.allCases) { p in
                        ToolButton(icon: p.icon, title: "UV \(p.rawValue)") { run { model.projectUVs(p) } }
                    }
                }
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
                Menu {
                    Button("Add Detail (Subdivide)", systemImage: "plus.magnifyingglass") { model.addDetail() }
                    Section("Voxel Remesh") {
                        ForEach([32, 48, 64, 96, 128, 160], id: \.self) { r in
                            Button("Resolution \(r)") { model.remeshResolution = Double(r); model.remeshPrimary() }
                        }
                    }
                } label: {
                    Label("Detail", systemImage: "cube.transparent").font(.footnote.weight(.semibold))
                        .padding(.horizontal, 12).frame(height: 34).background(Color.primary.opacity(0.08), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: paint tools

    private var paintTools: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                ColorPicker("", selection: $model.paintColor, supportsOpacity: false).labelsHidden().frame(width: 36)
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(Array(Self.swatches.enumerated()), id: \.offset) { _, c in
                            Circle().fill(c).frame(width: 28, height: 28)
                                .overlay(Circle().stroke(Color.primary.opacity(0.25), lineWidth: 1))
                                .onTapGesture { model.paintColor = c; Haptics.select() }
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
            HStack(spacing: 14) {
                LabeledSlider(icon: "circle.dashed", value: $model.brushRadius, range: 0.02...0.6)
                LabeledSlider(icon: "drop.fill", value: $model.brushStrength, range: 0.05...1)
            }
            HStack(spacing: 8) {
                SmallToggle(icon: "aqi.medium", title: "Blur", on: model.paintBlur) { model.paintBlur.toggle() }
                SmallToggle(icon: "arrow.left.and.right", title: "Mirror X", on: model.symmetryX) { model.symmetryX.toggle() }
                Spacer(minLength: 0)
                Menu {
                    Button("Fill with Colour", systemImage: "paintbrush.fill") { model.fillPaint() }
                    Button("Gradient", systemImage: "square.fill.and.line.vertical.and.square") { model.gradientPaint() }
                    Button("Clear Paint", systemImage: "eraser", role: .destructive) { model.clearPaint() }
                    Button("Add Detail", systemImage: "plus.magnifyingglass") { model.addDetail() }
                } label: {
                    Label("Fill", systemImage: "paintbrush.fill").font(.footnote.weight(.semibold))
                        .padding(.horizontal, 12).frame(height: 34).background(Color.primary.opacity(0.08), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    static let swatches: [Color] = [.white, .black, Color(white: 0.5), .red, .orange, .yellow, .green, .mint, .teal, .cyan, .blue, .indigo, .purple, .pink, .brown,
                                    Color(red: 0.96, green: 0.8, blue: 0.69), Color(red: 0.55, green: 0.36, blue: 0.24)]

    // MARK: pose / animate tools

    private var poseTools: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Button { showBones = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "figure.stand").font(.footnote.weight(.semibold))
                        Text(model.selectedBone?.name ?? "Choose Part").font(.footnote.weight(.semibold)).lineLimit(1)
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
                    Button("Reset Selected", systemImage: "arrow.counterclockwise") { model.resetBone() }.disabled(model.selectedBone == nil)
                    Button("Reset All", systemImage: "figure.stand") { model.resetPose() }
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
                    ForEach([1.0, 2.0, 3.0, 5.0, 10.0, 20.0], id: \.self) { d in Button("\(Int(d)) seconds") { model.poseDuration = d; if model.poseTime > d { model.poseTime = d } } }
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

private struct VerticalToolsKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    /// True in the landscape sidebar: tool strips become grids.
    var verticalTools: Bool {
        get { self[VerticalToolsKey.self] }
        set { self[VerticalToolsKey.self] = newValue }
    }
}

struct ToolStrip<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @Environment(\.verticalTools) private var vertical
    var body: some View {
        if vertical {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 74), spacing: 6)], spacing: 6) { content() }
                    .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
        } else {
            strip
        }
    }
    private var strip: some View {
        ScrollView(.horizontal) { HStack(spacing: 6) { content() }.padding(.horizontal, 2) }
            .scrollIndicators(.hidden)
    }
}

struct ToolLabel: View {
    @Environment(\.verticalTools) private var vertical
    let icon: String, title: String
    var tint: Color? = nil
    var on = false
    var destructive = false
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 18, weight: .semibold)).frame(height: 24)
                .foregroundStyle(on ? Color.white : destructive ? Color.red : (tint ?? Color.primary))
            if vertical {
                Text(title).font(.caption2.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.65).foregroundStyle(on ? Color.white : Color.primary)
            } else {
                Text(title).font(.caption2.weight(.semibold)).lineLimit(1).fixedSize().foregroundStyle(on ? Color.white : Color.primary)
            }
        }
        .padding(.horizontal, vertical ? 4 : 8)
        .frame(minWidth: 58, maxWidth: vertical ? .infinity : nil).frame(height: 58)
        .background {
            if on { RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.accentColor.gradient) }
            else { RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.primary.opacity(0.045)) }
        }
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
            .buttonStyle(.pressable(0.9)).disabled(!enabled).opacity(enabled ? 1 : 0.35)
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
            .background(on ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(Color.primary.opacity(0.08)), in: Capsule())
            .fixedSize()
        }
        .buttonStyle(.pressable(0.92))
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
                        Image(systemName: k.icon).font(.footnote.weight(.semibold)).frame(width: 34, height: 32)
                            .foregroundStyle(on ? Color.white : Color.primary)
                            .background { if on { Capsule().fill(Color.accentColor.gradient) } }
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

/// Category chips: a sideways scroller in portrait, a tidy grid in the landscape sidebar.
struct ChipsContainer<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @Environment(\.verticalTools) private var vertical
    var body: some View {
        if vertical {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 6)], spacing: 6) { content() }
        } else {
            ScrollView(.horizontal) { HStack(spacing: 6) { content() } }
                .scrollIndicators(.hidden)
        }
    }
}
