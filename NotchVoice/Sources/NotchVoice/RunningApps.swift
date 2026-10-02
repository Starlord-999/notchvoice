import SwiftUI

@MainActor final class RunningApps: ObservableObject {
    static let shared = RunningApps()
    @Published var apps: [NSRunningApplication] = []

    init() {
        refresh()
        let nc = NSWorkspace.shared.notificationCenter
        for n in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                  NSWorkspace.didActivateApplicationNotification, NSWorkspace.didHideApplicationNotification,
                  NSWorkspace.didUnhideApplicationNotification] {
            nc.addObserver(forName: n, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
        }
    }

    func refresh() {
        let me = ProcessInfo.processInfo.processIdentifier
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != me }
            .sorted { ($0.processIdentifier == front ? 0 : 1, $0.localizedName ?? "") < ($1.processIdentifier == front ? 0 : 1, $1.localizedName ?? "") }
    }
}

struct AppsView: View {
    @ObservedObject var model = RunningApps.shared

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(model.apps, id: \.processIdentifier) { app in
                    Button {
                        app.unhide()
                        app.activate(options: [.activateAllWindows])
                    } label: {
                        VStack(spacing: 4) {
                            Image(nsImage: app.icon ?? NSImage()).resizable().frame(width: 40, height: 40)
                                .opacity(app.isHidden ? 0.4 : 1)
                            Text(app.localizedName ?? "").font(.system(size: 10, design: .rounded)).lineLimit(1)
                                .frame(width: 64)
                            Circle().fill(app.isActive ? Color.green : .clear).frame(width: 4, height: 4)
                        }
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Hide") { app.hide() }
                        Button("Quit") { app.terminate() }
                    }
                }
            }
            .padding(.horizontal, 4)
        }
    }
}
