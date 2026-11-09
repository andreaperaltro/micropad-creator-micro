import AppKit
import Carbon.HIToolbox

/// Default profiles. Everything can be changed in the editor.
/// Shortcuts use physical key positions: if one doesn't work with your layout,
/// re-record it in the editor by pressing the real combination.
enum DefaultProfiles {
    private static let cmd = NSEvent.ModifierFlags.command
    private static let shift = NSEvent.ModifierFlags.shift
    private static let opt = NSEvent.ModifierFlags.option
    private static let ctrl = NSEvent.ModifierFlags.control

    private static func k(_ label: String, _ code: Int, _ mods: NSEvent.ModifierFlags = [], _ name: String) -> PadAction {
        PadAction(kind: .shortcut, label: label, keyCode: UInt16(code), modifiers: mods.rawValue, keyName: name)
    }
    private static func scroll(_ label: String, _ amount: Int, _ mods: NSEvent.ModifierFlags = []) -> PadAction {
        PadAction(kind: .scroll, label: label, modifiers: mods.rawValue, amount: amount)
    }
    private static func media(_ key: MediaKey) -> PadAction {
        PadAction(kind: .media, label: key.title, text: key.rawValue)
    }
    private static func text(_ label: String, _ t: String) -> PadAction {
        PadAction(kind: .text, label: label, text: t)
    }

    private static func make(_ name: String, _ ids: [String], _ hex: String,
                             _ actions: [Int: PadAction], enc0: EncoderSlot, enc1: EncoderSlot) -> Profile {
        var p = Profile(name: name, bundleIDs: ids, color: RGB(hex: hex) ?? .off, isBase: ids.isEmpty)
        for (i, a) in actions { p.keys[i].action = a }
        p.encoders = [enc0, enc1]
        return p
    }

    // Common actions
    private static var undo: PadAction { k("Undo", kVK_ANSI_Z, cmd, "Z") }
    private static var redo: PadAction { k("Redo", kVK_ANSI_Z, [cmd, shift], "Z") }
    private static var hand: PadAction { k("Hand (hold)", kVK_Space, [], "Space") }
    private static var scrollEnc: EncoderSlot { EncoderSlot(left: scroll("Up", 3), right: scroll("Down", -3)) }
    private static var undoEnc: EncoderSlot { EncoderSlot(left: undo, right: redo) }

    private static func aiActions() -> [Int: PadAction] {
        [
            1: k("New chat", kVK_ANSI_N, cmd, "N"),
            2: k("Search", kVK_ANSI_K, cmd, "K"),
            4: k("Send", kVK_Return, [], "↩︎"),
            5: k("New line", kVK_Return, shift, "↩︎"),
            6: k("Stop", kVK_Escape, [], "Esc"),
            7: k("Copy", kVK_ANSI_C, cmd, "C"),
            8: k("Paste", kVK_ANSI_V, cmd, "V"),
            9: k("Select all", kVK_ANSI_A, cmd, "A"),
            10: undo,
            11: redo,
            12: text("Prompt: explain", "Explain it simply, with a concrete example."),
            13: k("Screenshot → chat", kVK_ANSI_4, [cmd, shift, ctrl], "4"),
            14: k("Go to bottom", kVK_DownArrow, cmd, "↓"),
            0: k("Go to bottom", kVK_DownArrow, cmd, "↓"),
        ]
    }

    static func all() -> [Profile] {
        var list: [Profile] = []
        list.append(make("Base", [], "c8c8d2", [
            1: undo, 2: redo,
            4: k("Copy", kVK_ANSI_C, cmd, "C"),
            5: k("Paste", kVK_ANSI_V, cmd, "V"),
            6: k("Cut", kVK_ANSI_X, cmd, "X"),
            7: k("Select all", kVK_ANSI_A, cmd, "A"),
            8: k("Save", kVK_ANSI_S, cmd, "S"),
            9: k("Search", kVK_ANSI_F, cmd, "F"),
            10: k("Spotlight", kVK_Space, cmd, "Space"),
            11: k("Screenshot", kVK_ANSI_4, [cmd, shift], "4"),
            13: k("Mission Control", kVK_UpArrow, ctrl, "↑"),
            14: k("Previous app", kVK_Tab, cmd, "⇥"),
            0: media(.playPause),
            3: media(.mute),
        ], enc0: EncoderSlot(left: media(.volumeDown), right: media(.volumeUp)), enc1: scrollEnc))

        list.append(make("Claude", ["com.anthropic.claudefordesktop"], "d97757", aiActions(),
             enc0: scrollEnc, enc1: undoEnc))

        list.append(make("ChatGPT", ["com.openai.chat"], "10a37f", aiActions(),
             enc0: scrollEnc, enc1: undoEnc))

        list.append(make("Photoshop", ["com.adobe.Photoshop"], "31a8ff", [
            1: k("Brush", kVK_ANSI_B, [], "B"),
            2: k("Eraser", kVK_ANSI_E, [], "E"),
            4: k("Move", kVK_ANSI_V, [], "V"),
            5: k("Selection", kVK_ANSI_M, [], "M"),
            6: k("Lasso", kVK_ANSI_L, [], "L"),
            7: k("Eyedropper", kVK_ANSI_I, [], "I"),
            8: k("Duplicate layer", kVK_ANSI_J, cmd, "J"),
            9: k("New layer", kVK_ANSI_N, [cmd, shift], "N"),
            10: k("Merge down", kVK_ANSI_E, cmd, "E"),
            11: k("Transform", kVK_ANSI_T, cmd, "T"),
            12: hand,
            13: undo,
            14: redo,
            15: k("Swap colors", kVK_ANSI_X, [], "X"),
            0: k("Fit", kVK_ANSI_0, cmd, "0"),
            3: k("Default colors", kVK_ANSI_D, [], "D"),
        ], enc0: EncoderSlot(left: k("Brush −", kVK_ANSI_LeftBracket, [], "["),
                             right: k("Brush +", kVK_ANSI_RightBracket, [], "]")),
           enc1: EncoderSlot(left: scroll("Zoom −", -1, opt), right: scroll("Zoom +", 1, opt))))

        list.append(make("Illustrator", ["com.adobe.illustrator"], "ff9a00", [
            1: k("Selection", kVK_ANSI_V, [], "V"),
            2: k("Direct sel.", kVK_ANSI_A, [], "A"),
            4: k("Pen", kVK_ANSI_P, [], "P"),
            5: k("Text", kVK_ANSI_T, [], "T"),
            6: k("Rectangle", kVK_ANSI_M, [], "M"),
            7: k("Ellipse", kVK_ANSI_L, [], "L"),
            8: k("Group", kVK_ANSI_G, cmd, "G"),
            9: k("Ungroup", kVK_ANSI_G, [cmd, shift], "G"),
            10: k("Outline", kVK_ANSI_Y, cmd, "Y"),
            11: k("Rulers", kVK_ANSI_R, cmd, "R"),
            12: hand,
            13: undo,
            14: redo,
            15: k("Artboard", kVK_ANSI_O, shift, "O"),
            0: k("Fit", kVK_ANSI_0, cmd, "0"),
            3: k("Panels", kVK_Tab, [], "⇥"),
        ], enc0: EncoderSlot(left: scroll("Zoom −", -1, opt), right: scroll("Zoom +", 1, opt)),
           enc1: undoEnc))

        list.append(make("Figma", ["com.figma.Desktop"], "a259ff", [
            1: k("Frame", kVK_ANSI_F, [], "F"),
            2: k("Rectangle", kVK_ANSI_R, [], "R"),
            4: k("Text", kVK_ANSI_T, [], "T"),
            5: k("Pen", kVK_ANSI_P, [], "P"),
            6: k("Move", kVK_ANSI_V, [], "V"),
            7: k("Auto layout", kVK_ANSI_A, shift, "A"),
            8: k("Component", kVK_ANSI_K, [cmd, opt], "K"),
            9: k("Duplicate", kVK_ANSI_D, cmd, "D"),
            10: k("Group", kVK_ANSI_G, cmd, "G"),
            11: k("Ungroup", kVK_ANSI_G, [cmd, shift], "G"),
            12: hand,
            13: undo,
            14: redo,
            15: k("Fit", kVK_ANSI_1, shift, "1"),
            0: k("Zoom 100%", kVK_ANSI_0, shift, "0"),
            3: k("Comments", kVK_ANSI_C, [], "C"),
        ], enc0: EncoderSlot(left: scroll("Zoom −", -1, cmd), right: scroll("Zoom +", 1, cmd)),
           enc1: undoEnc))

        list.append(make("Chrome", ["com.google.Chrome"], "ffd60a", [
            1: k("New tab", kVK_ANSI_T, cmd, "T"),
            2: k("Reopen tab", kVK_ANSI_T, [cmd, shift], "T"),
            4: k("Back", kVK_LeftArrow, cmd, "←"),
            5: k("Forward", kVK_RightArrow, cmd, "→"),
            6: k("Reload", kVK_ANSI_R, cmd, "R"),
            7: k("Close tab", kVK_ANSI_W, cmd, "W"),
            8: k("Address bar", kVK_ANSI_L, cmd, "L"),
            9: k("Search", kVK_ANSI_F, cmd, "F"),
            10: k("DevTools", kVK_ANSI_I, [cmd, opt], "I"),
            11: k("Bookmark", kVK_ANSI_D, cmd, "D"),
            13: k("New window", kVK_ANSI_N, cmd, "N"),
            14: k("Incognito", kVK_ANSI_N, [cmd, shift], "N"),
        ], enc0: EncoderSlot(left: k("Tab ←", kVK_Tab, [ctrl, shift], "⇥"),
                             right: k("Tab →", kVK_Tab, ctrl, "⇥")),
           enc1: scrollEnc))
        for i in list.indices where !Profile.chatAppIDs.isDisjoint(with: list[i].bundleIDs) {
            list[i].watchReplies = true
        }
        return list
    }
}
