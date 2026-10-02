import Carbon.HIToolbox

/// Global hotkeys (no permission needed). ⌥Space = Type, ⌥⇧Space = Command.
enum Hotkeys {
    private static var handlers: [UInt32: () -> Void] = [:]

    static func register(id: UInt32, key: Int, mods: Int, _ action: @escaping () -> Void) {
        handlers[id] = action
        if handlers.count == 1 {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, e, _ in
                var hk = EventHotKeyID()
                GetEventParameter(e, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                  MemoryLayout<EventHotKeyID>.size, nil, &hk)
                DispatchQueue.main.async { Hotkeys.handlers[hk.id]?() }
                return noErr
            }, 1, &spec, nil, nil)
        }
        var ref: EventHotKeyRef?
        RegisterEventHotKey(UInt32(key), UInt32(mods), EventHotKeyID(signature: 0x4E54_4348, id: id),
                            GetApplicationEventTarget(), 0, &ref)
    }
}
