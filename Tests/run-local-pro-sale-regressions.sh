#!/bin/zsh
set -eu

project_root="$(cd "$(dirname "$0")/.." && pwd)"
test_directory="$(mktemp -d /tmp/ponder-sale-tests.XXXXXX)"
trap 'rm -rf "$test_directory"' EXIT

xcrun swiftc \
    "$project_root/Ponder/models/LocalProSaleCampaign.swift" \
    "$project_root/Tests/LocalProSaleRegression.swift" \
    -o "$test_directory/LocalProSaleRegression"
"$test_directory/LocalProSaleRegression"
