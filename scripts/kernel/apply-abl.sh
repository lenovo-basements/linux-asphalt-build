#!/bin/sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
dtc=${DTC:-dtc}
fdtoverlay=${FDTOVERLAY:-fdtoverlay}
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
"$dtc" -q -@ -I dts -O dtb -o "$tmp/abl.dtbo" "$here/tb320fc-abl.dtso"
"$fdtoverlay" -i "$1" -o "$2" "$tmp/abl.dtbo"
