import Foundation
import Supabase

/// The existing presentation endpoints, unchanged: PowerPoint → PDF,
/// audience questions from the talk, and feedback on a spoken answer —
/// plus the signed-in speech-to-text used to transcribe recordings.
enum PresentationAPI {
    // MARK: Transcription

    /// Transcribes a recording (AAC in an .m4a) with the server's Scribe
    /// boundary. Signed-in only; files up to 10 MB.
    static func transcribe(_ audio: URL, language: String) async throws -> String {
        let session = try await currentSession()
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".data(using: .utf8)!)
        }
        field("language", language)
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"audio\"; filename=\"\(audio.lastPathComponent)\"\r\nContent-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(try Data(contentsOf: audio))
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        var request = URLRequest(url: AppConfig.apiBaseURL.appending(path: "api/exam-transcribe"))
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        struct Result: Decodable { let text: String }
        let result: Result = try await send(request, body: body)
        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Questions and feedback

    static func questions(deck: PresentationDeck, transcript: String, events: [SlideEvent]) async throws -> [AudienceQuestion] {
        struct Slide: Encodable { let index: Int; let text: String }
        struct Body: Encodable {
            let title: String
            let brief: PresentationBrief
            let transcript: String
            let slides: [Slide]
            let slideEvents: [SlideEvent]
            let language = AppLanguage.code
        }
        struct Result: Decodable { let questions: [AudienceQuestion] }
        let body = Body(
            title: String(deck.title.prefix(300)),
            brief: deck.brief,
            transcript: String(transcript.prefix(80_000)),
            slides: deck.slideTexts.enumerated().map { Slide(index: $0.offset, text: String($0.element.prefix(20_000))) },
            slideEvents: Array(events.prefix(1000))
        )
        let result: Result = try await postJSON("api/presentations/questions", body)
        return result.questions
    }

    static func feedback(deck: PresentationDeck, question: AudienceQuestion, answer: String, talk: String) async throws -> QuestionAnswer {
        struct Project: Encodable { let title: String; let brief: PresentationBrief; let slideTexts: [String] }
        struct Body: Encodable {
            let project: Project
            let question: AudienceQuestion
            let answer: String
            let presentationTranscript: String
            let language = AppLanguage.code
        }
        return try await postJSON("api/presentations/answer-feedback", Body(
            project: Project(title: deck.title, brief: deck.brief, slideTexts: deck.slideTexts),
            question: question,
            answer: String(answer.prefix(20_000)),
            presentationTranscript: String(talk.prefix(80_000))
        ))
    }

    // MARK: PowerPoint

    /// Converts a .pptx to PDF on the server. Needs LibreOffice there; when
    /// it isn't available the server says so, and the app asks for a PDF.
    static func convert(pptx: Data, fileName: String) async throws -> Data {
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"presentation\"; filename=\"\(fileName)\"\r\nContent-Type: application/vnd.openxmlformats-officedocument.presentationml.presentation\r\n\r\n".data(using: .utf8)!)
        body.append(pptx)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        var request = URLRequest(url: AppConfig.apiBaseURL.appending(path: "api/presentations/convert"))
        request.httpMethod = "POST"
        request.timeoutInterval = 150
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200, (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type")?.contains("pdf") == true else {
            throw PracticeAPIError.server(status: status, message: String(localized: "This PowerPoint couldn't be converted here. Export it as a PDF (File → Export in PowerPoint or Keynote) and add that instead.", bundle: AppLanguage.bundle))
        }
        return data
    }

    // MARK: Plumbing

    private static func postJSON<Body: Encodable, Response: Decodable>(_ path: String, _ body: Body) async throws -> Response {
        var request = URLRequest(url: AppConfig.apiBaseURL.appending(path: path))
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let session = try await currentSession()
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        return try await send(request, body: try JSONEncoder().encode(body))
    }

    private static func currentSession() async throws -> Session {
        do {
            return try await Backend.supabase.auth.session
        } catch let error as AuthError where error == .sessionMissing {
            throw PracticeAPIError.signedOut
        } catch {
            throw PracticeAPIError.sessionUnavailable
        }
    }

    private static func send<Response: Decodable>(_ request: URLRequest, body: Data) async throws -> Response {
        var request = request
        request.httpBody = body
        let data: Data
        let response: URLResponse
        do { (data, response) = try await URLSession.shared.data(for: request) } catch { throw PracticeAPIError.offline }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let message = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
            throw PracticeAPIError.server(status: status, message: message ?? String(localized: "That didn't work. Please try again.", bundle: AppLanguage.bundle))
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }
}
