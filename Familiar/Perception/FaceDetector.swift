import Foundation
import Vision
import QuartzCore
import CoreImage
import CoreVideo
import os

struct DetectorConfig: Equatable {
    /// Frames are downscaled so the upright width is at most this before Vision runs.
    var maxWidth: CGFloat = 960
    /// Detections smaller than this (upright pixels) are dropped: too small to align or embed.
    var minFaceHeightPx: Double = 20
    var minConfidence: Float = 0.3
    static let `default` = DetectorConfig()
}

/// Apple Vision face rectangles (rev 3, radians) + 76-point landmarks on a ≤ 960 px-wide downscale.
/// One serial queue; `detect` returns nil immediately while a previous frame is still being processed.
final class FaceDetector: @unchecked Sendable {
    let config: DetectorConfig
    private let queue = DispatchQueue(label: "familiar.facedetector", qos: .userInitiated)
    private let busy = OSAllocatedUnfairLock(initialState: false)
    private let ciContext = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull(), .cacheIntermediates: false])
    private var pool: CVPixelBufferPool?
    private var poolSize = CGSize.zero
    private(set) var lastDurationMillis: Double = 0

    init(config: DetectorConfig = .default) { self.config = config }

    static func uprightSize(width: Int, height: Int, orientation: CGImagePropertyOrientation) -> CGSize {
        switch orientation {
        case .left, .right, .leftMirrored, .rightMirrored: return CGSize(width: height, height: width)
        default: return CGSize(width: width, height: height)
        }
    }

    /// Async wrapper that drops the frame when the detector is busy.
    func detect(_ frame: Frame) async -> DetectionResult? {
        let claimed = busy.withLock { b -> Bool in if b { return false }; b = true; return true }
        guard claimed else { return nil }
        defer { busy.withLock { $0 = false } }
        return await withCheckedContinuation { cont in
            queue.async { cont.resume(returning: self.detectSync(frame.pixelBuffer, orientation: frame.orientation, timestamp: frame.timestamp)) }
        }
    }

    func detectSync(_ pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation, timestamp: TimeInterval) -> DetectionResult {
        let t0 = CACurrentMediaTime()
        defer { lastDurationMillis = (CACurrentMediaTime() - t0) * 1000 }
        let w = CVPixelBufferGetWidth(pixelBuffer), h = CVPixelBufferGetHeight(pixelBuffer)
        let upright = Self.uprightSize(width: w, height: h, orientation: orientation)
        let input = downscaled(pixelBuffer, uprightWidth: upright.width) ?? pixelBuffer

        let rects = VNDetectFaceRectanglesRequest()
        rects.revision = VNDetectFaceRectanglesRequestRevision3
        let handler = VNImageRequestHandler(cvPixelBuffer: input, orientation: orientation, options: [:])
        do { try handler.perform([rects]) } catch { return DetectionResult(detections: [], uprightSize: upright, timestamp: timestamp) }
        let faces = (rects.results ?? []).filter { $0.confidence >= config.minConfidence && Double($0.boundingBox.height) * Double(upright.height) >= config.minFaceHeightPx }
        guard !faces.isEmpty else { return DetectionResult(detections: [], uprightSize: upright, timestamp: timestamp) }

        let lm = VNDetectFaceLandmarksRequest()
        lm.revision = VNDetectFaceLandmarksRequestRevision3
        lm.constellation = .constellation76Points
        lm.inputFaceObservations = faces
        try? handler.perform([lm])
        let withLandmarks = lm.results ?? []

        var out: [FaceDetection] = []
        for face in faces {
            let bb = face.boundingBox   // bottom-left normalized
            let box = CGRect(x: bb.minX, y: 1 - bb.maxY, width: bb.width, height: bb.height)
            let deg = 180.0 / Double.pi
            var d = FaceDetection(box: box, confidence: face.confidence,
                                  yawDegrees: face.yaw.map { $0.doubleValue * deg },
                                  rollDegrees: face.roll.map { $0.doubleValue * deg },
                                  pitchDegrees: face.pitch.map { $0.doubleValue * deg },
                                  landmarks: nil, mouthOpenness: nil)
            if let obs = withLandmarks.max(by: { FaceTracker.iou($0.boundingBox, bb) < FaceTracker.iou($1.boundingBox, bb) }),
               FaceTracker.iou(obs.boundingBox, bb) > 0.5, let l = obs.landmarks {
                let (five, mouth) = Self.fivePoints(l, boundingBox: obs.boundingBox, upright: upright)
                d.landmarks = five
                d.mouthOpenness = mouth
                if d.yawDegrees == nil, let y = obs.yaw { d.yawDegrees = y.doubleValue * deg }
            }
            out.append(d)
        }
        return DetectionResult(detections: out, uprightSize: upright, timestamp: timestamp)
    }

    /// Landmark points → upright full-resolution pixels (top-left origin), reduced to the ArcFace five, plus mouth openness.
    static func fivePoints(_ l: VNFaceLandmarks2D, boundingBox bb: CGRect, upright: CGSize) -> (FaceLandmarks5?, Double?) {
        let W = Int(upright.width), H = Int(upright.height)
        func px(_ p: CGPoint) -> CGPoint {
            let v = VNImagePointForFaceLandmarkPoint(vector_float2(Float(p.x), Float(p.y)), bb, W, H)
            return CGPoint(x: v.x, y: upright.height - v.y)
        }
        func center(_ r: VNFaceLandmarkRegion2D?) -> CGPoint? {
            guard let r, r.pointCount > 0 else { return nil }
            let pts = r.normalizedPoints.map(px)
            let n = CGFloat(pts.count)
            return CGPoint(x: pts.map(\.x).reduce(0, +) / n, y: pts.map(\.y).reduce(0, +) / n)
        }
        var mouth: Double?
        if let inner = l.innerLips, inner.pointCount > 1 {
            let ys = inner.normalizedPoints.map { px($0).y }
            mouth = Double((ys.max()! - ys.min()!) / max(1, bb.height * upright.height))
        }
        guard let e1 = center(l.leftPupil) ?? center(l.leftEye), let e2 = center(l.rightPupil) ?? center(l.rightEye) else { return (nil, mouth) }
        let nose: CGPoint? = center(l.nose) ?? l.noseCrest.flatMap { $0.pointCount > 0 ? px($0.normalizedPoints.last!) : nil }
        guard let nose, let lips = l.outerLips, lips.pointCount > 1 else { return (nil, mouth) }
        let lipPts = lips.normalizedPoints.map(px)
        let mL = lipPts.min { $0.x < $1.x }!, mR = lipPts.max { $0.x < $1.x }!
        let (le, re) = e1.x <= e2.x ? (e1, e2) : (e2, e1)
        return (FaceLandmarks5(leftEye: le, rightEye: re, nose: nose, mouthLeft: mL, mouthRight: mR), mouth)
    }

    private func downscaled(_ pb: CVPixelBuffer, uprightWidth: CGFloat) -> CVPixelBuffer? {
        guard uprightWidth > config.maxWidth else { return nil }
        let scale = config.maxWidth / uprightWidth
        let w = Int((CGFloat(CVPixelBufferGetWidth(pb)) * scale).rounded()), h = Int((CGFloat(CVPixelBufferGetHeight(pb)) * scale).rounded())
        let size = CGSize(width: w, height: h)
        if pool == nil || poolSize != size {
            let attrs: [CFString: Any] = [kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey: w, kCVPixelBufferHeightKey: h, kCVPixelBufferIOSurfacePropertiesKey: [:]]
            var p: CVPixelBufferPool?
            CVPixelBufferPoolCreate(nil, nil, attrs as CFDictionary, &p)
            pool = p; poolSize = size
        }
        guard let pool else { return nil }
        var out: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &out)
        guard let out else { return nil }
        let img = CIImage(cvPixelBuffer: pb).transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        ciContext.render(img, to: out, bounds: CGRect(x: 0, y: 0, width: w, height: h), colorSpace: nil)
        return out
    }
}
