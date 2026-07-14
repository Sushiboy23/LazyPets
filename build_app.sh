#!/bin/bash
# Builds LazyPets and packages it as a proper .app bundle (needed for
# LSUIElement / Info.plist to take effect — `swift run` alone won't apply it).
#
# Usage: ./build_app.sh
# Output: ./LazyPets.app

set -euo pipefail

cd "$(dirname "$0")"

echo "Building (release)…"
swift build -c release

APP="LazyPets.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp .build/release/LazyPets "$APP/Contents/MacOS/LazyPets"
cp Info.plist "$APP/Contents/Info.plist"

# The sprite sheets live in the SwiftPM-generated resource bundle, loaded at
# runtime via Bundle.module. Copy it in so the packaged app can find them.
cp -R .build/release/LazyPets_LazyPets.bundle "$APP/Contents/Resources/"

echo "Built $APP"
echo "Run with: open $APP"
