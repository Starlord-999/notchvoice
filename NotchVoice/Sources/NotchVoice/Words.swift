import Foundation

/// Cheap string rules that run before Laya. Laya is weak on one-word commands, so these win.
enum Words {
    // Whisper spellings of "Hey Notch" seen in testing (+ the prompt keeps most as "Notch").
    static let wake = ["hey notch", "hey natch", "hey nach", "hey knotch", "hey not", "hi notch",
                       "okay notch", "ok notch", "notch", "natch"]
    static let stop: Set = ["stop", "quiet", "shut up", "enough", "pause", "silence", "be quiet",
                            "stop it", "stop talking", "stop reading", "okay stop", "ok stop", "hush"]
    static let yes: Set = ["yes", "yeah", "yep", "yup", "sure", "ok", "okay", "do it", "please", "go ahead", "correct"]
    static let no: Set = ["no", "nope", "nah", "cancel", "never mind", "don't", "no thanks"]

    static let endPhrases: Set = ["bye", "goodbye", "bye bye", "that's all", "thats all", "that's it for now",
                                  "stop listening", "go to sleep", "close the notch", "close notch", "dismiss", "go away"]
    static let startDictation: Set = ["type", "write", "dictate", "start typing", "start writing", "start dictation",
                                      "take dictation", "dictation", "type for me", "write for me"]
    static let stopDictation: Set = ["stop typing", "stop writing", "stop dictation", "stop dictating", "done",
                                     "done typing", "i'm done", "that's it", "finish", "end dictation", "stop"]

    static func endsSession(_ n: String) -> Bool { endPhrases.contains(n) }
    static func isSend(_ n: String) -> Bool { ["send", "send it", "send this", "send message", "send the message", "hit send", "press send", "click send"].contains(n) }

    static let ordinals = ["first": 1, "1st": 1, "second": 2, "2nd": 2, "third": 3, "3rd": 3, "fourth": 4, "4th": 4,
                           "fifth": 5, "5th": 5, "sixth": 6, "seventh": 7, "eighth": 8, "ninth": 9, "tenth": 10, "last": -1]
    static let ordinalKinds: Set = ["link", "result", "video", "button", "one", "article", "item", "option", "field",
                                    "box", "story", "post", "tab"]

    /// "open the second result" -> (2, "result"). Needs a kind or an action verb, so "the first time" doesn't count.
    static func ordinal(_ n: String) -> (Int, String)? {
        let w = n.split(separator: " ").map(String.init)
        guard let i = w.firstIndex(where: { ordinals[$0] != nil }) else { return nil }
        let kind = w[(i + 1)...].first(where: { ordinalKinds.contains($0) }) ?? ""
        let verbs: Set = ["open", "visit", "click", "play", "tap", "select", "choose", "go"]
        guard !kind.isEmpty || w[..<i].contains(where: { verbs.contains($0) }) else { return nil }
        return (ordinals[w[i]]!, kind)
    }

    /// "Hey, Notch! Open up." -> "hey notch open up"
    static func normalize(_ s: String) -> String {
        s.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.union(.whitespaces).union(CharacterSet(charactersIn: "'")).inverted)
            .joined(separator: " ")
            .split(separator: " ").joined(separator: " ")
    }

    /// Returns the command after the wake phrase, or nil when there is no wake phrase.
    /// "hey notch" may appear mid-transcript (background talk before it); bare "notch" only counts at the start.
    static func afterWake(_ n: String) -> String? {
        let padded = " " + n + " "
        for w in wake {
            if n == w || n.hasPrefix(w + " ") {
                return String(n.dropFirst(w.count)).trimmingCharacters(in: .whitespaces)
            }
            if w.contains(" "), let r = padded.range(of: " " + w + " ", options: .backwards) {
                return String(padded[r.upperBound...]).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    static func isStop(_ n: String) -> Bool {
        stop.contains(n) || stop.contains(afterWake(n) ?? "")
    }

    /// true / false when it's an obvious yes/no, nil when Laya should judge.
    static func yesNo(_ n: String) -> Bool? {
        if yes.contains(n) || yes.contains(where: { n.hasPrefix($0 + " ") }) { return true }
        if no.contains(n) || no.contains(where: { n.hasPrefix($0 + " ") }) { return false }
        return nil
    }

    /// Whisper's non-speech outputs.
    static func isJunk(_ raw: String) -> Bool {
        let n = normalize(raw)
        return n.isEmpty || raw.contains("[") || raw.hasPrefix("(") || ["you", "thank you", "bye"].contains(n)
    }

    static func check() {
        assert(normalize("Hey, Notch! Open up.") == "hey notch open up")
        assert(afterWake("hey notch open up") == "open up")
        assert(afterWake("hey natch") == "")
        assert(afterWake("notches are cool") == nil)
        assert(afterWake("so i told him") == nil)
        assert(afterWake("meanwhile at the camp hey notch close the notch") == "close the notch")
        assert(afterWake("the notch on my laptop") == nil)
        assert(isStop("stop") && isStop("hey notch stop") && isStop("shut up"))
        assert(!isStop("stop the music later please"))
        assert(yesNo("yeah do it") == true && yesNo("no thanks") == false && yesNo("read it") == nil)
        assert(isJunk("[BLANK_AUDIO]") && isJunk("(music)") && isJunk(" Thank you.") && !isJunk("Open up"))
        assert(endsSession("bye") && endsSession("close the notch") && !endsSession("close the tab"))
        assert(isSend("send it") && !isSend("send an email to sam"))
        assert(stopDictation.contains("stop typing"))
        assert(ordinal("visit the first link")! == (1, "link"))
        assert(ordinal("open the third result")! == (3, "result"))
        assert(ordinal("play the last video")! == (-1, "video"))
        assert(ordinal("click the second one")! == (2, "one"))
        assert(ordinal("the first time i went there") == nil)
        assert(ordinal("go to the 2nd tab")! == (2, "tab"))
        print("Words ok")
    }
}
