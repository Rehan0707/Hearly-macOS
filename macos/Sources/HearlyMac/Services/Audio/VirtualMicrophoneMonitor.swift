import Foundation

enum VirtualMicrophoneStatus: Equatable {
    case installed
    case notInstalled

    var title: String {
        switch self {
        case .installed: return "Virtual microphone ready"
        case .notInstalled: return "Driver not installed"
        }
    }

    var detail: String {
        switch self {
        case .installed: return "Select Hearly Microphone in Meet, Zoom, or Teams."
        case .notInstalled: return "Build and install the signed HAL driver before joining a call."
        }
    }
}

@MainActor
final class VirtualMicrophoneMonitor: ObservableObject {
    @Published private(set) var status: VirtualMicrophoneStatus = .notInstalled

    func refresh() {
        status = CoreAudioDeviceManager.hasHearlyVirtualMicrophone() ? .installed : .notInstalled
    }
}
