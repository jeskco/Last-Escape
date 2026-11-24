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

/// Home screen: big actions up top, your projects and recent files, and samples.
struct LibraryView: View {
    @ObservedObject var model: ViewerModel
    @Binding var isPresented: Bool
    @State private var showSettings = false
    @State private var studioSession: StudioSession?
    @State private var projects: [StudioProjectSummary] = []
    @State private var shown = false
    @Environment(\.colorScheme) private var scheme
    @AppStorage("accentIndex") private var accentIndex = 0

    private var accent: Color { Accent.all[min(max(accentIndex, 0), Accent.all.count - 1)].color }

    private func bundled(_ name: String) -> UIImage? {
        Bundle.main.url(forResource: name, withExtension: "jpg").flatMap { UIImage(contentsOfFile: $0.path) }
    }
    private func pick() { DocumentPicker.present { urls in isPresented = false; model.importFiles(urls) } }

    var body: some View {
        ZStack {
            Aurora(accent: accent)
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header.entrance(0, shown: shown)
                    actions.entrance(1, shown: shown)
                    if !projects.isEmpty { projectsRow.entrance(2, shown: shown) }
                    if !model.recents.isEmpty { recents.entrance(3, shown: shown) }
                    samples.entrance(4, shown: shown)
                }
                .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 48)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .fullScreenCover(item: $studioSession, onDismiss: { withAnimation(Theme.spring) { projects = StudioModel.listProjects() } }) { session in
            StudioView(model: session.model, savesAsProject: true) {
                session.model.detach()
                studioSession = nil
            }
            .tint(accent)
        }
        .onAppear {
            projects = StudioModel.listProjects()
            DispatchQueue.main.async { shown = true }
        }
        .sheet(isPresented: $showSettings) { SettingsView(model: model) }
        .tint(accent)
    }

    // MARK: header

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Spacer()
                roundButton("gearshape.fill") { showSettings = true }.accessibilityLabel("Settings")
                roundButton("xmark") { isPresented = false }.accessibilityLabel("Close")
            }
            HStack(alignment: .center, spacing: 16) {
                AppMark(accent: accent, size: 64)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Rig Viewer")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundStyle(LinearGradient(colors: [.primary, .primary.opacity(0.75)], startPoint: .top, endPoint: .bottom))
                        .lineLimit(1).minimumScaleFactor(0.7)
                    HStack(spacing: 6) {
                        tag("View", "eye.fill", .cyan)
                        tag("Animate", "figure.run", .orange)
                        tag("Create", "sparkles", .pink)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func tag(_ title: String, _ icon: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 10, weight: .bold)).foregroundStyle(color)
            Text(title).font(.caption.weight(.bold)).fixedSize()
        }
        .padding(.horizontal, 9).frame(height: 24)
        .background(color.opacity(0.14), in: Capsule())
        .overlay(Capsule().strokeBorder(color.opacity(0.3), lineWidth: 1))
    }

    private func roundButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 15, weight: .bold)).frame(width: 40, height: 40).card(20)
        }
        .buttonStyle(.pressable)
    }

    // MARK: two big actions

    private var actions: some View {
        HStack(spacing: 12) {
            actionTile(title: "Open File", subtitle: "FBX, glTF, USDZ, OBJ…", icon: "folder.fill",
                       colors: [accent, accent.blend(.indigo, 0.55)], action: pick)
            actionTile(title: "New Model", subtitle: "Model, sculpt, paint", icon: "sparkles",
                       colors: [Color.orange, Color.pink], action: { studioSession = StudioSession(model: StudioModel(), fromLibrary: true) })
        }
    }

    private func actionTile(title: String, subtitle: String, icon: String, colors: [Color], action: @escaping () -> Void) -> some View {
        Button(action: { Haptics.tap(); action() }) {
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: icon).font(.system(size: 24, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 46, height: 46).background(.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                Spacer(minLength: 14)
                Text(title).font(.system(size: 19, weight: .heavy, design: .rounded)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.8)
                Text(subtitle).font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.82)).lineLimit(1).minimumScaleFactor(0.75)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
            .background {
                ZStack {
                    LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                    RadialGradient(colors: [.white.opacity(0.35), .clear], center: .topTrailing, startRadius: 0, endRadius: 170)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .shadow(color: (colors.first ?? .clear).opacity(0.35), radius: 16, y: 8)
        }
        .buttonStyle(.pressable(0.96))
    }

    // MARK: projects

    private var projectsRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Your Projects")
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(projects) { p in
                        Button { if let m = StudioModel.open(projectID: p.id) { studioSession = StudioSession(model: m, fromLibrary: true) } } label: {
                            posterCard(image: p.thumbnail, title: p.name,
                                       detail: "\(p.objectCount) \(p.objectCount == 1 ? "object" : "objects") · \(p.date.formatted(.relative(presentation: .named)))")
                        }
                        .buttonStyle(.pressable)
                        .contextMenu {
                            Button("Delete Project", systemImage: "trash", role: .destructive) {
                                StudioModel.deleteProject(p.id)
                                withAnimation(Theme.spring) { projects = StudioModel.listProjects() }
                            }
                        }
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
    }

    /// Image card with the title laid over a soft gradient at the bottom.
    private func posterCard(image: UIImage?, title: String, detail: String, width: CGFloat = 148, height: CGFloat = 178) -> some View {
        FillImage(image: image)
            .frame(width: width, height: height)
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.bold)).foregroundStyle(.white).lineLimit(1)
                    Text(detail).font(.caption2.weight(.medium)).foregroundStyle(.white.opacity(0.8)).lineLimit(1)
                }
                .padding(12)
                .frame(width: width, alignment: .leading)
                .background(LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .top, endPoint: .bottom))
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.stroke(scheme), lineWidth: 1))
            .shadow(color: .black.opacity(0.16), radius: 10, y: 6)
    }

    // MARK: recents — a grid that grows with your history

    @State private var showAllRecents = false

    private var recents: some View {
        let limit = showAllRecents ? model.recents.count : min(model.recents.count, 9)
        return VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Recent", action: ("Clear", { withAnimation(Theme.spring) { model.clearRecents() } }))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)], spacing: 10) {
                ForEach(model.recents.prefix(limit)) { r in
                    Button { isPresented = false; model.openRecent(r) } label: {
                        GeometryReader { g in
                            posterCard(image: r.thumbnail, title: r.name, detail: "\(r.format) · \(r.date.formatted(.relative(presentation: .named)))",
                                       width: g.size.width, height: g.size.width)
                        }
                        .aspectRatio(1, contentMode: .fit)
                    }
                    .buttonStyle(.pressable)
                    .contextMenu { Button("Remove", systemImage: "trash", role: .destructive) { withAnimation(Theme.spring) { model.deleteRecent(r) } } }
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
            }
            if model.recents.count > 9 {
                Button { withAnimation(Theme.spring) { showAllRecents.toggle() } } label: {
                    Label(showAllRecents ? "Show Less" : "Show All \(model.recents.count)", systemImage: showAllRecents ? "chevron.up" : "chevron.down")
                        .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).frame(height: 44).card(22)
                }
                .buttonStyle(.pressable)
            }
        }
    }

    // MARK: samples

    private var samples: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Try a Sample")
            ScrollView(.horizontal) {
                HStack(spacing: 14) {
                    ForEach(Sample.all) { s in
                        Button { isPresented = false; model.openSample(s.id) } label: { sampleCard(s) }
                            .buttonStyle(.pressable)
                            .scrollTransition(.interactive, axis: .horizontal) { v, phase in
                                v.scaleEffect(phase.isIdentity ? 1 : 0.92).opacity(phase.isIdentity ? 1 : 0.7)
                            }
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
    }

    private func sampleCard(_ s: Sample) -> some View {
        FillImage(image: bundled(s.thumb))
            .frame(width: 250, height: 300)
            .overlay(alignment: .topLeading) {
                HStack(spacing: 6) {
                    ForEach(s.badges, id: \.self) { b in
                        Text(b).font(.caption2.weight(.bold)).padding(.horizontal, 9).frame(height: 24).background(.ultraThinMaterial, in: Capsule())
                    }
                }
                .padding(12)
            }
            .overlay(alignment: .bottom) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.title).font(.headline).foregroundStyle(.white).lineLimit(1)
                        Text(s.subtitle).font(.caption).foregroundStyle(.white.opacity(0.8)).lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    Image(systemName: "play.fill").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 34, height: 34).background(Color.accentColor.gradient, in: Circle())
                }
                .padding(14)
                .background(LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom))
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Theme.stroke(scheme), lineWidth: 1))
            .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
    }
}

/// The app's mark: a glowing gradient tile with a wireframe cube and a little spark.
struct AppMark: View {
    let accent: Color
    var size: CGFloat = 64
    @State private var glow = false
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(LinearGradient(colors: [accent, accent.blend(.purple, 0.55), accent.blend(.pink, 0.35)], startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(RadialGradient(colors: [.white.opacity(0.45), .clear], center: .topLeading, startRadius: 0, endRadius: size))
            Image(systemName: "cube.transparent")
                .font(.system(size: size * 0.48, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.2), radius: 3, y: 2)
            Image(systemName: "sparkle")
                .font(.system(size: size * 0.2, weight: .black))
                .foregroundStyle(.white)
                .offset(x: size * 0.27, y: -size * 0.27)
                .scaleEffect(glow ? 1.15 : 0.85)
                .opacity(glow ? 1 : 0.7)
        }
        .frame(width: size, height: size)
        .overlay(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).strokeBorder(.white.opacity(0.25), lineWidth: 1))
        .shadow(color: accent.opacity(0.45), radius: glow ? 18 : 10, y: 6)
        .onAppear { withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { glow = true } }
    }
}
