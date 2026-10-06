import SwiftUI

#Preview("Sign In") {
    RootView(model: AppViewModel(preview: true))
}

#Preview("App Shell") {
    ControlView(model: AppViewModel(preview: true))
}

#Preview("Settings") {
    SettingsView(model: AppViewModel(preview: true))
}
