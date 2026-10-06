import AppKit
import SwiftUI

@MainActor
final class HUDOverlayController {
    static let shared = HUDOverlayController()
    private var window: NSPanel?
    private var hideTask: Task<Void, Never>?

    func show(isActive: Bool) {
        hideTask?.cancel()

        let hudView = HUDView(isActive: isActive)
        let hostingView = NSHostingView(rootView: hudView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 320, height: 80)

        if window == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 320, height: 80),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.level = .floating
            panel.ignoresMouseEvents = true
            panel.collectionBehavior = [.canJoinAllSpaces, .transient]
            window = panel
        }

        guard let window else { return }
        window.contentView = hostingView

        if let screen = NSScreen.main {
            let screenRect = screen.visibleFrame
            let x = screenRect.midX - 160
            let y = screenRect.maxY - 120
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }

        window.orderFrontRegardless()

        hideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_300_000_000)
            guard !Task.isCancelled, let self else { return }
            self.window?.orderOut(nil)
        }
    }
}

private struct HUDView: View {
    let isActive: Bool

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(isActive ? HearlyColor.lime.opacity(0.18) : Color.white.opacity(0.08))
                    .frame(width: 44, height: 44)
                Image(systemName: isActive ? "waveform" : "waveform.slash")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(isActive ? HearlyColor.lime : Color.white.opacity(0.6))
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(isActive ? "Voice Focus Active" : "Voice Focus Muted")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    Circle()
                        .fill(isActive ? HearlyColor.lime : Color.gray)
                        .frame(width: 6, height: 6)
                }
                Text(isActive ? "Noise isolation & gating ON" : "Microphone on standby")
                    .font(.system(size: 12))
                    .foregroundStyle(HearlyColor.muted)
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(red: 0.08, green: 0.10, blue: 0.09).opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(isActive ? HearlyColor.lime.opacity(0.4) : Color.white.opacity(0.15), lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
