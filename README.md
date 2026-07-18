# LazyPets

Pixel-art pets that live on top of your Mac's Dock — they roam, idle, run across
displays, and do useful work on the side. LazyPets is a menu-bar accessory app
(no Dock icon) built with AppKit + SpriteKit, with SwiftUI for panels and windows.

## Features

- **Pets on the Dock** — pick from a library of animated pixel pets; they walk,
  idle, and run along the Dock on any display, including pinning a pet to a
  specific screen.
- **File attacks** — drag a file onto a pet and it attacks the file, sending it
  to the Bin (with an undo-friendly toast).
- **Focus timers** — click a pet to start a per-pet timer with presets, a note,
  a countdown badge on the pet, and a completion chime/notification.
- **Task List** — one shared task list across all pets, with due dates, overdue
  highlighting, and a full editor in the manage window.
- **Boombox** — a now-playing panel with playback controls for Spotify and
  Apple Music.
- **Dial** — an audio panel for switching input/output devices, adjusting
  volume, and (optionally) a live mic level meter.

Features are assigned per pet in the manage window and can be armed/paused from
the menu-bar dropdown without losing the assignment.

## Requirements

- macOS 13+
- Xcode 15+ (or the standalone Swift toolchain) — this is a native
  AppKit/SpriteKit app, it must be built on a Mac.

## Run it

Fastest way, from Terminal:

```
cd LazyPets
swift run
```

This launches the app directly. Note: running via `swift run` does *not* apply
`Info.plist` (no bundle), so the app will briefly show in the Dock/app-switcher
during development, and notifications won't work — that's expected and fine for
iterating.

## Build the real .app

```
cd LazyPets
./build_app.sh
open LazyPets.app
```

This produces an ad-hoc-signed `LazyPets.app` with `Info.plist` applied
(`LSUIElement`, so no Dock icon; signing enables timer notifications) — the way
it's meant to run day-to-day.

## Open in Xcode

Xcode can open the `Package.swift` directly (File → Open… → select the
`LazyPets` folder) and build/run/debug from there like a normal project.

## Project layout

```
LazyPets/
  Package.swift
  Info.plist                 — LSUIElement, bundle metadata, usage descriptions
  build_app.sh               — packages the built binary as LazyPets.app
  CLAUDE.md                  — detailed architecture map + hard-won gotchas
  Sources/LazyPets/
    main.swift                 — entry point, sets .accessory activation policy
    AppDelegate.swift          — central wiring: menu bar, popovers, persistence
    PetOverlayCoordinator.swift— routes pets across displays
    PetOverlayWindow.swift     — click-through overlay panel per display
    PetScene/PetNode/…         — SpriteKit pets + state machine + animations
    PetRosterView.swift        — menu-bar dropdown + shared roster model
    ManageView.swift           — manage window (library, features, settings)
    PetTimers/TimerPopoverView — focus timers
    PetTaskList*…              — shared task list
    Boombox*…                  — now-playing panel (Spotify / Apple Music)
    AudioDeviceService/Dial*…  — audio device & volume panel
    FileDropController.swift   — drag-a-file-onto-a-pet handling
```

See `CLAUDE.md` for the full per-file architecture map, persistence keys, and
platform gotchas.

## Permissions

- **Automation (Apple Events)** — asked once per music app, for Boombox.
- **Microphone** — only if you open Dial's input level meter; device switching
  and volume never need it.

The dev build is ad-hoc signed and not sandboxed.

## Art credits

- Male Hero sprites by [Ozzbit Games](https://ozzbit-games.itch.io) (free
  version — personal, non-commercial use; credit required).
