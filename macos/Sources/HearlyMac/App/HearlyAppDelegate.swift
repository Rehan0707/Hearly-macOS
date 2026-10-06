import AppKit
import SwiftUI

extension Notification.Name {
    static let showHearlyMainWindow = Notification.Name("showHearlyMainWindow")
}

@MainActor
final class HearlyAppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        if let iconURL = Bundle.main.url(forResource: "HearlyLogo", withExtension: "png")
            ?? Bundle.main.url(forResource: "HearlyAppIcon", withExtension: "png")
            ?? Bundle.main.url(forResource: "Hearly", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = icon
        }
        if CommandLine.arguments.contains("--local-workspace") {
            AppViewModel.shared.useLocalWorkspace()
        }
        NotificationCenter.default.addObserver(
            forName: .showHearlyMainWindow,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.showMainWindow()
            }
        }
        showMainWindow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showMainWindow()
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppViewModel.shared.stopAudio()
    }

    func showMainWindow() {
        if let mainWindow {
            mainWindow.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        let hostingController = NSHostingController(rootView: RootView(model: AppViewModel.shared))
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Hearly"
        window.identifier = NSUserInterfaceItemIdentifier("live.hearely.main")
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.setContentSize(NSSize(width: 1200, height: 800))
        window.contentAspectRatio = NSSize(width: 3, height: 2)
        window.minSize = NSSize(width: 1050, height: 700)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = NSColor(red: 0.035, green: 0.035, blue: 0.04, alpha: 1)
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        mainWindow = window
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
