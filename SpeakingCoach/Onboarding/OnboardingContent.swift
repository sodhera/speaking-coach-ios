import Foundation

// Everything the onboarding says, in one place. Copy rule: a kicker, one big
// line, one small line. If a screen needs a paragraph, the screen is wrong.

// MARK: - The moment

enum SpeakingMoment: String, Codable, CaseIterable, Identifiable {
    case interview, raise, hardConversation, presentation, speakingUp, meetingPeople, everyday

    var id: String { rawValue }

    var title: String {
        switch self {
        case .interview: "A job interview"
        case .raise: "Asking for a raise"
        case .hardConversation: "A hard conversation"
        case .presentation: "A presentation or pitch"
        case .speakingUp: "Speaking up at work"
        case .meetingPeople: "Meeting new people"
        case .everyday: "Speaking better, day to day"
        }
    }

    var icon: String {
        switch self {
        case .interview: "briefcase"
        case .raise: "chart.line.uptrend.xyaxis"
        case .hardConversation: "bubble.left.and.bubble.right"
        case .presentation: "person.wave.2"
        case .speakingUp: "hand.raised"
        case .meetingPeople: "hand.wave"
        case .everyday: "waveform"
        }
    }

    /// The moment as a noun inside a sentence: "before *your interview*".
    var noun: String {
        switch self {
        case .interview: "your interview"
        case .raise: "the raise conversation"
        case .hardConversation: "that conversation"
        case .presentation: "your presentation"
        case .speakingUp: "your next meeting"
        case .meetingPeople: "meeting new people"
        case .everyday: "everyday conversations"
        }
    }

    /// No single event ahead — the user wants to speak better in general.
    /// There's no date to ask about, and no "walk into" to promise.
    var isGeneral: Bool { self == .everyday }

    /// Sentence-initial form of `noun` for headlines.
    var nounCapitalized: String { noun.prefix(1).uppercased() + noun.dropFirst() }

    /// The rehearsal this moment starts with, from the shared catalog.
    var firstPracticeID: String {
        switch self {
        case .interview: "interview_tell_me_about_yourself"
        case .raise: "salary_raise"
        case .hardConversation: "set_a_boundary"
        case .presentation: "presentation_opening"
        case .speakingUp: "disagree_in_meeting"
        case .meetingPeople: "meet_someone_new"
        case .everyday: "first_gentle_introduction"
        }
    }

    /// The plan's last step, in the user's own outcome: "Walk in clear".
    /// The same words before the paywall and after it — the plan the app
    /// keeps is the plan the user committed to.
    func planFinish(outcomes: [SpeakingOutcome]) -> String {
        let outcome = SpeakingOutcome.allCases.first(where: outcomes.contains)
        if isGeneral { return "Speak \(outcome?.adverb ?? "with ease"), every day" }
        let how = outcome.map { " \($0.phrase)" } ?? " ready"
        return self == .meetingPeople ? "Meet people\(how)" : "Walk in\(how)"
    }

    var readinessQuestion: String {
        switch self {
        case .meetingPeople: "How at ease do you feel meeting someone new?"
        case .everyday: "How confident do you feel speaking day to day?"
        case .speakingUp: "How easy is it to speak up in a meeting?"
        default: "How ready do you feel for \(noun) right now?"
        }
    }

    var outcomeQuestion: String {
        switch self {
        case .meetingPeople: "Picture it going well. What's different?"
        case .everyday: "Picture yourself speaking at your best. What's different?"
        default: "Picture \(noun) going well. What's different?"
        }
    }
}

// MARK: - When

enum MomentTiming: String, Codable, CaseIterable, Identifiable {
    case soon, thisWeek, thisMonth, noDate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .soon: "Today or tomorrow"
        case .thisWeek: "This week"
        case .thisMonth: "This month"
        case .noDate: "No date — I want to be ready"
        }
    }

    var icon: String {
        switch self {
        case .soon: "bolt"
        case .thisWeek: "calendar"
        case .thisMonth: "calendar.badge.clock"
        case .noDate: "infinity"
        }
    }
}

// MARK: - The pain deck

enum Agreement: String, Codable {
    case yes, sometimes, no

    var weight: Int {
        switch self {
        case .yes: 2
        case .sometimes: 1
        case .no: 0
        }
    }
}

/// The self-recognition statements. Each is written so the right person
/// thinks "that's me" before they've finished reading it.
enum PainStatement: String, Codable, CaseIterable, Identifiable {
    case wordsVanish, blankOnTheSpot, rambleWhenNervous, stayQuiet, onlyInMyHead, replayAfterwards

    var id: String { rawValue }

    var text: String {
        switch self {
        case .wordsVanish: "I know what I want to say — until I have to say it."
        case .blankOnTheSpot: "My mind goes blank when I'm put on the spot."
        case .rambleWhenNervous: "When I'm nervous, I talk too fast or ramble."
        case .stayQuiet: "I stay quiet, even when I have a good point."
        case .onlyInMyHead: "I rehearse conversations in my head, never out loud."
        case .replayAfterwards: "Afterwards, I replay what I should have said."
        }
    }

    /// Which pattern a "that's me" here is evidence for. `onlyInMyHead` feeds
    /// none — it's the one every pattern shares, and it sets up the reframe.
    var pattern: SpeakingPattern? {
        switch self {
        case .wordsVanish, .blankOnTheSpot: .blankOut
        case .rambleWhenNervous: .rambler
        case .stayQuiet: .holdBack
        case .replayAfterwards: .replayer
        case .onlyInMyHead: nil
        }
    }
}

/// Encodes the answers map as a JSON object keyed by statement, not as a
/// flat key/value array.
extension PainStatement: CodingKeyRepresentable {}

// MARK: - The mirror

enum SpeakingPattern: String, Codable {
    case blankOut, rambler, holdBack, replayer, steady

    var name: String {
        switch self {
        case .blankOut: "The Blank-Out"
        case .rambler: "The Rambler"
        case .holdBack: "The Holder-Back"
        case .replayer: "The Replayer"
        case .steady: "The Steady One"
        }
    }

    var diagnosis: String {
        switch self {
        case .blankOut: "You have the words. They just don't show up under pressure."
        case .rambler: "You know your point. It gets lost on the way out."
        case .holdBack: "You have good things to say. They stay in your head."
        case .replayer: "The conversation ends. The replay doesn't."
        case .steady: "You're steadier than most. Now make it sharp."
        }
    }

    /// How the app answers this pattern — the third beat of "how it works".
    var fix: String {
        switch self {
        case .blankOut: "Rehearse the exact question until the answer is there."
        case .rambler: "Practice landing your point in three sentences."
        case .holdBack: "Say it out loud first, so the real time is the second time."
        case .replayer: "Retry the moment in practice, not in your head at 2am."
        case .steady: "Retry the one moment that could be better."
        }
    }

    /// Derived purely from the deck: the pattern with the most weight, ties
    /// broken in deck order. No "yes" anywhere means `.steady` — never a
    /// problem the user didn't report.
    static func from(_ answers: [PainStatement: Agreement]) -> SpeakingPattern {
        var scores: [SpeakingPattern: Int] = [:]
        for statement in PainStatement.allCases {
            guard let pattern = statement.pattern, let answer = answers[statement] else { continue }
            scores[pattern, default: 0] += answer.weight
        }
        let order: [SpeakingPattern] = [.blankOut, .rambler, .holdBack, .replayer]
        let best = order.max { (scores[$0] ?? 0) < (scores[$1] ?? 0) }
        guard let best, let top = scores[best], top > 0 else { return .steady }
        // `max` returns the *last* of equal elements; prefer the first in order.
        return order.first { scores[$0] == top } ?? best
    }
}

// MARK: - Cost and outcome

enum SpeakingCost: String, Codable, CaseIterable, Identifiable {
    case jobOrPromotion, creditForIdeas, takenSeriously, connection, selfConfidence, nothingYet

    var id: String { rawValue }

    var title: String {
        switch self {
        case .jobOrPromotion: "A job or promotion"
        case .creditForIdeas: "Credit for my ideas"
        case .takenSeriously: "Being taken seriously"
        case .connection: "A connection I wanted"
        case .selfConfidence: "Confidence in myself"
        case .nothingYet: "Nothing yet — I want to stay ahead"
        }
    }

    var icon: String {
        switch self {
        case .jobOrPromotion: "briefcase"
        case .creditForIdeas: "lightbulb"
        case .takenSeriously: "person.fill.checkmark"
        case .connection: "person.2"
        case .selfConfidence: "heart"
        case .nothingYet: "arrow.up.right"
        }
    }
}

enum SpeakingOutcome: String, Codable, CaseIterable, Identifiable {
    case calm, clear, myself, getTheYes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .calm: "I stay calm"
        case .clear: "I say it clearly, the first time"
        case .myself: "I sound like myself"
        case .getTheYes: "I get what I asked for"
        }
    }

    var icon: String {
        switch self {
        case .calm: "leaf"
        case .clear: "text.bubble"
        case .myself: "person.crop.circle"
        case .getTheYes: "hand.thumbsup"
        }
    }

    /// The outcome as a manner of speaking, for general-improvement copy:
    /// "Speak calmly and clearly, every day."
    var adverb: String {
        switch self {
        case .calm: "calmly"
        case .clear: "clearly"
        case .myself: "like yourself"
        case .getTheYes: "with conviction"
        }
    }

    /// The outcome as an adjective phrase, for the paywall headline.
    var phrase: String {
        switch self {
        case .calm: "calm"
        case .clear: "clear"
        case .myself: "like yourself"
        case .getTheYes: "ready to get the yes"
        }
    }
}

// MARK: - Try it

struct OpeningQuiz {
    let setup: String
    let prompt: String
    let options: [String]
    let bestIndex: Int
    let why: String

    static func `for`(_ moment: SpeakingMoment) -> OpeningQuiz {
        switch moment {
        case .interview:
            OpeningQuiz(
                setup: "Your interviewer asks.",
                prompt: "“Tell me about yourself.”",
                options: [
                    "“Well, I grew up in… then I studied…”",
                    "“I'm a designer who turns messy problems into simple tools — most recently at Acme.”",
                    "“Um, what would you like to know?”",
                ],
                bestIndex: 1,
                why: "Who you are now, plus one proof. They'll ask for the rest."
            )
        case .raise:
            OpeningQuiz(
                setup: "You're opening with your manager.",
                prompt: "Your first line?",
                options: [
                    "“Sorry to bother you, I know budgets are tight…”",
                    "“Other companies pay more for my role.”",
                    "“I'd like to talk about my pay. This year I took on the launch and grew it 30%.”",
                ],
                bestIndex: 2,
                why: "The ask, then the evidence. No apology, no threat."
            )
        case .hardConversation:
            OpeningQuiz(
                setup: "A coworker keeps moving your deadlines.",
                prompt: "What do you say?",
                options: [
                    "“You always do this.”",
                    "“When the deadline moved without warning, I got stuck. Can we flag changes early?”",
                    "“It's fine, never mind.”",
                ],
                bestIndex: 1,
                why: "Name the moment, not the person. Then ask for one change."
            )
        case .presentation:
            OpeningQuiz(
                setup: "All eyes are on you.",
                prompt: "Your first sentence?",
                options: [
                    "“Hi, so, um, I'm going to talk about our results.”",
                    "“Sorry, this might be a bit dry.”",
                    "“Last quarter, one change doubled our sign-ups. Here's what it was.”",
                ],
                bestIndex: 2,
                why: "Open with the most interesting thing you know."
            )
        case .speakingUp:
            OpeningQuiz(
                setup: "The meeting is moving on. You have a point.",
                prompt: "How do you get in?",
                options: [
                    "“This is probably wrong, but…”",
                    "“Can I add one thing? We're missing the cost side.”",
                    "Wait for a better moment.",
                ],
                bestIndex: 1,
                why: "Ask for the floor, then say it plainly. No disclaimers."
            )
        case .everyday:
            OpeningQuiz(
                setup: "Someone asks for your view.",
                prompt: "“What do you think?”",
                options: [
                    "“Um, I don't know — it's probably fine?”",
                    "“Whatever everyone else thinks.”",
                    "“I think it works, but the timing's risky. I'd test it first.”",
                ],
                bestIndex: 2,
                why: "Say what you think, then one reason. Hedging hides a good point."
            )
        case .meetingPeople:
            OpeningQuiz(
                setup: "Someone new asks.",
                prompt: "“So, what do you do?”",
                options: [
                    "“Oh, nothing interesting.”",
                    "“I'm an engineer.”",
                    "“I teach kids to code — one just built a game about his cat. You?”",
                ],
                bestIndex: 2,
                why: "A detail and a question back turn an answer into a conversation."
            )
        }
    }
}

// MARK: - Practice language

struct PracticeLanguage: Identifiable, Hashable {
    let id: String
    let name: String

    static let all: [PracticeLanguage] = [
        ("en", "English"), ("es", "Spanish"), ("fr", "French"), ("de", "German"),
        ("it", "Italian"), ("pt", "Portuguese"), ("nl", "Dutch"), ("pl", "Polish"),
        ("sv", "Swedish"), ("tr", "Turkish"), ("ru", "Russian"), ("uk", "Ukrainian"),
        ("hi", "Hindi"), ("ar", "Arabic"), ("ja", "Japanese"), ("ko", "Korean"),
        ("zh", "Chinese"), ("id", "Indonesian"), ("tl", "Filipino"), ("vi", "Vietnamese"),
    ].map { PracticeLanguage(id: $0.0, name: $0.1) }

    static func named(_ code: String) -> String {
        all.first { $0.id == code }?.name ?? "English"
    }

    /// The device's language if the partner can speak it, else English.
    static var deviceDefault: String {
        let code = Locale.current.language.languageCode?.identifier ?? "en"
        return all.contains { $0.id == code } ? code : "en"
    }
}
