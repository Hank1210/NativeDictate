@preconcurrency import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation

/// Captures a chosen input device without connecting it to the system output route.
/// AVAudioEngine's I/O graph can stop delivering input when the output device changes.
nonisolated final class SelectedMicrophoneInput: @unchecked Sendable {
    enum CaptureError: LocalizedError {
        case audioUnit(OSStatus)
        case invalidFormat

        var errorDescription: String? {
            switch self {
            case let .audioUnit(status):
                "The selected microphone could not start (Core Audio \(status))."
            case .invalidFormat:
                "The selected microphone has no usable audio format."
            }
        }
    }

    let format: AVAudioFormat
    private var unit: AudioUnit?
    private var onBuffer: @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void = { _, _ in }
    private var onError: @Sendable (OSStatus) -> Void = { _ in }
    private(set) var isRunning = false

    init(deviceID: AudioDeviceID) throws {
        var description = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        guard let component = AudioComponentFindNext(nil, &description) else {
            throw CaptureError.invalidFormat
        }
        var createdUnit: AudioUnit?
        try Self.check(AudioComponentInstanceNew(component, &createdUnit))
        guard let createdUnit else { throw CaptureError.invalidFormat }
        unit = createdUnit
        do {
            var enabled: UInt32 = 1
            try Self.check(AudioUnitSetProperty(
                createdUnit, kAudioOutputUnitProperty_EnableIO,
                kAudioUnitScope_Input, 1, &enabled, UInt32(MemoryLayout<UInt32>.size)
            ))
            enabled = 0
            try Self.check(AudioUnitSetProperty(
                createdUnit, kAudioOutputUnitProperty_EnableIO,
                kAudioUnitScope_Output, 0, &enabled, UInt32(MemoryLayout<UInt32>.size)
            ))
            var chosenDevice = deviceID
            try Self.check(AudioUnitSetProperty(
                createdUnit, kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global, 0, &chosenDevice,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            ))

            // The input scope is the chosen microphone's hardware format. The
            // output scope can still reflect the old/default output route here.
            var nativeFormat = AudioStreamBasicDescription()
            var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            try Self.check(AudioUnitGetProperty(
                createdUnit, kAudioUnitProperty_StreamFormat,
                kAudioUnitScope_Input, 1, &nativeFormat, &formatSize
            ))
            guard nativeFormat.mSampleRate > 0,
                  nativeFormat.mChannelsPerFrame > 0,
                  let format = AVAudioFormat(
                      commonFormat: .pcmFormatFloat32,
                      sampleRate: nativeFormat.mSampleRate,
                      channels: AVAudioChannelCount(nativeFormat.mChannelsPerFrame),
                      interleaved: false
                  ) else {
                throw CaptureError.invalidFormat
            }
            self.format = format
            var clientFormat = format.streamDescription.pointee
            try Self.check(AudioUnitSetProperty(
                createdUnit, kAudioUnitProperty_StreamFormat,
                kAudioUnitScope_Output, 1, &clientFormat,
                UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            ))
            var callback = AURenderCallbackStruct(
                inputProc: { refCon, flags, timeStamp, _, frameCount, _ in
                    let capture = Unmanaged<SelectedMicrophoneInput>
                        .fromOpaque(refCon).takeUnretainedValue()
                    return capture.render(
                        flags: flags,
                        timeStamp: timeStamp,
                        frameCount: frameCount
                    )
                },
                inputProcRefCon: Unmanaged.passUnretained(self).toOpaque()
            )
            try Self.check(AudioUnitSetProperty(
                createdUnit, kAudioOutputUnitProperty_SetInputCallback,
                kAudioUnitScope_Global, 1, &callback,
                UInt32(MemoryLayout<AURenderCallbackStruct>.size)
            ))
            try Self.check(AudioUnitInitialize(createdUnit))
        } catch {
            AudioComponentInstanceDispose(createdUnit)
            unit = nil
            throw error
        }
    }

    /// Install before `start()`; callbacks are immutable for the running capture.
    func setHandlers(
        onBuffer: @escaping @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void,
        onError: @escaping @Sendable (OSStatus) -> Void
    ) {
        self.onBuffer = onBuffer
        self.onError = onError
    }

    func start() throws {
        guard let unit else { throw CaptureError.invalidFormat }
        try Self.check(AudioOutputUnitStart(unit))
        isRunning = true
    }

    func stop() {
        guard let unit else { return }
        if isRunning {
            AudioOutputUnitStop(unit)
            isRunning = false
        }
    }

    deinit {
        stop()
        if let unit {
            AudioUnitUninitialize(unit)
            AudioComponentInstanceDispose(unit)
        }
    }

    private func render(
        flags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
        timeStamp: UnsafePointer<AudioTimeStamp>,
        frameCount: UInt32
    ) -> OSStatus {
        guard let unit,
              let buffer = Self.makeRenderBuffer(format: format, frameCount: frameCount) else {
            onError(-1)
            return noErr
        }
        var timestamp = timeStamp.pointee
        let status = AudioUnitRender(
            unit, flags, &timestamp, 1, frameCount, buffer.mutableAudioBufferList
        )
        if status == kAudioUnitErr_CannotDoInCurrentContext {
            // HAL can temporarily reconfigure the device. Never spin or wait
            // on its realtime callback; the next cycle can provide audio.
            return noErr
        }
        guard status == noErr else {
            onError(status)
            return status
        }
        let hostTime = timestamp.mFlags.contains(.hostTimeValid)
            ? timestamp.mHostTime : mach_continuous_time()
        onBuffer(buffer, AVAudioTime(hostTime: hostTime))
        return noErr
    }

    private static func check(_ status: OSStatus) throws {
        guard status == noErr else { throw CaptureError.audioUnit(status) }
    }

    static func makeRenderBuffer(
        format: AVAudioFormat,
        frameCount: UInt32
    ) -> AVAudioPCMBuffer? {
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }
        // AudioUnitRender validates mDataByteSize on input. AVAudioPCMBuffer
        // initializes it to zero until frameLength is set.
        buffer.frameLength = frameCount
        return buffer
    }
}
