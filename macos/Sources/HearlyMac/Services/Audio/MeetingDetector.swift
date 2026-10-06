import AppKit
import CoreAudio
import Foundation

@MainActor
final class MeetingDetector: ObservableObject {
    @Published private(set) var isMeetingActive = false
    @Published private(set) var meetingPlatform: String?

    var onMeetingStarted: ((String) -> Void)?
    var onMeetingEnded: (() -> Void)?

    private var monitoredDeviceID: AudioDeviceID?
    private var listenerBlock: AudioObjectPropertyListenerBlock?
    private var cooldownTask: Task<Void, Never>?
    private var pollTimer: Timer?

    private static let meetingApps: [String: String] = [
        "us.zoom.xos": "Zoom",
        "com.microsoft.teams2": "Microsoft Teams",
        "com.microsoft.teams": "Microsoft Teams",
        "com.google.Chrome": "Google Meet",
        "com.tinyspeck.slackmacgap": "Slack Huddle",
        "com.cisco.webexmeetingsapp": "Webex",
        "com.apple.FaceTime": "FaceTime"
    ]

    init() {
        startMonitoring()
    }

    isolated deinit {
        stopMonitoring()
    }

    func startMonitoring() {
        stopMonitoring()
        guard let deviceID = CoreAudioDeviceManager.hearlyVirtualMicrophoneID() else {
            pollTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.checkDeviceRegistration()
                }
            }
            return
        }
        attachListener(to: deviceID)
    }

    private func checkDeviceRegistration() {
        if let deviceID = CoreAudioDeviceManager.hearlyVirtualMicrophoneID() {
            pollTimer?.invalidate()
            pollTimer = nil
            attachListener(to: deviceID)
        }
    }

    private func attachListener(to deviceID: AudioDeviceID) {
        monitoredDeviceID = deviceID
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.handleDeviceRunningStateChanged()
            }
        }
        listenerBlock = block

        AudioObjectAddPropertyListenerBlock(deviceID, &address, DispatchQueue.main, block)
        handleDeviceRunningStateChanged()
    }

    func stopMonitoring() {
        pollTimer?.invalidate()
        pollTimer = nil
        cooldownTask?.cancel()
        cooldownTask = nil

        if let deviceID = monitoredDeviceID, let block = listenerBlock {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(deviceID, &address, DispatchQueue.main, block)
        }
        monitoredDeviceID = nil
        listenerBlock = nil
    }

    func refresh() {
        if monitoredDeviceID == nil || monitoredDeviceID != CoreAudioDeviceManager.hearlyVirtualMicrophoneID() {
            startMonitoring()
        } else {
            handleDeviceRunningStateChanged()
        }
    }

    private func handleDeviceRunningStateChanged() {
        guard let deviceID = monitoredDeviceID else { return }
        let running = CoreAudioDeviceManager.isDeviceRunningSomewhere(deviceID: deviceID)

        if running {
            cooldownTask?.cancel()
            cooldownTask = nil
            if !isMeetingActive {
                let platform = detectMeetingPlatform()
                isMeetingActive = true
                meetingPlatform = platform
                onMeetingStarted?(platform)
            }
        } else if isMeetingActive {
            // Apply a 6-second cooldown to prevent flickering when in-app mute is toggled
            guard cooldownTask == nil else { return }
            cooldownTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                guard !Task.isCancelled, let self else { return }
                guard let dev = self.monitoredDeviceID, !CoreAudioDeviceManager.isDeviceRunningSomewhere(deviceID: dev) else { return }
                self.isMeetingActive = false
                self.meetingPlatform = nil
                self.cooldownTask = nil
                self.onMeetingEnded?()
            }
        }
    }

    private func detectMeetingPlatform() -> String {
        let runningApps = NSWorkspace.shared.runningApplications
        for app in runningApps {
            if let bundleID = app.bundleIdentifier, let name = Self.meetingApps[bundleID] {
                return name
            }
        }
        return "Online Meeting"
    }

    func simulateMeeting(active: Bool, platform: String? = "Zoom") {
        isMeetingActive = active
        meetingPlatform = active ? platform : nil
    }
}
