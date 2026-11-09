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
    static func walk(_ roots: [AXUIElement], limit: Int, deadline: Date, visit: (AXUIElement) -> Bool) {
        var queue = roots
        var index = 0
        while index < queue.count && index < limit {
            if index % 50 == 0 && Date() > deadline { return }
            let el = queue[index]
            index += 1
            if visit(el) { return }
            queue.append(contentsOf: children(el))
        }
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
    private var generating: [String: Bool] = [:]
    private var timer: Timer?

    private static let stopWords = ["stop", "interrompi", "ferma", "arresta", "annulla risposta"]

    var targets: [String] {
        get { lock.lock(); defer { lock.unlock() }; return _targets }
        set { lock.lock(); _targets = newValue; lock.unlock() }
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            let ids = self.targets
            let running = ids.compactMap { id in
                NSRunningApplication.runningApplications(withBundleIdentifier: id).first.map { (id, $0.processIdentifier) }
            }
            self.queue.async { self.tick(running) }
        }
    }

    private func tick(_ running: [(String, pid_t)]) {
        guard AXIsProcessTrusted() else { return }
        let runningIDs = Set(running.map { $0.0 })
        for id in generating.keys where !runningIDs.contains(id) { generating[id] = nil }

        for (id, pid) in running {
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, 0.3)
            // Electron apps (like Claude) only expose web content when asked to.
            AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)

            let busy = hasStopButton(app)
            if generating[id] == true && !busy {
                DispatchQueue.main.async { self.onReply?(id) }
            }
            generating[id] = busy
        }
    }

    private func hasStopButton(_ app: AXUIElement) -> Bool {
        var found = false
        AX.walk(AX.windows(app), limit: 8000, deadline: Date().addingTimeInterval(0.8)) { el in
            guard AX.string(el, kAXRoleAttribute as String) == (kAXButtonRole as String) else { return false }
            let label = [kAXDescriptionAttribute, kAXTitleAttribute, kAXHelpAttribute]
                .compactMap { AX.string(el, $0 as String) }
                .joined(separator: " ")
                .lowercased()
            if Self.stopWords.contains(where: { label.contains($0) }) {
                found = true
                return true
            }
            return false
        }
        return found
    }
}

// MARK: Notification banners

/// Reads notification banners as they appear on screen (macOS Notification Center).
final class NotificationWatcher {
    var onBanner: ((String) -> Void)?

    private let queue = DispatchQueue(label: "micropad.notifications", qos: .utility)
    private var visible: Set<String> = []
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
            self.queue.async { self.tick(pids) }
        }
    }

    private static let countRegex = try! NSRegularExpression(pattern: #"\((\d+)\)"#) // swiftlint:disable:this force_try

    private func tick(_ pids: [pid_t]) {
        guard AXIsProcessTrusted(), !pids.isEmpty else { return }
        var seen: [String: Int] = [:]
        var titles: [String: String] = [:]

        for pid in pids {
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, 0.3)
            for window in AX.windows(app) {
                for title in tabTitles(window) {
                    let range = NSRange(title.startIndex..., in: title)
                    guard let m = Self.countRegex.firstMatch(in: title, range: range),
                          let r = Range(m.range(at: 1), in: title), let n = Int(title[r]) else { continue }
                    // Key = title without the number, so the same tab is recognized.
                    let key = Self.countRegex.stringByReplacingMatches(in: title, range: range, withTemplate: "")
                    seen[key] = max(seen[key] ?? 0, n)
                    titles[key] = title
                }
            }
        }

        var increased: [String] = []
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
