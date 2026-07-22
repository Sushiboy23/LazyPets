import CoreAudio
import Foundation

/// One selectable audio device (output or input side).
struct AudioDevice: Identifiable, Equatable {
    let id: AudioDeviceID
    let name: String
    /// User-facing transport label ("Built-in" / "Bluetooth" / "USB" …).
    let transport: String
    /// False when the device exposes no software-settable volume — the
    /// slider is hidden for it rather than silently failing.
    let hasVolumeControl: Bool
}

/// Which side of the Dial panel is showing. Lives on the service so the
/// popover tab and the manage window's config page are two views onto the
/// same state and can't drift apart.
enum DialScope: String, CaseIterable {
    case output = "Output"
    case input = "Input"

    var coreAudioScope: AudioObjectPropertyScope {
        self == .output ? kAudioObjectPropertyScopeOutput : kAudioObjectPropertyScopeInput
    }
}

/// Device list, default-device switching, and volume — all via public
/// CoreAudio C APIs. No microphone permission is involved anywhere here:
/// that's only needed for the live level meter (see AudioLevelMonitor).
/// Property reads/writes run on a serial background queue; published state
/// updates on main. Changes made outside the app (media keys, System
/// Settings, plug/unplug) arrive via property listener blocks, not polling.
final class AudioDeviceService: ObservableObject {

    @Published var scope: DialScope = .output {
        didSet { refresh() }
    }
    @Published private(set) var outputDevices: [AudioDevice] = []
    @Published private(set) var inputDevices: [AudioDevice] = []
    @Published private(set) var defaultOutputID: AudioDeviceID?
    @Published private(set) var defaultInputID: AudioDeviceID?
    /// nil = the current default device has no software volume control.
    @Published private(set) var outputVolume: Float?
    @Published private(set) var inputVolume: Float?

    private let queue = DispatchQueue(label: "com.zac.lazypets.dial.coreaudio")
    private let systemObject = AudioObjectID(kAudioObjectSystemObject)
    private let live: Bool
    /// Devices already carrying our volume listener (queue-confined).
    /// Listeners are added once and never removed: a Swift closure passed to
    /// a C block parameter bridges to a *fresh* block object on every call,
    /// so AudioObjectRemovePropertyListenerBlock can never match the block
    /// that was added. The old remove/re-add-per-reload cycle therefore
    /// leaked two listeners per refresh; every volume event then fired all
    /// of them, each queuing another reload, until the serial queue was
    /// permanently saturated and setDefaultDevice's work never ran.
    private struct VolumeListenerKey: Hashable {
        let device: AudioDeviceID
        let scope: AudioObjectPropertyScope
    }
    private var volumeListenerKeys: Set<VolumeListenerKey> = []
    private lazy var listenerBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        self?.refresh()
    }

    init(live: Bool = true) {
        self.live = live
        guard live else { return }
        for selector in [
            kAudioHardwarePropertyDevices,
            kAudioHardwarePropertyDefaultOutputDevice,
            kAudioHardwarePropertyDefaultInputDevice,
        ] {
            var address = Self.address(selector)
            AudioObjectAddPropertyListenerBlock(systemObject, &address, queue, listenerBlock)
        }
        refresh()
    }

    /// Preview factory — fixed state, no CoreAudio.
    static func preview(
        scope: DialScope = .output,
        outputs: [AudioDevice] = [],
        inputs: [AudioDevice] = [],
        defaultOutputID: AudioDeviceID? = nil,
        defaultInputID: AudioDeviceID? = nil,
        outputVolume: Float? = nil,
        inputVolume: Float? = nil
    ) -> AudioDeviceService {
        let service = AudioDeviceService(live: false)
        service.scope = scope
        service.outputDevices = outputs
        service.inputDevices = inputs
        service.defaultOutputID = defaultOutputID
        service.defaultInputID = defaultInputID
        service.outputVolume = outputVolume
        service.inputVolume = inputVolume
        return service
    }

    // MARK: - Scope-generic accessors for the shared view

    func devices(for scope: DialScope) -> [AudioDevice] {
        scope == .output ? outputDevices : inputDevices
    }

    func defaultDeviceID(for scope: DialScope) -> AudioDeviceID? {
        scope == .output ? defaultOutputID : defaultInputID
    }

    func volume(for scope: DialScope) -> Float? {
        scope == .output ? outputVolume : inputVolume
    }

    // MARK: - Actions

    func setDefaultDevice(_ id: AudioDeviceID, for scope: DialScope) {
        // Optimistic so the row highlight moves instantly.
        if scope == .output { defaultOutputID = id } else { defaultInputID = id }
        guard live else { return }
        queue.async { [weak self] in
            guard let self else { return }
            var deviceID = id
            var address = Self.address(scope == .output
                ? kAudioHardwarePropertyDefaultOutputDevice
                : kAudioHardwarePropertyDefaultInputDevice)
            AudioObjectSetPropertyData(
                systemObject, &address, 0, nil,
                UInt32(MemoryLayout<AudioDeviceID>.size), &deviceID
            )
        }
    }

    func setVolume(_ volume: Float, for scope: DialScope) {
        if scope == .output { outputVolume = volume } else { inputVolume = volume }
        guard live, let deviceID = defaultDeviceID(for: scope) else { return }
        queue.async {
            guard let element = Self.volumeElement(deviceID, scope.coreAudioScope) else { return }
            var value = Float32(max(0, min(1, volume)))
            // Per-channel fallback devices need both stereo channels set.
            let elements = element == kAudioObjectPropertyElementMain ? [element] : [1, 2]
            for element in elements {
                var address = Self.address(kAudioDevicePropertyVolumeScalar, scope.coreAudioScope, element)
                guard AudioObjectHasProperty(deviceID, &address) else { continue }
                AudioObjectSetPropertyData(deviceID, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
            }
        }
    }

    // MARK: - Refresh

    private func refresh() {
        guard live else { return }
        queue.async { [weak self] in
            self?.reloadEverything()
        }
    }

    private func reloadEverything() {
        let ids = allDeviceIDs()
        var outputs: [AudioDevice] = []
        var inputs: [AudioDevice] = []
        for id in ids {
            // Aggregate/virtual devices are plumbing, not user choices.
            guard let transport = Self.transportLabel(id) else { continue }
            let name = Self.deviceName(id) ?? "Audio Device"
            if Self.streamCount(id, kAudioObjectPropertyScopeOutput) > 0 {
                outputs.append(AudioDevice(
                    id: id, name: name, transport: transport,
                    hasVolumeControl: Self.volumeElement(id, kAudioObjectPropertyScopeOutput) != nil
                ))
            }
            if Self.streamCount(id, kAudioObjectPropertyScopeInput) > 0 {
                inputs.append(AudioDevice(
                    id: id, name: name, transport: transport,
                    hasVolumeControl: Self.volumeElement(id, kAudioObjectPropertyScopeInput) != nil
                ))
            }
        }

        let defaultOut = Self.defaultDevice(systemObject, kAudioHardwarePropertyDefaultOutputDevice)
        let defaultIn = Self.defaultDevice(systemObject, kAudioHardwarePropertyDefaultInputDevice)
        let outVolume = defaultOut.flatMap { Self.readVolume($0, kAudioObjectPropertyScopeOutput) }
        let inVolume = defaultIn.flatMap { Self.readVolume($0, kAudioObjectPropertyScopeInput) }

        // Track external volume changes (media keys, System Settings) on
        // whichever devices are currently the defaults. One listener per
        // device+scope, kept for the device's lifetime (see volumeListenerKeys
        // for why removal is impossible); prune keys for unplugged devices so
        // a recycled AudioDeviceID gets a fresh listener.
        volumeListenerKeys = volumeListenerKeys.filter { ids.contains($0.device) }
        for (device, scope) in [(defaultOut, kAudioObjectPropertyScopeOutput), (defaultIn, kAudioObjectPropertyScopeInput)] {
            guard let device, let element = Self.volumeElement(device, scope) else { continue }
            let key = VolumeListenerKey(device: device, scope: scope)
            guard volumeListenerKeys.insert(key).inserted else { continue }
            var address = Self.address(kAudioDevicePropertyVolumeScalar, scope, element)
            AudioObjectAddPropertyListenerBlock(device, &address, queue, listenerBlock)
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            outputDevices = outputs
            inputDevices = inputs
            defaultOutputID = defaultOut
            defaultInputID = defaultIn
            outputVolume = outVolume
            inputVolume = inVolume
        }
    }

    // MARK: - CoreAudio helpers (all called on the background queue)

    private static func address(
        _ selector: AudioObjectPropertySelector,
        _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        _ element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    private func allDeviceIDs() -> [AudioDeviceID] {
        var address = Self.address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(systemObject, &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard !ids.isEmpty,
              AudioObjectGetPropertyData(systemObject, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func deviceName(_ id: AudioDeviceID) -> String? {
        var address = address(kAudioObjectPropertyName)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &name) == noErr,
              let name else { return nil }
        return name.takeRetainedValue() as String
    }

    private static func streamCount(_ id: AudioDeviceID, _ scope: AudioObjectPropertyScope) -> Int {
        var address = address(kAudioDevicePropertyStreams, scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr else { return 0 }
        return Int(size) / MemoryLayout<AudioStreamID>.size
    }

    /// Nil filters the device out (aggregate/virtual plumbing).
    private static func transportLabel(_ id: AudioDeviceID) -> String? {
        var address = address(kAudioDevicePropertyTransportType)
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &transport) == noErr else { return "Other" }
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn: return "Built-in"
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return "Bluetooth"
        case kAudioDeviceTransportTypeUSB: return "USB"
        case kAudioDeviceTransportTypeDisplayPort, kAudioDeviceTransportTypeHDMI: return "Display"
        case kAudioDeviceTransportTypeAirPlay: return "AirPlay"
        case kAudioDeviceTransportTypeThunderbolt, kAudioDeviceTransportTypePCI: return "Wired"
        case kAudioDeviceTransportTypeAggregate, kAudioDeviceTransportTypeVirtual, kAudioDeviceTransportTypeUnknown:
            return nil
        default: return "Other"
        }
    }

    private static func defaultDevice(_ systemObject: AudioObjectID, _ selector: AudioObjectPropertySelector) -> AudioDeviceID? {
        var address = address(selector)
        var id: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(systemObject, &address, 0, nil, &size, &id) == noErr, id != 0 else { return nil }
        return id
    }

    /// The element carrying a settable volume: the main (master) element
    /// first, falling back to channel 1 for devices without a master channel.
    private static func volumeElement(_ id: AudioDeviceID, _ scope: AudioObjectPropertyScope) -> AudioObjectPropertyElement? {
        for element in [kAudioObjectPropertyElementMain, AudioObjectPropertyElement(1)] {
            var address = address(kAudioDevicePropertyVolumeScalar, scope, element)
            guard AudioObjectHasProperty(id, &address) else { continue }
            var settable = DarwinBoolean(false)
            if AudioObjectIsPropertySettable(id, &address, &settable) == noErr, settable.boolValue {
                return element
            }
        }
        return nil
    }

    private static func readVolume(_ id: AudioDeviceID, _ scope: AudioObjectPropertyScope) -> Float? {
        guard let element = volumeElement(id, scope) else { return nil }
        var address = address(kAudioDevicePropertyVolumeScalar, scope, element)
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }
}
