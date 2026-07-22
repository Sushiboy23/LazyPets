# LazyPets — Claude context

macOS **accessory app** (no Dock icon, `LSUIElement`): sprite pets (pixel art +
one anime-style pet) live on top of
the macOS Dock, roam, attack files dragged onto them (moving them to the Bin), and
carry per-pet click panels: focus timers, one shared task list, Boombox (music
now-playing/control), and Dial (audio devices/volume). Plain AppKit lifecycle
(`main.swift` + `AppDelegate`), SwiftUI for panels/windows, SpriteKit for the pets.
SwiftPM package; no third-party dependencies.

**Feature pattern** (follow it for new per-pet features): the manage window
*assigns* a feature to a pet (persisted set + toggle list page); the dropdown row
shows an icon only for assigned features, and clicking that icon *arms/disarms*
(`PetFeature` + `disabledFeatures` on the model) without removing the assignment.
Consumers must use the `active*` computed sets, never the raw assignment sets.

## Build / run workflow

- Compile-check: `BuildProject` (Xcode MCP) or `swift build`.
- Ship + test locally: `./build_app.sh` (release build → `LazyPets.app` bundle →
  **ad-hoc codesign**, required for UserNotifications), then
  `pkill -x LazyPets; open LazyPets.app`.
- The user's standing rule: **rebuild the bundle and relaunch the app after every
  change** unless told they're batching.
- Verify launch with `pgrep -x LazyPets`.

## Architecture map (one line per file)

- `AppDelegate.swift` — central wiring: status item + roster popover, pet click
  popover, manage window, timer/task callbacks, persistence, drop handling. Timer
  completion chime = system "Glass" looped for 3s (`playTimerDoneSound`), gated by
  the "Timer sounds" toggle.
- `PetOverlayCoordinator.swift` — routes pets across displays; owns one
  `PetOverlayWindow` per display UUID; debounced (0.4s) diff-based reconciliation on
  screen changes; orphan/snap-back for pinned pets; broadcasts visual calls to all
  windows (scenes ignore unknown ids).
- `PetOverlayWindow.swift` — click-through `NSPanel` per display holding the SKView +
  `PetScene`; per-window Dock poll (1s) repositions over the Dock.
- `PetScene.swift` / `PetNode.swift` / `PetStateMachine.swift` — SpriteKit pets:
  bottom-anchored sprites, `SKAction.animate` frame steppers, idle/walk/run ambient
  loops, one-shot jump/attack, timer badge nodes, holdsPosition while popover open.
- `PetAnimations.swift` — `PetKind` enum (rawValue = display name = **stable
  persistence key**); slices sprite sheets into `SKTexture` frames (.nearest);
  `bodyUnitRect(for:)` = alpha-scanned visible-body bounds, reused by drop glow,
  click zones, avatars, preview scaling.
- `PetCatalog.swift` — library entries (7 real pets + locked teasers Puppy/Dragon/
  Wizard with `kind == nil`, metadata only); `avatarColor`, `avatarImage` (cropped
  first idle frame, cached).
- `PetRosterView.swift` — `PetRosterModel` (shared ObservableObject: enabled/roster/
  favorites/feature sets, `disabledFeatures` arming, pinned displays,
  `pendingManagePage` one-shot navigation request) + the menu-bar dropdown (360pt
  wide; rows = roster pets + manage row; feature icons appear only when assigned,
  blue = armed / plain = paused).
- `Boombox.swift` / `BoomboxView.swift` — "Boombox" now-playing panel:
  `MediaPlayerAdapter` protocol + Spotify/Apple Music adapters (AppleScript on a
  serial background queue; `isRunning` via NSRunningApplication so a `tell` never
  launches a closed app); coordinator prefers the playing app, sticky tie-break;
  DistributedNotificationCenter events + 3s poll only while visible; last-played
  cache. Never brand with a service name — descriptive "via Spotify" only.
- `AudioDeviceService.swift` / `AudioLevelMonitor.swift` / `DialView.swift` —
  "Dial" audio panel. Service = public CoreAudio C APIs (device list filtered by
  transport type, default in/out switching, volume with main-element →
  channel-1/2 fallback, property listener blocks registered once per device+scope —
  never removed, see gotchas — background queue, **no mic permission**). Monitor = AVAudioEngine mic tap for the input level meter only —
  separate class on purpose (needs mic permission + orange dot), reference-counted
  strictly around Input-panel visibility. `DialAudioBlockView` is one shared view
  for popover + manage page; `scope` lives on the service so the two can't drift.
  The Dial popover tab is always present; unassigned pets get an explanatory
  disabled state, never a silently hidden tab.
- `ManageView.swift` — manage window: sidebar (library/features), search + category
  chips + card grid, preview tab strip, per-feature pages, Displays page, Settings.
- `PetPreviewView.swift` — "Preview: <Pet>" tab; animates with **TimelineView flipping
  NSImage frames** (see gotchas), pills per available animation, CTA by lock/roster
  state.
- `PetTimers.swift` — `PetTimerManager`: per-pet timers, **duration in seconds**,
  absolute `endsAt` persistence + launch reconciliation, 1s ticker only while running.
- `TimerPopoverView.swift` — set (preset chips + custom min/sec + note) / running /
  done modes.
- `TimerNotifier.swift` — UNUserNotificationCenter gated on `Bundle.main.
  bundleIdentifier` (crashes without a real bundle); TrashToast fallback.
- `PetTaskList.swift` / `PetTaskListView.swift` — **one shared task list** for all
  pets (key `sharedTaskList`; legacy per-pet `petTaskLists` migrated once).
  `PetTask`: `isHiddenInPopover` (eye toggle in the manage window filters the task
  out of pet popovers), optional `dueDate` (start-of-day normalized; `isOverdue`),
  editable `createdAt`, and `dateKind` preset (`completeBy` → "Due 22 Jul", red when
  overdue / `createdOn` → "Added 15 Jul" / `hidden` → dates kept, row shows only the
  calendar icon). New optional fields use `decodeIfPresent` + defaults in a custom
  `init(from:)` so old saved tasks keep loading. The add row can stage a due date
  before creating. `PetClickPopoverView` = Timer|Task List|Boombox|Dial segmented
  popover with a "Manage tasks…" link that opens the manage window's Task list page
  (full editor + per-pet click toggles) via `pendingManagePage`. It opens on the
  tab the user last viewed for that pet (`petPopoverLastTabs`, reported back via
  `onTabChange`); a running/done timer overrides and lands on Timer, and a
  last-used tab whose feature was since disarmed falls back to the first enabled
  tab.
- `FileDropController.swift` / `PetClickController.swift` — interactive "islands":
  small floating panels tracking pets (drags at `.popUpMenu`, clicks at `.statusBar`),
  since the main overlay is click-through.
- `PetDisplays.swift` — display identity via `CGDisplayCreateUUIDFromDisplayID`
  (EDID UUID, survives replug; **never** use index/order/CGDirectDisplayID for
  persistence); `DisplayPickerOptions` shared picker.
- `DockGeometry.swift` — Dock height inference: `visibleFrame.minY − frame.minY ≥ 30`
  else flush to screen bottom. There is **no public Dock API**; the Dock's window in
  the window list is full-screen sized (useless for height).
- `TrashToast.swift` — top-right toast, 2.5s auto-dismiss.

## Persistence (UserDefaults keys)

`enabledPetKinds`, `rosterPetKinds`, `attacksFilesPetKinds`, `timerPetKinds`,
`timerSoundsEnabled`, `taskListPetKinds`, `boomboxPetKinds`, `dialPetKinds`,
`disabledPetFeatures` (kind → paused features), `favoritePetKinds`,
`pinnedDisplayUUIDs`, `petPopoverLastTabs` (kind → last click-popover tab),
`petTimers` (JSON), `sharedTaskList` (JSON), `boomboxLastPlayed` (JSON). Keys are
`PetKind.rawValue`; per-launch instance UUIDs map via
`AppDelegate.instanceIDs[kind]`.

## Signing / permissions state

- Dev build = ad-hoc signed, **not sandboxed** (`build_app.sh`, no entitlements).
- `LazyPets.entitlements` exists for future App Store signing only: sandbox +
  scripting-targets (Spotify `com.spotify.library`/`.playback`; Apple Music
  `com.apple.Music.library.read`/`.playback` — bundle ID is `com.apple.Music`) +
  `device.audio-input`. Don't flip the dev build to sandboxed — file-drop-to-Bin
  isn't sandbox-ready.
- Info.plist has `NSAppleEventsUsageDescription` (Boombox, one-time Automation
  prompt per app) and `NSMicrophoneUsageDescription` (Dial level meter only).

## Hard-won gotchas (do not relearn these)

- **`NSPanel.hidesOnDeactivate` defaults TRUE** — must be false on every overlay/
  toast/island panel or windows silently vanish when the app deactivates.
- **SwiftUI `SpriteView` and raw `SKView` both freeze in the manage window** (one
  frame renders, actions never advance). Preview animation therefore uses
  TimelineView + NSImage frame flipping. Overlay SKViews on the desktop are fine.
- Fully transparent windows are skipped by hit-testing — island panels need a layer
  with ≥ ~2% alpha to receive events.
- Accessory app: popovers/windows need `makeKey()` / `NSApp.activate` or text fields
  can't be typed in.
- `NSHostingController.sizingOptions = .preferredContentSize` so popovers resize on
  tab switches; task list uses a fixed-height ScrollView to avoid shrink-after-switch.
- Roster popover is clamped below the menu bar after showing
  (`setFrameTopLeftPoint` vs `visibleFrame.maxY`).
- Don't override `NSWindow.screen` — name collisions (use `assignedScreen`).
- Attack sheets have per-sheet bottom crops; body sizes differ per pet — always scale
  via `bodyUnitRect`, never raw frame size.
- Timer "done" tint is a static `colorBlendFactor`, not an SKAction
  (`removeAllActions` would kill it).
- **`TextField` ignores `.strikethrough` on macOS** — done tasks render as `Text`
  (struck through, not editable) and become fields again when unticked.
- Don't hard-code widths on popovers containing segmented controls — a fixed frame
  clipped the 3-segment date-kind picker; use `.fixedSize(horizontal:)` instead.
- Segmented `Picker` can't style one segment (Dial's disabled tab conveys state
  through its content instead).
- Spotify's sdef deprecates the `artwork` data property — use `artwork url`;
  Apple Music has no artwork URL, only `data of artwork 1` (raw bytes).
- CoreAudio `kAudioObjectPropertyName` returns a +1 CFString — read via
  `Unmanaged<CFString>` + `takeRetainedValue`, not a bare `CFString` var.
- **A Swift closure passed to a C block parameter bridges to a fresh block object
  on every call** — so `AudioObjectRemovePropertyListenerBlock` can never match the
  block that was added; a remove/re-add-per-refresh cycle leaked two listeners each
  time, every leaked listener re-queued a refresh, and the Dial CoreAudio serial
  queue eventually saturated (device switching silently stopped after hours of
  uptime). Volume listeners are therefore registered **once per device+scope**
  (`volumeListenerKeys`, pruned on unplug) and never removed.
- Naming: the feature is always **"Task List"**, never "Daily Tasks".
- **AI-generated sprite sheets need preprocessing** (learned building the Cadet):
  turnaround rows look like animation cycles but aren't (rotation poses, and even
  the "walk" row mixed right/back/left-facing frames); opaque white backgrounds
  must be flood-filled from the borders (a whiteness threshold alone punches holes
  in white clothing); frames whose rifles/props interleave can't be split by
  column cuts — extract by connected components instead. Clean generator output
  (one animation per file, real alpha, uniform grid, e.g. the Cadet's 5×5 v1
  sheets) needs only a rescale — but check whether the last cell duplicates the
  first (drop it or the loop hitches), and rescale so body pixel-height matches
  the pet's other sheets, since one `pixelScale` serves all of a pet's animations.
  The Cadet's sheets are pre-downscaled bakes; her originals live outside the repo.

## Conventions

- 4-space indent; `@State private var`; no Combine (prefer async/await); comments
  explain constraints, not narration. New pets: add sprites + a `PetAnimationSet` in
  `PetAnimations.swift`, a catalog entry, and an `avatarColor` — everything else
  (rows, grids, features, displays) is data-driven off `PetKind.allCases`.
