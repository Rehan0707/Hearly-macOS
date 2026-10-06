import AppKit
import SwiftUI

/// Standalone visual-regression harness. Fixtures are memory-only: this does
/// not sign in, open the private database, or access the microphone.
@main
struct UISnapshots {
    @MainActor static func main() throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 2 else { fatalError("Pass an output directory") }
        let output = URL(fileURLWithPath: arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)
        let model = AppViewModel(preview: true)
        try render(SignInView(model: model), name: "login", directory: output)
        try render(ControlView(model: model), name: "home", directory: output)
        model.page = .training
        model.profileName = "rehan"
        try render(ControlView(model: model), name: "preparation", directory: output)
        model.trainingStep = 2
        try render(ControlView(model: model), name: "phrase-ready", directory: output)
        model.phraseCaptured = true
        try render(ControlView(model: model), name: "phrase-captured", directory: output)
        model.phraseIndex = 1
        model.phraseCaptured = false
        try render(ControlView(model: model), name: "phrase-two", directory: output)
        model.trainingStep = 3
        try render(ControlView(model: model), name: "enrollment-complete", directory: output)
        // A deliberately unusable embedding: the fixture is presentation-only.
        model.profile = VoiceProfile(name: "rehan", embedding: [], model: "ui-snapshot-only")
        model.page = .home
        try render(ControlView(model: model), name: "enrolled-home", directory: output)
        model.meetingDetector.simulateMeeting(active: true, platform: "Zoom")
        try render(ControlView(model: model), name: "meeting-active", directory: output)
        model.meetingDetector.simulateMeeting(active: false)
        model.isAuditionActive = true
        model.auditionFeed = .filtered
        model.isHeadphonesConnected = true
        try render(ControlView(model: model), name: "audition-filtered", directory: output)
        model.auditionFeed = .raw
        try render(ControlView(model: model), name: "audition-raw", directory: output)
        model.isAuditionActive = false
        model.inputDevices = [
            HearlyAudioDevice(id: 1, name: "MacBook Pro Microphone", uid: "builtin-mic"),
            HearlyAudioDevice(id: 2, name: "AirPods Pro", uid: "airpods-mic"),
            HearlyAudioDevice(id: 3, name: "Shure MV7 USB Microphone", uid: "shure-usb")
        ]
        model.selectedInputDeviceID = 2
        try render(ControlView(model: model), name: "mic-selected-airpods", directory: output)
        model.selectedInputDeviceID = nil
        model.page = .history
        try render(ControlView(model: model), name: "history", directory: output)
        model.page = .settings
        try render(ControlView(model: model), name: "settings", directory: output)
        print("Rendered memory-only UI fixtures to \(output.path)")
    }

    @MainActor private static func render<V: View>(_ view: V, name: String, directory: URL) throws {
        let root = ZStack { AmbientBackground(); view }
            .frame(width: 1440, height: 960).preferredColorScheme(.dark).tint(HearlyColor.lime)
        let hosting = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1440, height: 960), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        window.appearance = NSAppearance(named: .darkAqua)
        hosting.frame = NSRect(x: 0, y: 0, width: 1440, height: 960)
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { fatalError("No bitmap") }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("No PNG") }
        try png.write(to: directory.appendingPathComponent(name + ".png"))
        window.close()
    }
}
