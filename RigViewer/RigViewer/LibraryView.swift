import SwiftUI

struct Sample: Identifiable {
    let id: String, title: String, subtitle: String, thumb: String, badges: [String]
    static let all: [Sample] = [
        .init(id: "RobotExpressive.glb", title: "Expressive Robot", subtitle: "14 animations · face shapes", thumb: "thumb_RobotExpressive", badges: ["glTF", "Rigged"]),
        .init(id: "mannequin", title: "Mannequin", subtitle: "Built-in rig · walk and wave", thumb: "thumb_mannequin", badges: ["Rigged"]),
        .init(id: "colored.stl", title: "Coloured STL", subtitle: "Mesh with vertex colours", thumb: "thumb_colored", badges: ["STL"]),
    ]
}

/// Fills a fixed frame with an image without ever growing past it (the cause of overlapping tiles).
struct FillImage: View {
    let image: UIImage?
    var body: some View {
        Color(uiColor: .tertiarySystemFill)
            .overlay {
                if let image { Image(uiImage: image).resizable().scaledToFill() }
                else { Image(systemName: "cube.transparent").font(.system(size: 34, weight: .light)).foregroundStyle(.secondary) }
            }
            .clipped()
    }
}

struct LibraryView: View {
    @ObservedObject var model: ViewerModel
    @Binding var isPresented: Bool

    private func bundled(_ name: String) -> UIImage? {
        Bundle.main.url(forResource: name, withExtension: "jpg").flatMap { UIImage(contentsOfFile: $0.path) }
    }
    private func pick() { DocumentPicker.present { urls in isPresented = false; model.importFiles(urls) } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    openCard.padding(.horizontal, 20)
                    if !model.recents.isEmpty { recents }
                    samples
                    formats.padding(.horizontal, 20)
                }
                .padding(.top, 6).padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Rig Viewer")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { isPresented = false } label: { Image(systemName: "xmark").fontWeight(.semibold) }
                        .accessibilityLabel("Close")
                }
            }
        }
    }

    // MARK: open card
    private var openCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Open a model").font(.title2.weight(.bold)).foregroundStyle(.white)
                    Text("Inspect skeletons, animations, blend shapes and materials, then place it in AR.")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.85)).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Image(systemName: "figure.walk.motion").font(.system(size: 40, weight: .semibold)).foregroundStyle(.white.opacity(0.9))
            }
            Button(action: pick) {
                Label("Choose File", systemImage: "folder.fill").font(.headline).frame(maxWidth: .infinity).frame(height: 50)
                    .foregroundStyle(Color.accentColor)
                    .background(.white, in: Capsule())
            }
            .buttonStyle(.plain)
            Text("FBX · glTF · USDZ · OBJ · STL · ZIP and more").font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.8))
                .frame(maxWidth: .infinity)
        }
        .padding(20)
        .background {
            ZStack {
                LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.75), .indigo], startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [.white.opacity(0.28), .clear], center: .topTrailing, startRadius: 0, endRadius: 260)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .shadow(color: Color.accentColor.opacity(0.25), radius: 20, y: 10)
    }

    private func header(_ title: String, trailing: (String, () -> Void)? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title3.weight(.bold))
            Spacer()
            if let trailing { Button(trailing.0, action: trailing.1).font(.subheadline) }
        }
        .padding(.horizontal, 20)
    }

    // MARK: recents
    private var recents: some View {
        VStack(alignment: .leading, spacing: 12) {
            header("Recent", trailing: ("Clear", { withAnimation { model.clearRecents() } }))
            ScrollView(.horizontal) {
                HStack(spacing: 14) {
                    ForEach(model.recents) { r in
                        Button { isPresented = false; model.openRecent(r) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                FillImage(image: r.thumbnail)
                                    .frame(width: 128, height: 128)
                                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                                Text(r.name).font(.footnote.weight(.semibold)).lineLimit(1)
                                Text("\(r.format) · \(r.date.formatted(.relative(presentation: .named)))").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                            .frame(width: 128, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .contextMenu { Button("Remove", systemImage: "trash", role: .destructive) { withAnimation { model.deleteRecent(r) } } }
                    }
                }
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)
        }
    }

    // MARK: samples — a paged carousel of fixed-size cards
    private var samples: some View {
        VStack(alignment: .leading, spacing: 12) {
            header("Samples")
            ScrollView(.horizontal) {
                HStack(spacing: 14) {
                    ForEach(Sample.all) { s in
                        Button { isPresented = false; model.openSample(s.id) } label: { sampleCard(s) }
                            .buttonStyle(.plain)
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, 20)
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
        }
    }

    private func sampleCard(_ s: Sample) -> some View {
        VStack(spacing: 0) {
            FillImage(image: bundled(s.thumb))
                .frame(width: 236, height: 236)
                .overlay(alignment: .topLeading) {
                    HStack(spacing: 6) {
                        ForEach(s.badges, id: \.self) { b in
                            Text(b).font(.caption2.weight(.semibold)).padding(.horizontal, 9).frame(height: 24).background(.ultraThinMaterial, in: Capsule())
                        }
                    }
                    .padding(10)
                }
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.title).font(.headline).lineLimit(1)
                    Text(s.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right.circle.fill").font(.title2).symbolRenderingMode(.hierarchical).foregroundStyle(.tint)
            }
            .padding(.horizontal, 14).frame(width: 236, height: 64)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
        }
        .frame(width: 236, height: 300)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 12, y: 6)
    }

    // MARK: formats
    private var formats: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Supported Formats").font(.title3.weight(.bold))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(["FBX", "GLB", "glTF", "USDZ", "USD", "OBJ", "STL", "PLY", "DAE", "ABC", "SCN", "ZIP"], id: \.self) { f in
                    Text(f).font(.footnote.weight(.semibold)).frame(maxWidth: .infinity).frame(height: 34)
                        .background(Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
                }
            }
            Text("For models with separate texture files, open the ZIP they came in, or select the model and its textures together.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}
