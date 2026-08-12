#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Typewriter"
BUNDLE_ID="ca.alexradford.Typewriter"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/.build/DerivedData"
APP_BUNDLE="$BUILD_DIR/Build/Products/Debug/$APP_NAME.app"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

xcodebuild \
  -project "$PROJECT_DIR/Typewriter.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration Debug \
  -derivedDataPath "$BUILD_DIR" \
  CODE_SIGNING_ALLOWED=NO \
  build

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    VERIFY_LIBRARY_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/TypewriterVerify.XXXXXX")"
    /usr/bin/open -n \
      --env "TYPEWRITER_LIBRARY_ROOT=$VERIFY_LIBRARY_ROOT" \
      "$APP_BUNDLE"
    sleep 2
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
