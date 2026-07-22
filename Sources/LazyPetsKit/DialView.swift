import CoreAudio
import SwiftUI

/// The shared Dial control block — Output/Input segmented switch, device
/// table, volume slider, and (Input only) the live level meter. Rendered by
/// both the pet popover tab (~300pt) and the manage window's config page;
/// one implementation, two widths. Tab selection, device choice, and volume
/// all live on the shared services, so the two surfaces can't drift apart.
struct DialAudioBlockView: View {

    @ObservedObject var audio: AudioDeviceService
    @ObservedObject var levels: AudioLevelMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("", selection: $audio.scope) {
                ForEach(DialScope.allCases, id: \.self) { scope in
                    Text(scope.rawValue).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            deviceTable

            volumeSection

            if audio.scope == .input {
                inputLevelSection
            }
        }
        // The meter taps the mic, so it runs strictly while an Input panel
        // is on screen — acquired on appear, released immediately after.
        .onAppear { if audio.scope == .input { levels.acquire() } }
        .onDisappear { if audio.scope == .input { levels.release() } }
        .onChange(of: audio.scope) { scope in
            if scope == .input { levels.acquire() } else { levels.release() }
        }
    }

    // MARK: - Device table

    private var deviceTable: some View {
        let devices = audio.devices(for: audio.scope)
        let activeID = audio.defaultDeviceID(for: audio.scope)
        return VStack(spacing: 0) {
            HStack {
                Text("Name")
                Spacer()
                Text("Type")
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            Divider()

            if devices.isEmpty {
                Text("No \(audio.scope.rawValue.lowercased()) devices")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
            } else {
                ForEach(devices) { device in
                    deviceRow(device, isActive: device.id == activeID)
                    if device.id != devices.last?.id {
                        Divider()
                    }
                }
            }
        }
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.secondary.opacity(0.2))
        }
    }

    /// Radio-style row: clicking makes the device the default for the scope.
    private func deviceRow(_ device: AudioDevice, isActive: Bool) -> some View {
        Button {
            audio.setDefaultDevice(device.id, for: audio.scope)
        } label: {
            HStack {
                Text(device.name)
                    .font(.callout.weight(isActive ? .semibold : .regular))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(device.transport)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(isActive ? Color.accentColor.opacity(0.18) : Color.clear)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(device.name), \(device.transport)\(isActive ? ", active" : "")")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    // MARK: - Volume

    @ViewBuilder private var volumeSection: some View {
        let scope = audio.scope
        Text("\(scope.rawValue) volume")
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
        if audio.volume(for: scope) != nil {
            HStack(spacing: 8) {
                Image(systemName: scope == .output ? "speaker.fill" : "mic.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Slider(value: volumeBinding, in: 0...1)
                    .accessibilityLabel("\(scope.rawValue) volume")
                    .accessibilityValue("\(Int((audio.volume(for: scope) ?? 0) * 100)) percent")
                Image(systemName: scope == .output ? "speaker.wave.3.fill" : "mic.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        } else {
            // Some devices (HDMI/DisplayPort outputs, many USB mics) have no
            // software volume — say so instead of a control that can't work.
            Text("This device's volume can't be adjusted here.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var volumeBinding: Binding<Float> {
        Binding(
            get: { audio.volume(for: audio.scope) ?? 0 },
            set: { audio.setVolume($0, for: audio.scope) }
        )
    }

    // MARK: - Input level meter

    private static let segmentCount = 16

    @ViewBuilder private var inputLevelSection: some View {
        Text("Input level")
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
        if levels.permission == .denied {
            Text("Microphone access is needed for the level meter. Allow it in System Settings › Privacy & Security › Microphone. Device switching and volume still work without it.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            let lit = Int(levels.level * Float(Self.segmentCount))
            HStack(spacing: 3) {
                ForEach(0..<Self.segmentCount, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(index < lit ? Color.accentColor : Color.secondary.opacity(0.25))
                        .frame(width: 6, height: 14)
                }
            }
            // The meter is decorative confirmation — the device table and
            // volume slider carry the state for assistive tech.
            .accessibilityHidden(true)
        }
    }
}

/// The popover tab's wrapper at panel width, matching Task List/Boombox.
struct DialPanelView: View {

    @ObservedObject var audio: AudioDeviceService
    @ObservedObject var levels: AudioLevelMonitor
    var showsHeader = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsHeader {
                Label("Dial", systemImage: "dial.medium")
                    .font(.headline)
            }
            DialAudioBlockView(audio: audio, levels: levels)
        }
        .padding(12)
        .frame(width: 300)
    }
}

/// Shown in place of the panel when the clicked pet doesn't have Dial
/// enabled — the tab stays visible but leads here instead of vanishing.
struct DialDisabledView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "dial.medium")
                .font(.title3)
                .foregroundStyle(.tertiary)
            Text("Dial isn't enabled for this pet — turn it on in the Dial config page.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(16)
        .frame(width: 300)
    }
}

// MARK: - Previews

private let previewOutputs = [
    AudioDevice(id: 1, name: "MacBook Air Speakers", transport: "Built-in", hasVolumeControl: true),
    AudioDevice(id: 2, name: "AirPods Pro", transport: "Bluetooth", hasVolumeControl: true),
    AudioDevice(id: 3, name: "Studio Display", transport: "USB", hasVolumeControl: true),
]
private let previewInputs = [
    AudioDevice(id: 4, name: "MacBook Air Microphone", transport: "Built-in", hasVolumeControl: true),
    AudioDevice(id: 5, name: "External Microphone", transport: "USB", hasVolumeControl: false),
]

#Preview("Outputs — several, one active") {
    DialPanelView(
        audio: .preview(outputs: previewOutputs, defaultOutputID: 2, outputVolume: 0.6),
        levels: .preview(permission: .granted)
    )
}

#Preview("Output with no settable volume") {
    DialPanelView(
        audio: .preview(
            outputs: [AudioDevice(id: 9, name: "HDMI TV", transport: "Display", hasVolumeControl: false)],
            defaultOutputID: 9,
            outputVolume: nil
        ),
        levels: .preview(permission: .granted)
    )
}

#Preview("Single device") {
    DialPanelView(
        audio: .preview(outputs: [previewOutputs[0]], defaultOutputID: 1, outputVolume: 0.4),
        levels: .preview(permission: .granted)
    )
}

#Preview("Input with live meter") {
    DialPanelView(
        audio: .preview(scope: .input, inputs: previewInputs, defaultInputID: 4, inputVolume: 0.7),
        levels: .preview(permission: .granted, level: 0.55)
    )
}

#Preview("Pet without Dial enabled") {
    DialDisabledView()
}

#Preview("Mic permission denied — meter only") {
    DialPanelView(
        audio: .preview(scope: .input, inputs: previewInputs, defaultInputID: 4, inputVolume: 0.7),
        levels: .preview(permission: .denied)
    )
}
