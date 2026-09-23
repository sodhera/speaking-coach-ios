import Foundation

/// Public client configuration. Every value here is designed to ship inside
/// the app binary (publishable keys, public ids) — secrets live on the server.
enum AppConfig {
    static let supabaseURL = URL(string: "https://kaqimqvijjwzfajeazme.supabase.co")!
    static let supabaseAnonKey = "sb_publishable_RkLMCBjOK6GJkOZMl2m3BQ_uolTyZXd"
    static let apiBaseURL = URL(string: "https://dating-coach-sodheras-projects.vercel.app")!
    static let authCallback = URL(string: "com.sodhera.speakingcoach://auth-callback")!

    static let privacyURL = URL(string: "https://www.orecci.com/privacy-policy.html")!
    static let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
}
