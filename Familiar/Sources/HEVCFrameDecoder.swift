import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox
import os

/// Software HEVC decoder for the glasses stream. Software so the session survives
/// backgrounding (iOS tears hardware sessions down). Output is 32BGRA.
/// Thread-safe; call `decode` from the SDK callback thread.
final class HEVCFrameDecoder: @unchecked Sendable {
    private struct State {
        var session: VTDecompressionSession?
        var formatDescription: CMFormatDescription?
        var awaitingKeyframe = true
        var consecutiveFailures = 0
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private struct SessionRef: @unchecked Sendable { let session: VTDecompressionSession? }

    deinit { reset() }

    func reset() {
        state.withLock {
            if let s = $0.session { VTDecompressionSessionInvalidate(s) }
            $0 = State()
        }
    }

    /// Returns nil for frames that cannot be decoded yet (before the first keyframe, or on error).
    func decode(_ sampleBuffer: CMSampleBuffer) -> CVPixelBuffer? {
        guard CMSampleBufferGetDataBuffer(sampleBuffer) != nil,
              let format = CMSampleBufferGetFormatDescription(sampleBuffer) else { return nil }
        let isKeyframe = Self.isHEVCKeyframe(sampleBuffer)

        let session: VTDecompressionSession? = state.withLock { s -> SessionRef in
            if let existing = s.session, let f = s.formatDescription, CMFormatDescriptionEqual(f, otherFormatDescription: format) {
                return SessionRef(session: existing)
            }
            if let old = s.session { VTDecompressionSessionInvalidate(old) }
            let spec = [kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder as String: false] as CFDictionary
            let attrs: [CFString: Any] = [kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA]
            var created: VTDecompressionSession?
            VTDecompressionSessionCreate(allocator: kCFAllocatorDefault,
                                         formatDescription: format,
                                         decoderSpecification: spec,
                                         imageBufferAttributes: attrs as CFDictionary,
                                         outputCallback: nil,
                                         decompressionSessionOut: &created)
            s.session = created
            s.formatDescription = format
            s.awaitingKeyframe = true
            s.consecutiveFailures = 0
            return SessionRef(session: created)
        }.session
        guard let session else { return nil }

        let awaiting = state.withLock { $0.awaitingKeyframe }
        if awaiting && !isKeyframe { return nil }

        final class Box: @unchecked Sendable { var buffer: CVPixelBuffer? }
        let box = Box()
        var infoFlags = VTDecodeInfoFlags()
        let status = VTDecompressionSessionDecodeFrame(session, sampleBuffer: sampleBuffer, flags: [], infoFlagsOut: &infoFlags) { status, _, imageBuffer, _, _ in
            if status == noErr { box.buffer = imageBuffer }
        }

        state.withLock { s in
            if status == noErr, box.buffer != nil {
                s.consecutiveFailures = 0
                if isKeyframe { s.awaitingKeyframe = false }
            } else {
                s.consecutiveFailures += 1
                if s.consecutiveFailures >= 10 {
                    if let old = s.session { VTDecompressionSessionInvalidate(old) }
                    s.session = nil
                    s.formatDescription = nil
                }
            }
        }
        return box.buffer
    }

    /// NAL units arrive length-prefixed (hvcC). IRAP NAL types 16...21 are keyframes.
    static func isHEVCKeyframe(_ sampleBuffer: CMSampleBuffer) -> Bool {
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[CFString: Any]],
           let first = attachments.first, let notSync = first[kCMSampleAttachmentKey_NotSync] as? Bool {
            return !notSync
        }
        guard let data = CMSampleBufferGetDataBuffer(sampleBuffer) else { return false }
        let total = CMBlockBufferGetDataLength(data)
        var offset = 0
        while offset + 4 < total {
            var lengthBE: UInt32 = 0
            guard CMBlockBufferCopyDataBytes(data, atOffset: offset, dataLength: 4, destination: &lengthBE) == kCMBlockBufferNoErr else { break }
            let length = Int(UInt32(bigEndian: lengthBE))
            offset += 4
            guard length > 0, offset + length <= total else { break }
            var header: UInt8 = 0
            guard CMBlockBufferCopyDataBytes(data, atOffset: offset, dataLength: 1, destination: &header) == kCMBlockBufferNoErr else { break }
            let nalType = (header >> 1) & 0x3F
            if nalType >= 16 && nalType <= 21 { return true }
            offset += length
        }
        return false
    }
}
