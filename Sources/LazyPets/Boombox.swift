import AppKit
import Foundation

// MARK: - Model

/// One playable/displayable track. `appName` is descriptive text only
/// ("via Spotify") — the feature itself is always branded "Boombox".
struct BoomboxTrack: Codable, Equatable {
    var title: String
    var artist: String
    var album: String
    var appName: String
    var artworkURL: URL?

    /// Identity for artwork caching — good enough across polls.
    var key: String { "\(appName)|\(title)|\(artist)" }
}

enum BoomboxPlayback: String {
    case playing
    case paused
    case stopped
}

// MARK: - Adapter protocol

/// One supported music app. Adding another app (VLC, Podcasts, IINA…) is
/// just a new conformer added to `BoomboxController.adapters` — the UI layer
/// never sees app-specific logic. All methods that send Apple Events are
/// called on the controller's background queue, never the main thread.
protocol MediaPlayerAdapter {
    var bundleIdentifier: String { get }
    var appName: String { get }
    /// Checked via NSRunningApplication (no Apple Event, no launch side
    /// effect — a `tell` to a closed app would launch it).
    var isRunning: Bool { get }
    /// Nil when not running, no track is loaded, scripting failed, or the
    /// user denied the Automation permission for this app. A denial for one
    /// app must not affect the others.
    func currentTrack() -> (track: BoomboxTrack, state: BoomboxPlayback)?
    /// Raw artwork bytes for apps that expose data instead of a URL.
    func artworkData() -> Data?
    func togglePlayPause()
}

extension MediaPlayerAdapter {
    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }
}

/// Executes AppleScript synchronously, returning nil on any error (including
/// Automation-permission denial, error -1743) — callers fail into the empty
/// state rather than surfacing errors. NSAppleScript is documented as
/// main-thread-only but is reliably used on a single serial background queue
/// in practice; keeping it off the main thread is what prevents a slow or
/// stalled target app from freezing the UI.
private enum BoomboxScript {
    static func run(_ source: String) -> NSAppleEventDescriptor? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        return error == nil ? result : nil
    }
}

// MARK: - Adapters

/// Spotify (com.spotify.client). Verified against its current sdef:
/// `player state`, `current track` (name/artist/album/`artwork url`),
/// `playpause`. Scripting access groups: com.spotify.library,
/// com.spotify.playback.
struct SpotifyAdapter: MediaPlayerAdapter {

    let bundleIdentifier = "com.spotify.client"
    let appName = "Spotify"

    func currentTrack() -> (track: BoomboxTrack, state: BoomboxPlayback)? {
        guard isRunning else { return nil }
        let source = """
        tell application "Spotify"
            set ps to player state as text
            set out to "" & linefeed & "" & linefeed & "" & linefeed & "" & linefeed & ps
            try
                set t to current track
                set out to (name of t) & linefeed & (artist of t) & linefeed & (album of t) & linefeed & (artwork url of t) & linefeed & ps
            end try
        end tell
        out
        """
        guard let raw = BoomboxScript.run(source)?.stringValue else { return nil }
        let parts = raw.components(separatedBy: "\n")
        guard parts.count >= 5, !parts[0].isEmpty else { return nil }
        let track = BoomboxTrack(
            title: parts[0],
            artist: parts[1],
            album: parts[2],
            appName: appName,
            artworkURL: URL(string: parts[3])
        )
        return (track, BoomboxPlayback(rawValue: parts[4]) ?? .paused)
    }

    func artworkData() -> Data? { nil } // artwork comes via URL instead

    func togglePlayPause() {
        guard isRunning else { return }
        _ = BoomboxScript.run(#"tell application "Spotify" to playpause"#)
    }
}

/// Apple Music (com.apple.Music — the post-Catalina bundle ID, verified via
/// mdls on this machine). Verified against its current sdef: `player state`,
/// `current track`, `playpause`, and artwork exposed as `data of artwork 1`
/// (no URL — the artwork ships as raw bytes). Scripting access groups:
/// com.apple.Music.library.read, com.apple.Music.playback.
struct AppleMusicAdapter: MediaPlayerAdapter {

    let bundleIdentifier = "com.apple.Music"
    let appName = "Apple Music"

    func currentTrack() -> (track: BoomboxTrack, state: BoomboxPlayback)? {
        guard isRunning else { return nil }
        let source = """
        tell application "Music"
            set ps to player state as text
            set out to "" & linefeed & "" & linefeed & "" & linefeed & ps
            try
                set t to current track
                set out to (name of t) & linefeed & (artist of t) & linefeed & (album of t) & linefeed & ps
            end try
        end tell
        out
        """
        guard let raw = BoomboxScript.run(source)?.stringValue else { return nil }
        let parts = raw.components(separatedBy: "\n")
        guard parts.count >= 4, !parts[0].isEmpty else { return nil }
        let track = BoomboxTrack(
            title: parts[0],
            artist: parts[1],
            album: parts[2],
            appName: appName,
            artworkURL: nil
        )
        // Music also reports "fast forwarding"/"rewinding"; treat anything
        // actively advancing as playing.
        let state: BoomboxPlayback
        switch parts[3] {
        case "playing", "fast forwarding", "rewinding": state = .playing
        case "paused": state = .paused
        default: state = .stopped
        }
        return (track, state)
    }

    func artworkData() -> Data? {
        guard isRunning else { return nil }
        let source = """
        tell application "Music"
            set d to data of artwork 1 of current track
        end tell
        d
        """
        return BoomboxScript.run(source)?.data
    }

    func togglePlayPause() {
        guard isRunning else { return }
        _ = BoomboxScript.run(#"tell application "Music" to playpause"#)
    }
}

// MARK: - Controller

/// Surfaces one "now playing" across all supported apps and remembers the
/// last-played track when nothing is running. Event-driven via distributed
/// notifications, plus a light 3s poll only while the panel is visible.
final class BoomboxController: ObservableObject {

    enum Display {
        /// Nothing running and nothing cached — neutral empty state.
        case nothing
        /// Nothing running now, but this played earlier. Controls disabled.
        case lastPlayed(BoomboxTrack)
        case nowPlaying(BoomboxTrack, BoomboxPlayback)
    }

    @Published private(set) var display: Display = .nothing
    @Published private(set) var artwork: NSImage?

    private let adapters: [MediaPlayerAdapter]
    private let queue = DispatchQueue(label: "com.zac.lazypets.boombox")
    private var pollTimer: Timer?
    /// Bundle id of the adapter currently on screen — the tie-break sticks
    /// to it so the panel doesn't flip-flop between two paused apps.
    private var surfacedBundleID: String?
    private var artworkTrackKey: String?
    private let live: Bool

    private static let cacheKey = "boomboxLastPlayed"

    init(live: Bool = true, adapters: [MediaPlayerAdapter] = [SpotifyAdapter(), AppleMusicAdapter()]) {
        self.live = live
        self.adapters = adapters
        if let data = UserDefaults.standard.data(forKey: Self.cacheKey),
           let track = try? JSONDecoder().decode(BoomboxTrack.self, from: data) {
            display = .lastPlayed(track)
        }
        guard live else { return }
        // Spotify posts PlaybackStateChanged on every play/pause/track
        // change; Music posts playerInfo (the com.apple.iTunes.playerInfo
        // successor). Observing both keeps the last-played cache fresh even
        // while no panel is open. The poll below covers anything missed.
        let center = DistributedNotificationCenter.default()
        center.addObserver(
            self, selector: #selector(playbackChanged),
            name: Notification.Name("com.spotify.client.PlaybackStateChanged"), object: nil
        )
        center.addObserver(
            self, selector: #selector(playbackChanged),
            name: Notification.Name("com.apple.Music.playerInfo"), object: nil
        )
    }

    /// Preview factory — fixed state, no scripting, no observers.
    static func preview(_ display: Display, artwork: NSImage? = nil) -> BoomboxController {
        let controller = BoomboxController(live: false)
        controller.display = display
        controller.artwork = artwork
        return controller
    }

    @objc private func playbackChanged() {
        refresh()
    }

    /// The panel drives this from onAppear/onDisappear; polling only runs
    /// while something is actually watching.
    func setPanelVisible(_ visible: Bool) {
        guard live else { return }
        pollTimer?.invalidate()
        pollTimer = nil
        if visible {
            refresh()
            pollTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
                self?.refresh()
            }
        }
    }

    func togglePlayPause() {
        guard live, case .nowPlaying(let track, let state) = display,
              let adapter = adapters.first(where: { $0.bundleIdentifier == surfacedBundleID }) else { return }
        // Optimistic flip so the button feels instant; the follow-up refresh
        // reconciles with the app's real state.
        display = .nowPlaying(track, state == .playing ? .paused : .playing)
        queue.async { [weak self] in
            adapter.togglePlayPause()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self?.refresh() }
        }
    }

    func refresh() {
        guard live else { return }
        queue.async { [weak self] in
            guard let self else { return }
            let results = adapters.compactMap { adapter -> (String, BoomboxTrack, BoomboxPlayback)? in
                guard let (track, state) = adapter.currentTrack() else { return nil }
                return (adapter.bundleIdentifier, track, state)
            }
            // Pick which app to surface: (1) an actively playing app always
            // wins; (2) otherwise any app with a loaded track; ties keep the
            // previously surfaced app if it's still eligible, else fall back
            // to adapter declaration order (Spotify first). Stickiness is a
            // judgment call — it stops the panel flapping between two paused
            // apps on every poll.
            let chosen = pick(from: results.filter { $0.2 == .playing })
                ?? pick(from: results)
            DispatchQueue.main.async {
                self.apply(chosen)
            }
        }
    }

    private func pick(
        from candidates: [(String, BoomboxTrack, BoomboxPlayback)]
    ) -> (String, BoomboxTrack, BoomboxPlayback)? {
        candidates.first { $0.0 == surfacedBundleID } ?? candidates.first
    }

    private func apply(_ chosen: (bundleID: String, track: BoomboxTrack, state: BoomboxPlayback)?) {
        guard let chosen else {
            surfacedBundleID = nil
            // Nothing running: fall back to the cached last-played track.
            if case .nowPlaying(let track, _) = display {
                display = .lastPlayed(track)
            } else if case .lastPlayed = display {
                // keep it
            } else {
                display = .nothing
            }
            return
        }
        surfacedBundleID = chosen.bundleID
        display = .nowPlaying(chosen.track, chosen.state)
        if let data = try? JSONEncoder().encode(chosen.track) {
            UserDefaults.standard.set(data, forKey: Self.cacheKey)
        }
        loadArtworkIfNeeded(for: chosen.track, bundleID: chosen.bundleID)
    }

    /// Artwork is fetched once per track: from the URL when the app provides
    /// one (Spotify), else from raw script data (Apple Music). Failures just
    /// leave the placeholder — never an error state.
    private func loadArtworkIfNeeded(for track: BoomboxTrack, bundleID: String) {
        guard track.key != artworkTrackKey else { return }
        artworkTrackKey = track.key
        artwork = nil
        if let url = track.artworkURL {
            URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                guard let data, let image = NSImage(data: data) else { return }
                DispatchQueue.main.async {
                    guard self?.artworkTrackKey == track.key else { return }
                    self?.artwork = image
                }
            }.resume()
        } else if let adapter = adapters.first(where: { $0.bundleIdentifier == bundleID }) {
            queue.async { [weak self] in
                guard let data = adapter.artworkData(), let image = NSImage(data: data) else { return }
                DispatchQueue.main.async {
                    guard self?.artworkTrackKey == track.key else { return }
                    self?.artwork = image
                }
            }
        }
    }
}
