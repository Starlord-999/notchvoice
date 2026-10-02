import EventKit
import SwiftUI

/// Timers / pomodoro, next calendar event (+ join + 5-min alert), and a feed of notifications.
@MainActor final class Today: ObservableObject {
    static let shared = Today()
    struct Timer: Identifiable { let id = UUID(); let label: String; let end: Date; let total: TimeInterval }
    struct Note: Identifiable { let id = UUID(); let title: String; let body: String; let at = Date() }

    @Published var timers: [Timer] = []
    @Published var event: EKEvent?
    @Published var feed: [Note] = []
    private let store = EKEventStore()
    private var alerted = Set<String>()
    private var seenDownloads = Set<String>()

    func start() {
        Task { _ = try? await store.requestFullAccessToEvents() }
        seenDownloads = Set(downloads())
        Foundation.Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in Task { @MainActor in self?.tick() } }
    }

    private var ticks = 0
    private func tick() {
        ticks += 1
        for t in timers where t.end <= Date() {
            notify("Timer done", t.label)
            NSSound(named: "Glass")?.play()
        }
        timers.removeAll { $0.end <= Date() }
        if ticks % 20 == 0 { refreshEvent() }
        if ticks % 3 == 0 { checkDownloads() }
    }

    func addTimer(_ seconds: TimeInterval, _ label: String) {
        timers.append(.init(label: label, end: Date().addingTimeInterval(seconds), total: seconds))
    }

    func notify(_ title: String, _ body: String = "") {
        feed.insert(.init(title: title, body: body), at: 0)
        if feed.count > 20 { feed.removeLast() }
        TabState.shared.tab = .today
        if Assistant.shared.vm?.status != .opened { Assistant.shared.vm?.notchOpen(.voice) }
    }

    private func refreshEvent() {
        let now = Date()
        let ev = store.events(matching: store.predicateForEvents(withStart: now, end: now.addingTimeInterval(86400), calendars: nil))
            .filter { !$0.isAllDay && $0.endDate > now }.sorted { $0.startDate < $1.startDate }.first
        event = ev
        if let ev, let id = ev.eventIdentifier, ev.startDate.timeIntervalSinceNow < 300, ev.startDate.timeIntervalSinceNow > -60, alerted.insert(id).inserted {
            notify("\(ev.title ?? "Meeting") starts soon", ev.startDate.formatted(date: .omitted, time: .shortened))
        }
    }

    static func joinURL(_ e: EKEvent) -> URL? {
        let text = [e.url?.absoluteString, e.location, e.notes].compactMap { $0 }.joined(separator: " ")
        let m = text.range(of: #"https://[^\s<>"]*(zoom\.us|meet\.google\.com|teams\.microsoft\.com|teams\.live\.com|webex\.com)[^\s<>"]*"#, options: .regularExpression)
        return m.flatMap { URL(string: String(text[$0])) }
    }

    private func downloads() -> [String] {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        return ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).filter {
            !$0.hasPrefix(".") && ![".crdownload", ".download", ".part", ".tmp"].contains { [name = $0] s in name.hasSuffix(s) }
        }
    }

    private func checkDownloads() {
        for f in downloads() where seenDownloads.insert(f).inserted { notify("Download finished", f) }
    }

    /// `notchvoice://notify?title=…&body=…` — wire to Claude Code hooks, build scripts, etc.
    func handle(_ url: URL) {
        let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        notify(q.first { $0.name == "title" }?.value ?? "Notification", q.first { $0.name == "body" }?.value ?? "")
    }
}

struct TodayView: View {
    @ObservedObject var m = Today.shared

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                if let e = m.event {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(e.title ?? "Event").font(.system(.subheadline, design: .rounded).weight(.semibold)).lineLimit(1)
                        TimelineView(.periodic(from: .now, by: 1)) { _ in
                            let s = e.startDate.timeIntervalSinceNow
                            Text(s > 0 ? "in \(fmt(s))" : "now").font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                        }
                        if let u = Today.joinURL(e) { Button("Join") { NSWorkspace.shared.open(u) }.buttonStyle(.borderedProminent).controlSize(.small) }
                    }
                } else {
                    Text("No events in the next 24 h").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(m.timers) { t in
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        HStack {
                            Image(systemName: "timer"); Text(t.label).lineLimit(1); Spacer()
                            Text(fmt(t.end.timeIntervalSinceNow)).font(.system(.caption, design: .monospaced))
                            Button { m.timers.removeAll { $0.id == t.id } } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain)
                        }.font(.caption)
                    }
                }
                HStack {
                    Button("Focus 25m") { m.addTimer(1500, "Focus") }
                    Button("5m") { m.addTimer(300, "Timer") }
                }.controlSize(.small)
            }
            .frame(width: 230, alignment: .leading)
            ScrollView {
                VStack(alignment: .leading, spacing: 5) {
                    if m.feed.isEmpty { Text("No notifications").font(.caption).foregroundStyle(.secondary) }
                    ForEach(m.feed) { n in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(n.title).font(.system(.caption, design: .rounded).weight(.semibold))
                            if !n.body.isEmpty { Text(n.body).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    func fmt(_ s: TimeInterval) -> String {
        let s = max(Int(s), 0)
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }
}
