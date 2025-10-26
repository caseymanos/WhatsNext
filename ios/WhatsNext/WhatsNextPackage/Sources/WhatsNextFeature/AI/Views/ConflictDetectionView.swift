import SwiftUI

struct ConflictDetectionView: View {
    let conversationId: UUID

    @State private var conflicts: [SchedulingConflict] = []
    @State private var aiSummary: String = ""
    @State private var isAnalyzing = false
    @State private var errorMessage: String?
    @State private var selectedConflict: SchedulingConflict?

    private let service = ConflictDetectionService.shared

    var body: some View {
        Group {
            if isAnalyzing {
                ProgressView("Analyzing schedule for conflicts...")
            } else if let error = errorMessage {
                errorView(error)
            } else if conflicts.isEmpty {
                emptyStateView
            } else {
                conflictListView
            }
        }
        .task {
            await analyzeConflicts()
        }
        .refreshable {
            await analyzeConflicts()
        }
        .sheet(item: $selectedConflict) { conflict in
            ConflictDetailView(conflict: conflict)
        }
    }

    private var conflictListView: some View {
        List {
            if !aiSummary.isEmpty {
                Section("AI Analysis") {
                    Text(aiSummary)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Detected Conflicts (\(conflicts.count))") {
                ForEach(conflicts) { conflict in
                    ConflictRow(conflict: conflict)
                        .onTapGesture {
                            selectedConflict = conflict
                        }
                }
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 60))
                .foregroundStyle(.green)
            Text("No conflicts detected")
                .font(.headline)
            Text("Your schedule looks good!")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundStyle(.orange)
            Text("Analysis Failed")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task { await analyzeConflicts() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func analyzeConflicts() async {
        isAnalyzing = true
        errorMessage = nil
        defer { isAnalyzing = false }

        do {
            let result = try await service.detectConflicts(
                conversationId: conversationId,
                daysAhead: 14
            )
            conflicts = result.conflicts
            aiSummary = result.summary
        } catch {
            errorMessage = error.localizedDescription
            print("Conflict detection failed: \(error)")
        }
    }
}

struct ConflictRow: View {
    let conflict: SchedulingConflict

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: severityIcon)
                    .foregroundStyle(severityColor)
                Text(conflict.conflictType.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(conflict.severity.rawValue.uppercased())
                    .font(.caption2.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(severityColor.opacity(0.2))
                    .foregroundStyle(severityColor)
                    .cornerRadius(4)
            }

            Text(conflict.description)
                .font(.body)

            if conflict.status == .unresolved {
                Label(conflict.suggestedResolution, systemImage: "lightbulb")
                    .font(.caption)
                    .foregroundStyle(.blue)
            } else {
                Label("Resolved", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
        .padding(.vertical, 4)
    }

    private var severityIcon: String {
        switch conflict.severity {
        case .urgent: return "exclamationmark.triangle.fill"
        case .high: return "exclamationmark.circle.fill"
        case .medium: return "exclamationmark.circle"
        case .low: return "info.circle"
        }
    }

    private var severityColor: Color {
        switch conflict.severity {
        case .urgent: return .red
        case .high: return .orange
        case .medium: return .yellow
        case .low: return .blue
        }
    }
}

struct ConflictDetailView: View {
    let conflict: SchedulingConflict

    @Environment(\.dismiss) private var dismiss
    @State private var resolution: String = ""
    @State private var isResolving = false

    private let service = ConflictDetectionService.shared

    var body: some View {
        NavigationStack {
            List {
                Section("Details") {
                    LabeledContent("Type", value: conflict.conflictType.displayName)
                    LabeledContent("Severity", value: conflict.severity.rawValue)
                    LabeledContent("Description", value: conflict.description)
                }

                Section("Affected Items") {
                    ForEach(conflict.affectedItems, id: \.self) { item in
                        VStack(alignment: .leading) {
                            Text(item)
                                .font(.headline)
                        }
                    }
                }

                Section("AI Suggestion") {
                    Text(conflict.suggestedResolution)
                }

                if conflict.status == .unresolved {
                    Section("Resolve Conflict") {
                        TextField("What did you do to resolve this?", text: $resolution)
                        Button("Mark as Resolved") {
                            Task { await resolveConflict() }
                        }
                        .disabled(resolution.isEmpty || isResolving)
                    }
                }
            }
            .navigationTitle("Conflict Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func resolveConflict() async {
        isResolving = true
        defer { isResolving = false }

        do {
            // Update conflict status in database
            let supabase = SupabaseClientService.shared.client
            let now = ISO8601DateFormatter().string(from: Date())

            try await supabase.database
                .from("scheduling_conflicts")
                .update([
                    "status": SchedulingConflict.Status.resolved.rawValue,
                    "resolution": resolution,
                    "resolved_at": now
                ])
                .eq("id", value: conflict.id)
                .execute()

            dismiss()
        } catch {
            print("Failed to resolve conflict: \(error)")
        }
    }
}
