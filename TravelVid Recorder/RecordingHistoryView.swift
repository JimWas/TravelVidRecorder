import SwiftUI
import MapKit

struct RecordingHistoryView: View {
    let log: [RecordingHistoryEntry]
    @Environment(\.dismiss) private var dismiss
    private let onClear: (() -> Void)?

    init(log: [RecordingHistoryEntry], onClear: (() -> Void)? = nil) {
        self.log = log
        self.onClear = onClear
    }

    @State private var showClearConfirm = false

    var totalDuration: TimeInterval { log.reduce(0) { $0 + $1.duration } }
    var totalSessions: Int { log.count }

    var body: some View {
        NavigationStack {
            Group {
                if log.isEmpty {
                    emptyState
                } else {
                    List {
                        summarySection
                        sessionsSection
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Recording History")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !log.isEmpty {
                        Button("Clear", role: .destructive) {
                            showClearConfirm = true
                        }
                        .foregroundColor(.red)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Clear all history?", isPresented: $showClearConfirm, titleVisibility: .visible) {
                Button("Clear History", role: .destructive) { onClear?() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This cannot be undone.")
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                .font(.system(size: 52))
                .foregroundColor(.secondary)
            Text("No History Yet")
                .font(.title3.bold())
            Text("Each recording session will appear here with date, duration, and location.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var summarySection: some View {
        Section {
            HStack(spacing: 0) {
                statCell(value: "\(totalSessions)", label: "Sessions")
                Divider().frame(height: 40)
                statCell(value: formatDuration(totalDuration), label: "Total Time")
                Divider().frame(height: 40)
                statCell(value: "\(log.filter { $0.latitude != nil }.count)", label: "With GPS")
            }
        } header: {
            Text("All Time")
        }
    }

    private func statCell(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.bold())
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var sessionsSection: some View {
        Section {
            ForEach(log) { entry in
                HistoryEntryRow(entry: entry)
            }
        } header: {
            Text("Sessions")
        }
    }

    private func formatDuration(_ t: TimeInterval) -> String {
        let h = Int(t) / 3600
        let m = (Int(t) % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m \(Int(t) % 60)s"
    }
}

struct HistoryEntryRow: View {
    let entry: RecordingHistoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.startDate, style: .date)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(entry.startDate, style: .time)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 16) {
                Label(formatDuration(entry.duration), systemImage: "clock")
                Label("\(entry.segmentCount) segment\(entry.segmentCount == 1 ? "" : "s")", systemImage: "film.stack")
            }
            .font(.caption)
            .foregroundColor(.secondary)

            if let address = entry.address {
                Label(address, systemImage: "mappin.and.ellipse")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            } else if entry.latitude != nil {
                Label("GPS recorded", systemImage: "location.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func formatDuration(_ t: TimeInterval) -> String {
        let h = Int(t) / 3600
        let m = (Int(t) % 3600) / 60
        let s = Int(t) % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}
