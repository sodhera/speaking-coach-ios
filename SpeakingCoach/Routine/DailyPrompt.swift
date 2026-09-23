import Foundation

/// The one-breath speaking prompt behind the daily reminder and "speak to
/// unlock": small enough to do standing in a doorway, real enough to count.
struct DailyPrompt: Equatable, Identifiable {
    enum Kind: Equatable { case sayIt, answer, describe }

    let id: String
    let kind: Kind
    let instruction: String
    let prompt: String
    /// For `describe`: words that show the scene was actually described.
    var keywords: [String] = []

    /// Rotates once a day, the same all day.
    static func today(_ now: Date = .now, language: String = "en", calendar: Calendar = .current) -> DailyPrompt {
        // Reading an English line aloud only works in English; other
        // languages get the open questions, answered in their own words.
        let pool = language == "en" ? all : all.filter { $0.kind == .answer }
        let day = calendar.ordinality(of: .day, in: .era, for: now) ?? 0
        return pool[day % pool.count]
    }

    static let all: [DailyPrompt] = [
        DailyPrompt(id: "say-steady", kind: .sayIt, instruction: "Say this out loud, slowly.",
                    prompt: "I can take a breath, choose my words, and say what I mean."),
        DailyPrompt(id: "answer-today", kind: .answer, instruction: "Answer in one full sentence.",
                    prompt: "What is one thing you want to get done today, and why?"),
        DailyPrompt(id: "describe-cafe", kind: .describe, instruction: "Picture this and describe it in a sentence: ☕️ 🌧️ 📖",
                    prompt: "Someone reading in a café while it rains outside.",
                    keywords: ["reading", "book", "cafe", "café", "coffee", "rain", "raining", "outside", "window"]),
        DailyPrompt(id: "answer-proud", kind: .answer, instruction: "Answer with one detail.",
                    prompt: "What's something small you did recently that you're proud of?"),
        DailyPrompt(id: "say-pause", kind: .sayIt, instruction: "Say this out loud, with a pause at the comma.",
                    prompt: "When I slow down, people listen more closely."),
        DailyPrompt(id: "answer-explain", kind: .answer, instruction: "Explain it as if to a friend.",
                    prompt: "Describe your job or your studies in two sentences."),
        DailyPrompt(id: "describe-station", kind: .describe, instruction: "Picture this and describe what's happening: 🚉 🧳 🕘",
                    prompt: "Travellers with bags waiting for a train at a busy station.",
                    keywords: ["train", "station", "bag", "bags", "luggage", "waiting", "people", "travellers", "travelers", "platform"]),
        DailyPrompt(id: "answer-disagree", kind: .answer, instruction: "Give your view and one reason.",
                    prompt: "What's an opinion you hold that many people disagree with?"),
        DailyPrompt(id: "say-ask", kind: .sayIt, instruction: "Say this out loud, like you mean it.",
                    prompt: "Could you say a little more about what you need from me?"),
        DailyPrompt(id: "answer-recommend", kind: .answer, instruction: "Recommend it in two sentences.",
                    prompt: "What's a book, show, or place you'd recommend, and what makes it good?"),
        DailyPrompt(id: "answer-weekend", kind: .answer, instruction: "Answer with a reason.",
                    prompt: "What would make this weekend feel well spent?"),
        DailyPrompt(id: "say-no", kind: .sayIt, instruction: "Say this out loud, calmly.",
                    prompt: "I can't take that on this week, but I can help next Monday."),
    ]

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
            return Result(passed: false, note: "We didn't catch enough. Try once more, a little closer to the phone.")
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
                ? Result(passed: true, note: "Clear. That landed.")
                : Result(passed: false, note: "Close. Try it again, keeping the words in order.")
        case .answer:
            let passed = spoken.count >= 6 && Set(spoken).count >= 5
            return passed
                ? Result(passed: true, note: "That's a real answer. Nicely done.")
                : Result(passed: false, note: "Add one detail or reason, then try again.")
        case .describe:
            let hits = Set(keywords.map { $0.lowercased() }).intersection(spoken).count
            let passed = spoken.count >= 5 && hits >= 2
            return passed
                ? Result(passed: true, note: "Good. You painted the scene.")
                : Result(passed: false, note: "Mention two things happening in the scene, then try again.")
        }
    }

    static func words(_ text: String) -> [String] {
        text.lowercased()
            .map { $0.isLetter || $0.isNumber || $0 == "'" ? $0 : " " }
            .reduce(into: "") { $0.append($1) }
            .split(separator: " ")
            .map(String.init)
    }
}
