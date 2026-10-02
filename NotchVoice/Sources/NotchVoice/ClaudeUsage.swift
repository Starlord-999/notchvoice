import SwiftUI

/// Token usage read from Claude Code's local transcripts (~/.claude/projects/**/*.jsonl). Nothing leaves the Mac.
/// Plan limits aren't stored locally, so this shows raw token counts, not "% of limit".
@MainActor final class ClaudeUsage: ObservableObject {
    static let shared = ClaudeUsage()
    struct Entry { let date: Date; let input: Int; let output: Int; let cacheWrite: Int; let cacheRead: Int; let model: String }
    struct Total { var input = 0, output = 0, cacheWrite = 0, cacheRead = 0
        var fresh: Int { input + output + cacheWrite }
        mutating func add(_ e: Entry) { input += e.input; output += e.output; cacheWrite += e.cacheWrite; cacheRead += e.cacheRead }
    }

    @Published var window = Total()   // last 5 h
    @Published var today = Total()
    @Published var week = Total()
    @Published var days: [Int] = Array(repeating: 0, count: 7)  // oldest -> today
    @Published var models: [(String, Int)] = []
    private var timer: Timer?
    private var cache: [String: (Date, [String: Entry])] = [:]  // path -> (mtime, entries by message id)

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in Task { @MainActor in self?.refresh() } }
    }

    func stop() { timer?.invalidate(); timer = nil }

    private func refresh() {
        let snapshot = cache
        Task.detached(priority: .utility) {
            let (entries, newCache) = Self.scan(snapshot)
            await MainActor.run { self.cache = newCache; self.apply(entries) }
        }
    }

    private func apply(_ all: [Entry]) {
        let now = Date(), cal = Calendar.current
        var w = Total(), t = Total(), wk = Total()
        var d = Array(repeating: 0, count: 7), m: [String: Int] = [:]
        for e in all {
            let age = cal.dateComponents([.day], from: cal.startOfDay(for: e.date), to: cal.startOfDay(for: now)).day ?? 99
            guard age < 7 else { continue }
            wk.add(e); d[6 - age] += e.input + e.output + e.cacheWrite
            if age == 0 { t.add(e) }
            if now.timeIntervalSince(e.date) < 5 * 3600 { w.add(e) }
            m[e.model, default: 0] += e.input + e.output + e.cacheWrite
        }
        window = w; today = t; week = wk; days = d
        models = m.sorted { $0.value > $1.value }.prefix(3).map { ($0.key, $0.value) }
    }

    nonisolated private static func scan(_ cache: [String: (Date, [String: Entry])]) -> ([Entry], [String: (Date, [String: Entry])]) {
        let fm = FileManager.default
        let root = fm.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
        let cutoff = Date().addingTimeInterval(-8 * 86400)
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var out: [String: (Date, [String: Entry])] = [:]
        guard let it = fm.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else { return ([], out) }
        for case let url as URL in it where url.pathExtension == "jsonl" {
            let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            guard mtime > cutoff else { continue }
            if let c = cache[url.path], c.0 == mtime { out[url.path] = c; continue }
            var found: [String: Entry] = [:]
            guard let data = try? Data(contentsOf: url) else { continue }
            for line in data.split(separator: UInt8(ascii: "\n")) {
                guard line.range(of: Data("\"usage\"".utf8)) != nil,
                      let j = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      j["type"] as? String == "assistant",
                      let msg = j["message"] as? [String: Any], let u = msg["usage"] as? [String: Any],
                      let ts = j["timestamp"] as? String, let date = iso.date(from: ts) else { continue }
                let id = (msg["id"] as? String) ?? UUID().uuidString
                found[id] = Entry(date: date, input: u["input_tokens"] as? Int ?? 0, output: u["output_tokens"] as? Int ?? 0,
                                  cacheWrite: u["cache_creation_input_tokens"] as? Int ?? 0, cacheRead: u["cache_read_input_tokens"] as? Int ?? 0,
                                  model: msg["model"] as? String ?? "?")  // streamed messages repeat; last line wins
            }
            out[url.path] = (mtime, found)
        }
        // a message id can appear in several files (resumed sessions): count it once
        var byId: [String: Entry] = [:]
        for (_, v) in out.values.enumerated() { for (k, e) in v.1 { byId[k] = e } }
        return (Array(byId.values), out)
    }
}

struct ClaudeUsageView: View {
    @ObservedObject var m = ClaudeUsage.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                tile("Last 5 h", m.window)
                tile("Today", m.today)
                tile("7 days", m.week)
                bars
            }
            Text(m.models.map { "\($0.0.replacingOccurrences(of: "claude-", with: "")) \(fmt($0.1))" }.joined(separator: "  ·  "))
                .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
        }
        .onAppear { m.start() }
        .onDisappear { m.stop() }
    }

    func tile(_ name: String, _ t: ClaudeUsage.Total) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(name).font(.system(size: 10, design: .rounded)).foregroundStyle(.secondary)
            Text(fmt(t.fresh)).font(.system(.title2, design: .rounded).weight(.semibold))
            Text("in \(fmt(t.input)) · out \(fmt(t.output))").font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
            Text("cache read \(fmt(t.cacheRead))").font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary)
        }
        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    var bars: some View {
        let top = Double(max(m.days.max() ?? 1, 1))
        return HStack(alignment: .bottom, spacing: 3) {
            ForEach(m.days.indices, id: \.self) { i in
                Capsule().fill(i == 6 ? Color.orange : .white.opacity(0.35)).frame(width: 6, height: max(3, 56 * Double(m.days[i]) / top))
            }
        }.frame(width: 70, height: 60, alignment: .bottom)
    }

    func fmt(_ n: Int) -> String {
        n >= 1_000_000 ? String(format: "%.1fM", Double(n) / 1e6) : n >= 1000 ? String(format: "%.1fk", Double(n) / 1e3) : "\(n)"
    }
}
