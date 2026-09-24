import Foundation

/// Public client configuration. Every value here is designed to ship inside
/// the app binary (publishable keys, public ids) — secrets live on the server.
enum AppConfig {
    static let supabaseURL = URL(string: "https://kaqimqvijjwzfajeazme.supabase.co")!
    static let supabaseAnonKey = "sb_publishable_RkLMCBjOK6GJkOZMl2m3BQ_uolTyZXd"
    static let apiBaseURL = URL(string: "https://dating-coach-sodheras-projects.vercel.app")!
    /// The two ElevenLabs voice partners (public agent ids). Custom
    /// situations fetch their own token for these; catalog rehearsals get
    /// theirs from the practice server.
    static let femaleAgentID = "agent_2901kqyrw41rfsmrfxdvsmk1pn6b"
    static let maleAgentID = "agent_8801kqz4fh4sfy2vrxazg3nacksn"
    // Keep the callback already registered with Supabase for the existing app.
    static let authCallback = URL(string: "dating-coach://auth/callback")!

    static let privacyURL = URL(string: "https://www.orecci.com/privacy-policy.html")!
    static let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
}
