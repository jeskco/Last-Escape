import SwiftUI

struct Sample: Identifiable {
    let id: String, title: String, subtitle: String, thumb: String, badges: [String]
    static let all: [Sample] = [
        .init(id: "mannequin", title: "Mannequin", subtitle: "Built-in rig · 2 animations", thumb: "thumb_mannequin", badges: ["Rigged", "Animated"]),
        .init(id: "RobotExpressive.glb", title: "Expressive Robot", subtitle: "glTF · 14 animations · face shapes", thumb: "thumb_RobotExpressive", badges: ["Rigged", "Blend shapes"]),
        .init(id: "colored.stl", title: "Coloured STL", subtitle: "STL · vertex colours", thumb: "thumb_colored", badges: ["Mesh"]),
    ]
}

struct LibraryView: View {
    @ObservedObject var model: ViewerModel
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    hero
                    if !model.recents.isEmpty { recents }
                    samples
                    formats
                    about
                }
                .padding(.horizontal, 20).padding(.bottom, 40)
            }
            .background(Backdrop(accent: .accentColor).ignoresSafeArea())
            .navigationTitle("Rig Viewer")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { isPresented = false }.fontWeight(.semibold) }
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(systemName: "figure.walk.motion").font(.system(size: 30, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 62, height: 62).background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Inspect any rigged model").font(.title3.weight(.semibold))
                    Text("Skeletons, animations, blend shapes, materials and AR — native, on device.").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Button { DocumentPicker.present { urls in isPresented = false; model.importFiles(urls) } } label: {
                Label("Open from Files", systemImage: "folder").font(.headline).frame(maxWidth: .infinity).frame(height: 34)
            }
            .glassButton(prominent: true)
        }
        .padding(18)
        .glass(RoundedRectangle(cornerRadius: 30, style: .continuous))
    }

    private var recents: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Recent").font(.title3.weight(.bold))
                Spacer()
                Button("Clear", role: .destructive) { withAnimation { model.clearRecents() } }.font(.subheadline)
            }
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(model.recents) { r in
                        Button { isPresented = false; model.openRecent(r) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Group {
                                    if let t = r.thumbnail { Image(uiImage: t).resizable().scaledToFill() }
                                    else { Image(systemName: "cube.transparent").font(.largeTitle).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity) }
                                }
                                .frame(width: 140, height: 140).clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                                .background(Color(uiColor: .secondarySystemBackground).opacity(0.6), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                                Text(r.name).font(.subheadline.weight(.medium)).lineLimit(1)
                                Text("\(r.format) · \(r.date.formatted(.relative(presentation: .named)))").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            .frame(width: 140)
                        }
                        .buttonStyle(.plain)
                        .contextMenu { Button("Remove", systemImage: "trash", role: .destructive) { withAnimation { model.deleteRecent(r) } } }
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var samples: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Samples").font(.title3.weight(.bold))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                ForEach(Sample.all) { s in
                    Button { isPresented = false; model.openSample(s.id) } label: {
                        VStack(alignment: .leading, spacing: 0) {
                            Group {
                                if let u = Bundle.main.url(forResource: s.thumb, withExtension: "jpg"), let img = UIImage(contentsOfFile: u.path) {
                                    Image(uiImage: img).resizable().scaledToFill()
                                } else { Color.gray.opacity(0.2) }
                            }
                            .frame(height: 150).frame(maxWidth: .infinity).clipped()
                            .overlay(alignment: .topLeading) {
                                HStack(spacing: 4) {
                                    ForEach(s.badges, id: \.self) { b in
                                        Text(b).font(.caption2.weight(.semibold)).padding(.horizontal, 8).frame(height: 22).background(.ultraThinMaterial, in: Capsule())
                                    }
                                }
                                .padding(8)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.title).font(.headline).lineLimit(1)
                                Text(s.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            .padding(12)
                        }
                        .background(Color(uiColor: .secondarySystemBackground).opacity(0.75))
                        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var formats: some View {
        Section2(title: "Supported Formats", footer: "For FBX files with separate textures, select the FBX and its texture images together in Files.") {
            ForEach(Array(ModelFormats.display.enumerated()), id: \.offset) { i, f in
                Row(f.1, value: f.0, showDivider: i < ModelFormats.display.count - 1)
            }
        }
    }

    private var about: some View {
        Section2(title: "About", footer: "Rig Viewer 2.1 · Native SwiftUI + SceneKit. No web engine.") {
            Row("Expressive Robot", value: "Tomás Laulhé (Quaternius), CC0 · face shapes Don McCurdy")
            Row("HDR environments", value: "Poly Haven, CC0")
            Row("Coloured STL", value: "three.js examples, MIT")
            Row("glTF loader", value: "GLTFKit2 by Warren Moore, MIT")
            Row("FBX loader", value: "ufbx by Samuli Raivio, MIT", showDivider: false)
        }
    }
}
