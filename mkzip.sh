#!/bin/bash
# Build <theme>/<theme>-conky.zip from the repository tree.
#   ./mkzip.sh <theme> [<theme> ...]
#   ./mkzip.sh                       # rebuild every theme that already ships a zip
set -eu
ROOT="$(cd "$(dirname "$0")" && pwd)"

build() {
  name="$1"; dir="$ROOT/$name"
  [ -d "$dir" ] || { echo "MISSING THEME: $name" >&2; return 1; }
  readme=""
  if [ -f "$dir/README.md" ]; then readme="$dir/README.md"
  elif [ -f "$dir/README" ]; then readme="$dir/README"; fi
  [ -n "$readme" ] || { echo "SKIP $name: no README"; return 0; }
  [ -f "$dir/screenshot.png" ] || { echo "SKIP $name: no screenshot.png"; return 0; }

  stage="$(mktemp -d)"; out="$stage/$name-conky"
  mkdir -p "$out/$name"
  rsync -a \
        --exclude 'README' --exclude 'README.md' \
        --exclude 'screenshot.png' --exclude 'screenshot-*.png' \
        --exclude '*Family*.png' --exclude 'wallpapers/' --exclude '*.zip' \
        "$dir/" "$out/$name/"
  cp "$ROOT/LICENSE" "$out/LICENSE"
  cp "$readme" "$out/README.md"
  cp "$dir/screenshot.png" "$out/screenshot.png"
  [ -d "$dir/wallpapers" ] && cp -a "$dir/wallpapers" "$out/wallpapers"

  rm -f "$dir/$name-conky.zip"
  ( cd "$stage" && zip -rqX "$dir/$name-conky.zip" "$name-conky" )
  rm -rf "$stage"
  echo "built: $name/$name-conky.zip"
}

if [ "$#" -gt 0 ]; then
  for t in "$@"; do build "$t"; done
else
  for d in "$ROOT"/*/; do
    n="$(basename "$d")"
    if [ -f "$ROOT/$n/$n-conky.zip" ]; then build "$n"; fi
  done
fi
