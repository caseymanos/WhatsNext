import SwiftUI

public struct ContentView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var globalRealtimeManager: GlobalRealtimeManager

    public init() {}

    public var body: some View {
        Group {
            // Only show ConversationListView after GlobalRealtimeManager is active
            if authViewModel.isAuthenticated && globalRealtimeManager.isActive {
                ConversationListView()
            } else if authViewModel.isAuthenticated {
                // User is authenticated but GlobalRealtimeManager not ready yet
                ProgressView("Connecting...")
            } else {
                LoginView()
            }
        }
        .onOpenURL { url in
            Task {
                do {
                    try await SupabaseClientService.shared.auth.session(from: url)
                } catch {
                    print("Failed to handle auth URL: \(error)")
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthViewModel())
}

