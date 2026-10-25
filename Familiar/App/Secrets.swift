import Foundation

/// Values flow Secrets.xcconfig → Info.plist keys → here. Empty strings become nil.
enum Secrets {
    private static func value(_ key: String) -> String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // An unexpanded "$(KEY)" means the xcconfig was missing entirely.
        if trimmed.isEmpty || trimmed.hasPrefix("$(") { return nil }
        return trimmed
    }
    static var elevenLabsAPIKey: String? { value("ELEVENLABS_API_KEY") }
    static var elevenLabsVoiceID: String? { value("ELEVENLABS_VOICE_ID") }
    static var elevenLabsAgentID: String? { value("ELEVENLABS_AGENT_ID") }
    static var elevenLabsModelID: String? { value("ELEVENLABS_MODEL_ID") }
    static var metaModelAPIKey: String? { value("META_MODEL_API_KEY") }
    /// Optional override for the vision model; unset = Meta Model API with `META_MODEL_API_KEY`.
    static var visionAPIURL: URL? { value("VISION_API_URL").flatMap(URL.init(string:)) }
    static var visionAPIKey: String? { value("VISION_API_KEY") }
    static var visionModel: String? { value("VISION_MODEL") }
    static var modalEmbedURL: URL? { value("MODAL_EMBED_URL").flatMap(URL.init(string:)) }
    static var modalKey: String? { value("MODAL_KEY") }
    static var modalSecret: String? { value("MODAL_SECRET") }
}
