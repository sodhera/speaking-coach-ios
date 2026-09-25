import Foundation
import Supabase

enum PracticeAPIError: LocalizedError {
    case signedOut
    case sessionUnavailable
    case subscriptionRequired
    /// The session's one focused retry has already been started.
    case retryUsed
    case server(status: Int, message: String)
    case offline

    var errorDescription: String? {
        switch self {
        case .signedOut: "Please sign in again to practice."
        case .sessionUnavailable: "We couldn't verify your sign-in. Check your connection and try again."
        case .subscriptionRequired: "Your plan isn't active right now."
        case .retryUsed: "Each session gets one focused retry, and this one has already been started. You can practice the whole scene again instead."
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
        let session: Session
        do {
            session = try await Backend.supabase.auth.session
        } catch let error as AuthError where error == .sessionMissing {
            throw PracticeAPIError.signedOut
        } catch {
            throw PracticeAPIError.sessionUnavailable
        }
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
            if status == 409, path == "start", payload?["code"] == "retry_used" { throw PracticeAPIError.retryUsed }
            if status == 409, path == "start" {
                throw PracticeAPIError.server(status: status, message: payload?["error"] ?? "This session's retry has already been used. Start a new session instead.")
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

// MARK: - Custom situations

/// The existing endpoints the old app used for "Custom situation": a
/// legibility check that restates the situation, a voice token straight from
/// the partner agent, and the general analysis. The report is saved by the
/// app itself into `reports` (row-level security lets a user insert their own).
enum CustomSituationAPI {
    struct Evaluation: Decodable {
        let isAppropriate: Bool
        let message: String
    }

    static func evaluate(_ description: String, language: String) async throws -> Evaluation {
        struct Body: Encodable { let customDescription: String; let language: String }
        return try await post("api/evaluate-custom-scenario", Body(customDescription: description, language: language), timeout: 25)
    }

    static func token(persona: PracticeSetup.Persona) async throws -> String {
        let agent = persona == .male ? AppConfig.maleAgentID : AppConfig.femaleAgentID
        var components = URLComponents(url: AppConfig.apiBaseURL.appending(path: "api/elevenlabs-token"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "agent_id", value: agent)]
        let (data, response) = try await URLSession.shared.data(from: components.url!)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let token = (try? JSONDecoder().decode([String: String].self, from: data))?["token"] else {
            throw PracticeAPIError.server(status: (response as? HTTPURLResponse)?.statusCode ?? 0, message: "Your partner couldn't connect. Try again in a moment.")
        }
        return token
    }

    struct Analysis: Decodable {
        let score: Int
        let summary: String
        let subscores: [Subscore]
        let improvements: [String]
        let rewrites: [Rewrite]
    }

    static func analyze(_ transcript: [TranscriptLine], situation: CustomSituation, language: String) async throws -> Analysis {
        struct Body: Encodable {
            let scenarioId = "custom"
            let scenarioDescription: String
            let goal: String
            let personaName: String
            let language: String
            let focusMetrics = ["Clarity", "Confidence", "Assertiveness", "Warmth"]
            let transcript: [TranscriptLine]
        }
        let body = Body(
            scenarioDescription: "\(situation.description) (The partner plays: \(situation.partner).)",
            goal: "Say what I need to say clearly and confidently.",
            personaName: situation.partner,
            language: language,
            transcript: transcript
        )
        return try await post("api/analyze", body, timeout: 90)
    }

    /// Saves the finished custom rehearsal to history and returns it in the
    /// same shape as every other report.
    static func save(_ analysis: Analysis, transcript: [TranscriptLine], context: PracticeContext, userID: UUID) async throws -> PracticeReport {
        guard let custom = context.custom else { throw PracticeAPIError.server(status: 0, message: "Missing situation.") }
        let report = PracticeReport(
            id: context.attemptId,
            transcript: transcript,
            analysis: .init(
                score: analysis.score, summary: analysis.summary, improvements: analysis.improvements,
                subscores: analysis.subscores, rewrites: analysis.rewrites, custom: custom
            )
        )
        struct Row: Encodable {
            let id: UUID
            let user_id: UUID
            let persona_id: String
            let scenario_id = "custom"
            let goal_text: String
            let transcript: [TranscriptLine]
            let analysis: PracticeReport.Analysis
            let score: Int
        }
        try await Backend.supabase.from("reports").insert(Row(
            id: report.id, user_id: userID, persona_id: context.personaId ?? "female",
            goal_text: String(custom.description.prefix(500)), transcript: transcript,
            analysis: report.analysis, score: analysis.score
        )).execute()
        return report
    }

    private static func post<Body: Encodable, Response: Decodable>(_ path: String, _ body: Body, timeout: TimeInterval) async throws -> Response {
        var request = URLRequest(url: AppConfig.apiBaseURL.appending(path: path))
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let data: Data
        let response: URLResponse
        do { (data, response) = try await URLSession.shared.data(for: request) } catch { throw PracticeAPIError.offline }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let message = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
            throw PracticeAPIError.server(status: status, message: message ?? "That didn't work. Please try again.")
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }
}
