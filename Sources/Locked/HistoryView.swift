import SwiftUI
import LockedShared

/// Past sessions, newest first.
@MainActor
struct HistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [HistoryEntry] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("History")
                .font(.title2.bold())
            if entries.isEmpty {
                Text("No sessions yet.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(entries) { entry in
                    HistoryRow(entry: entry)
                }
            }
            HStack {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 560, height: 520)
        .onAppear {
            entries = LockedStore.loadHistory().sorted { $0.startedAt > $1.startedAt }
        }
    }

    private var summary: String {
        let completed = entries.filter { $0.outcome == .completed }.count
        return "\(entries.count) sessions, \(completed) completed"
    }
}

@MainActor
struct HistoryRow: View {
    let entry: HistoryEntry

    private var plannedMinutes: Int {
        max(0, Int((entry.plannedEndAt.timeIntervalSince(entry.startedAt) / 60).rounded()))
    }

    private var actualMinutes: Int {
        max(0, Int((entry.endedAt.timeIntervalSince(entry.startedAt) / 60).rounded()))
    }

    var body: some View {
        HStack {
            Image(systemName: entry.outcome == .completed ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(entry.outcome == .completed ? Color.green : Color.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.startedAt.formatted(date: .abbreviated, time: .shortened))
                Text("Planned \(formatMinutes(plannedMinutes))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(entry.outcome == .completed ? "Completed" : "Exited early")
                if entry.outcome == .exitedEarly {
                    Text("after \(formatMinutes(actualMinutes))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
