import CoreAudio
import Foundation

struct AudioInputDevice: Identifiable, Hashable, Sendable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let isDefault: Bool
}

@MainActor
protocol AudioDeviceServing {
    func inputDevices() throws -> [AudioInputDevice]
    func deviceID(forUID uid: String?) throws -> AudioDeviceID?
}

enum AudioDeviceServiceError: LocalizedError {
    case propertyUnavailable(OSStatus)
    case selectedDeviceUnavailable

    var errorDescription: String? {
        switch self {
        case let .propertyUnavailable(status):
            "Audio devices could not be read (CoreAudio status \(status))."
        case .selectedDeviceUnavailable:
            "The selected microphone is no longer available."
        }
    }
}

struct AudioDeviceService: AudioDeviceServing {
    func inputDevices() throws -> [AudioInputDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size
        )
        guard status == noErr else { throw AudioDeviceServiceError.propertyUnavailable(status) }

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = Array(repeating: AudioDeviceID(0), count: count)
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids
        )
        guard status == noErr else { throw AudioDeviceServiceError.propertyUnavailable(status) }

        let defaultID = defaultInputDeviceID()
        return ids.compactMap { id in
            guard hasInputStreams(deviceID: id) else { return nil }
            guard let uid = stringProperty(kAudioDevicePropertyDeviceUID, deviceID: id) else {
                return nil
            }
            let name = stringProperty(kAudioObjectPropertyName, deviceID: id) ?? "Microphone"
            return AudioInputDevice(id: id, uid: uid, name: name, isDefault: id == defaultID)
        }
        .sorted { lhs, rhs in
            if lhs.isDefault != rhs.isDefault { return lhs.isDefault }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    func deviceID(forUID uid: String?) throws -> AudioDeviceID? {
        guard let uid else { return nil }
        guard let device = try inputDevices().first(where: { $0.uid == uid }) else {
            throw AudioDeviceServiceError.selectedDeviceUnavailable
        }
        return device.id
    }

    private func defaultInputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &value
        )
        return status == noErr ? value : nil
    }

    private func hasInputStreams(deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size)
        return status == noErr && size >= UInt32(MemoryLayout<AudioStreamID>.size)
    }

    private func stringProperty(
        _ selector: AudioObjectPropertySelector,
        deviceID: AudioDeviceID
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value)
        guard status == noErr, let value else { return nil }
        return value.takeUnretainedValue() as String
    }
}
