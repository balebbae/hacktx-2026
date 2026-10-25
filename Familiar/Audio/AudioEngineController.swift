import Foundation
import AVFoundation
import QuartzCore
import os

/// Single owner of `AVAudioSession` and the one `AVAudioEngine`. Configures the session once at launch and never
/// deactivates it (re-activation costs Bluetooth setup lag and clipped first syllables).
///
/// Route A `.phoneMicGlassesA2DP` (default): phone mic in, glasses as A2DP out; HFP stays closed for the glasses SDK.
/// Route B `.glassesHFP`: glasses mic + speaker over HFP with voice processing. Refused while `glassesStreamActive`.
/// `.phoneOnly`: no Bluetooth. `.glassesStreamMic` (S6) keeps the session like Route A; the mic comes from the SDK.
final class AudioEngineController: NSObject, PCMPlayback, StreamingPCMPlayback, @unchecked Sendable {
    let rawInput: EngineAudioInput
    let transcriberInput: EngineAudioInput
    private(set) var route: AudioRoute
    /// Set by S6 while the glasses stream their mic; Route B is then refused.
    var glassesStreamActive = false
    var speakingTail: TimeInterval = 0.3
    /// Audio held back before a stream starts playing, so a late chunk does not leave a gap mid-sentence.
    var streamPrebuffer: TimeInterval = 0.3
    var isRunning: Bool { engine.isRunning }
    var lastError: String?

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let queue = DispatchQueue(label: "familiar.audio.engine")
    private var chunker: AudioChunker?
    private var tapInstalled = false
    private var sessionConfigured = false
    private var playerAttached = false
    private var observers: [NSObjectProtocol] = []
    private let speakingState = OSAllocatedUnfairLock(initialState: (speaking: false, until: TimeInterval(-1)))
    private let playLock = OSAllocatedUnfairLock(initialState: (generation: 0, continuation: Optional<CheckedContinuation<Bool, Never>>.none))
    private let playbackFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!

    init(route: AudioRoute = .phoneMicGlassesA2DP) {
        self.route = route
        var routeBox: (() -> AudioRoute)!
        let speaking = speakingState
        rawInput = EngineAudioInput(route: { routeBox() })
        transcriberInput = EngineAudioInput(route: { routeBox() }, gate: { chunk in
            speaking.withLock { $0.speaking || chunk.timestamp < $0.until }
        })
        super.init()
        routeBox = { [weak self] in self?.route ?? .phoneOnly }
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    // MARK: Session

    /// Idempotent. Called once at launch; route switches call `applyRoute` instead of deactivating.
    func configureSessionOnce() throws {
        guard !sessionConfigured else { return }
        try applySession(for: route)
        try AVAudioSession.sharedInstance().setActive(true, options: [])
        sessionConfigured = true
    }

    private func applySession(for route: AudioRoute) throws {
        let session = AVAudioSession.sharedInstance()
        switch route {
        case .phoneMicGlassesA2DP, .glassesStreamMic:
            try session.setCategory(.playAndRecord, mode: .default, options: [.allowBluetoothA2DP, .defaultToSpeaker])
            if let builtIn = session.availableInputs?.first(where: { $0.portType == .builtInMic }) { try? session.setPreferredInput(builtIn) }
        case .glassesHFP:
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetoothHFP, .allowBluetoothA2DP])
            if let hfp = session.availableInputs?.first(where: { $0.portType == .bluetoothHFP }) { try? session.setPreferredInput(hfp) }
        case .phoneOnly:
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            if let builtIn = session.availableInputs?.first(where: { $0.portType == .builtInMic }) { try? session.setPreferredInput(builtIn) }
        }
        try? session.setPreferredSampleRate(48_000)
        try? session.setPreferredIOBufferDuration(0.02)
    }

    // MARK: Lifecycle

    func start() throws {
        try configureSessionOnce()
        try queue.sync { try self.startLocked() }
        if observers.isEmpty { installObservers() }
    }

    /// Stops the tap and the engine (the session stays active).
    func stopEngine() {
        queue.sync {
            removeTap()
            if engine.isRunning { engine.stop() }
        }
    }

    /// Switch routes at runtime (Settings). Tears down the tap, reconfigures the session, rebuilds.
    func setRoute(_ newRoute: AudioRoute) throws {
        if newRoute == .glassesHFP && glassesStreamActive { throw AudioEngineError.hfpBlockedByGlassesStream }
        try queue.sync {
            removeTap()
            if engine.isRunning { engine.stop() }
            if newRoute == .glassesHFP { try? engine.inputNode.setVoiceProcessingEnabled(true) }
            else if engine.inputNode.isVoiceProcessingEnabled { try? engine.inputNode.setVoiceProcessingEnabled(false) }
            try applySession(for: newRoute)
            route = newRoute
            try startLocked()
        }
    }

    private func startLocked() throws {
        if route == .glassesHFP && !engine.inputNode.isVoiceProcessingEnabled { try? engine.inputNode.setVoiceProcessingEnabled(true) }
        if !playerAttached {
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: playbackFormat)
            playerAttached = true
        }
        installTap()
        engine.prepare()
        try engine.start()
    }

    private func installTap() {
        removeTap()
        let input = engine.inputNode
        // After a route change the node's cached output format can lag the hardware (48 kHz vs 16 kHz HFP), and
        // installTap with a mismatched rate raises an ObjC exception that kills the app. Always tap at the hw rate.
        let hardware = input.inputFormat(forBus: 0)
        let cached = input.outputFormat(forBus: 0)
        guard hardware.sampleRate > 0, cached.channelCount > 0 else {
            lastError = "no usable input format"
            return
        }
        let format = cached.sampleRate == hardware.sampleRate ? cached
            : AVAudioFormat(standardFormatWithSampleRate: hardware.sampleRate, channels: cached.channelCount) ?? hardware
        guard let chunker = AudioChunker(inputFormat: format) else {
            lastError = "no usable input format"
            return
        }
        self.chunker = chunker
        let raw = rawInput, gated = transcriberInput
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, when in
            guard let chunk = chunker.chunk(buffer, when: when) else { return }
            raw.publish(chunk)
            gated.publish(chunk)
        }
        tapInstalled = true
    }

    private func removeTap() {
        guard tapInstalled else { return }
        engine.inputNode.removeTap(onBus: 0)
        tapInstalled = false
    }

    private func installObservers() {
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { [weak self] _ in self?.rebuild(reason: "engine configuration change") })
        observers.append(nc.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: nil) { [weak self] note in
            let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt).flatMap(AVAudioSession.RouteChangeReason.init(rawValue:))
            switch reason {
            // Not `.override`: that is our own speaker switch for `.otherPerson` utterances. Rebuilding then stops the
            // engine under the buffer that just started, so the consent question is cut off and never completes.
            case .newDeviceAvailable, .oldDeviceUnavailable, .categoryChange, .routeConfigurationChange: self?.rebuild(reason: "route change \(reason.map { String($0.rawValue) } ?? "?")")
            default: break
            }
        })
        observers.append(nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: nil) { [weak self] note in
            guard let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init(rawValue:)), type == .ended else { return }
            self?.rebuild(reason: "interruption ended")
        })
    }

    /// Re-install the tap with the new input format and restart the engine.
    func rebuild(reason: String) {
        queue.async { [self] in
            removeTap()
            if engine.isRunning { engine.stop() }
            do { try startLocked() } catch { lastError = "rebuild after \(reason) failed: \(error.localizedDescription)" }
        }
    }

    // MARK: Playback (PCMPlayback)

    var isSpeaking: Bool { speakingState.withLock { $0.speaking } }

    func play(_ audio: SynthesizedAudio, audience: Audience) async -> ClosedRange<TimeInterval>? {
        guard engine.isRunning || (try? start()) != nil, engine.isRunning else { return nil }
        guard let buffer = makeBuffer(audio) else { return nil }
        let session = AVAudioSession.sharedInstance()
        if audience == .otherPerson { try? session.overrideOutputAudioPort(.speaker) }
        defer { if audience == .otherPerson { try? session.overrideOutputAudioPort(.none) } }

        speakingState.withLock { $0.speaking = true }
        let start = CACurrentMediaTime()
        let duration = Double(buffer.frameLength) / buffer.format.sampleRate
        let completed = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            // One step, so a `stop()` in between cannot bump the generation and strand this continuation.
            let generation: Int = playLock.withLock { s in s.generation += 1; s.continuation = cont; return s.generation }
            // `.dataPlayedBack` never fires if the engine stops mid-buffer (route change, interruption); without
            // this the caller — e.g. the consent flow — would wait forever.
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(duration + 2))
                self?.finishPlayback(generation: generation, completed: false)
            }
            player.scheduleBuffer(buffer, at: nil, options: [], completionCallbackType: .dataPlayedBack) { [weak self] _ in
                self?.finishPlayback(generation: generation, completed: true)
            }
            if !player.isPlaying { player.play() }
        }
        let end = CACurrentMediaTime()
        speakingState.withLock { $0.speaking = false; $0.until = end + speakingTail }
        return completed || end > start ? start...end : nil
    }

    private func finishPlayback(generation: Int, completed: Bool) {
        let cont: CheckedContinuation<Bool, Never>? = playLock.withLock { s in
            guard s.generation == generation else { return nil }
            let c = s.continuation; s.continuation = nil; return c
        }
        cont?.resume(returning: completed)
    }

    // MARK: Streaming playback (StreamingPCMPlayback)

    /// Schedules each chunk on the player node as it arrives (after `streamPrebuffer` worth is in hand) and returns
    /// when the last scheduled buffer has played, the stream failed, or `stop()` cut it. Shares `playLock`'s
    /// generation with `play`, so a priority-0 interruption stops a stream the same way.
    func playStream(_ chunks: AsyncThrowingStream<[Float], Error>, sampleRate: Double, prefix: [Float], gain: Float, audience: Audience) async -> ClosedRange<TimeInterval>? {
        guard engine.isRunning || (try? start()) != nil, engine.isRunning else { return nil }
        let session = AVAudioSession.sharedInstance()
        if audience == .otherPerson { try? session.overrideOutputAudioPort(.speaker) }
        defer { if audience == .otherPerson { try? session.overrideOutputAudioPort(.none) } }

        speakingState.withLock { $0.speaking = true }
        let start = CACurrentMediaTime()
        let state = OSAllocatedUnfairLock(initialState: StreamState(held: prefix))
        let prebuffer = streamPrebuffer

        let completed = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            let generation: Int = playLock.withLock { s in s.generation += 1; s.continuation = cont; return s.generation }
            Task {
                var failed = false
                do {
                    for try await chunk in chunks {
                        guard self.playLock.withLock({ $0.generation == generation }) else { return }    // stopped
                        let ready: [Float]? = state.withLock { s in
                            s.held += chunk
                            if !s.started, Double(s.held.count) / sampleRate < prebuffer { return nil }
                            s.started = true
                            defer { s.held.removeAll(keepingCapacity: true) }
                            return s.held
                        }
                        if let ready { self.scheduleStreamed(ready, gain: gain, sampleRate: sampleRate, state: state, generation: generation) }
                    }
                } catch { failed = true }
                guard self.playLock.withLock({ $0.generation == generation }) else { return }
                let rest: [Float] = state.withLock { s in defer { s.held.removeAll() }; return s.held }
                self.scheduleStreamed(rest, gain: gain, sampleRate: sampleRate, state: state, generation: generation)
                let (allPlayed, seconds, any) = state.withLock { s -> (Bool, Double, Bool) in s.done = true; return (s.played >= s.scheduled, s.seconds, s.scheduled > 0) }
                if allPlayed || !any { self.finishPlayback(generation: generation, completed: !failed && any); return }
                // `.dataPlayedBack` never fires if the engine stops mid-buffer; never leave the speaker waiting.
                try? await Task.sleep(for: .seconds(seconds + 2))
                self.finishPlayback(generation: generation, completed: false)
            }
        }
        let end = CACurrentMediaTime()
        speakingState.withLock { $0.speaking = false; $0.until = end + speakingTail }
        let any = state.withLock { $0.scheduled > 0 }
        return completed || (any && end > start) ? start...end : nil
    }

    private struct StreamState { var held: [Float]; var started = false; var scheduled = 0; var played = 0; var done = false; var seconds = 0.0 }

    private func scheduleStreamed(_ samples: [Float], gain: Float, sampleRate: Double, state: OSAllocatedUnfairLock<StreamState>, generation: Int) {
        // Checked last, right before scheduling: a chunk converted while `stop()` ran must not restart the player.
        guard !samples.isEmpty, let buffer = makeBuffer(SynthesizedAudio(samples: gain == 1 ? samples : samples.map { $0 * gain }, sampleRate: sampleRate, source: "stream")),
              playLock.withLock({ $0.generation == generation }) else { return }
        state.withLock { $0.scheduled += 1; $0.seconds += Double(buffer.frameLength) / buffer.format.sampleRate }
        player.scheduleBuffer(buffer, at: nil, options: [], completionCallbackType: .dataPlayedBack) { [weak self] _ in
            let last = state.withLock { s -> Bool in s.played += 1; return s.done && s.played >= s.scheduled }
            if last { self?.finishPlayback(generation: generation, completed: true) }
        }
        if !player.isPlaying { player.play() }
    }

    /// PCMPlayback: cut the current utterance short. A new generation, so a stream still receiving chunks stops
    /// scheduling them (and the mic gate does not reopen under the rest of the answer).
    func stop() {
        let cont = playLock.withLock { s in s.generation += 1; defer { s.continuation = nil }; return s.continuation }
        player.stop()
        cont?.resume(returning: false)
    }

    private func makeBuffer(_ audio: SynthesizedAudio) -> AVAudioPCMBuffer? {
        var samples = audio.samples
        if audio.sampleRate != playbackFormat.sampleRate {
            guard let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: audio.sampleRate, channels: 1, interleaved: false), let chunker = AudioChunker(inputFormat: fmt), let src = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(samples.count)) else { return nil }
            samples.withUnsafeBufferPointer { src.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
            src.frameLength = AVAudioFrameCount(samples.count)
            guard let converted = chunker.convert(src) else { return nil }
            samples = converted
        }
        guard !samples.isEmpty, let buffer = AVAudioPCMBuffer(pcmFormat: playbackFormat, frameCapacity: AVAudioFrameCount(samples.count)) else { return nil }
        samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        return buffer
    }
}
