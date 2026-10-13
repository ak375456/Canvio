#!/bin/zsh
set -eu

project_root="$(cd "$(dirname "$0")/.." && pwd)"
test_directory="$(mktemp -d /tmp/ponder-zoom-tests.XXXXXX)"
trap 'rm -rf "$test_directory"' EXIT

xcrun swiftc \
    "$project_root/Ponder/models/CanvasZoomConfiguration.swift" \
    "$project_root/Tests/CanvasZoomRegression.swift" \
    -o "$test_directory/CanvasZoomRegression"
"$test_directory/CanvasZoomRegression"
