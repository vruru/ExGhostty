#!/bin/sh

set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$project_dir"

app_path="$project_dir/zig-out/ExGhostty.app"

zig build -Doptimize=ReleaseSmall
"$project_dir/package-dmg.sh" "$app_path"

# 发布产物只保留 DMG；其中已经包含完整 app 和 Applications 快捷方式。
if [ -d "$app_path/Contents" ]; then
    rm -rf -- "$app_path"
fi
