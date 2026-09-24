import AuthenticationServices
import CryptoKit
import Foundation
import Supabase

enum AuthFailure: LocalizedError, Equatable {
    case cancelled
    case message(String)

    var errorDescription: String? {
        switch self {
        case .cancelled: nil
        case .message(let text): text
        }
    }
}

/// Sign-in with Apple (native sheet) or Google (web sheet via Supabase
/// OAuth) — the only two ways in. Every path ends in a Supabase session; the
/// app model observes the session, so these methods only need to succeed or
/// throw.
@MainActor
enum AuthService {
    private static var auth: AuthClient { Backend.supabase.auth }

    // MARK: Apple

    static func signInWithApple() async throws {
        let nonce = randomNonce()
        let credential = try await AppleSignInSheet.present(hashedNonce: sha256(nonce))
        guard let tokenData = credential.identityToken, let idToken = String(data: tokenData, encoding: .utf8) else {
            throw AuthFailure.message("Apple didn't return a sign-in token. Please try again.")
        }
        do {
            try await auth.signInWithIdToken(credentials: .init(provider: .apple, idToken: idToken, nonce: nonce))
        } catch {
            throw map(error)
        }
        // Apple shares the name only on the very first authorization; keep it.
        if let given = credential.fullName?.givenName, !given.isEmpty {
            _ = try? await auth.update(user: UserAttributes(data: ["full_name": .string(given)]))
        }
    }

    // MARK: Google

    static func signInWithGoogle() async throws {
        do {
            try await auth.signInWithOAuth(provider: .google, redirectTo: AppConfig.authCallback) { session in
                session.prefersEphemeralWebBrowserSession = false
            }
        } catch {
            if (error as? ASWebAuthenticationSessionError)?.code != .canceledLogin {
                let failure = error as NSError
                AppLog.error("Google OAuth failed: \(failure.domain) (\(failure.code))")
            }
            throw map(error)
        }
    }

    static func signOut() async {
        try? await auth.signOut()
    }

    // MARK: Errors

    private static func map(_ error: Error) -> AuthFailure {
        if let failure = error as? AuthFailure { return failure }
        if let web = error as? ASWebAuthenticationSessionError, web.code == .canceledLogin { return .cancelled }
        if let apple = error as? ASAuthorizationError, apple.code == .canceled { return .cancelled }
        if let api = error as? AuthError {
            switch api.errorCode {
            case .overRequestRateLimit: return .message("Too many tries. Wait a minute and try again.")
            default: return .message(api.message)
            }
        }
        if (error as? URLError) != nil { return .message("You're offline. Check your connection and try again.") }
        return .message("Something went wrong. Please try again.")
    }

    // MARK: Nonce

    private static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in charset.randomElement(using: &generator)! })
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// Presents the native Sign in with Apple sheet and bridges it to async.
@MainActor
private final class AppleSignInSheet: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>?
    private static var current: AppleSignInSheet?

    static func present(hashedNonce: String) async throws -> ASAuthorizationAppleIDCredential {
        let sheet = AppleSignInSheet()
        current = sheet
        defer { current = nil }
        return try await withCheckedThrowingContinuation { continuation in
            sheet.continuation = continuation
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName, .email]
            request.nonce = hashedNonce
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = sheet
            controller.presentationContextProvider = sheet
            controller.performRequests()
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        MainActor.assumeIsolated {
            if let credential = authorization.credential as? ASAuthorizationAppleIDCredential {
                continuation?.resume(returning: credential)
            } else {
                continuation?.resume(throwing: AuthFailure.message("Apple sign-in returned an unexpected credential."))
            }
            continuation = nil
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        MainActor.assumeIsolated {
            let cancelled = (error as? ASAuthorizationError)?.code == .canceled
            if !cancelled {
                let failure = error as NSError
                AppLog.error("Apple authorization failed: \(failure.domain) (\(failure.code))")
            }
            continuation?.resume(throwing: cancelled ? AuthFailure.cancelled : AuthFailure.message("Apple sign-in didn't finish. Please try again."))
            continuation = nil
        }
    }

    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.keyWindow }
                .first ?? ASPresentationAnchor()
        }
    }
}
