import AppKit
import ApplicationServices

// MARK: Accessibility tree helpers

enum AX {
    static func attr(_ el: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        return AXUIElementCopyAttributeValue(el, name as CFString, &value) == .success ? value : nil
    }

    static func string(_ el: AXUIElement, _ name: String) -> String? {
        attr(el, name) as? String
    }

    static func children(_ el: AXUIElement) -> [AXUIElement] {
        (attr(el, kAXChildrenAttribute as String) as? [AXUIElement]) ?? []
    }

    static func windows(_ app: AXUIElement) -> [AXUIElement] {
        (attr(app, kAXWindowsAttribute as String) as? [AXUIElement]) ?? []
    }

    static func size(_ el: AXUIElement) -> CGSize? {
        guard let v = attr(el, kAXSizeAttribute as String), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        // swiftlint:disable:next force_cast
        AXValueGetValue(v as! AXValue, .cgSize, &size)
        return size
    }

    /// Breadth-first walk; `visit` returns true to stop.
    /// reversed: visits the last children first (useful for elements at the bottom of a page).
    /// Returns true if the whole tree was visited (not cut short by limit, deadline or `visit`).
    @discardableResult
    static func walk(_ roots: [AXUIElement], limit: Int, deadline: Date, reversed: Bool = false,
                     visit: (AXUIElement) -> Bool) -> Bool {
        var queue = roots
        var index = 0
        while index < queue.count {
            if index >= limit { return false }
            if index % 50 == 0 && Date() > deadline { return false }
            let el = queue[index]
            index += 1
            if visit(el) { return false }
            let kids = children(el)
            queue.append(contentsOf: reversed ? kids.reversed() : kids)
        }
        return true
    }

    static func parent(_ el: AXUIElement) -> AXUIElement? {
        guard let p = attr(el, kAXParentAttribute as String) else { return nil }
        return (p as! AXUIElement) // swiftlint:disable:this force_cast
    }
}

// MARK: Reply ready (Claude, ChatGPT…)

/// Polls chat apps: while writing a reply they show a
/// "Stop" button. When that button disappears, the reply is ready. Stop words include localized labels.
final class ReplyWatcher {
    var onReply: ((String) -> Void)?

    private let queue = DispatchQueue(label: "micropad.replies", qos: .utility)
    private let lock = NSLock()
    private var _targets: [String] = []
    private var _lastSwitch = Date.distantPast
    private var generating: [String: Bool] = [:]
    private var idleStreak: [String: Int] = [:]
    private var timer: Timer?

    /// Labels that start with one of these are "stop generating" buttons
    /// (English and Italian UIs: "Stop response", "Interrompi la risposta"…).
    private static let stopWords = ["stop", "interrompi", "ferma"]
    /// …unless they're about dictation or recording ("Stop dictation", "Arresta dettatura").
    private static let excludedWords = ["dettatura", "dictation", "registrazione", "recording", "vocale", "voice",
                                        "caricamento", "loading", "download"]
    /// Buttons that appear next to the chat input once a reply is done
    /// ("Send message", "Retry", "Start voice mode"…): positive proof the reply finished.
    private static let doneWords = ["invia", "send", "riprova", "retry", "rigenera", "regenerate",
                                    "avvia la modalità vocale", "start voice", "use voice"]
    /// Seconds after an app or desktop switch during which "reply finished" is not trusted:
    /// apps briefly stop exposing their UI while they're being switched away from.
    private static let switchGrace: TimeInterval = 1.5
    /// Without positive proof: consecutive "no Stop button" checks needed (0.5 s apart).
    private static let idleChecksNeeded = 3
    /// Check interval while a reply is being written, and otherwise.
    private static let fastInterval: TimeInterval = 0.5
    private static let slowEvery = 3 // slow checks = every 3rd fast tick (1.5 s)
    private var tickCount = 0

    var targets: [String] {
        get { lock.lock(); defer { lock.unlock() }; return _targets }
        set { lock.lock(); _targets = newValue; lock.unlock() }
    }

    /// Call on every app activation (including desktop switches).
    func noteAppSwitch() {
        lock.lock(); _lastSwitch = Date(); lock.unlock()
    }

    private var lastSwitch: Date {
        lock.lock(); defer { lock.unlock() }; return _lastSwitch
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: Self.fastInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            let ids = self.targets
            let running = ids.compactMap { id in
                NSRunningApplication.runningApplications(withBundleIdentifier: id).first.map { (id, $0.processIdentifier) }
            }
            let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            // Skip this round if the previous check is still running (scans can take ~1 s).
            self.lock.lock()
            let busy = self.ticking
            self.ticking = true
            self.lock.unlock()
            guard !busy else { return }
            self.queue.async {
                self.tick(running, front: front)
                self.lock.lock(); self.ticking = false; self.lock.unlock()
            }
        }
    }

    private var ticking = false

    // Per app: the Stop button last found and the area around the chat input. Watching these
    // directly also works when the app sits on another desktop, where its windows aren't listed.
    private var stopElement: [String: AXUIElement] = [:]
    private var inputArea: [String: AXUIElement] = [:]
    /// Last time a check could actually see the app (Stop present or surely absent).
    private var lastConclusive: [String: Date] = [:]

    private func tick(_ running: [(String, pid_t)], front: String?) {
        guard AXIsProcessTrusted() else { return }
        let runningIDs = Set(running.map { $0.0 })
        for id in generating.keys where !runningIDs.contains(id) {
            generating[id] = nil
            idleStreak[id] = nil
        }
        let recentlySwitched = Date().timeIntervalSince(lastSwitch) < Self.switchGrace
        tickCount += 1
        let slowTick = tickCount % Self.slowEvery == 0

        for (id, pid) in running {
            // Apps that are writing are checked every tick, the others every 1.5 s.
            guard generating[id] == true || slowTick else { continue }
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, 0.3)
            // Electron apps (like Claude) only expose web content when asked to.
            AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)

            let wasVisibleAt = lastConclusive[id] ?? .distantPast
            let scan = hasStopButton(app, id: id)
            if scan.stop != nil || scan.done { lastConclusive[id] = Date() }

            // Reply finished: alert, unless we only found out now that you're back on the app
            // after not being able to see it (you're already looking at the answer).
            func finished(_ how: String) {
                generating[id] = false
                idleStreak[id] = 0
                stopElement[id] = nil
                inputArea[id] = nil
                let blind = Date().timeIntervalSince(wasVisibleAt) > 3
                if front == id && blind {
                    Log.write("REPLY \(id) writing=false (\(how)) — no alert: app was not visible until now")
                } else {
                    Log.write("REPLY \(id) writing=false (\(how))")
                    DispatchQueue.main.async { self.onReply?(id) }
                }
            }

            if scan.stop != true, scan.done, generating[id] == true, !recentlySwitched {
                finished("done button visible")
                continue
            }
            switch scan.stop {
            case .some(true):
                if generating[id] != true { Log.write("REPLY \(id) writing=true") }
                generating[id] = true
                idleStreak[id] = 0
            case .some(false) where generating[id] == true && !recentlySwitched:
                let n = (idleStreak[id] ?? 0) + 1
                idleStreak[id] = n
                if n >= Self.idleChecksNeeded {
                    finished("confirmed \(n)x")
                }
            case .some(false):
                if generating[id] == nil { generating[id] = false }
                if recentlySwitched { idleStreak[id] = 0 }
            case .none:
                // Couldn't see the whole window: no conclusion either way.
                break
            }
        }
    }

    private var lastDump: [String: Date] = [:]
    private var loggedStopLabels: Set<String> = []

    private func buttonLabel(_ el: AXUIElement) -> String? {
        guard AX.string(el, kAXRoleAttribute as String) == (kAXButtonRole as String) else { return nil }
        let label = [kAXDescriptionAttribute, kAXTitleAttribute, kAXHelpAttribute]
            .compactMap { AX.string(el, $0 as String) }
            .joined(separator: " ")
        return label
    }

    /// Only labels that start with the word, so chat titles in the sidebar aren't mistaken
    /// for the button; dictation/recording buttons are excluded.
    private func isStop(_ label: String) -> Bool {
        let l = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard Self.stopWords.contains(where: { l.hasPrefix($0) }),
              !Self.excludedWords.contains(where: { l.contains($0) }) else { return false }
        if !loggedStopLabels.contains(l) {
            loggedStopLabels.insert(l)
            Log.write("REPLY stop button found: \"\(label)\"")
        }
        return true
    }

    private func isDone(_ label: String) -> Bool {
        let l = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return Self.doneWords.contains(where: { l.hasPrefix($0) })
    }

    /// stop: true = Stop button visible, false = surely not there, nil = couldn't tell.
    /// done: a "reply finished" button (Send, Retry…) was seen near the input.
    /// The Stop button sits next to the text field: start from the focused element
    /// and walk up; if needed, scan the window starting from the bottom.
    private func hasStopButton(_ app: AXUIElement, id: String) -> (stop: Bool?, done: Bool) {
        var found = false
        var foundElement: AXUIElement?
        var done = false
        var seen: [String] = []
        let check: (AXUIElement) -> Bool = { el in
            guard let label = self.buttonLabel(el) else { return false }
            if !label.isEmpty && seen.count < 40 && !seen.contains(label) { seen.append(label) }
            if self.isStop(label) { found = true; foundElement = el; return true }
            if self.isDone(label) { done = true }
            return false
        }

        // 1. The Stop button we already know about: still there and still "Stop"?
        if let el = stopElement[id], let label = buttonLabel(el), isStop(label) {
            return (true, false)
        }
        // 2. The area around the chat input: look inside it (works on other desktops too).
        if let area = inputArea[id], AX.string(area, kAXRoleAttribute as String) != nil {
            let whole = AX.walk([area], limit: 3000, deadline: Date().addingTimeInterval(0.4), reversed: true, visit: check)
            if found {
                stopElement[id] = foundElement
                return (true, false)
            }
            if whole { return (false, done) }
        }

        if let focusedObj = AX.attr(app, kAXFocusedUIElementAttribute as String) {
            var node: AXUIElement? = (focusedObj as! AXUIElement) // swiftlint:disable:this force_cast
            for _ in 0..<6 {
                guard let n = node, !found else { break }
                AX.walk([n], limit: 1500, deadline: Date().addingTimeInterval(0.3), reversed: true, visit: check)
                node = AX.parent(n)
            }
        }
        var complete = false
        if !found {
            // Windows on the current desktop, plus the main/focused window wherever it is.
            var roots = AX.windows(app)
            for attr in [kAXMainWindowAttribute, kAXFocusedWindowAttribute] {
                if let w = AX.attr(app, attr as String), CFGetTypeID(w) == AXUIElementGetTypeID() {
                    let win = w as! AXUIElement // swiftlint:disable:this force_cast
                    if !roots.contains(where: { CFEqual($0, win) }) { roots.append(win) }
                }
            }
            complete = !roots.isEmpty && AX.walk(roots, limit: 30000, deadline: Date().addingTimeInterval(1.2),
                                                  reversed: true, visit: check)
        }
        if found, let el = foundElement {
            stopElement[id] = el
            var area = el
            for _ in 0..<4 { if let p = AX.parent(area) { area = p } }
            inputArea[id] = area
        }

        // Every 30 s, log the buttons seen, to learn how the Stop button is labeled.
        let key = "\(found)"
        if Date().timeIntervalSince(lastDump[key] ?? .distantPast) > 30 {
            lastDump[key] = Date()
            Log.write("REPLY buttons seen (stop=\(found), complete=\(complete)): \(seen.joined(separator: " | "))")
        }
        if found { return (true, false) }
        return (complete ? false : nil, done)
    }
}

// MARK: Notification banners

/// Reads notification banners as they appear on screen (macOS Notification Center).
final class NotificationWatcher {
    var onBanner: ((String) -> Void)?

    private let queue = DispatchQueue(label: "micropad.notifications", qos: .utility)
    private var visible: Set<String> = []
    private var firstTick = true
    private var timer: Timer?

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] _ in
            guard let self,
                  let nc = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.notificationcenterui").first
            else { return }
            let pid = nc.processIdentifier
            self.queue.async { self.tick(pid) }
        }
    }

    private func tick(_ pid: pid_t) {
        guard AXIsProcessTrusted() else { return }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)

        var current: Set<String> = []
        for window in AX.windows(app) {
            // The full Notification Center panel is tall: skip it, we only want banners.
            if let size = AX.size(window), size.height > 600 { continue }
            for banner in bannerTexts(in: window) { current.insert(banner) }
        }

        let new = current.subtracting(visible)
        visible = current
        // On the first pass, ignore what's already on screen (widgets, old banners).
        if firstTick { firstTick = false; return }
        for t in new { Log.write("NOTIFICATION seen: \(t)") }
        guard !new.isEmpty else { return }
        DispatchQueue.main.async {
            for text in new { self.onBanner?(text) }
        }
    }

    /// One text per banner: groups with a notification subrole, or the whole window.
    private func bannerTexts(in window: AXUIElement) -> [String] {
        var banners: [AXUIElement] = []
        AX.walk([window], limit: 400, deadline: Date().addingTimeInterval(0.3)) { el in
            let subrole = AX.string(el, kAXSubroleAttribute as String) ?? ""
            if subrole.contains("Notification") { banners.append(el) }
            return false
        }
        let roots = banners.isEmpty ? [window] : banners
        return roots.map(text(of:)).filter { !$0.isEmpty }
    }

    private func text(of root: AXUIElement) -> String {
        var parts: [String] = []
        AX.walk([root], limit: 200, deadline: Date().addingTimeInterval(0.2)) { el in
            for name in [kAXDescriptionAttribute, kAXTitleAttribute, kAXValueAttribute] {
                if let s = AX.string(el, name as String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !s.isEmpty, !parts.contains(s) {
                    parts.append(s)
                }
            }
            return false
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: Chrome tab titles

/// Many sites show unread counts in the tab title, e.g. "Inbox (3) - Gmail".
/// When that number grows, the title is reported as if it were a notification.
/// Works without enabling notifications: just keep the tab open (even in the background).
final class TabTitleWatcher {
    var onIncrease: ((String) -> Void)?
    /// On every pass: all tabs (title, number in parentheses or 0) and the title
    /// of the active tab if Chrome is frontmost.
    var onTick: (([(title: String, count: Int)], String?) -> Void)?
    var bundleIDs = ["com.google.Chrome"]

    private let queue = DispatchQueue(label: "micropad.tabs", qos: .utility)
    private var counts: [String: Int] = [:]
    private var timer: Timer?

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            guard let self else { return }
            let pids = self.bundleIDs.flatMap {
                NSRunningApplication.runningApplications(withBundleIdentifier: $0).map(\.processIdentifier)
            }
            let front = NSWorkspace.shared.frontmostApplication
            let frontPid = self.bundleIDs.contains(front?.bundleIdentifier ?? "") ? front?.processIdentifier : nil
            self.queue.async { self.tick(pids, frontPid: frontPid) }
        }
    }

    private static let countRegex = try! NSRegularExpression(pattern: #"\((\d+)\)"#) // swiftlint:disable:this force_try
    // Chrome adds changing info to titles (memory usage, "Pinned"): strip it from the key.
    private static let noiseRegex = try! NSRegularExpression( // swiftlint:disable:this force_try
        pattern: #"\s*-\s*(Memoria utilizzata|Memory usage)[^-]*|\s*-\s*(Fissata|Pinned)\b|\d+([.,]\d+)?\s*(MB|GB|KB)"#,
        options: [.caseInsensitive])

    static func cleanKey(_ title: String) -> String {
        var s = title
        for re in [countRegex, noiseRegex] {
            s = re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
        }
        return s.trimmingCharacters(in: .whitespaces)
    }

    static func count(in title: String) -> Int {
        let range = NSRange(title.startIndex..., in: title)
        guard let m = countRegex.firstMatch(in: title, range: range),
              let r = Range(m.range(at: 1), in: title) else { return 0 }
        return Int(title[r]) ?? 0
    }

    private func tick(_ pids: [pid_t], frontPid: pid_t?) {
        guard AXIsProcessTrusted(), !pids.isEmpty else { return }
        var seen: [String: Int] = [:]
        var titles: [String: String] = [:]
        var all: [(title: String, count: Int)] = []
        var activeTitle: String?

        for pid in pids {
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, 0.3)
            if pid == frontPid, let wObj = AX.attr(app, kAXFocusedWindowAttribute as String) {
                activeTitle = AX.string(wObj as! AXUIElement, kAXTitleAttribute as String) // swiftlint:disable:this force_cast
            }
            for window in AX.windows(app) {
                for title in tabTitles(window) {
                    let n = Self.count(in: title)
                    all.append((title, n))
                    guard n > 0 else { continue }
                    // Key = title without the number or changing info, so the same tab is recognized.
                    let key = Self.cleanKey(title)
                    seen[key] = max(seen[key] ?? 0, n)
                    titles[key] = title
                }
            }
        }
        DispatchQueue.main.async { self.onTick?(all, activeTitle) }

        var increased: [String] = []
        if Set(seen.keys) != Set(counts.keys) { Log.write("TABS with counter: \(seen.map { "\($0.key)=\($0.value)" }.joined(separator: " | "))") }
        for (key, n) in seen {
            if let old = counts[key], n > old, let t = titles[key] { increased.append(t) }
        }
        counts = seen
        guard !increased.isEmpty else { return }
        DispatchQueue.main.async {
            for t in increased { self.onIncrease?(t) }
        }
    }

    private func tabTitles(_ window: AXUIElement) -> [String] {
        var out: [String] = []
        AX.walk([window], limit: 1500, deadline: Date().addingTimeInterval(0.5)) { el in
            let role = AX.string(el, kAXRoleAttribute as String) ?? ""
            if role == (kAXTabGroupRole as String) {
                for tab in AX.children(el) {
                    if let t = AX.string(tab, kAXTitleAttribute as String) ?? AX.string(tab, kAXDescriptionAttribute as String),
                       !t.isEmpty { out.append(t) }
                }
            }
            return false
        }
        // If tabs aren't exposed, fall back to the window title (active tab).
        if out.isEmpty, let t = AX.string(window, kAXTitleAttribute as String) { out.append(t) }
        return out
    }
}
