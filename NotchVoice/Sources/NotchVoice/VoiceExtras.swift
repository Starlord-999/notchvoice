import AppKit

/// Voice shortcuts for the widgets. Returns a status line if the command was handled.
@MainActor enum VoiceExtras {
    private static let nums = ["one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
                               "fifteen": 15, "twenty": 20, "thirty": 30, "forty five": 45, "sixty": 60, "an": 1, "a": 1]

    static func handle(_ c: String) -> String? {
        let tabs: [(String, Tab)] = [("apps", .apps), ("music", .music), ("calendar", .today), ("today", .today), ("timer", .today),
                                     ("clipboard", .clipboard), ("system", .system), ("stats", .system), ("assistant", .assistant)]
        if let rest = Actions.rest(after: ["show", "show me", "switch to"], in: c), let (_, t) = tabs.first(where: { rest.hasPrefix($0.0) }) {
            TabState.shared.tab = t
            if Assistant.shared.vm?.status != .opened { Assistant.shared.vm?.notchOpen(.voice) }
            return "Showing \(t.rawValue)"
        }
        switch c {
        case "play music", "resume music", "pause music", "play pause": NowPlaying.shared.control("playpause"); return "Play/pause"
        case "next song", "next track", "skip song", "skip track": NowPlaying.shared.control("next track"); return "Next"
        case "previous song", "previous track", "last song": NowPlaying.shared.control("previous track"); return "Previous"
        case "start pomodoro", "pomodoro", "focus timer": Today.shared.addTimer(1500, "Focus"); return "Focus 25 min"
        case "cancel timers", "cancel timer", "clear timers": Today.shared.timers = []; return "Timers cleared"
        default: break
        }
        if c.contains("timer"), let m = c.range(of: #"(\d+|[a-z]+( five)?) (second|minute|hour)s?"#, options: .regularExpression) {
            let w = c[m].split(separator: " ").map(String.init)
            let unit = w.last!.hasPrefix("hour") ? 3600.0 : w.last!.hasPrefix("minute") ? 60 : 1
            let n = Double(w.dropLast().joined(separator: " ")) ?? Double(nums[w.dropLast().joined(separator: " ")] ?? 0)
            guard n > 0 else { return nil }
            Today.shared.addTimer(n * unit, "\(Int(n)) \(w.last!)")
            return "Timer set"
        }
        if let q = Actions.rest(after: ["paste from clipboard", "paste clipboard"], in: c) ?? c.range(of: " from clipboard").map({ String(c[..<$0.lowerBound]) }).flatMap({ Actions.rest(after: ["paste"], in: $0) }) {
            guard let s = Clips.shared.find(q) else { return "Nothing in clipboard matching \(q)" }
            Clips.shared.paste(s)
            return "Pasted"
        }
        return nil
    }
}
