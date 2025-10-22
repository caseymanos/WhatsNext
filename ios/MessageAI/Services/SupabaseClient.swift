import Foundation
import Supabase

/// Singleton service for Supabase client access
final class SupabaseClientService {
    static let shared = SupabaseClientService()
    
    let client: SupabaseClient
    
    private init() {
        // Read from Info.plist
        guard let supabaseURL = Bundle.main.object(forInfoDictionaryKey: "SupabaseURL") as? String,
              let supabaseAnonKey = Bundle.main.object(forInfoDictionaryKey: "SupabaseAnonKey") as? String,
              let url = URL(string: supabaseURL) else {
            fatalError("Missing or invalid Supabase configuration in Info.plist")
        }
        
        self.client = SupabaseClient(
            supabaseURL: url,
            supabaseKey: supabaseAnonKey,
            options: SupabaseClientOptions(
                db: .init(schema: "public"),
                auth: .init(autoRefreshToken: true),
                global: .init(headers: ["X-Client-Info": "whatsnext-ios/1.0.0"])
            )
        )
    }
    
    /// Convenience access to auth
    var auth: AuthClient {
        client.auth
    }
    
    /// Convenience access to database
    var database: PostgrestClient {
        client.database
    }
    
    /// Convenience access to realtime
    var realtime: RealtimeClient {
        client.realtime
    }

    /// Convenience access to realtime V2
    var realtimeV2: RealtimeClientV2 {
        client.realtimeV2
    }

    /// Convenience access to storage
    var storage: SupabaseStorageClient {
        client.storage
    }
    
    /// Simple health check
    func healthCheck() async throws -> Bool {
        // Simple query to verify connection
        let response: [User] = try await database
            .from("users")
            .select()
            .limit(1)
            .execute()
            .value
        
        return true
    }
}

