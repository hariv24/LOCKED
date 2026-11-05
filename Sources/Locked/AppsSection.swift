import AppKit
import SwiftUI
import UniformTypeIdentifiers
import LockedShared

@MainActor
struct AppsSection: View {
    @EnvironmentObject var model: SetupModel
    @State private var showPicker = false
    @State private var errorMessage: String?

    var body: some View {
        SectionBox(title: "Apps", systemImage: "square.grid.2x2") {
            if model.allowlist.apps.isEmpty {
                Text("No apps allowed yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(model.allowlist.apps) { app in
                RemovableRow(title: app.name, subtitle: app.bundleId, onRemove: {
                    model.removeApp(bundleId: app.bundleId)
                }) {
                    Image(nsImage: IconCache.shared.icon(for: app))
                        .resizable()
                        .frame(width: 22, height: 22)
                }
            }
            HStack {
                Button("Choose Apps…") {
                    showPicker = true
                }
                Button("Add Other App…") {
                    addOtherApp()
                }
                if model.isScanning {
                    ProgressView()
                        .controlSize(.small)
                    Text("Scanning installed apps…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Text("Chrome is allowed automatically when you add websites or videos (and the extension is connected).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .sheet(isPresented: $showPicker) {
            AppPickerSheet()
                .environmentObject(model)
        }
    }

    private func addOtherApp() {
        let panel = NSOpenPanel()
        panel.title = "Choose an app to allow"
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        guard panel.runModal() == .OK else { return }
        var errors: [String] = []
        for url in panel.urls {
            if let error = model.addOtherApp(at: url) {
                errors.append(error)
            }
        }
        errorMessage = errors.isEmpty ? nil : errors.joined(separator: " ")
    }
}

/// Searchable checklist of installed apps.
@MainActor
struct AppPickerSheet: View {
    @EnvironmentObject var model: SetupModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filteredApps: [InstalledApp] {
        let apps = model.selectableApps
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return apps }
        return apps.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed) || $0.bundleId.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Choose allowed apps")
                .font(.headline)
            TextField("Search apps", text: $query)
                .textFieldStyle(.roundedBorder)
            if model.isScanning && model.installedApps.isEmpty {
                ProgressView("Scanning…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredApps) { app in
                    AppPickerRow(app: app)
                }
            }
            HStack {
                Text("\(model.allowlist.apps.count) selected")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 500, height: 560)
    }
}

@MainActor
struct AppPickerRow: View {
    @EnvironmentObject var model: SetupModel
    let app: InstalledApp

    private var isSelected: Binding<Bool> {
        Binding(
            get: { model.isAppSelected(app.bundleId) },
            set: { model.setApp(app, selected: $0) })
    }

    var body: some View {
        Toggle(isOn: isSelected) {
            HStack(spacing: 8) {
                Image(nsImage: IconCache.shared.icon(forPath: app.path))
                    .resizable()
                    .frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(app.name)
                    Text(app.bundleId)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .toggleStyle(.checkbox)
    }
}
