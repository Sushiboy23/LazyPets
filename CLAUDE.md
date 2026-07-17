# LazyPets — Claude context

macOS **accessory app** (no Dock icon, `LSUIElement`): pixel-art pets live on top of
the macOS Dock, roam, attack files dragged onto them (moving them to the Bin), and
carry per-pet focus timers plus one shared task list. Plain AppKit lifecycle
(`main.swift` + `AppDelegate`), SwiftUI for panels/windows, SpriteKit for the pets.
SwiftPM package; no third-party dependencies.

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
  popover, manage window, timer/task callbacks, persistence, drop handling.
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
- `PetCatalog.swift` — library entries (6 real pets + locked teasers Puppy/Dragon/
  Wizard with `kind == nil`, metadata only); `avatarColor`, `avatarImage` (cropped
  first idle frame, cached).
- `PetRosterView.swift` — `PetRosterModel` (shared ObservableObject: enabled/roster/
  favorites/feature sets, pinned displays, `pendingManagePage` one-shot navigation
  request) + the menu-bar dropdown (360pt wide; rows = roster pets + manage row).
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
  pets (key `sharedTaskList`; legacy per-pet `petTaskLists` migrated once);
  `PetClickPopoverView` = Timer|Task List segmented popover.
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
`timerSoundsEnabled`, `taskListPetKinds`, `favoritePetKinds`, `pinnedDisplayUUIDs`,
`petTimers` (JSON), `sharedTaskList` (JSON). Keys are `PetKind.rawValue`; per-launch
instance UUIDs map via `AppDelegate.instanceIDs[kind]`.

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
- Naming: the feature is always **"Task List"**, never "Daily Tasks".

## Conventions

- 4-space indent; `@State private var`; no Combine (prefer async/await); comments
  explain constraints, not narration. New pets: add sprites + a `PetAnimationSet` in
  `PetAnimations.swift`, a catalog entry, and an `avatarColor` — everything else
  (rows, grids, features, displays) is data-driven off `PetKind.allCases`.
