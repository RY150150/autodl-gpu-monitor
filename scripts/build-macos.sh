#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PYTHON="${PYTHON:-python3}"
if [[ "$(uname -s)" != Darwin || "$(uname -m)" != arm64 ]]; then
    printf 'This build script requires an Apple Silicon Mac.\n' >&2
    exit 1
fi
APP="$ROOT/dist/AutoDLMonitor.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ROOT/.build"
"$PYTHON" -m PyInstaller --noconfirm --clean --onefile \
    --name autodl_watch --collect-all playwright --hidden-import greenlet \
    --distpath "$ROOT/.build/worker-dist" --workpath "$ROOT/.build/worker" \
    --specpath "$ROOT/.build" "$ROOT/src/autodl_watch.py"
swiftc -O -parse-as-library -framework AppKit \
    "$ROOT/src/AutoDLMonitor.swift" "$ROOT/src/RentalHistory.swift" \
    -o "$APP/Contents/MacOS/AutoDLMonitor"
cp "$ROOT/src/AutoDLMonitor-Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/.build/worker-dist/autodl_watch" "$APP/Contents/Resources/autodl_watch"
cp "$ROOT/src/autodl_watch.py" "$APP/Contents/Resources/autodl_watch.py"
chmod 755 "$APP/Contents/MacOS/AutoDLMonitor" "$APP/Contents/Resources/autodl_watch"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ROOT/dist/AutoDLMonitor-macOS-AppleSilicon.zip"
(
    cd "$ROOT/dist"
    shasum -a 256 AutoDLMonitor-macOS-AppleSilicon.zip > AutoDLMonitor-macOS-AppleSilicon.zip.sha256
)
printf 'Built %s\n' "$ROOT/dist/AutoDLMonitor-macOS-AppleSilicon.zip"
