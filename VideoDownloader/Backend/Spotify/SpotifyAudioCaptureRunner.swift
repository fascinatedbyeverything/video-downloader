import Foundation
import CoreAudio
import AudioToolbox
import AppKit

enum SpotifyAudioCaptureError: Error {
    case spotifyNotRunning
    case tapCreateFailed(OSStatus)
    case aggregateCreateFailed(OSStatus)
    case ioProcInstallFailed(OSStatus)
    case deviceStartFailed(OSStatus)
}

/// PCM frame delivered by the capture runner.
/// Default format: 32-bit float, 44.1 kHz, channel count varies (typically 2 stereo or 1 mono mixdown).
struct SpotifyPCMChunk {
    let samples: [Float]
    let sampleRate: Double
    let channelCount: Int
    let timestamp: Date
}

/// Captures Spotify.app's process audio via CoreAudio Process Tap (macOS 14.2+).
/// Apple's `AudioHardwareCreateProcessTap` + aggregate device pattern; reads PCM via IOProc.
final class SpotifyAudioCaptureRunner {
    private var tapID: AudioObjectID = 0
    private var aggregateID: AudioDeviceID = 0
    private var ioProcID: AudioDeviceIOProcID?
    private let onChunk: (SpotifyPCMChunk) -> Void
    private var running = false
    private var streamFormat = AudioStreamBasicDescription()

    init(onChunk: @escaping (SpotifyPCMChunk) -> Void) {
        self.onChunk = onChunk
    }

    func start() throws {
        guard !running else { return }
        let pid = try locateSpotifyPID()
        let processObjectID = try translatePIDToProcessObject(pid)

        // 1) Create a stereo-mixdown process tap targeting Spotify's process audio object.
        let desc = CATapDescription(stereoMixdownOfProcesses: [processObjectID])
        desc.muteBehavior = CATapMuteBehavior.unmuted
        var tap: AudioObjectID = 0
        let st1 = AudioHardwareCreateProcessTap(desc, &tap)
        guard st1 == noErr else { throw SpotifyAudioCaptureError.tapCreateFailed(st1) }
        self.tapID = tap

        // 2) Create an aggregate device that contains the tap as a sub-device.
        let aggUID = "com.fascinatedbyeverything.VideoDownloader.SpotifyTapAggregate-\(UUID().uuidString)"
        let tapUIDStr = tapUID(of: tap)
        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey as String: "Spotify Tap Aggregate",
            kAudioAggregateDeviceUIDKey as String: aggUID,
            kAudioAggregateDeviceMainSubDeviceKey as String: tapUIDStr,
            kAudioAggregateDeviceIsPrivateKey as String: 1,
            kAudioAggregateDeviceIsStackedKey as String: 0,
            kAudioAggregateDeviceTapListKey as String: [
                [kAudioSubTapUIDKey as String: tapUIDStr]
            ],
            kAudioAggregateDeviceSubDeviceListKey as String: []
        ]
        var agg: AudioDeviceID = 0
        let st2 = AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &agg)
        guard st2 == noErr else { throw SpotifyAudioCaptureError.aggregateCreateFailed(st2) }
        self.aggregateID = agg

        // 3) Read the input stream's actual format so we know sampleRate/channelCount.
        streamFormat = try fetchInputStreamFormat(deviceID: agg)

        // 4) Install IOProc.
        var procID: AudioDeviceIOProcID?
        let st3 = AudioDeviceCreateIOProcIDWithBlock(&procID, agg, nil) { [weak self] _, inInputData, _, _, _ in
            guard let self else { return }
            self.handleIO(inInputData)
        }
        guard st3 == noErr, let pid = procID else { throw SpotifyAudioCaptureError.ioProcInstallFailed(st3) }
        self.ioProcID = pid

        // 5) Start.
        let st4 = AudioDeviceStart(agg, pid)
        guard st4 == noErr else { throw SpotifyAudioCaptureError.deviceStartFailed(st4) }
        running = true
    }

    func stop() {
        guard running else { return }
        if let pid = ioProcID {
            AudioDeviceStop(aggregateID, pid)
            AudioDeviceDestroyIOProcID(aggregateID, pid)
            ioProcID = nil
        }
        if aggregateID != 0 {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = 0
        }
        if tapID != 0 {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = 0
        }
        running = false
    }

    deinit { stop() }

    private func handleIO(_ inputDataPtr: UnsafePointer<AudioBufferList>) {
        let abl = inputDataPtr.pointee
        guard abl.mNumberBuffers > 0 else { return }
        // Use UnsafeMutableAudioBufferListPointer for safe iteration.
        let mutablePtr = UnsafeMutablePointer<AudioBufferList>(mutating: inputDataPtr)
        let bufList = UnsafeMutableAudioBufferListPointer(mutablePtr)
        guard let firstBuf = bufList.first, let raw = firstBuf.mData else { return }
        let frameCount = Int(firstBuf.mDataByteSize) / MemoryLayout<Float>.size
        let ptr = raw.bindMemory(to: Float.self, capacity: frameCount)
        let samples = Array(UnsafeBufferPointer(start: ptr, count: frameCount))
        let chunk = SpotifyPCMChunk(
            samples: samples,
            sampleRate: streamFormat.mSampleRate > 0 ? streamFormat.mSampleRate : 44100,
            channelCount: Int(firstBuf.mNumberChannels),
            timestamp: Date()
        )
        onChunk(chunk)
    }

    private func locateSpotifyPID() throws -> pid_t {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").first else {
            throw SpotifyAudioCaptureError.spotifyNotRunning
        }
        return app.processIdentifier
    }

    /// Translate a UNIX pid_t to its CoreAudio process AudioObjectID via the
    /// system object's `kAudioHardwarePropertyTranslatePIDToProcessObject` qualified-data property.
    private func translatePIDToProcessObject(_ pid: pid_t) throws -> AudioObjectID {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var pidLocal = pid
        var processID: AudioObjectID = 0
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &addr,
            UInt32(MemoryLayout<pid_t>.size),
            &pidLocal,
            &size,
            &processID
        )
        guard status == noErr else { throw SpotifyAudioCaptureError.tapCreateFailed(status) }
        return processID
    }

    private func tapUID(of tap: AudioObjectID) -> String {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<CFString?>.size)
        var uidUnmanaged: Unmanaged<CFString>?
        let status = withUnsafeMutablePointer(to: &uidUnmanaged) { ptr -> OSStatus in
            ptr.withMemoryRebound(to: UInt8.self, capacity: MemoryLayout<Unmanaged<CFString>?>.size) { _ in
                AudioObjectGetPropertyData(tap, &addr, 0, nil, &size, ptr)
            }
        }
        guard status == noErr, let uid = uidUnmanaged?.takeRetainedValue() else { return "" }
        return uid as String
    }

    private func fetchInputStreamFormat(deviceID: AudioDeviceID) throws -> AudioStreamBasicDescription {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamFormat,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let st = AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &asbd)
        guard st == noErr else { throw SpotifyAudioCaptureError.deviceStartFailed(st) }
        return asbd
    }
}
