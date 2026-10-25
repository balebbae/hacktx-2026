import Foundation
import Vision
import CoreImage
import CoreVideo
import QuartzCore
import os

/// Things the wearer might walk into or down. Spoken immediately (priority 0), each at most once per cooldown.
enum HazardKind: String, CaseIterable, Sendable { case stairs, escalator, crosswalk, obstacle }

enum SceneEvent: Equatable, Sendable {
    case hazard(HazardKind)
    /// The stable place changed (e.g. "kitchen"); spoken only in chatty mode.
    case placeChanged(String)
}

/// Pure decisions over on-device Vision outputs: image labels (≈1 Hz) and looming time-to-contact (≈4 Hz).
/// Never sees people or clothing labels: only the allowlists below can ever be spoken, so strangers are never described.
struct HazardPolicy {
    static let labelHazards: [String: HazardKind] = ["stairs": .stairs, "escalator": .escalator, "crosswalk": .crosswalk]
    static let places: [String: String] = ["kitchen": "kitchen", "bathroom": "bathroom", "bedroom": "bedroom", "living_room": "living room", "dining_room": "dining room",
                                           "classroom": "classroom", "library": "library", "restaurant": "restaurant", "auditorium": "auditorium", "conference": "conference room",
                                           "street": "street", "sidewalk": "sidewalk", "parking_lot": "parking lot", "park": "park", "train_station": "train station",
                                           "hospital": "hospital", "museum": "museum", "stadium": "stadium"]
    static let objects: [String: String] = ["door": "door", "elevator": "elevator", "chair": "chair", "table": "table", "desk": "desk", "bench": "bench", "sofa": "couch",
                                            "bed": "bed", "trash_can": "trash can", "bicycle": "bike", "car": "car", "bus": "bus", "truck": "truck",
                                            "traffic_light": "traffic light", "hydrant": "hydrant", "fence": "fence", "computer": "computer", "television": "TV",
                                            "window": "window", "shopping_cart": "cart", "dog": "dog", "cat": "cat"]

    // shortcut: thresholds picked from the Vision taxonomy docs, not from glasses footage; calibrate on hardware (docs/CALIBRATION.md).
    var hazardConfidence: Float = 0.5
    var hazardVotes = 2
    var hazardWindow = 3
    var obstacleTimeToContact: Double = 1.8
    var obstacleFrames = 2
    var cooldown: TimeInterval = 8
    var placeConfidence: Float = 0.4
    var objectConfidence: Float = 0.35
    var placeHold: TimeInterval = 5

    private var recent: [Set<HazardKind>] = []
    private var looming = 0
    private var lastSpoken: [HazardKind: TimeInterval] = [:]
    private(set) var active: [HazardKind: TimeInterval] = [:]
    private(set) var place: String?
    private(set) var objects: [String] = []
    private var candidatePlace: (name: String, since: TimeInterval)?
    private var announcedPlace: String?

    /// One classification pass. Returns hazards to speak now and, at most once per stable change, the new place.
    mutating func classify(_ labels: [String: Float], now: TimeInterval) -> [SceneEvent] {
        let hits = Set(Self.labelHazards.compactMap { label, kind in (labels[label] ?? 0) >= hazardConfidence ? kind : nil })
        recent.append(hits)
        if recent.count > hazardWindow { recent.removeFirst() }
        var out: [SceneEvent] = []
        for kind in HazardKind.allCases where kind != .obstacle {
            if recent.filter({ $0.contains(kind) }).count >= hazardVotes, let e = fire(kind, now: now) { out.append(e) }
        }

        place = Self.places.filter { (labels[$0.key] ?? 0) >= placeConfidence }.max { labels[$0.key]! < labels[$1.key]! }?.value
        objects = Self.objects.filter { (labels[$0.key] ?? 0) >= objectConfidence }.sorted { labels[$0.key]! > labels[$1.key]! }.prefix(3).map(\.value)
        if let p = place {
            if candidatePlace?.name != p { candidatePlace = (p, now) }
            if let c = candidatePlace, now - c.since >= placeHold, c.name != announcedPlace {
                announcedPlace = c.name
                out.append(.placeChanged(c.name))
            }
        }
        return out
    }

    /// One optical-flow pass: `timeToContact` of the centre of the view in seconds (nil = not approaching anything).
    mutating func flow(timeToContact: Double?, now: TimeInterval) -> SceneEvent? {
        if let ttc = timeToContact, ttc > 0, ttc < obstacleTimeToContact { looming += 1 } else { looming = 0 }
        guard looming >= obstacleFrames else { return nil }
        return fire(.obstacle, now: now)
    }

    private mutating func fire(_ kind: HazardKind, now: TimeInterval) -> SceneEvent? {
        active[kind] = now
        if let last = lastSpoken[kind], now - last < cooldown { return nil }
        lastSpoken[kind] = now
        return .hazard(kind)
    }

    /// "Stairs ahead. Marcus, ahead, close. Kitchen. Table, chair." Hazards seen in the last 5 s first, then the
    /// people (roll call, strangers only counted), then the place, then objects.
    func describe(now: TimeInterval, people: String? = nil) -> String {
        var parts = HazardKind.allCases.filter { (active[$0] ?? -.infinity) > now - 5 }.map(Phrasebook.hazard)
        if let people { parts.append(people) }
        if let place { parts.append(Phrasebook.place(place)) }
        if !objects.isEmpty { parts.append(Phrasebook.place(objects.joined(separator: ", "))) }
        return parts.isEmpty ? Phrasebook.nothingToName : parts.joined(separator: " ")
    }
}

/// Scene and hazard awareness, entirely on the phone: Apple Vision image classification for stairs / escalators /
/// crosswalks and the place, plus optical-flow expansion ("looming") in the centre of the view for obstacles.
/// No frame or crop ever leaves the device.
final class SceneAwareness: @unchecked Sendable {
    var classifyInterval: TimeInterval = 1.0
    var flowInterval: TimeInterval = 0.25
    private let bus = EventBus<SceneEvent>()
    private let policy = OSAllocatedUnfairLock(initialState: HazardPolicy())
    private var task: Task<Void, Never>?
    private let ciContext = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull(), .cacheIntermediates: false])
    private var previous: (buffer: CVPixelBuffer, t: TimeInterval)?
    private var lastClassify: TimeInterval = -.infinity
    private var lastFlow: TimeInterval = -.infinity
    private var loggedFailure = false
    private let log = Logger(subsystem: "familiar", category: "scene")

    func subscribe() -> AsyncStream<SceneEvent> { bus.subscribe() }

    func start(frames: FrameSource) {
        guard task == nil else { return }
        let stream = frames.subscribe()
        task = Task.detached(priority: .utility) { [weak self] in
            for await frame in stream {
                guard let self, !Task.isCancelled else { break }
                self.process(frame)
            }
        }
    }

    func stop() { task?.cancel(); task = nil; previous = nil }

    func describe(people: String? = nil) -> String { policy.withLock { $0.describe(now: CACurrentMediaTime(), people: people) } }

    private func process(_ frame: Frame) {
        let now = frame.timestamp
        if now - lastClassify >= classifyInterval {
            lastClassify = now
            if let labels = classify(frame) {
                for e in policy.withLock({ $0.classify(labels, now: now) }) { bus.publish(e) }
            }
        }
        if now - lastFlow >= flowInterval {
            lastFlow = now
            let ttc = timeToContact(frame)
            if let e = policy.withLock({ $0.flow(timeToContact: ttc, now: now) }) { bus.publish(e) }
        }
    }

    private func classify(_ frame: Frame) -> [String: Float]? {
        let request = VNClassifyImageRequest()
        do {
            try VNImageRequestHandler(cvPixelBuffer: frame.pixelBuffer, orientation: frame.orientation, options: [:]).perform([request])
        } catch {
            failedOnce(error)
            return nil
        }
        var labels: [String: Float] = [:]
        for o in request.results ?? [] where o.confidence >= 0.2 { labels[o.identifier] = o.confidence }
        return labels
    }

    /// Mean divergence of the optical flow in the centre square of a 160 px-wide copy, as seconds to contact.
    /// A surface approaching at time-to-contact τ expands with du/dx + dv/dy = 2Δt/τ; head turns add almost none.
    private func timeToContact(_ frame: Frame) -> Double? {
        guard let small = downscaled(frame.pixelBuffer, width: 160) else { return nil }
        defer { previous = (small, frame.timestamp) }
        guard let prev = previous, frame.timestamp - prev.t > 0.05, frame.timestamp - prev.t < 1,
              CVPixelBufferGetWidth(prev.buffer) == CVPixelBufferGetWidth(small) else { return nil }
        let request = VNGenerateOpticalFlowRequest(targetedCVPixelBuffer: prev.buffer, options: [:])
        request.computationAccuracy = .low
        request.outputPixelFormat = kCVPixelFormatType_TwoComponent32Float
        do { try VNImageRequestHandler(cvPixelBuffer: small, options: [:]).perform([request]) } catch { failedOnce(error); return nil }
        guard let flow = request.results?.first?.pixelBuffer else { return nil }
        // Flow is from `small` toward the previous frame, so expansion since then reads as negative divergence.
        let div = -Self.centreDivergence(flow)
        guard div > 0 else { return nil }
        return 2 * (frame.timestamp - prev.t) / div
    }

    static func centreDivergence(_ flow: CVPixelBuffer) -> Double {
        CVPixelBufferLockBaseAddress(flow, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(flow, .readOnly) }
        let w = CVPixelBufferGetWidth(flow), h = CVPixelBufferGetHeight(flow), rowBytes = CVPixelBufferGetBytesPerRow(flow)
        guard let base = CVPixelBufferGetBaseAddress(flow), w > 8, h > 8 else { return 0 }
        func uv(_ x: Int, _ y: Int) -> (Float, Float) {
            let p = (base + y * rowBytes).assumingMemoryBound(to: Float.self) + 2 * x
            return (p[0], p[1])
        }
        var sum = 0.0, n = 0
        for y in stride(from: Int(Double(h) * 0.3), to: Int(Double(h) * 0.7), by: 2) {
            for x in stride(from: Int(Double(w) * 0.3), to: Int(Double(w) * 0.7), by: 2) {
                let dudx = Double(uv(x + 1, y).0 - uv(x - 1, y).0) / 2
                let dvdy = Double(uv(x, y + 1).1 - uv(x, y - 1).1) / 2
                sum += dudx + dvdy; n += 1
            }
        }
        return n == 0 ? 0 : sum / Double(n)
    }

    private func downscaled(_ pb: CVPixelBuffer, width: Int) -> CVPixelBuffer? {
        let scale = CGFloat(width) / CGFloat(CVPixelBufferGetWidth(pb))
        let h = Int((CGFloat(CVPixelBufferGetHeight(pb)) * scale).rounded())
        var out: CVPixelBuffer?
        let attrs: [CFString: Any] = [kCVPixelBufferIOSurfacePropertiesKey: [:]]
        CVPixelBufferCreate(nil, width, h, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &out)
        guard let out else { return nil }
        ciContext.render(CIImage(cvPixelBuffer: pb).transformed(by: CGAffineTransform(scaleX: scale, y: scale)), to: out)
        return out
    }

    /// The Simulator cannot create Vision inference contexts; say so once instead of once per frame.
    private func failedOnce(_ error: Error) {
        guard !loggedFailure else { return }
        loggedFailure = true
        log.error("scene awareness unavailable: \(error.localizedDescription, privacy: .public)")
    }
}
