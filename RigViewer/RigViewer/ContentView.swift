import SwiftUI
import SceneKit

enum InspectorTab: String, CaseIterable, Identifiable {
    case info = "Info", scene = "Scene", clips = "Clips", bones = "Bones", look = "Look", view = "View"
    var id: String { rawValue }
}
enum Detent: Int { case peek, medium, large }

struct ContentView: View {
    @StateObject private var model = ViewerModel()
    @State private var showLibrary = true
    @State private var immersive = false
    @State private var showExit = false
    @State private var importing = false
    @State private var tab: InspectorTab = .info
    @State private var detent: Detent = .peek
    @State private var drag: CGFloat = 0
    @State private var snapshot: SnapshotItem?
    @AppStorage("accentIndex") private var accentIndex = 0

    private var accent: Color { Accent.all[min(max(accentIndex, 0), Accent.all.count - 1)].color }

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height && geo.size.width > 600
            ZStack {
                Backdrop(accent: accent).ignoresSafeArea()
                SceneViewer(model: model, onSingleTap: singleTap, onDoubleTap: { model.frame() })
                    .ignoresSafeArea()

                if !immersive {
                    VStack { topBar; Spacer() }
                        .padding(.horizontal, 12).padding(.top, 2)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    if landscape {
                        HStack(alignment: .bottom, spacing: 12) {
                            VStack { Spacer(); transport }
                            inspector(height: geo.size.height - 8, landscape: true).frame(width: 370)
                        }
                        .padding(.horizontal, 12).padding(.bottom, 4)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    } else {
                        VStack(spacing: 10) {
                            Spacer()
                            if detent != .large { transport.padding(.horizontal, 12).transition(.opacity.combined(with: .scale(scale: 0.95))) }
                            inspector(height: height(for: detent, total: geo.size.height + geo.safeAreaInsets.bottom) - drag, landscape: false)
                        }
                        .ignoresSafeArea(edges: .bottom)
                        .transition(.move(edge: .bottom))
                    }
                } else if showExit {
                    VStack {
                        Button { withAnimation(.spring(duration: 0.5, bounce: 0.25)) { immersive = false; showExit = false } } label: {
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
                            .padding(.horizontal, 24).padding(.top, immersive ? 60 : 70)
                        Spacer()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity)).allowsHitTesting(false)
                }
                if model.isLoading {
                    VStack(spacing: 14) { ProgressView().controlSize(.large); Text(model.loadingText).font(.subheadline).foregroundStyle(.secondary).lineLimit(2) }
                        .padding(28).frame(minWidth: 200).glass(RoundedRectangle(cornerRadius: 30, style: .continuous))
                }
            }
            .animation(.spring(duration: 0.45, bounce: 0.18), value: immersive)
            .animation(.spring(duration: 0.42, bounce: 0.12), value: detent)
        }
        .tint(accent)
        .fullScreenCover(isPresented: $showLibrary) { LibraryView(model: model, isPresented: $showLibrary).tint(accent) }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { model.importFiles(urls) }
        }
        .sheet(item: $snapshot) { SnapshotSheet(image: $0.image).tint(accent) }
        .onOpenURL { url in showLibrary = false; model.importFiles([url]) }
        .onChange(of: tab) { _, _ in if detent == .peek { detent = .medium } }
    }

    private func singleTap() {
        guard immersive else { return }
        withAnimation(.spring(duration: 0.45, bounce: 0.25)) { showExit = true }
        Task { try? await Task.sleep(nanoseconds: 3_000_000_000); withAnimation(.easeOut(duration: 0.3)) { showExit = false } }
    }

    private func height(for d: Detent, total: CGFloat) -> CGFloat {
        switch d { case .peek: return 104; case .medium: return total * 0.46; case .large: return total * 0.88 }
    }

    // MARK: top bar
    private var topBar: some View {
        GlassGroup(spacing: 10) {
            HStack(spacing: 10) {
                Button { showLibrary = true } label: {
                    Image(systemName: "square.grid.2x2").font(.system(size: 18, weight: .semibold)).frame(width: 50, height: 50).contentShape(Circle())
                }
                .buttonStyle(.plain).glass(Circle(), interactive: true).accessibilityLabel("Library")

                VStack(alignment: .leading, spacing: 1) {
                    Text(model.stats.name).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1).monospacedDigit()
                }
                .padding(.horizontal, 18).frame(height: 50).frame(maxWidth: .infinity, alignment: .leading)
                .glass(Capsule())

                Button { withAnimation(.spring(duration: 0.5, bounce: 0.2)) { immersive = true }; model.showToast("Full screen · tap the model to show the exit button") } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 17, weight: .semibold)).frame(width: 50, height: 50).contentShape(Circle())
                }
                .buttonStyle(.plain).glass(Circle(), interactive: true).accessibilityLabel("Full screen")

                Button { importing = true } label: {
                    Image(systemName: "plus").font(.system(size: 20, weight: .bold)).foregroundStyle(.white).frame(width: 50, height: 50).contentShape(Circle())
                }
                .buttonStyle(.plain).glass(Circle(), tint: accent, interactive: true).accessibilityLabel("Open file")
            }
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if model.stats.triangles > 0 { parts.append("\(Fmt.count(model.stats.triangles)) triangles") }
        if model.stats.bones > 0 { parts.append("\(model.stats.bones) bones") }
        parts.append("\(model.clips.count) \(model.clips.count == 1 ? "animation" : "animations")")
        return parts.joined(separator: " · ")
    }

    // MARK: transport
    private var transport: some View {
        HStack(spacing: 12) {
            Button { model.isPlaying.toggle() } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 19, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 48, height: 48).contentShape(Circle()).contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain).glass(Circle(), tint: accent, interactive: true).disabled(model.clips.isEmpty)

            Menu {
                ForEach(Array(model.clips.enumerated()), id: \.element.id) { i, c in
                    Button { model.play(i) } label: { Label(c.name, systemImage: i == model.currentClip ? "checkmark" : "film") }
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(model.currentClip.map { model.clips[$0].name } ?? "No animation").font(.subheadline.weight(.semibold)).lineLimit(1)
                        if model.clips.count > 1 { Image(systemName: "chevron.up.chevron.down").font(.caption2.weight(.bold)).foregroundStyle(.secondary) }
                    }
                    Text(model.currentClip.map { String(format: "%.1f s · %d of %d", model.clips[$0].duration, $0 + 1, model.clips.count) } ?? "This file has no animation")
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain).disabled(model.clips.isEmpty)

            Menu {
                ForEach([0.25, 0.5, 1.0, 1.5, 2.0], id: \.self) { s in Button("\(Fmt.speed(s))×") { model.speed = s } }
            } label: {
                Text("\(Fmt.speed(model.speed))×").font(.subheadline.weight(.semibold)).monospacedDigit().padding(.horizontal, 14).frame(height: 38)
            }
            .buttonStyle(.plain).glass(Capsule(), interactive: true)
        }
        .padding(.horizontal, 8).frame(height: 66)
        .glass(Capsule())
        .opacity(model.clips.isEmpty ? 0.7 : 1)
    }

    // MARK: inspector
    private func inspector(height: CGFloat, landscape: Bool) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                if !landscape { Capsule().fill(Color.secondary.opacity(0.45)).frame(width: 40, height: 5).padding(.top, 8) }
                Picker("Inspector", selection: $tab) { ForEach(InspectorTab.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented).padding(.horizontal, 14).padding(.top, landscape ? 14 : 0)
            }
            .padding(.bottom, 10)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 6).onChanged { v in drag = v.translation.height }.onEnded { v in
                let vy = v.predictedEndTranslation.height - v.translation.height
                withAnimation(.spring(duration: 0.42, bounce: 0.12)) {
                    if v.translation.height < -40 || vy < -200 { detent = Detent(rawValue: min(2, detent.rawValue + 1))! }
                    else if v.translation.height > 40 || vy > 200 { detent = Detent(rawValue: max(0, detent.rawValue - 1))! }
                    drag = 0
                }
            }, including: landscape ? .none : .all)
            .onTapGesture { if !landscape && detent == .peek { detent = .medium } }

            ScrollView {
                InspectorContent(model: model, tab: tab, accentIndex: $accentIndex,
                                 onFullScreen: { withAnimation { immersive = true } },
                                 onSnapshot: { if let img = model.snapshot() { snapshot = SnapshotItem(image: img) } },
                                 onAR: openAR)
                    .padding(.horizontal, 14).padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .opacity(detent == .peek && !landscape ? 0 : 1)
        }
        .frame(height: max(96, height)).frame(maxWidth: .infinity)
        .glass(RoundedRectangle(cornerRadius: landscape ? 30 : 38, style: .continuous))
        .padding(.horizontal, landscape ? 0 : (detent == .large ? 0 : 8))
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
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack {
            (scheme == .dark ? Color(white: 0.06) : Color(red: 0.93, green: 0.94, blue: 0.96))
            RadialGradient(colors: [accent.opacity(scheme == .dark ? 0.28 : 0.22), .clear], center: .init(x: 0.15, y: 0.15), startRadius: 0, endRadius: 420)
            RadialGradient(colors: [Color.orange.opacity(0.16), .clear], center: .init(x: 0.9, y: 0.1), startRadius: 0, endRadius: 360)
            RadialGradient(colors: [Color.purple.opacity(0.16), .clear], center: .init(x: 0.75, y: 0.95), startRadius: 0, endRadius: 420)
            RadialGradient(colors: [(scheme == .dark ? Color.white.opacity(0.06) : Color.white.opacity(0.7)), .clear], center: .init(x: 0.5, y: 0.38), startRadius: 0, endRadius: 380)
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
