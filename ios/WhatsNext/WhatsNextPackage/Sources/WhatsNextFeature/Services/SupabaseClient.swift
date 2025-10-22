import Foundation
import Supabase

/// Singleton service for Supabase client access
public final class SupabaseClientService: Sendable {
    public static let shared = SupabaseClientService()

    let client: SupabaseClient
    
    private init() {
        // Read from bundled Config.plist in package resources
        guard let configURL = Bundle.module.url(forResource: "Config", withExtension: "plist"),
              let configData = try? Data(contentsOf: configURL),
              let config = try? PropertyListSerialization.propertyList(from: configData, format: nil) as? [String: String],
              let supabaseURL = config["SupabaseURL"],
              let supabaseAnonKey = config["SupabaseAnonKey"],
              let url = URL(string: supabaseURL) else {
            fatalError("Missing or invalid Supabase configuration in Config.plist")
        }
        
        self.client = SupabaseClient(
            supabaseURL: url,
            supabaseKey: supabaseAnonKey,
            options: SupabaseClientOptions(
                db: .init(schema: "public"),
                auth: .init(
                    redirectToURL: URL(string: "com.gauntletai.whatsnext://login-callback"),
                    autoRefreshToken: true
                ),
                global: .init(headers: ["X-Client-Info": "whatsnext-ios/1.0.0"])
            )
        )
    }
    
    /// Convenience access to auth
    public var auth: AuthClient {
        client.auth
    }

    /// Convenience access to database
    public var database: PostgrestClient {
        client.database
    }

    /// Convenience access to realtime
    public var realtime: RealtimeClient {
        client.realtime
    }

    /// Convenience access to realtime V2
    public var realtimeV2: RealtimeClientV2 {
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

