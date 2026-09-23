import os

enum AppLog {
    private static let logger = Logger(subsystem: "com.sodhera.speakingcoach", category: "app")

    static func info(_ message: String) { logger.info("\(message, privacy: .public)") }
    static func error(_ message: String) { logger.error("\(message, privacy: .public)") }
}
