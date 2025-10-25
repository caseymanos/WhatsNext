import Foundation
import SwiftUI

public struct AvatarService {
    /// Generate initials from display name
    /// - "John Doe" → "JD"
    /// - "John" → "J"
    /// - nil/empty → "?"
    public static func initials(from displayName: String?) -> String {
        guard let name = displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else {
            return "?"
        }

        let words = name.split(separator: " ")
        if words.count >= 2 {
            // Multiple words: first letter of first two words
            return String(words[0].prefix(1) + words[1].prefix(1)).uppercased()
        } else {
            // Single word: first letter only
            return String(name.prefix(1)).uppercased()
        }
    }

    /// Generate consistent color for user based on ID
    public static func color(for userId: UUID) -> Color {
        let colors: [Color] = [.blue, .purple, .green, .orange, .pink, .teal]
        let hash = abs(userId.hashValue)
        let index = hash % colors.count
        return colors[index]
    }

    /// Generate consistent color for display name (fallback if no UUID)
    public static func color(for displayName: String) -> Color {
        let colors: [Color] = [.blue, .purple, .green, .orange, .pink, .teal]
        let hash = abs(displayName.hashValue)
        let index = hash % colors.count
        return colors[index]
    }
}
