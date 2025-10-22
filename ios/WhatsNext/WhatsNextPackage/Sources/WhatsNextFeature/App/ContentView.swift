import SwiftUI

public struct ContentView: View {
    @EnvironmentObject var authViewModel: AuthViewModel

    public init() {}

    public var body: some View {
        Group {
            if authViewModel.isAuthenticated {
                ConversationListView()
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

