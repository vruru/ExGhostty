#!/bin/sh

set -eu

project_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
cd "$project_dir"

app_path="$project_dir/zig-out/ExGhostty.app"
dmg_path="$project_dir/zig-out/ExGhostty.dmg"

# Never leave a stale release artifact that could be mistaken for this build.
rm -rf -- "$app_path"
rm -f -- "$dmg_path"
zig build -Doptimize=ReleaseSmall
"$project_dir/package-dmg.sh" "$app_path" "$dmg_path"

# 发布产物只保留 DMG；其中已经包含完整 app 和 Applications 快捷方式。
if [ -d "$app_path/Contents" ]; then
    rm -rf -- "$app_path"
fi
