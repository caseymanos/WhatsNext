import SwiftUI

#if AI_FEATURES

struct ConflictDetectionView: View {
    @Environment(\.colorScheme) var colorScheme
    let conversationId: UUID

    @State private var result: ConflictDetectionService.ConflictAnalysisResult?
    @State private var isAnalyzing = false
    @State private var error: String?

    var body: some View {
        Group {
            if isAnalyzing {
                ProgressView("Detecting conflicts...")
            } else if let error {
                errorView(error)
            } else if let result {
                conflictsView(result)
            } else {
                emptyStateView
            }
        }
        .task {
            await analyzeConflicts()
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("Analyze this conversation for scheduling conflicts")
                .font(.headline)
                .foregroundStyle(.secondary)

            Button {
                Task { await analyzeConflicts() }
            } label: {
                Label("Detect Conflicts", systemImage: "sparkles")
                    .font(.subheadline.bold())
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .cornerRadius(8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundStyle(.red)
            Text("Error")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Try Again") {
                Task { await analyzeConflicts() }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func conflictsView(_ result: ConflictDetectionService.ConflictAnalysisResult) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "sparkles")
                            .foregroundStyle(.blue)
                        Text("AI Analysis")
                            .font(.headline)
                    }

                    Text(result.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 20) {
                        StatPill(
                            icon: "exclamationmark.triangle",
                            label: "\(result.conflicts.count)",
                            sublabel: "conflicts"
                        )
                        StatPill(
                            icon: "cpu",
                            label: "\(result.stepsUsed)",
                            sublabel: "AI steps"
                        )
                    }
                }
                .padding(.vertical, 8)
            }

            if result.conflicts.isEmpty {
                Section {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("No conflicts detected! Your schedule looks good.")
                            .font(.subheadline)
                    }
                    .padding(.vertical, 8)
                }
            } else {
                Section("Detected Conflicts") {
                    ForEach(result.conflicts.sorted(by: { $0.severity.sortOrder < $1.severity.sortOrder })) { conflict in
                        ConflictCard(conflict: conflict)
                    }
                }
            }
        }
    }

    private func analyzeConflicts() async {
        isAnalyzing = true
        error = nil

        defer { isAnalyzing = false }

        do {
            result = try await ConflictDetectionService.shared.detectConflicts(
                conversationId: conversationId,
                daysAhead: 14
            )
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct ConflictCard: View {
    let conflict: SchedulingConflict

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with type and severity
            HStack {
                Image(systemName: conflict.conflictType.icon)
                    .foregroundStyle(colorForSeverity(conflict.severity))

                VStack(alignment: .leading, spacing: 2) {
                    Text(conflict.conflictType.displayName)
                        .font(.headline)

                    Text(conflict.severity.rawValue.uppercased())
                        .font(.caption2.bold())
                        .foregroundStyle(colorForSeverity(conflict.severity))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(colorForSeverity(conflict.severity).opacity(0.2))
                        .cornerRadius(4)
                }

                Spacer()
            }

            // Description
            Text(conflict.description)
                .font(.subheadline)
                .foregroundStyle(.primary)

            // Affected items
            if !conflict.affectedItems.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Affects:")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)

                    ForEach(conflict.affectedItems, id: \.self) { item in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.secondary)
                                .frame(width: 4, height: 4)
                            Text(item)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            // Suggestion
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "lightbulb")
                    .font(.caption)
                    .foregroundStyle(.blue)

                Text(conflict.suggestedResolution)
                    .font(.caption)
                    .foregroundStyle(.blue)
            }
            .padding(8)
            .background(Color.blue.opacity(0.1))
            .cornerRadius(6)
        }
        .padding(.vertical, 4)
    }

    private func colorForSeverity(_ severity: SchedulingConflict.Severity) -> Color {
        switch severity {
        case .urgent: return .red
        case .high: return .orange
        case .medium: return .yellow
        case .low: return .green
        }
    }
}

struct StatPill: View {
    let icon: String
    let label: String
    let sublabel: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(.caption.bold())
                Text(sublabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.systemGray6))
        .cornerRadius(6)
    }
}

#endif
