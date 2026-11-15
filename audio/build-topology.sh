#!/bin/bash
# Build the asphalt AudioReach topology from Lenovo-Asphalt.m4.
#
#   audio/build-topology.sh <audioreach-topology checkout> <output-tplg.bin>
#
set -euo pipefail

[[ $# -eq 2 ]] || { sed -n '2,4p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
src="$(cd "$1" && pwd)"
out="$2"
here="$(cd "$(dirname "$0")" && pwd)"
[[ -f "$src/audioreach/audioreach.m4" ]] || { echo "Not an audioreach-topology checkout: $src" >&2; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
m4 -I "$src" -I "$here" "$here/Lenovo-Asphalt.m4" > "$work/Lenovo-Asphalt.conf"
alsatplg -c "$work/Lenovo-Asphalt.conf" -o "$work/Lenovo-Asphalt-tplg.bin"
for mixer in PRIMARY_MI2S_RX DISPLAY_PORT_RX_0; do
    grep -q "$mixer Audio Mixer" "$work/Lenovo-Asphalt-tplg.bin" ||
        { echo "Built topology lacks the $mixer Audio Mixer" >&2; exit 1; }
done
install -m 644 "$work/Lenovo-Asphalt-tplg.bin" "$out"
sha256sum "$out"
