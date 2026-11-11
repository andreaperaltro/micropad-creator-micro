import AppKit
import SwiftUI

/// "Key map" panel: shows the active profile's commands above all windows.
/// It never takes focus, so the frontmost app stays the one you're working in.
final class OverlayController {
    private var panel: NSPanel?
    private(set) var isVisible = false

    func show(_ controller: AppController) {
        if panel == nil {
            let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 600, height: 560),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
            p.level = .statusBar
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = true
            p.ignoresMouseEvents = true
            p.hidesOnDeactivate = false
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            let host = NSHostingView(rootView: OverlayView().environmentObject(controller))
            p.contentView = host
            panel = p
        }
        guard let panel else { return }
        if let host = panel.contentView {
            let size = host.fittingSize
            panel.setContentSize(size)
            // Bottom center of the screen the pointer is on.
            let mouse = NSEvent.mouseLocation
            let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
            if let f = screen?.visibleFrame {
                panel.setFrameOrigin(NSPoint(x: f.midX - size.width / 2, y: f.minY + 60))
            }
        }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 1
        }
        isVisible = true
    }

    func hide() {
        guard let panel, isVisible else { return }
        isVisible = false
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: {
            if !self.isVisible { panel.orderOut(nil) }
        })
    }
}

struct OverlayView: View {
    @EnvironmentObject var ctl: AppController

    var body: some View {
        let profile = ctl.activeProfile
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                if let id = profile.bundleIDs.first, let icon = AppInfo.icon(id) {
                    Image(nsImage: icon).resizable().frame(width: 28, height: 28)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(profile.name).font(.title3.weight(.semibold))
                    Text(ctl.frontAppName).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Circle().fill(profile.color.color).frame(width: 12, height: 12)
            }

            PadView(profile: profile, selected: nil, pressed: ctl.pressedKeys,
                    overrides: ctl.overlayKey ? [PadLayout.overlayKey: "Key map"] : [:]) { _ in }

            VStack(alignment: .leading, spacing: 4) {
                encoderRow("Left encoder", profile.encoders[0])
                encoderRow("Right encoder", profile.encoders[1])
            }
            .font(.callout)
        }
        .padding(20)
        .frame(width: 420)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.white.opacity(0.12)))
        .environment(\.colorScheme, .dark)
    }

    private func encoderRow(_ title: String, _ e: EncoderSlot) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
            Text("↺ " + (e.left.kind == .none ? "—" : e.left.displayText))
            Text("·").foregroundStyle(.secondary)
            Text("↻ " + (e.right.kind == .none ? "—" : e.right.displayText))
        }
        .lineLimit(1)
    }
}
