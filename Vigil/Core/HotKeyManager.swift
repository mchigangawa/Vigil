import AppKit
import Carbon.HIToolbox
import Combine

/// The three actions a global shortcut can be bound to.
enum HotKeyAction: String, CaseIterable, Identifiable, Codable {
    case toggleKeepAwake
    case toggleCleaningMode
    case lockAndKeepAwake

    var id: String { rawValue }

    var title: String {
        switch self {
        case .toggleKeepAwake: return "Toggle Keep Awake"
        case .toggleCleaningMode: return "Toggle Cleaning Mode"
        case .lockAndKeepAwake: return "Lock & Keep Awake"
        }
    }

    /// Stable per-action id used as the Carbon hot key id.
    var carbonID: UInt32 {
        switch self {
        case .toggleKeepAwake: return 1
        case .toggleCleaningMode: return 2
        case .lockAndKeepAwake: return 3
        }
    }
}

/// A recorded shortcut: a virtual key code plus Cocoa modifier flags.
struct HotKeyCombo: Codable, Equatable, Hashable {
    var keyCode: UInt32
    /// Raw value of `NSEvent.ModifierFlags`, masked to the device-independent set.
    var modifierFlags: UInt

    var cocoaFlags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifierFlags) }

    /// Cocoa flags translated to the Carbon bitfield `RegisterEventHotKey` wants.
    var carbonModifiers: UInt32 {
        var carbon: UInt32 = 0
        if cocoaFlags.contains(.command) { carbon |= UInt32(cmdKey) }
        if cocoaFlags.contains(.option) { carbon |= UInt32(optionKey) }
        if cocoaFlags.contains(.control) { carbon |= UInt32(controlKey) }
        if cocoaFlags.contains(.shift) { carbon |= UInt32(shiftKey) }
        return carbon
    }

    /// A shortcut with no modifier would swallow an ordinary keystroke globally.
    var isValid: Bool { carbonModifiers != 0 }

    var displayString: String {
        var out = ""
        if cocoaFlags.contains(.control) { out += "\u{2303}" }
        if cocoaFlags.contains(.option) { out += "\u{2325}" }
        if cocoaFlags.contains(.shift) { out += "\u{21E7}" }
        if cocoaFlags.contains(.command) { out += "\u{2318}" }
        out += HotKeyCombo.keyName(for: keyCode)
        return out
    }

    static func keyName(for keyCode: UInt32) -> String {
        let named: [UInt32: String] = [
            36: "\u{21A9}", 48: "\u{21E5}", 49: "Space", 51: "\u{232B}", 53: "\u{238B}",
            123: "\u{2190}", 124: "\u{2192}", 125: "\u{2193}", 126: "\u{2191}",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
            98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        ]
        if let name = named[keyCode] { return name }

        // Ask the current keyboard layout what this key produces, so the label
        // matches what is printed on the user's own keyboard.
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return "Key \(keyCode)" }

        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)

        let status = data.withUnsafeBytes { raw -> OSStatus in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return -1 }
            return UCKeyTranslate(layout,
                                  UInt16(keyCode),
                                  UInt16(kUCKeyActionDisplay),
                                  0,
                                  UInt32(LMGetKbdType()),
                                  OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                  &deadKeyState,
                                  chars.count,
                                  &length,
                                  &chars)
        }

        guard status == noErr, length > 0 else { return "Key \(keyCode)" }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }
}

/// Registers system-wide shortcuts through Carbon's hot key API.
///
/// Carbon is the only route to a global shortcut that *consumes* the keystroke
/// without needing Accessibility permission — `NSEvent` global monitors can
/// observe but not swallow, and would leak the shortcut into the focused app.
@MainActor
final class HotKeyManager: ObservableObject {

    static let shared = HotKeyManager()

    private var handlers: [HotKeyAction: () -> Void] = [:]
    private var registered: [HotKeyAction: EventHotKeyRef] = [:]
    private var eventHandler: EventHandlerRef?
    private static let signature: OSType = 0x5647_4C21 // 'VGL!'

    private init() {}

    func setHandler(_ handler: @escaping () -> Void, for action: HotKeyAction) {
        handlers[action] = handler
    }

    /// Applies whatever is currently stored in preferences.
    func reloadFromPreferences() {
        installEventHandlerIfNeeded()
        for action in HotKeyAction.allCases {
            unregister(action)
            if let combo = Preferences.shared.hotKey(for: action), combo.isValid {
                register(combo, for: action)
            }
        }
    }

    func unregisterAll() {
        for action in HotKeyAction.allCases { unregister(action) }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    // MARK: - Carbon plumbing

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return noErr }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard status == noErr else { return status }

            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            // Carbon delivers on the main thread; hop explicitly so the call
            // into main-actor state is checked rather than assumed.
            DispatchQueue.main.async {
                MainActor.assumeIsolated { manager.fire(carbonID: hotKeyID.id) }
            }
            return noErr
        }, 1, &spec, context, &eventHandler)
    }

    private func fire(carbonID: UInt32) {
        guard let action = HotKeyAction.allCases.first(where: { $0.carbonID == carbonID }) else { return }
        handlers[action]?()
    }

    private func register(_ combo: HotKeyCombo, for action: HotKeyAction) {
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: action.carbonID)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(combo.keyCode,
                                         combo.carbonModifiers,
                                         hotKeyID,
                                         GetApplicationEventTarget(),
                                         0,
                                         &ref)
        if status == noErr, let ref {
            registered[action] = ref
        }
    }

    private func unregister(_ action: HotKeyAction) {
        if let ref = registered[action] {
            UnregisterEventHotKey(ref)
            registered[action] = nil
        }
    }
}
