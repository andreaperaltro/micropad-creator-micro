import AppKit
import Carbon.HIToolbox

/// Ready-made commands to assign to keys, per app.
/// App menu commands are read live (see AppMenus); this file mostly lists
/// commands that don't appear in menus (tools, single keys, system shortcuts).
struct LibraryGroup: Identifiable {
    var id: String { title }
    let title: String
    let items: [PadAction]
}

enum Library {
    private static let cmd = NSEvent.ModifierFlags.command
    private static let shift = NSEvent.ModifierFlags.shift
    private static let opt = NSEvent.ModifierFlags.option
    private static let ctrl = NSEvent.ModifierFlags.control

    private static func k(_ label: String, _ code: Int, _ mods: NSEvent.ModifierFlags = [], _ name: String) -> PadAction {
        PadAction(kind: .shortcut, label: label, keyCode: UInt16(code), modifiers: mods.rawValue, keyName: name)
    }
    private static func media(_ m: MediaKey) -> PadAction {
        PadAction(kind: .media, label: m.title, text: m.rawValue)
    }
    private static func scroll(_ label: String, _ amount: Int, _ mods: NSEvent.ModifierFlags = []) -> PadAction {
        PadAction(kind: .scroll, label: label, modifiers: mods.rawValue, amount: amount)
    }

    /// Groups for the given apps (bundle IDs).
    static func groups(for bundleIDs: [String]) -> [LibraryGroup] {
        var out: [LibraryGroup] = []
        for id in bundleIDs { out += appGroups[id] ?? [] }
        return out
    }

    static var macGroups: [LibraryGroup] {
        [
            LibraryGroup(title: "Edit", items: [
                k("Copy", kVK_ANSI_C, cmd, "C"),
                k("Paste", kVK_ANSI_V, cmd, "V"),
                k("Paste without formatting", kVK_ANSI_V, [cmd, opt, shift], "V"),
                k("Cut", kVK_ANSI_X, cmd, "X"),
                k("Undo", kVK_ANSI_Z, cmd, "Z"),
                k("Redo", kVK_ANSI_Z, [cmd, shift], "Z"),
                k("Select all", kVK_ANSI_A, cmd, "A"),
                k("Find", kVK_ANSI_F, cmd, "F"),
                k("Save", kVK_ANSI_S, cmd, "S"),
                k("Print", kVK_ANSI_P, cmd, "P"),
                k("Return", kVK_Return, [], "↩︎"),
                k("Esc", kVK_Escape, [], "Esc"),
                k("Delete", kVK_Delete, [], "⌫"),
                k("Tab", kVK_Tab, [], "⇥"),
            ]),
            LibraryGroup(title: "Windows & apps", items: [
                k("Spotlight", kVK_Space, cmd, "Space"),
                k("Previous app", kVK_Tab, cmd, "⇥"),
                k("Mission Control", kVK_UpArrow, ctrl, "↑"),
                k("App windows", kVK_DownArrow, ctrl, "↓"),
                k("Desktop to the left", kVK_LeftArrow, ctrl, "←"),
                k("Desktop to the right", kVK_RightArrow, ctrl, "→"),
                k("New window", kVK_ANSI_N, cmd, "N"),
                k("Close window", kVK_ANSI_W, cmd, "W"),
                k("Hide app", kVK_ANSI_H, cmd, "H"),
                k("Quit app", kVK_ANSI_Q, cmd, "Q"),
                k("Full screen", kVK_ANSI_F, [cmd, ctrl], "F"),
                k("Emoji & symbols", kVK_Space, [cmd, ctrl], "Space"),
                k("Lock screen", kVK_ANSI_Q, [cmd, ctrl], "Q"),
            ]),
            LibraryGroup(title: "Screenshot", items: [
                k("Screenshot area", kVK_ANSI_4, [cmd, shift], "4"),
                k("Screenshot area → clipboard", kVK_ANSI_4, [cmd, shift, ctrl], "4"),
                k("Screenshot screen", kVK_ANSI_3, [cmd, shift], "3"),
                k("Record / options", kVK_ANSI_5, [cmd, shift], "5"),
            ]),
            LibraryGroup(title: "Audio & brightness", items: MediaKey.allCases.map(media)),
            LibraryGroup(title: "Scroll & zoom", items: [
                scroll("Scroll up", 3), scroll("Scroll down", -3),
                PadAction(kind: .scroll, label: "Scroll left", amount: 3, horizontal: true),
                PadAction(kind: .scroll, label: "Scroll right", amount: -3, horizontal: true),
                scroll("Zoom + (⌘ scroll)", 1, cmd), scroll("Zoom − (⌘ scroll)", -1, cmd),
                scroll("Zoom + (⌥ scroll)", 1, opt), scroll("Zoom − (⌥ scroll)", -1, opt),
            ]),
        ]
    }

    private static var chatBasics: [PadAction] {
        [
            k("Send", kVK_Return, [], "↩︎"),
            k("New line", kVK_Return, shift, "↩︎"),
            k("Stop response", kVK_Escape, [], "Esc"),
            k("Edit last message", kVK_UpArrow, [], "↑"),
            k("Go to latest message", kVK_DownArrow, cmd, "↓"),
            k("Go to top", kVK_UpArrow, cmd, "↑"),
            k("Screenshot area → clipboard", kVK_ANSI_4, [cmd, shift, ctrl], "4"),
        ]
    }

    private static let appGroups: [String: [LibraryGroup]] = [
        "com.anthropic.claudefordesktop": [
            LibraryGroup(title: "Chat", items: chatBasics + [
                k("New chat", kVK_ANSI_N, cmd, "N"),
                k("Search chats", kVK_ANSI_K, cmd, "K"),
                // Claude's dictation uses a shortcut you set in Settings → General:
                // set one there (e.g. ⌃⌥Space) and record the same combination with "More".
            ]),
        ],
        "com.openai.chat": [
            LibraryGroup(title: "Chat", items: chatBasics + [
                k("New chat", kVK_ANSI_O, [cmd, shift], "O"),
                k("Toggle sidebar", kVK_ANSI_S, [cmd, shift], "S"),
                k("Focus chat input", kVK_Escape, shift, "Esc"),
                k("Copy last response", kVK_ANSI_C, [cmd, shift], "C"),
                k("Delete chat", kVK_Delete, [cmd, shift], "⌫"),
                k("Custom instructions", kVK_ANSI_I, [cmd, shift], "I"),
                k("Dictation (microphone)", kVK_ANSI_D, [cmd, shift], "D"),
                k("Screenshot and send", kVK_ANSI_1, [cmd, shift], "1"),
                k("Show all shortcuts", kVK_ANSI_Slash, cmd, "/"),
            ]),
        ],
        "com.adobe.Photoshop": [
            LibraryGroup(title: "Tools", items: [
                k("Move", kVK_ANSI_V, [], "V"),
                k("Rectangular marquee", kVK_ANSI_M, [], "M"),
                k("Lasso", kVK_ANSI_L, [], "L"),
                k("Quick / object selection", kVK_ANSI_W, [], "W"),
                k("Crop", kVK_ANSI_C, [], "C"),
                k("Eyedropper", kVK_ANSI_I, [], "I"),
                k("Healing brush", kVK_ANSI_J, [], "J"),
                k("Brush", kVK_ANSI_B, [], "B"),
                k("Clone stamp", kVK_ANSI_S, [], "S"),
                k("Eraser", kVK_ANSI_E, [], "E"),
                k("Gradient / paint bucket", kVK_ANSI_G, [], "G"),
                k("Dodge / burn", kVK_ANSI_O, [], "O"),
                k("Pen", kVK_ANSI_P, [], "P"),
                k("Text", kVK_ANSI_T, [], "T"),
                k("Path selection", kVK_ANSI_A, [], "A"),
                k("Shapes", kVK_ANSI_U, [], "U"),
                k("Hand (hold)", kVK_Space, [], "Space"),
                k("Zoom", kVK_ANSI_Z, [], "Z"),
                k("Rotate view", kVK_ANSI_R, [], "R"),
                k("Next tool in group", kVK_ANSI_B, shift, "B"),
            ]),
            LibraryGroup(title: "Brush & colors", items: [
                k("Smaller brush", kVK_ANSI_LeftBracket, [], "["),
                k("Bigger brush", kVK_ANSI_RightBracket, [], "]"),
                k("Softer brush", kVK_ANSI_LeftBracket, shift, "["),
                k("Harder brush", kVK_ANSI_RightBracket, shift, "]"),
                k("Default colors", kVK_ANSI_D, [], "D"),
                k("Swap colors", kVK_ANSI_X, [], "X"),
                k("Quick mask", kVK_ANSI_Q, [], "Q"),
                k("Opacity 10%", kVK_ANSI_1, [], "1"),
                k("Opacity 50%", kVK_ANSI_5, [], "5"),
                k("Opacity 100%", kVK_ANSI_0, [], "0"),
            ]),
            LibraryGroup(title: "Layers & selection", items: [
                k("New layer", kVK_ANSI_N, [cmd, shift], "N"),
                k("Layer via copy", kVK_ANSI_J, cmd, "J"),
                k("Merge down", kVK_ANSI_E, cmd, "E"),
                k("Group layers", kVK_ANSI_G, cmd, "G"),
                k("Clipping mask", kVK_ANSI_G, [cmd, opt], "G"),
                k("Free transform", kVK_ANSI_T, cmd, "T"),
                k("Deselect", kVK_ANSI_D, cmd, "D"),
                k("Invert selection", kVK_ANSI_I, [cmd, shift], "I"),
                k("Levels…", kVK_ANSI_L, cmd, "L"),
                k("Curves…", kVK_ANSI_M, cmd, "M"),
                k("Hue/saturation…", kVK_ANSI_U, cmd, "U"),
                k("Fit on screen", kVK_ANSI_0, cmd, "0"),
                k("Zoom 100%", kVK_ANSI_1, cmd, "1"),
                k("Export as…", kVK_ANSI_W, [cmd, opt, shift], "W"),
            ]),
        ],
        "com.adobe.illustrator": [
            LibraryGroup(title: "Tools", items: [
                k("Selection", kVK_ANSI_V, [], "V"),
                k("Direct selection", kVK_ANSI_A, [], "A"),
                k("Magic wand", kVK_ANSI_Y, [], "Y"),
                k("Lasso", kVK_ANSI_Q, [], "Q"),
                k("Pen", kVK_ANSI_P, [], "P"),
                k("Text", kVK_ANSI_T, [], "T"),
                k("Rectangle", kVK_ANSI_M, [], "M"),
                k("Ellipse", kVK_ANSI_L, [], "L"),
                k("Brush", kVK_ANSI_B, [], "B"),
                k("Pencil", kVK_ANSI_N, [], "N"),
                k("Eraser", kVK_ANSI_E, shift, "E"),
                k("Rotate", kVK_ANSI_R, [], "R"),
                k("Reflect", kVK_ANSI_O, [], "O"),
                k("Scale", kVK_ANSI_S, [], "S"),
                k("Free transform", kVK_ANSI_E, [], "E"),
                k("Shape builder", kVK_ANSI_M, shift, "M"),
                k("Width", kVK_ANSI_W, shift, "W"),
                k("Eyedropper", kVK_ANSI_I, [], "I"),
                k("Artboard", kVK_ANSI_O, shift, "O"),
                k("Hand (hold)", kVK_Space, [], "Space"),
                k("Zoom", kVK_ANSI_Z, [], "Z"),
                k("Default colors", kVK_ANSI_D, [], "D"),
                k("Swap fill/stroke", kVK_ANSI_X, shift, "X"),
            ]),
            LibraryGroup(title: "Objects & view", items: [
                k("Group", kVK_ANSI_G, cmd, "G"),
                k("Ungroup", kVK_ANSI_G, [cmd, shift], "G"),
                k("Lock", kVK_ANSI_2, cmd, "2"),
                k("Hide", kVK_ANSI_3, cmd, "3"),
                k("Transform again", kVK_ANSI_D, cmd, "D"),
                k("Make clipping mask", kVK_ANSI_7, cmd, "7"),
                k("Outline / preview", kVK_ANSI_Y, cmd, "Y"),
                k("Rulers", kVK_ANSI_R, cmd, "R"),
                k("Fit artboard", kVK_ANSI_0, cmd, "0"),
                k("Show/hide panels", kVK_Tab, [], "⇥"),
            ]),
        ],
        "com.figma.Desktop": [
            LibraryGroup(title: "Tools", items: [
                k("Move", kVK_ANSI_V, [], "V"),
                k("Frame", kVK_ANSI_F, [], "F"),
                k("Rectangle", kVK_ANSI_R, [], "R"),
                k("Ellipse", kVK_ANSI_O, [], "O"),
                k("Line", kVK_ANSI_L, [], "L"),
                k("Arrow", kVK_ANSI_L, shift, "L"),
                k("Pen", kVK_ANSI_P, [], "P"),
                k("Pencil", kVK_ANSI_P, shift, "P"),
                k("Text", kVK_ANSI_T, [], "T"),
                k("Comment", kVK_ANSI_C, [], "C"),
                k("Hand (hold)", kVK_Space, [], "Space"),
                k("Place image", kVK_ANSI_K, [cmd, shift], "K"),
            ]),
            LibraryGroup(title: "Layers", items: [
                k("Auto layout", kVK_ANSI_A, shift, "A"),
                k("Create component", kVK_ANSI_K, [cmd, opt], "K"),
                k("Detach instance", kVK_ANSI_B, [cmd, opt], "B"),
                k("Duplicate", kVK_ANSI_D, cmd, "D"),
                k("Group", kVK_ANSI_G, cmd, "G"),
                k("Ungroup", kVK_ANSI_G, [cmd, shift], "G"),
                k("Frame selection", kVK_ANSI_G, [cmd, opt], "G"),
                k("Use as mask", kVK_ANSI_M, [cmd, ctrl], "M"),
                k("Show/hide", kVK_ANSI_H, [cmd, shift], "H"),
                k("Lock/unlock", kVK_ANSI_L, [cmd, shift], "L"),
                k("Copy properties", kVK_ANSI_C, [cmd, opt], "C"),
                k("Paste properties", kVK_ANSI_V, [cmd, opt], "V"),
                k("Flatten", kVK_ANSI_E, cmd, "E"),
            ]),
            LibraryGroup(title: "View", items: [
                k("Zoom to fit", kVK_ANSI_1, shift, "1"),
                k("Zoom to selection", kVK_ANSI_2, shift, "2"),
                k("Zoom 100%", kVK_ANSI_0, shift, "0"),
                k("Rulers", kVK_ANSI_R, shift, "R"),
                k("Quick actions", kVK_ANSI_K, cmd, "K"),
            ]),
        ],
        "com.google.Chrome": [
            LibraryGroup(title: "Tabs", items: [
                k("New tab", kVK_ANSI_T, cmd, "T"),
                k("Reopen closed tab", kVK_ANSI_T, [cmd, shift], "T"),
                k("Close tab", kVK_ANSI_W, cmd, "W"),
                k("Next tab", kVK_Tab, ctrl, "⇥"),
                k("Previous tab", kVK_Tab, [ctrl, shift], "⇥"),
                k("First tab", kVK_ANSI_1, cmd, "1"),
                k("Last tab", kVK_ANSI_9, cmd, "9"),
                k("New window", kVK_ANSI_N, cmd, "N"),
                k("Incognito window", kVK_ANSI_N, [cmd, shift], "N"),
            ]),
            LibraryGroup(title: "Navigation", items: [
                k("Back", kVK_LeftArrow, cmd, "←"),
                k("Forward", kVK_RightArrow, cmd, "→"),
                k("Reload", kVK_ANSI_R, cmd, "R"),
                k("Hard reload", kVK_ANSI_R, [cmd, shift], "R"),
                k("Address bar", kVK_ANSI_L, cmd, "L"),
                k("Find in page", kVK_ANSI_F, cmd, "F"),
                k("Bookmark page", kVK_ANSI_D, cmd, "D"),
                k("History", kVK_ANSI_Y, cmd, "Y"),
                k("Developer tools", kVK_ANSI_I, [cmd, opt], "I"),
                k("Full screen", kVK_ANSI_F, [cmd, ctrl], "F"),
            ]),
        ],
    ]
}
