import Foundation
import CoreImage
import CoreGraphics
import QuartzCore
import UIKit
import Vision
import os

/// What the vision model saw in one redacted frame. Positions are horizontal frame fractions (0 = left edge);
/// `bearing(_:)` turns them into the same true-angle bearings the people cues use.
struct SceneReading: Equatable {
    struct Item: Equatable { let name: String; let x: Double; let meters: Double? }
    enum PathStatus: String { case clear, caution, blocked }

    var path: PathStatus
    var pathWhat: String?
    var pathX: Double
    var pathMeters: Double?
    var hazards: [Item]
    var place: String?
    var objects: [Item]
    var signs: [String]
    var summary: String
    var at: TimeInterval
    var hFOV: Double

    func bearing(_ x: Double) -> Bearing { Spatial.bearing(centerX: min(1, max(0, x)), hFOV: hFOV) }

    init(path: PathStatus = .clear, pathWhat: String? = nil, pathX: Double = 0.5, pathMeters: Double? = nil, hazards: [Item] = [], place: String? = nil,
         objects: [Item] = [], signs: [String] = [], summary: String = "", at: TimeInterval = 0, hFOV: Double = GlassesCameraGeometry.horizontalFOVDegrees) {
        self.path = path; self.pathWhat = pathWhat; self.pathX = pathX; self.pathMeters = pathMeters; self.hazards = hazards; self.place = place
        self.objects = objects; self.signs = signs; self.summary = summary; self.at = at; self.hFOV = hFOV
    }

    init?(json o: [String: Any], at: TimeInterval, hFOV: Double) {
        func str(_ v: Any?) -> String? {
            guard let s = (v as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty, s.lowercased() != "null" else { return nil }
            return s
        }
        func num(_ v: Any?) -> Double? { (v as? Double) ?? (v as? Int).map(Double.init) ?? (v as? NSNumber)?.doubleValue }
        func items(_ v: Any?) -> [Item] {
            ((v as? [[String: Any]]) ?? []).compactMap { d in str(d["name"]).map { Item(name: $0, x: num(d["x"]) ?? 0.5, meters: num(d["meters"])) } }
        }
        guard let p = o["path"] as? [String: Any] else { return nil }
        self.init(path: PathStatus(rawValue: str(p["status"]) ?? "clear") ?? .clear, pathWhat: str(p["what"]), pathX: num(p["x"]) ?? 0.5, pathMeters: num(p["meters"]),
                  hazards: items(o["hazards"]), place: str(o["place"]), objects: items(o["objects"]),
                  signs: ((o["signs"] as? [String]) ?? []).compactMap { str($0) }, summary: str(o["summary"]) ?? "", at: at, hFOV: hFOV)
    }

    static let schema: [String: Any] = {
        let item: [String: Any] = ["type": "object", "additionalProperties": false,
                                   "properties": ["name": ["type": "string"], "x": ["type": "number"], "meters": ["type": ["number", "null"]]],
                                   "required": ["name", "x", "meters"]]
        let path: [String: Any] = ["type": "object", "additionalProperties": false,
                                   "properties": ["status": ["type": "string", "enum": ["clear", "caution", "blocked"]], "what": ["type": ["string", "null"]],
                                                  "x": ["type": "number"], "meters": ["type": ["number", "null"]]],
                                   "required": ["status", "what", "x", "meters"]]
        return ["type": "object", "additionalProperties": false,
                "properties": ["path": path, "hazards": ["type": "array", "items": item], "place": ["type": ["string", "null"]],
                               "objects": ["type": "array", "items": item], "signs": ["type": "array", "items": ["type": "string"]], "summary": ["type": "string"]],
                "required": ["path", "hazards", "place", "objects", "signs", "summary"]]
    }()

    static let systemPrompt = """
    You are the eyes of a blind person walking with camera glasses. The image is their view right now. \
    Every face is blacked out on purpose: ignore people completely. Never mention, count or describe people, their \
    clothes or bodies, and never mention the black boxes. Report only what helps them move safely and know where they are.
    path: the walking corridor straight ahead (centre 40% of the image, floor up to head height). status is blocked if a \
    wall, closed door, furniture or any object is in that corridor within 2.5 m; caution if within 2.5 to 5 m or the way \
    narrows; otherwise clear. what: the thing in 1 or 2 words (wall, door, chair, table, pillar, glass door). x: its \
    horizontal centre from 0 (left edge) to 1 (right edge). meters: your distance estimate.
    hazards: things that could trip or hurt: stairs up or down, a step, curb, drop, escalator, wet floor, cables, low \
    obstacle, vehicle, open door edge. Each with x and meters. Empty if none.
    place: 1 to 3 words (hallway, classroom, cafeteria, street, office, kitchen), or null.
    objects: up to 5 useful landmarks, most useful first (door, table, chair, laptop, stairs, sign, elevator, trash can, \
    bench), with x and meters. Never people.
    signs: short text readable on signs or screens, at most 4, at most 5 words each. Never name badges or text on people.
    summary: at most 10 words, the single most useful thing to tell the walker now, using clock directions where the \
    left edge is 11 o'clock, the centre 12 and the right edge 1, e.g. "Hallway, door at 1 o'clock, about 3 meters."
    """
}

/// Turns a frame into the only thing that may leave the phone: an upright copy with every face blacked out.
enum FrameRedactor {
    private static let ciContext = CIContext(options: [.cacheIntermediates: false])

    /// Upright copy with the long side at most `maxSide` px.
    static func uprightImage(_ frame: Frame, maxSide: CGFloat = 512) -> CGImage? {
        var image = CIImage(cvPixelBuffer: frame.pixelBuffer).oriented(frame.orientation)
        let scale = min(1, maxSide / max(image.extent.width, image.extent.height))
        image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return ciContext.createCGImage(image, from: image.extent)
    }

    /// Faces Vision finds in `image` (normalized, top-left origin), or nil when Vision cannot run: callers then
    /// upload nothing.
    static func faceBoxes(in image: CGImage) -> [CGRect]? {
        let request = VNDetectFaceRectanglesRequest()
        do { try VNImageRequestHandler(cgImage: image, options: [:]).perform([request]) } catch { return nil }
        return (request.results ?? []).map { o in
            let b = o.boundingBox
            return CGRect(x: b.minX, y: 1 - b.maxY, width: b.width, height: b.height)
        }
    }

    /// The image as JPEG with every box (normalized, top-left origin) grown by `margin` and filled black.
    static func redacted(_ image: CGImage, boxes: [CGRect], margin: CGFloat = 0.35) -> CGImage? {
        let w = CGFloat(image.width), h = CGFloat(image.height)
        guard let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        for b in boxes {
            let r = b.insetBy(dx: -b.width * margin, dy: -b.height * margin)
            ctx.fill(CGRect(x: r.minX * w, y: (1 - r.maxY) * h, width: r.width * w, height: r.height * h))   // CG is bottom-left
        }
        return ctx.makeImage()
    }

    static func jpeg(_ image: CGImage, quality: CGFloat = 0.6) -> Data? { UIImage(cgImage: image).jpegData(compressionQuality: quality) }

    /// 16×16 grey thumbnail, 0…1, for cheap "did the view change" checks.
    static func thumbnail(_ image: CGImage, side: Int = 16) -> [Float] {
        var pixels = [UInt8](repeating: 0, count: side * side)
        guard let ctx = CGContext(data: &pixels, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return [] }
        ctx.interpolationQuality = .low
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        return pixels.map { Float($0) / 255 }
    }

    static func difference(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 1 }
        return zip(a, b).reduce(0) { $0 + abs($1.0 - $1.1) } / Float(a.count)
    }
}

/// The always-on eye: keeps an upright copy of the newest frame, and whenever the view changed (or every
/// `heartbeat` seconds) asks the vision model what matters for walking. One request in flight at a time.
final class CloudScene: @unchecked Sendable {
    var captureInterval: TimeInterval = 0.25
    var minInterval: TimeInterval = 1.5
    var heartbeat: TimeInterval = 6
    var changeThreshold: Float = 0.06
    /// Face boxes perception already tracks (normalized, top-left origin); blacked out on top of a fresh detection.
    var trackedFaces: () -> [CGRect] = { [] }

    struct Status: Equatable { var uploads = 0; var lastLatency: TimeInterval?; var lastError: String? }

    private struct Latest { let image: CGImage; let thumb: [Float]; let t: TimeInterval; let hFOV: Double }
    private struct State {
        var latest: Latest?
        var reading: SceneReading?
        var inFlight = false
        var lastSentAt: TimeInterval = -.infinity
        var lastSentThumb: [Float]?
        var lastUpload: CGImage?
        var status = Status()
    }

    let client: VisionLLM
    private let bus = EventBus<SceneReading>()
    private let state = OSAllocatedUnfairLock(initialState: State())
    private var task: Task<Void, Never>?
    private let log = Logger(subsystem: "familiar", category: "cloudscene")

    init(client: VisionLLM) { self.client = client }

    var isConfigured: Bool { client.isConfigured }
    var reading: SceneReading? { state.withLock { $0.reading } }
    var status: Status { state.withLock { $0.status } }
    /// The last image that left the phone (faces blacked out), for the judge view.
    var lastUpload: CGImage? { state.withLock { $0.lastUpload } }

    func subscribe() -> AsyncStream<SceneReading> { bus.subscribe() }

    func start(frames: FrameSource) {
        guard task == nil, client.isConfigured else { return }
        let stream = frames.subscribe()
        task = Task.detached(priority: .utility) { [weak self] in
            var lastCapture: TimeInterval = -.infinity
            for await frame in stream {
                guard let self, !Task.isCancelled else { break }
                guard frame.timestamp - lastCapture >= self.captureInterval, let image = FrameRedactor.uprightImage(frame) else { continue }
                lastCapture = frame.timestamp
                let latest = Latest(image: image, thumb: FrameRedactor.thumbnail(image), t: CACurrentMediaTime(), hFOV: frame.horizontalFOVDegrees)
                if let due = self.store(latest) { Task.detached(priority: .utility) { await self.read(due) } }
            }
        }
    }

    func stop() {
        task?.cancel(); task = nil
        state.withLock { $0.latest = nil; $0.inFlight = false }
    }

    /// Freshest view with every face blacked out, for a question. nil when there is no frame yet or face detection
    /// is unavailable (nothing is uploaded then).
    func redactedSnapshot() -> (jpeg: Data, image: CGImage)? {
        guard let latest = state.withLock({ $0.latest }), let image = redact(latest.image), let jpeg = FrameRedactor.jpeg(image) else { return nil }
        state.withLock { $0.lastUpload = image }
        return (jpeg, image)
    }

    /// Keeps `latest` and returns it when a scene request is due.
    private func store(_ latest: Latest) -> Latest? {
        state.withLock { s in
            s.latest = latest
            guard !s.inFlight, latest.t - s.lastSentAt >= minInterval else { return nil }
            let changed = s.lastSentThumb.map { FrameRedactor.difference($0, latest.thumb) > changeThreshold } ?? true
            guard changed || latest.t - s.lastSentAt >= heartbeat else { return nil }
            s.inFlight = true
            s.lastSentAt = latest.t
            s.lastSentThumb = latest.thumb
            return latest
        }
    }

    private func redact(_ image: CGImage) -> CGImage? {
        guard let found = FrameRedactor.faceBoxes(in: image) else { return nil }
        return FrameRedactor.redacted(image, boxes: found + trackedFaces())
    }

    private func read(_ latest: Latest) async {
        defer { state.withLock { $0.inFlight = false } }
        guard let image = redact(latest.image), let jpeg = FrameRedactor.jpeg(image) else {
            state.withLock { $0.status.lastError = "face check unavailable: nothing uploaded" }
            return
        }
        state.withLock { $0.lastUpload = image; $0.status.uploads += 1 }
        let started = CACurrentMediaTime()
        do {
            let json = try await client.complete(system: SceneReading.systemPrompt, text: "What matters for walking right now?", imageJPEG: jpeg,
                                                 schemaName: "SceneReading", schema: SceneReading.schema, maxTokens: 700, cacheKey: "poyo-scene-v1", timeout: 10)
            guard let reading = SceneReading(json: json, at: latest.t, hFOV: latest.hFOV) else { throw MetaModelClient.ClientError.malformed }
            state.withLock { $0.reading = reading; $0.status.lastLatency = CACurrentMediaTime() - started; $0.status.lastError = nil }
            bus.publish(reading)
        } catch {
            log.error("scene reading failed: \(error.localizedDescription, privacy: .public)")
            state.withLock { $0.status.lastError = error.localizedDescription }
        }
    }
}
