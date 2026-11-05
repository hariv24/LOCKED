import AppKit
import SwiftUI
import LockedShared

@MainActor
struct DurationSection: View {
    @EnvironmentObject var model: SetupModel

    private static let quickChoices = [25, 50, 90]

    private var minutes: Binding<Int> {
        Binding(
            get: { model.durationMinutes },
            set: { model.setDuration($0) })
    }

    var body: some View {
        SectionBox(title: "Duration", systemImage: "timer") {
            HStack(spacing: 8) {
                ForEach(Self.quickChoices, id: \.self) { choice in
                    DurationChip(minutes: choice, isSelected: model.durationMinutes == choice) {
                        model.setDuration(choice)
                    }
                }
                Divider()
                    .frame(height: 20)
                Text("Custom:")
                TextField("Minutes", value: minutes, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 64)
                Stepper("minutes", value: minutes, in: SessionManager.minDurationMinutes...SessionManager.maxDurationMinutes)
                Spacer()
            }
            Text("Between 1 and 600 minutes. Currently \(formatMinutes(model.durationMinutes)).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

@MainActor
struct DurationChip: View {
    let minutes: Int
    let isSelected: Bool
    let action: @MainActor () -> Void

    var body: some View {
        if isSelected {
            Button("\(minutes) min") { action() }
                .buttonStyle(.borderedProminent)
        } else {
            Button("\(minutes) min") { action() }
                .buttonStyle(.bordered)
        }
    }
}

@MainActor
struct PresetsSection: View {
    @EnvironmentObject var model: SetupModel
    @State private var name = ""

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !model.allowlist.isEmpty
    }

    var body: some View {
        SectionBox(title: "Presets", systemImage: "bookmark") {
            HStack {
                TextField("Preset name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        save()
                    }
                Button("Save Current") {
                    save()
                }
                .disabled(!canSave)
            }
            if let error = model.presetError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if model.presets.isEmpty {
                Text("No presets yet. Save your current allowlist and duration to reuse it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(model.presets) { preset in
                PresetRow(preset: preset)
            }
        }
    }

    private func save() {
        guard canSave else { return }
        model.savePreset(named: name)
        name = ""
    }
}

@MainActor
struct PresetRow: View {
    @EnvironmentObject var model: SetupModel
    let preset: Preset

    private var summary: String {
        let list = preset.allowlist
        var parts: [String] = []
        if !list.apps.isEmpty { parts.append("\(list.apps.count) apps") }
        if !list.websites.isEmpty { parts.append("\(list.websites.count) sites") }
        if !list.youtube.isEmpty { parts.append("\(list.youtube.count) videos") }
        if !list.pdfs.isEmpty { parts.append("\(list.pdfs.count) PDFs") }
        parts.append(formatMinutes(preset.durationMinutes))
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack {
            Image(systemName: "bookmark.fill")
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(preset.name)
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Load") {
                model.loadPreset(preset)
            }
            Button(role: .destructive) {
                model.deletePreset(preset)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Delete preset")
        }
    }
}

@MainActor
struct ExtensionStatusSection: View {
    @EnvironmentObject var bridge: BridgeStatus

    var body: some View {
        SectionBox(title: "Chrome extension", systemImage: "puzzlepiece.extension") {
            HStack(spacing: 8) {
                Circle()
                    .fill(bridge.isConnected ? Color.green : Color.red)
                    .frame(width: 10, height: 10)
                Text(statusText)
                Spacer()
                Button("Copy Path") {
                    copyPath()
                }
                Button("Show Extension Folder") {
                    showFolder()
                }
            }
            Text(verbatim: "Chrome → chrome://extensions → Developer mode → Load unpacked → pick this folder")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var statusText: String {
        guard bridge.isConnected else { return "Not connected" }
        if let version = bridge.extensionVersion {
            return "Connected (extension \(version))"
        }
        return "Connected"
    }

    private func ensureExtensionCopied() {
        if !FileManager.default.fileExists(atPath: LockedPaths.extensionDir.path) {
            ExtensionInstaller.install()
        }
    }

    private func showFolder() {
        ensureExtensionCopied()
        NSWorkspace.shared.activateFileViewerSelecting([LockedPaths.extensionDir])
    }

    private func copyPath() {
        ensureExtensionCopied()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        _ = pasteboard.setString(LockedPaths.extensionDir.path, forType: .string)
    }
}
