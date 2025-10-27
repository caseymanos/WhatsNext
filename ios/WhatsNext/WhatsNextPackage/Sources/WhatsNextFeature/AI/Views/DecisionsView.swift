import SwiftUI
#if AI_FEATURES

struct DecisionsView: View {
    @ObservedObject var viewModel: AIViewModel

    private var allDecisions: [Decision] {
        viewModel.decisionsByConversation.values.flatMap { $0 }
    }

    var body: some View {
        Group {
            if viewModel.isAnalyzing {
                ProgressView("Finding decisions...")
            } else if allDecisions.isEmpty {
                emptyState
            } else {
                decisionsList
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "list.bullet.clipboard")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("No decisions tracked")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("AI will extract family decisions from your conversations")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var decisionsList: some View {
        List {
            // Only show decisions for effectiveConversations (selected or all if none selected)
            // Sort conversations for consistent display order
            ForEach(Array(viewModel.effectiveConversations).sorted(), id: \.self) { convId in
                if let decisions = viewModel.decisionsByConversation[convId], !decisions.isEmpty {
                    Section(header: Text("Conversation \(convId.uuidString.prefix(4))")) {
                        ForEach(decisions) { decision in
                            decisionRow(decision)
                        }
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.effectiveConversations)
    }

    private func decisionRow(_ decision: Decision) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                categoryBadge(decision.category)
                Spacer()
                if let deadline = decision.deadline {
                    Text(deadline, style: .date)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Text(decision.decisionText)
                .font(.body)

            if decision.deadline != nil {
                HStack {
                    Image(systemName: "clock")
                        .font(.caption2)
                    Text("Deadline:")
                        .font(.caption)
                    if let deadline = decision.deadline {
                        Text(deadline, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func categoryBadge(_ category: Decision.DecisionCategory) -> some View {
        Text(category.rawValue.capitalized)
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(categoryColor(category).opacity(0.2))
            .foregroundStyle(categoryColor(category))
            .cornerRadius(4)
    }

    private func categoryColor(_ category: Decision.DecisionCategory) -> Color {
        switch category {
        case .activity: return .blue
        case .schedule: return .purple
        case .purchase: return .green
        case .policy: return .orange
        case .food: return .pink
        case .other: return .gray
        }
    }
}

#endif
