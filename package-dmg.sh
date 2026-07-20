#!/bin/sh

set -eu

project_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
app_path=${1:-"$project_dir/zig-out/ExGhostty.app"}
dmg_path=${2:-"$project_dir/zig-out/ExGhostty.dmg"}

if [ ! -d "$app_path/Contents" ]; then
    echo "error: app bundle not found: $app_path" >&2
    exit 1
fi

mkdir -p "$(dirname -- "$dmg_path")"
staging_dir=$(mktemp -d "${TMPDIR:-/tmp}/exghostty-dmg.XXXXXX")
trap 'rm -rf "$staging_dir"' EXIT HUP INT TERM

ditto "$app_path" "$staging_dir/ExGhostty.app"
ln -s /Applications "$staging_dir/Applications"

hdiutil create \
    -volname "ExGhostty" \
    -srcfolder "$staging_dir" \
    -format UDZO \
    -ov \
    "$dmg_path"

echo "Created $dmg_path"
