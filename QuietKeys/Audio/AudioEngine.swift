import AVFoundation
import CoreAudio

/// Lock-free, low-latency sample playback engine.
///
/// Design:
///  - An `AVAudioSourceNode` renders a fixed pool of voices. No allocation,
///    no locks, no ObjC messaging on the render thread.
///  - Triggers travel from the event-tap thread to the render thread through
///    a single-producer / single-consumer ring buffer guarded by C11
///    acquire/release atomics (see qk_atomics.h).
///  - Sample data lives in preloaded `SampleBuffer`s. The engine retains
///    every bank that could still be audible; banks are pruned on the main
///    thread well after their last possible voice has decayed.
final class AudioEngine {
    static let sampleRate: Double = 48_000
    private static let ringSize = 256           // power of two
    private static let voiceCount = 64

    struct Trigger {
        var samples: UnsafeMutablePointer<Float>?
        var count: Int = 0
        var gain: Float = 0
        var pan: Float = 0                       // -1 (left) … +1 (right)
    }

    private struct Voice {
        var samples: UnsafeMutablePointer<Float>?
        var count: Int = 0
        var position: Int = 0
        var gainL: Float = 0
        var gainR: Float = 0
        var active: Bool = false
    }

    private let engine = AVAudioEngine()
    private let eq = AVAudioUnitEQ(numberOfBands: 2)
    private var sourceNode: AVAudioSourceNode!

    // SPSC ring: producer = event-tap thread, consumer = render thread.
    private let ring = UnsafeMutablePointer<Trigger>.allocate(capacity: ringSize)
    private let head = UnsafeMutablePointer<qk_atomic_u64>.allocate(capacity: 1)
    private let tail = UnsafeMutablePointer<qk_atomic_u64>.allocate(capacity: 1)
    private let voices = UnsafeMutablePointer<Voice>.allocate(capacity: voiceCount)

    /// Master volume, read atomically-enough (single float store) on render.
    private let masterGain = UnsafeMutablePointer<Float>.allocate(capacity: 1)

    /// Banks kept alive while any voice might still reference their buffers.
    private var retainedBanks: [SampleBank] = []

    init() {
        ring.initialize(repeating: Trigger(), count: Self.ringSize)
        voices.initialize(repeating: Voice(), count: Self.voiceCount)
        head.initialize(to: qk_atomic_u64())
        tail.initialize(to: qk_atomic_u64())
        qk_store_relaxed(head, 0)
        qk_store_relaxed(tail, 0)
        masterGain.initialize(to: 0.8)

        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                   sampleRate: Self.sampleRate,
                                   channels: 2,
                                   interleaved: false)!

        // Capture raw pointers, not self, so the render closure stays trivial.
        let ring = self.ring, head = self.head, tail = self.tail
        let voices = self.voices, master = self.masterGain
        let ringMask = UInt64(Self.ringSize - 1)
        let voiceCount = Self.voiceCount

        sourceNode = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard abl.count >= 2,
                  let outL = abl[0].mData?.assumingMemoryBound(to: Float.self),
                  let outR = abl[1].mData?.assumingMemoryBound(to: Float.self)
            else { return noErr }
            let n = Int(frameCount)
            outL.update(repeating: 0, count: n)
            outR.update(repeating: 0, count: n)

            // Drain pending triggers into free voices.
            var t = qk_load_relaxed(tail)
            let h = qk_load_acquire(head)
            while t < h {
                let trig = ring[Int(t & ringMask)]
                t += 1
                guard let data = trig.samples else { continue }
                for v in 0..<voiceCount where !voices[v].active {
                    // Equal-power pan.
                    let angle = (trig.pan + 1) * 0.25 * Float.pi
                    voices[v] = Voice(samples: data,
                                      count: trig.count,
                                      position: 0,
                                      gainL: trig.gain * cos(angle),
                                      gainR: trig.gain * sin(angle),
                                      active: true)
                    break
                }
            }
            qk_store_release(tail, t)

            // Mix active voices.
            let gain = master.pointee
            for v in 0..<voiceCount where voices[v].active {
                let voice = voices[v]
                let remaining = voice.count - voice.position
                let frames = min(n, remaining)
                let src = voice.samples! + voice.position
                let gl = voice.gainL * gain, gr = voice.gainR * gain
                for i in 0..<frames {
                    let s = src[i]
                    outL[i] += s * gl
                    outR[i] += s * gr
                }
                voices[v].position += frames
                if voices[v].position >= voice.count {
                    voices[v].active = false
                    voices[v].samples = nil
                }
            }
            return noErr
        }

        configureTone(0)
        engine.attach(sourceNode)
        engine.attach(eq)
        engine.connect(sourceNode, to: eq, format: format)
        engine.connect(eq, to: engine.mainMixerNode, format: format)

        // CoreAudio tears the engine down on sleep or output-device changes;
        // isRunning can stay stale afterwards, so rebuild explicitly.
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main) { [weak self] _ in
            self?.restartAfterInterruption()
        }
    }

    deinit {
        engine.stop()
        ring.deallocate()
        head.deallocate()
        tail.deallocate()
        voices.deallocate()
        masterGain.deallocate()
    }

    /// Whether the engine is supposed to be running (user intent, not
    /// CoreAudio state). Lets wake/config-change handlers know if a dead
    /// engine should be revived.
    private var shouldBeRunning = false

    func start() {
        shouldBeRunning = true
        guard !engine.isRunning else { return }
        requestSmallIOBuffer()
        engine.prepare()
        try? engine.start()
    }

    func stop() {
        shouldBeRunning = false
        engine.stop()
    }

    /// Force a full stop + start on the current output device. Used after
    /// sleep/wake and configuration changes, where `isRunning` may report
    /// true while the engine is actually dead.
    func restartAfterInterruption() {
        guard shouldBeRunning else { return }
        engine.stop()
        requestSmallIOBuffer()
        engine.prepare()
        try? engine.start()
    }

    /// Ask CoreAudio for a 128-frame device buffer (~2.7 ms at 48 kHz).
    private func requestSmallIOBuffer() {
        guard let unit = engine.outputNode.audioUnit else { return }
        var frames: UInt32 = 128
        AudioUnitSetProperty(unit,
                             kAudioDevicePropertyBufferFrameSize,
                             kAudioUnitScope_Global,
                             0,
                             &frames,
                             UInt32(MemoryLayout<UInt32>.size))
    }

    // MARK: - Control (main / event-tap threads)

    var volume: Float {
        get { masterGain.pointee }
        set { masterGain.pointee = max(0, min(1.5, newValue)) }
    }

    /// Tone tilt, -1 (darker) … +1 (brighter). Shelving EQ pair.
    func configureTone(_ tone: Float) {
        let t = max(-1, min(1, tone))
        let low = eq.bands[0]
        low.filterType = .lowShelf
        low.frequency = 250
        low.gain = t * -6
        low.bypass = false
        let high = eq.bands[1]
        high.filterType = .highShelf
        high.frequency = 3_000
        high.gain = t * 8
        high.bypass = false
    }

    /// Fire a sample. Producer side of the ring — event-tap thread only.
    func trigger(buffer: SampleBuffer, gain: Float, pan: Float) {
        let h = qk_load_relaxed(head)
        let t = qk_load_acquire(tail)
        guard h - t < UInt64(Self.ringSize) else { return }   // ring full: drop
        ring[Int(h & UInt64(Self.ringSize - 1))] = Trigger(samples: buffer.samples,
                                                           count: buffer.count,
                                                           gain: gain,
                                                           pan: pan)
        qk_store_release(head, h + 1)
    }

    /// Keep `bank` alive while its buffers may still be rendering.
    /// Prune older banks after every possible voice has ended (< 1 s).
    func retain(bank: SampleBank) {
        retainedBanks.append(bank)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self else { return }
            // Newest bank is always last; by now every voice playing an
            // older bank has finished (samples are < 0.25 s long).
            if let newest = self.retainedBanks.last {
                self.retainedBanks = [newest]
            }
        }
    }
}
