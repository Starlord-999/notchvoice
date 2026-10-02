import AVFoundation

/// One AVAudioEngine for mic + playback, so voice processing can cancel our own speech (echo).
/// Mic side: energy VAD cuts speech into 16 kHz mono Int16 segments.
final class Audio {
    var onSpeechStart: () -> Void = {}
    var onSegment: (Data) -> Void = { _ in }
    var onSpeechEnd: () -> Void = {}
    var onBuffer: (AVAudioPCMBuffer) -> Void = { _ in }  // audio thread, only while speech is active

    // Calibration knobs — real rooms differ.
    // ponytail: energy VAD with adaptive noise floor; swap for Silero / whisper VAD if noisy rooms false-trigger.
    var minRMS: Float = 0.01
    var floorMultiplier: Float = 3
    var silenceToEnd = 0.7
    var maxSegment = 8.0
    var minSpeech = 0.3
    var preroll = 0.3

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let out16k = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)!
    private var mono: AVAudioFormat!
    private var converter: AVAudioConverter!

    private var noiseFloor: Float = 0.005
    private var inSpeech = false
    private var segment = Data()
    private var recent: [(Data, Double)] = []
    private var speechSec = 0.0, silenceSec = 0.0, totalSec = 0.0

    func start() throws {
        // Order matters: connect playback BEFORE enabling voice processing, else start() fails with -10875.
        engine.attach(player)
        // OmniVoice always writes 24 kHz mono.
        engine.connect(player, to: engine.mainMixerNode, format: AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1))

        let input = engine.inputNode
        try input.setVoiceProcessingEnabled(true)
        // Voice processing ducks other apps' audio by default; keep that minimal.
        input.voiceProcessingOtherAudioDuckingConfiguration = .init(enableAdvancedDucking: false, duckingLevel: .min)
        let inFormat = input.outputFormat(forBus: 0)
        mono = AVAudioFormat(standardFormatWithSampleRate: inFormat.sampleRate, channels: 1)
        converter = AVAudioConverter(from: mono, to: out16k)

        input.installTap(onBus: 0, bufferSize: 1024, format: inFormat) { [weak self] buf, _ in self?.process(buf) }
        engine.prepare()
        try engine.start()
    }

    // MARK: playback

    var volume: Float {
        get { player.volume }
        set { player.volume = newValue }
    }

    func play(_ url: URL) async {
        guard let file = try? AVAudioFile(forReading: url) else { return }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            player.scheduleFile(file, at: nil, completionCallbackType: .dataPlayedBack) { _ in c.resume() }
            player.play()
        }
    }

    func stopPlayback() {
        player.stop()  // fires pending completion handlers, so play() returns
        player.volume = 1
    }

    // MARK: mic + VAD (audio thread)

    private func process(_ buf: AVAudioPCMBuffer) {
        guard let ch = buf.floatChannelData?[0], buf.frameLength > 0 else { return }
        let n = Int(buf.frameLength)
        var sum: Float = 0
        for i in 0 ..< n { sum += ch[i] * ch[i] }
        let rms = (sum / Float(n)).squareRoot()
        let dur = Double(n) / buf.format.sampleRate
        let pcm = to16k(buf)
        let loud = rms > max(minRMS, noiseFloor * floorMultiplier)

        if !inSpeech {
            recent.append((pcm, dur))
            while recent.map(\.1).reduce(0, +) > preroll { recent.removeFirst() }
            guard loud else {
                noiseFloor = noiseFloor * 0.98 + rms * 0.02
                return
            }
            inSpeech = true
            segment = recent.map(\.0).reduce(Data(), +)
            speechSec = dur; silenceSec = 0; totalSec = dur
            recent.removeAll()
            onBuffer(buf)
            DispatchQueue.main.async { self.onSpeechStart() }
            return
        }

        onBuffer(buf)
        segment.append(pcm)
        totalSec += dur
        if loud { speechSec += dur; silenceSec = 0 } else { silenceSec += dur }
        if silenceSec >= silenceToEnd || totalSec >= maxSegment {
            inSpeech = false
            DispatchQueue.main.async { self.onSpeechEnd() }
            if speechSec >= minSpeech {
                let wav = Audio.wav(segment)
                DispatchQueue.main.async { self.onSegment(wav) }
            }
            segment = Data()
        }
    }

    private func to16k(_ buf: AVAudioPCMBuffer) -> Data {
        guard let m = AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: buf.frameLength) else { return Data() }
        m.frameLength = buf.frameLength
        memcpy(m.floatChannelData![0], buf.floatChannelData![0], Int(buf.frameLength) * 4)  // channel 0 only
        let cap = AVAudioFrameCount(Double(buf.frameLength) * 16000 / buf.format.sampleRate) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: out16k, frameCapacity: cap) else { return Data() }
        var fed = false
        converter.convert(to: out, error: nil) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true
            status.pointee = .haveData
            return m
        }
        return Data(bytes: out.int16ChannelData![0], count: Int(out.frameLength) * 2)
    }

    /// 16 kHz mono s16le PCM -> WAV bytes.
    static func wav(_ pcm: Data) -> Data {
        var d = Data()
        func u32(_ v: Int) { withUnsafeBytes(of: UInt32(v).littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: Int) { withUnsafeBytes(of: UInt16(v).littleEndian) { d.append(contentsOf: $0) } }
        d.append("RIFF".data(using: .ascii)!); u32(36 + pcm.count)
        d.append("WAVEfmt ".data(using: .ascii)!); u32(16); u16(1); u16(1); u32(16000); u32(32000); u16(2); u16(16)
        d.append("data".data(using: .ascii)!); u32(pcm.count)
        d.append(pcm)
        return d
    }
}
