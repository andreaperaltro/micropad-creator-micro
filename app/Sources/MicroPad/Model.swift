import AppKit
import SwiftUI

// MARK: Colors

struct RGB: Codable, Hashable {
    var r: UInt8
    var g: UInt8
    var b: UInt8

    static let off = RGB(r: 0, g: 0, b: 0)

    init(r: UInt8, g: UInt8, b: UInt8) { self.r = r; self.g = g; self.b = b }

    init?(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        r = UInt8((v >> 16) & 0xFF); g = UInt8((v >> 8) & 0xFF); b = UInt8(v & 0xFF)
    }

    var hex: String { String(format: "%02x%02x%02x", r, g, b) }

    /// true if the color is light (perceived luminance), to pick the text color on top.
    var isLight: Bool {
        func lin(_ c: UInt8) -> Double {
            let v = Double(c) / 255
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        let l = 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
        return l > 0.18
    }

    var color: Color {
        Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }

    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .white
        r = UInt8(clamping: Int((ns.redComponent * 255).rounded()))
        g = UInt8(clamping: Int((ns.greenComponent * 255).rounded()))
        b = UInt8(clamping: Int((ns.blueComponent * 255).rounded()))
    }

    func dimmed(_ f: Double) -> RGB {
        RGB(r: UInt8(Double(r) * f), g: UInt8(Double(g) * f), b: UInt8(Double(b) * f))
    }

    // Encoded as a hex string, more readable in JSON.
    init(from decoder: Decoder) throws {
        let s = try decoder.singleValueContainer().decode(String.self)
        self = RGB(hex: s) ?? .off
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(hex)
    }
}

// MARK: Actions

enum ActionKind: String, Codable, CaseIterable, Identifiable {
    case none, shortcut, menu, text, url, media, scroll
    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: return "None"
        case .shortcut: return "Shortcut"
        case .menu: return "Menu command"
        case .text: return "Type text"
        case .url: return "Open link / app"
        case .media: return "Media key"
        case .scroll: return "Scroll"
        }
    }
}

enum MediaKey: String, CaseIterable, Identifiable {
    case volumeUp, volumeDown, mute, playPause, next, previous, brightnessUp, brightnessDown
    var id: String { rawValue }
    var title: String {
        switch self {
        case .volumeUp: return "Volume +"
        case .volumeDown: return "Volume −"
        case .mute: return "Mute"
        case .playPause: return "Play / Pause"
        case .next: return "Next track"
        case .previous: return "Previous track"
        case .brightnessUp: return "Brightness +"
        case .brightnessDown: return "Brightness −"
        }
    }
}

struct PadAction: Codable, Hashable {
    var kind: ActionKind = .none
    var label: String = ""
    /// Shortcut: physical key code (kVK_*) and modifiers (NSEvent.ModifierFlags.rawValue).
    var keyCode: UInt16 = 0
    var modifiers: UInt = 0
    /// Readable key name, captured when recording (respects the current keyboard layout).
    var keyName: String = ""
    /// Text to type, URL to open, media key name,
    /// or menu path (titles separated by newlines, e.g. "File\nExport").
    var text: String = ""
    /// Scroll: lines (positive = up / right). horizontal = horizontal scroll.
    var amount: Int = 0
    var horizontal: Bool = false

    static let none = PadAction()

    init(kind: ActionKind = .none, label: String = "", keyCode: UInt16 = 0, modifiers: UInt = 0,
         keyName: String = "", text: String = "", amount: Int = 0, horizontal: Bool = false) {
        self.kind = kind; self.label = label; self.keyCode = keyCode; self.modifiers = modifiers
        self.keyName = keyName; self.text = text; self.amount = amount; self.horizontal = horizontal
    }

    // Lenient decoding: missing fields get default values.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = (try? c.decode(ActionKind.self, forKey: .kind)) ?? .none
        label = (try? c.decode(String.self, forKey: .label)) ?? ""
        keyCode = (try? c.decode(UInt16.self, forKey: .keyCode)) ?? 0
        modifiers = (try? c.decode(UInt.self, forKey: .modifiers)) ?? 0
        keyName = (try? c.decode(String.self, forKey: .keyName)) ?? ""
        text = (try? c.decode(String.self, forKey: .text)) ?? ""
        amount = (try? c.decode(Int.self, forKey: .amount)) ?? 0
        horizontal = (try? c.decode(Bool.self, forKey: .horizontal)) ?? false
    }

    var menuPath: [String] { text.components(separatedBy: "\n").filter { !$0.isEmpty } }

    var modifierFlags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    var shortcutDescription: String {
        let m = modifierFlags
        var s = ""
        if m.contains(.control) { s += "⌃" }
        if m.contains(.option) { s += "⌥" }
        if m.contains(.shift) { s += "⇧" }
        if m.contains(.command) { s += "⌘" }
        return s + (keyName.isEmpty ? KeyNames.name(for: keyCode) : keyName)
    }

    /// Short text shown on the key in the editor.
    var displayText: String {
        if !label.isEmpty { return label }
        switch kind {
        case .none: return ""
        case .shortcut: return shortcutDescription
        case .menu: return menuPath.last ?? ""
        case .text: return "“\(text.prefix(8))”"
        case .url: return "↗︎"
        case .media: return MediaKey(rawValue: text)?.title ?? text
        case .scroll: return amount >= 0 ? "Scroll +" : "Scroll −"
        }
    }
}

// MARK: Profiles

struct KeySlot: Codable, Hashable {
    var action: PadAction = .none
    /// nil = use the profile color.
    var color: RGB? = nil
}

struct EncoderSlot: Codable, Hashable {
    var left: PadAction = .none   // counter-clockwise
    var right: PadAction = .none  // clockwise
}

struct Profile: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    /// Bundle IDs of the apps that activate this profile.
    var bundleIDs: [String]
    var color: RGB
    /// The base profile applies to every app without a profile of its own.
    var isBase: Bool = false
    /// Flash when the app (Claude, ChatGPT…) finishes writing a reply.
    var watchReplies: Bool = false
    var keys: [KeySlot] = Array(repeating: KeySlot(), count: 16)
    var encoders: [EncoderSlot] = [EncoderSlot(), EncoderSlot()]

    /// Color the pad shows for the key at position i.
    func ledColor(_ i: Int) -> RGB {
        let slot = keys[i]
        if slot.action.kind == .none { return color.dimmed(0.08) }
        return slot.color ?? color
    }
}

extension Profile {
    static let chatAppIDs: Set<String> = ["com.anthropic.claudefordesktop", "com.openai.chat"]

    // Lenient decoding: profiles saved by older versions stay valid.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        name = (try? c.decode(String.self, forKey: .name)) ?? "Profile"
        bundleIDs = (try? c.decode([String].self, forKey: .bundleIDs)) ?? []
        color = (try? c.decode(RGB.self, forKey: .color)) ?? RGB(r: 255, g: 255, b: 255)
        isBase = (try? c.decode(Bool.self, forKey: .isBase)) ?? false
        watchReplies = (try? c.decode(Bool.self, forKey: .watchReplies))
            ?? !Profile.chatAppIDs.isDisjoint(with: bundleIDs)
        var k = (try? c.decode([KeySlot].self, forKey: .keys)) ?? []
        while k.count < 16 { k.append(KeySlot()) }
        keys = Array(k.prefix(16))
        var e = (try? c.decode([EncoderSlot].self, forKey: .encoders)) ?? []
        while e.count < 2 { e.append(EncoderSlot()) }
        encoders = Array(e.prefix(2))
    }
}

// MARK: Notification alerts

/// If a notification banner contains one of the words, the edge LEDs flash in the chosen color.
struct AlertRule: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    /// Comma-separated words, case-insensitive.
    var keywords: String
    var color: RGB
    /// true = flash until a pad key is pressed.
    var untilPressed: Bool = true
    var enabled: Bool = true

    var keywordList: [String] {
        keywords.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    func matches(_ text: String) -> Bool {
        enabled && keywordList.contains { text.localizedCaseInsensitiveContains($0) }
    }

    static var defaults: [AlertRule] {
        [AlertRule(name: "Gmail", keywords: "mail.google.com, Gmail", color: RGB(hex: "ea4335")!)]
    }
}

// MARK: Physical pad layout

/// Positions (in key units) from QMK's keyboard.json. Index = row*4 + column.
enum PadLayout {
    static let positions: [CGPoint] = [
        CGPoint(x: 0, y: 0), CGPoint(x: 1.25, y: 0.25), CGPoint(x: 2.25, y: 0.25), CGPoint(x: 3.5, y: 0),
        CGPoint(x: 0.25, y: 1.25), CGPoint(x: 1.25, y: 1.25), CGPoint(x: 2.25, y: 1.25), CGPoint(x: 3.25, y: 1.25),
        CGPoint(x: 0.25, y: 2.25), CGPoint(x: 1.25, y: 2.25), CGPoint(x: 2.25, y: 2.25), CGPoint(x: 3.25, y: 2.25),
        CGPoint(x: 0, y: 3.5), CGPoint(x: 1.25, y: 3.25), CGPoint(x: 2.25, y: 3.25), CGPoint(x: 3.5, y: 3.5),
    ]
    /// Corner positions have no LED. 0 and 3 are the encoder clicks.
    static let corners: Set<Int> = [0, 3, 12, 15]
    static func encoderFor(key: Int) -> Int? { key == 0 ? 0 : (key == 3 ? 1 : nil) }
    static func keyFor(encoder: Int) -> Int { encoder == 0 ? 0 : 3 }

    static func name(_ i: Int) -> String {
        switch i {
        case 0: return "Left encoder"
        case 3: return "Right encoder"
        case 12: return "Bottom-left corner"
        case 15: return "Bottom-right corner"
        default: return "Key \(i)"
        }
    }
}
