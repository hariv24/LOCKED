import AppKit
import SwiftUI
import LockedShared

/// Switches between the setup screen and the session screen.
@MainActor
struct RootView: View {
    @EnvironmentObject var session: SessionManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if session.isActive {
                SessionView()
            } else {
                SetupView()
            }
        }
        .frame(minWidth: 680, minHeight: 640)
        .background(
            WindowAccessor { window in
                MainWindowRouter.shared.window = window
            }
        )
        .onAppear {
            MainWindowRouter.shared.openWindowAction = openWindow
        }
    }
}

/// A titled box used by every section on the setup screen.
@MainActor
struct SectionBox<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        } label: {
            Label(title, systemImage: systemImage)
                .font(.headline)
        }
    }
}

/// One removable row in a setup list.
@MainActor
struct RemovableRow<Leading: View>: View {
    let title: String
    let subtitle: String?
    let onRemove: @MainActor () -> Void
    @ViewBuilder let leading: () -> Leading

    var body: some View {
        HStack(spacing: 8) {
            leading()
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
            Button {
                onRemove()
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Remove")
        }
    }
}
