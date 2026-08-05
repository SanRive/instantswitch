#!/bin/sh
# Builds the resident space-switch daemon.
#
# SwiftPM cannot build upstream's GUI app with Command Line Tools alone
# (mismatched PackageDescription), but nothing here needs Swift: the daemon
# is plain C.
set -e
cd "$(dirname "$0")"
OUT="${1:-./spaced}"

clang -O2 -o "$OUT" \
    src/issd.c src/ISS.c src/event_serialize.c \
    -Isrc -Isrc/include \
    -framework ApplicationServices -framework CoreFoundation -framework CoreGraphics

# Ad-hoc sign so the binary has a stable identity for the Accessibility grant.
# NOTE: the grant is tied to the code hash. Rebuilding invalidates it and you
# must remove and re-add the binary in System Settings.
codesign --force --sign - -i spaced "$OUT"

echo "built: $OUT"
echo "Next: grant it Accessibility permission (see README.md), then run it."
