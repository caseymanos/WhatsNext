# iOS Integration Guide - Conflict Detection

**Status**: Backend deployed and operational
**Date**: October 25, 2025
**Worktree**: `/Users/caseymanos/GauntletAI/WhatsNext-conflict-detection`

---

## Overview

This guide documents how to integrate the conflict detection feature into the iOS app once the calendar sync integration work is complete.

## Backend Status

✅ **Deployed and Operational**
- Migration: `20251026120000_scheduling_conflicts.sql`
- Edge Function: `detect-conflicts-agent` (version 2, ACTIVE)
- Test Data: Created and verified
- Tools: 8 conflict detection tools fully functional

See [BACKEND_VERIFIED.md](./BACKEND_VERIFIED.md) for backend testing details.

---

## iOS Files to Create

### 1. ConflictDetectionService.swift

**Location**: `ios/WhatsNext/WhatsNextPackage/Sources/WhatsNextFeature/Services/ConflictDetectionService.swift`

```swift
import Foundation
import Supabase

/// Service for detecting scheduling conflicts using AI agent
@MainActor
final class ConflictDetectionService {
    private let supabase = SupabaseClientService.shared

    // MARK: - Conflict Detection

    /// Detect scheduling conflicts for a conversation
    /// - Parameters:
    ///   - conversationId: The conversation to analyze
    ///   - daysAhead: How many days ahead to check (default: 14)
    /// - Returns: Detected conflicts with AI summary
    func detectConflicts(
        conversationId: UUID,
        daysAhead: Int = 14
    ) async throws -> ConflictDetectionResult {
        struct RequestPayload: Encodable {
            let conversationId: UUID
            let daysAhead: Int
        }

        struct Response: Decodable {
            let summary: String
            let conflicts: [SchedulingConflict]
            let detectedCount: Int
        }

        let response: Response = try await supabase.functions
            .invoke(
                "detect-conflicts-agent",
                options: FunctionInvokeOptions(
                    body: RequestPayload(
                        conversationId: conversationId,
                        daysAhead: daysAhead
                    )
                )
            )

        return ConflictDetectionResult(
            summary: response.summary,
            conflicts: response.conflicts,
            detectedCount: response.detectedCount
        )
    }

    /// Fetch stored conflicts for a conversation
    func fetchConflicts(conversationId: UUID) async throws -> [SchedulingConflict] {
        let conflicts: [SchedulingConflict] = try await supabase.database
            .from("scheduling_conflicts")
            .select()
            .eq("conversation_id", value: conversationId)
            .order("severity")
            .order("created_at", ascending: false)
            .execute()
            .value

        return conflicts
    }

    /// Mark conflict as resolved
    func resolveConflict(
        conflictId: UUID,
        resolution: String,
        wasHelpful: Bool
    ) async throws {
        struct UpdatePayload: Encodable {
            let resolved: Bool
            let resolution: String
            let resolved_at: Date
        }

        // Update conflict
        try await supabase.database
            .from("scheduling_conflicts")
            .update(UpdatePayload(
                resolved: true,
                resolution: resolution,
                resolved_at: Date()
            ))
            .eq("id", value: conflictId)
            .execute()

        // Store feedback
        struct FeedbackPayload: Encodable {
            let conflict_id: UUID
            let was_helpful: Bool
            let resolution_chosen: String
        }

        try await supabase.database
            .from("resolution_feedback")
            .insert(FeedbackPayload(
                conflict_id: conflictId,
                was_helpful: wasHelpful,
                resolution_chosen: resolution
            ))
            .execute()
    }
}

// MARK: - Models

struct ConflictDetectionResult: Sendable {
    let summary: String
    let conflicts: [SchedulingConflict]
    let detectedCount: Int
}

struct SchedulingConflict: Identifiable, Codable, Sendable {
    let id: UUID
    let conversationId: UUID
    let conflictType: ConflictType
    let severity: Severity
    let description: String
    let suggestedResolution: String
    let affectedItems: [AffectedItem]
    let resolved: Bool
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case conversationId = "conversation_id"
        case conflictType = "conflict_type"
        case severity
        case description
        case suggestedResolution = "suggested_resolution"
        case affectedItems = "affected_items"
        case resolved
        case createdAt = "created_at"
    }

    enum ConflictType: String, Codable, Sendable {
        case timeOverlap = "time_overlap"
        case travelTime = "travel_time"
        case capacityOverload = "capacity_overload"
        case deadlineRisk = "deadline_risk"
        case noBuffer = "no_buffer"
    }

    enum Severity: String, Codable, Sendable {
        case urgent
        case high
        case medium
        case low

        var color: String {
            switch self {
            case .urgent: return "red"
            case .high: return "orange"
            case .medium: return "yellow"
            case .low: return "blue"
            }
        }
    }

    struct AffectedItem: Codable, Sendable {
        let type: String
        let id: UUID
        let title: String
        let date: String
    }
}
```

### 2. ConflictDetectionView.swift

**Location**: `ios/WhatsNext/WhatsNextPackage/Sources/WhatsNextFeature/AI/Views/ConflictDetectionView.swift`

```swift
import SwiftUI

struct ConflictDetectionView: View {
    let conversationId: UUID

    @State private var conflicts: [SchedulingConflict] = []
    @State private var aiSummary: String = ""
    @State private var isAnalyzing = false
    @State private var errorMessage: String?
    @State private var selectedConflict: SchedulingConflict?

    private let service = ConflictDetectionService()

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
            ConflictDetailView(conflict: conflict, service: service)
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
            let result = try await service.detectConflicts(conversationId: conversationId)
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

            if !conflict.resolved {
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
    let service: ConflictDetectionService

    @Environment(\.dismiss) private var dismiss
    @State private var resolution: String = ""
    @State private var isResolving = false

    var body: some View {
        NavigationStack {
            List {
                Section("Details") {
                    LabeledContent("Type", value: conflict.conflictType.displayName)
                    LabeledContent("Severity", value: conflict.severity.rawValue)
                    LabeledContent("Description", value: conflict.description)
                }

                Section("Affected Items") {
                    ForEach(conflict.affectedItems, id: \.id) { item in
                        VStack(alignment: .leading) {
                            Text(item.title)
                                .font(.headline)
                            Text(item.date)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("AI Suggestion") {
                    Text(conflict.suggestedResolution)
                }

                if !conflict.resolved {
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
            try await service.resolveConflict(
                conflictId: conflict.id,
                resolution: resolution,
                wasHelpful: true
            )
            dismiss()
        } catch {
            print("Failed to resolve conflict: \(error)")
        }
    }
}

extension SchedulingConflict.ConflictType {
    var displayName: String {
        switch self {
        case .timeOverlap: return "Time Overlap"
        case .travelTime: return "Travel Time Issue"
        case .capacityOverload: return "Schedule Overload"
        case .deadlineRisk: return "Deadline at Risk"
        case .noBuffer: return "No Buffer Time"
        }
    }
}
```

### 3. AITabView.swift Integration

**Location**: Modify existing `ios/WhatsNext/WhatsNextPackage/Sources/WhatsNextFeature/AI/Views/AITabView.swift`

Add to the `AIFeature` enum:
```swift
case conflicts = "Conflicts"
```

Add icon mapping:
```swift
case .conflicts: return "calendar.badge.exclamationmark"
```

Add to the feature content switch:
```swift
case .conflicts:
    if let firstConv = vm.selectedConversations.first ?? conversations.first?.id {
        ConflictDetectionView(conversationId: firstConv)
    } else {
        Text("Select a conversation to check for conflicts")
            .foregroundStyle(.secondary)
    }
```

---

## Integration Steps

1. **Wait for calendar sync work to complete** - Another agent is currently working on calendar sync integration

2. **Create the service file**:
   ```bash
   # Create ConflictDetectionService.swift with the code above
   ```

3. **Create the view file**:
   ```bash
   # Create ConflictDetectionView.swift with the code above
   ```

4. **Update AITabView.swift**:
   ```bash
   # Add conflicts case, icon, and view as shown above
   ```

5. **Build and test**:
   ```bash
   # Using XcodeBuildMCP tools
   build_run_sim_name_ws({
       workspacePath: "ios/WhatsNext/WhatsNext.xcworkspace",
       scheme: "WhatsNext",
       simulatorName: "iPhone 16"
   })
   ```

6. **Test the feature**:
   - Navigate to AI tab
   - Select "Conflicts" feature
   - Choose a conversation with calendar events
   - Tap "Analyze" to detect conflicts
   - Verify conflicts are displayed
   - Test resolving conflicts

---

## Backend Testing (Optional)

If you want to verify the backend before iOS integration:

```bash
cd /Users/caseymanos/GauntletAI/WhatsNext-conflict-detection
deno run --allow-net --allow-env test-agent.ts test@test.com <password>
```

Expected output:
- 7-8 conflicts detected
- Severity levels: 2 urgent, 2-3 high, 2 medium, 1 low
- AI summary with actionable recommendations
- Conflicts stored in database

---

## Notes

- Backend is fully deployed and operational on Supabase project `wgptkitofarpdyhmmssx`
- Test data includes 17 calendar events and 3 deadlines
- Edge function uses GPT-4o with 8 specialized conflict detection tools
- See [BACKEND_VERIFIED.md](./BACKEND_VERIFIED.md) for complete backend documentation
- See [CONFLICT_DETECTION_TEST_PLAN.md](./CONFLICT_DETECTION_TEST_PLAN.md) for test scenarios

---

## Troubleshooting

### Common Issues

1. **"Function not found"**
   - Verify edge function is deployed: Check Supabase dashboard
   - Ensure you're calling the correct project

2. **"No conflicts detected" when you expect some**
   - Check test data exists in calendar_events table
   - Verify conversation_id matches your test data
   - Check edge function logs for errors

3. **Build errors**
   - Ensure all calendar sync changes are complete
   - Verify Supabase client is properly configured
   - Check that CalendarEvent model has all required fields

### Debugging

View edge function logs:
```bash
# In Supabase dashboard
https://supabase.com/dashboard/project/wgptkitofarpdyhmmssx/logs/edge-functions?fn=detect-conflicts-agent
```

Check stored conflicts:
```sql
SELECT conflict_type, severity, description, suggested_resolution
FROM scheduling_conflicts
WHERE conversation_id = 'YOUR_CONVERSATION_ID'
ORDER BY severity, created_at DESC;
```
