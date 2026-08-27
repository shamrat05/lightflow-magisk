#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
module_dir="$repo_dir/module"
dist_dir="$repo_dir/dist"
version="$(sed -n 's/^version=//p' "$module_dir/module.prop" | head -n 1)"
output="$dist_dir/LightFlow-v${version}.zip"

command -v zip >/dev/null 2>&1 || {
  echo "zip is required" >&2
  exit 1
}

test -f "$module_dir/module.prop"
mkdir -p "$dist_dir"
rm -f "$output"

(cd "$module_dir" && zip -9 -q -r "$output" . -x '*.DS_Store')

echo "$output"
