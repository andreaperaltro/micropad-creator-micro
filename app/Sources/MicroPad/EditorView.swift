import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: Main window

struct EditorView: View {
    @EnvironmentObject var ctl: AppController
    @EnvironmentObject var store: ProfileStore
    @State private var showAlerts = false

    var body: some View {
        NavigationSplitView {
            List(selection: $ctl.editingProfileID) {
                ForEach(store.profiles) { p in
                    HStack(spacing: 8) {
                        Circle().fill(p.color.color).frame(width: 10, height: 10)
                        Text(p.name)
                        Spacer()
                        if p.id == ctl.activeProfileID {
                            Text("active").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .tag(p.id)
                    .contextMenu {
                        Button("Duplicate") { duplicate(p) }
                        if !p.isBase { Button("Delete", role: .destructive) { delete(p) } }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { sidebarFooter }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            if let id = ctl.editingProfileID, store.profile(id: id) != nil {
                ProfileEditor(profile: binding(for: id))
            } else {
                Text("Choose a profile").foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 960, minHeight: 620)
        .sheet(isPresented: $showAlerts) {
            AlertsView().environmentObject(store).environmentObject(ctl)
        }
    }

    private var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            HStack {
                Button { addProfile() } label: { Image(systemName: "plus") }
                    .help("New profile")
                Spacer()
                Button { showAlerts = true } label: { Image(systemName: "bell.badge") }
                    .help("Notification alerts")
                    .buttonStyle(.borderless)
                Menu {
                    Button("Notification alerts…") { showAlerts = true }
                    Button("Test flash") { ctl.testFlash() }
                    Toggle("Launch at login", isOn: Binding(get: { ctl.launchAtLogin },
                                                            set: { ctl.launchAtLogin = $0 }))
                    Divider()
                    Button("Show profiles in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([ProfileStore.fileURL])
                    }
                    Button("Reset to default profiles…") { store.resetToDefaults(); ctl.editingProfileID = store.profiles.first?.id }
                } label: { Image(systemName: "gearshape") }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
            }
            Toggle("Key LEDs", isOn: $ctl.keyLEDs)
                .toggleStyle(.switch).controlSize(.small)
            Toggle("Key map (bottom-right key)", isOn: $ctl.overlayKey)
                .toggleStyle(.switch).controlSize(.small)
            Toggle("Edge LEDs", isOn: $ctl.edgeLEDs)
                .toggleStyle(.switch).controlSize(.small)
                .help("Off when idle: alerts still make it flash.")
            HStack(spacing: 6) {
                Image(systemName: "sun.min")
                Slider(value: $ctl.brightness, in: 20...150)
                Image(systemName: "sun.max")
            }
            .foregroundStyle(.secondary)
            Label(ctl.connected ? "Pad connected" : "Pad not connected",
                  systemImage: ctl.connected ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(ctl.connected ? Color.green : Color.secondary)
                .font(.caption)
            if !ctl.accessibilityOK {
                Button("⚠︎ Accessibility permission needed") {
                    ctl.requestAccessibility(); ctl.openAccessibilitySettings()
                }
                .font(.caption)
                .buttonStyle(.link)
            }
        }
        .padding([.horizontal, .bottom], 12)
    }

    private func binding(for id: UUID) -> Binding<Profile> {
        Binding(
            get: { store.profile(id: id) ?? store.base },
            set: { new in
                if let i = store.profiles.firstIndex(where: { $0.id == new.id }) { store.profiles[i] = new }
            })
    }

    private func addProfile() {
        let p = Profile(name: "New profile", bundleIDs: [], color: RGB(hex: "4cc9f0")!)
        store.profiles.append(p)
        ctl.editingProfileID = p.id
    }

    private func duplicate(_ p: Profile) {
        var copy = p
        copy.id = UUID()
        copy.name = p.name + " copy"
        copy.bundleIDs = []
        copy.isBase = false
        store.profiles.append(copy)
        ctl.editingProfileID = copy.id
    }

    private func delete(_ p: Profile) {
        store.profiles.removeAll { $0.id == p.id }
        ctl.editingProfileID = store.profiles.first?.id
    }
}

// MARK: Profile editor

struct ProfileEditor: View {
    @Binding var profile: Profile
    @EnvironmentObject var ctl: AppController

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 18) {
                header
                AppsRow(profile: $profile)
                if !profile.isBase {
                    Toggle(isOn: $profile.watchReplies) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Flash when a reply is ready")
                            Text("For chat apps (Claude, ChatGPT…): the edge LEDs flash in the profile color when a reply is finished.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                }
                Spacer(minLength: 0)
                HStack {
                    Spacer()
                    PadView(profile: profile, selected: ctl.selectedKey, pressed: ctl.pressedKeys,
                            overrides: ctl.overlayKey ? [PadLayout.overlayKey: "Key map"] : [:]) { i in
                        ctl.selectedKey = i
                    }
                    Spacer()
                }
                Text("Tip: with this window in front, press a key or turn an encoder on the pad to select it.")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(minWidth: 480)

            ScrollView {
                if let k = ctl.selectedKey {
                    KeyInspector(profile: $profile, index: k).padding(20)
                }
            }
            .frame(minWidth: 320, idealWidth: 340, maxWidth: 420)
        }
        .task(id: profile.id) { profile.bundleIDs.forEach { ctl.loadMenus($0) } }
    }

    private var header: some View {
        HStack(spacing: 12) {
            TextField("Profile name", text: $profile.name)
                .textFieldStyle(.plain)
                .font(.title2.weight(.semibold))
            ColorPicker("Color", selection: Binding(get: { profile.color.color },
                                                     set: { profile.color = RGB($0) }),
                        supportsOpacity: false)
                .fixedSize()
        }
    }
}

// MARK: Profile apps

struct AppsRow: View {
    @Binding var profile: Profile

    var body: some View {
        if profile.isBase {
            Text("Base profile: used for every app that has no profile of its own.")
                .font(.callout).foregroundStyle(.secondary)
        } else {
            HStack(spacing: 8) {
                Text("Active in:").font(.callout).foregroundStyle(.secondary)
                ForEach(profile.bundleIDs, id: \.self) { id in
                    HStack(spacing: 4) {
                        if let icon = AppInfo.icon(id) {
                            Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                        }
                        Text(AppInfo.name(id)).font(.callout)
                        Button { profile.bundleIDs.removeAll { $0 == id } } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(Color.secondary.opacity(0.12)))
                }
                Menu {
                    ForEach(AppInfo.runningApps(), id: \.bundleIdentifier) { app in
                        Button(app.localizedName ?? app.bundleIdentifier ?? "?") {
                            if let id = app.bundleIdentifier, !profile.bundleIDs.contains(id) {
                                profile.bundleIDs.append(id)
                            }
                        }
                    }
                    Divider()
                    Button("Choose from Applications folder…") {
                        if let id = AppInfo.pickApp(), !profile.bundleIDs.contains(id) {
                            profile.bundleIDs.append(id)
                        }
                    }
                } label: { Label("Add app", systemImage: "plus") }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
            }
        }
    }
}

enum AppInfo {
    static func url(_ id: String) -> URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) }

    static func name(_ id: String) -> String {
        guard let u = url(id) else { return id }
        return FileManager.default.displayName(atPath: u.path).replacingOccurrences(of: ".app", with: "")
    }

    static func icon(_ id: String) -> NSImage? {
        guard let u = url(id) else { return nil }
        return NSWorkspace.shared.icon(forFile: u.path)
    }

    static func runningApps() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil
                && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    static func pickApp() -> String? {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let u = panel.url else { return nil }
        return Bundle(url: u)?.bundleIdentifier
    }
}

// MARK: Pad drawing

struct PadView: View {
    let profile: Profile
    let selected: Int?
    let pressed: Set<Int>
    /// Forced labels for some keys (e.g. the key map key).
    var overrides: [Int: String] = [:]
    let onSelect: (Int) -> Void

    private let unit: CGFloat = 78
    private let keySize: CGFloat = 68

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 22)
                .fill(Color(white: 0.13))
                .frame(width: unit * 4.5 + 24, height: unit * 4.5 + 24)
            ForEach(0..<16, id: \.self) { i in
                keyView(i)
                    .offset(x: 12 + PadLayout.positions[i].x * unit,
                            y: 12 + PadLayout.positions[i].y * unit)
            }
        }
        .frame(width: unit * 4.5 + 24, height: unit * 4.5 + 24, alignment: .topLeading)
    }

    @ViewBuilder
    private func keyView(_ i: Int) -> some View {
        let isCorner = PadLayout.corners.contains(i)
        let isEncoder = PadLayout.encoderFor(key: i) != nil
        let action = profile.keys[i].action
        let fill: Color = isCorner ? Color(white: 0.25) : profile.ledColor(i).color
        // Light text on dark (or unlit) keys, dark text on light keys.
        let lightText = isCorner || action.kind == .none || !profile.ledColor(i).isLight
        let size = isCorner ? keySize * 0.8 : keySize
        let shape = RoundedRectangle(cornerRadius: isEncoder ? size / 2 : (isCorner ? size / 2 : 10))

        ZStack {
            shape.fill(fill.opacity(action.kind == .none && !isCorner ? 0.25 : 1))
            if pressed.contains(i) { shape.fill(Color.white.opacity(0.55)) }
            if isEncoder {
                Image(systemName: "arrow.left.and.right.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.6))
                    .offset(y: -size / 2 + 12)
            }
            Text(overrides[i] ?? action.displayText)
                .font(.system(size: 10, weight: .semibold))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.7)
                .foregroundStyle(lightText ? Color.white : Color.black.opacity(0.85))
                .padding(4)
            shape.stroke(selected == i ? Color.accentColor : Color.clear, lineWidth: 3)
        }
        .frame(width: size, height: size)
        .padding(isCorner ? (keySize - size) / 2 : 0)
        .scaleEffect(pressed.contains(i) ? 0.93 : 1)
        .animation(.easeOut(duration: 0.08), value: pressed.contains(i))
        .contentShape(Rectangle())
        .onTapGesture { onSelect(i) }
        .help(PadLayout.name(i))
    }
}

// MARK: Selected key inspector

struct KeyInspector: View {
    @Binding var profile: Profile
    let index: Int
    @EnvironmentObject var ctl: AppController

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(PadLayout.name(index)).font(.title3.weight(.semibold))

            if index == PadLayout.overlayKey && ctl.overlayKey {
                GroupBox("Key map") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("In every profile this key shows the command map for the current app: hold it to peek, or tap it to keep the map open (tap again to close).")
                            .font(.callout).fixedSize(horizontal: false, vertical: true)
                        Toggle("Use this key for the key map", isOn: $ctl.overlayKey)
                    }
                    .padding(6)
                }
            } else {
                GroupBox(PadLayout.encoderFor(key: index) != nil ? "Click" : "Press") {
                    ActionEditor(action: $profile.keys[index].action, apps: profile.bundleIDs)
                        .padding(6)
                }
                if index == PadLayout.overlayKey {
                    Toggle("Use this key for the key map", isOn: $ctl.overlayKey)
                }
            }

            if !PadLayout.corners.contains(index) {
                GroupBox("Key color") {
                    VStack(alignment: .leading) {
                        Toggle("Custom color", isOn: Binding(
                            get: { profile.keys[index].color != nil },
                            set: { profile.keys[index].color = $0 ? profile.color : nil }))
                        if let c = profile.keys[index].color {
                            ColorPicker("Color", selection: Binding(
                                get: { c.color },
                                set: { profile.keys[index].color = RGB($0) }), supportsOpacity: false)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                }
            }

            if let e = PadLayout.encoderFor(key: index) {
                GroupBox("Turn left ↺") {
                    ActionEditor(action: $profile.encoders[e].left, apps: profile.bundleIDs).padding(6)
                }
                GroupBox("Turn right ↻") {
                    ActionEditor(action: $profile.encoders[e].right, apps: profile.bundleIDs).padding(6)
                }
            }
        }
    }
}

struct ActionEditor: View {
    @Binding var action: PadAction
    let apps: [String]
    @EnvironmentObject var ctl: AppController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // What the key does now
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(action.kind == .none ? "No command" : (action.label.isEmpty ? action.displayText : action.label))
                        .font(.headline)
                    if !summary.isEmpty {
                        Text(summary).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            CommandPicker(action: $action, apps: apps)

            // Details only for custom commands
            switch action.kind {
            case .none, .menu, .media:
                EmptyView()
            case .shortcut:
                ShortcutRecorder(action: $action)
            case .text:
                TextField("Text to type", text: $action.text, axis: .vertical)
                    .lineLimit(3...8)
            case .url:
                TextField("https://… or /Applications/App.app", text: $action.text)
            case .scroll:
                Stepper("Lines: \(action.amount)", value: $action.amount, in: -20...20)
                Toggle("Horizontal", isOn: $action.horizontal)
                ModifierToggles(action: $action)
            }

            if action.kind != .none {
                TextField("Key label (optional)", text: $action.label)
                    .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { apps.forEach { ctl.loadMenus($0) } }
    }

    private var summary: String {
        switch action.kind {
        case .none: return "Pick a command below."
        case .shortcut: return "Shortcut " + action.shortcutDescription
        case .menu: return action.keyName.isEmpty ? "App command" : "Shortcut " + action.keyName
        case .text: return "Types text"
        case .url: return "Opens " + action.text
        case .media: return "Media key"
        case .scroll: return "Scroll"
        }
    }
}

/// Button that opens the shortcut list, plus custom options.
struct CommandPicker: View {
    @Binding var action: PadAction
    let apps: [String]
    @EnvironmentObject var ctl: AppController
    @State private var showBrowser = false

    var body: some View {
        HStack {
            Button {
                showBrowser = true
            } label: {
                Label("Choose shortcut…", systemImage: "keyboard")
            }
            .controlSize(.large)
            .popover(isPresented: $showBrowser, arrowEdge: .leading) {
                ShortcutBrowser(apps: apps) { picked in
                    action = picked
                    showBrowser = false
                }
                .environmentObject(ctl)
            }

            Menu {
                Button("Record a shortcut manually…") { set(.shortcut) }
                Button("Type text…") { set(.text) }
                Button("Open a link or app…") { set(.url) }
                Button("Scroll / zoom…") { set(.scroll) }
                Divider()
                Button("No command") { action = .none }
            } label: {
                Text("More")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private func set(_ kind: ActionKind) {
        var a = PadAction(kind: kind)
        if kind == .scroll { a.amount = 3 }
        action = a
    }
}

/// Searchable shortcut list per app.
struct ShortcutBrowser: View {
    let apps: [String]
    let onPick: (PadAction) -> Void
    @EnvironmentObject var ctl: AppController
    @State private var source: String = ""
    @State private var query = ""

    private var sources: [String] { apps + ["mac"] }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("", selection: $source) {
                ForEach(sources, id: \.self) { id in
                    Text(id == "mac" ? "Mac" : AppInfo.name(id)).tag(id)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            TextField("Search (e.g. layer, zoom, new)…", text: $query)
                .textFieldStyle(.roundedBorder)

            List {
                ForEach(filteredGroups) { group in
                    Section(group.title) {
                        ForEach(Array(group.items.enumerated()), id: \.offset) { item in
                            ShortcutRow(action: item.element)
                                .contentShape(Rectangle())
                                .onTapGesture { onPick(item.element) }
                        }
                    }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))

            footer
        }
        .padding(14)
        .frame(width: 440, height: 520)
        .onAppear {
            if source.isEmpty { source = sources.first ?? "mac" }
            apps.forEach { ctl.loadMenus($0) }
        }
    }

    @ViewBuilder
    private var footer: some View {
        if source != "mac" {
            if ctl.loadingMenus.contains(source) {
                Text("Reading \(AppInfo.name(source)) shortcuts…").font(.caption).foregroundStyle(.secondary)
            } else if ctl.appMenus[source] == nil {
                Text("Open \(AppInfo.name(source)) to see all its shortcuts, then reopen this list.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var groups: [LibraryGroup] {
        source == "mac" ? Library.macGroups : ctl.shortcutGroups(for: source)
    }

    private var filteredGroups: [LibraryGroup] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return groups }
        return groups.compactMap { g in
            let items = g.items.filter {
                $0.label.localizedCaseInsensitiveContains(q) || g.title.localizedCaseInsensitiveContains(q)
            }
            return items.isEmpty ? nil : LibraryGroup(title: g.title, items: items)
        }
    }
}

struct ShortcutRow: View {
    let action: PadAction

    var body: some View {
        HStack {
            Text(action.label)
            Spacer()
            if !keys.isEmpty {
                Text(keys)
                    .font(.system(.callout, design: .rounded).weight(.medium))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.secondary.opacity(0.15)))
            }
        }
        .padding(.vertical, 2)
    }

    private var keys: String {
        switch action.kind {
        case .shortcut: return action.shortcutDescription
        case .menu: return action.keyName
        case .scroll: return action.modifierFlags.contains(.command) ? "⌘ scroll"
            : (action.modifierFlags.contains(.option) ? "⌥ scroll" : "scroll")
        default: return ""
        }
    }
}

struct ModifierToggles: View {
    @Binding var action: PadAction
    private let mods: [(String, NSEvent.ModifierFlags)] = [("⌃", .control), ("⌥", .option), ("⇧", .shift), ("⌘", .command)]

    var body: some View {
        HStack {
            ForEach(0..<mods.count, id: \.self) { i in
                let symbol = mods[i].0
                let flag = mods[i].1
                Toggle(symbol, isOn: Binding(
                    get: { action.modifierFlags.contains(flag) },
                    set: { on in
                        var m = action.modifierFlags
                        if on { m.insert(flag) } else { m.remove(flag) }
                        action.modifiers = m.rawValue
                    }))
                .toggleStyle(.button)
            }
        }
    }
}

struct ShortcutRecorder: View {
    @Binding var action: PadAction
    @State private var recording = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    recording ? stop() : start()
                } label: {
                    Text(recording ? "Press the key combination…" : (action.keyName.isEmpty ? "Record shortcut" : action.shortcutDescription))
                        .font(.system(.body, design: .rounded).weight(.medium))
                        .frame(minWidth: 160)
                }
                .controlSize(.large)
                if recording {
                    Button("Cancel") { stop() }.buttonStyle(.link)
                }
            }
            if !action.keyName.isEmpty {
                ModifierToggles(action: $action)
                Text("You can also toggle the modifier keys by hand.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        KeyCapture.shared.start { code, mods, name in
            var a = action
            a.keyCode = code
            a.modifiers = mods.rawValue
            a.keyName = name
            action = a
            recording = false
        }
    }

    private func stop() {
        KeyCapture.shared.stop()
        recording = false
    }
}

/// Captures the next key combination system-wide, before any app receives it,
/// so global hotkeys of other apps (e.g. ChatGPT's ⇧⌘D) can be recorded too.
final class KeyCapture {
    static let shared = KeyCapture()

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var localMonitor: Any?
    private var handler: ((UInt16, NSEvent.ModifierFlags, String) -> Void)?

    func start(_ handler: @escaping (UInt16, NSEvent.ModifierFlags, String) -> Void) {
        stop()
        self.handler = handler

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: CGEventTapCallBack = { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let me = Unmanaged<KeyCapture>.fromOpaque(context).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let t = me.tap { CGEvent.tapEnable(tap: t, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            guard type == .keyDown else { return Unmanaged.passUnretained(event) }
            let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            let name = NSEvent(cgEvent: event).map { KeyNames.current(for: $0) } ?? KeyNames.name(for: code)
            me.finish(code: code, flags: event.flags, name: name)
            return nil // the key never reaches any app
        }

        for location in [CGEventTapLocation.cghidEventTap, .cgSessionEventTap] {
            if let t = CGEvent.tapCreate(tap: location, place: .headInsertEventTap, options: .defaultTap,
                                         eventsOfInterest: mask, callback: callback, userInfo: context) {
                tap = t
                break
            }
        }

        if let tap {
            source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        } else {
            // Without Accessibility permission: capture only inside the MicroPad window.
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
                guard let self, let cg = event.cgEvent else { return event }
                self.finish(code: event.keyCode, flags: cg.flags, name: KeyNames.current(for: event))
                return nil
            }
        }
    }

    private func finish(code: UInt16, flags: CGEventFlags, name: String) {
        var mods: NSEvent.ModifierFlags = []
        if flags.contains(.maskCommand) { mods.insert(.command) }
        if flags.contains(.maskAlternate) { mods.insert(.option) }
        if flags.contains(.maskShift) { mods.insert(.shift) }
        if flags.contains(.maskControl) { mods.insert(.control) }
        let h = handler
        DispatchQueue.main.async {
            self.stop()
            h?(code, mods, name)
        }
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let m = localMonitor { NSEvent.removeMonitor(m) }
        tap = nil
        source = nil
        localMonitor = nil
        handler = nil
    }
}

// MARK: Notification alerts

struct AlertsView: View {
    @EnvironmentObject var store: ProfileStore
    @EnvironmentObject var ctl: AppController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Notification alerts").font(.title2.weight(.semibold))
            Text("When a notification banner or a Chrome tab title contains one of these words, the edge LEDs flash. Notifications for the app (or the site in Chrome) must be enabled with the Banner style.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(store.alerts) { rule in
                AlertRow(rule: binding(for: rule.id)) {
                    store.alerts.removeAll { $0.id == rule.id }
                }
            }
            Button {
                store.alerts.append(AlertRule(name: "New alert", keywords: "", color: RGB(hex: "4cc9f0")!))
            } label: { Label("Add alert", systemImage: "plus") }

            Divider()
            Text("Recently seen notifications").font(.headline)
            Text("Copy words from here to use in your alerts.")
                .font(.caption).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if ctl.recentBanners.isEmpty {
                        Text("None yet: notifications show up here as they arrive.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(Array(ctl.recentBanners.enumerated()), id: \.offset) { item in
                        Text(item.element)
                            .font(.caption)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(height: 140)

            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 760)
    }

    private func binding(for id: UUID) -> Binding<AlertRule> {
        Binding(
            get: { store.alerts.first(where: { $0.id == id }) ?? AlertRule(name: "", keywords: "", color: .off) },
            set: { new in
                if let i = store.alerts.firstIndex(where: { $0.id == id }) { store.alerts[i] = new }
            })
    }
}

struct AlertRow: View {
    @Binding var rule: AlertRule
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: $rule.enabled).labelsHidden()
            TextField("Name", text: $rule.name).frame(width: 120)
            TextField("words, comma separated", text: $rule.keywords)
            ColorPicker("", selection: Binding(get: { rule.color.color }, set: { rule.color = RGB($0) }),
                        supportsOpacity: false)
                .labelsHidden()
            Toggle("until I press a key", isOn: $rule.untilPressed)
            Button(action: onDelete) { Image(systemName: "trash") }
                .buttonStyle(.borderless)
        }
    }
}
