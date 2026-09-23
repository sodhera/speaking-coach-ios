import Foundation
import Supabase

/// The one Supabase client. Sessions persist in the Keychain (the SDK's
/// default) and the stored session is emitted immediately on launch, so a
/// returning user never sees the welcome screen flash.
enum Backend {
    static let supabase = SupabaseClient(
        supabaseURL: AppConfig.supabaseURL,
        supabaseKey: AppConfig.supabaseAnonKey,
        options: SupabaseClientOptions(
            auth: .init(emitLocalSessionAsInitialSession: true)
        )
    )
}
