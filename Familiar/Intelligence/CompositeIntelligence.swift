import Foundation
import QuartzCore

/// Regex first (instant, returns when confidence ≥ 0.7); otherwise races Foundation Models and Meta,
/// first result with confidence ≥ 0.6 wins (Foundation Models preferred on a tie); 15 s overall.
struct CompositeNameExtractor: NameExtractor {
    let regex: NameExtractor
    let foundationModels: NameExtractor?
    let meta: NameExtractor?
    var regexThreshold = 0.7
    var raceThreshold = 0.6
    var overallTimeout: TimeInterval = 15

    func otherPersonName(segments: [TranscriptSegment], userName: String) async -> NameGuess {
        let quick = await regex.otherPersonName(segments: segments, userName: userName)
        if quick.name != nil, quick.confidence >= regexThreshold { return quick }
        let racers: [(String, NameExtractor)] = [("fm", foundationModels), ("meta", meta)].compactMap { k, v in v.map { (k, $0) } }
        guard !racers.isEmpty else { return quick }
        let threshold = raceThreshold
        let timeout = overallTimeout
        let winner: NameGuess? = await withTaskGroup(of: NameGuess?.self) { group in
            for (_, extractor) in racers {
                group.addTask { await extractor.otherPersonName(segments: segments, userName: userName) }
            }
            group.addTask { try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000)); return nil }
            var fallback: NameGuess?
            for await raw in group {
                guard let raw else { break }   // timeout fired
                let result = raw.name?.lowercased() == userName.lowercased() ? NameGuess(name: nil, confidence: 0, source: raw.source) : raw
                if result.name != nil, result.confidence >= threshold { group.cancelAll(); return result }
                if result.name != nil, (fallback == nil || result.confidence > fallback!.confidence || (result.confidence == fallback!.confidence && result.source == "fm")) { fallback = result }
            }
            group.cancelAll()
            return fallback
        }
        if let winner, winner.confidence >= (quick.name == nil ? 0 : quick.confidence) { return winner }
        return quick
    }
}

/// Rules first; anything else → Foundation Models, then Meta (4 s), then `.unclear`.
struct CompositeYesNoClassifier: YesNoClassifier {
    let rules: YesNoClassifier
    let foundationModels: YesNoClassifier?
    let meta: YesNoClassifier?
    var timeout: TimeInterval = 4

    func classify(_ reply: String) async -> YesNo {
        let r = await rules.classify(reply)
        if r != .unclear { return r }
        if let fm = foundationModels {
            let v = await fm.classify(reply)
            if v != .unclear { return v }
        }
        if let meta {
            let v = await withTimeout(timeout) { await meta.classify(reply) } ?? .unclear
            if v != .unclear { return v }
        }
        return .unclear
    }
}

/// Runs `body` with a deadline; nil when the deadline hits first.
func withTimeout<T: Sendable>(_ seconds: TimeInterval, _ body: @escaping @Sendable () async -> T) async -> T? {
    await withTaskGroup(of: T?.self) { group in
        group.addTask { await body() }
        group.addTask { try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000)); return nil }
        let first = await group.next() ?? nil
        group.cancelAll()
        return first
    }
}

/// Background loop: on each new `other` final segment that looks like an introduction, and every 20 s while an
/// unknown track is close, refresh the name guess for the current track-session. Reset when no unknowns remain.
@MainActor
final class NameGuessCache: ObservableObject {
    @Published private(set) var guess: NameGuess?
    @Published private(set) var lastRefreshAt: TimeInterval?
    private let extractor: NameExtractor
    private let userName: () -> String
    private let clock: () -> TimeInterval
    private var tasks: [Task<Void, Never>] = []
    private var refreshing = false
    var periodicInterval: TimeInterval = 20
    var transcriptWindow: TimeInterval = 90

    init(extractor: NameExtractor, userName: @escaping () -> String, clock: @escaping () -> TimeInterval = { CACurrentMediaTime() }) {
        self.extractor = extractor
        self.userName = userName
        self.clock = clock
    }

    func start(transcriber: Transcriber, perception: Perception) {
        stop()
        tasks.append(Task { [weak self] in
            for await seg in transcriber.subscribe() {
                guard let self else { return }
                if seg.isFinal, seg.speaker == .other, RegexNameExtractor.looksLikeIntroduction(seg.text) {
                    await self.refresh(transcriber: transcriber)
                }
            }
        })
        tasks.append(Task { [weak self] in
            var lastPeriodic: TimeInterval = 0
            for await event in perception.subscribe() {
                guard let self else { return }
                guard case let .snapshot(tracks, _) = event else { continue }
                let unknowns = tracks.filter { !$0.identity.isKnown }
                if unknowns.isEmpty { if self.guess != nil { self.guess = nil }; continue }
                let now = self.clock()
                if unknowns.contains(where: { $0.distance == .close }), now - lastPeriodic >= self.periodicInterval {
                    lastPeriodic = now
                    await self.refresh(transcriber: transcriber)
                }
            }
        })
    }

    func stop() { tasks.forEach { $0.cancel() }; tasks.removeAll() }

    func refresh(transcriber: Transcriber) async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        let segments = transcriber.recentSegments(seconds: transcriptWindow)
        let g = await extractor.otherPersonName(segments: segments, userName: userName())
        lastRefreshAt = clock()
        if g.name != nil || guess == nil { guess = g }
    }

    func reset() { guess = nil }
}

/// Builds the intelligence stack from the keys that are present. S5 calls this from `Services.make`.
enum IntelligenceFactory {
    struct Bundle {
        let metaClient: MetaModelClient?
        let nameExtractor: NameExtractor
        let yesNo: YesNoClassifier
        let foundationModelsName: FoundationModelsNameExtractor?
    }

    static func make(metaAPIKey: String? = Secrets.metaModelAPIKey, useFoundationModels: Bool = true, useMeta: Bool = true) -> Bundle {
        let meta = (useMeta && !(metaAPIKey ?? "").isEmpty) ? MetaModelClient(apiKey: metaAPIKey) : nil
        let fm = useFoundationModels && FoundationModelsSupport.isAvailable ? FoundationModelsNameExtractor() : nil
        fm?.prewarm()
        let name = CompositeNameExtractor(regex: RegexNameExtractor(), foundationModels: fm, meta: meta.map { MetaNameExtractor(client: $0) })
        let yesNo = CompositeYesNoClassifier(rules: RulesYesNoClassifier(), foundationModels: fm == nil ? nil : FoundationModelsYesNoClassifier(), meta: meta.map { MetaYesNoClassifier(client: $0) })
        return Bundle(metaClient: meta, nameExtractor: name, yesNo: yesNo, foundationModelsName: fm)
    }
}
