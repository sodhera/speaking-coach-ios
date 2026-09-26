import Foundation
import NaturalLanguage

/// The one-breath speaking prompt behind the daily reminder and "speak to
/// unlock": small enough to do standing in a doorway, real enough to count.
struct DailyPrompt: Equatable, Identifiable {
    enum Kind: String, Equatable { case sayIt, answer, describe }

    let id: String
    let kind: Kind
    let instruction: String
    let prompt: String
    /// For `describe`: words that show the scene was actually described.
    var keywords: [String] = []

    /// Rotates once a day, the same all day.
    static func today(_ now: Date = .now, calendar: Calendar = .current) -> DailyPrompt {
        // Picture prompts check for English keywords, so they're English only;
        // the lines to say and the open questions are written in every language.
        let pool = AppLanguage.code == "en" ? all : all.filter { $0.kind != .describe }
        let day = calendar.ordinality(of: .day, in: .era, for: now) ?? 0
        return pool[day % pool.count]
    }

    static var all: [DailyPrompt] { [
        DailyPrompt(id: "say-steady", kind: .sayIt, instruction: String(localized: "Say this out loud, slowly.", bundle: AppLanguage.bundle),
                    prompt: String(localized: "I can take a breath, choose my words, and say what I mean.", bundle: AppLanguage.bundle)),
        DailyPrompt(id: "answer-today", kind: .answer, instruction: String(localized: "Answer in one full sentence.", bundle: AppLanguage.bundle),
                    prompt: String(localized: "What is one thing you want to get done today, and why?", bundle: AppLanguage.bundle)),
        DailyPrompt(id: "describe-cafe", kind: .describe, instruction: "Picture this and describe it in a sentence: ☕️ 🌧️ 📖",
                    prompt: "Someone reading in a café while it rains outside.",
                    keywords: ["reading", "book", "cafe", "café", "coffee", "rain", "raining", "outside", "window"]),
        DailyPrompt(id: "answer-proud", kind: .answer, instruction: String(localized: "Answer with one detail.", bundle: AppLanguage.bundle),
                    prompt: String(localized: "What's something small you did recently that you're proud of?", bundle: AppLanguage.bundle)),
        DailyPrompt(id: "say-pause", kind: .sayIt, instruction: String(localized: "Say this out loud, with a pause at the comma.", bundle: AppLanguage.bundle),
                    prompt: String(localized: "When I slow down, people listen more closely.", bundle: AppLanguage.bundle)),
        DailyPrompt(id: "answer-explain", kind: .answer, instruction: String(localized: "Explain it as if to a friend.", bundle: AppLanguage.bundle),
                    prompt: String(localized: "Describe your job or your studies in two sentences.", bundle: AppLanguage.bundle)),
        DailyPrompt(id: "describe-station", kind: .describe, instruction: "Picture this and describe what's happening: 🚉 🧳 🕘",
                    prompt: "Travellers with bags waiting for a train at a busy station.",
                    keywords: ["train", "station", "bag", "bags", "luggage", "waiting", "people", "travellers", "travelers", "platform"]),
        DailyPrompt(id: "answer-disagree", kind: .answer, instruction: String(localized: "Give your view and one reason.", bundle: AppLanguage.bundle),
                    prompt: String(localized: "What's an opinion you hold that many people disagree with?", bundle: AppLanguage.bundle)),
        DailyPrompt(id: "say-ask", kind: .sayIt, instruction: String(localized: "Say this out loud, like you mean it.", bundle: AppLanguage.bundle),
                    prompt: String(localized: "Could you say a little more about what you need from me?", bundle: AppLanguage.bundle)),
        DailyPrompt(id: "answer-recommend", kind: .answer, instruction: String(localized: "Recommend it in two sentences.", bundle: AppLanguage.bundle),
                    prompt: String(localized: "What's a book, show, or place you'd recommend, and what makes it good?", bundle: AppLanguage.bundle)),
        DailyPrompt(id: "answer-weekend", kind: .answer, instruction: String(localized: "Answer with a reason.", bundle: AppLanguage.bundle),
                    prompt: String(localized: "What would make this weekend feel well spent?", bundle: AppLanguage.bundle)),
        DailyPrompt(id: "say-no", kind: .sayIt, instruction: String(localized: "Say this out loud, calmly.", bundle: AppLanguage.bundle),
                    prompt: String(localized: "I can't take that on this week, but I can help next Monday.", bundle: AppLanguage.bundle)),
    ] }

    struct Result: Equatable {
        let passed: Bool
        let note: String
    }

    /// A kind check, never a gate on accent or grammar: it asks only that
    /// you really spoke — the words in order for a line, enough of your own
    /// words for a question, the scene for a picture.
    func evaluate(_ transcript: String) -> Result {
        let spoken = Self.words(transcript)
        guard spoken.count >= 3 else {
            return Result(passed: false, note: String(localized: "We didn't catch enough. Try once more, a little closer to the phone.", bundle: AppLanguage.bundle))
        }
        switch kind {
        case .sayIt:
            let expected = Self.words(prompt)
            var cursor = 0
            var matches = 0
            for word in spoken {
                if let index = expected[cursor...].firstIndex(of: word) {
                    matches += 1
                    cursor = index + 1
                    if cursor >= expected.count { break }
                }
            }
            let coverage = Double(matches) / Double(max(expected.count, 1))
            return coverage >= 0.65
                ? Result(passed: true, note: String(localized: "Clear. That landed.", bundle: AppLanguage.bundle))
                : Result(passed: false, note: String(localized: "Close. Try it again, keeping the words in order.", bundle: AppLanguage.bundle))
        case .answer:
            let passed = spoken.count >= 6 && Set(spoken).count >= 5
            return passed
                ? Result(passed: true, note: String(localized: "That's a real answer. Nicely done.", bundle: AppLanguage.bundle))
                : Result(passed: false, note: String(localized: "Add one detail or reason, then try again.", bundle: AppLanguage.bundle))
        case .describe:
            let hits = Set(keywords.map { $0.lowercased() }).intersection(spoken).count
            let passed = spoken.count >= 5 && hits >= 2
            return passed
                ? Result(passed: true, note: String(localized: "Good. You painted the scene.", bundle: AppLanguage.bundle))
                : Result(passed: false, note: String(localized: "Mention two things happening in the scene, then try again.", bundle: AppLanguage.bundle))
        }
    }

    /// The words in a line, lowercased. Cut by the system's tokenizer, so
    /// languages written without spaces (Japanese, Chinese) count too.
    static func words(_ text: String) -> [String] {
        let lowered = text.lowercased()
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = lowered
        return tokenizer.tokens(for: lowered.startIndex..<lowered.endIndex).map { String(lowered[$0]) }
    }
}
