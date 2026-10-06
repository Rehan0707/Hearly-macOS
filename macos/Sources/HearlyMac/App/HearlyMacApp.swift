import SwiftUI

@main
struct HearlyMacApp: App {
    @NSApplicationDelegateAdaptor(HearlyAppDelegate.self) private var appDelegate
    @StateObject private var model = AppViewModel.shared

    var body: some Scene {
        MenuBarExtra("Hearly", systemImage: "waveform") {
            MenuBarView(model: model)
        }

        Settings {
            SettingsView(model: model)
        }
    }
}
