#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
version="$(cat VERSION)"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { printf 'Invalid VERSION\n' >&2; exit 1; }
app_dir="$PWD/dist/Concentration Slop.app"
mkdir -p "$app_dir/Contents/MacOS"
if [[ "${1:-}" == "--universal" ]]; then
    binaries=()
    for architecture in arm64 x86_64; do
        build_args=(-c release --triple "$architecture-apple-macosx14.0" --scratch-path ".build/release-$architecture")
        swift build "${build_args[@]}"
        binary_dir="$(swift build "${build_args[@]}" --show-bin-path)"
        binaries+=("$binary_dir/ConcentrationSlop")
    done
    lipo -create "${binaries[@]}" -output "$app_dir/Contents/MacOS/ConcentrationSlop"
elif [[ $# == 0 ]]; then
    swift build -c release
    binary_dir="$(swift build -c release --show-bin-path)"
    cp "$binary_dir/ConcentrationSlop" "$app_dir/Contents/MacOS/ConcentrationSlop"
else
    printf 'Usage: %s [--universal]\n' "$0" >&2
    exit 1
fi
cat > "$app_dir/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleExecutable</key><string>ConcentrationSlop</string>
    <key>CFBundleIdentifier</key><string>com.concentrationslop.macos</string>
    <key>CFBundleName</key><string>Concentration Slop</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$version</string>
    <key>CFBundleVersion</key><string>$version</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$app_dir"
printf '\nReady: %s\n' "$app_dir"
