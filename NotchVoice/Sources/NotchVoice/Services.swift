import Foundation

/// Clients for the two local servers. Everything is 127.0.0.1.
enum Local {
    static let whisper = URL(string: "http://127.0.0.1:8178")!
    static let brain = URL(string: "http://127.0.0.1:8179")!

    struct Failure: Error { let message: String }

    static func transcribe(_ wav: Data) async throws -> String {
        let b = UUID().uuidString
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(b)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".data(using: .utf8)!)
        }
        body.append("--\(b)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"a.wav\"\r\nContent-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(wav)
        body.append("\r\n".data(using: .utf8)!)
        field("response_format", "json")
        field("prompt", "Hey Notch.") // biases Whisper to spell the wake word right
        body.append("--\(b)--\r\n".data(using: .utf8)!)
        let json = try await post(whisper.appendingPathComponent("inference"), body, "multipart/form-data; boundary=\(b)")
        return ((json["text"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Returns laya's `answers` dict.
    static func decide(_ state: String, _ questions: [String: Any]) async throws -> [String: [String: Any]] {
        let body = try JSONSerialization.data(withJSONObject: ["state": state, "questions": questions])
        let json = try await post(brain.appendingPathComponent("decide"), body)
        guard let answers = json["answers"] as? [String: [String: Any]] else {
            throw Failure(message: json["error"] as? String ?? "bad laya reply")
        }
        return answers
    }

    static func speak(_ text: String) async throws -> URL {
        let body = try JSONSerialization.data(withJSONObject: ["text": text])
        let json = try await post(brain.appendingPathComponent("speak"), body)
        guard let path = json["wav"] as? String else { throw Failure(message: json["error"] as? String ?? "no audio") }
        return URL(fileURLWithPath: path)
    }

    static func healthy(_ url: URL) async -> Bool {
        var req = URLRequest(url: url)
        req.timeoutInterval = 1
        return (try? await URLSession.shared.data(for: req)) != nil
    }

    private static func post(_ url: URL, _ body: Data, _ type: String = "application/json") async throws -> [String: Any] {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(type, forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        req.timeoutInterval = 120
        let (data, _) = try await URLSession.shared.data(for: req)
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
}

/// Starts whisper-server and the laya/OmniVoice sidecar, restarts them if they die, stops them on quit.
final class Servers {
    static let shared = Servers()
    private var procs: [Process] = []
    private var quitting = false

    func start() async {
        let root = Settings.root
        if await !Local.healthy(Local.whisper) {
            launch("/opt/homebrew/bin/whisper-server",
                   ["-m", root.appendingPathComponent("models/ggml-base.en.bin").path,
                    "--host", "127.0.0.1", "--port", "8178"])
        }
        if await !Local.healthy(Local.brain) {
            launch(root.appendingPathComponent("sidecar/.venv/bin/python").path,
                   [root.appendingPathComponent("sidecar/laya_server.py").path],
                   env: ["HF_HUB_OFFLINE": "1"])
        }
        for _ in 0 ..< 120 {  // Laya + OmniVoice load takes a few seconds
            if await Local.healthy(Local.whisper), await Local.healthy(Local.brain) { return }
            try? await Task.sleep(for: .milliseconds(500))
        }
    }

    private func launch(_ exe: String, _ args: [String], env: [String: String] = [:]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        p.environment = ProcessInfo.processInfo.environment.merging(env) { $1 }
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        p.terminationHandler = { [weak self] dead in
            guard let self, !self.quitting else { return }
            self.procs.removeAll { $0 === dead }
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) { self.launch(exe, args, env: env) }
        }
        do { try p.run(); procs.append(p) } catch { NSLog("NotchVoice: cannot launch \(exe): \(error)") }
    }

    func stop() {
        quitting = true
        procs.forEach { $0.terminate() }
    }
}

/// Appends to ~/Library/Logs/NotchVoice.log
func log(_ s: String) {
    let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/NotchVoice.log")
    let line = "\(Date().formatted(.iso8601.time(includingFractionalSeconds: true))) \(s)\n"
    if let h = try? FileHandle(forWritingTo: url) {
        h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close()
    } else {
        try? line.write(to: url, atomically: true, encoding: .utf8)
    }
}
