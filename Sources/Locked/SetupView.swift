import AppKit
import SwiftUI
import LockedShared

/// The screen shown when no session is active.
@MainActor
struct SetupView: View {
    @EnvironmentObject var model: SetupModel
    @EnvironmentObject var session: SessionManager
    @EnvironmentObject var bridge: BridgeStatus

    @State private var showHistory = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    SetupHeader(showHistory: $showHistory)
                    AppsSection()
                    WebsitesSection()
                    YouTubeSection()
                    PDFsSection()
                    DurationSection()
                    PresetsSection()
                    ExtensionStatusSection()
                }
                .padding(20)
            }
            Divider()
            StartBar()
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
        }
        .sheet(isPresented: $showHistory) {
            HistoryView()
        }
        .onAppear {
            model.scanAppsIfNeeded()
            bridge.refresh()
        }
    }
}

@MainActor
struct SetupHeader: View {
    @Binding var showHistory: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Locked")
                    .font(.largeTitle.bold())
                Text("Choose what you're allowed to use, then lock in.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                showHistory = true
            } label: {
                Label("History", systemImage: "clock.arrow.circlepath")
            }
        }
    }
}

/// Bottom bar with warnings and the Start button.
@MainActor
struct StartBar: View {
    @EnvironmentObject var model: SetupModel
    @EnvironmentObject var session: SessionManager
    @EnvironmentObject var bridge: BridgeStatus

    @State private var showChromeWarning = false
    @State private var startError: String?

    private var chromeWillBeBlocked: Bool {
        model.allowlist.needsBrowser && !bridge.isConnected
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Every app that isn't allowed will be hidden, and Locked can't be quit until the timer ends.",
                  systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.secondary)
            if chromeWillBeBlocked {
                Label("The Chrome extension isn't connected, so Chrome will be hidden too.",
                      systemImage: "exclamationmark.octagon")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            HStack {
                Text("\(formatMinutes(model.durationMinutes)) session")
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    startTapped()
                } label: {
                    Text("Start Session")
                        .frame(minWidth: 140)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(model.allowlist.isEmpty)
            }
        }
        .alert("Chrome will be blocked", isPresented: $showChromeWarning) {
            Button("Start Anyway", role: .destructive) {
                startSession()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your allowlist has websites or YouTube videos, but Locked's Chrome extension isn't connected. Chrome will be hidden for the whole session until the extension connects.")
        }
        .background(
            Color.clear
                .alert("Couldn't start the session", isPresented: startErrorBinding) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(startError ?? "")
                }
        )
    }

    private var startErrorBinding: Binding<Bool> {
        Binding(
            get: { startError != nil },
            set: { if !$0 { startError = nil } })
    }

    private func startTapped() {
        if chromeWillBeBlocked {
            showChromeWarning = true
        } else {
            startSession()
        }
    }

    private func startSession() {
        do {
            try session.start(allowlist: model.allowlist, durationMinutes: model.durationMinutes)
        } catch {
            startError = error.localizedDescription
        }
    }
}
