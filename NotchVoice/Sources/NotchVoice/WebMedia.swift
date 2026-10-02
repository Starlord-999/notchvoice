import AppKit

/// Now Playing from browser tabs (YouTube Music, YouTube, Spotify Web, SoundCloud) via navigator.mediaSession.
/// Needs "Allow JavaScript from Apple Events" in the browser's Developer/Develop menu.
extension NowPlaying {
    static let browsers = ["com.google.Chrome": "Google Chrome", "com.brave.Browser": "Brave Browser",
                           "com.microsoft.edgemac": "Microsoft Edge", "company.thebrowser.Browser": "Arc", "com.apple.Safari": "Safari"]
    private static let hosts = ["music.youtube.com", "youtube.com", "open.spotify.com", "soundcloud.com"]
    private static let sep = "~|~"
    private static let readJS = """
    (function(){var m=navigator.mediaSession.metadata;var v=document.querySelector('video,audio');if(!m||!m.title)return '';\
    var a=m.artwork&&m.artwork.length?m.artwork[m.artwork.length-1].src:'';\
    return [m.title,m.artist,(v&&!v.paused)?'true':'false',a].join('~|~');})()
    """

    /// Runs `js` in the first matching media tab of `app`; returns its string result.
    func tabScript(_ app: String, _ js: String) -> String? {
        let cond = Self.hosts.map { "URL of t contains \"\($0)\"" }.joined(separator: " or ")
        let esc = js.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let run = app == "Safari" ? "do JavaScript \"\(esc)\" in t" : "execute t javascript \"\(esc)\""
        return script("""
        tell application "\(app)"
          repeat with w in windows
            repeat with t in tabs of w
              if \(cond) then
                try
                  set r to \(run)
                  if r is not missing value and r is not "" then return r
                end try
              end if
            end repeat
          end repeat
        end tell
        return ""
        """)?.stringValue
    }

    /// (app, [title, artist, "true"/"false" playing, artwork url])
    func webPoll(_ running: Set<String>) -> (String, [String])? {
        var first: (String, [String])?
        for (id, app) in Self.browsers where running.contains(id) {
            guard let r = tabScript(app, Self.readJS), !r.isEmpty else { continue }
            let v = r.components(separatedBy: Self.sep)
            guard v.count >= 4 else { continue }
            if v[2] == "true" { return (app, v) }
            first = first ?? (app, v)
        }
        return first
    }

    func webControl(_ cmd: String) {
        let click = { (sel: String) in "var b=document.querySelector('\(sel)');if(b)b.click();''" }
        let js = cmd == "playpause" ? "var v=document.querySelector('video,audio');if(v){v.paused?v.play():v.pause()};''"
            : cmd == "next track" ? click("ytmusic-player-bar .next-button, .ytp-next-button, [data-testid=control-button-skip-forward]")
            : click("ytmusic-player-bar .previous-button, [data-testid=control-button-skip-back]")
        _ = tabScript(player, js)
    }
}
