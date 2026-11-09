# MicroPad

**A new brain for the Work Louder Creator Micro: custom QMK firmware + a native macOS app that makes the pad follow whatever app you're using.**

The Creator Micro ships with four layers that you switch by hand, so you always have to remember which one is active. MicroPad flips that around. The pad becomes a simple input/output device, and a small menu bar app on your Mac decides what every key does based on the app in front. Switch from Photoshop to Figma and the pad follows by itself: new commands, new colors.

> Unofficial community project. Not affiliated with or endorsed by Work Louder.

---

## Features

- **Per-app profiles, switched automatically.** Ready-made profiles for Claude, ChatGPT, Photoshop, Illustrator, Figma and Chrome, plus a Base profile for every other app. Add as many profiles as you want; you're not limited to 4 layers.
- **Per-key RGB colors.** Each profile has its own color, and any key can override it, so you can tell at a glance which profile is active.
- **Visual editor.** The pad is drawn on screen. Click a key, or just press it on the real pad, then pick a command. Changes show up on the pad instantly, with no reflashing.
- **Searchable shortcut library.** For each app you get a curated list (tools, layers, chat commands…) plus every shortcut the app declares in its own menus, read live via Accessibility.
- **Custom actions.** A key can send any shortcut (the recorder captures even global hotkeys like `⇧⌘D`), type text or prompts, open a URL or an app, press a menu item, scroll or zoom, or control media and volume. Keys stay held while you hold the pad key, so things like Space for the Photoshop hand tool work.
- **Two encoders.** Separate actions for left/right rotation and click, per profile (brush size, zoom, undo/redo, tab switching…).
- **Notifications on the edge LEDs.** The underglow flashes in the profile color when:
  - **Claude or ChatGPT finishes a reply.** The app finds the "Stop" button next to the chat input (English or Italian UI) and flashes when it disappears.
  - **Gmail gets new mail.** The app watches the unread count in the Chrome tab title.
  - **A macOS notification banner matches your keywords**, in a color you pick.
  - **Anything else triggers it** through the `micropad://` URL scheme, for example Claude Code hooks, scripts or Shortcuts.

  Keys keep their colors, so the edge color tells you where the alert came from.
- **LED controls.** Turn key LEDs and edge LEDs on or off. With edge LEDs off, alerts still flash.
- **Safe fallback.** If the app isn't running, after 3 seconds the pad goes back to being a normal keyboard with generic Mac shortcuts.

## How it works

```
 ┌────────────────────┐   Raw HID (32-byte reports)   ┌──────────────────────────┐
 │  Creator Micro     │  ── key 7 down / enc 1 cw ──▶ │  MicroPad.app (menu bar) │
 │  QMK "micropad"    │                               │  · which app is in front?│
 │  keymap            │  ◀── colors / underglow ───── │  · profile → action      │
 └────────────────────┘                               │  · CGEvent / AX actions  │
                                                      └──────────────────────────┘
```

- **Firmware** (`firmware/micropad`): a QMK keymap for `work_louder/micro`. While the app is connected (heartbeat every second), keys and encoders send raw events over QMK's Raw HID channel (usage page `0xFF60`) instead of keycodes, and LEDs show whatever colors the app sends. If the heartbeat stops for 3 s, the regular keymap takes over.
- **App** (`app/`): a Swift Package (AppKit + SwiftUI, macOS 13+). It runs in the menu bar, starts at login, wakes up when the pad is plugged in, and maps events to actions for the frontmost app.

### Raw HID protocol

| Direction | Byte 0 | Payload |
|---|---|---|
| Pad → Mac | `0x01` key | `[1]` index 0–15 (row×4+col), `[2]` 1 = down / 0 = up |
| Pad → Mac | `0x02` encoder | `[1]` encoder 0–1, `[2]` 1 = clockwise / 0 = counter-clockwise |
| Pad → Mac | `0x03` hello | `[1]` protocol version |
| Mac → Pad | `0x10` ping | heartbeat; the pad answers with hello |
| Mac → Pad | `0x11` release | the app is quitting, so return to standalone mode now |
| Mac → Pad | `0x20` key colors | `[1]` first index, `[2]` count (≤ 9), then r,g,b per key |
| Mac → Pad | `0x21` fill | r,g,b for all keys |
| Mac → Pad | `0x22` flash | r,g,b, times (0 = until a key is pressed), phase length in 10 ms |
| Mac → Pad | `0x23` brightness | 0–150 |
| Mac → Pad | `0x24` indicators | bitmask for the 3 small LEDs |
| Mac → Pad | `0x25` underglow | r,g,b |

## Requirements

- A Work Louder **Creator Micro** (the atmega32u4 version supported by QMK as `work_louder/micro`)
- macOS 13 Ventura or later
- [Homebrew](https://brew.sh), used to install QMK
- Apple Command Line Tools (`xcode-select --install`). Full Xcode is not needed.

## Installation

The installers are double-clickable `.command` scripts. Each one also writes a log file next to itself.

### 1. Flash the firmware

```bash
./install-firmware.command
```

The script:
1. Installs QMK via Homebrew. Recent Homebrew versions require trusting the `qmk/qmk`, `osx-cross/avr` and `osx-cross/arm` taps, and the script does this for you.
2. Falls back to a Python venv in `~/.micropad-qmk` if Homebrew's `qmk` binary is broken.
3. Runs `qmk setup` and copies the keymap into `~/qmk_firmware`.
4. Compiles and flashes.

When it asks, put the pad in bootloader mode: **unplug it, hold the top-left encoder, plug it back in.** Or press the reset button on the back of the PCB.

There's also a prebuilt `firmware/prebuilt/work_louder_micro_micropad.hex`. You can flash it with [QMK Toolbox](https://github.com/qmk/qmk_toolbox) (bootloader: `atmel-dfu`).

### 2. Build and install the app

```bash
./install-app.command
```

It builds with `swift build -c release` (build files go to `~/Library/Caches`, not the repo), creates `/Applications/MicroPad.app`, signs it ad hoc and launches it. Your configuration is backed up first.

On first launch, grant **Accessibility** permission (System Settings → Privacy & Security → Accessibility). MicroPad needs it to send shortcuts and read app menus. The app is ad-hoc signed, so every rebuild needs the permission again; the installer resets the old entry so you only have to flip the switch.

### 3. (Optional) Claude Code integration

```bash
./connect-claude-code.command
```

This adds hooks to `~/.claude/settings.json`. The pad flashes orange when Claude Code finishes, and yellow when it needs your permission.

## Usage

- **Menu bar icon:** a filled grid means the pad is connected. The menu shows the active profile and has the LED toggles, *Test flash* and *Launch at login*.
- **Editor** (*Open editor…*): profiles on the left, the pad in the middle, the selected key on the right.
  - **Choose shortcut…** opens the searchable library for the profile's apps and for macOS.
  - **More** records a shortcut by hand, types text, opens a link or app, or sets up scroll/zoom.
  - **Encoders** (the top corners) have click, left and right actions.
  - **Profile apps:** add them from running apps or from `/Applications`.
- **Alerts** (bell icon): keyword rules for notification banners and tab titles. The window lists the latest banners the app has seen, so you can copy the exact words.

### Flash from anywhere

```bash
open -g "micropad://flash?color=d97757&times=0&speed=350"   # until a key is pressed
open -g "micropad://flash?color=10a37f&times=3"              # three blinks
open -g "micropad://stop"
```

## Configuration files

- `~/Library/Application Support/MicroPad/profiles.json`: profiles, keys, encoders, colors
- `~/Library/Application Support/MicroPad/alerts.json`: notification rules
- `~/Library/Logs/MicroPad/micropad.log`: diagnostic log of key presses, actions, reply detection and alerts (capped at about 1 MB)

Both are plain JSON. Updating the app never overwrites them, and newer versions read files written by older ones.

## Project structure

```
firmware/micropad/       QMK keymap (keymap.c, config.h, rules.mk)
firmware/prebuilt/       ready-to-flash .hex
app/Package.swift        Swift Package
app/Info.plist           bundle info (menu bar app, micropad:// URL scheme)
app/Sources/MicroPad/
  PadDevice.swift        IOKit Raw HID connection + protocol
  AppController.swift    profiles ↔ frontmost app, actions, alerts, LEDs
  KeySender.swift        CGEvent shortcuts, typing, scroll, media keys
  AppMenus.swift         reads / presses app menu items via Accessibility
  Watchers.swift         reply watcher, notification banners, Chrome tab titles
  Log.swift              diagnostic log
  Library.swift          curated shortcut lists per app
  Defaults.swift         default profiles
  Model.swift            data model (profiles, actions, alert rules, pad layout)
  ProfileStore.swift     JSON persistence
  EditorView.swift       SwiftUI editor
  AppDelegate.swift      menu bar item, URL handling, windows
```

## Known limitations

- **Keyboard layouts:** curated shortcuts use physical key positions, so a few (like `[` `]` for brush size in Photoshop) can differ on non-US layouts. Re-record them in the editor, or pick the command from the app's own shortcut list.
- **Reply detection:** it relies on the label of the Stop button (for example "Stop response" or "Interrompi la risposta"). If an app changes it, check the diagnostic log, which records the buttons it sees, and add the new label to `stopWords` in `Watchers.swift`.
- **Pressed-key highlight:** in the current firmware a pressed key briefly lights white, even with key LEDs turned off.
- **Firmware size:** it uses about 93 % of the atmega32u4's flash. `config.h` lists RGB animations you can disable if you need room.
- **Firmware variants:** only the QMK-supported atmega32u4 Creator Micro is targeted.

## Credits

- [QMK Firmware](https://qmk.fm) and the `work_louder/micro` keyboard definition by Drashna Jael're
- [Work Louder](https://worklouder.cc) for the Creator Micro hardware

## License

GPL-2.0, the same license as QMK. See [LICENSE](LICENSE).
