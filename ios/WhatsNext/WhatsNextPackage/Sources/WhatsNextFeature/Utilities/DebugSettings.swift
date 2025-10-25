import Foundation

@MainActor
final class DebugSettings: ObservableObject {
    static let shared = DebugSettings()

    enum ForcedError: String, CaseIterable, Identifiable {
        case none
        case offline
        case serverUnavailable
        case rateLimited
        case unauthorized
        case invalidRequest
        case unknown

        var id: String { rawValue }
    }

    @Published var forcedError: ForcedError = .none

    // Runtime AI toggle
    @Published var aiEnabled: Bool {
        didSet { UserDefaults.standard.set(aiEnabled, forKey: "aiEnabled") }
    }

    // Choose between live AI (Supabase Edge) and mock
    @Published var useLiveAI: Bool {
        didSet { UserDefaults.standard.set(useLiveAI, forKey: "useLiveAI") }
    }

    @Published var stickyError = false
    @Published var retryAfterSeconds: Int = 10

    private init() {
        // Check if this is first launch after settings reset
        let hasResetSettings = UserDefaults.standard.bool(forKey: "hasResetDebugSettings_v1")
        if !hasResetSettings {
            // Clear old values to ensure clean state
            UserDefaults.standard.removeObject(forKey: "aiEnabled")
            UserDefaults.standard.removeObject(forKey: "useLiveAI")
            UserDefaults.standard.set(true, forKey: "hasResetDebugSettings_v1")
        }

        self.aiEnabled = UserDefaults.standard.object(forKey: "aiEnabled") as? Bool ?? false
        self.useLiveAI = UserDefaults.standard.object(forKey: "useLiveAI") as? Bool ?? true
    }

    /// Reset all debug settings to defaults
    func resetToDefaults() {
        aiEnabled = false
        useLiveAI = true
        forcedError = .none
        stickyError = false
        retryAfterSeconds = 10
    }
}


