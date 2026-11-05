import AppKit
import SwiftUI
import UniformTypeIdentifiers
import LockedShared

@MainActor
struct WebsitesSection: View {
    @EnvironmentObject var model: SetupModel
    @State private var input = ""
    @State private var scope: WebsiteScope = .domain
    @State private var errorMessage: String?

    private var canAdd: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        SectionBox(title: "Websites", systemImage: "globe") {
            HStack {
                TextField("example.com or https://example.com/some/page", text: $input)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        add()
                    }
                Picker("Scope", selection: $scope) {
                    Text("Whole domain").tag(WebsiteScope.domain)
                    Text("This page").tag(WebsiteScope.page)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 210)
                Button("Add") {
                    add()
                }
                .disabled(!canAdd)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Button {
                model.addAISites()
            } label: {
                Label("Add AI sites (ChatGPT, Claude, Gemini)", systemImage: "sparkles")
            }
            ForEach(model.allowlist.websites) { site in
                RemovableRow(title: site.url, subtitle: scopeDescription(site.scope), onRemove: {
                    model.removeWebsite(id: site.id)
                }) {
                    Image(systemName: site.scope == .domain ? "globe" : "doc.text")
                        .frame(width: 22)
                }
            }
        }
    }

    private func scopeDescription(_ scope: WebsiteScope) -> String {
        switch scope {
        case .domain: return "Whole domain, including subdomains"
        case .page: return "This page and pages below it"
        }
    }

    private func add() {
        guard canAdd else { return }
        if let error = model.addWebsite(input, scope: scope) {
            errorMessage = error
        } else {
            errorMessage = nil
            input = ""
        }
    }
}

@MainActor
struct YouTubeSection: View {
    @EnvironmentObject var model: SetupModel
    @State private var input = ""
    @State private var errorMessage: String?

    private var canAdd: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        SectionBox(title: "YouTube videos", systemImage: "play.rectangle") {
            HStack {
                TextField("Paste a YouTube video link", text: $input)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        add()
                    }
                Button("Add") {
                    add()
                }
                .disabled(!canAdd)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            ForEach(model.allowlist.youtube) { video in
                RemovableRow(title: video.title ?? "Video \(video.videoId)",
                             subtitle: video.watchURL.absoluteString,
                             onRemove: { model.removeYouTube(id: video.id) }) {
                    Image(systemName: "play.rectangle.fill")
                        .foregroundStyle(.red)
                        .frame(width: 22)
                }
            }
        }
    }

    private func add() {
        guard canAdd else { return }
        if let error = model.addYouTube(input) {
            errorMessage = error
        } else {
            errorMessage = nil
            input = ""
        }
    }
}

@MainActor
struct PDFsSection: View {
    @EnvironmentObject var model: SetupModel

    var body: some View {
        SectionBox(title: "PDFs", systemImage: "doc.richtext") {
            ForEach(model.allowlist.pdfs) { pdf in
                RemovableRow(title: pdf.fileName, subtitle: pdf.path, onRemove: {
                    model.removePDF(id: pdf.id)
                }) {
                    Image(systemName: "doc.richtext")
                        .frame(width: 22)
                }
            }
            HStack {
                Button("Add PDFs…") {
                    choosePDFs()
                }
                Text("PDFs open in Locked's built-in viewer during the session.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func choosePDFs() {
        let panel = NSOpenPanel()
        panel.title = "Choose PDFs to allow"
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        model.addPDFs(panel.urls)
    }
}
