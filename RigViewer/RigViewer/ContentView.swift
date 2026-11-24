import SwiftUI
import SceneKit

enum InspectorTab: String, CaseIterable, Identifiable {
    case info = "Info", scene = "Scene", clips = "Clips", bones = "Bones", look = "Look", view = "View"
    var id: String { rawValue }
}
enum Detent: Int { case peek, medium, large }

struct ContentView: View {
    @StateObject private var model = ViewerModel()
    @ObservedObject private var settings = AppSettings.shared
    @State private var showLibrary = AppSettings.shared.libraryOnLaunch
    @State private var showSettings = false
    @State private var showStudio = false
    @State private var studio: StudioModel?
    @State private var pendingStudio: StudioModel?
    @State private var immersive = false
    @State private var showExit = false
    @State private var tab: InspectorTab = .info
    @State private var detent: Detent = AppSettings.shared.startExpanded ? .medium : .peek
    @State private var drag: CGFloat = 0
    @State private var snapshot: SnapshotItem?
    @AppStorage("accentIndex") private var accentIndex = 0

    private var accent: Color { Accent.all[min(max(accentIndex, 0), Accent.all.count - 1)].color }
    private let headerHeight: CGFloat = 68

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height && geo.size.width > 600
            ZStack {
                Backdrop(accent: accent, style: settings.backgroundStyle).ignoresSafeArea()
                SceneViewer(model: model, onSingleTap: singleTap, onDoubleTap: {
                    guard settings.doubleTapReset else { return }
                    Haptics.tap(); model.frame()
                })
                    .ignoresSafeArea()

                if !immersive {
                    if landscape {
                        HStack(alignment: .top, spacing: 12) {
                            topBar.frame(maxWidth: 520)
                            Spacer(minLength: 0)
                            dock(height: geo.size.height, landscape: true).frame(width: 380)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .transition(.opacity)
                    } else {
                        VStack(spacing: 0) {
                            topBar.padding(.horizontal, 14).padding(.top, 4)
                            Spacer(minLength: 0)
                            dock(height: dockHeight(total: geo.size.height) - drag, landscape: false)
                                .padding(.horizontal, 10).padding(.bottom, 6)
                        }
                        .transition(.opacity)
                    }
                } else if showExit {
                    VStack {
                        Button { withAnimation(.spring(duration: 0.5, bounce: 0.2)) { immersive = false; showExit = false } } label: {
                            Label("Exit Full Screen", systemImage: "arrow.down.right.and.arrow.up.left").font(.subheadline.weight(.semibold)).padding(.horizontal, 18).frame(height: 44)
                        }
                        .buttonStyle(.plain).glass(Capsule(), interactive: true)
                        Spacer()
                    }
                    .padding(.top, 8).transition(.move(edge: .top).combined(with: .opacity))
                }

                if let t = model.toast {
                    VStack {
                        Text(t).font(.subheadline.weight(.medium)).multilineTextAlignment(.center).padding(.horizontal, 20).padding(.vertical, 13)
                            .glass(RoundedRectangle(cornerRadius: 24, style: .continuous))
                            .padding(.horizontal, 24).padding(.top, immersive ? 56 : 66)
                        Spacer()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity)).allowsHitTesting(false)
                }
                if model.isLoading {
                    VStack(spacing: 14) { ProgressView().controlSize(.large); Text(model.loadingText).font(.subheadline).foregroundStyle(.secondary).lineLimit(2) }
                        .padding(28).frame(minWidth: 200).glass(RoundedRectangle(cornerRadius: 30, style: .continuous))
                }
            }
            .animation(.spring(duration: 0.45, bounce: 0.15), value: immersive)
            .animation(.spring(duration: 0.4, bounce: 0.1), value: detent)
        }
        .tint(accent)
        .preferredColorScheme(settings.colorScheme)
        .fullScreenCover(isPresented: $showLibrary, onDismiss: {
            // Present Studio only once the library has fully gone, otherwise UIKit ignores the second cover.
            if let s = pendingStudio { pendingStudio = nil; studio = s; showStudio = true }
        }) {
            LibraryView(model: model, isPresented: $showLibrary,
                        onNewModel: { pendingStudio = StudioModel(); showLibrary = false },
                        onOpenProject: { id in if let s = StudioModel.open(projectID: id) { pendingStudio = s; showLibrary = false } })
                .tint(accent).preferredColorScheme(settings.colorScheme)
        }
        .fullScreenCover(isPresented: $showStudio) {
            if let studio { StudioView(model: studio, onDone: finishStudio).tint(accent).preferredColorScheme(settings.colorScheme) }
            else { ProgressView().onAppear { showStudio = false } }
        }
        .sheet(isPresented: $showSettings) { SettingsView(model: model) }
        .sheet(item: $snapshot) { SnapshotSheet(image: $0.image).tint(accent) }
        .onOpenURL { url in showLibrary = false; model.importFiles([url]) }
    }

    // MARK: Studio

    private func startStudio(_ s: StudioModel) {
        if showLibrary { pendingStudio = s; showLibrary = false } else { studio = s; showStudio = true }
    }

    /// Moves the current model into Studio for posing, animating or editing.
    private func editInStudio() {
        let lent = model.lendToStudio()
        let s = StudioModel()
        s.importLent(nodes: lent.nodes, name: lent.name.isEmpty ? "Model" : lent.name)
        studio = s; showStudio = true
    }

    private func finishStudio(_ s: StudioModel) {
        if s.hasSavableContent && s.dirty { s.saveProject() }
        let scene = s.makeViewerScene()
        s.detach()
        model.receiveFromStudio(scene: scene, newClips: s.savedClips, name: s.projectName)
        showStudio = false
        Task { @MainActor in try? await Task.sleep(nanoseconds: 600_000_000); studio = nil }
    }

    private func singleTap() {
        guard immersive else { return }
        withAnimation(.spring(duration: 0.45, bounce: 0.2)) { showExit = true }
        Task { try? await Task.sleep(nanoseconds: 3_000_000_000); withAnimation(.easeOut(duration: 0.3)) { showExit = false } }
    }

    private func dockHeight(total: CGFloat) -> CGFloat {
        switch detent { case .peek: return headerHeight; case .medium: return total * 0.5; case .large: return total * 0.86 }
    }

    private func enterFullScreen() {
        withAnimation(.spring(duration: 0.5, bounce: 0.15)) { immersive = true }
        Haptics.tap()
        if settings.showHints { model.showToast("Tap the model to show the exit button") }
    }

    // MARK: top bar — three controls, one glass group
    private var topBar: some View {
        GlassGroup(spacing: 10) {
            HStack(spacing: 10) {
                Button { showLibrary = true } label: {
                    Image(systemName: "square.grid.2x2").font(.system(size: 17, weight: .semibold)).frame(width: 46, height: 46).contentShape(Circle())
                }
                .buttonStyle(.plain).glass(Circle(), interactive: true).accessibilityLabel("Library")

                VStack(alignment: .leading, spacing: 0) {
                    Text(model.stats.name).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1).monospacedDigit()
                }
                .padding(.horizontal, 16).frame(height: 46).frame(maxWidth: .infinity, alignment: .leading)
                .glass(Capsule())

                Button { DocumentPicker.present { model.importFiles($0) } } label: {
                    Image(systemName: "plus").font(.system(size: 19, weight: .bold)).foregroundStyle(.white).frame(width: 46, height: 46).contentShape(Circle())
                }
                .buttonStyle(.plain).glass(Circle(), tint: accent, interactive: true).accessibilityLabel("Open file")
            }
        }
    }

    private var subtitle: String {
        var parts = [model.stats.format]
        if model.stats.triangles > 0 { parts.append("\(Fmt.count(model.stats.triangles)) tris") }
        if model.stats.bones > 0 { parts.append("\(model.stats.bones) bones") }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    // MARK: dock — playback header + inspector in a single glass panel
    private func dock(height: CGFloat, landscape: Bool) -> some View {
        let expanded = landscape || detent != .peek
        return VStack(spacing: 0) {
            header(landscape: landscape)
            if expanded {
                Picker("Inspector", selection: $tab) { ForEach(InspectorTab.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented).padding(.horizontal, 12).padding(.bottom, 10)
                ScrollView {
                    InspectorContent(model: model, tab: tab, accentIndex: $accentIndex,
                                     onFullScreen: enterFullScreen,
                                     onSnapshot: { if let img = model.snapshot() { snapshot = SnapshotItem(image: img) } },
                                     onAR: openAR,
                                     onSettings: { showSettings = true },
                                     onStudio: editInStudio)
                        .padding(.horizontal, 12).padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
                .transition(.opacity)
            }
        }
        .frame(height: landscape ? nil : max(headerHeight, height), alignment: .top)
        .frame(maxHeight: landscape ? .infinity : nil, alignment: .top)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .glass(RoundedRectangle(cornerRadius: 32, style: .continuous))
    }

    private func header(landscape: Bool) -> some View {
        HStack(spacing: 10) {
            if model.clips.isEmpty {
                Image(systemName: "cube").font(.system(size: 18, weight: .semibold)).foregroundStyle(.secondary).frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 1) {
                    Text("No animation").font(.subheadline.weight(.semibold))
                    Text("\(Fmt.count(model.stats.vertices)) vertices · \(model.stats.materials) materials").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Button { model.isPlaying.toggle(); Haptics.tap() } label: {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 44, height: 44).background(accent, in: Circle()).contentShape(Circle())
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain).accessibilityLabel(model.isPlaying ? "Pause" : "Play")

                Menu {
                    ForEach(Array(model.clips.enumerated()), id: \.element.id) { i, c in
                        Button { model.play(i) } label: { Label(c.name, systemImage: i == model.currentClip ? "checkmark" : "film") }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(model.currentClip.map { model.clips[$0].name } ?? "Choose animation").font(.subheadline.weight(.semibold)).lineLimit(1)
                            if model.clips.count > 1 { Image(systemName: "chevron.up.chevron.down").font(.caption2.weight(.bold)).foregroundStyle(.secondary) }
                        }
                        Text(model.currentClip.map { String(format: "%.1f s · %d of %d", model.clips[$0].duration, $0 + 1, model.clips.count) } ?? "")
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Menu {
                    ForEach([0.25, 0.5, 1.0, 1.5, 2.0], id: \.self) { s in Button("\(Fmt.speed(s))×") { model.speed = s } }
                } label: {
                    Text("\(Fmt.speed(model.speed))×").font(.footnote.weight(.semibold)).monospacedDigit().padding(.horizontal, 11).frame(height: 32)
                        .background(Color.primary.opacity(0.08), in: Capsule())
                }
                .buttonStyle(.plain)
            }

            Button(action: enterFullScreen) {
                Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 15, weight: .semibold)).frame(width: 36, height: 36)
                    .background(Color.primary.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain).accessibilityLabel("Full screen")

            if !landscape {
                Button { detent = detent == .peek ? .medium : .peek; Haptics.select() } label: {
                    Image(systemName: "chevron.up").font(.system(size: 14, weight: .bold)).rotationEffect(.degrees(detent == .peek ? 0 : 180))
                        .frame(width: 36, height: 36).background(Color.primary.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain).accessibilityLabel(detent == .peek ? "Show details" : "Hide details")
            }
        }
        .padding(.horizontal, 12).frame(height: headerHeight)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 8).onChanged { v in drag = max(-200, min(200, v.translation.height)) }.onEnded { v in
            let vy = v.predictedEndTranslation.height
            withAnimation(.spring(duration: 0.4, bounce: 0.1)) {
                if vy < -60 { detent = Detent(rawValue: min(2, detent.rawValue + 1))! }
                else if vy > 60 { detent = Detent(rawValue: max(0, detent.rawValue - 1))! }
                drag = 0
            }
        }, including: landscape ? .none : .all)
    }

    private func openAR() {
        model.loadingText = "Preparing AR"; model.isLoading = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000)
            let url = model.usdzForAR(); model.isLoading = false
            if let url { ARPresenter.present(url: url) } else { model.showToast("This model couldn’t be converted for AR.") }
        }
    }
}

/// Soft colour field behind the 3D view so the glass has something to refract.
struct Backdrop: View {
    let accent: Color
    var style: Int = 0          // 0 gradient, 1 plain, 2 black, 3 white
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        switch style {
        case 1: Color(uiColor: .systemGroupedBackground)
        case 2: Color.black
        case 3: Color.white
        default:
            ZStack {
                (scheme == .dark ? Color(white: 0.06) : Color(red: 0.93, green: 0.94, blue: 0.96))
                RadialGradient(colors: [accent.opacity(scheme == .dark ? 0.28 : 0.22), .clear], center: .init(x: 0.15, y: 0.15), startRadius: 0, endRadius: 420)
                RadialGradient(colors: [Color.orange.opacity(0.16), .clear], center: .init(x: 0.9, y: 0.1), startRadius: 0, endRadius: 360)
                RadialGradient(colors: [Color.purple.opacity(0.16), .clear], center: .init(x: 0.75, y: 0.95), startRadius: 0, endRadius: 420)
                RadialGradient(colors: [(scheme == .dark ? Color.white.opacity(0.06) : Color.white.opacity(0.7)), .clear], center: .init(x: 0.5, y: 0.38), startRadius: 0, endRadius: 380)
            }
        }
    }
}

enum Fmt {
    static func count(_ n: Int) -> String { n >= 1_000_000 ? String(format: "%.2fM", Double(n) / 1e6) : n >= 10_000 ? String(format: "%.1fK", Double(n) / 1e3) : "\(n)" }
    static func bytes(_ b: Double) -> String { b >= 1e9 ? String(format: "%.2f GB", b / 1e9) : b >= 1e6 ? String(format: "%.1f MB", b / 1e6) : b >= 1e3 ? String(format: "%.0f KB", b / 1e3) : "\(Int(b)) B" }
    static func speed(_ s: Double) -> String { s == floor(s) ? String(format: "%.0f", s) : (s * 4 == floor(s * 4) && s < 1 ? String(format: "%.2g", s) : String(format: "%.2g", s)) }
    static func len(_ v: Float) -> String { abs(v) >= 100 ? String(format: "%.0f", v) : abs(v) >= 10 ? String(format: "%.1f", v) : String(format: "%.2f", v) }
}

struct SnapshotSheet: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss
    @State private var saved = false
    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Image(uiImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Color(uiColor: .secondarySystemBackground)))
                HStack(spacing: 12) {
                    ShareLink(item: Image(uiImage: image), preview: SharePreview("Rig Viewer snapshot", image: Image(uiImage: image))) {
                        Label("Share", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity).frame(height: 30)
                    }
                    .glassButton()
                    Button { UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil); saved = true } label: {
                        Label(saved ? "Saved" : "Save to Photos", systemImage: saved ? "checkmark" : "photo.on.rectangle").frame(maxWidth: .infinity).frame(height: 30)
                    }
                    .glassButton(prominent: true).disabled(saved)
                }
            }
            .padding(20)
            .navigationTitle("Snapshot").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}
