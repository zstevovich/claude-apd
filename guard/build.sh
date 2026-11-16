#!/bin/bash
# Builds apd-guard for the four platforms APD ships and writes the binaries to
# plugins/apd/bin/compiled/. The build is reproducible: the same source and the
# Go toolchain named in go.mod give the same bytes on any machine, which is
# what lets CI check that the committed binaries match the source.
#
#   bash guard/build.sh            build into plugins/apd/bin/compiled
#   bash guard/build.sh <dir>      build into <dir> (CI compares against the committed ones)
set -euo pipefail
cd "$(dirname "$0")"
OUT="${1:-../plugins/apd/bin/compiled}"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
for target in darwin/amd64 darwin/arm64 linux/amd64 linux/arm64; do
  os="${target%/*}"; arch="${target#*/}"
  CGO_ENABLED=0 GOOS="$os" GOARCH="$arch" GOFLAGS=-mod=readonly \
    go build -trimpath -buildvcs=false -ldflags "-s -w -buildid=" -o "$OUT/apd-guard-$os-$arch" ./cmd/apd-guard
  echo "built apd-guard-$os-$arch"
done
