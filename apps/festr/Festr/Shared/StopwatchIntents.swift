import AppIntents

struct StartStopwatchIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Start stopwatch"
    @MainActor func perform() async throws -> some IntentResult {
        try await StopwatchController.shared.perform(.start)
        return .result()
    }
}

struct StopStopwatchIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Stop stopwatch"
    @MainActor func perform() async throws -> some IntentResult {
        try await StopwatchController.shared.perform(.stop)
        return .result()
    }
}

struct LapStopwatchIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Lap"
    @MainActor func perform() async throws -> some IntentResult {
        try await StopwatchController.shared.perform(.lap)
        return .result()
    }
}

struct ResetStopwatchIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Reset stopwatch"
    @MainActor func perform() async throws -> some IntentResult {
        try await StopwatchController.shared.perform(.reset)
        return .result()
    }
}
