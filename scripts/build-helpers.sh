#!/usr/bin/env bash
# Compiles the Swift helpers into universal (arm64 + x86_64) binaries next to
# their sources. Runs in CI for releases and for contributors working from a
# git checkout; end users get the prebuilt binaries and never need Swift.

set -euo pipefail

PROJ="$(cd "$(dirname "$0")/.." && pwd)"
PLUGINS="$PROJ/sketchybar/plugins"
MIN_MACOS=13.0

build_dir=$(mktemp -d)
trap 'rm -rf "$build_dir"' EXIT

for source_file in "$PLUGINS"/*.swift; do
  helper=$(basename "$source_file" .swift)
  arch_binaries=()
  for arch in arm64 x86_64; do
    arch_binary="$build_dir/$helper-$arch"
    swiftc -O -target "$arch-apple-macos$MIN_MACOS" -o "$arch_binary" "$source_file"
    arch_binaries+=("$arch_binary")
  done
  lipo -create -output "$PLUGINS/$helper" "${arch_binaries[@]}"
  # lipo drops the linker's ad-hoc signature; Apple Silicon refuses unsigned code.
  codesign --force --sign - "$PLUGINS/$helper"
  echo "built $PLUGINS/$helper"
done
