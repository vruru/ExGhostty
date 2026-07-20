#!/bin/sh

set -eu

project_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
cd "$project_dir"

app_path="$project_dir/zig-out/ExGhostty.app"
dmg_path="$project_dir/zig-out/ExGhostty.dmg"
release_tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/exghostty-release.XXXXXX")
tmp_dmg_path="$release_tmp_dir/ExGhostty.dmg"
trap 'rm -rf -- "$release_tmp_dir"' EXIT HUP INT TERM

# Never leave a stale release artifact that could be mistaken for this build.
rm -rf -- "$project_dir/zig-out"
zig build -Doptimize=ReleaseSmall
"$project_dir/package-dmg.sh" "$app_path" "$tmp_dmg_path"

# 发布目录只保留 DMG；其中已经包含完整 app 和 Applications 快捷方式。
rm -rf -- "$project_dir/zig-out"
mkdir -p "$project_dir/zig-out"
mv -- "$tmp_dmg_path" "$dmg_path"

echo "Created $dmg_path"
