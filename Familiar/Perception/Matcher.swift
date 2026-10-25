import Foundation
import Accelerate

struct MatcherConfig: Equatable {
    /// Cosine similarity needed to accept the best person.
    var threshold: Float = 0.40
    /// Best must beat the runner-up person by this much (only meaningful with two or more people enrolled).
    var margin: Float = 0.08
    /// Consistent accepted votes before a track's label is shown.
    var lockVotes: Int = 3
    /// Votes never accumulate past this, so a handful of conflicting votes can still unlock.
    var maxVotes: Int = 6
    static let `default` = MatcherConfig()
}

struct MatchResult: Equatable {
    let personID: UUID?
    let name: String?
    let bestScore: Float
    let secondBestPersonScore: Float
    let accepted: Bool
    static let none = MatchResult(personID: nil, name: nil, bestScore: 0, secondBestPersonScore: 0, accepted: false)
}

/// Cosine matching against every embedding of every person in a `Gallery`. Pure value type; call with a fresh
/// `gallery()` snapshot at every match.
struct Matcher {
    var config: MatcherConfig

    init(config: MatcherConfig = .default) { self.config = config }

    static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0, na: Float = 0, nb: Float = 0
        vDSP_dotpr(a, 1, b, 1, &dot, vDSP_Length(a.count))
        vDSP_svesq(a, 1, &na, vDSP_Length(a.count))
        vDSP_svesq(b, 1, &nb, vDSP_Length(b.count))
        let denom = sqrt(na) * sqrt(nb)
        return denom > 1e-9 ? dot / denom : 0
    }

    static func normalized(_ v: [Float]) -> [Float] {
        var ss: Float = 0
        vDSP_svesq(v, 1, &ss, vDSP_Length(v.count))
        let n = sqrt(ss)
        guard n > 1e-9 else { return v }
        var out = [Float](repeating: 0, count: v.count)
        var scale = 1 / n
        vDSP_vsmul(v, 1, &scale, &out, 1, vDSP_Length(v.count))
        return out
    }

    /// Per-person best score (max over that person's embeddings), then threshold + margin.
    func match(_ vector: [Float], gallery: Gallery, modelID: String) -> MatchResult {
        guard gallery.modelID == modelID || gallery.people.isEmpty else { return .none }
        var ranked: [(personID: UUID, name: String, score: Float)] = []
        for p in gallery.people {
            var best: Float = -1
            for e in p.embeddings where e.count == vector.count { best = max(best, Self.cosine(vector, e)) }
            if best > -1 { ranked.append((p.personID, p.name, best)) }
        }
        ranked.sort { $0.score > $1.score }
        guard let top = ranked.first else { return .none }
        let second = ranked.dropFirst().first?.score ?? 0
        let accepted = top.score >= config.threshold && (top.score - second) >= config.margin
        return MatchResult(personID: accepted ? top.personID : nil, name: accepted ? top.name : nil,
                           bestScore: top.score, secondBestPersonScore: second, accepted: accepted)
    }
}

/// Per-track identity voting: lock after `lockVotes` consistent accepted votes, a conflicting accepted vote
/// decrements, unlock when the count drops below 1. Rejected votes are neutral once locked (a head turn should
/// not flicker the label) and decrement while still tentative.
struct IdentityVotes: Equatable {
    private(set) var candidateID: UUID?
    private(set) var candidateName: String?
    private(set) var count = 0
    private(set) var locked = false
    private(set) var lastScore: Float?
    private(set) var lastBestScore: Float?
    /// Set by `assignIdentity`; the label is pinned until the track dies.
    private(set) var pinned = false
    var config: MatcherConfig

    init(config: MatcherConfig = .default) { self.config = config }

    var identity: Identity {
        if locked, let id = candidateID, let name = candidateName {
            return .known(personID: id, name: name, score: lastScore ?? lastBestScore ?? 0)
        }
        return .unknown(bestScore: lastBestScore)
    }

    /// Returns true when this vote flipped the track from unknown to known.
    @discardableResult
    mutating func record(_ r: MatchResult) -> Bool {
        lastBestScore = r.bestScore
        guard !pinned else { if r.accepted, r.personID == candidateID { lastScore = r.bestScore }; return false }
        let wasLocked = locked
        if r.accepted, let id = r.personID {
            if candidateID == id {
                count = min(config.maxVotes, count + 1)
                lastScore = r.bestScore
            } else if candidateID == nil || count <= 0 {
                candidateID = id; candidateName = r.name; count = 1; lastScore = r.bestScore
            } else {
                count -= 1
            }
        } else if !locked {
            count = max(0, count - 1)
        }
        if count < 1 { candidateID = nil; candidateName = nil; locked = false; lastScore = nil }
        else if count >= config.lockVotes { locked = true }
        return !wasLocked && locked
    }

    mutating func assign(personID: UUID, name: String, score: Float = 1) {
        candidateID = personID; candidateName = name; count = config.maxVotes; locked = true; pinned = true; lastScore = score
    }
}
