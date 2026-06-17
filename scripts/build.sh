#!/usr/bin/env bash
#
# Build a PRG (simulator) or IQ (store package) for analog-simple.
#
#   scripts/build.sh prg            # simulator build -> bin/analog-simple-<version>.prg
#   scripts/build.sh iq [beta|public]   # store package -> bin/analog-simple-<version>.iq
#                                        # target defaults to beta
#
# The version is read from resources/strings/strings.xml (AppVersion string).
# The output file is named with that version so you always know what's in bin/.
set -euo pipefail

cd "$(dirname "$0")/.."

SDK="$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-9.1.0-2026-03-09-6a872a80b"
KEY=/Users/yeled/Downloads/developer_key
DEVICE=venu445mm

MODE="${1:-prg}"
TARGET="${2:-beta}"

# Read AppVersion from strings.xml
VERSION=$(grep -o 'id="AppVersion">[^<]*' resources/strings/strings.xml | cut -d'>' -f2)
if [[ -z "$VERSION" ]]; then
  echo "error: could not read AppVersion from resources/strings/strings.xml" >&2
  exit 1
fi

mkdir -p bin

case "$MODE" in
  prg)
    OUT="bin/analog-simple-${VERSION}.prg"
    echo "Building PRG: $OUT (device=$DEVICE)"
    java -Xms1g -Dapple.awt.UIElement=true -jar "$SDK/bin/monkeybrains.jar" \
      -o "$OUT" -f monkey.jungle -y "$KEY" -d "$DEVICE"
    # Also write the unversioned prg that monkeydo/the simulator expects
    cp "$OUT" bin/analog-simple.prg
    echo "Done: $OUT (+ bin/analog-simple.prg for monkeydo)"
    ;;

  iq)
    OUT="bin/analog-simple-${VERSION}.iq"
    echo "Stamping manifest for: $TARGET"
    scripts/set-manifest.sh "$TARGET"
    echo "Building IQ: $OUT"
    java -Xms1g -Dapple.awt.UIElement=true -jar "$SDK/bin/monkeybrains.jar" \
      -o "$OUT" -f monkey.jungle -y "$KEY" -e
    echo "Done: $OUT"
    ;;

  *)
    echo "usage: $0 {prg|iq} [beta|public]" >&2
    exit 2
    ;;
esac
