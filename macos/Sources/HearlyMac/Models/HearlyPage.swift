enum HearlyPage: String, CaseIterable {
    case home = "Home", training = "Voice Training", history = "History", settings = "Settings"

    var icon: String {
        switch self {
        case .home: return "house"
        case .training: return "waveform"
        case .history: return "clock"
        case .settings: return "gearshape"
        }
    }
}
