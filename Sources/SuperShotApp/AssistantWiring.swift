import AI
import Editor
import Settings

@MainActor enum AssistantWiring {
    static var factory: AssistantFactory = { Assistant.service(for: $0) }

    static func options(_ preferences: AssistantPreferences) -> AskOptions? {
        guard let provider = AssistantProvider(rawValue: preferences.provider) else { return nil }
        return AskOptions(provider: provider, model: preferences.model, confirmBeforeSending: preferences.confirmBeforeSending,
                          includeRecognizedText: preferences.includeRecognizedText, redactBeforeSending: preferences.redactBeforeSending,
                          suggestions: preferences.suggestions)
    }
}
