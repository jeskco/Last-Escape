import SwiftUI
import PhotosUI
import SceneKit

// (Properties moved to StudioProperties.swift)

struct MaterialSlider: View {
    let title: String
    @Binding var value: Float
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { Text(title); Spacer(); Text("\(Int(value * 100))%").foregroundStyle(.secondary).monospacedDigit() }
            Slider(value: $value, in: 0...1)
        }
    }
}

struct VectorRow: View {
    let title: String
    let value: SIMD3<Float>
    let step: Float
    let onChange: (SIMD3<Float>) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold))
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { i in
                    AxisField(label: ["X", "Y", "Z"][i], color: [.red, .green, .blue][i], value: value[i], step: step) { v in
                        var n = value; n[i] = v; onChange(n)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}

struct AxisField: View {
    let label: String, color: Color
    let value: Float, step: Float
    let onCommit: (Float) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool
    var body: some View {
        HStack(spacing: 4) {
            Text(label).font(.caption.weight(.bold)).foregroundStyle(color)
            TextField("0", text: $text)
                .keyboardType(.numbersAndPunctuation).monospacedDigit().font(.footnote)
                .focused($focused)
                .onSubmit { if let v = Float(text.replacingOccurrences(of: ",", with: ".")) { onCommit(v) } }
                .onAppear { text = String(format: "%.2f", value) }
                .onChange(of: value) { _, v in if !focused { text = String(format: "%.2f", v) } }
        }
        .padding(.horizontal, 8).frame(height: 34)
        .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

// MARK: - Outliner (Blender's outliner: every object, grouped by the model it came from)

struct StudioOutlinerView: View {
    @ObservedObject var model: StudioModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var open: Set<UUID> = []

    private var filtered: [StudioObject] {
        query.isEmpty ? model.objects : model.objects.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        let list = filtered
        let loose = list.filter { $0.groupID == nil }
        var groupOrder: [UUID] = []
        var groups: [UUID: [StudioObject]] = [:]
        for o in list { if let g = o.groupID { if groups[g] == nil { groupOrder.append(g) }; groups[g, default: []].append(o) } }
        return NavigationStack {
            List {
                if model.objects.isEmpty {
                    ContentUnavailableView("Empty Scene", systemImage: "cube.transparent", description: Text("Add a shape to get started."))
                }
                ForEach(groupOrder, id: \.self) { g in
                    let items = groups[g] ?? []
                    Section {
                        DisclosureGroup(isExpanded: Binding(get: { open.contains(g) || !query.isEmpty }, set: { v in if v { open.insert(g) } else { open.remove(g) } })) {
                            ForEach(items) { o in row(o, indent: true) }
                        } label: {
                            groupHeader(g, items)
                        }
                    }
                }
                if !loose.isEmpty {
                    Section(groupOrder.isEmpty ? "" : "Objects") {
                        ForEach(loose) { o in row(o, indent: false) }
                    }
                }
            }
            .searchable(text: $query, prompt: "Search \(model.objects.count) objects")
            .navigationTitle("Outliner").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("Select All", systemImage: "checkmark.square") { model.selection = Set(model.objects.filter { !$0.hidden }.map(\.id)) }
                        Button("Select None", systemImage: "square") { model.selection = [] }
                        Button("Show All", systemImage: "eye") { for o in model.objects where o.hidden { model.setHidden(o, false) } }
                        Toggle(isOn: $model.selectParts) { Label("Tap Selects Parts", systemImage: "square.on.square.dashed") }
                        Toggle(isOn: $model.multiSelect) { Label("Multi-Select", systemImage: "checkmark.circle") }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.fontWeight(.semibold) }
            }
        }
    }

    private func groupHeader(_ g: UUID, _ items: [StudioObject]) -> some View {
        let allSelected = !items.isEmpty && items.allSatisfy { model.selection.contains($0.id) }
        let allHidden = items.allSatisfy(\.hidden)
        return HStack(spacing: 12) {
            Image(systemName: "shippingbox.fill").foregroundStyle(.white).font(.footnote.weight(.semibold))
                .frame(width: 30, height: 30).background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 1) {
                Text(items.first?.groupName ?? "Model").font(.body.weight(.semibold)).lineLimit(1)
                Text("\(items.count) parts").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { model.selectGroup(g); Haptics.select() } label: {
                Image(systemName: allSelected ? "checkmark.circle.fill" : "circle").font(.title3).foregroundStyle(.tint)
            }
            .buttonStyle(.plain).accessibilityLabel("Select whole model")
            Button { for o in items { model.setHidden(o, !allHidden) } } label: {
                Image(systemName: allHidden ? "eye.slash" : "eye.fill").foregroundStyle(allHidden ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.tint))
            }
            .buttonStyle(.plain)
            Menu {
                Button("Select Whole Model", systemImage: "checkmark.circle") { model.selectGroup(g) }
                Button("Join Into One Object", systemImage: "link") { model.joinGroup(g) }
                Button("Ungroup", systemImage: "square.on.square.dashed") { for o in items { o.groupID = nil; o.groupName = nil }; model.touch() }
            } label: { Image(systemName: "ellipsis").frame(width: 28, height: 28) }
        }
    }

    private func row(_ o: StudioObject, indent: Bool) -> some View {
        let on = model.selection.contains(o.id)
        return HStack(spacing: 12) {
            Image(systemName: o.light.map { $0.kind.icon } ?? (o.isImported ? "figure.stand" : "cube.fill"))
                .foregroundStyle(.white).font(.caption.weight(.semibold))
                .frame(width: 26, height: 26)
                .background((o.isLight ? Color.yellow : o.isImported ? Color.orange : Color(red: Double(o.material.r), green: Double(o.material.g), blue: Double(o.material.b))).gradient, in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 1) {
                Text(o.name).font(.subheadline.weight(on ? .semibold : .regular)).lineLimit(1)
                Text(o.light.map { "\($0.kind.rawValue) light" } ?? o.mesh.map { "\(Fmt.count($0.triangleCount)) tris" + (o.modifiers.isEmpty ? "" : " · \(o.modifiers.count) modifiers") } ?? "Imported model")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if on { Image(systemName: "checkmark").foregroundStyle(.tint).font(.footnote.weight(.bold)) }
            Button { model.setHidden(o, !o.hidden) } label: {
                Image(systemName: o.hidden ? "eye.slash" : "eye.fill").foregroundStyle(o.hidden ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.tint))
            }
            .buttonStyle(.plain)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard !o.hidden else { return }
            if model.multiSelect { if on { model.selection.remove(o.id) } else { model.selection.insert(o.id); model.primaryID = o.id } }
            else { model.selection = [o.id]; model.primaryID = o.id }
            Haptics.select()
        }
        .listRowBackground(on ? Color.accentColor.opacity(0.12) : nil)
        .swipeActions {
            Button(role: .destructive) { model.selection = [o.id]; model.deleteSelection() } label: { Label("Delete", systemImage: "trash") }
        }
    }
}

// MARK: - Export

struct StudioExportView: View {
    @ObservedObject var model: StudioModel
    @Environment(\.dismiss) private var dismiss
    @State private var format: ExportFormat = .usdz
    @State private var working = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(ExportFormat.allCases) { f in
                        Button { format = f; Haptics.select() } label: {
                            HStack(spacing: 12) {
                                Text(f.rawValue).font(.system(.subheadline, design: .rounded).weight(.bold)).frame(width: 54, height: 34)
                                    .foregroundStyle(format == f ? Color.white : Color.primary)
                                    .background(format == f ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color(uiColor: .tertiarySystemFill)), in: RoundedRectangle(cornerRadius: 9))
                                Text(f.detail).foregroundStyle(.primary)
                                Spacer()
                                if format == f { Image(systemName: "checkmark").foregroundStyle(.tint).fontWeight(.semibold) }
                            }
                        }
                    }
                } header: { Text("Format") } footer: {
                    Text(format == .glb ? "GLB includes meshes, colours and textures. Rigs and animations export with USDZ." :
                         format == .usdz ? "USDZ keeps rigs and saved animations and opens straight into AR." : "Exports every visible object.")
                }
                if let error { Section { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) } }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    working = true; error = nil
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 60_000_000)
                        let (url, err) = model.export(format)
                        working = false
                        if let url { dismiss(); try? await Task.sleep(nanoseconds: 450_000_000); SharePresenter.share(url) } else { error = err }
                    }
                } label: {
                    HStack { if working { ProgressView().tint(.white) }; Text(working ? "Exporting…" : "Export \(format.rawValue)") }
                        .font(.headline).frame(maxWidth: .infinity).frame(height: 50)
                }
                .buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
                .padding(.horizontal, 20).padding(.bottom, 8).disabled(working)
            }
            .navigationTitle("Export").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Cancel") { dismiss() } } }
        }
    }
}

// MARK: - Bone picker

struct BonePickerView: View {
    @ObservedObject var model: StudioModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    var body: some View {
        NavigationStack {
            List {
                ForEach(model.bones.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }) { b in
                    Button { model.selectBone(b); dismiss() } label: {
                        HStack(spacing: 8) {
                            if query.isEmpty { Color.clear.frame(width: CGFloat(min(b.depth, 10)) * 12, height: 1) }
                            Image(systemName: "circle.fill").font(.system(size: 7)).foregroundStyle(model.selectedBone == b ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                            Text(b.name).foregroundStyle(.primary)
                            Spacer()
                            if model.selectedBone == b { Image(systemName: "checkmark").foregroundStyle(.tint) }
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "Search \(model.bones.count) bones")
            .navigationTitle("Bones").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.fontWeight(.semibold) } }
        }
    }
}
