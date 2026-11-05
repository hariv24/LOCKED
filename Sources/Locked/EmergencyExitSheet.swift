import AppKit
import SwiftUI
import LockedShared

/// SPEC emergency exit: type a random 40-char phrase exactly, wait 60s, then confirm. Cancel any time.
@MainActor
struct EmergencyExitSheet: View {
    @EnvironmentObject var session: SessionManager

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Emergency exit", systemImage: "exclamationmark.triangle.fill")
                .font(.title2.bold())
                .foregroundStyle(.orange)
            phaseContent
            HStack {
                Spacer()
                Button("Cancel") {
                    session.cancelEmergencyExit()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 600)
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch session.emergency {
        case .inactive:
            EmptyView()
        case .typing(let phrase):
            EmergencyTypingStep(phrase: phrase)
        case .countdown:
            EmergencyCountdownStep(remaining: session.emergencyRemaining)
        case .confirm:
            EmergencyConfirmStep()
        }
    }
}

@MainActor
struct EmergencyTypingStep: View {
    @EnvironmentObject var session: SessionManager
    let phrase: String

    @State private var typed = ""
    @State private var showMismatch = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ending early is allowed, but it should take effort. Type the phrase below exactly (spaces don't matter, letter case does).")
                .fixedSize(horizontal: false, vertical: true)
            Text(phrase)
                .font(.system(size: 21, weight: .medium, design: .monospaced))
                .textSelection(.disabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
            TextField("Type the phrase here", text: $typed)
                .font(.system(size: 16, design: .monospaced))
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .onSubmit {
                    submit()
                }
            if showMismatch {
                Text("That doesn't match. Check each character.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Continue") {
                    submit()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(SessionManager.stripWhitespace(typed).isEmpty)
            }
        }
    }

    private func submit() {
        showMismatch = !session.submitEmergencyPhrase(typed)
    }
}

@MainActor
struct EmergencyCountdownStep: View {
    let remaining: TimeInterval

    private var elapsed: Double {
        max(0, min(SessionManager.emergencyWaitSeconds, SessionManager.emergencyWaitSeconds - remaining))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Phrase accepted. Wait for the countdown. Maybe you'll decide to keep going.")
                .fixedSize(horizontal: false, vertical: true)
            Text("\(Int(remaining.rounded(.up)))s")
                .font(.system(size: 48, weight: .bold, design: .rounded).monospacedDigit())
                .frame(maxWidth: .infinity)
            ProgressView(value: elapsed, total: SessionManager.emergencyWaitSeconds)
        }
    }
}

@MainActor
struct EmergencyConfirmStep: View {
    @EnvironmentObject var session: SessionManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("You can end the session now. It will be logged in your history as ended early.")
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(role: .destructive) {
                    session.confirmEmergencyExit()
                } label: {
                    Text("End Session Now")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
    }
}
