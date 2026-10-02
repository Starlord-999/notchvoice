import SwiftUI

/// Music / Spotify through AppleScript (MediaRemote is closed to third-party apps since macOS 15.4).
@MainActor final class NowPlaying: ObservableObject {
    static let shared = NowPlaying()
    @Published var title = ""
    @Published var artist = ""
    @Published var playing = false
    @Published var player = ""
    @Published var art: NSImage?
    private var timer: Timer?
    private var artKey = ""
    private var web = false

    private static let players = [("Spotify", "com.spotify.client"), ("Music", "com.apple.Music")]

    func start() {
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in Task { @MainActor in self?.poll() } }
    }

    func stop() { timer?.invalidate(); timer = nil }

    func script(_ src: String) -> NSAppleEventDescriptor? { NSAppleScript(source: src)?.executeAndReturnError(nil) }

    func poll() {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        var found: (String, [String])?
        for (name, id) in Self.players where running.contains(id) {
            guard let d = script("tell application \"\(name)\" to if player state is not stopped then return {name of current track, artist of current track, (player state is playing) as text}"),
                  d.numberOfItems == 3 else { continue }
            let v = (1 ... 3).map { d.atIndex($0)?.stringValue ?? "" }
            if found == nil || v[2] == "true" { found = (name, v) }
        }
        if found?.1[2] != "true", let w = webPoll(running), w.1[2] == "true" || found == nil { found = w }
        guard let (name, v) = found else { title = ""; artist = ""; playing = false; player = ""; art = nil; web = false; return }
        web = Self.browsers.values.contains(name)
        player = name; title = v[0]; artist = v[1]; playing = v[2] == "true"
        let key = name + v[0] + v[1]
        guard key != artKey else { return }
        artKey = key
        art = nil
        if web, v.count > 3, let url = URL(string: v[3]) {
            Task { if let (data, _) = try? await URLSession.shared.data(from: url), self.artKey == key { self.art = NSImage(data: data) } }
        } else if name == "Spotify", let u = script("tell application \"Spotify\" to artwork url of current track")?.stringValue, let url = URL(string: u) {
            Task { if let (data, _) = try? await URLSession.shared.data(from: url), self.artKey == key { self.art = NSImage(data: data) } }
        } else if name == "Music", let data = script("tell application \"Music\" to data of artwork 1 of current track")?.data {
            art = NSImage(data: data)
        }
    }

    func control(_ cmd: String) {  // "playpause" | "next track" | "previous track"
        poll()
        guard !player.isEmpty else { return }
        if web { webControl(cmd); poll(); return }
        _ = script("tell application \"\(player)\" to \(cmd)")
        poll()
    }
}

struct NowPlayingView: View {
    @ObservedObject var m = NowPlaying.shared

    var body: some View {
        Group {
            if m.title.isEmpty {
                Text("Nothing playing in Music, Spotify or a YouTube Music tab.\nBrowsers: allow JavaScript from Apple Events (Developer menu).").multilineTextAlignment(.center).font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 14) {
                    Group {
                        if let a = m.art { Image(nsImage: a).resizable() } else { Color.white.opacity(0.1) }
                    }
                    .frame(width: 84, height: 84).clipShape(RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(m.title).font(.system(.headline, design: .rounded)).lineLimit(1)
                        Text(m.artist).font(.system(.subheadline, design: .rounded)).foregroundStyle(.secondary).lineLimit(1)
                        HStack(spacing: 18) {
                            btn("backward.fill", "previous track")
                            btn(m.playing ? "pause.fill" : "play.fill", "playpause")
                            btn("forward.fill", "next track")
                            Spacer()
                            wave
                        }
                    }
                }
            }
        }
        .onAppear { m.start() }
        .onDisappear { m.stop() }
    }

    func btn(_ icon: String, _ cmd: String) -> some View {
        Button { m.control(cmd) } label: { Image(systemName: icon).font(.title3) }.buttonStyle(.plain)
    }

    // Cosmetic: animates while playing, not driven by the actual audio.
    var wave: some View {
        TimelineView(.animation(minimumInterval: 0.08, paused: !m.playing)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                ForEach(0 ..< 6, id: \.self) { i in
                    Capsule().fill(.green).frame(width: 3, height: m.playing ? 6 + 16 * abs(sin(t * 4 + Double(i) * 0.9)) : 4)
                }
            }
            .frame(height: 24)
        }
    }
}
