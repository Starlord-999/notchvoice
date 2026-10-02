import AVFoundation
import Speech

/// Apple on-device recognizer used only for the live preview; Whisper still produces the final text.
final class LiveSpeech {
    var onText: (String) -> Void = { _ in }
    private let rec = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let lock = NSLock()
    private var req: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    static func authorize() { SFSpeechRecognizer.requestAuthorization { _ in } }

    func begin() {
        guard let rec, rec.isAvailable, SFSpeechRecognizer.authorizationStatus() == .authorized else { return }
        end()
        let r = SFSpeechAudioBufferRecognitionRequest()
        r.shouldReportPartialResults = true
        r.requiresOnDeviceRecognition = rec.supportsOnDeviceRecognition
        lock.lock(); req = r; lock.unlock()
        task = rec.recognitionTask(with: r) { [weak self] res, _ in
            guard let t = res?.bestTranscription.formattedString else { return }
            DispatchQueue.main.async { self?.onText(t) }
        }
    }

    /// Audio thread.
    func feed(_ b: AVAudioPCMBuffer) {
        lock.lock(); req?.append(b); lock.unlock()
    }

    func end() {
        lock.lock(); let r = req; req = nil; lock.unlock()
        r?.endAudio()
        task?.cancel()
        task = nil
    }
}
