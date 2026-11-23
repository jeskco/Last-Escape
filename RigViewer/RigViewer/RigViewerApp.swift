import SwiftUI
import QuickLook

@main
struct RigViewerApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

enum Accent {
    static let all: [(name: String, color: Color)] = [
        ("Blue", .blue), ("Indigo", .indigo), ("Purple", .purple), ("Pink", .pink), ("Red", .red),
        ("Orange", .orange), ("Green", .green), ("Teal", .teal), ("Graphite", .gray),
    ]
}

/// Presents AR Quick Look from the top-most view controller.
@MainActor
enum ARPresenter {
    private static var source: ARQuickLookView.Coordinator?
    static func present(url: URL) {
        let windows = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }
        guard var top = windows.first?.rootViewController else { return }
        while let p = top.presentedViewController { top = p }
        let c = ARQuickLookView.Coordinator(url: url); source = c
        let q = QLPreviewControllerHolder.make(c)
        top.present(q, animated: true)
    }
}

enum QLPreviewControllerHolder {
    static func make(_ ds: QLPreviewControllerDataSource) -> QLPreviewController { let q = QLPreviewController(); q.dataSource = ds; return q }
}

struct SnapshotItem: Identifiable { let id = UUID(); let image: UIImage }

import UniformTypeIdentifiers

/// UIKit document picker. SwiftUI's `.fileImporter` silently fails to present when the same view
/// hierarchy also has sheets / full-screen covers, so the app presents the picker itself.
@MainActor
enum DocumentPicker {
    private final class Delegate: NSObject, UIDocumentPickerDelegate {
        let onPick: ([URL]) -> Void
        init(_ onPick: @escaping ([URL]) -> Void) { self.onPick = onPick }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { onPick(urls); DocumentPicker.delegate = nil }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { DocumentPicker.delegate = nil }
    }
    private static var delegate: Delegate?

    static func present(onPick: @escaping ([URL]) -> Void) {
        let windows = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }
        guard var top = windows.first?.rootViewController else { return }
        while let p = top.presentedViewController, !p.isBeingDismissed { top = p }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.allowsMultipleSelection = true
        picker.shouldShowFileExtensions = true
        let d = Delegate(onPick); delegate = d; picker.delegate = d
        top.present(picker, animated: true)
    }
}
