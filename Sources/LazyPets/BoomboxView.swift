import SwiftUI

/// The Boombox panel for the pet click popover: shows what's playing in a
/// supported music app with a play/pause control, a disabled "Last played"
/// state when nothing is running, and a neutral empty state otherwise.
/// Matches the Timer/Task List panel dimensions and styling.
struct BoomboxView: View {

    @ObservedObject var controller: BoomboxController
    /// Hidden when the panel sits under the tab switcher, which already
    /// names it (same pattern as the Task List panel).
    var showsHeader = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsHeader {
                Label("Boombox", systemImage: "music.note")
                    .font(.headline)
            }

            switch controller.display {
            case .nothing:
                Text("Nothing playing")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 10)
            case .lastPlayed(let track):
                Text("Last played")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                trackRow(track, state: nil)
            case .nowPlaying(let track, let state):
                trackRow(track, state: state)
                Text("via \(track.appName)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .frame(width: 260)
        .onAppear { controller.setPanelVisible(true) }
        .onDisappear { controller.setPanelVisible(false) }
    }

    /// state == nil means "no controls" (the last-played state).
    private func trackRow(_ track: BoomboxTrack, state: BoomboxPlayback?) -> some View {
        HStack(spacing: 8) {
            artworkView
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(track.album.isEmpty ? track.artist : "\(track.artist) — \(track.album)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(track.title) by \(track.artist)")
            Spacer(minLength: 4)
            Button {
                controller.togglePlayPause()
            } label: {
                Image(systemName: state == .playing ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(state == nil ? Color.secondary : Color.accentColor)
            }
            .buttonStyle(.plain)
            .disabled(state == nil)
            .accessibilityLabel(state == .playing ? "Pause" : "Play")
        }
    }

    private var artworkView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.15))
            if let artwork = controller.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "music.note")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 38, height: 38)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityHidden(true)
    }
}

// MARK: - Previews

private let spotifyTrack = BoomboxTrack(
    title: "Everything In Its Right Place", artist: "Radiohead",
    album: "Kid A", appName: "Spotify", artworkURL: nil
)
private let musicTrack = BoomboxTrack(
    title: "Nights", artist: "Frank Ocean",
    album: "Blonde", appName: "Apple Music", artworkURL: nil
)

#Preview("Spotify playing") {
    BoomboxView(controller: .preview(.nowPlaying(spotifyTrack, .playing)))
}

#Preview("Apple Music playing") {
    BoomboxView(controller: .preview(.nowPlaying(musicTrack, .playing)))
}

// Both apps running: the coordinator surfaces exactly one (the playing one,
// with a sticky tie-break) — visually identical to a single-app state.
#Preview("Both running — Spotify surfaced") {
    BoomboxView(controller: .preview(.nowPlaying(spotifyTrack, .playing)))
}

#Preview("Nothing running, cached last played") {
    BoomboxView(controller: .preview(.lastPlayed(musicTrack)))
}

#Preview("Nothing running, nothing cached") {
    BoomboxView(controller: .preview(.nothing))
}

// One app's Automation permission denied: its adapter yields nothing, so the
// panel behaves as if only the permitted app exists — here neither, so the
// neutral empty state (never an error).
#Preview("Permission denied for the only running app") {
    BoomboxView(controller: .preview(.nothing))
}
