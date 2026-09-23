import Foundation

// Everything the onboarding says, in one place. Copy rule: a kicker, one big
// line, one small line. If a screen needs a paragraph, the screen is wrong.

// MARK: - The category

/// The four doors the app is marketed through, and the first real question.
/// Each is a situation people already name themselves by ("I have a
/// presentation", "I'm taking IELTS"), so the ad, the store listing and this
/// screen all say the same thing. The boundary between the two work doors:
/// **Presentations** is speaking to a room; **Work** is one-to-one or a meeting.
enum SpeakingCategory: String, Codable, CaseIterable, Identifiable {
    case work, presentations, ielts, everyday

    var id: String { rawValue }

    var title: String {
        switch self {
        case .work: "Work"
        case .presentations: "Presentations"
        case .ielts: "IELTS Speaking"
        case .everyday: "Everyday conversations"
        }
    }

    var icon: String {
        switch self {
        case .work: "briefcase"
        case .presentations: "person.wave.2"
        case .ielts: "graduationcap"
        case .everyday: "bubble.left.and.bubble.right"
        }
    }

    /// The situations inside the door. A door with one situation skips the
    /// second question — the answer is already given.
    var moments: [SpeakingMoment] {
        switch self {
        case .work: [.interview, .raise, .hardConversation, .speakingUp]
        case .presentations: [.presentation]
        case .ielts: [.ielts]
        case .everyday: [.meetingPeople, .everyday]
        }
    }

    /// IELTS is an English exam: it's only offered to someone practicing English.
    static func available(forPracticeLanguage language: String) -> [SpeakingCategory] {
        language == "en" ? allCases : allCases.filter { $0 != .ielts }
    }
}

// MARK: - The moment

enum SpeakingMoment: String, Codable, CaseIterable, Identifiable {
    case interview, raise, hardConversation, presentation, speakingUp, meetingPeople, everyday, ielts

    var id: String { rawValue }

    var category: SpeakingCategory {
        SpeakingCategory.allCases.first { $0.moments.contains(self) } ?? .work
    }

    var title: String {
        switch self {
        case .interview: "A job interview"
        case .raise: "Asking for a raise"
        case .hardConversation: "A hard conversation"
        case .presentation: "A presentation or pitch"
        case .speakingUp: "Speaking up at work"
        case .meetingPeople: "Meeting new people"
        case .everyday: "Speaking better, day to day"
        case .ielts: "The IELTS Speaking test"
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
        case .ielts: "graduationcap"
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
        case .ielts: "your speaking test"
        }
    }

    /// No single event ahead — the user wants to speak better in general.
    /// There's no date to ask about, and no "walk into" to promise.
    var isGeneral: Bool { self == .everyday }

    /// Sentence-initial form of `noun` for headlines.
    var nounCapitalized: String { noun.prefix(1).uppercased() + noun.dropFirst() }

    /// The rehearsal this moment starts with: from the shared catalog, or a
    /// scene built into the app where the catalog has none yet.
    var firstPractice: PracticeDefinition? {
        if let builtInSituation { return builtInSituation.definition }
        return PracticeCatalog.definition(catalogPracticeID)
    }

    /// Set where the server's catalog has no rehearsal for this moment yet.
    /// It runs on the custom-situation endpoints the app already uses.
    var builtInSituation: CustomSituation? {
        self == .ielts ? .ieltsSpeaking : nil
    }

    private var catalogPracticeID: String {
        switch self {
        case .interview: "interview_tell_me_about_yourself"
        case .raise: "salary_raise"
        case .hardConversation: "set_a_boundary"
        case .presentation: "presentation_opening"
        case .speakingUp: "disagree_in_meeting"
        case .meetingPeople: "meet_someone_new"
        case .everyday: "first_gentle_introduction"
        case .ielts: ""
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

    var timingQuestion: String {
        switch self {
        case .meetingPeople, .speakingUp: "When's the next one?"
        case .ielts: "When is your test?"
        default: "When is it?"
        }
    }

    /// The outcomes worth offering for this moment. "I get what I asked
    /// for" means nothing in an exam or a chat; fluency means everything.
    var outcomeOptions: [SpeakingOutcome] {
        switch self {
        case .ielts, .meetingPeople, .everyday: [.calm, .clear, .fluent, .myself]
        default: [.calm, .clear, .myself, .getTheYes]
        }
    }

    /// The promise, in the user's own outcomes: "and you'll walk into your
    /// interview calm and clear." Strong on purpose — it names the result
    /// they asked for — but never a number we can't measure.
    func promise(outcomes: Set<SpeakingOutcome>) -> String {
        let chosen = SpeakingOutcome.allCases.filter(outcomes.contains).prefix(2)
        if isGeneral {
            let how = chosen.isEmpty ? "with ease" : chosen.map(\.adverb).joined(separator: " and ")
            return "and you'll speak \(how), every day."
        }
        let how = chosen.isEmpty ? "ready" : chosen.map(\.headlinePhrase).joined(separator: " and ")
        return self == .meetingPeople ? "and you'll walk into any room \(how)." : "and you'll walk into \(noun) \(how)."
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
    case calm, clear, myself, getTheYes, fluent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .calm: "I stay calm"
        case .clear: "I say it clearly, the first time"
        case .myself: "I sound like myself"
        case .getTheYes: "I get what I asked for"
        case .fluent: "I keep going, without freezing"
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

    /// The outcome as a manner of speaking, for general-improvement copy:
    /// "Speak calmly and clearly, every day."
    var adverb: String {
        switch self {
        case .calm: "calmly"
        case .clear: "clearly"
        case .myself: "like yourself"
        case .getTheYes: "with conviction"
        case .fluent: "fluently"
        }
    }

    /// The outcome as a short adjective phrase, for the plan's last step:
    /// "Walk in clear".
    var phrase: String {
        switch self {
        case .calm: "calm"
        case .clear: "clear"
        case .myself: "like yourself"
        case .getTheYes: "ready to get the yes"
        case .fluent: "fluent"
        }
    }

    /// The outcome after "Walk into your interview …", for the promise and
    /// the paywall headline.
    var headlinePhrase: String {
        switch self {
        case .myself: "sounding like yourself"
        default: phrase
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
    /// Fillers as a listener hears them: "and basically" is one, not two.
    var fillerCount: Int { firstTake.filter { $0 == "{" }.count }

    /// Splits a take into words, flagging everything inside `{…}`.
    static func words(_ take: String, idBase: Int) -> [Word] {
        var words: [Word] = []
        var inFiller = false
        for raw in take.split(separator: " ") {
            var text = String(raw)
            let opens = text.hasPrefix("{")
            if opens { inFiller = true; text.removeFirst() }
            let closes = text.contains("}")
            text = text.replacingOccurrences(of: "}", with: "")
            if !text.isEmpty { words.append(Word(id: idBase + words.count, text: text, isFiller: inFiller)) }
            if closes { inFiller = false }
        }
        return words
    }

    static func `for`(_ moment: SpeakingMoment) -> DemoScript {
        switch moment {
        case .interview:
            DemoScript(
                partner: "Your interviewer",
                prompt: "“Tell me about yourself.”",
                firstTake: "{Um, so,} I grew up in Ohio, then I studied {like,} design, {and basically} I make tools now. {I guess.}",
                betterTake: "I'm a designer who turns messy problems into simple tools — most recently at Acme.",
                note: "Lead with who you are now."
            )
        case .raise:
            DemoScript(
                partner: "Your manager",
                prompt: "“You wanted to talk?”",
                firstTake: "{Yeah, um,} sorry to bother you, I know budgets are tight, {but, like,} maybe my pay could {sort of} go up?",
                betterTake: "I'd like to talk about my pay. This year I took on the launch and grew it 30%.",
                note: "No apology. The ask, then the evidence."
            )
        case .hardConversation:
            DemoScript(
                partner: "Your coworker",
                prompt: "“What's up?”",
                firstTake: "{So, um,} it's probably nothing, but you {kind of} always move my deadlines. {You know?}",
                betterTake: "When the deadline moved without warning, I got stuck. Can we flag changes early?",
                note: "Name the moment, not the person."
            )
        case .presentation:
            DemoScript(
                partner: "The room",
                prompt: "“Whenever you're ready.”",
                firstTake: "{Hi, so, um,} I'm going to talk about {like,} our results. {And stuff, I guess.}",
                betterTake: "Last quarter, one change doubled our sign-ups. Here's what it was.",
                note: "Open with the most interesting thing you know."
            )
        case .speakingUp:
            DemoScript(
                partner: "Your team",
                prompt: "“Okay, moving on…”",
                firstTake: "{Sorry, um,} this is probably wrong, but {I think, like,} we're missing the cost side?",
                betterTake: "Can I add one thing? We're missing the cost side.",
                note: "Ask for the floor. No disclaimers."
            )
        case .meetingPeople:
            DemoScript(
                partner: "Someone new",
                prompt: "“So, what do you do?”",
                firstTake: "{Oh, um,} nothing interesting, {really.} I'm {like,} a teacher. {I guess.}",
                betterTake: "I teach kids to code — one just built a game about his cat. You?",
                note: "A detail, then a question back."
            )
        case .everyday:
            DemoScript(
                partner: "A friend",
                prompt: "“What do you think?”",
                firstTake: "{Um, I don't know,} it's probably fine, {I guess?} {Like,} whatever works.",
                betterTake: "I think it works, but the timing's risky. I'd test it first.",
                note: "Say what you think, then one reason."
            )
        case .ielts:
            DemoScript(
                partner: "Your examiner",
                prompt: "“Do you enjoy cooking?”",
                firstTake: "{Um,} yes. {Like,} I cook {uh,} sometimes. {I guess.}",
                betterTake: "Yes, I love it — especially cooking for friends at the weekend. It's how I relax.",
                note: "Answer, then extend with a reason."
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
        case .appStore: "App Store search"
        case .tiktok: "TikTok"
        case .instagram: "Instagram"
        case .youtube: "YouTube"
        case .friend: "A friend or colleague"
        case .other: "Somewhere else"
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

    /// The language's name in itself — "Deutsch", "Español" — so a German
    /// speaker finds their own language without reading English.
    var autonym: String {
        let own = Locale(identifier: id).localizedString(forLanguageCode: id) ?? name
        return own.prefix(1).uppercased() + own.dropFirst()
    }

    /// The short list the language question opens with: the device's
    /// language first, then the most practiced, then whatever is chosen.
    static func shortList(selected: String) -> [PracticeLanguage] {
        var ids = [deviceDefault, "en", "es", "fr", "de", "it", "pt"]
        if !ids.contains(selected) { ids.append(selected) }
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }.compactMap { id in all.first { $0.id == id } }
    }

    /// The device's language if the partner can speak it, else English.
    static var deviceDefault: String {
        let code = Locale.current.language.languageCode?.identifier ?? "en"
        return all.contains { $0.id == code } ? code : "en"
    }
}
