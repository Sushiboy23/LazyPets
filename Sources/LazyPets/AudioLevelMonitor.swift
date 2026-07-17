import AVFoundation
import Foundation

/// The live input level meter's engine: taps the default microphone via
/// AVAudioEngine and publishes a normalized 0–1 loudness. Deliberately
/// separate from AudioDeviceService — this half needs the microphone
/// permission and lights macOS's mic-in-use indicator, so it only runs
/// while a Dial Input panel is actually on screen. Views acquire()/release()
/// around visibility; the tap never runs in the background.
final class AudioLevelMonitor: ObservableObject {

    enum Permission {
        case undetermined
        case granted
        case denied
    }

    @Published private(set) var permission: Permission = .undetermined
    /// Normalized 0–1, log-scaled to feel like System Settings' meter.
    @Published private(set) var level: Float = 0

    private var engine: AVAudioEngine?
    private var viewers = 0
    private let live: Bool

    init(live: Bool = true) {
        self.live = live
        guard live else { return }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: permission = .granted
        case .notDetermined: permission = .undetermined
        default: permission = .denied
        }
    }

    /// Preview factory — fixed state, no engine, no permission prompt.
    static func preview(permission: Permission, level: Float = 0) -> AudioLevelMonitor {
        let monitor = AudioLevelMonitor(live: false)
        monitor.permission = permission
        monitor.level = level
        return monitor
    }

    /// Reference-counted: the popover tab and the manage page can both show
    /// the meter; the tap stops only when the last one disappears.
    func acquire() {
        guard live else { return }
        viewers += 1
        guard viewers == 1 else { return }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            permission = .granted
            startTap()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    permission = granted ? .granted : .denied
                    if granted, viewers > 0 { startTap() }
                }
            }
        default:
            permission = .denied
        }
    }

    func release() {
        guard live else { return }
        viewers = max(0, viewers - 1)
        if viewers == 0 {
            stopTap()
        }
    }

    private func startTap() {
        guard engine == nil else { return }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else { return }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let samples = buffer.floatChannelData?[0] else { return }
            let frames = Int(buffer.frameLength)
            guard frames > 0 else { return }
            var sum: Float = 0
            for index in 0..<frames {
                sum += samples[index] * samples[index]
            }
            let rms = sqrt(sum / Float(frames))
            // Map ~-50dB…0dB onto 0…1 so quiet rooms sit near zero and
            // speech fills most of the meter.
            let decibels = 20 * log10(max(rms, 0.00001))
            let normalized = max(0, min(1, (decibels + 50) / 50))
            DispatchQueue.main.async {
                self?.level = normalized
            }
        }
        do {
            try engine.start()
            self.engine = engine
        } catch {
            // No input device / engine failure: meter just stays at zero.
            input.removeTap(onBus: 0)
        }
    }

    private func stopTap() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        level = 0
    }
}
