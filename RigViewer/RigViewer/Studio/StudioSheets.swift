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

// MARK: - Outliner

struct StudioOutlinerView: View {
    @ObservedObject var model: StudioModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                if model.objects.isEmpty {
                    ContentUnavailableView("Empty Scene", systemImage: "cube.transparent", description: Text("Add a shape to get started."))
                }
                ForEach(model.objects) { o in
                    HStack(spacing: 12) {
                        Image(systemName: o.light.map { $0.kind.icon } ?? (o.isImported ? "figure.stand" : "cube.fill"))
                            .foregroundStyle(.white).font(.footnote.weight(.semibold))
                            .frame(width: 30, height: 30)
                            .background((o.isLight ? Color.yellow : o.isImported ? Color.orange : Color(red: Double(o.material.r), green: Double(o.material.g), blue: Double(o.material.b))).gradient, in: RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(o.name).font(.body.weight(model.selection.contains(o.id) ? .semibold : .regular))
                            Text(o.light.map { "\($0.kind.rawValue) light" } ?? o.mesh.map { "\(Fmt.count($0.triangleCount)) tris" + (o.modifiers.isEmpty ? "" : " · \(o.modifiers.count) modifiers") } ?? "Imported model").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { model.setHidden(o, !o.hidden) } label: {
                            Image(systemName: o.hidden ? "eye.slash" : "eye.fill").foregroundStyle(o.hidden ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.tint))
                        }
                        .buttonStyle(.plain)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { if !o.hidden { model.selection = [o.id] } }
                    .listRowBackground(model.selection.contains(o.id) ? Color.accentColor.opacity(0.12) : nil)
                    .swipeActions {
                        Button(role: .destructive) { model.selection = [o.id]; model.deleteSelection() } label: { Label("Delete", systemImage: "trash") }
                    }
                }
            }
            .id(model.revision)
            .navigationTitle("Outliner").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.fontWeight(.semibold) } }
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
