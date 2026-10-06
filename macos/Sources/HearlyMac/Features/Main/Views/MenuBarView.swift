import AppKit
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var model: AppViewModel

    var body: some View {
        if model.meetingDetector.isMeetingActive {
            HStack {
                Image(systemName: "phone.fill")
                    .foregroundColor(HearlyColor.lime)
                Text("Meeting: \(model.meetingDetector.meetingPlatform ?? "Connected")")
            }
        }

        HStack {
            Image(systemName: model.audio.isRunning ? "waveform" : "waveform.slash")
            Text(model.audio.isRunning ? "Voice focus is live" : "Hearly is ready")
        }

        Button(model.audio.isRunning ? "Stop voice focus" : "Start voice focus") {
            model.toggleAudio()
        }

        Button("Open Hearly") {
            NotificationCenter.default.post(name: .showHearlyMainWindow, object: nil)
        }

        Divider()

        Menu("Microphone: \(model.selectedDeviceName)") {
            Button(action: { model.selectInputDevice(nil) }) {
                HStack {
                    Text("System Default")
                    if model.selectedInputDeviceID == nil {
                        Image(systemName: "checkmark")
                    }
                }
            }
            Divider()
            ForEach(model.inputDevices) { device in
                Button(action: { model.selectInputDevice(device.id) }) {
                    HStack {
                        Text(device.name)
                        if model.selectedInputDeviceID == device.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }

        if !model.isSignedIn {
            Button("Open local workspace") {
                model.useLocalWorkspace()
                NotificationCenter.default.post(name: .showHearlyMainWindow, object: nil)
            }
        }

        Button("Refresh devices") {
            model.refresh()
        }
        .keyboardShortcut("r")

        Button("Quit Hearly") {
            model.stopAudio()
            NSApplication.shared.terminate(nil)
        }
    }
}
