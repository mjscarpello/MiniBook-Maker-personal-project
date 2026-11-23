#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

clear
printf "\nMiniBook Maker 2.1 — Cut-Stack + Adaptive Punch Builder\n"
printf "=======================================================\n\n"

if ! command -v swift >/dev/null 2>&1; then
  printf "Swift is not installed.\n\n"
  printf "Install Xcode from the Mac App Store, open it once, then run this builder again.\n"
  printf "Press Return to close.\n"
  read
  exit 1
fi

printf "1/4 Running cut-stack + binding regression tests…\n"
TEST_BIN="$ROOT/.minibook-self-test"
swiftc \
  "$ROOT/Sources/MiniBookMaker/ImpositionPlan.swift" \
  "$ROOT/Sources/MiniBookMaker/BindingGeometry.swift" \
  "$ROOT/Tests/main.swift" \
  -o "$TEST_BIN"
"$TEST_BIN"
rm -f "$TEST_BIN"

printf "\n2/4 Building the native Mac app…\n"
swift build -c release

APP_DIR="$ROOT/build/MiniBook Maker 2.app"
EXECUTABLE="$ROOT/.build/release/MiniBookMaker"

printf "\n3/4 Packaging MiniBook Maker 2.app…\n"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$EXECUTABLE" "$APP_DIR/Contents/MacOS/MiniBookMaker"
cp "$ROOT/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
chmod +x "$APP_DIR/Contents/MacOS/MiniBookMaker"

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true
fi

printf "\n4/4 Installing in your user Applications folder…\n"
USER_APPS="$HOME/Applications"
INSTALLED_APP="$USER_APPS/MiniBook Maker 2.app"
mkdir -p "$USER_APPS"
rm -rf "$INSTALLED_APP"
cp -R "$APP_DIR" "$INSTALLED_APP"

xattr -dr com.apple.quarantine "$INSTALLED_APP" >/dev/null 2>&1 || true

printf "\nSUCCESS — cut-stack and adaptive punch tests passed.\n"
printf "Installed app:\n%s\n\n" "$INSTALLED_APP"
printf "Version: MiniBook Maker 2.1\n"
printf "Full exports end in: MB21-CUTSTACK-VERIFIED.pdf\n\n"
printf "Opening the exact newly-built app now…\n"
open "$INSTALLED_APP"

printf "\nYou can open it later with Spotlight by typing: MiniBook Maker 2\n"
printf "Press Return to close this window.\n"
read
