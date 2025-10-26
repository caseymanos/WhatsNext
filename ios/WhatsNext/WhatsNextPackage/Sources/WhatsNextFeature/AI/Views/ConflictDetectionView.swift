import SwiftUI

struct ConflictDetectionView: View {
    let conversationId: UUID

    @State private var allConflicts: [SchedulingConflict] = []
    @State private var isAnalyzing = false
    @State private var errorMessage: String?
    @State private var selectedConflict: SchedulingConflict?
    @State private var selectedTab: ConflictTab = .unresolved

    enum ConflictTab {
        case unresolved
        case resolved
    }

    private let service = ConflictDetectionService.shared

    private var filteredConflicts: [SchedulingConflict] {
        allConflicts.filter { conflict in
            switch selectedTab {
            case .unresolved:
                return conflict.status == .unresolved
            case .resolved:
                return conflict.status == .resolved
            }
        }
    }

    var body: some View {
        Group {
            if isAnalyzing {
                ProgressView("Analyzing schedule for conflicts...")
            } else if let error = errorMessage {
                errorView(error)
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
            ConflictDetailView(conflict: conflict, conversationId: conversationId) {
                // Refresh after resolving
                Task { await loadAllConflicts() }
            }
        }
    }

    private var conflictListView: some View {
        VStack(spacing: 0) {
            // Tab picker
            Picker("Status", selection: $selectedTab) {
                Text("Unresolved (\(allConflicts.filter { $0.status == .unresolved }.count))")
                    .tag(ConflictTab.unresolved)
                Text("Resolved (\(allConflicts.filter { $0.status == .resolved }.count))")
                    .tag(ConflictTab.resolved)
            }
            .pickerStyle(.segmented)
            .padding()

            if filteredConflicts.isEmpty {
                emptyStateView
            } else {
                List {
                    ForEach(filteredConflicts) { conflict in
                        Button {
                            selectedConflict = conflict
                        } label: {
                            ConflictRow(conflict: conflict)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: selectedTab == .unresolved ? "checkmark.circle" : "tray")
                .font(.system(size: 60))
                .foregroundStyle(selectedTab == .unresolved ? .green : .secondary)
            Text(selectedTab == .unresolved ? "No conflicts detected" : "No resolved conflicts")
                .font(.headline)
            Text(selectedTab == .unresolved ? "Your schedule looks good!" : "Resolved conflicts will appear here")
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
            // Run fresh analysis
            _ = try await service.detectConflicts(
                conversationId: conversationId,
                daysAhead: 14
            )
            // Load all conflicts (unresolved + resolved)
            await loadAllConflicts()
        } catch {
            errorMessage = error.localizedDescription
            print("Conflict detection failed: \(error)")
        }
    }

    private func loadAllConflicts() async {
        do {
            let supabase = SupabaseClientService.shared.client

            // Fetch all conflicts for this conversation (both unresolved and resolved)
            let response: [SchedulingConflictResponse] = try await supabase
                .from("scheduling_conflicts")
                .select()
                .eq("conversation_id", value: conversationId.uuidString)
                .order("created_at", ascending: false)
                .execute()
                .value

            allConflicts = try response.map { try $0.toDomain() }
        } catch {
            print("Failed to load conflicts: \(error)")
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

            Text(formattedDescription)
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

    private var formattedDescription: String {
        var result = conflict.description

        // Replace all dates in format "YYYY-MM-DD" with formatted dates like "Monday, October 27"
        let datePattern = #"\d{4}-\d{2}-\d{2}"#
        if let dateRegex = try? NSRegularExpression(pattern: datePattern) {
            let inputFormatter = DateFormatter()
            inputFormatter.dateFormat = "yyyy-MM-dd"

            let outputFormatter = DateFormatter()
            outputFormatter.dateFormat = "EEEE, MMMM d"

            // Find all date matches in reverse order to avoid offset issues
            let matches = dateRegex.matches(in: result, range: NSRange(result.startIndex..., in: result))

            for match in matches.reversed() {
                guard let range = Range(match.range, in: result) else { continue }
                let dateString = String(result[range])

                if let date = inputFormatter.date(from: dateString) {
                    let formattedDateStr = outputFormatter.string(from: date)
                    result.replaceSubrange(range, with: formattedDateStr)
                }
            }
        }

        // Replace all times in format "HH:mm:ss" with formatted times like "3:00 PM"
        let timePattern = #"\d{2}:\d{2}:\d{2}"#
        if let timeRegex = try? NSRegularExpression(pattern: timePattern) {
            let inputFormatter = DateFormatter()
            inputFormatter.dateFormat = "HH:mm:ss"

            let outputFormatter = DateFormatter()
            outputFormatter.dateFormat = "h:mm a"

            // Find all time matches in reverse order to avoid offset issues
            let matches = timeRegex.matches(in: result, range: NSRange(result.startIndex..., in: result))

            for match in matches.reversed() {
                guard let range = Range(match.range, in: result) else { continue }
                let timeString = String(result[range])

                if let date = inputFormatter.date(from: timeString) {
                    let formattedTimeStr = outputFormatter.string(from: date)
                    result.replaceSubrange(range, with: formattedTimeStr)
                }
            }
        }

        return result
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
    let conversationId: UUID
    let onResolve: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var resolution: String = ""
    @State private var isResolving = false
    @State private var conversation: Conversation?
    @State private var events: [CalendarEvent] = []

    private let service = ConflictDetectionService.shared

    var body: some View {
        NavigationStack {
            List {
                // Conversation context
                if let conversation = conversation {
                    Section("From Conversation") {
                        HStack {
                            if conversation.isGroup {
                                Image(systemName: "person.3.fill")
                                Text(conversation.name ?? "Group Chat")
                                    .font(.headline)
                            } else {
                                Image(systemName: "person.fill")
                                Text(conversationDisplayName)
                                    .font(.headline)
                            }
                        }
                    }
                }

                Section("Details") {
                    LabeledContent("Type", value: conflict.conflictType.displayName)
                    LabeledContent("Severity", value: conflict.severity.rawValue.capitalized)
                    LabeledContent("Date", value: formattedDate)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Description")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(formattedDescription)
                    }
                }

                Section("Affected Items") {
                    ForEach(conflict.affectedItems, id: \.self) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item)
                                .font(.headline)
                            if let time = findEventTime(for: item) {
                                Text("Time: \(time)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                Section("AI Suggestion") {
                    Text(conflict.suggestedResolution)
                }

                if conflict.status == .unresolved {
                    Section("Resolve Conflict") {
                        TextField("What did you do to resolve this?", text: $resolution, axis: .vertical)
                            .lineLimit(3...6)
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
            .task {
                await loadConversationDetails()
                await loadEvents()
            }
        }
    }

    private var conversationDisplayName: String {
        guard let conversation = conversation,
              !conversation.isGroup,
              let participants = conversation.participants else {
            return "Direct Message"
        }

        // Find the other participant (not current user)
        if let otherParticipant = participants.first(where: { $0.id != conflict.userId }) {
            return otherParticipant.displayName ?? otherParticipant.username ?? "User"
        }

        return "Direct Message"
    }

    private var formattedDate: String {
        // Extract date from description (e.g., "2025-10-27")
        let datePattern = #"\d{4}-\d{2}-\d{2}"#
        guard let regex = try? NSRegularExpression(pattern: datePattern),
              let match = regex.firstMatch(in: conflict.description, range: NSRange(conflict.description.startIndex..., in: conflict.description)),
              let range = Range(match.range, in: conflict.description) else {
            return ""
        }

        let dateString = String(conflict.description[range])

        // Parse and format
        let inputFormatter = DateFormatter()
        inputFormatter.dateFormat = "yyyy-MM-dd"

        guard let date = inputFormatter.date(from: dateString) else {
            return dateString
        }

        let outputFormatter = DateFormatter()
        outputFormatter.dateFormat = "EEEE, MMMM d"
        return outputFormatter.string(from: date)
    }

    private var formattedDescription: String {
        var result = conflict.description

        // Replace all dates in format "YYYY-MM-DD" with formatted dates like "Monday, October 27"
        let datePattern = #"\d{4}-\d{2}-\d{2}"#
        if let dateRegex = try? NSRegularExpression(pattern: datePattern) {
            let inputFormatter = DateFormatter()
            inputFormatter.dateFormat = "yyyy-MM-dd"

            let outputFormatter = DateFormatter()
            outputFormatter.dateFormat = "EEEE, MMMM d"

            // Find all date matches in reverse order to avoid offset issues
            let matches = dateRegex.matches(in: result, range: NSRange(result.startIndex..., in: result))

            for match in matches.reversed() {
                guard let range = Range(match.range, in: result) else { continue }
                let dateString = String(result[range])

                if let date = inputFormatter.date(from: dateString) {
                    let formattedDateStr = outputFormatter.string(from: date)
                    result.replaceSubrange(range, with: formattedDateStr)
                }
            }
        }

        // Replace all times in format "HH:mm:ss" with formatted times like "3:00 PM"
        let timePattern = #"\d{2}:\d{2}:\d{2}"#
        if let timeRegex = try? NSRegularExpression(pattern: timePattern) {
            let inputFormatter = DateFormatter()
            inputFormatter.dateFormat = "HH:mm:ss"

            let outputFormatter = DateFormatter()
            outputFormatter.dateFormat = "h:mm a"

            // Find all time matches in reverse order to avoid offset issues
            let matches = timeRegex.matches(in: result, range: NSRange(result.startIndex..., in: result))

            for match in matches.reversed() {
                guard let range = Range(match.range, in: result) else { continue }
                let timeString = String(result[range])

                if let date = inputFormatter.date(from: timeString) {
                    let formattedTimeStr = outputFormatter.string(from: date)
                    result.replaceSubrange(range, with: formattedTimeStr)
                }
            }
        }

        return result
    }

    private func findEventTime(for eventTitle: String) -> String? {
        // Try exact match first
        if let event = events.first(where: { $0.title == eventTitle }) {
            return formatTime(event.time)
        }

        // Try case-insensitive match
        if let event = events.first(where: { $0.title.lowercased() == eventTitle.lowercased() }) {
            return formatTime(event.time)
        }

        // Try contains match
        if let event = events.first(where: { $0.title.contains(eventTitle) || eventTitle.contains($0.title) }) {
            return formatTime(event.time)
        }

        return nil
    }

    private func formatTime(_ time: String?) -> String? {
        guard let time = time else { return nil }

        // Parse time from "HH:mm:ss" or "HH:mm" format
        let inputFormatter = DateFormatter()
        inputFormatter.dateFormat = time.contains(":") && time.split(separator: ":").count == 3 ? "HH:mm:ss" : "HH:mm"

        guard let date = inputFormatter.date(from: time) else {
            return time // Return original if parsing fails
        }

        // Format to 12-hour with AM/PM
        let outputFormatter = DateFormatter()
        outputFormatter.dateFormat = "h:mm a"
        return outputFormatter.string(from: date)
    }

    private func loadConversationDetails() async {
        do {
            let service = ConversationService()
            conversation = try await service.fetchConversation(conversationId: conversationId)
        } catch {
            print("Failed to load conversation: \(error)")
        }
    }

    private func loadEvents() async {
        do {
            let supabase = SupabaseClientService.shared.client

            // Fetch calendar events for this conversation
            let response: [CalendarEvent] = try await supabase
                .from("calendar_events")
                .select()
                .eq("conversation_id", value: conversationId.uuidString)
                .execute()
                .value

            events = response
        } catch {
            print("Failed to load events: \(error)")
        }
    }

    private func resolveConflict() async {
        isResolving = true
        defer { isResolving = false }

        do {
            // Update conflict status in database
            let supabase = SupabaseClientService.shared.client
            let dateFormatter = ISO8601DateFormatter()
            dateFormatter.formatOptions.insert(.withFractionalSeconds)
            let now = dateFormatter.string(from: Date())

            try await supabase
                .from("scheduling_conflicts")
                .update([
                    "status": SchedulingConflict.Status.resolved.rawValue,
                    "resolution": resolution,
                    "resolved_at": now
                ])
                .eq("id", value: conflict.id)
                .execute()

            onResolve()
            dismiss()
        } catch {
            print("Failed to resolve conflict: \(error)")
        }
    }
}
