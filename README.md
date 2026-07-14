# LazyPets

A tiny pet that lives on top of your Mac's Dock, idling and occasionally running across it.

## Requirements

- macOS 13+
- Xcode 15+ (or the standalone Swift toolchain) — this is a native AppKit/SpriteKit app, it must be built on a Mac.

## Run it

Fastest way, from Terminal:

```
cd LazyPets
swift run
```

This launches the app directly. Note: running via `swift run` does *not* apply `Info.plist` (no bundle), so the app will briefly show in the Dock/app-switcher during development — that's expected and fine for iterating.

## Build the real .app

```
cd LazyPets
./build_app.sh
open LazyPets.app
```

This produces `LazyPets.app` with `Info.plist` applied (`LSUIElement`, so no Dock icon in the finished build) — the way it's meant to run day-to-day.

## Open in Xcode

Xcode can open the `Package.swift` directly (File → Open… → select the `LazyPets` folder) and build/run/debug from there like a normal project.

## Project layout

```
LazyPets/
  Package.swift
  Info.plist            — LSUIElement, bundle metadata
  build_app.sh           — packages the built binary as LazyPets.app
  Sources/LazyPets/
    main.swift            — entry point, sets .accessory activation policy
    AppDelegate.swift      — menu bar item + owns the overlay window
    PetOverlayWindow.swift — transparent always-on-top NSPanel above the Dock
    DockGeometry.swift     — infers Dock rect from NSScreen visibleFrame delta
    PetScene.swift          — SpriteKit scene sized to the Dock
    PetNode.swift            — pet sprite + placeholder art + walk/idle actions
    PetStateMachine.swift     — randomized idle <-> walk timing
```

## Art credits

- Male Hero sprites by [Ozzbit Games](https://ozzbit-games.itch.io) (free version — personal, non-commercial use; credit required).

## Known limitations (v1, by design — see PLAN.md)

- Placeholder procedural art, not real sprite frames.
- Assumes Dock is at the bottom of the primary screen; doesn't yet handle Dock on left/right or on a secondary display.
- No click/drag interaction — window is click-through.
- No persistence, no multiple pets, no needs/hunger system (planned for v2).
