import AVFoundation

/// An immutable, preloaded mono sample held in a contiguous float buffer.
/// Allocated once at load time; the audio render thread only ever reads it.
final class SampleBuffer {
    let samples: UnsafeMutablePointer<Float>
    let count: Int

    init?(url: URL, targetSampleRate: Double) {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                         sampleRate: targetSampleRate,
                                         channels: 1,
                                         interleaved: false) else { return nil }

        let ratio = targetSampleRate / file.processingFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(file.length) * ratio) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity),
              let converter = AVAudioConverter(from: file.processingFormat, to: format)
        else { return nil }

        let inCapacity = AVAudioFrameCount(file.length)
        guard let inBuf = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                           frameCapacity: max(inCapacity, 1)),
              (try? file.read(into: inBuf)) != nil else { return nil }

        var fed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if fed {
                status.pointee = .endOfStream
                return nil
            }
            fed = true
            status.pointee = .haveData
            return inBuf
        }
        if error != nil || out.frameLength == 0 { return nil }

        count = Int(out.frameLength)
        samples = .allocate(capacity: count)
        samples.update(from: out.floatChannelData![0], count: count)
    }

    deinit { samples.deallocate() }
}

/// One playable key class: round-robin press and release variants.
struct SampleSet {
    let down: [SampleBuffer]
    let up: [SampleBuffer]
}

/// All buffers for the active switch profile, plus the shared mouse clicks.
/// The engine retains banks until every voice referencing them has finished.
final class SampleBank {
    enum KeyClass: String, CaseIterable {
        case `default`, space, `return`, delete
    }

    private(set) var keys: [KeyClass: SampleSet] = [:]
    private(set) var mouse: [MouseButton: SampleSet] = [:]
    let gain: Float

    private var rrDown: [KeyClass: Int] = [:]
    private var rrUp: [KeyClass: Int] = [:]

    init(profile: Profile, mouseManifest: MouseManifest?, sampleRate: Double) {
        gain = profile.gain
        for (className, entry) in profile.keys {
            guard let keyClass = KeyClass(rawValue: className) else { continue }
            let downs = entry.down.compactMap {
                SampleBuffer(url: profile.directory.appendingPathComponent($0),
                             targetSampleRate: sampleRate)
            }
            let ups = entry.up.compactMap {
                SampleBuffer(url: profile.directory.appendingPathComponent($0),
                             targetSampleRate: sampleRate)
            }
            keys[keyClass] = SampleSet(down: downs, up: ups)
        }
        if let mm = mouseManifest {
            for (button, entry) in mm.buttons {
                let downs = entry.down.compactMap {
                    SampleBuffer(url: mm.directory.appendingPathComponent($0),
                                 targetSampleRate: sampleRate)
                }
                let ups = entry.up.compactMap {
                    SampleBuffer(url: mm.directory.appendingPathComponent($0),
                                 targetSampleRate: sampleRate)
                }
                mouse[button] = SampleSet(down: downs, up: ups)
            }
        }
    }

    /// Round-robin pick. Called on the event-tap thread only (single consumer).
    func nextBuffer(for keyClass: KeyClass, isDown: Bool) -> SampleBuffer? {
        let set = keys[keyClass] ?? keys[.default]
        guard let set else { return nil }
        let pool = isDown ? set.down : set.up
        guard !pool.isEmpty else { return nil }
        var table = isDown ? rrDown : rrUp
        let idx = (table[keyClass] ?? 0) % pool.count
        table[keyClass] = idx + 1
        if isDown { rrDown = table } else { rrUp = table }
        return pool[idx]
    }

    func nextMouseBuffer(for button: MouseButton, isDown: Bool) -> SampleBuffer? {
        guard let set = mouse[button] else { return nil }
        let pool = isDown ? set.down : set.up
        guard !pool.isEmpty else { return nil }
        return pool.randomElement()
    }
}

enum MouseButton: String, Codable {
    case mouse_left, mouse_right, mouse_middle
}
