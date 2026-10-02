import SwiftUI

enum Tab: String, CaseIterable {
    case assistant, apps, music, today, clipboard, system
    var icon: String {
        switch self {
        case .assistant: "waveform"
        case .apps: "square.grid.2x2"
        case .music: "music.note"
        case .today: "calendar.badge.clock"
        case .clipboard: "doc.on.clipboard"
        case .system: "gauge.with.dots.needle.33percent"
        }
    }
}

@MainActor final class TabState: ObservableObject {
    static let shared = TabState()
    @Published var tab: Tab = .assistant
}

/// Opened-notch content: tab body on top, tab bar at the bottom (the hardware notch hides the top centre).
struct Dashboard: View {
    @StateObject var vm: NotchViewModel
    @ObservedObject var assistant = Assistant.shared
    @ObservedObject var state = TabState.shared

    var body: some View {
        VStack(spacing: 8) {
            Group {
                switch state.tab {
                case .assistant: AssistantView(vm: vm, assistant: assistant)
                case .apps: AppsView()
                case .music: NowPlayingView()
                case .today: TodayView()
                case .clipboard: ClipboardView()
                case .system: GlanceView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            HStack(spacing: 6) {
                ForEach(Tab.allCases, id: \.self) { t in
                    Button { state.tab = t } label: {
                        Image(systemName: t.icon).frame(width: 34, height: 22)
                            .background(state.tab == t ? Color.white.opacity(0.18) : .clear, in: Capsule())
                    }.buttonStyle(.plain)
                }
            }
        }
        .onChange(of: assistant.hearing) { if $0 { state.tab = .assistant } }
    }
}
