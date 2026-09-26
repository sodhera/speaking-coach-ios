import Foundation
import Supabase

/// Where a user's `CoachProfile` lives:
/// 1. `user_metadata.coach_profile_v1` on the Supabase account — the source
///    of truth, restored on reinstall or a new phone. No schema change needed.
/// 2. The `profiles` table row the server and old app already use — kept in
///    step (name, language, goals) so nothing downstream loses its data.
/// 3. A per-user cache in UserDefaults, so launch never waits on the network.
enum ProfileService {
    private static let metadataKey = "coach_profile_v1"
    private static var auth: AuthClient { Backend.supabase.auth }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    // MARK: Cache

    static func cached(userID: UUID) -> CoachProfile? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey(userID)) else { return nil }
        return try? decoder.decode(CoachProfile.self, from: data)
    }

    static func cache(_ profile: CoachProfile?, userID: UUID) {
        if let profile, let data = try? encoder.encode(profile) {
            UserDefaults.standard.set(data, forKey: cacheKey(userID))
        } else {
            UserDefaults.standard.removeObject(forKey: cacheKey(userID))
        }
    }

    private static func cacheKey(_ userID: UUID) -> String { "sc.profile.\(userID.uuidString)" }

    // MARK: Remote

    /// The account's profile: the native metadata first, then a legacy
    /// `profiles` row from the old app, else nil (the user still needs setup).
    static func fetch(user: User) async -> CoachProfile? {
        let freshUser = (try? await auth.user()) ?? user
        if let json = freshUser.userMetadata[metadataKey],
           let data = try? encoder.encode(json),
           let profile = try? decoder.decode(CoachProfile.self, from: data) {
            return profile
        }
        return await legacyProfile(userID: freshUser.id)
    }

    static func save(_ profile: CoachProfile, userID: UUID) async {
        cache(profile, userID: userID)
        do {
            let json = try decoder.decode(AnyJSON.self, from: encoder.encode(profile))
            _ = try await auth.update(user: UserAttributes(data: [metadataKey: json]))
        } catch {
            AppLog.error("Profile metadata save failed: \(error.localizedDescription)")
        }
        do {
            try await Backend.supabase.from("profiles").upsert(ProfileRow(profile: profile, id: userID)).execute()
        } catch {
            AppLog.error("Profile row upsert failed: \(error.localizedDescription)")
        }
    }

    private static func legacyProfile(userID: UUID) async -> CoachProfile? {
        do {
            let rows: [LegacyRow] = try await Backend.supabase.from("profiles")
                .select("name, language, onboarded_at")
                .eq("id", value: userID)
                .limit(1)
                .execute()
                .value
            guard let row = rows.first, row.onboarded_at != nil else { return nil }
            return CoachProfile(
                name: row.name ?? "",
                language: row.language ?? AppLanguage.code,
                statements: [:],
                costs: [],
                outcomes: [],
                onboardedAt: .now,
                isLegacy: true
            )
        } catch {
            return nil
        }
    }

    private struct LegacyRow: Decodable {
        let name: String?
        let language: String?
        let onboarded_at: String?
    }

    /// The columns the existing `profiles` table has. Goals map from the
    /// outcomes the user chose, in the old app's vocabulary.
    private struct ProfileRow: Encodable {
        let id: UUID
        let name: String
        let language: String
        let goals: [String]
        let onboarded_at: String

        init(profile: CoachProfile, id: UUID) {
            self.id = id
            name = profile.name
            language = profile.language
            let mapped = profile.outcomes.map { outcome -> String in
                switch outcome {
                case .calm, .myself: "Confidence"
                case .clear, .fluent: "Clarity"
                case .getTheYes: "Assertiveness"
                }
            }
            goals = Array(NSOrderedSet(array: mapped.isEmpty ? ["Confidence"] : mapped)) as? [String] ?? ["Confidence"]
            onboarded_at = ISO8601DateFormatter().string(from: profile.onboardedAt)
        }
    }
}
