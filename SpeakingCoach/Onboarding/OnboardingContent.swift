import Foundation
import NaturalLanguage

// Everything the onboarding says, in one place. Copy rule: a kicker, one big
// line, one small line. If a screen needs a paragraph, the screen is wrong.
//
// Every sentence is written whole, per moment, rather than assembled from
// fragments ("walk into" + "your interview"): assembled sentences can't be
// translated into languages whose words change with case or gender. The only
// slot left open is the user's own outcomes, and those are written as
// phrases that fit it in every language.

// MARK: - The category

/// The three doors the app is marketed through, and the first real question.
/// Each is a situation people already name themselves by ("I have a
/// presentation"), so the ad, the store listing and this screen all say the
/// same thing. The boundary between the two work doors: **Presentations** is
/// speaking to a room; **Work** is one-to-one or a meeting.
enum SpeakingCategory: String, Codable, CaseIterable, Identifiable {
    case work, presentations, everyday

    var id: String { rawValue }

    var title: String {
        switch self {
        case .work: String(localized: "Work", bundle: AppLanguage.bundle)
        case .presentations: String(localized: "Presentations", bundle: AppLanguage.bundle)
        case .everyday: String(localized: "Everyday conversations", bundle: AppLanguage.bundle)
        }
    }

    var icon: String {
        switch self {
        case .work: "briefcase"
        case .presentations: "person.wave.2"
        case .everyday: "bubble.left.and.bubble.right"
        }
    }

    /// The situations inside the door. A door with one situation skips the
    /// second question — the answer is already given.
    var moments: [SpeakingMoment] {
        switch self {
        case .work: [.interview, .raise, .hardConversation, .speakingUp]
        case .presentations: [.presentation]
        case .everyday: [.meetingPeople, .everyday]
        }
    }
}

// MARK: - The moment

enum SpeakingMoment: String, Codable, CaseIterable, Identifiable {
    case interview, raise, hardConversation, presentation, speakingUp, meetingPeople, everyday

    var id: String { rawValue }

    var category: SpeakingCategory {
        SpeakingCategory.allCases.first { $0.moments.contains(self) } ?? .work
    }

    var title: String {
        switch self {
        case .interview: String(localized: "A job interview", bundle: AppLanguage.bundle)
        case .raise: String(localized: "Asking for a raise", bundle: AppLanguage.bundle)
        case .hardConversation: String(localized: "A hard conversation", bundle: AppLanguage.bundle)
        case .presentation: String(localized: "A presentation or pitch", bundle: AppLanguage.bundle)
        case .speakingUp: String(localized: "Speaking up at work", bundle: AppLanguage.bundle)
        case .meetingPeople: String(localized: "Meeting new people", bundle: AppLanguage.bundle)
        case .everyday: String(localized: "Speaking better, day to day", bundle: AppLanguage.bundle)
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

    /// No single event ahead — the user wants to speak better in general.
    /// There's no date to ask about, and no "walk into" to promise.
    var isGeneral: Bool { self == .everyday }

    /// The catalog session this moment starts with.
    var firstPractice: PracticeDefinition? {
        let id = switch self {
        case .interview: "interview_tell_me_about_yourself"
        case .raise: "salary_raise"
        case .hardConversation: "set_a_boundary"
        case .presentation: "presentation_opening"
        case .speakingUp: "disagree_in_meeting"
        case .meetingPeople: "meet_someone_new"
        case .everyday: "first_gentle_introduction"
        }
        return PracticeCatalog.definition(id)
    }

    /// The plan's last step, in the user's own outcome: "Walk in calm".
    /// The same words before the paywall and after it — the plan the app
    /// keeps is the plan the user committed to.
    func planFinish(outcomes: [SpeakingOutcome]) -> String {
        let outcome = SpeakingOutcome.allCases.first(where: outcomes.contains)
        if isGeneral {
            let how = outcome?.adverb ?? String(localized: "with ease", bundle: AppLanguage.bundle, comment: "Fills: Speak ___, every day")
            return String(localized: "Speak \(how), every day", bundle: AppLanguage.bundle, comment: "Plan step. The slot is a manner of speaking, e.g. 'calmly'.")
        }
        let how = outcome?.phrase ?? String(localized: "ready", bundle: AppLanguage.bundle, comment: "Fills: Walk in ___ / Meet people ___")
        return self == .meetingPeople
            ? String(localized: "Meet people \(how)", bundle: AppLanguage.bundle, comment: "Plan step. The slot is an outcome phrase, e.g. 'calm'.")
            : String(localized: "Walk in \(how)", bundle: AppLanguage.bundle, comment: "Plan step: walk into the moment itself. The slot is an outcome phrase, e.g. 'calm'.")
    }

    var readinessQuestion: String {
        switch self {
        case .interview: String(localized: "How ready do you feel for your interview right now?", bundle: AppLanguage.bundle)
        case .raise: String(localized: "How ready do you feel for the raise conversation right now?", bundle: AppLanguage.bundle)
        case .hardConversation: String(localized: "How ready do you feel for that conversation right now?", bundle: AppLanguage.bundle)
        case .presentation: String(localized: "How ready do you feel for your presentation right now?", bundle: AppLanguage.bundle)
        case .speakingUp: String(localized: "How easy is it to speak up in a meeting?", bundle: AppLanguage.bundle)
        case .meetingPeople: String(localized: "How at ease do you feel meeting someone new?", bundle: AppLanguage.bundle)
        case .everyday: String(localized: "How confident do you feel speaking day to day?", bundle: AppLanguage.bundle)
        }
    }

    var outcomeQuestion: String {
        switch self {
        case .interview: String(localized: "Picture your interview going well. What's different?", bundle: AppLanguage.bundle)
        case .raise: String(localized: "Picture the raise conversation going well. What's different?", bundle: AppLanguage.bundle)
        case .hardConversation: String(localized: "Picture that conversation going well. What's different?", bundle: AppLanguage.bundle)
        case .presentation: String(localized: "Picture your presentation going well. What's different?", bundle: AppLanguage.bundle)
        case .speakingUp: String(localized: "Picture your next meeting going well. What's different?", bundle: AppLanguage.bundle)
        case .meetingPeople: String(localized: "Picture it going well. What's different?", bundle: AppLanguage.bundle)
        case .everyday: String(localized: "Picture yourself speaking at your best. What's different?", bundle: AppLanguage.bundle)
        }
    }

    var timingQuestion: String {
        switch self {
        case .meetingPeople, .speakingUp: String(localized: "When's the next one?", bundle: AppLanguage.bundle)
        default: String(localized: "When is it?", bundle: AppLanguage.bundle)
        }
    }

    /// The outcomes worth offering for this moment. "I get what I asked
    /// for" means nothing in a chat; fluency means everything.
    var outcomeOptions: [SpeakingOutcome] {
        switch self {
        case .meetingPeople, .everyday: [.calm, .clear, .fluent, .myself]
        default: [.calm, .clear, .myself, .getTheYes]
        }
    }

    /// The promise, in the user's own outcomes: "and you'll walk into your
    /// interview calm and clear." Strong on purpose — it names the result
    /// they asked for — but never a number we can't measure.
    func promise(outcomes: Set<SpeakingOutcome>) -> String {
        if isGeneral {
            return String(localized: "and you'll speak \(Self.manner(outcomes)), every day.", bundle: AppLanguage.bundle, comment: "Last line of the promise. Slot: one or two manners of speaking.")
        }
        let how = Self.phrases(outcomes)
        return switch self {
        case .interview: String(localized: "and you'll walk into your interview \(how).", bundle: AppLanguage.bundle, comment: "Last line of the promise. Slot: one or two outcome phrases, e.g. 'calm and clear'.")
        case .raise: String(localized: "and you'll walk into the raise conversation \(how).", bundle: AppLanguage.bundle, comment: "Last line of the promise. Slot: one or two outcome phrases.")
        case .hardConversation: String(localized: "and you'll walk into that conversation \(how).", bundle: AppLanguage.bundle, comment: "Last line of the promise. Slot: one or two outcome phrases.")
        case .presentation: String(localized: "and you'll walk into your presentation \(how).", bundle: AppLanguage.bundle, comment: "Last line of the promise. Slot: one or two outcome phrases.")
        case .speakingUp: String(localized: "and you'll walk into your next meeting \(how).", bundle: AppLanguage.bundle, comment: "Last line of the promise. Slot: one or two outcome phrases.")
        case .meetingPeople, .everyday: String(localized: "and you'll walk into any room \(how).", bundle: AppLanguage.bundle, comment: "Last line of the promise. Slot: one or two outcome phrases.")
        }
    }

    /// The paywall's headline: the promise, standing on its own.
    func headline(outcomes: [SpeakingOutcome]) -> String {
        let chosen = Set(outcomes)
        if isGeneral {
            return String(localized: "Speak \(Self.manner(chosen)), every day.", bundle: AppLanguage.bundle, comment: "Paywall headline. Slot: one or two manners of speaking.")
        }
        let how = Self.phrases(chosen)
        return switch self {
        case .interview: String(localized: "Walk into your interview \(how).", bundle: AppLanguage.bundle, comment: "Paywall headline. Slot: one or two outcome phrases.")
        case .raise: String(localized: "Walk into the raise conversation \(how).", bundle: AppLanguage.bundle, comment: "Paywall headline. Slot: one or two outcome phrases.")
        case .hardConversation: String(localized: "Walk into that conversation \(how).", bundle: AppLanguage.bundle, comment: "Paywall headline. Slot: one or two outcome phrases.")
        case .presentation: String(localized: "Walk into your presentation \(how).", bundle: AppLanguage.bundle, comment: "Paywall headline. Slot: one or two outcome phrases.")
        case .speakingUp: String(localized: "Walk into your next meeting \(how).", bundle: AppLanguage.bundle, comment: "Paywall headline. Slot: one or two outcome phrases.")
        case .meetingPeople, .everyday: String(localized: "Walk into any room \(how).", bundle: AppLanguage.bundle, comment: "Paywall headline. Slot: one or two outcome phrases.")
        }
    }

    /// The plan's headline, once the user has said when it is.
    func arrival(_ timing: MomentTiming) -> String {
        switch (self, timing) {
        case (.interview, .soon): String(localized: "Your interview is almost here.", bundle: AppLanguage.bundle)
        case (.interview, .thisWeek): String(localized: "Your interview is this week.", bundle: AppLanguage.bundle)
        case (.interview, .thisMonth): String(localized: "Your interview is this month.", bundle: AppLanguage.bundle)
        case (.raise, .soon): String(localized: "The raise conversation is almost here.", bundle: AppLanguage.bundle)
        case (.raise, .thisWeek): String(localized: "The raise conversation is this week.", bundle: AppLanguage.bundle)
        case (.raise, .thisMonth): String(localized: "The raise conversation is this month.", bundle: AppLanguage.bundle)
        case (.hardConversation, .soon): String(localized: "That conversation is almost here.", bundle: AppLanguage.bundle)
        case (.hardConversation, .thisWeek): String(localized: "That conversation is this week.", bundle: AppLanguage.bundle)
        case (.hardConversation, .thisMonth): String(localized: "That conversation is this month.", bundle: AppLanguage.bundle)
        case (.presentation, .soon): String(localized: "Your presentation is almost here.", bundle: AppLanguage.bundle)
        case (.presentation, .thisWeek): String(localized: "Your presentation is this week.", bundle: AppLanguage.bundle)
        case (.presentation, .thisMonth): String(localized: "Your presentation is this month.", bundle: AppLanguage.bundle)
        case (.speakingUp, .soon): String(localized: "Your next meeting is almost here.", bundle: AppLanguage.bundle)
        case (.speakingUp, .thisWeek): String(localized: "Your next meeting is this week.", bundle: AppLanguage.bundle)
        case (.speakingUp, .thisMonth): String(localized: "Your next meeting is this month.", bundle: AppLanguage.bundle)
        default: String(localized: "Your plan is ready.", bundle: AppLanguage.bundle)
        }
    }

    /// The question the fingerprint answers.
    func commitQuestion(name: String) -> String {
        if name.isEmpty {
            return switch self {
            case .interview: String(localized: "Ready to walk into your interview prepared?", bundle: AppLanguage.bundle)
            case .raise: String(localized: "Ready to walk into the raise conversation prepared?", bundle: AppLanguage.bundle)
            case .hardConversation: String(localized: "Ready to walk into that conversation prepared?", bundle: AppLanguage.bundle)
            case .presentation: String(localized: "Ready to walk into your presentation prepared?", bundle: AppLanguage.bundle)
            case .speakingUp: String(localized: "Ready to walk into your next meeting prepared?", bundle: AppLanguage.bundle)
            case .meetingPeople: String(localized: "Ready to meet new people with ease?", bundle: AppLanguage.bundle)
            case .everyday: String(localized: "Ready to start speaking better, every day?", bundle: AppLanguage.bundle)
            }
        }
        return switch self {
        case .interview: String(localized: "\(name), ready to walk into your interview prepared?", bundle: AppLanguage.bundle, comment: "Slot: the user's first name.")
        case .raise: String(localized: "\(name), ready to walk into the raise conversation prepared?", bundle: AppLanguage.bundle, comment: "Slot: the user's first name.")
        case .hardConversation: String(localized: "\(name), ready to walk into that conversation prepared?", bundle: AppLanguage.bundle, comment: "Slot: the user's first name.")
        case .presentation: String(localized: "\(name), ready to walk into your presentation prepared?", bundle: AppLanguage.bundle, comment: "Slot: the user's first name.")
        case .speakingUp: String(localized: "\(name), ready to walk into your next meeting prepared?", bundle: AppLanguage.bundle, comment: "Slot: the user's first name.")
        case .meetingPeople: String(localized: "\(name), ready to meet new people with ease?", bundle: AppLanguage.bundle, comment: "Slot: the user's first name.")
        case .everyday: String(localized: "\(name), ready to start speaking better, every day?", bundle: AppLanguage.bundle, comment: "Slot: the user's first name.")
        }
    }

    /// The paywall's first benefit: this moment, practiced out loud.
    var practiceBenefit: String {
        switch self {
        case .interview: String(localized: "Your interview, out loud, with a partner who plays the other side.", bundle: AppLanguage.bundle)
        case .raise: String(localized: "The raise conversation, out loud, with a manager who pushes back.", bundle: AppLanguage.bundle)
        case .hardConversation: String(localized: "That conversation, out loud, before it happens for real.", bundle: AppLanguage.bundle)
        case .presentation: String(localized: "Your opening, out loud, until it lands.", bundle: AppLanguage.bundle)
        case .speakingUp: String(localized: "Your point, out loud, in a meeting that keeps moving.", bundle: AppLanguage.bundle)
        case .meetingPeople: String(localized: "First conversations, out loud, with someone new.", bundle: AppLanguage.bundle)
        case .everyday: String(localized: "Everyday conversations, out loud, with a partner who plays the other side.", bundle: AppLanguage.bundle)
        }
    }

    /// Up to two outcomes, as a list in the app's language: "calm and clear".
    private static func phrases(_ outcomes: Set<SpeakingOutcome>) -> String {
        let chosen = SpeakingOutcome.allCases.filter(outcomes.contains).prefix(2).map(\.phrase)
        return chosen.isEmpty ? String(localized: "ready", bundle: AppLanguage.bundle, comment: "Fills: Walk in ___ / Meet people ___") : list(chosen)
    }

    private static func manner(_ outcomes: Set<SpeakingOutcome>) -> String {
        let chosen = SpeakingOutcome.allCases.filter(outcomes.contains).prefix(2).map(\.adverb)
        return chosen.isEmpty ? String(localized: "with ease", bundle: AppLanguage.bundle, comment: "Fills: Speak ___, every day") : list(chosen)
    }

    static func list(_ items: [String]) -> String {
        let formatter = ListFormatter()
        formatter.locale = AppLanguage.locale
        return formatter.string(from: items) ?? items.joined(separator: ", ")
    }
}

/// Accounts and drafts from before IELTS was retired still say "ielts".
/// They land on everyday conversations, the nearest goal left, rather than
/// failing to decode and losing the whole profile with them.
extension SpeakingCategory {
    init(from decoder: Decoder) throws {
        self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .everyday
    }
}

extension SpeakingMoment {
    init(from decoder: Decoder) throws {
        self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .everyday
    }
}

// MARK: - When

enum MomentTiming: String, Codable, CaseIterable, Identifiable {
    case soon, thisWeek, thisMonth, noDate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .soon: String(localized: "Today or tomorrow", bundle: AppLanguage.bundle)
        case .thisWeek: String(localized: "This week", bundle: AppLanguage.bundle)
        case .thisMonth: String(localized: "This month", bundle: AppLanguage.bundle)
        case .noDate: String(localized: "No date, I just want to be ready", bundle: AppLanguage.bundle)
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
        case .wordsVanish: String(localized: "I know what I want to say, until I have to say it.", bundle: AppLanguage.bundle)
        case .blankOnTheSpot: String(localized: "My mind goes blank when I'm put on the spot.", bundle: AppLanguage.bundle)
        case .rambleWhenNervous: String(localized: "When I'm nervous, I talk too fast or ramble.", bundle: AppLanguage.bundle)
        case .stayQuiet: String(localized: "I stay quiet, even when I have a good point.", bundle: AppLanguage.bundle)
        case .onlyInMyHead: String(localized: "I practice conversations in my head, never out loud.", bundle: AppLanguage.bundle)
        case .replayAfterwards: String(localized: "Afterwards, I replay what I should have said.", bundle: AppLanguage.bundle)
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

    /// Private tailoring for a supportive onboarding response. The app never
    /// presents this internal grouping as a label for the person.
    var encouragement: String {
        switch self {
        case .blankOut: String(localized: "It's okay to pause when a question catches you off guard.", bundle: AppLanguage.bundle)
        case .rambler: String(localized: "Your ideas deserve room to land.", bundle: AppLanguage.bundle)
        case .holdBack: String(localized: "What you want to say matters.", bundle: AppLanguage.bundle)
        case .replayer: String(localized: "A difficult conversation can stay with you afterward.", bundle: AppLanguage.bundle)
        case .steady: String(localized: "You already have a strong starting point.", bundle: AppLanguage.bundle)
        }
    }

    var practiceHelp: String {
        switch self {
        case .blankOut: String(localized: "We'll practice one question at a time, with room to find your words.", bundle: AppLanguage.bundle)
        case .rambler: String(localized: "We'll practice finding your main point and saying it clearly.", bundle: AppLanguage.bundle)
        case .holdBack: String(localized: "We'll give you a place to say it out loud before the real conversation.", bundle: AppLanguage.bundle)
        case .replayer: String(localized: "Here you can try that kind of moment again, at your own pace.", bundle: AppLanguage.bundle)
        case .steady: String(localized: "We'll help you make one good answer even clearer.", bundle: AppLanguage.bundle)
        }
    }

    /// How the app answers this pattern — the paywall's third benefit.
    var fix: String {
        switch self {
        case .blankOut: String(localized: "Practice the exact question until the answer is there.", bundle: AppLanguage.bundle)
        case .rambler: String(localized: "Practice landing your point in three sentences.", bundle: AppLanguage.bundle)
        case .holdBack: String(localized: "Say it out loud first, so the real time is the second time.", bundle: AppLanguage.bundle)
        case .replayer: String(localized: "Retry the moment in practice, not in your head at 2am.", bundle: AppLanguage.bundle)
        case .steady: String(localized: "Retry the one moment that could be better.", bundle: AppLanguage.bundle)
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
        guard let top = order.compactMap({ scores[$0] }).max(), top > 0 else { return .steady }
        return order.first { scores[$0] == top } ?? .steady
    }
}

// MARK: - Cost and outcome

enum SpeakingCost: String, Codable, CaseIterable, Identifiable {
    case jobOrPromotion, creditForIdeas, takenSeriously, connection, selfConfidence, nothingYet

    var id: String { rawValue }

    var title: String {
        switch self {
        case .jobOrPromotion: String(localized: "A job or promotion", bundle: AppLanguage.bundle)
        case .creditForIdeas: String(localized: "Credit for my ideas", bundle: AppLanguage.bundle)
        case .takenSeriously: String(localized: "Being taken seriously", bundle: AppLanguage.bundle)
        case .connection: String(localized: "A connection I wanted", bundle: AppLanguage.bundle)
        case .selfConfidence: String(localized: "Confidence in myself", bundle: AppLanguage.bundle)
        case .nothingYet: String(localized: "Nothing yet, I want to stay ahead", bundle: AppLanguage.bundle)
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
    case calm, clear, myself, getTheYes, fluent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .calm: String(localized: "I stay calm", bundle: AppLanguage.bundle)
        case .clear: String(localized: "I say it clearly, the first time", bundle: AppLanguage.bundle)
        case .myself: String(localized: "I sound like myself", bundle: AppLanguage.bundle)
        case .getTheYes: String(localized: "I get what I asked for", bundle: AppLanguage.bundle)
        case .fluent: String(localized: "I keep going, without freezing", bundle: AppLanguage.bundle)
        }
    }

    var icon: String {
        switch self {
        case .calm: "leaf"
        case .clear: "text.bubble"
        case .myself: "person.crop.circle"
        case .getTheYes: "hand.thumbsup"
        case .fluent: "waveform"
        }
    }

    /// The outcome as a manner of speaking: "Speak calmly, every day".
    var adverb: String {
        switch self {
        case .calm: String(localized: "calmly", bundle: AppLanguage.bundle, comment: "Fills: Speak ___, every day")
        case .clear: String(localized: "clearly", bundle: AppLanguage.bundle, comment: "Fills: Speak ___, every day")
        case .myself: String(localized: "like yourself", bundle: AppLanguage.bundle, comment: "Fills: Speak ___, every day")
        case .getTheYes: String(localized: "with conviction", bundle: AppLanguage.bundle, comment: "Fills: Speak ___, every day")
        case .fluent: String(localized: "fluently", bundle: AppLanguage.bundle, comment: "Fills: Speak ___, every day")
        }
    }

    /// How the user walks in: "Walk in calm", "walk into your interview
    /// calm and clear". Written so it fits after any of those sentences.
    var phrase: String {
        switch self {
        case .calm: String(localized: "calm", bundle: AppLanguage.bundle, comment: "Fills: Walk into your interview ___. Use a form that needs no gender agreement.")
        case .clear: String(localized: "clear", bundle: AppLanguage.bundle, comment: "Fills: Walk into your interview ___. Use a form that needs no gender agreement.")
        case .myself: String(localized: "sounding like yourself", bundle: AppLanguage.bundle, comment: "Fills: Walk into your interview ___.")
        case .getTheYes: String(localized: "ready to get the yes", bundle: AppLanguage.bundle, comment: "Fills: Walk into your interview ___.")
        case .fluent: String(localized: "fluent", bundle: AppLanguage.bundle, comment: "Fills: Walk into your interview ___. Use a form that needs no gender agreement.")
        }
    }
}

// MARK: - The demo

/// A rehearsal in miniature, played under the user's thumb: the partner's
/// line, a first take full of fillers, the fillers lifting off, and a retry
/// that lands. The first take marks its fillers in braces.
struct DemoScript {
    let partner: String
    let prompt: String
    let firstTake: String
    let betterTake: String
    /// What "hear it back" says, in one line.
    let note: String

    struct Word: Identifiable, Equatable {
        let id: Int
        let text: String
        let isFiller: Bool
    }

    var firstWords: [Word] { Self.words(firstTake, idBase: 0) }
    var betterWords: [Word] { Self.words(betterTake, idBase: 1000) }

    /// Whether this language writes spaces between words. Japanese and
    /// Chinese don't, so their words sit flush against each other.
    static var spacesWords: Bool { !["ja", "zh"].contains(AppLanguage.code) }

    /// Splits a take into words, flagging everything inside `{…}`. Languages
    /// without spaces are cut into words by the system's tokenizer, with
    /// punctuation kept on the word before it.
    static func words(_ take: String, idBase: Int) -> [Word] {
        var words: [Word] = []
        var remaining = Substring(take)
        while !remaining.isEmpty {
            let isFiller = remaining.hasPrefix("{")
            let segment: Substring
            if isFiller {
                let end = remaining.firstIndex(of: "}") ?? remaining.endIndex
                segment = remaining[remaining.index(after: remaining.startIndex)..<end]
                remaining = end < remaining.endIndex ? remaining[remaining.index(after: end)...] : ""
            } else {
                let end = remaining.firstIndex(of: "{") ?? remaining.endIndex
                segment = remaining[..<end]
                remaining = remaining[end...]
            }
            for text in pieces(String(segment)) {
                words.append(Word(id: idBase + words.count, text: text, isFiller: isFiller))
            }
        }
        return words
    }

    private static func pieces(_ segment: String) -> [String] {
        let trimmed = segment.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        if trimmed.contains(" ") || spacesWords {
            return trimmed.split(separator: " ").map(String.init)
        }
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = trimmed
        var result: [String] = []
        var cursor = trimmed.startIndex
        tokenizer.enumerateTokens(in: trimmed.startIndex..<trimmed.endIndex) { range, _ in
            // Punctuation between words rides on the word before it.
            if range.lowerBound > cursor, !result.isEmpty {
                result[result.count - 1] += trimmed[cursor..<range.lowerBound]
            }
            result.append(String(trimmed[range]))
            cursor = range.upperBound
            return true
        }
        if cursor < trimmed.endIndex {
            if result.isEmpty { result.append(String(trimmed[cursor...])) } else { result[result.count - 1] += trimmed[cursor...] }
        }
        return result
    }

    static func `for`(_ moment: SpeakingMoment) -> DemoScript {
        return switch moment {
        case .interview:
            DemoScript(
                partner: String(localized: "Your interviewer", bundle: AppLanguage.bundle),
                prompt: String(localized: "Tell me about yourself.", bundle: AppLanguage.bundle),
                firstTake: String(localized: "{Um, so,} I grew up in Ohio, then I studied {like,} design, {and basically} I make tools now. {I guess.}", bundle: AppLanguage.bundle, comment: "Demo first take. Mark this language's own filler words in {braces} and keep the braces."),
                betterTake: String(localized: "I'm a designer who turns messy problems into simple tools. Lately, a booking app for local clinics.", bundle: AppLanguage.bundle),
                note: String(localized: "Lead with who you are now.", bundle: AppLanguage.bundle)
            )
        case .raise:
            DemoScript(
                partner: String(localized: "Your manager", bundle: AppLanguage.bundle),
                prompt: String(localized: "You wanted to talk?", bundle: AppLanguage.bundle),
                firstTake: String(localized: "{Yeah, um,} sorry to bother you, I know budgets are tight, {but, like,} maybe my pay could {sort of} go up?", bundle: AppLanguage.bundle, comment: "Demo first take. Mark this language's own filler words in {braces} and keep the braces."),
                betterTake: String(localized: "I'd like to talk about my pay. This year I took on the launch and grew it 30%.", bundle: AppLanguage.bundle),
                note: String(localized: "No apology. The ask, then the evidence.", bundle: AppLanguage.bundle)
            )
        case .hardConversation:
            DemoScript(
                partner: String(localized: "Your coworker", bundle: AppLanguage.bundle),
                prompt: String(localized: "What's up?", bundle: AppLanguage.bundle),
                firstTake: String(localized: "{So, um,} it's probably nothing, but you {kind of} always move my deadlines. {You know?}", bundle: AppLanguage.bundle, comment: "Demo first take. Mark this language's own filler words in {braces} and keep the braces."),
                betterTake: String(localized: "When the deadline moved without warning, I got stuck. Can we flag changes early?", bundle: AppLanguage.bundle),
                note: String(localized: "Name the moment, not the person.", bundle: AppLanguage.bundle)
            )
        case .presentation:
            DemoScript(
                partner: String(localized: "The room", bundle: AppLanguage.bundle),
                prompt: String(localized: "Whenever you're ready.", bundle: AppLanguage.bundle),
                firstTake: String(localized: "{Hi, so, um,} I'm going to talk about {like,} our results. {And stuff, I guess.}", bundle: AppLanguage.bundle, comment: "Demo first take. Mark this language's own filler words in {braces} and keep the braces."),
                betterTake: String(localized: "Last quarter, one change doubled our sign-ups. Here's what it was.", bundle: AppLanguage.bundle),
                note: String(localized: "Open with the most interesting thing you know.", bundle: AppLanguage.bundle)
            )
        case .speakingUp:
            DemoScript(
                partner: String(localized: "Your team", bundle: AppLanguage.bundle),
                prompt: String(localized: "Okay, moving on…", bundle: AppLanguage.bundle),
                firstTake: String(localized: "{Sorry, um,} this is probably wrong, but {I think, like,} we're missing the cost side?", bundle: AppLanguage.bundle, comment: "Demo first take. Mark this language's own filler words in {braces} and keep the braces."),
                betterTake: String(localized: "Can I add one thing? We're missing the cost side.", bundle: AppLanguage.bundle),
                note: String(localized: "Ask for the floor. No disclaimers.", bundle: AppLanguage.bundle)
            )
        case .meetingPeople:
            DemoScript(
                partner: String(localized: "Someone new", bundle: AppLanguage.bundle),
                prompt: String(localized: "So, what do you do?", bundle: AppLanguage.bundle),
                firstTake: String(localized: "{Oh, um,} nothing interesting, {really.} I'm {like,} a teacher. {I guess.}", bundle: AppLanguage.bundle, comment: "Demo first take. Mark this language's own filler words in {braces} and keep the braces."),
                betterTake: String(localized: "I teach kids to code. One just built a game about his cat. You?", bundle: AppLanguage.bundle),
                note: String(localized: "A detail, then a question back.", bundle: AppLanguage.bundle)
            )
        case .everyday:
            DemoScript(
                partner: String(localized: "A friend", bundle: AppLanguage.bundle),
                prompt: String(localized: "What do you think?", bundle: AppLanguage.bundle),
                firstTake: String(localized: "{Um, I don't know,} it's probably fine, {I guess?} {Like,} whatever works.", bundle: AppLanguage.bundle, comment: "Demo first take. Mark this language's own filler words in {braces} and keep the braces."),
                betterTake: String(localized: "I think it works, but the timing's risky. I'd test it first.", bundle: AppLanguage.bundle),
                note: String(localized: "Say what you think, then one reason.", bundle: AppLanguage.bundle)
            )
        }
    }
}

// MARK: - Where they heard of us

/// Asked after the paywall, never before it: an answer here earns the
/// business nothing if the user left at step four to give it.
enum AcquisitionSource: String, Codable, CaseIterable, Identifiable {
    case appStore, tiktok, instagram, youtube, friend, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appStore: String(localized: "App Store search", bundle: AppLanguage.bundle)
        case .tiktok: "TikTok"
        case .instagram: "Instagram"
        case .youtube: "YouTube"
        case .friend: String(localized: "A friend or colleague", bundle: AppLanguage.bundle)
        case .other: String(localized: "Somewhere else", bundle: AppLanguage.bundle)
        }
    }

    var icon: String {
        switch self {
        case .appStore: "magnifyingglass"
        case .tiktok: "music.note"
        case .instagram: "camera"
        case .youtube: "play.rectangle"
        case .friend: "person.2"
        case .other: "ellipsis"
        }
    }
}
