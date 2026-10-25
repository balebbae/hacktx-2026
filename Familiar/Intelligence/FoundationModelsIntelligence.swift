import Foundation

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26, *)
@Generable
struct NameGuessGen {
    @Guide(description: "First name the OTHER person gave, or empty if none") var name: String
    @Guide(description: "0 to 1") var confidence: Double
}

@available(iOS 26, *)
@Generable
enum YesNoGen { case yes, no, unclear }
#endif

/// On-device Foundation Models (iOS 26). Unavailable in the Simulator and on older phones: every path returns
/// "no answer" quickly so the composite extractors fall through to regex / Meta.
enum FoundationModelsSupport {
    static var availabilityDescription: String {
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return "available"
            case let .unavailable(reason): return "unavailable (\(String(describing: reason)))"
            }
        }
        return "needs iOS 26"
        #else
        return "SDK without FoundationModels"
        #endif
    }

    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26, *) { return SystemLanguageModel.default.availability == .available }
        #endif
        return false
    }
}

final class FoundationModelsNameExtractor: NameExtractor, @unchecked Sendable {
    static let instructions = "You help a blind user remember people they meet. You will read a transcript between USER (the blind wearer) and OTHER (the person they talk to). Give the first name OTHER used for themselves, or an empty string if OTHER never introduced themselves. Never give USER's name."

    #if canImport(FoundationModels)
    @available(iOS 26, *)
    private var session: LanguageModelSession? {
        get { _session as? LanguageModelSession }
        set { _session = newValue }
    }
    #endif
    private var _session: Any?

    func prewarm() {
        #if canImport(FoundationModels)
        if #available(iOS 26, *), FoundationModelsSupport.isAvailable {
            let s = LanguageModelSession(instructions: Self.instructions)
            session = s
            Task { s.prewarm() }
        }
        #endif
    }

    func otherPersonName(segments: [TranscriptSegment], userName: String) async -> NameGuess {
        let empty = NameGuess(name: nil, confidence: 0, source: "fm")
        #if canImport(FoundationModels)
        if #available(iOS 26, *), FoundationModelsSupport.isAvailable {
            let s = session ?? LanguageModelSession(instructions: Self.instructions)
            session = s
            let transcript = MetaModelClient.formatTranscript(segments)
            guard !transcript.isEmpty else { return empty }
            let prompt = "USER's name is \(userName).\n\(transcript)"
            do {
                let response = try await s.respond(to: prompt, generating: NameGuessGen.self, options: GenerationOptions(sampling: .greedy))
                let name = response.content.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty, name.lowercased() != userName.lowercased() else { return empty }
                return NameGuess(name: name, confidence: min(1, max(0, response.content.confidence)), source: "fm")
            } catch {
                // guardrail / refusal / rateLimited / context window / locale: let the race continue
                return empty
            }
        }
        #endif
        return empty
    }
}

final class FoundationModelsYesNoClassifier: YesNoClassifier, @unchecked Sendable {
    static let instructions = "You help a blind user remember people they meet. The user asked someone for permission to remember their face. Classify the reply as yes, no or unclear. Only a clear agreement is yes."

    func classify(_ reply: String) async -> YesNo {
        #if canImport(FoundationModels)
        if #available(iOS 26, *), FoundationModelsSupport.isAvailable {
            let session = LanguageModelSession(instructions: Self.instructions)
            do {
                let response = try await session.respond(to: "REPLY: \(reply)", generating: YesNoGen.self, options: GenerationOptions(sampling: .greedy))
                switch response.content { case .yes: return .yes; case .no: return .no; case .unclear: return .unclear }
            } catch { return .unclear }
        }
        #endif
        return .unclear
    }
}
