import SwiftUI
import SceneKit

/// Scene outliner: smart part groups with visibility, materials, and texture-channel controls.
struct SceneTab: View {
    @ObservedObject var model: ViewerModel
    @State private var section = 0
    var body: some View {
        VStack(spacing: 16) {
            Picker("Section", selection: $section) {
                Text("Parts").tag(0); Text("Materials").tag(1); Text("Textures").tag(2)
            }
            .pickerStyle(.segmented)
            switch section {
            case 0: PartsSection(model: model)
            case 1: MaterialsSection(model: model)
            default: TexturesSection(model: model)
            }
        }
    }
}

// MARK: - Parts

private struct EyeButton: View {
    /// 0 hidden, 1 partly visible, 2 visible
    let state: Int
    let action: () -> Void
    var body: some View {
        Button { action(); Haptics.select() } label: {
            Image(systemName: state == 2 ? "eye.fill" : state == 1 ? "eye.trianglebadge.exclamationmark" : "eye.slash")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(state == 0 ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.tint))
                .frame(width: 40, height: 36).contentShape(Rectangle())
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(state == 0 ? "Show" : "Hide")
    }
}

private struct PartsSection: View {
    @ObservedObject var model: ViewerModel
    @State private var expanded: Set<String> = []
    @State private var query = ""

    var body: some View {
        let groups = model.partGroups
        VStack(spacing: 12) {
            if model.parts.isEmpty {
                Empty(icon: "cube.transparent", title: "No parts", text: "This model has no meshes to list.")
            } else {
                HStack(spacing: 8) {
                    Picker("Group by", selection: $model.groupMode) { ForEach(PartGrouping.allCases) { Text($0.rawValue).tag($0) } }
                        .pickerStyle(.menu).labelsHidden()
                        .padding(.horizontal, 6).frame(height: 34)
                        .background(Color.primary.opacity(0.07), in: Capsule())
                    Spacer()
                    Button { withAnimation { model.showAllParts() }; Haptics.tap() } label: { Label("Show All", systemImage: "eye").font(.footnote.weight(.semibold)) }
                        .buttonStyle(.plain).padding(.horizontal, 12).frame(height: 34).background(Color.primary.opacity(0.07), in: Capsule())
                        .disabled(model.hiddenParts.isEmpty)
                    Button { withAnimation { model.hideAllParts() }; Haptics.tap() } label: { Image(systemName: "eye.slash").font(.footnote.weight(.semibold)) }
                        .buttonStyle(.plain).frame(width: 40, height: 34).background(Color.primary.opacity(0.07), in: Capsule())
                        .accessibilityLabel("Hide all")
                }

                Text("\(model.parts.count) parts in \(groups.count) \(groups.count == 1 ? "group" : "groups") · \(model.parts.count - model.hiddenParts.count) visible")
                    .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4)

                VStack(spacing: 0) {
                    ForEach(Array(groups.enumerated()), id: \.element.id) { i, g in
                        groupRow(g)
                        if expanded.contains(g.id) {
                            ForEach(g.parts) { p in partRow(p) }
                        }
                        if i < groups.count - 1 { Divider().padding(.leading, 60) }
                    }
                }
                .background(Color(uiColor: .secondarySystemBackground).opacity(0.62), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

                Text("Tap a group to see its parts. Hold a group or part for Show Only and Focus.")
                    .font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 6)
            }
        }
    }

    private func groupState(_ g: PartGroup) -> Int {
        let visible = g.parts.filter { model.isVisible($0) }.count
        return visible == 0 ? 0 : visible == g.parts.count ? 2 : 1
    }

    private func groupRow(_ g: PartGroup) -> some View {
        let state = groupState(g)
        return HStack(spacing: 12) {
            Image(systemName: g.icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 32, height: 32).background(g.color.gradient, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .opacity(state == 0 ? 0.45 : 1)
            VStack(alignment: .leading, spacing: 1) {
                Text(g.name).font(.body.weight(.semibold)).lineLimit(1)
                Text("\(g.parts.count) \(g.parts.count == 1 ? "part" : "parts") · \(Fmt.count(g.triangles)) tris").font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer(minLength: 6)
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
                .rotationEffect(.degrees(expanded.contains(g.id) ? 90 : 0))
            EyeButton(state: state) { withAnimation(.snappy) { model.setVisible(g, state != 2) } }
        }
        .padding(.leading, 14).padding(.trailing, 6).frame(minHeight: 58)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.snappy) { if expanded.contains(g.id) { expanded.remove(g.id) } else { expanded.insert(g.id) } } }
        .contextMenu {
            Button("Show Only \(g.name)", systemImage: "eye.circle") { withAnimation { model.solo(g) } }
            Button("Focus Camera", systemImage: "scope") { model.focus(g.parts) }
            Button(state == 2 ? "Hide Group" : "Show Group", systemImage: state == 2 ? "eye.slash" : "eye") { model.setVisible(g, state != 2) }
        }
    }

    private func partRow(_ p: PartInfo) -> some View {
        let visible = model.isVisible(p)
        return HStack(spacing: 10) {
            Color.clear.frame(width: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(p.name).font(.subheadline).lineLimit(1).foregroundStyle(visible ? .primary : .secondary)
                Text("\(p.materialName) · \(Fmt.count(p.triangles)) tris").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 6)
            Button { model.focus([p]); Haptics.tap() } label: { Image(systemName: "scope").font(.footnote.weight(.semibold)).frame(width: 34, height: 34) }
                .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Focus \(p.name)")
            EyeButton(state: visible ? 2 : 0) { withAnimation(.snappy) { model.setVisible(p, !visible) } }
        }
        .padding(.leading, 14).padding(.trailing, 6).frame(minHeight: 46)
        .background(Color.primary.opacity(0.03))
        .contextMenu {
            Button("Show Only This Part", systemImage: "eye.circle") { withAnimation { model.solo(p) } }
            Button("Focus Camera", systemImage: "scope") { model.focus([p]) }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

// MARK: - Materials

private struct MaterialsSection: View {
    @ObservedObject var model: ViewerModel
    @State private var expanded: Set<UUID> = []

    var body: some View {
        if model.materials.isEmpty {
            Empty(icon: "paintpalette", title: "No materials", text: "This model has no materials to show.")
        } else {
            VStack(spacing: 0) {
                ForEach(Array(model.materials.enumerated()), id: \.element.id) { i, m in
                    let visible = model.isVisible(m)
                    VStack(spacing: 0) {
                        HStack(spacing: 12) {
                            Group {
                                if let t = m.thumbnail { Image(uiImage: t).resizable().scaledToFill() } else { Color(uiColor: m.color) }
                            }
                            .frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(.white.opacity(0.25), lineWidth: 0.5))
                            .opacity(visible ? 1 : 0.4)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(m.name).font(.body.weight(.medium)).lineLimit(1)
                                Text(m.textures.isEmpty ? "\(m.model) · no textures" : "\(m.textures.count) \(m.textures.count == 1 ? "texture" : "textures") · \(m.model)")
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 6)
                            if !m.textures.isEmpty {
                                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
                                    .rotationEffect(.degrees(expanded.contains(m.id) ? 90 : 0))
                            }
                            EyeButton(state: visible ? 2 : 0) { withAnimation(.snappy) { model.setVisible(m, !visible) } }
                        }
                        .padding(.leading, 14).padding(.trailing, 6).padding(.vertical, 8)
                        .contentShape(Rectangle())
                        .onTapGesture { withAnimation(.snappy) { if expanded.contains(m.id) { expanded.remove(m.id) } else if !m.textures.isEmpty { expanded.insert(m.id) } } }

                        if expanded.contains(m.id), let mat = m.material {
                            ScrollView(.horizontal) {
                                HStack(spacing: 10) {
                                    ForEach(TextureChannel.allCases) { c in
                                        if let img = ViewerModel.thumbnail(c.property(mat).contents), let size = ViewerModel.imageSize(c.property(mat).contents) {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Image(uiImage: img).resizable().scaledToFill().frame(width: 96, height: 96)
                                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                                Text(c.rawValue).font(.caption2.weight(.semibold)).lineLimit(1)
                                                Text("\(size.0)×\(size.1)").font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                                            }
                                            .frame(width: 96)
                                        }
                                    }
                                }
                                .padding(.horizontal, 14).padding(.bottom, 12)
                            }
                            .scrollIndicators(.hidden)
                            .transition(.opacity)
                        }
                    }
                    if i < model.materials.count - 1 { Divider().padding(.leading, 70) }
                }
            }
            .background(Color(uiColor: .secondarySystemBackground).opacity(0.62), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }
}

// MARK: - Textures

private struct TexturesSection: View {
    @ObservedObject var model: ViewerModel
    var body: some View {
        VStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("View Channel").font(.headline).padding(.horizontal, 6)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 74), spacing: 8)], spacing: 8) {
                    ForEach(ChannelView.allCases) { v in
                        let on = model.channelView == v
                        Button { withAnimation(.snappy) { model.channelView = v }; Haptics.select() } label: {
                            Text(v.rawValue).font(.footnote.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                                .frame(maxWidth: .infinity).frame(height: 36)
                                .foregroundStyle(on ? Color.white : Color.primary)
                                .background(on ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.primary.opacity(0.07)), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text("Shows one texture map on its own, unlit, so you can check it on the model. UV Grid reveals stretching and seams.")
                    .font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 6)
            }

            Section2(title: "Texture Channels", footer: "Switch a channel off to see the model without it, across every material.") {
                ForEach(Array(TextureChannel.allCases.enumerated()), id: \.element.id) { i, c in
                    let count = model.textureCount(c)
                    Row(label: c.rawValue, showDivider: i < TextureChannel.allCases.count - 1) {
                        Text(count == 0 ? "None" : "\(count) \(count == 1 ? "map" : "maps")").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        Toggle("", isOn: Binding(get: { model.isEnabled(c) }, set: { model.setChannel(c, enabled: $0); Haptics.select() })).labelsHidden()
                    }
                }
            }
            if !model.disabledChannels.isEmpty || model.channelView != .final {
                Button { withAnimation { model.resetChannels(); model.channelView = .final } } label: {
                    Label("Restore All Textures", systemImage: "arrow.counterclockwise").frame(maxWidth: .infinity).frame(height: 30)
                }
                .glassButton()
            }
        }
    }
}
