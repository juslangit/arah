#!/usr/bin/env bash
# Builds the Android release APK, and installs it on a phone plugged in by USB
# when there is one:
#
#   ./tools/android/build.sh
#
# Keys (TOMTOM_API_KEY for live traffic) come from ~/.claude/.env, never the repo.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

source "$HOME/Documents/dev/tools/flutter-env.sh"
set -a; [ -f "$HOME/.claude/.env" ] && . "$HOME/.claude/.env"; set +a
flutter build apk --release --dart-define=TOMTOM_API_KEY="${TOMTOM_API_KEY:-}"

APK=build/app/outputs/flutter-apk/app-release.apk
if adb get-state >/dev/null 2>&1; then
  adb install -r "$APK"
  adb shell monkey -p com.juslangit.arah -c android.intent.category.LAUNCHER 1 >/dev/null
else
  echo "No phone connected; APK at $APK"
fi
