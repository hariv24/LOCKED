import AppKit
import PDFKit
import SwiftUI
import LockedShared

/// Built-in PDF viewer window. PDFs never open in Preview during a session.
@MainActor
final class PDFViewerModel: ObservableObject {
    @Published var entries: [PDFEntry] = []
    @Published var selectedId: UUID?

    var selected: PDFEntry? {
        guard let selectedId else { return nil }
        return entries.first { $0.id == selectedId }
    }
}

@MainActor
final class PDFViewerController: NSObject {
    static let shared = PDFViewerController()

    private let model = PDFViewerModel()
    private var window: NSWindow?

    private override init() {
        super.init()
    }

    func open(_ entry: PDFEntry, among entries: [PDFEntry]) {
        model.entries = entries.isEmpty ? [entry] : entries
        model.selectedId = entry.id

        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 980, height: 900),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false)
            window.title = "Locked PDF Viewer"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: PDFViewerView(model: model))
            window.center()
            window.setFrameAutosaveName("LockedPDFViewer")
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.orderOut(nil)
    }
}

@MainActor
struct PDFViewerView: View {
    @ObservedObject var model: PDFViewerModel

    var body: some View {
        HStack(spacing: 0) {
            if model.entries.count > 1 {
                List(model.entries, selection: $model.selectedId) { entry in
                    Label(entry.fileName, systemImage: "doc.richtext")
                        .lineLimit(1)
                }
                .frame(width: 220)
                Divider()
            }
            PDFDetailView(entry: model.selected)
        }
        .frame(minWidth: 500, minHeight: 400)
    }
}

@MainActor
struct PDFDetailView: View {
    let entry: PDFEntry?

    var body: some View {
        if let entry {
            if FileManager.default.fileExists(atPath: entry.path) {
                PDFKitView(url: URL(fileURLWithPath: entry.path))
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                    Text("File not found")
                        .font(.headline)
                    Text(entry.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            Text("Select a PDF")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// PDFKit's PDFView wrapped for SwiftUI. Swaps the document when the URL changes.
@MainActor
struct PDFKitView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displaysPageBreaks = true
        view.document = PDFDocument(url: url)
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        if nsView.document?.documentURL != url {
            nsView.document = PDFDocument(url: url)
            nsView.autoScales = true
        }
    }
}
