import AppKit

/// Hands-free loop: mic segment -> Whisper -> word rules -> Laya -> action -> OmniVoice.
@MainActor
final class Assistant: ObservableObject {
    static let shared = Assistant()

    weak var vm: NotchViewModel?
    @Published var status = "Starting…"
    @Published var heard = ""
    @Published var fileName: String?
    @Published var hearing = false
    @Published var speaking = false
    @Published var thinking = false
    @Published var live = ""  // Apple Speech partials while you talk
    private let liveSpeech = LiveSpeech()

    private let audio = Audio()
    private var sentences: [String] = []
    private var keyPoints: [String] = []
    private var pending: (intent: String, at: Date)?  // intent awaiting a spoken yes/no
    private var speakTask: Task<Void, Never>?
    private var lastActive = Date()

    // Laya choice options. Descriptions matter: bare labels scored 0.2–0.5, described ones 0.9+.
    static let intents: [String: String] = [
        "open": "open, show or expand the notch panel",
        "close": "close, hide or dismiss the notch panel, goodbye",
        "read_file": "read the dropped file or document aloud",
        "key_points": "the main or key points, highlights, gist of the file",
        "find_in_file": "find or look for something specific in the file, what does it say about something",
        "what_is_file": "what kind of file or document this is",
        "is_urgent": "whether the file is urgent, has a deadline or needs action soon",
        "look_at_selection": "look at, open or use the file selected in Finder",
        "run_shortcut": "do a task, run an automation or shortcut, turn something on or off on the Mac",
        "ignore": "not a command for the assistant; background talk",
    ]
    static let fileIntents: Set = ["read_file", "key_points", "find_in_file", "what_is_file", "is_urgent"]
    static let kinds = ["invoice", "receipt", "contract", "resume", "letter", "report", "article",
                        "notes", "code", "form", "other"]

    // Fixed replies are rendered once and cached by the sidecar -> instant playback.
    static let confirm: [String: String] = [
        "open": "Open the notch?", "close": "Close the notch?", "read_file": "Read the file?",
        "key_points": "Key points?", "find_in_file": "Search the file?", "what_is_file": "Check the file type?",
        "is_urgent": "Check if it's urgent?", "look_at_selection": "Use the Finder selection?",
    ]
    static var fixedReplies: [String] {
        ["Yes?", "I'm here.", "Opening.", "Done.", "You have no shortcuts yet.",
         "I need Accessibility permission to type.", "I need Accessibility permission for that.", "Couldn't find that.",
         "Turn on Allow JavaScript from Apple Events in the browser's Developer menu.", "Bye.", "Okay.", "Got it.", "Drop a file on the notch first.",
         "Here are the key points.", "Couldn't find that.", "Nothing selected in Finder.",
         "I couldn't read that file.", "Yes, it looks urgent.", "It doesn't look urgent.", "Looking."]
            + Array(confirm.values)
            + kinds.map { kindReply($0) }
    }

    static func kindReply(_ k: String) -> String {
        k == "other" ? "I'm not sure what kind of file this is." : "This looks like \(["a", "e", "i", "o", "u"].contains(k.prefix(1)) ? "an" : "a") \(k)."
    }

    // MARK: lifecycle

    func start() async {
        status = "Starting local models…"
        log("start: servers")
        await Servers.shared.start()
        log("start: servers ready, starting mic")
        audio.onSpeechStart = { [weak self] in self?.speechStarted() }
        LiveSpeech.authorize()
        liveSpeech.onText = { [weak self] t in self?.live = t }
        audio.onBuffer = { [liveSpeech] b in liveSpeech.feed(b) }
        audio.onSpeechEnd = { [weak self] in
            self?.liveSpeech.end()
            Task { @MainActor in  // short blips never reach Whisper, so clear the preview ourselves
                try? await Task.sleep(for: .seconds(2))
                if self?.hearing == false, self?.thinking == false { self?.live = "" }
            }
        }
        audio.onSegment = { [weak self] wav in Task { await self?.handle(wav) } }
        do {
            try audio.start()
        } catch {
            status = "Mic unavailable: \(error.localizedDescription)"
            log("mic failed: \(error)")
            return
        }
        status = "Say “Hey Notch”"
        Task { await Actions.loadShortcuts() }
        Actions.trackFrontmost()
        log("mic started; accessibility granted: \(AXIsProcessTrusted())")
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.autoClose() }
        }
        Task.detached(priority: .background) {  // warm the reply cache (~3 s each, first run only)
            for r in await Assistant.fixedReplies { _ = try? await Local.speak(r) }
        }
    }

    private func autoClose() {
        let active = Date() < sessionUntil || dictating
        if active != inSession { inSession = active }
        guard let vm, vm.status == .opened, vm.openReason == .voice, !typeLocked, !commandLocked, !speaking, !thinking,
              Date().timeIntervalSince(lastActive) > 20 else { return }
        vm.notchClose()
    }

    // MARK: listening

    private func speechStarted() {
        hearing = true
        live = ""
        liveSpeech.begin()
        if inSession, vm?.status != .opened { vm?.notchOpen(.voice) }  // show the live text
        log("speech start")
        if speaking { audio.volume = 0.25 }  // duck; decide after we know what was said
    }

    func handle(_ wav: Data) async {
        hearing = false
        defer { if speaking { audio.volume = 1 } }
        let raw = (try? await Local.transcribe(wav)) ?? ""
        log("heard \(wav.count) bytes: \(raw)")
        live = ""
        guard !Words.isJunk(raw) else { return }
        let n = Words.normalize(raw)
        let open = vm?.status == .opened

        if Words.isStop(n) {  // keyword beats Laya for one-word commands
            heard = raw
            if dictating { dictating = false; status = "Stopped typing" }
            stopSpeaking()
            return
        }
        let wake = typeLocked ? nil : Words.afterWake(n)
        if let p = pending, wake == nil, Date().timeIntervalSince(p.at) < 8 {
            pending = nil
            heard = raw
            if await isYes(raw, n) { await perform(p.intent, raw) } else { say("Okay.") }
            return
        }
        pending = nil

        var command = n
        if let rest = wake {
            command = rest
            dictating = false  // "Hey Notch …" always means a command, even mid-dictation
            if !open { vm?.notchOpen(.voice) }
            extendSession()
            heard = raw
            if rest.isEmpty { say("Yes?"); return }
        } else if !inSession || (Settings.requireWake && !commandLocked && !typeLocked) {
            return  // not addressed and no session: background talk
        }
        heard = raw

        if Words.endsSession(command) {
            endSession()
            say("Bye.")
            return
        }
        if dictating {
            await dictate(raw, command)
            return
        }
        if await structured(raw, command) {
            extendSession()
            return
        }
        thinking = true
        defer { thinking = false }
        guard let a = try? await Local.decide(command, ["intent": [
            "type": "choice", "instructions": "What does the user want the notch assistant to do?",
            "criteria": Self.intents,
        ]])["intent"], let intent = a["choice"] as? String, let conf = a["confidence"] as? Double else {
            status = "Brain not responding"
            return
        }
        status = "\(intent) · \(Int(conf * 100))%"
        log("intent \(intent) \(conf) for: \(command)")
        guard intent != "ignore" else { return }
        if conf >= Settings.actAt {
            extendSession()
            await perform(intent, command)
        } else if conf >= Settings.confirmAt, wake != nil {  // only confirm when explicitly addressed
            pending = (intent, Date())
            say(Self.confirm[intent] ?? "Did you mean \(intent)?")
        }
    }

    // MARK: session + dictation

    /// "Hey Notch" opens a session: commands need no wake phrase until "bye" or 30 s without a command.
    private var sessionUntil = Date.distantPast
    @Published var dictating = false
    @Published var inSession = false
    private var typedInDictation = false

    private func extendSession() { sessionUntil = commandLocked ? .distantFuture : Date().addingTimeInterval(30) }

    /// Two buttons / hotkeys: Type (everything is typed, no wake word) and Command (everything is a command).
    @Published var typeLocked = false
    @Published var commandLocked = false

    func toggleType() {
        typeLocked.toggle()
        commandLocked = false
        dictating = typeLocked
        typedInDictation = false
        sessionUntil = typeLocked ? .distantFuture : .distantPast
        status = typeLocked ? "Typing — speak, press again to stop" : "Stopped typing"
        if typeLocked, vm?.status != .opened { vm?.notchOpen(.voice) }
    }

    func toggleCommand() {
        commandLocked.toggle()
        typeLocked = false
        dictating = false
        sessionUntil = commandLocked ? .distantFuture : .distantPast
        status = commandLocked ? "Command mode — speak a command" : "Command mode off"
        if commandLocked, vm?.status != .opened { vm?.notchOpen(.voice) }
    }

    private func endSession() {
        sessionUntil = .distantPast
        dictating = false
        typeLocked = false
        commandLocked = false
        vm?.notchClose()
    }

    /// While dictating, everything heard is typed; a few phrases are keys instead.
    private func dictate(_ raw: String, _ n: String) async {
        extendSession()
        if Words.stopDictation.contains(n) {
            dictating = false
            typeLocked = false
            status = "Stopped typing"
            log("dictation off")
            return
        }
        if ["new line", "next line", "new paragraph"].contains(n) {
            for _ in 0 ..< (n == "new paragraph" ? 2 : 1) { _ = await Actions.press(36, []) }
            return
        }
        if Words.isSend(n) { await send(); return }
        if ["delete that", "undo that", "scratch that", "undo"].contains(n) { _ = await Actions.press(6, .maskCommand); return }
        if let rest = Actions.rest(after: ["press", "hit"], in: n), let (code, flags) = Actions.parseKeys(rest) {
            _ = await Actions.press(code, flags)
            return
        }
        log("dictate: \(raw)")
        if await Actions.type((typedInDictation ? " " : "") + raw, into: nil) {
            typedInDictation = true
            status = "Dictating…"
        } else {
            say("I need Accessibility permission to type.")
        }
    }

    /// Runs a browser action; explains the one-time browser setting if JavaScript is blocked.
    private func browser(_ body: () throws -> Void) {
        do { try body() } catch {
            let msg = (error as? Browser.Failure)?.message ?? "\(error)"
            log("browser: \(msg)")
            if msg.localizedCaseInsensitiveContains("javascript") {
                say("Turn on Allow JavaScript from Apple Events in the browser's Developer menu.")
            } else {
                status = msg
            }
        }
    }

    private func send() async {
        log("send")
        if !Actions.click("send") { _ = await Actions.press(36, []) }
        status = "Sent"
    }

    /// Commands handled by plain parsing (Laya can't pick from 100+ apps, copy text or name keys). True if handled.
    private func structured(_ raw: String, _ command: String) async -> Bool {
        let closePanel = { if self.vm?.openReason == .voice { self.vm?.notchClose() } }
        let noAccess = { self.say("I need Accessibility permission for that.") }

        if let s = VoiceExtras.handle(command) { status = s; return true }

        if Words.startDictation.contains(command) {
            dictating = true
            typedInDictation = false
            status = "Dictating… say “stop typing” to finish"
            log("dictation on")
            return true
        }
        if let (app, text) = Actions.typing(raw, apps: Actions.apps.keys) {
            log("type into \(app ?? "front app"): \(text)")
            closePanel()
            if await Actions.type(text, into: app.flatMap { Actions.apps[$0] }) {
                dictating = true  // keep typing whatever comes next, across pauses
                typedInDictation = true
                status = "Dictating… say “stop typing” to finish"
            } else {
                noAccess()
            }
            return true
        }
        if Words.isSend(command) {
            await send()
            return true
        }
        if let rest = Actions.rest(after: ["press", "hit", "push"], in: command) {
            if let (code, flags) = Actions.parseKeys(rest) {
                log("press \(rest)")
                if !(await Actions.press(code, flags)) { noAccess() }
            } else if !Actions.click(rest) {
                say("Couldn't find that.")
            }
            status = "Pressed \(rest)"
            return true
        }
        if let (code, flags) = Actions.parseKeys(command), command.count > 1 {  // "enter", "escape", "command z"
            log("press \(command)")
            if !(await Actions.press(code, flags)) { noAccess() }
            status = "Pressed \(command)"
            return true
        }
        if let (n, kind) = Words.ordinal(command) {
            log("ordinal \(n) \(kind)")
            if kind == "tab" {
                if !(await Actions.press(n < 0 || n > 8 ? 25 : Actions.keyCodes[String(n)]!, .maskCommand)) { noAccess() }
            } else if Browser.front != nil, !["button", "field", "box"].contains(kind) {
                browser { let t = try Browser.openNth(n); self.status = t.isEmpty ? "No such link" : "Opened \(t)" }
            } else if !Actions.clickNth(n, kind) {
                say("Couldn't find that.")
            }
            return true
        }
        if let q = Actions.rest(after: ["search for", "search", "google", "look up"], in: command),
           !q.split(separator: " ").contains(where: { ["file", "page", "document", "this"].contains($0) }) {
            log("search \(q)")
            Browser.navigate(Browser.searchURL(q))
            status = "Searching \(q)"
            return true
        }
        if let (verb, app) = Actions.namedAppControl(command) {
            log("\(verb) \(app.localizedName ?? "")")
            if verb == "hide" { app.hide() } else { app.terminate() }
            status = "\(verb.capitalized) \(app.localizedName ?? "")"
            return true
        }
        if let control = Actions.matchControl(command) {
            log("control \(control)")
            closePanel()
            if await Actions.perform(control) { status = control.capitalized } else { noAccess() }
            return true
        }
        if let rest = Actions.rest(after: Actions.openVerbs, in: command) {
            let found = Actions.matchApps(rest, in: Actions.apps.keys)
            if !found.isEmpty {
                log("open apps \(found)")
                found.forEach { Actions.open(Actions.apps[$0]!) }
                status = "Opened \(found.joined(separator: ", "))"
                say("Opening.")
                return true
            }
        }
        if let rest = Actions.rest(after: ["go to", "visit", "open", "navigate to"], in: command),
           Browser.front != nil || rest.split(separator: " ").contains(where: { ["com", "org", "net", "io", "dot"].contains($0) }),
           let url = Browser.url(forSite: rest) {
            log("navigate \(url)")
            Browser.navigate(url)
            status = "Going to \(url.host ?? "")"
            return true
        }
        if let rest = Actions.rest(after: ["click on", "click", "tap on", "tap", "select", "choose"], in: command) {
            log("click \(rest)")
            if Browser.front != nil, let t = try? Browser.click(rest), !t.isEmpty {
                status = "Clicked \(t)"
            } else if Actions.click(rest) {
                status = "Clicked \(rest)"
            } else {
                say("Couldn't find that.")
            }
            return true
        }
        return false
    }

    private func isYes(_ raw: String, _ n: String) async -> Bool {
        if let yn = Words.yesNo(n) { return yn }
        let a = try? await Local.decide(raw, ["yes": ["type": "noul", "instructions": "Does the user say yes or agree?"]])
        return (a?["yes"]?["noul"] as? Double ?? 0) >= 0.5
    }

    // MARK: actions

    func perform(_ intent: String, _ command: String) async {
        log("perform \(intent)")
        let aboutPage = command.split(separator: " ").contains { ["page", "site", "website", "article", "tab"].contains($0) }
        if Self.fileIntents.contains(intent), Browser.front != nil, aboutPage || sentences.isEmpty {
            browser {
                let (title, text) = try Browser.pageText()
                self.fileName = title
                self.sentences = FileText.sentences(text)
                self.keyPoints = []
            }
        }
        if Self.fileIntents.contains(intent), sentences.isEmpty {
            say("Drop a file on the notch first.")
            return
        }
        switch intent {
        case "open":
            vm?.notchOpen(.voice)
            say("I'm here.")
        case "close":
            say("Bye.")
            endSession()
        case "read_file":
            speak(sentences)
        case "key_points":
            if keyPoints.isEmpty { keyPoints = await rankKeyPoints() }
            speak(["Here are the key points."] + keyPoints)
        case "find_in_file":
            say("Looking.")
            if let hit = await find(command) { speak([hit]) } else { say("Couldn't find that.") }
        case "what_is_file":
            let a = try? await Local.decide(head(), ["kind": [
                "type": "choice", "instructions": "What kind of document is this?", "criteria": Self.kinds,
            ]])
            say(Self.kindReply(a?["kind"]?["choice"] as? String ?? "other"))
        case "is_urgent":
            let a = try? await Local.decide(head(), ["urgent": [
                "type": "noul", "instructions": "Does this document communicate a deadline, time pressure or need for action soon?",
            ]])
            say((a?["urgent"]?["noul"] as? Double ?? 0) >= 0.5 ? "Yes, it looks urgent." : "It doesn't look urgent.")
        case "run_shortcut":
            guard !Actions.shortcuts.isEmpty else { say("You have no shortcuts yet."); return }
            let a = try? await Local.decide(command, ["which": [
                "type": "choice", "instructions": "Which shortcut should run?", "criteria": Actions.shortcuts,
            ]])
            if let name = a?["which"]?["choice"] as? String, (a?["which"]?["confidence"] as? Double ?? 0) >= Settings.confirmAt {
                log("shortcut \(name)")
                Actions.runShortcut(name)
                status = "Ran \(name)"
                say("Done.")
            } else {
                say("Couldn't find that.")
            }
        case "look_at_selection":
            if let url = finderSelection() { load(url) } else { say("Nothing selected in Finder.") }
        default:
            break
        }
    }

    // MARK: files

    func load(_ url: URL) {
        vm?.notchOpen(.voice)  // no focus steal; also auto-closes when idle
        lastActive = Date()
        fileName = url.lastPathComponent
        status = "Reading \(url.lastPathComponent)…"
        Task {
            let text = await Task.detached { (try? FileText.extract(url)) ?? "" }.value
            sentences = FileText.sentences(text)
            keyPoints = []
            guard !sentences.isEmpty else {
                status = "No text found"
                say("I couldn't read that file.")
                return
            }
            status = "\(sentences.count) sentences"
            say("Got it.")
            // Prefetch so "read" and "key points" start fast.
            keyPoints = await rankKeyPoints()
            for s in sentences.prefix(2) + keyPoints { _ = try? await Local.speak(s) }
        }
    }

    private func head() -> String { String(sentences.joined(separator: " ").prefix(1500)) }

    // ponytail: scores the first 120 sentences one Laya call each (~30 ms); chunk-then-rank if files get huge.
    private func rankKeyPoints() async -> [String] {
        var scored: [(Int, Double)] = []
        for (i, s) in sentences.prefix(120).enumerated() {
            let a = try? await Local.decide(s, ["imp": [
                "type": "score", "instructions": "How important is this sentence to the document's main point?",
                "criteria": ["minor detail", "somewhat important", "key point"],
            ]])
            scored.append((i, a?["imp"]?["score"] as? Double ?? 0))
        }
        return scored.sorted { $0.1 > $1.1 }.prefix(3).sorted { $0.0 < $1.0 }.map { sentences[$0.0] }
    }

    private func find(_ query: String) async -> String? {
        var best: (String, Double)?
        for s in sentences.prefix(120) {
            let a = try? await Local.decide(s, ["hit": [
                "type": "noul", "instructions": "Does this sentence answer or mention: \(query)?",
            ]])
            let p = a?["hit"]?["noul"] as? Double ?? 0
            if p > (best?.1 ?? 0) { best = (s, p) }
        }
        return (best?.1 ?? 0) >= 0.6 ? best?.0 : nil
    }

    private func finderSelection() -> URL? {
        let src = "tell application \"Finder\" to get POSIX path of (item 1 of (get selection) as alias)"
        guard let path = NSAppleScript(source: src)?.executeAndReturnError(nil).stringValue else { return nil }
        return URL(fileURLWithPath: path)
    }

    // MARK: speaking

    func say(_ text: String) { speak([text]) }

    /// Plays sentences in order, fetching the next one while the current one plays.
    func speak(_ texts: [String]) {
        log("say \(texts.first ?? "")\(texts.count > 1 ? " +\(texts.count - 1)" : "")")
        stopSpeaking()
        guard !texts.isEmpty else { return }
        speakTask = Task {
            speaking = true
            defer { speaking = false }
            var next: Task<URL?, Never>? = Task { try? await Local.speak(texts[0]) }
            for i in texts.indices {
                guard let url = await next?.value, !Task.isCancelled else { break }
                next = i + 1 < texts.count ? Task { [t = texts[i + 1]] in try? await Local.speak(t) } : nil
                lastActive = Date()
                await audio.play(url)
                if Task.isCancelled { break }
            }
            next?.cancel()
        }
    }

    func stopSpeaking() {
        speakTask?.cancel()
        speakTask = nil
        audio.stopPlayback()
        speaking = false
    }
}
