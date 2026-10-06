import CoreAudio
import Foundation

struct HearlyAudioDevice: Identifiable, Hashable {
    let id: UInt32
    let name: String
    let uid: String

    var identifier: UInt32 { id }
}

enum CoreAudioDeviceManager {
    static func inputDevices() -> [HearlyAudioDevice] {
        let devices = allDevices()
        return devices.filter { !$0.name.localizedCaseInsensitiveContains("Hearly Microphone") && $0.uid != "live.hearely.virtual-mic" && hasInputChannels(deviceID: AudioDeviceID($0.id)) }
    }

    static func hasHearlyVirtualMicrophone() -> Bool {
        allDevices().contains { device in
            device.uid == "live.hearely.virtual-mic" || device.name.localizedCaseInsensitiveContains("Hearly Microphone")
        }
    }

    static func hearlyVirtualMicrophoneID() -> AudioDeviceID? {
        allDevices().first { device in
            device.uid == "live.hearely.virtual-mic" || device.name.localizedCaseInsensitiveContains("Hearly Microphone")
        }.map { AudioDeviceID($0.id) }
    }

    static func isDeviceRunningSomewhere(deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var isRunning: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &isRunning)
        return status == noErr && isRunning != 0
    }

    private static func allDevices() -> [HearlyAudioDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var byteCount: UInt32 = 0
        let systemObject = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(systemObject, &address, 0, nil, &byteCount) == noErr else {
            return []
        }

        let deviceCount = Int(byteCount) / MemoryLayout<AudioDeviceID>.stride
        var deviceIDs = Array(repeating: AudioDeviceID(0), count: deviceCount)
        let status = deviceIDs.withUnsafeMutableBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return OSStatus(-1) }
            return AudioObjectGetPropertyData(systemObject, &address, 0, nil, &byteCount, baseAddress)
        }
        guard status == noErr else { return [] }

        return deviceIDs.map { deviceID in
            HearlyAudioDevice(
                id: UInt32(deviceID),
                name: stringProperty(deviceID: deviceID, selector: kAudioObjectPropertyName) ?? "Unnamed device",
                uid: stringProperty(deviceID: deviceID, selector: kAudioDevicePropertyDeviceUID) ?? "device-\(deviceID)"
            )
        }
    }

    private static func hasInputChannels(deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var byteCount: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &byteCount) == noErr else {
            return false
        }

        let rawBuffer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(byteCount),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { rawBuffer.deallocate() }
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &byteCount, rawBuffer) == noErr else {
            return false
        }

        let bufferList = UnsafeMutableAudioBufferListPointer(rawBuffer.assumingMemoryBound(to: AudioBufferList.self))
        return bufferList.reduce(0) { partialResult, buffer in
            partialResult + Int(buffer.mNumberChannels)
        } > 0
    }

    private static func stringProperty(deviceID: AudioDeviceID, selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var byteCount = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &byteCount, pointer)
        }
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    static func defaultOutputDeviceName() -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var defaultOutput = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &defaultOutput) == noErr else {
            return "Built-in Output"
        }
        return stringProperty(deviceID: defaultOutput, selector: kAudioDevicePropertyDeviceNameCFString) ?? "Built-in Output"
    }

    static func defaultInputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var defaultInput = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &defaultInput) == noErr else {
            return nil
        }
        return defaultInput
    }

    static func defaultInputDeviceName() -> String {
        guard let id = defaultInputDeviceID() else { return "Default Microphone" }
        return stringProperty(deviceID: id, selector: kAudioDevicePropertyDeviceNameCFString) ?? "Default Microphone"
    }

    static func isHeadphonesConnected() -> Bool {
        let name = defaultOutputDeviceName().lowercased()
        return name.contains("headphone") || name.contains("airpod") || name.contains("buds") ||
               name.contains("earphone") || name.contains("earpiece") || name.contains("pro") ||
               name.contains("bose") || name.contains("sony") || name.contains("wh-") || name.contains("wf-")
    }

    static func iconName(for deviceName: String) -> String {
        let name = deviceName.lowercased()
        if name.contains("airpod") || name.contains("buds") || name.contains("earphone") || name.contains("headphone") {
            return "airpodspro"
        } else if name.contains("macbook") || name.contains("built-in") || name.contains("internal") {
            return "laptopcomputer"
        } else if name.contains("usb") || name.contains("studio") || name.contains("yeti") || name.contains("shure") || name.contains("rode") || name.contains("elgato") {
            return "mic.badge.plus"
        }
        return "mic.fill"
    }
}

@MainActor
final class AudioHardwareWatcher: ObservableObject {
    var onDevicesChanged: (() -> Void)?
    private var isWatching = false
    private var listenerBlock: AudioObjectPropertyListenerBlock?

    init() {
        startWatching()
    }

    isolated deinit {
        stopWatching()
    }

    func startWatching() {
        guard !isWatching else { return }
        let systemObject = AudioObjectID(kAudioObjectSystemObject)
        var addressDevices = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var addressDefault = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.onDevicesChanged?()
            }
        }
        listenerBlock = block

        AudioObjectAddPropertyListenerBlock(systemObject, &addressDevices, DispatchQueue.main, block)
        AudioObjectAddPropertyListenerBlock(systemObject, &addressDefault, DispatchQueue.main, block)
        isWatching = true
    }

    func stopWatching() {
        guard isWatching, let block = listenerBlock else { return }
        let systemObject = AudioObjectID(kAudioObjectSystemObject)
        var addressDevices = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var addressDefault = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(systemObject, &addressDevices, DispatchQueue.main, block)
        AudioObjectRemovePropertyListenerBlock(systemObject, &addressDefault, DispatchQueue.main, block)
        listenerBlock = nil
        isWatching = false
    }
}
