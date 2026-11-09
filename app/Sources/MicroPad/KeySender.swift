import AppKit
import Carbon.HIToolbox
import CoreGraphics

/// Runs actions by synthesizing keyboard, scroll and media key events.
/// Requires Accessibility permission (System Settings → Privacy & Security).
enum KeySender {
    private static let source = CGEventSource(stateID: .hidSystemState)

    private static let modifierKeys: [(NSEvent.ModifierFlags, CGKeyCode, CGEventFlags)] = [
        (.control, CGKeyCode(kVK_Control), .maskControl),
        (.option, CGKeyCode(kVK_Option), .maskAlternate),
        (.shift, CGKeyCode(kVK_Shift), .maskShift),
        (.command, CGKeyCode(kVK_Command), .maskCommand),
    ]

    static func cgFlags(_ m: NSEvent.ModifierFlags) -> CGEventFlags {
        var f: CGEventFlags = []
        for (mod, _, flag) in modifierKeys where m.contains(mod) { f.insert(flag) }
        return f
    }

    private static func post(_ code: CGKeyCode, down: Bool, flags: CGEventFlags) {
        guard let e = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { return }
        e.flags = flags
        e.post(tap: .cghidEventTap)
    }

    /// Presses (without releasing) a shortcut. Modifiers are pressed as
    /// real keys, so it works in Adobe apps too.
    static func press(_ a: PadAction) {
        let mods = a.modifierFlags
        var flags: CGEventFlags = []
        for (mod, code, flag) in modifierKeys where mods.contains(mod) {
            flags.insert(flag)
            post(code, down: true, flags: flags)
            usleep(8_000)
        }
        // Short pause: some apps (global hotkeys, Electron) read modifier state late.
        if !mods.isEmpty { usleep(12_000) }
        post(CGKeyCode(a.keyCode), down: true, flags: flags)
    }

    static func release(_ a: PadAction) {
        let mods = a.modifierFlags
        var flags = cgFlags(mods)
        post(CGKeyCode(a.keyCode), down: false, flags: flags)
        if !mods.isEmpty { usleep(12_000) }
        for (mod, code, flag) in modifierKeys.reversed() where mods.contains(mod) {
            flags.remove(flag)
            post(code, down: false, flags: flags)
        }
    }

    static func tap(_ a: PadAction) {
        press(a)
        usleep(20_000)
        release(a)
    }

    static func type(_ text: String) {
        let units = Array(text.utf16)
        var i = 0
        while i < units.count {
            let chunk = Array(units[i..<min(i + 20, units.count)])
            for down in [true, false] {
                guard let e = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down) else { continue }
                chunk.withUnsafeBufferPointer { buf in
                    e.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: buf.baseAddress)
                }
                e.post(tap: .cghidEventTap)
            }
            i += 20
        }
    }

    static func scroll(_ a: PadAction) {
        let lines = Int32(a.amount)
        let e = a.horizontal
            ? CGEvent(scrollWheelEvent2Source: source, units: .line, wheelCount: 2, wheel1: 0, wheel2: lines, wheel3: 0)
            : CGEvent(scrollWheelEvent2Source: source, units: .line, wheelCount: 1, wheel1: lines, wheel2: 0, wheel3: 0)
        guard let e else { return }
        // With modifiers this becomes zoom: ⌥ in Photoshop/Illustrator, ⌘ in Figma.
        e.flags = cgFlags(a.modifierFlags)
        e.post(tap: .cghidEventTap)
    }

    static func media(_ key: MediaKey) {
        // NX_KEYTYPE_* codes from IOKit/hidsystem/ev_keymap.h
        let code: Int32
        switch key {
        case .volumeUp: code = 0
        case .volumeDown: code = 1
        case .brightnessUp: code = 2
        case .brightnessDown: code = 3
        case .mute: code = 7
        case .playPause: code = 16
        case .next: code = 17
        case .previous: code = 18
        }
        for down in [true, false] {
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00)
            let data1 = Int((code << 16) | ((down ? 0xA : 0xB) << 8))
            let ev = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags,
                                        timestamp: 0, windowNumber: 0, context: nil,
                                        subtype: 8, data1: data1, data2: -1)
            ev?.cgEvent?.post(tap: .cghidEventTap)
        }
    }

    static func open(_ target: String) {
        let t = target.trimmingCharacters(in: .whitespaces)
        if t.hasSuffix(".app") || t.hasPrefix("/") {
            NSWorkspace.shared.open(URL(fileURLWithPath: t))
        } else if let url = URL(string: t.contains("://") ? t : "https://\(t)") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Key names for default profiles (physical positions, ANSI/ISO layout).
enum KeyNames {
    static func name(for code: UInt16) -> String {
        switch Int(code) {
        case kVK_Return: return "↩︎"
        case kVK_Tab: return "⇥"
        case kVK_Space: return "Space"
        case kVK_Delete: return "⌫"
        case kVK_Escape: return "Esc"
        case kVK_ForwardDelete: return "⌦"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_Home: return "↖︎"
        case kVK_End: return "↘︎"
        case kVK_PageUp: return "⇞"
        case kVK_PageDown: return "⇟"
        default: return "#\(code)"
        }
    }

    /// Name from the current keyboard layout (e.g. "È" on an Italian layout).
    static func current(for event: NSEvent) -> String {
        let special = name(for: event.keyCode)
        if !special.hasPrefix("#") { return special }
        if let c = event.charactersIgnoringModifiers, !c.isEmpty, c.unicodeScalars.allSatisfy({ $0.value >= 32 && $0.value < 0xF700 }) {
            return c.uppercased()
        }
        return special
    }
}
