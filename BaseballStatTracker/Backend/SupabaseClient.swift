import Foundation
import Supabase

/// Single Supabase client for the whole app.
///
/// The publishable key is safe to embed in the binary — it only grants
/// anon-role access. All sensitive ops (Anthropic calls, quota mutation,
/// StoreKit webhook ingest) run inside edge functions using the
/// service-role key, which never leaves the server.
enum SupabaseConfig {
    static let url = URL(string: "https://ifcsanqnrbefgsydcfgf.supabase.co")!
    static let publishableKey = "sb_publishable_mBHwTt6rT8XjL1ULvMZXDw_TEIgG-KI"
    static let storageBucket = "swing-media"
}

@MainActor
enum SupabaseService {
    static let client = SupabaseClient(
        supabaseURL: SupabaseConfig.url,
        supabaseKey: SupabaseConfig.publishableKey
    )
}
