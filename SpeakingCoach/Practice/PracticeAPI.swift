import Foundation
import Supabase

enum PracticeAPIError: LocalizedError {
    case signedOut
    case subscriptionRequired
    case server(status: Int, message: String)
    case offline

    var errorDescription: String? {
        switch self {
        case .signedOut: "Please sign in again to practice."
        case .subscriptionRequired: "Your plan isn't active right now."
        case .server(_, let message): message
        case .offline: "You're offline. Check your connection and try again."
        }
    }
}

/// The existing practice endpoints, unchanged: start an attempt (which checks
/// the subscription and mints the voice token), assess its transcript, and
/// record lifecycle events.
enum PracticeAPI {
    struct StartResponse: Decodable {
        let token: String
        let context: PracticeContext
    }

    static func start(_ context: PracticeContext) async throws -> StartResponse {
        struct Body: Encodable {
            let attemptId: UUID
            let activityId: String
            let parentAttemptId: UUID?
            let pressure: String
            let pacing: String
            let language: String
            let situation: String
            let personaId: String
        }
        let body = Body(
            attemptId: context.attemptId,
            activityId: context.activityId,
            parentAttemptId: context.retry?.parentAttemptId,
            pressure: context.pressure,
            pacing: context.pacing,
            language: context.language,
            situation: context.situation,
            personaId: context.personaId ?? "female"
        )
        return try await post("start", body: body, timeout: 25)
    }

    /// Assessment can take a while — the server runs the model and saves the
    /// report — so it gets a long timeout, and it is idempotent: calling it
    /// again for the same attempt returns the saved report.
    static func assess(attemptId: UUID, transcript: [TranscriptLine]) async throws -> PracticeReport {
        struct Body: Encodable { let transcript: [TranscriptLine] }
        return try await post("\(attemptId.uuidString.lowercased())/assess", body: Body(transcript: transcript), timeout: 90)
    }

    /// Fire-and-forget lifecycle facts (never transcript text).
    static func event(_ name: String, attemptId: UUID) {
        struct Body: Encodable { let name: String }
        Task {
            let _: Ignored? = try? await post("\(attemptId.uuidString.lowercased())/event", body: Body(name: name), timeout: 10)
        }
    }

    private struct Ignored: Decodable {}

    private static func post<Body: Encodable, Response: Decodable>(_ path: String, body: Body, timeout: TimeInterval) async throws -> Response {
        guard let session = try? await Backend.supabase.auth.session else { throw PracticeAPIError.signedOut }
        var request = URLRequest(url: AppConfig.apiBaseURL.appending(path: "api/practice/\(path)"))
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw PracticeAPIError.offline
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let payload = try? JSONDecoder().decode([String: String].self, from: data)
            if status == 402 { throw PracticeAPIError.subscriptionRequired }
            if status == 409, path == "start" {
                throw PracticeAPIError.server(status: status, message: payload?["error"] ?? "This rehearsal's retry has already been used. Start a new rehearsal instead.")
            }
            throw PracticeAPIError.server(status: status, message: payload?["error"] ?? "Practice is unavailable right now. Please try again.")
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }
}

// MARK: - Drafts

/// One draft per account, in Application Support with complete file
/// protection — encrypted whenever the phone is locked, never in backups'
/// plain text, and written atomically so an interrupted write can't leave a
/// half-snapshot behind.
enum PracticeDrafts {
    private static func url(for userID: UUID) -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let folder = base.appending(path: "Practice", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: "draft-\(userID.uuidString.lowercased()).json")
    }

    static func save(_ draft: PracticeDraft, userID: UUID) {
        guard let url = url(for: userID), let data = try? JSONEncoder().encode(draft) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtection])
    }

    static func load(userID: UUID) -> PracticeDraft? {
        guard let url = url(for: userID), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PracticeDraft.self, from: data)
    }

    static func clear(userID: UUID) {
        guard let url = url(for: userID) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
