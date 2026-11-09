import AppKit
import ApplicationServices

/// A menu item of an app (e.g. File ▸ Export ▸ PNG) with its shortcut, if any.
struct MenuEntry: Identifiable, Hashable {
    var id: String { path.joined(separator: "\n") }
    let path: [String]
    let shortcut: String

    /// Title shown in lists: submenus included, top-level menu omitted.
    var displayTitle: String { path.dropFirst().joined(separator: " ▸ ") }
}

struct MenuGroup: Identifiable, Hashable {
    var id: String { title }
    let title: String
    let entries: [MenuEntry]
}

enum AppMenus {
    static let separator = "\n"

    // MARK: Reading

    /// Reads all of an app's menus (except the Apple menu). Call off the main thread.
    static func read(pid: pid_t) -> [MenuGroup] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1.0)
        guard let barObj = AX.attr(app, kAXMenuBarAttribute as String) else { return [] }
        let bar = barObj as! AXUIElement // swiftlint:disable:this force_cast
        let deadline = Date().addingTimeInterval(4)

        var groups: [MenuGroup] = []
        for (i, top) in AX.children(bar).enumerated() where i > 0 { // 0 = Apple menu
            guard let title = AX.string(top, kAXTitleAttribute as String), !title.isEmpty else { continue }
            var entries: [MenuEntry] = []
            for menu in AX.children(top) {
                collect(menu, path: [title], depth: 0, deadline: deadline, into: &entries)
            }
            if !entries.isEmpty { groups.append(MenuGroup(title: title, entries: entries)) }
        }
        return groups
    }

    private static func collect(_ menu: AXUIElement, path: [String], depth: Int, deadline: Date,
                                into entries: inout [MenuEntry]) {
        guard depth < 4, Date() < deadline, entries.count < 1500 else { return }
        for item in AX.children(menu) {
            guard let title = AX.string(item, kAXTitleAttribute as String), !title.isEmpty else { continue }
            let sub = AX.children(item).filter { AX.string($0, kAXRoleAttribute as String) == (kAXMenuRole as String) }
            if let submenu = sub.first, !AX.children(submenu).isEmpty {
                collect(submenu, path: path + [title], depth: depth + 1, deadline: deadline, into: &entries)
            } else {
                entries.append(MenuEntry(path: path + [title], shortcut: shortcut(of: item)))
            }
        }
    }

    /// Shortcut as ⌃⌥⇧⌘X, read from the menu item's attributes.
    private static func shortcut(of item: AXUIElement) -> String {
        let char = AX.string(item, "AXMenuItemCmdChar") ?? ""
        let glyph = (AX.attr(item, "AXMenuItemCmdGlyph") as? Int) ?? 0
        guard !char.isEmpty || glyph != 0 else { return "" }
        let mods = (AX.attr(item, "AXMenuItemCmdModifiers") as? Int) ?? 0

        var s = ""
        if mods & 4 != 0 { s += "⌃" }
        if mods & 2 != 0 { s += "⌥" }
        if mods & 1 != 0 { s += "⇧" }
        if mods & 8 == 0 { s += "⌘" }

        if let g = glyphs[glyph] { return s + g }
        switch char {
        case " ": return s + "Space"
        case "\u{7F}", "\u{8}": return s + "⌫"
        case "\r": return s + "↩︎"
        case "\t": return s + "⇥"
        default: return s + char.uppercased()
        }
    }

    private static let glyphs: [Int: String] = [
        0x02: "⇥", 0x04: "⌅", 0x09: "Space", 0x0A: "⌦", 0x0B: "↩︎", 0x17: "⌫", 0x1B: "Esc",
        0x64: "←", 0x65: "→", 0x68: "↑", 0x6A: "↓", 0x62: "⇞", 0x6B: "⇟", 0x66: "↖︎", 0x67: "↘︎",
        0x6F: "F1", 0x70: "F2", 0x71: "F3", 0x72: "F4", 0x73: "F5", 0x74: "F6", 0x75: "F7",
        0x76: "F8", 0x77: "F9", 0x78: "F10", 0x79: "F11", 0x7A: "F12",
    ]

    // MARK: Running

    /// Presses the given menu item in the frontmost app. Returns false if not found.
    @discardableResult
    static func press(path: [String], pid: pid_t) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1.0)
        guard path.count >= 2, let barObj = AX.attr(app, kAXMenuBarAttribute as String) else { return false }
        let bar = barObj as! AXUIElement // swiftlint:disable:this force_cast

        guard var current = find(path[0], in: AX.children(bar)) else { return false }
        for title in path.dropFirst() {
            guard let menu = AX.children(current).first(where: {
                AX.string($0, kAXRoleAttribute as String) == (kAXMenuRole as String)
            }), let item = find(title, in: AX.children(menu)) else { return false }
            current = item
        }
        return AXUIElementPerformAction(current, kAXPressAction as CFString) == .success
    }

    private static func normalize(_ s: String) -> String {
        s.replacingOccurrences(of: "…", with: "").replacingOccurrences(of: "...", with: "")
            .trimmingCharacters(in: .whitespaces).lowercased()
    }

    private static func find(_ title: String, in elements: [AXUIElement]) -> AXUIElement? {
        if let exact = elements.first(where: { AX.string($0, kAXTitleAttribute as String) == title }) { return exact }
        let n = normalize(title)
        return elements.first(where: { normalize(AX.string($0, kAXTitleAttribute as String) ?? "") == n })
    }
}
