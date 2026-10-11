#!/bin/zsh
set -eu

project_root="$(cd "$(dirname "$0")/.." && pwd)"
test_directory="$(mktemp -d /tmp/ponder-scribble-tests.XXXXXX)"
trap 'rm -rf "$test_directory"' EXIT
bundle_contents="$test_directory/Regression.app/Contents"
mkdir -p "$bundle_contents/MacOS"

# PencilKit's replica manager requires a bundle identifier when existing
# strokes are reused across drawings. Run the tests in an isolated app bundle.
cat > "$bundle_contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.ponder.scribble-regression</string>
<key>CFBundleExecutable</key><string>Regression</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST

xcrun swiftc \
    "$project_root/Ponder/Views/Canvas/ScribbleEraser.swift" \
    "$project_root/Tests/ScribbleEraserRegression.swift" \
    -o "$bundle_contents/MacOS/Regression"
"$bundle_contents/MacOS/Regression"
