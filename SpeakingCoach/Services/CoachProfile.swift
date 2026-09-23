import Foundation

/// Everything onboarding learned, as the user answered it. Stored on the
/// account (Supabase `user_metadata`) so a reinstall or a second phone
/// restores it, and cached on device for instant launches.
struct CoachProfile: Codable, Equatable {
    var name: String
    var language: String
    var moment: SpeakingMoment?
    var timing: MomentTiming?
    /// Self-rated readiness, 0–10, before any practice. The baseline future
    /// progress is measured against — never a number we made up.
    var readiness: Int?
    var statements: [PainStatement: Agreement]
    var costs: [SpeakingCost]
    var outcomes: [SpeakingOutcome]
    var onboardedAt: Date
    /// True for an account that onboarded in the old app, whose profile only
    /// carries a name and language.
    var isLegacy = false

    var pattern: SpeakingPattern { SpeakingPattern.from(statements) }
    var firstName: String {
        name.split(separator: " ").first.map(String.init) ?? name
    }
}

/// In-progress answers, persisted as the user goes so a killed app resumes
/// on the same step.
struct OnboardingAnswers: Codable, Equatable {
    var name = ""
    var language = PracticeLanguage.deviceDefault
    var moment: SpeakingMoment?
    var timing: MomentTiming?
    var readiness = 5
    var readinessTouched = false
    var statements: [PainStatement: Agreement] = [:]
    var costs: Set<SpeakingCost> = []
    var outcomes: Set<SpeakingOutcome> = []
    var quizChoice: Int?

    var pattern: SpeakingPattern { SpeakingPattern.from(statements) }

    func profile(at date: Date = .now) -> CoachProfile {
        CoachProfile(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            language: language,
            moment: moment,
            timing: timing,
            readiness: readinessTouched ? readiness : nil,
            statements: statements,
            costs: SpeakingCost.allCases.filter(costs.contains),
            outcomes: SpeakingOutcome.allCases.filter(outcomes.contains),
            onboardedAt: date
        )
    }
}
