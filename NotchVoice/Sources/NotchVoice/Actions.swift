import AppKit

/// Doing things in other apps: open apps, type text, run Apple Shortcuts.
enum Actions {
    static let openVerbs = ["open", "launch", "start", "switch to", "go to", "show me"]
    static let typeVerbs = ["type", "write", "dictate"]
    private static let filler: Set = ["the", "app", "application", "please", "up", "for", "me", "a", "my", "it", "this",
                                      "that", "file", "files", "document", "folder", "one"]

    /// normalized app name -> URL, scanned once at launch.
    static let apps: [String: URL] = {
        var out: [String: URL] = [:]
        let dirs = ["/Applications", "/System/Applications", "/System/Applications/Utilities",
                    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path]
        for d in dirs {
            for f in (try? FileManager.default.contentsOfDirectory(atPath: d)) ?? [] where f.hasSuffix(".app") {
                out[Words.normalize(String(f.dropLast(4)))] = URL(fileURLWithPath: d).appendingPathComponent(f)
            }
        }
        out["finder"] = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
        return out
    }()

    static var shortcuts: [String] = []

    // MARK: parsing (pure)

    /// "can you open safari please" -> "safari please" (first verb anywhere, whole words).
    static func rest(after verbs: [String], in n: String) -> String? {
        let padded = " \(n) "
        let hits = verbs.compactMap { padded.range(of: " \($0) ") }
        guard let r = hits.min(by: { $0.lowerBound < $1.lowerBound }) else { return nil }
        let rest = padded[r.upperBound...].trimmingCharacters(in: .whitespaces)
        return rest.isEmpty ? nil : rest
    }

    /// What to type and (optionally) where, keeping Whisper's casing and punctuation.
    /// "Hey Notch, type Hello." -> (nil, "Hello.")   "In text editor, write how are you?" -> ("textedit", "how are you?")
    /// The verb must start the command, or follow an app name — so "what type of file" is not typing.
    static func typing(_ raw: String, apps names: some Collection<String>) -> (app: String?, text: String)? {
        var s = Substring(raw)
        if let r = raw.range(of: #"\b(notch|natch)\b"#, options: [.regularExpression, .caseInsensitive, .backwards]) {
            s = raw[r.upperBound...]
        }
        guard let m = s.range(of: #"\b(type|write|dictate)\b[\s,.:]*"#, options: [.regularExpression, .caseInsensitive])
        else { return nil }
        let text = s[m.upperBound...].trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        let before = Words.normalize(String(s[..<m.lowerBound]))
        if before.isEmpty { return (nil, text) }
        let place = before.split(separator: " ").filter { !["in", "into", "on", "open", "and", "then", "go", "to"].contains($0) }
            .joined(separator: " ")
        guard let app = matchApp(place, in: names) else { return nil }
        return (app, text)
    }

    /// Installed apps named in spoken words. "anti gravity and nodes" -> ["antigravity", "notes"].
    static func matchApps(_ rest: String, in names: some Collection<String>) -> [String] {
        rest.components(separatedBy: " and ").compactMap { matchApp($0, in: names) }
    }

    /// Best installed-app name for one spoken name. Tolerates Whisper splitting words ("anti gravity"),
    /// plurals ("note") and one-letter mishearings ("nodes").
    static func matchApp(_ rest: String, in names: some Collection<String>) -> String? {
        func sing(_ s: String) -> String {
            s.split(separator: " ").map { $0.count > 3 && $0.hasSuffix("s") ? String($0.dropLast()) : String($0) }
                .joined(separator: " ")
        }
        let words = sing(rest.split(separator: " ").filter { !filler.contains(String($0)) }.joined(separator: " "))
        guard !words.isEmpty else { return nil }
        let byKey = Dictionary(names.map { (sing($0), $0) }, uniquingKeysWith: { a, _ in a })
        if let m = byKey[words] { return m }
        // 1. app name inside the words (longest wins), 2. same with spaces removed
        if let m = byKey.keys.filter({ " \(words) ".contains(" \($0) ") }).max(by: { $0.count < $1.count }) { return byKey[m] }
        let compact = words.replacingOccurrences(of: " ", with: "")
        if let m = byKey.keys.filter({ $0.count >= 4 && compact.contains($0.replacingOccurrences(of: " ", with: "")) })
            .max(by: { $0.count < $1.count }) { return byKey[m] }
        // 3. words inside an app name ("chrome" -> "google chrome")
        if let m = byKey.keys.filter({ " \($0) ".contains(" \(words) ") }).min(by: { $0.count < $1.count }) { return byKey[m] }
        // 4. one-letter mishearing of a single-word app name
        let spoken = words.split(separator: " ").map(String.init)
        return byKey.keys.filter { k in k.count >= 4 && !k.contains(" ") && spoken.contains { oneEdit($0, k) } }
            .min(by: { $0.count < $1.count }).flatMap { byKey[$0] }
    }

    /// Levenshtein distance <= 1.
    static func oneEdit(_ a: String, _ b: String) -> Bool {
        let a = Array(a), b = Array(b)
        guard abs(a.count - b.count) <= 1 else { return false }
        var i = 0, j = 0, edits = 0
        while i < a.count, j < b.count {
            if a[i] == b[j] { i += 1; j += 1; continue }
            edits += 1
            if edits > 1 { return false }
            if a.count > b.count { i += 1 } else if b.count > a.count { j += 1 } else { i += 1; j += 1 }
        }
        return edits + (a.count - i) + (b.count - j) <= 1
    }

    // MARK: doing

    static func open(_ url: URL) {
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    /// Brings `app` forward (launching it + new document if needed), then types. False = no Accessibility permission.
    static func type(_ text: String, into app: URL?) async -> Bool {
        guard trusted()
        else { return false }
        if let app {
            let wasRunning = NSWorkspace.shared.runningApplications.contains { $0.bundleURL == app }
            open(app)
            for _ in 0 ..< 30 where NSWorkspace.shared.frontmostApplication?.bundleURL != app {
                try? await Task.sleep(for: .milliseconds(100))
            }
            // ponytail: fresh launches (TextEdit shows an Open panel) get Cmd-N; apps that restore windows may get an extra one
            if !wasRunning {
                try? await Task.sleep(for: .milliseconds(800))
                key(45, .maskCommand)
            }
            try? await Task.sleep(for: .milliseconds(400))
        } else if NSWorkspace.shared.frontmostApplication?.processIdentifier == NSRunningApplication.current.processIdentifier {
            lastApp?.activate()
            try? await Task.sleep(for: .milliseconds(250))
        }
        focusTextInput()
        try? await Task.sleep(for: .milliseconds(120))  // let the focus land before pasting
        return paste(text)
    }

    /// Makes sure typing lands in a text box: keeps the user's focused field, otherwise picks the main one.
    static func focusTextInput() {
        if Browser.front != nil {
            let r = (try? Browser.focusInput()) ?? "no js"
            log("focus input: \(r)")
            if r == "kept" || r == "focused" { return }  // else fall through to accessibility
        }
        guard let app = targetRoot() else { return }
        if let f = attr(app, "AXFocusedUIElement"), textRoles.contains(attr(f as! AXUIElement, "AXRole") as? String ?? "") {
            return
        }
        let window = attr(app, "AXFocusedWindow").map { $0 as! AXUIElement } ?? app
        var best: (AXUIElement, CGFloat)?
        walk(window) { e, role in
            if textRoles.contains(role), let v = attr(e, "AXSize") {
                var size = CGSize.zero
                AXValueGetValue(v as! AXValue, .cgSize, &size)
                if size.width * size.height > best?.1 ?? 0 { best = (e, size.width * size.height) }
            }
            return false
        }
        if let (e, _) = best {
            AXUIElementSetAttributeValue(e, "AXFocused" as CFString, kCFBooleanTrue)
            log("focus input: largest text area")
        }
    }

    static func key(_ code: CGKeyCode, _ flags: CGEventFlags) {
        let src = CGEventSource(stateID: .combinedSessionState)
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: down)
            e?.flags = flags
            e?.post(tap: .cghidEventTap)
        }
    }

    /// Pastes into the frontmost app, then restores the clipboard.
    private static func paste(_ text: String) -> Bool {
        let pb = NSPasteboard.general
        let old = pb.string(forType: .string)
        pb.clearContents()
        pb.setString(text, forType: .string)
        key(9, .maskCommand)  // Cmd-V
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {  // give the clipboard back
            pb.clearContents()
            if let old { pb.setString(old, forType: .string) }
        }
        return true
    }

    static func loadShortcuts() async {
        shortcuts = await Task.detached { run("/usr/bin/shortcuts", ["list"]) }.value
            .split(separator: "\n").map { String($0) }.filter { !$0.isEmpty }
    }

    static func runShortcut(_ name: String) {
        Task.detached { _ = run("/usr/bin/shortcuts", ["run", name]) }
    }

    @discardableResult
    private static func run(_ exe: String, _ args: [String]) -> String {
        let p = Process(), out = Pipe()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return "" }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    static func check() {
        let names = ["safari", "google chrome", "notes", "visual studio code", "system settings", "slack", "antigravity"]
        assert(matchApp("safari", in: names) == "safari")
        assert(matchApp("chrome", in: names) == "google chrome")
        assert(matchApp("the notes app please", in: names) == "notes")
        assert(matchApp("settings", in: names) == "system settings")
        assert(matchApp("the notch", in: names) == nil)
        assert(rest(after: openVerbs, in: "open safari") == "safari")
        assert(rest(after: openVerbs, in: "open") == nil)
        assert(rest(after: openVerbs, in: "can you open node note that") == "node note that")
        assert(matchApp("node note that", in: names) == "notes")
        assert(matchApp("nord note", in: names) == "notes")
        assert(matchApp("anti gravity", in: names) == "antigravity")
        assert(matchApp("nodes", in: names) == "notes")
        assert(matchApps("anti gravity and nodes", in: names) == ["antigravity", "notes"])
        assert(matchApp("notch", in: names) == nil)
        assert(matchApp("the file", in: ["bluetooth file exchange"]) == nil)
        assert(oneEdit("node", "note") && oneEdit("slak", "slack") && !oneEdit("notch", "note"))
        func t(_ raw: String) -> String? { typing(raw, apps: names + ["textedit"]).map { "\($0.app ?? "-")|\($0.text)" } }
        assert(t("blah blah. Hey Notch, type Hello there, Sam.") == "-|Hello there, Sam.")
        assert(t("Hey Notch, write: Meeting at 5.") == "-|Meeting at 5.")
        assert(t("Hey Notch, what type of file is this?") == nil)
        assert(t("Hey Notch, type") == nil)
        assert(t("In text editor, write how are you? I'm good.") == "textedit|how are you? I'm good.")
        assert(t("Open notes and type buy milk") == "notes|buy milk")
        assert(t("Write hello") == "-|hello")
        print("Actions ok")
    }
}

// MARK: - controlling the frontmost app / window

extension Actions {
    enum Control {
        case keys(CGKeyCode, CGEventFlags)
        case script(String)
        case quit
    }

    private static let cmd = CGEventFlags.maskCommand, shift = CGEventFlags.maskShift,
                       ctrl = CGEventFlags.maskControl, opt = CGEventFlags.maskAlternate

    /// name, spoken phrases, what to do. Standard macOS shortcuts, so they work in most apps.
    static let controls: [(name: String, phrases: [String], action: Control)] = [
        ("full screen", ["full screen", "fullscreen", "maximize", "maximise", "exit full screen"], .keys(3, [cmd, ctrl])),
        ("close tab", ["close tab", "close this tab", "close the tab"], .keys(13, cmd)),
        ("close window", ["close window", "close this window", "close the window", "close this", "close it"], .keys(13, cmd)),
        ("quit", ["quit", "quit this", "quit app", "quit the app", "close app", "close the app", "close this app", "exit app", "kill app"], .quit),
        ("minimize", ["minimize", "minimise"], .keys(46, cmd)),
        ("hide", ["hide this", "hide app", "hide the app", "hide window"], .keys(4, cmd)),
        ("hide others", ["hide others", "hide other apps", "hide everything else"], .keys(4, [cmd, opt])),
        ("new tab", ["new tab", "open a new tab", "open new tab"], .keys(17, cmd)),
        ("reopen tab", ["reopen tab", "reopen closed tab", "undo close tab"], .keys(17, [cmd, shift])),
        ("next tab", ["next tab"], .keys(48, ctrl)),
        ("previous tab", ["previous tab", "last tab"], .keys(48, [ctrl, shift])),
        ("new window", ["new window", "open a new window"], .keys(45, cmd)),
        ("new document", ["new document", "new file", "new note"], .keys(45, cmd)),
        ("reload", ["reload", "refresh"], .keys(15, cmd)),
        ("go back", ["go back", "back"], .keys(33, cmd)),
        ("go forward", ["go forward", "forward"], .keys(30, cmd)),
        ("undo", ["undo"], .keys(6, cmd)),
        ("redo", ["redo"], .keys(6, [cmd, shift])),
        ("copy", ["copy", "copy that", "copy this"], .keys(8, cmd)),
        ("cut", ["cut", "cut that", "cut this"], .keys(7, cmd)),
        ("paste", ["paste", "paste it", "paste that"], .keys(9, cmd)),
        ("select all", ["select all", "select everything"], .keys(0, cmd)),
        ("save", ["save", "save it", "save this", "save file"], .keys(1, cmd)),
        ("find", ["find", "search this page", "find on page"], .keys(3, cmd)),
        ("print", ["print", "print this"], .keys(35, cmd)),
        ("zoom in", ["zoom in", "bigger", "make it bigger"], .keys(24, cmd)),
        ("zoom out", ["zoom out", "smaller", "make it smaller"], .keys(27, cmd)),
        ("actual size", ["actual size", "reset zoom"], .keys(29, cmd)),
        ("scroll down", ["scroll down", "page down"], .keys(121, [])),
        ("scroll up", ["scroll up", "page up"], .keys(116, [])),
        ("go to top", ["go to top", "scroll to top", "top of the page"], .keys(126, cmd)),
        ("go to bottom", ["go to bottom", "scroll to bottom", "bottom of the page"], .keys(125, cmd)),
        ("switch app", ["switch app", "switch apps", "previous app"], .keys(48, cmd)),
        ("spotlight", ["spotlight", "open spotlight"], .keys(49, cmd)),
        ("mission control", ["mission control", "show all windows"], .keys(126, ctrl)),
        ("screenshot", ["screenshot", "take a screenshot", "screen shot"], .keys(20, [cmd, shift])),
        ("lock screen", ["lock screen", "lock the screen", "lock my mac", "lock the mac"], .keys(12, [cmd, ctrl])),
        ("volume up", ["volume up", "louder", "turn it up", "increase volume"],
         .script("set volume output volume ((output volume of (get volume settings)) + 15)")),
        ("volume down", ["volume down", "quieter", "turn it down", "decrease volume", "lower volume"],
         .script("set volume output volume ((output volume of (get volume settings)) - 15)")),
        ("mute", ["mute", "unmute", "toggle mute"], .script("set volume output muted (not (output muted of (get volume settings)))")),
    ]

    /// Longest matching phrase wins ("close this tab" beats "close this"). Anything about the notch is not ours.
    static func matchControl(_ n: String) -> String? {
        guard !n.split(separator: " ").contains(where: { ["notch", "natch"].contains($0) }) else { return nil }
        let padded = " \(n) "
        // One-word phrases ("find", "save") only count as the whole command, so "find the deadline" stays a file search.
        let polite: Set = ["please", "can", "you", "could", "now", "just", "it", "this", "that"]
        let core = n.split(separator: " ").map(String.init).filter { !polite.contains($0) }.joined(separator: " ")
        return controls.flatMap { c in c.phrases.map { (c.name, $0) } }
            .filter { $0.1.contains(" ") ? padded.contains(" \($0.1) ") : (core == $0.1 || n == $0.1) }
            .max(by: { $0.1.count < $1.1.count })?.0
    }

    /// "quit safari" / "close slack" / "hide notes" -> that running app.
    static func namedAppControl(_ n: String) -> (verb: String, app: NSRunningApplication)? {
        let running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        let byName = Dictionary(running.compactMap { a in a.localizedName.map { (Words.normalize($0), a) } }, uniquingKeysWith: { a, _ in a })
        for verb in ["quit", "close", "hide", "kill", "exit"] {
            if let rest = rest(after: [verb], in: n), let name = matchApp(rest, in: byName.keys) {
                return (verb == "hide" ? "hide" : "quit", byName[name]!)
            }
        }
        return nil
    }

    // The app the user is working in (not us, even if a click on the notch activated us).
    static var lastApp: NSRunningApplication?

    static func trackFrontmost() {
        let me = NSRunningApplication.current.processIdentifier
        if let f = NSWorkspace.shared.frontmostApplication, f.processIdentifier != me { lastApp = f }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { note in
            if let a = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication, a.processIdentifier != me {
                lastApp = a
            }
        }
    }

    /// Returns false when Accessibility permission is missing.
    static func perform(_ name: String) async -> Bool {
        guard let action = controls.first(where: { $0.name == name })?.action else { return true }
        switch action {
        case let .script(src):
            NSAppleScript(source: src)?.executeAndReturnError(nil)
        case .quit:
            lastApp?.terminate()
        case let .keys(code, flags):
            guard trusted()
            else { return false }
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == NSRunningApplication.current.processIdentifier {
                lastApp?.activate()
                try? await Task.sleep(for: .milliseconds(250))
            }
            key(code, flags)
        }
        return true
    }

    static func checkControls() {
        assert(matchControl("full screen") == "full screen")
        assert(matchControl("make this full screen please") == "full screen")
        assert(matchControl("close this tab") == "close tab")
        assert(matchControl("close this") == "close window")
        assert(matchControl("close the notch") == nil)
        assert(matchControl("quit") == "quit")
        assert(matchControl("volume up") == "volume up")
        assert(matchControl("turn it down") == "volume down")
        assert(matchControl("what kind of file is this") == nil)
        assert(matchControl("read the file") == nil)
        assert(matchControl("find the deadline in the file") == nil)
        assert(matchControl("can you save this please") == "save")
        assert(matchControl("print") == "print" && matchControl("copy that") == "copy")
        assert(matchControl("go back") == "go back" && matchControl("take me back to the start") == nil)
        print("Controls ok")
    }
}

// MARK: - any key, any button

extension Actions {
    static let keyCodes: [String: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13,
        "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "9": 25, "7": 26,
        "8": 28, "0": 29, "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46,
        "enter": 36, "return": 36, "tab": 48, "space": 49, "spacebar": 49, "delete": 51, "backspace": 51,
        "escape": 53, "esc": 53, "left": 123, "right": 124, "down": 125, "up": 126, "home": 115, "end": 119,
        "pageup": 116, "pagedown": 121, "forwarddelete": 117, "comma": 43, "period": 47, "dot": 47, "slash": 44,
        "minus": 27, "equals": 24, "plus": 24,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98, "f8": 100, "f9": 101,
        "f10": 109, "f11": 103, "f12": 111,
    ]
    private static let spokenDigits = ["zero": "0", "one": "1", "two": "2", "three": "3", "four": "4", "five": "5",
                                       "six": "6", "seven": "7", "eight": "8", "nine": "9"]
    private static let modifiers: [String: CGEventFlags] = [
        "command": .maskCommand, "cmd": .maskCommand, "commander": .maskCommand, "shift": .maskShift,
        "option": .maskAlternate, "alt": .maskAlternate, "control": .maskControl, "ctrl": .maskControl,
    ]

    /// "command shift t" -> (17, cmd+shift). Nil unless every word is a modifier, a key, or filler.
    static func parseKeys(_ n: String) -> (CGKeyCode, CGEventFlags)? {
        var words = n.split(separator: " ").map(String.init)
            .filter { !["the", "key", "keys", "button", "arrow", "please", "plus", "and", "then"].contains($0) }
        // two-word keys
        for (two, one) in [("page up", "pageup"), ("page down", "pagedown"), ("forward delete", "forwarddelete"),
                           ("space bar", "space")] {
            words = words.joined(separator: " ").replacingOccurrences(of: two, with: one).split(separator: " ").map(String.init)
        }
        var flags = CGEventFlags()
        var code: CGKeyCode?
        for w in words {
            if let m = modifiers[w] { flags.insert(m); continue }
            let k = spokenDigits[w] ?? w
            guard code == nil, let c = keyCodes[k] else { return nil }
            code = c
        }
        return code.map { ($0, flags) }
    }

    /// The app to act on: the frontmost one, unless that's us.
    static var targetApp: NSRunningApplication? {
        let f = NSWorkspace.shared.frontmostApplication
        return f?.processIdentifier == NSRunningApplication.current.processIdentifier ? lastApp : f
    }

    static func press(_ code: CGKeyCode, _ flags: CGEventFlags) async -> Bool {
        guard trusted()
        else { return false }
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == NSRunningApplication.current.processIdentifier {
            lastApp?.activate()
            try? await Task.sleep(for: .milliseconds(250))
        }
        key(code, flags)
        return true
    }

    private static var askedForAccess = false

    /// Accessibility check that shows the system prompt at most once per launch.
    static func trusted() -> Bool {
        if AXIsProcessTrusted() { return true }
        if !askedForAccess {
            askedForAccess = true
            AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
        }
        return false
    }

    static let pressableRoles: Set = ["AXButton", "AXMenuItem", "AXMenuBarItem", "AXLink", "AXCheckBox", "AXRadioButton",
                                      "AXPopUpButton", "AXTab", "AXCell", "AXMenuButton", "AXDisclosureTriangle"]
    static let textRoles: Set = ["AXTextField", "AXTextArea", "AXSearchField", "AXComboBox"]

    private static func attr(_ e: AXUIElement, _ a: String) -> CFTypeRef? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(e, a as CFString, &v) == .success ? v : nil
    }

    /// Breadth-first walk of an accessibility tree. ponytail: capped at 4000 nodes; no screen vision.
    private static func walk(_ root: AXUIElement, _ visit: (AXUIElement, String) -> Bool) {
        var queue = [root], seen = 0
        while !queue.isEmpty, seen < 4000 {
            let e = queue.removeFirst()
            seen += 1
            if visit(e, attr(e, "AXRole") as? String ?? "") { return }
            for a in ["AXChildren", "AXMenuBar"] {
                guard let kids = attr(e, a) else { continue }
                if CFGetTypeID(kids) == CFArrayGetTypeID() { queue += (kids as! [AXUIElement]) }
                else if CFGetTypeID(kids) == AXUIElementGetTypeID() { queue.append(kids as! AXUIElement) }
            }
        }
    }

    private static func targetRoot() -> AXUIElement? {
        guard let pid = targetApp?.processIdentifier else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)  // Electron apps
        return app
    }

    /// Presses a button / menu item / link, or focuses a text field, by its element.
    private static func activate(_ e: AXUIElement, _ role: String) -> Bool {
        if textRoles.contains(role) {
            return AXUIElementSetAttributeValue(e, "AXFocused" as CFString, kCFBooleanTrue) == .success
        }
        return AXUIElementPerformAction(e, kAXPressAction as CFString) == .success
    }

    /// Finds a button / menu item / link / text field by its visible name in the target app and presses (or focuses) it.
    static func click(_ name: String) -> Bool {
        guard trusted(), let app = targetRoot() else { return false }
        let want = Words.normalize(name).split(separator: " ")
            .filter { !["the", "button", "field", "box", "link", "menu", "on"].contains($0) }.joined(separator: " ")
        guard !want.isEmpty else { return false }
        var exact: (AXUIElement, String)?, partial: (AXUIElement, String)?
        walk(app) { e, role in
            guard pressableRoles.contains(role) || textRoles.contains(role) else { return false }
            let names = ["AXTitle", "AXDescription", "AXHelp", "AXPlaceholderValue"]
                .compactMap { attr(e, $0) as? String }.map(Words.normalize)
                + (textRoles.contains(role) ? [] : [(attr(e, "AXValue") as? String).map(Words.normalize) ?? ""])
            if names.contains(want) { exact = (e, role); return true }
            if partial == nil, names.contains(where: { !$0.isEmpty && $0.contains(want) }) { partial = (e, role) }
            return false
        }
        guard let (e, role) = exact ?? partial else { return false }
        return activate(e, role)
    }

    /// "click the second button" in any app: n-th element of a kind in the front window, in reading order.
    static func clickNth(_ n: Int, _ kind: String) -> Bool {
        guard trusted(), let app = targetRoot() else { return false }
        let window = attr(app, "AXFocusedWindow").map { $0 as! AXUIElement } ?? app
        let roles: Set<String> = switch kind {
        case "link", "result", "article", "story", "post", "video": ["AXLink"]
        case "button": ["AXButton"]
        case "field", "box": textRoles
        default: pressableRoles.union(textRoles)
        }
        var found: [(AXUIElement, String, CGPoint)] = []
        walk(window) { e, role in
            if roles.contains(role), let v = attr(e, "AXPosition") {
                var p = CGPoint.zero
                AXValueGetValue(v as! AXValue, .cgPoint, &p)
                found.append((e, role, p))
            }
            return false
        }
        found.sort { abs($0.2.y - $1.2.y) > 4 ? $0.2.y < $1.2.y : $0.2.x < $1.2.x }  // top-to-bottom, left-to-right
        guard !found.isEmpty else { return false }
        let pick = n < 0 ? found[found.count - 1] : (n <= found.count ? found[n - 1] : nil)
        guard let (e, role, _) = pick else { return false }
        return activate(e, role)
    }

    static func checkKeys() {
        assert(parseKeys("enter")! == (36, []))
        assert(parseKeys("command shift t")! == (17, [.maskCommand, .maskShift]))
        assert(parseKeys("the down arrow")! == (125, []))
        assert(parseKeys("command one")! == (18, .maskCommand))
        assert(parseKeys("page down")! == (121, []))
        assert(parseKeys("send") == nil)
        assert(parseKeys("the submit button") == nil)
        assert(parseKeys("command") == nil)
        print("Keys ok")
    }
}
