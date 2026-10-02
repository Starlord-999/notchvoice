import AppKit
import Combine
import Carbon.HIToolbox
import ServiceManagement

if let i = CommandLine.arguments.firstIndex(of: "--match") {  // debug: which installed apps would a phrase open?
    for phrase in CommandLine.arguments[(i + 1)...] {
        let rest = Actions.rest(after: Actions.openVerbs, in: Words.normalize(phrase)) ?? ""
        print(phrase, "->", Actions.matchApps(rest, in: Actions.apps.keys))
    }
    exit(0)
}

if CommandLine.arguments.contains("--check") {
    Words.check()
    Actions.check()
    Actions.checkControls()
    Actions.checkKeys()
    Browser.check()
    exit(0)
}

private let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)

final class AppDelegate: NSObject, NSApplicationDelegate {
    var windowController: NotchWindowController?
    var statusItem: NSStatusItem?
    var sessionWatch: AnyCancellable?

    func applicationDidFinishLaunching(_: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NotificationCenter.default.addObserver(
            self, selector: #selector(rebuildWindow),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
        _ = EventMonitors.shared
        rebuildWindow()
        buildMenu()
        Task { @MainActor in
            Clips.shared.start()
            Today.shared.start()
            Hotkeys.register(id: 1, key: kVK_Space, mods: optionKey) { MainActor.assumeIsolated { Assistant.shared.toggleType() } }
            Hotkeys.register(id: 2, key: kVK_Space, mods: optionKey | shiftKey) { MainActor.assumeIsolated { Assistant.shared.toggleCommand() } }
            await Assistant.shared.start()
        }
    }

    /// `open -a NotchVoice file.pdf` or Finder "Open With".
    func application(_: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        if url.scheme == "notchvoice" { Task { @MainActor in Today.shared.handle(url) }; return }
        Task { @MainActor in Assistant.shared.load(url) }
    }

    func applicationWillTerminate(_: Notification) {
        Servers.shared.stop()
    }

    @objc func rebuildWindow() {
        windowController?.destroy()
        let screen = NSScreen.buildin.flatMap { $0.notchSize == .zero ? nil : $0 } ?? NSScreen.main
        guard let screen else { return }
        windowController = NotchWindowController(screen: screen)
        Task { @MainActor in Assistant.shared.vm = self.windowController?.vm }
    }

    // Menu-bar item: the only non-voice controls.
    @MainActor func buildMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Notch Voice")
        let menu = NSMenu()
        menu.addItem(toggle("Always require “Hey Notch”", #selector(toggleWake), Settings.requireWake))
        menu.addItem(toggle("Launch at Login", #selector(toggleLogin), SMAppService.mainApp.status == .enabled))
        menu.addItem(withTitle: "Toggle Typing  (⌥Space)", action: #selector(menuType), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Toggle Command mode  (⌥⇧Space)", action: #selector(menuCommand), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApp.terminate), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
        // Filled icon while a "Hey Notch" session / dictation is listening without the wake phrase.
        sessionWatch = Assistant.shared.$inSession.receive(on: DispatchQueue.main).sink { [weak item] on in
            item?.button?.image = NSImage(systemSymbolName: on ? "waveform.circle.fill" : "waveform", accessibilityDescription: "Notch Voice")
        }
    }

    private func toggle(_ title: String, _ action: Selector, _ on: Bool) -> NSMenuItem {
        let m = NSMenuItem(title: title, action: action, keyEquivalent: "")
        m.target = self
        m.state = on ? .on : .off
        return m
    }

    @MainActor @objc func menuType() { Assistant.shared.toggleType() }
    @MainActor @objc func menuCommand() { Assistant.shared.toggleCommand() }

    @objc func toggleWake(_ sender: NSMenuItem) {
        Settings.requireWake.toggle()
        sender.state = Settings.requireWake ? .on : .off
    }

    @objc func toggleLogin(_ sender: NSMenuItem) {
        let s = SMAppService.mainApp
        try? (s.status == .enabled ? s.unregister() : s.register())
        sender.state = s.status == .enabled ? .on : .off
    }
}

enum Settings {
    private static let d = UserDefaults.standard

    /// Project folder holding models/, sidecar/, vendor/. Override: `defaults write <bundle id> root /path`
    static var root: URL {
        URL(fileURLWithPath: d.string(forKey: "root")
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/notch").path)
    }

    static var requireWake: Bool {
        get { d.object(forKey: "requireWake") as? Bool ?? false }
        set { d.set(newValue, forKey: "requireWake") }
    }

    // Laya confidence gate — tune on real speech in your room.
    static var actAt: Double { d.object(forKey: "actAt") as? Double ?? 0.9 }
    static var confirmAt: Double { d.object(forKey: "confirmAt") as? Double ?? 0.6 }
}
