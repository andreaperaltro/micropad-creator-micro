import Foundation
import IOKit.hid

/// Raw HID communication with the Creator Micro ("micropad" firmware).
final class PadDevice {
    static let vendorID = 0x574C
    static let productID = 0xE6E3
    static let rawUsagePage = 0xFF60
    static let rawUsage = 0x61
    static let reportSize = 32

    enum Cmd {
        static let ping: UInt8 = 0x10
        static let release: UInt8 = 0x11
        static let keyColors: UInt8 = 0x20
        static let fill: UInt8 = 0x21
        static let flash: UInt8 = 0x22
        static let brightness: UInt8 = 0x23
        static let indicators: UInt8 = 0x24
        static let underglow: UInt8 = 0x25
    }

    var onConnect: (() -> Void)?
    var onDisconnect: (() -> Void)?
    var onKey: ((Int, Bool) -> Void)?
    var onEncoder: ((Int, Bool) -> Void)?

    private let manager: IOHIDManager
    private var device: IOHIDDevice?
    private let inputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
    private var heartbeat: Timer?

    var isConnected: Bool { device != nil }

    init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    func start() {
        let matching: [String: Any] = [
            kIOHIDVendorIDKey: Self.vendorID,
            kIOHIDProductIDKey: Self.productID,
            kIOHIDPrimaryUsagePageKey: Self.rawUsagePage,
            kIOHIDPrimaryUsageKey: Self.rawUsage,
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            guard let context else { return }
            Unmanaged<PadDevice>.fromOpaque(context).takeUnretainedValue().attach(device)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            guard let context else { return }
            Unmanaged<PadDevice>.fromOpaque(context).takeUnretainedValue().detach(device)
        }, context)

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    // MARK: Connection

    private func attach(_ dev: IOHIDDevice) {
        guard device == nil else { return }
        device = dev
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(dev, inputBuffer, 64, { context, _, _, _, _, report, length in
            guard let context else { return }
            let bytes = Array(UnsafeBufferPointer(start: report, count: Int(length)))
            Unmanaged<PadDevice>.fromOpaque(context).takeUnretainedValue().handle(bytes)
        }, context)

        send([Cmd.ping])
        heartbeat?.invalidate()
        heartbeat = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.send([Cmd.ping])
        }
        onConnect?()
    }

    private func detach(_ dev: IOHIDDevice) {
        guard let current = device, CFEqual(current, dev) else { return }
        device = nil
        heartbeat?.invalidate()
        heartbeat = nil
        onDisconnect?()
    }

    private func handle(_ data: [UInt8]) {
        guard data.count >= 3 else { return }
        switch data[0] {
        case 0x01: onKey?(Int(data[1]), data[2] == 1)
        case 0x02: onEncoder?(Int(data[1]), data[2] == 1)
        default: break
        }
    }

    // MARK: Sending

    func send(_ bytes: [UInt8]) {
        guard let dev = device else { return }
        var report = [UInt8](repeating: 0, count: Self.reportSize)
        for (i, b) in bytes.prefix(Self.reportSize).enumerated() { report[i] = b }
        _ = IOHIDDeviceSetReport(dev, kIOHIDReportTypeOutput, 0, report, report.count)
    }

    /// 16 colors, one per position (row*4+col).
    func setKeyColors(_ colors: [RGB]) {
        var index = 0
        while index < colors.count {
            let chunk = Array(colors[index..<min(index + 9, colors.count)])
            var packet: [UInt8] = [Cmd.keyColors, UInt8(index), UInt8(chunk.count)]
            for c in chunk { packet += [c.r, c.g, c.b] }
            send(packet)
            index += 9
        }
    }

    func setUnderglow(_ c: RGB) { send([Cmd.underglow, c.r, c.g, c.b]) }

    func setBrightness(_ value: UInt8) { send([Cmd.brightness, value]) }

    /// times = 0: flash until a key is pressed. period in milliseconds per phase.
    func flash(_ c: RGB, times: Int, periodMs: Int) {
        send([Cmd.flash, c.r, c.g, c.b, UInt8(clamping: times), UInt8(clamping: periodMs / 10)])
    }

    /// Call on quit: the pad switches back to its standalone keymap right away.
    func release() { send([Cmd.release]) }
}
