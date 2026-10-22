import Foundation
import AVFoundation
import os

/// Plays the key reference chord or a sustained drone with a small additive synth (shared approach with InKey).
@MainActor
final class ReferencePlayer: ObservableObject {
    @Published private(set) var playing: KeyReference.Kind?

    private let engine = AVAudioEngine()
    private var source: AVAudioSourceNode?
    private let voice = SynthVoice()
    private var endTimer: Timer?

    func toggle(_ kind: KeyReference.Kind, key: NamedKey) {
        if playing == kind { stop() } else { play(kind, key: key) }
    }

    func play(_ kind: KeyReference.Kind, key: NamedKey) {
        halt()
        do {
            try AudioSession.activate()
            try ensureEngine()
            voice.load(KeyReference.notes(kind, key: key))
            if !engine.isRunning { try engine.start() }
        } catch { return }
        playing = kind
        if kind == .chord {
            endTimer = Timer.scheduledTimer(withTimeInterval: 2.7, repeats: false) { [weak self] _ in
                Task { @MainActor in self?.stop() }
            }
        }
    }

    func stop() {
        guard playing != nil else { return }
        halt()
    }

    private func halt() {
        endTimer?.invalidate(); endTimer = nil
        if engine.isRunning {
            voice.fadeOut()
            Thread.sleep(forTimeInterval: 0.03)
            engine.stop()
        }
        playing = nil
    }

    private func ensureEngine() throws {
        guard source == nil else { return }
        let out = engine.outputNode.outputFormat(forBus: 0)
        let sr = out.sampleRate > 0 ? out.sampleRate : 48_000
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1) else { throw AudioDecodeError.unreadable }
        let voice = self.voice
        voice.sampleRate = sr
        let node = AVAudioSourceNode(format: format) { _, _, frameCount, abl in
            let buffers = UnsafeMutableAudioBufferListPointer(abl)
            guard let data = buffers.first?.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            voice.render(into: data, frames: Int(frameCount))
            for b in buffers.dropFirst() { b.mData?.copyMemory(from: data, byteCount: Int(b.mDataByteSize)) }
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.9
        engine.prepare()
        source = node
    }
}

/// Render-thread state; the main thread swaps the note list under a lock.
final class SynthVoice: @unchecked Sendable {
    var sampleRate: Double = 48_000
    private struct State { var notes: [KeyReference.Note] = []; var time = 0.0; var fade = 1.0; var fading = false }
    private let state = OSAllocatedUnfairLock(initialState: State())

    func load(_ notes: [KeyReference.Note]) { state.withLock { $0 = State(notes: notes) } }
    func fadeOut() { state.withLock { $0.fading = true } }

    func render(into out: UnsafeMutablePointer<Float>, frames: Int) {
        let sr = sampleRate, dt = 1 / sr, fadeStep = dt / 0.02
        state.withLock { s in
            for i in 0..<frames {
                var sample = 0.0
                if s.fade > 0 {
                    for n in s.notes {
                        let t = s.time - n.start
                        guard t > 0, t < n.duration else { continue }
                        let p = 2 * Double.pi * KeyReference.frequency(midi: n.midi) * t
                        let wave = sin(p) + 0.22 * sin(2 * p) + 0.08 * sin(3 * p)
                        sample += n.amplitude * KeyReference.gain(at: t, duration: n.duration) * wave
                    }
                    sample *= s.fade
                    if s.fading { s.fade = max(0, s.fade - fadeStep) }
                }
                out[i] = Float(sample)
                s.time += dt
            }
        }
    }
}

enum AudioSession {
    static func activate() throws {
        let s = AVAudioSession.sharedInstance()
        if s.category != .playback { try s.setCategory(.playback, mode: .default, options: [.mixWithOthers]) }
        try s.setActive(true)
    }
}
