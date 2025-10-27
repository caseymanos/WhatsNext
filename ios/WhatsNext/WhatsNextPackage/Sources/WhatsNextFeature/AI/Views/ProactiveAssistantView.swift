import SwiftUI
#if AI_FEATURES

struct ProactiveAssistantView: View {
    @ObservedObject var viewModel: AIViewModel
    @State private var queryText = ""
    let conversationId: UUID

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isAnalyzing {
                ProgressView("AI is thinking...")
                    .padding()
            } else if let error = viewModel.errorMessage {
                errorView(error)
            } else if let insights = viewModel.proactiveInsights {
                insightsView(insights)
            } else {
                emptyState
            }

            Divider()

            queryInputBar
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundStyle(.red)
            Text("Error")
                .font(.headline)
                .foregroundStyle(.primary)
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button("Try Again") {
                viewModel.errorMessage = nil
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("Proactive Assistant")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Ask AI to analyze your conversation and provide insights")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button("Analyze Now") {
                Task {
                    await viewModel.runProactiveAssistant(conversationId: conversationId)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func insightsView(_ response: ProactiveAssistantResponse) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // AI Summary
                summaryCard(response.message)

                // Upcoming Events
                if !response.insights.upcomingEvents.isEmpty {
                    insightSection(
                        title: "Upcoming Events",
                        icon: "calendar",
                        color: .blue,
                        count: response.insights.upcomingEvents.count
                    ) {
                        ForEach(response.insights.upcomingEvents) { event in
                            eventCard(event)
                        }
                    }
                }

                // Pending RSVPs
                if !response.insights.pendingRSVPs.isEmpty {
                    insightSection(
                        title: "Pending RSVPs",
                        icon: "envelope.badge",
                        color: .orange,
                        count: response.insights.pendingRSVPs.count
                    ) {
                        ForEach(response.insights.pendingRSVPs) { rsvp in
                            rsvpCard(rsvp)
                        }
                    }
                }

                // Upcoming Deadlines
                if !response.insights.upcomingDeadlines.isEmpty {
                    insightSection(
                        title: "Upcoming Deadlines",
                        icon: "clock.badge",
                        color: .red,
                        count: response.insights.upcomingDeadlines.count
                    ) {
                        ForEach(response.insights.upcomingDeadlines) { deadline in
                            deadlineCard(deadline)
                        }
                    }
                }

                // Scheduling Conflicts
                if !response.insights.schedulingConflicts.isEmpty {
                    insightSection(
                        title: "Scheduling Conflicts",
                        icon: "exclamationmark.triangle",
                        color: .red,
                        count: response.insights.schedulingConflicts.count
                    ) {
                        ForEach(response.insights.schedulingConflicts, id: \.self) { conflict in
                            conflictCard(conflict)
                        }
                    }
                }

                // Tools Used
                if !response.toolsUsed.isEmpty {
                    toolsSection(response.toolsUsed)
                }
            }
            .padding()
        }
    }

    private func summaryCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(.yellow)
                Text("AI Summary")
                    .font(.headline)
            }
            Text(message)
                .font(.body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private func insightSection<Content: View>(
        title: String,
        icon: String,
        color: Color,
        count: Int,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.headline)
                    .foregroundStyle(color)
                Spacer()
                Text("\(count)")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            content()
        }
    }

    private func eventCard(_ event: CalendarEvent) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(event.title)
                .font(.subheadline.bold())
            Text(event.date, style: .date)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.blue.opacity(0.1))
        .cornerRadius(8)
    }

    private func rsvpCard(_ rsvp: RSVPTracking) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(rsvp.eventName)
                .font(.subheadline.bold())
            if let deadline = rsvp.deadline {
                Text("RSVP by: \(deadline, style: .relative)")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
    }

    private func deadlineCard(_ deadline: Deadline) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(deadline.task)
                .font(.subheadline.bold())
            Text(deadline.deadline, style: .relative)
                .font(.caption)
                .foregroundStyle(.red)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.red.opacity(0.1))
        .cornerRadius(8)
    }

    private func conflictCard(_ conflict: ProactiveAssistantResponse.SchedulingConflict) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Conflict on \(conflict.date)")
                .font(.subheadline.bold())
            Text("\(conflict.event1) vs \(conflict.event2)")
                .font(.caption)
            Text(conflict.reason)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.red.opacity(0.1))
        .cornerRadius(8)
    }

    private func toolsSection(_ tools: [ProactiveAssistantResponse.ToolExecution]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tools Used")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            HStack {
                ForEach(tools, id: \.tool) { tool in
                    Text(tool.tool)
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.systemGray5))
                        .cornerRadius(4)
                }
            }
        }
    }

    private var queryInputBar: some View {
        HStack(spacing: 12) {
            TextField("Ask AI a question...", text: $queryText)
                .textFieldStyle(.roundedBorder)

            Button {
                guard !queryText.isEmpty else { return }
                Task {
                    await viewModel.runProactiveAssistant(conversationId: conversationId, query: queryText)
                    queryText = ""
                }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .disabled(queryText.isEmpty || viewModel.isAnalyzing)
        }
        .padding()
        .background(Color(.systemBackground))
    }
}

#endif
