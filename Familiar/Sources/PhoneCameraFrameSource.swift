import Foundation
import AVFoundation
import CoreVideo
import QuartzCore

/// Back camera, 1080p30, portrait. Compiles in the Simulator; emits no frames there.
/// Exposes the running `AVCaptureSession` so `AVCaptureEventInteraction` (volume buttons) can be attached later.
final class PhoneCameraFrameSource: NSObject, FrameSource, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "familiar.camera", qos: .userInitiated)
    private let bus = EventBus<Frame>(defaultPolicy: .bufferingNewest(1))
    private var device: AVCaptureDevice?
    private(set) var horizontalFOVDegrees: Double = 70
    private(set) var verticalFOVDegrees: Double = 100
    private var configured = false

    func subscribe() -> AsyncStream<Frame> { bus.subscribe() }

    func start() async throws {
        #if targetEnvironment(simulator)
        return
        #else
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .video)
        }
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            throw NSError(domain: "PhoneCameraFrameSource", code: 1, userInfo: [NSLocalizedDescriptionKey: "Camera permission not granted"])
        }
        if !configured { try configure() }
        queue.async { [session] in if !session.isRunning { session.startRunning() } }
        #endif
    }

    func stop() {
        queue.async { [session] in if session.isRunning { session.stopRunning() } }
    }

    private func configure() throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .hd1920x1080
        guard let cam = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw NSError(domain: "PhoneCameraFrameSource", code: 2, userInfo: [NSLocalizedDescriptionKey: "No back camera"])
        }
        device = cam
        let input = try AVCaptureDeviceInput(device: cam)
        guard session.canAddInput(input) else { throw NSError(domain: "PhoneCameraFrameSource", code: 3) }
        session.addInput(input)
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else { throw NSError(domain: "PhoneCameraFrameSource", code: 4) }
        session.addOutput(output)
        if let conn = output.connection(with: .video) {
            if conn.isVideoRotationAngleSupported(90) { conn.videoRotationAngle = 90 }   // portrait
            if conn.isVideoStabilizationSupported { conn.preferredVideoStabilizationMode = .off }
        }
        try cam.lockForConfiguration()
        cam.videoZoomFactor = 1.0
        cam.unlockForConfiguration()
        // activeFormat.videoFieldOfView is the horizontal FOV of the landscape sensor (the long side).
        let longFOV = Double(cam.activeFormat.videoFieldOfView) * .pi / 180
        let dims = CMVideoFormatDescriptionGetDimensions(cam.activeFormat.formatDescription)
        let w = Double(min(dims.width, dims.height)), h = Double(max(dims.width, dims.height))   // portrait W < H
        verticalFOVDegrees = longFOV * 180 / .pi
        horizontalFOVDegrees = 2 * atan(tan(longFOV / 2) * w / h) * 180 / .pi
        configured = true
    }

    /// Only call with the largest face's centre (normalized, top-left origin).
    func setExposurePoint(_ p: CGPoint) {
        guard let device, device.isExposurePointOfInterestSupported else { return }
        queue.async {
            guard (try? device.lockForConfiguration()) != nil else { return }
            device.exposurePointOfInterest = CGPoint(x: p.y, y: 1 - p.x)   // portrait → sensor coordinates
            device.exposureMode = .continuousAutoExposure
            device.unlockForConfiguration()
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        // Capture PTS are already on the host clock (mach_absolute_time based), so this maps 1:1 to CACurrentMediaTime().
        let ts = CMTimeGetSeconds(pts)
        bus.publish(Frame(pixelBuffer: pb, timestamp: ts, orientation: .up,
                          horizontalFOVDegrees: horizontalFOVDegrees, verticalFOVDegrees: verticalFOVDegrees))
    }
}
