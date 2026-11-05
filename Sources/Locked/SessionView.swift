import AppKit
import SwiftUI
import LockedShared

/// Opens allowed items during a session.
@MainActor
enum SessionActions {
    /// Returns an error message, or nil on success.
    static func openApp(_ app: AllowedApp) -> String? {
        let url: URL?
        if let path = app.path, FileManager.default.fileExists(atPath: path) {
            url = URL(fileURLWithPath: path)
        } else {
            url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleId)
        }
        guard let appURL = url else { return "Couldn't find \(app.name) on this Mac." }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
            if let error {
                NSLog("Locked: failed to open app: %@", String(describing: error))
            }
        }
        return nil
    }

    static func openWebsite(_ site: WebsiteEntry) -> String? {
        guard let url = URL(string: site.url) else { return "That website address is invalid." }
        return openInChrome(url)
    }

    static func openYouTube(_ video: YouTubeEntry) -> String? {
        openInChrome(video.watchURL)
    }

    static func openPDF(_ pdf: PDFEntry, among all: [PDFEntry]) {
        PDFViewerController.shared.open(pdf, among: all)
    }

    private static func openInChrome(_ url: URL) -> String? {
        guard let chromeURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: LockedConstants.chromeBundleId) else {
            return "Google Chrome isn't installed."
        }
        AppBlocker.shared.noteChromeRequested()
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([url], withApplicationAt: chromeURL, configuration: configuration) { _, error in
            if let error {
                NSLog("Locked: failed to open URL in Chrome: %@", String(describing: error))
            }
        }
        return nil
    }
}

/// The screen shown while a session is active.
@MainActor
struct SessionView: View {
    @EnvironmentObject var session: SessionManager
    @EnvironmentObject var bridge: BridgeStatus
    @State private var actionError: String?

    private var emergencyPresented: Binding<Bool> {
        Binding(
            get: { session.emergency != .inactive },
            set: { if !$0 { session.cancelEmergencyExit() } })
    }

    private var actionErrorPresented: Binding<Bool> {
        Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } })
    }

    var body: some View {
        VStack(spacing: 0) {
            SessionHeader()
                .padding(.top, 28)
                .padding(.bottom, 16)
            Divider()
            if let state = session.state {
                AllowedItemsList(allowlist: state.allowlist, chromeConnected: bridge.isConnected) { message in
                    actionError = message
                }
            }
            Divider()
            HStack {
                Text("Locked can't be quit until the session ends.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Emergency Exit…") {
                    session.beginEmergencyExit()
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .sheet(isPresented: emergencyPresented) {
            EmergencyExitSheet()
                .environmentObject(session)
        }
        .alert("Couldn't open that", isPresented: actionErrorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
    }
}

@MainActor
struct SessionHeader: View {
    @EnvironmentObject var session: SessionManager

    var body: some View {
        VStack(spacing: 6) {
            Text("Focus session")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(formatCountdown(session.remaining))
                .font(.system(size: 76, weight: .bold, design: .rounded).monospacedDigit())
            if let state = session.state {
                Text("Ends at \(state.endsAt.formatted(date: .omitted, time: .shortened))")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

@MainActor
struct AllowedItemsList: View {
    let allowlist: Allowlist
    let chromeConnected: Bool
    let onError: @MainActor (String) -> Void

    var body: some View {
        List {
            if !allowlist.apps.isEmpty {
                appsSection
            }
            if !allowlist.websites.isEmpty {
                websitesSection
            }
            if !allowlist.youtube.isEmpty {
                youtubeSection
            }
            if !allowlist.pdfs.isEmpty {
                pdfsSection
            }
        }
    }

    private var appsSection: some View {
        Section("Apps") {
            ForEach(allowlist.apps) { app in
                AllowedItemRow(title: app.name, subtitle: nil, actionTitle: "Open") {
                    Image(nsImage: IconCache.shared.icon(for: app))
                        .resizable()
                        .frame(width: 22, height: 22)
                } action: {
                    if let message = SessionActions.openApp(app) { onError(message) }
                }
            }
        }
    }

    private var websitesTitle: String {
        chromeConnected ? "Websites (open in Chrome)" : "Websites (Chrome extension not connected: Chrome will be hidden)"
    }

    private var websitesSection: some View {
        Section(websitesTitle) {
            ForEach(allowlist.websites) { site in
                AllowedItemRow(title: site.url,
                               subtitle: site.scope == .domain ? "Whole domain" : "This page",
                               actionTitle: "Open in Chrome") {
                    Image(systemName: "globe")
                        .frame(width: 22)
                } action: {
                    if let message = SessionActions.openWebsite(site) { onError(message) }
                }
            }
        }
    }

    private var youtubeSection: some View {
        Section("YouTube") {
            ForEach(allowlist.youtube) { video in
                AllowedItemRow(title: video.title ?? "Video \(video.videoId)",
                               subtitle: video.watchURL.absoluteString,
                               actionTitle: "Watch") {
                    Image(systemName: "play.rectangle.fill")
                        .foregroundStyle(.red)
                        .frame(width: 22)
                } action: {
                    if let message = SessionActions.openYouTube(video) { onError(message) }
                }
            }
        }
    }

    private var pdfsSection: some View {
        Section("PDFs") {
            ForEach(allowlist.pdfs) { pdf in
                AllowedItemRow(title: pdf.fileName, subtitle: pdf.path, actionTitle: "Read") {
                    Image(systemName: "doc.richtext")
                        .frame(width: 22)
                } action: {
                    SessionActions.openPDF(pdf, among: allowlist.pdfs)
                }
            }
        }
    }
}

@MainActor
struct AllowedItemRow<Icon: View>: View {
    let title: String
    let subtitle: String?
    let actionTitle: String
    @ViewBuilder let icon: () -> Icon
    let action: @MainActor () -> Void

    var body: some View {
        HStack(spacing: 10) {
            icon()
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()
            Button(actionTitle) {
                action()
            }
        }
        .padding(.vertical, 2)
    }
}
