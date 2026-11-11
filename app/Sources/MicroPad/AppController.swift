import AppKit
import ApplicationServices
import Combine
import ServiceManagement

final class AppController: ObservableObject {
    let pad = PadDevice()
    let store = ProfileStore()
    let replyWatcher = ReplyWatcher()
    let notificationWatcher = NotificationWatcher()
    let tabWatcher = TabTitleWatcher()
    /// App menus read via Accessibility (bundle ID → groups), used by the shortcut picker.
    @Published var appMenus: [String: [MenuGroup]] = [:]
    @Published var loadingMenus: Set<String> = []
    private let menuQueue = DispatchQueue(label: "micropad.menus", qos: .userInitiated)

    @Published var connected = false
    @Published var activeProfileID: UUID?
    @Published var frontAppName = ""
    @Published var pressedKeys: Set<Int> = []
    /// Profile open in the editor and selected key.
    @Published var editingProfileID: UUID?
    @Published var selectedKey: Int? = 5
    @Published var accessibilityOK = AXIsProcessTrusted()
    /// Latest notification banners seen (to help set up alerts).
    @Published var recentBanners: [String] = []
    /// Key LEDs on/off.
    @Published var keyLEDs: Bool = UserDefaults.standard.object(forKey: "keyLEDs") as? Bool ?? true {
        didSet { UserDefaults.standard.set(keyLEDs, forKey: "keyLEDs"); pushLights(); onStatusChange?() }
    }
    /// Edge LEDs on when idle. Alerts flash regardless.
    @Published var edgeLEDs: Bool = UserDefaults.standard.object(forKey: "edgeLEDs") as? Bool ?? true {
        didSet { UserDefaults.standard.set(edgeLEDs, forKey: "edgeLEDs"); pushLights(); onStatusChange?() }
    }
    /// The bottom-right key shows the key map in every profile.
    @Published var overlayKey: Bool = UserDefaults.standard.object(forKey: "overlayKey") as? Bool ?? true {
        didSet { UserDefaults.standard.set(overlayKey, forKey: "overlayKey"); onStatusChange?() }
    }
    let overlay = OverlayController()
    private var overlayDownAt = Date.distantPast
    private var overlaySticky = false
    private var overlayIgnoreUp = false
    @Published var brightness: Double {
        didSet {
            UserDefaults.standard.set(brightness, forKey: "brightness")
            pad.setBrightness(UInt8(brightness))
        }
    }

    /// true when the MicroPad editor is in front: pad keys select instead of running actions.
    private(set) var editorIsFront = false
    private var held: [Int: PadAction] = [:]
    private var frontBundleID: String?
    private var cancellables = Set<AnyCancellable>()
    private var lastFlash: (color: RGB, at: Date)?
    // Edge LED (underglow) flashing, driven by the app.
    private var flashTimer: Timer?
    private var flashColor = RGB.off
    private var flashPhases = 0      // remaining phases; -1 = until a key is pressed
    private var flashOn = false
    private var holdAfter = false      // stay lit after blinking
    private var holdColor: RGB?        // pending alert: edge stays lit in this color
    /// Alert coming from a Chrome tab: keyword and unread count at alert time.
    private var pendingTab: (keyword: String, count: Int)?
    private var lastTabs: [(title: String, count: Int)] = []
    /// App whose "until pressed" flash also stops when you switch back to it.
    private var stickyBundle: String?

    var onStatusChange: (() -> Void)?

    init() {
        let saved = UserDefaults.standard.double(forKey: "brightness")
        brightness = saved > 0 ? saved : 150

        pad.onConnect = { [weak self] in
            guard let self else { return }
            self.connected = true
            Log.write("PAD connected")
            self.pad.setBrightness(UInt8(self.brightness))
            self.pushLights()
            self.flashUnderglow(self.shownProfile.color, phases: 2, period: 0.3) // hello
            self.onStatusChange?()
        }
        pad.onDisconnect = { [weak self] in
            self?.connected = false
            Log.write("PAD disconnected")
            self?.pressedKeys = []
            self?.held = [:]
            self?.flashTimer?.invalidate()
            self?.flashTimer = nil
            self?.onStatusChange?()
        }
        pad.onKey = { [weak self] i, down in self?.handleKey(i, down) }
        pad.onEncoder = { [weak self] i, cw in self?.handleEncoder(i, cw) }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            self?.frontChanged(note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
        }

        // Every edit shows up on the pad immediately.
        store.$profiles.dropFirst()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.pushLights(); self?.updateWatchTargets() } }
            .store(in: &cancellables)
        $editingProfileID.dropFirst()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.pushLights() } }
            .store(in: &cancellables)

        editingProfileID = store.profiles.first?.id
        frontChanged(NSWorkspace.shared.frontmostApplication)
        pad.start()

        replyWatcher.onReply = { [weak self] id in self?.replyReady(id) }
        notificationWatcher.onBanner = { [weak self] text in self?.bannerAppeared(text) }
        updateWatchTargets()
        replyWatcher.start()
        notificationWatcher.start()
        tabWatcher.onIncrease = { [weak self] title in self?.tabIncreased(title) }
        tabWatcher.onTick = { [weak self] tabs, active in self?.tabsUpdated(tabs, active: active) }
        tabWatcher.start()

        // Accessibility permission may be granted later: re-check periodically.
        Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            let ok = AXIsProcessTrusted()
            if self?.accessibilityOK != ok { self?.accessibilityOK = ok; self?.onStatusChange?() }
        }
    }

    // MARK: Active profile

    var activeProfile: Profile { store.profile(id: activeProfileID) ?? store.base }

    /// What the pad shows: the profile being edited if the editor is in front, otherwise the frontmost app's profile.
    var shownProfile: Profile {
        if editorIsFront, let p = store.profile(id: editingProfileID) { return p }
        return activeProfile
    }

    private func frontChanged(_ app: NSRunningApplication?) {
        if app?.bundleIdentifier == Bundle.main.bundleIdentifier {
            editorIsFront = true
        } else {
            editorIsFront = false
            frontBundleID = app?.bundleIdentifier
            frontAppName = app?.localizedName ?? ""
            activeProfileID = store.profile(for: frontBundleID).id
        }
        if let b = stickyBundle, b == app?.bundleIdentifier {
            stopFlash()
        }
        releaseAllHeld()
        pushLights()
        onStatusChange?()
    }

    /// Edge color when there is no alert.
    private var restingEdgeColor: RGB {
        if let h = holdColor { return h }
        return edgeLEDs ? shownProfile.color.dimmed(0.6) : .off
    }

    func pushLights() {
        guard connected else { return }
        let p = shownProfile
        pad.setKeyColors((0..<16).map { keyLEDs ? p.ledColor($0) : .off })
        if flashTimer == nil { pad.setUnderglow(restingEdgeColor) }
    }

    // MARK: Pad events

    private func handleKey(_ i: Int, _ down: Bool) {
        guard i >= 0 && i < 16 else { return }
        if down { pressedKeys.insert(i) } else { pressedKeys.remove(i) }
        if down && (holdColor != nil || (flashTimer != nil && holdAfter)) { stopFlash() }

        if editorIsFront {
            if down { selectedKey = i }
            return
        }
        if overlayKey && i == PadLayout.overlayKey {
            handleOverlayKey(down)
            return
        }
        if down {
            let a = activeProfile.keys[i].action
            Log.write("KEY \(i) down · profile=\(activeProfile.name) app=\(frontBundleID ?? "?") action=\(a.kind.rawValue) \(a.kind == .shortcut ? a.shortcutDescription : a.label) AX=\(AXIsProcessTrusted())")
            perform(a, holdKey: i)
        } else if let a = held.removeValue(forKey: i) {
            KeySender.release(a)
        }
    }

    private func handleEncoder(_ e: Int, _ clockwise: Bool) {
        guard e >= 0 && e < 2 else { return }
        if editorIsFront {
            selectedKey = PadLayout.keyFor(encoder: e)
            return
        }
        let slot = activeProfile.encoders[e]
        perform(clockwise ? slot.right : slot.left, holdKey: nil)
    }

    /// Key map: hold to peek; a short tap keeps it open until the next tap.
    private func handleOverlayKey(_ down: Bool) {
        if down {
            if overlay.isVisible && overlaySticky {
                overlay.hide()
                overlaySticky = false
                overlayIgnoreUp = true
            } else {
                overlayDownAt = Date()
                overlaySticky = false
                overlay.show(self)
                Log.write("KEYMAP shown · profile=\(activeProfile.name)")
            }
        } else {
            if overlayIgnoreUp { overlayIgnoreUp = false; return }
            if Date().timeIntervalSince(overlayDownAt) < 0.35 {
                overlaySticky = true
            } else {
                overlay.hide()
            }
        }
    }

    /// Runs an action. With holdKey, shortcuts stay pressed until the pad key is released
    /// (useful for Space = hand tool in Photoshop).
    func perform(_ a: PadAction, holdKey: Int?) {
        switch a.kind {
        case .none: break
        case .shortcut:
            if let k = holdKey {
                KeySender.press(a)
                held[k] = a
            } else {
                KeySender.tap(a)
            }
        case .menu:
            let path = a.menuPath
            if let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier {
                menuQueue.async { AppMenus.press(path: path, pid: pid) }
            }
        case .text: KeySender.type(a.text)
        case .url: KeySender.open(a.text)
        case .media: if let m = MediaKey(rawValue: a.text) { KeySender.media(m) }
        case .scroll: KeySender.scroll(a)
        }
    }

    private func releaseAllHeld() {
        for a in held.values { KeySender.release(a) }
        held = [:]
    }

    // MARK: External triggers (micropad://)

    /// micropad://flash?color=d97757&times=3&speed=200
    ///   color: hex (default: active profile color)
    ///   times: how many blinks; 0 = until a key is pressed (default 3)
    ///   speed: milliseconds per phase (default 200)
    func handleURL(_ url: URL) {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func q(_ name: String) -> String? { items.first(where: { $0.name == name })?.value }

        switch url.host {
        case "flash":
            let color = q("color").flatMap(RGB.init(hex:)) ?? activeProfile.color
            let times = q("times").flatMap(Int.init) ?? 3
            let speed = q("speed").flatMap(Int.init) ?? 200
            if times == 0 {
                flashUnderglow(color, phases: 6, period: Double(speed) / 1000, hold: true)
            } else {
                flashUnderglow(color, phases: times * 2, period: Double(speed) / 1000)
            }
        case "stop":
            stopFlash()
        default:
            break
        }
    }

    // MARK: App menus

    func isRunning(_ bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    /// Shortcuts for an app: curated list + every menu item that has a shortcut.
    func shortcutGroups(for bundleID: String) -> [LibraryGroup] {
        var groups = Library.groups(for: [bundleID])
        let known = Set(groups.flatMap { $0.items.map { $0.shortcutDescription } })
        for menu in appMenus[bundleID] ?? [] {
            let items = menu.entries
                .filter { !$0.shortcut.isEmpty && !known.contains($0.shortcut) }
                .map { e in
                    PadAction(kind: .menu, label: e.displayTitle, keyName: e.shortcut,
                              text: e.path.joined(separator: AppMenus.separator))
                }
            if !items.isEmpty { groups.append(LibraryGroup(title: "Menu " + menu.title, items: items)) }
        }
        return groups
    }

    /// Reads (or re-reads) the menus of a running app.
    func loadMenus(_ bundleID: String, force: Bool = false) {
        guard force || appMenus[bundleID] == nil, !loadingMenus.contains(bundleID),
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
        else { return }
        loadingMenus.insert(bundleID)
        let pid = app.processIdentifier
        menuQueue.async { [weak self] in
            let groups = AppMenus.read(pid: pid)
            DispatchQueue.main.async {
                self?.loadingMenus.remove(bundleID)
                if !groups.isEmpty { self?.appMenus[bundleID] = groups }
            }
        }
    }

    // MARK: Alerts

    private func updateWatchTargets() {
        replyWatcher.targets = store.profiles.filter { $0.watchReplies }.flatMap { $0.bundleIDs }
    }

    private func replyReady(_ bundleID: String) {
        Log.write("REPLY ready in \(bundleID)")
        let profile = store.profile(for: bundleID)
        let isFront = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID
        // If you're already looking at the app, two blinks are enough; otherwise flash until a key is pressed.
        alertFlash(profile.color, untilPressed: !isFront, bundle: bundleID)
    }

    private func bannerAppeared(_ text: String) {
        recentBanners.insert(text, at: 0)
        if recentBanners.count > 15 { recentBanners.removeLast() }
        Log.write("BANNER \(text) → rule: \(store.alerts.first(where: { $0.matches(text) })?.name ?? "none")")
        if let rule = store.alerts.first(where: { $0.matches(text) }) {
            alertFlash(rule.color, untilPressed: rule.untilPressed, bundle: nil)
        }
    }

    // MARK: Chrome tabs (Gmail…)

    private func totalCount(_ keyword: String, in tabs: [(title: String, count: Int)]) -> Int {
        tabs.filter { $0.title.localizedCaseInsensitiveContains(keyword) }.map(\.count).reduce(0, +)
    }

    private func tabIncreased(_ title: String) {
        bannerAppeared("Tab: " + title)
        if let rule = store.alerts.first(where: { $0.matches(title) }), rule.untilPressed,
           let kw = rule.matchedKeyword(title) {
            pendingTab = (kw, Self.count(title))
        }
    }

    private static func count(_ title: String) -> Int { TabTitleWatcher.count(in: title) }

    /// The alert clears when you open that tab or the unread count drops.
    private func tabsUpdated(_ tabs: [(title: String, count: Int)], active: String?) {
        lastTabs = tabs
        guard let p = pendingTab else { return }
        if let active, active.localizedCaseInsensitiveContains(p.keyword) {
            Log.write("ALERT read: tab \(p.keyword) opened")
            stopFlash()
        } else if totalCount(p.keyword, in: tabs) < p.count {
            Log.write("ALERT read: unread \(p.keyword) dropped")
            stopFlash()
        }
    }

    func alertFlash(_ color: RGB, untilPressed: Bool, bundle: String?) {
        // Avoid duplicates (e.g. reply ready + a notification from the same app).
        if let last = lastFlash, last.color == color, Date().timeIntervalSince(last.at) < 4 { return }
        lastFlash = (color, Date())
        Log.write("FLASH #\(color.hex) untilPressed=\(untilPressed) app=\(bundle ?? "-")")
        // Alerts to read: 3 blinks, then a steady edge; others: 2 blinks.
        flashUnderglow(color, phases: untilPressed ? 6 : 4, period: untilPressed ? 0.3 : 0.18, hold: untilPressed)
        stickyBundle = untilPressed ? bundle : nil
    }

    /// Flashes only the edge LEDs; keys keep their profile colors.
    func flashUnderglow(_ color: RGB, phases: Int, period: TimeInterval, hold: Bool = false) {
        flashTimer?.invalidate()
        holdAfter = hold
        holdColor = nil
        flashColor = color
        flashPhases = phases
        flashOn = false
        flashTimer = Timer.scheduledTimer(withTimeInterval: max(period, 0.05), repeats: true) { [weak self] _ in
            self?.flashStep()
        }
        flashStep()
    }

    private func flashStep() {
        if flashPhases == 0 {
            if holdAfter {
                flashTimer?.invalidate()
                flashTimer = nil
                holdColor = flashColor
                pad.setUnderglow(flashColor)
            } else {
                stopFlash()
            }
            return
        }
        flashOn.toggle()
        pad.setUnderglow(flashOn ? flashColor : .off)
        if flashPhases > 0 { flashPhases -= 1 }
    }

    func stopFlash() {
        flashTimer?.invalidate()
        flashTimer = nil
        holdColor = nil
        holdAfter = false
        pendingTab = nil
        pad.setUnderglow(restingEdgeColor)
        stickyBundle = nil
    }

    func testFlash() {
        flashUnderglow(RGB(hex: "d97757")!, phases: 6, period: 0.2)
    }

    // MARK: System

    func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        accessibilityOK = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("MicroPad: login item error \(error)")
            }
            objectWillChange.send()
            onStatusChange?()
        }
    }
}
