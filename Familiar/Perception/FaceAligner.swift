import Foundation
import CoreImage
import CoreVideo
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// ArcFace 112x112 alignment from five landmarks with a least-squares similarity transform, warped with Core Image
/// from the full-resolution frame. Also makes the 256x256 thumbnail JPEG.
final class FaceAligner: @unchecked Sendable {
    static let outputSize = 112
    static let template: [CGPoint] = [
        CGPoint(x: 38.2946, y: 51.6963), CGPoint(x: 73.5318, y: 51.5014), CGPoint(x: 56.0252, y: 71.7366),
        CGPoint(x: 41.5493, y: 92.3655), CGPoint(x: 70.7299, y: 92.2041),
    ]
    static let templateEyeMid = CGPoint(x: 55.9, y: 51.6)
    static let templateEyeDistance: CGFloat = 35.24

    static let shared = FaceAligner()
    private let ciContext = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull(), .cacheIntermediates: false])

    /// Least-squares similarity (rotation + uniform scale + translation, no reflection) mapping `src` onto `dst`.
    /// Equivalent to Umeyama without the reflection branch. Nil when the points are degenerate.
    static func similarity(from src: [CGPoint], to dst: [CGPoint]) -> CGAffineTransform? {
        guard src.count == dst.count, src.count >= 2 else { return nil }
        let n = CGFloat(src.count)
        let sx = src.map(\.x).reduce(0, +) / n, sy = src.map(\.y).reduce(0, +) / n
        let dx = dst.map(\.x).reduce(0, +) / n, dy = dst.map(\.y).reduce(0, +) / n
        var denom: CGFloat = 0, na: CGFloat = 0, nb: CGFloat = 0
        for i in 0..<src.count {
            let xc = src[i].x - sx, yc = src[i].y - sy, xd = dst[i].x - dx, yd = dst[i].y - dy
            denom += xc * xc + yc * yc
            na += xc * xd + yc * yd
            nb += xc * yd - yc * xd
        }
        guard denom > 1e-6 else { return nil }
        let a = na / denom, b = nb / denom
        let scale = sqrt(a * a + b * b)
        guard scale.isFinite, scale > 1e-4 else { return nil }
        let tx = dx - a * sx + b * sy
        let ty = dy - b * sx - a * sy
        return CGAffineTransform(a: a, b: b, c: -b, d: a, tx: tx, ty: ty)
    }

    /// Eyes level, inter-pupil distance 35.24 px, eye midpoint at (55.9, 51.6).
    static func fallbackTransform(leftEye: CGPoint, rightEye: CGPoint) -> CGAffineTransform {
        let ddx = rightEye.x - leftEye.x, ddy = rightEye.y - leftEye.y
        let dist = max(1e-3, sqrt(ddx * ddx + ddy * ddy))
        let scale = templateEyeDistance / dist
        let angle = -atan2(ddy, ddx)
        let a = scale * cos(angle), b = scale * sin(angle)
        let mid = CGPoint(x: (leftEye.x + rightEye.x) / 2, y: (leftEye.y + rightEye.y) / 2)
        let tx = templateEyeMid.x - (a * mid.x - b * mid.y)
        let ty = templateEyeMid.y - (b * mid.x + a * mid.y)
        return CGAffineTransform(a: a, b: b, c: -b, d: a, tx: tx, ty: ty)
    }

    /// Transform from upright full-res pixels (top-left) to the 112x112 template (top-left).
    static func alignmentTransform(_ l: FaceLandmarks5) -> CGAffineTransform {
        let m = similarity(from: l.points, to: template)
        if let m {
            // Reject wild solves (mirrored or absurd scale) before trusting them.
            let scale = sqrt(m.a * m.a + m.b * m.b)
            let eye = l.leftEye.applying(m)
            if scale.isFinite, abs(eye.x - template[0].x) < 20, abs(eye.y - template[0].y) < 20 { return m }
        }
        return fallbackTransform(leftEye: l.leftEye, rightEye: l.rightEye)
    }

    private static func uprightImage(_ pb: CVPixelBuffer, orientation: CGImagePropertyOrientation) -> CIImage {
        let img = CIImage(cvPixelBuffer: pb)
        return orientation == .up ? img : img.oriented(orientation)
    }

    /// Returns a 112x112 BGRA buffer and the transform that produced it.
    func align(_ pb: CVPixelBuffer, orientation: CGImagePropertyOrientation, landmarks: FaceLandmarks5) -> (buffer: CVPixelBuffer, transform: CGAffineTransform)? {
        let m = Self.alignmentTransform(landmarks)
        guard let out = warp(pb, orientation: orientation, transform: m) else { return nil }
        return (out, m)
    }

    /// Warp with a top-left-origin transform `m` (full-res upright px → 112 px) through Core Image's bottom-left space.
    func warp(_ pb: CVPixelBuffer, orientation: CGImagePropertyOrientation, transform m: CGAffineTransform) -> CVPixelBuffer? {
        let img = Self.uprightImage(pb, orientation: orientation)
        let h = img.extent.height
        let s = CGFloat(Self.outputSize)
        let flipIn = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: h)
        let flipOut = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: s)
        let t = flipIn.concatenating(m).concatenating(flipOut)
        let warped = img.transformed(by: t)
        guard let out = Self.makeBuffer(width: Self.outputSize, height: Self.outputSize) else { return nil }
        ciContext.render(warped, to: out, bounds: CGRect(x: 0, y: 0, width: s, height: s), colorSpace: nil)
        return out
    }

    /// Square crop around `box` (normalized, top-left, upright) with 20 % margin, scaled to 256x256, JPEG q 0.8.
    func thumbnail(_ pb: CVPixelBuffer, orientation: CGImagePropertyOrientation, box: CGRect, size: CGFloat = 256, quality: CGFloat = 0.8) -> Data? {
        let img = Self.uprightImage(pb, orientation: orientation)
        let W = img.extent.width, H = img.extent.height
        let px = CGRect(x: box.minX * W, y: box.minY * H, width: box.width * W, height: box.height * H)
        let side = max(px.width, px.height) * 1.4
        var sq = CGRect(x: px.midX - side / 2, y: px.midY - side / 2, width: side, height: side)
        sq = sq.intersection(CGRect(x: 0, y: 0, width: W, height: H))
        guard sq.width > 2, sq.height > 2 else { return nil }
        let ciRect = CGRect(x: sq.minX, y: H - sq.maxY, width: sq.width, height: sq.height)
        let scale = size / max(sq.width, sq.height)
        let cropped = img.cropped(to: ciRect).transformed(by: CGAffineTransform(translationX: -ciRect.minX, y: -ciRect.minY)).transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let padded = cropped.cropped(to: CGRect(x: 0, y: 0, width: size, height: size))
        return ciContext.jpegRepresentation(of: padded, colorSpace: CGColorSpaceCreateDeviceRGB(), options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: quality])
    }

    func jpeg(_ pb: CVPixelBuffer, quality: CGFloat = 0.9) -> Data? {
        ciContext.jpegRepresentation(of: CIImage(cvPixelBuffer: pb), colorSpace: CGColorSpaceCreateDeviceRGB(), options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: quality])
    }

    func cgImage(_ pb: CVPixelBuffer, orientation: CGImagePropertyOrientation, maxWidth: CGFloat) -> CGImage? {
        let img = Self.uprightImage(pb, orientation: orientation)
        let scale = min(1, maxWidth / img.extent.width)
        let small = img.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return ciContext.createCGImage(small, from: small.extent.integral)
    }

    func cgImage(_ pb: CVPixelBuffer) -> CGImage? {
        let img = CIImage(cvPixelBuffer: pb)
        return ciContext.createCGImage(img, from: img.extent)
    }

    /// Decode any image data (JPEG/PNG) into a BGRA buffer of its own size, for tests and the Modal oracle.
    func pixelBuffer(from data: Data) -> CVPixelBuffer? {
        guard let img = CIImage(data: data) else { return nil }
        let w = Int(img.extent.width), h = Int(img.extent.height)
        guard let out = Self.makeBuffer(width: w, height: h) else { return nil }
        ciContext.render(img, to: out, bounds: img.extent, colorSpace: nil)
        return out
    }

    static func makeBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        var out: CVPixelBuffer?
        let attrs: [CFString: Any] = [kCVPixelBufferCGImageCompatibilityKey: true, kCVPixelBufferCGBitmapContextCompatibilityKey: true, kCVPixelBufferIOSurfacePropertiesKey: [:]]
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &out)
        return out
    }
}
