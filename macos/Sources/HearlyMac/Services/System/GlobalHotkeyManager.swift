import Carbon
import Foundation

enum HotkeyOption: String, CaseIterable, Identifiable {
    case optionSpace = "⌥ Space"
    case cmdShiftH = "⌘ ⇧ H"

    var id: String { rawValue }

    var keyCode: UInt32 {
        switch self {
        case .optionSpace: return 0x31 // 49: Space
        case .cmdShiftH: return 0x04    // 4: 'H'
        }
    }

    var carbonModifiers: UInt32 {
        switch self {
        case .optionSpace: return UInt32(optionKey)
        case .cmdShiftH: return UInt32(cmdKey | shiftKey)
        }
    }
}

private func carbonHotKeyHandler(
    nextHandler: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData else { return noErr }
    let manager = Unmanaged<GlobalHotkeyManager>.fromOpaque(userData).takeUnretainedValue()
    DispatchQueue.main.async {
        manager.handleTrigger()
    }
    return noErr
}

@MainActor
final class GlobalHotkeyManager: ObservableObject {
    var onTrigger: (() -> Void)?

    @Published var isEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "hearly.hotkey.enabled")
            updateRegistration()
        }
    }

    @Published var currentOption: HotkeyOption = .optionSpace {
        didSet {
            UserDefaults.standard.set(currentOption.rawValue, forKey: "hearly.hotkey.option")
            updateRegistration()
        }
    }

    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private var isHandlerInstalled = false

    init() {
        if let savedOptionStr = UserDefaults.standard.string(forKey: "hearly.hotkey.option"),
           let savedOption = HotkeyOption(rawValue: savedOptionStr) {
            currentOption = savedOption
        }
        if UserDefaults.standard.object(forKey: "hearly.hotkey.enabled") != nil {
            isEnabled = UserDefaults.standard.bool(forKey: "hearly.hotkey.enabled")
        }
        installHandler()
        updateRegistration()
    }

    isolated deinit {
        unregisterHotKey()
        removeHandler()
    }

    func handleTrigger() {
        guard isEnabled else { return }
        onTrigger?()
    }

    private func installHandler() {
        guard !isHandlerInstalled else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            carbonHotKeyHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
        isHandlerInstalled = (status == noErr)
    }

    private func removeHandler() {
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
            eventHandlerRef = nil
        }
        isHandlerInstalled = false
    }

    private func updateRegistration() {
        unregisterHotKey()
        guard isEnabled else { return }
        registerHotKey(for: currentOption)
    }

    private func registerHotKey(for option: HotkeyOption) {
        let hotKeyID = EventHotKeyID(signature: OSType(0x48524C59), id: 1) // 'HRLY'
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            option.keyCode,
            option.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr {
            hotKeyRef = ref
        }
    }

    private func unregisterHotKey() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }
}
