#!/bin/bash
# ---------------------------------------------------------------------------
# Sync the curated Conky widgets from their live install dirs into this
# repository staging tree.
#
#   ./sync.sh            dry-run (show what would be copied)
#   ./sync.sh --apply    actually sync
#
# Repo-authored files (README.md, screenshot.png, .gitignore) are excluded
# so they survive rsync --delete. Runtime logs, backups, session state and
# secrets are never copied. Live install dirs are never modified.
# ---------------------------------------------------------------------------
set -eu

ROOT="$(cd "$(dirname "$0")" && pwd)"

# "repo-theme-name<TAB>live-source-directory"
PAIRS="
metal-sysmon		$HOME/.conky/metal-sysmon
metal-pianobar		$HOME/.config/metal-pianobar
metal-clock		$HOME/.conky/metal-clock
etched			$HOME/.conky/etched
etched-pianobar		$HOME/.config/etched-pianobar
etched-weather		$HOME/.config/etched-weather
cyber-deck		$HOME/.conky/cyber-deck
cyber-radar		$HOME/.conky/cyber-radar
clockwidget		$HOME/.conky/clockwidget
clockwork-alchemist	$HOME/.conky/clockwork-alchemist
bionic			$HOME/.conky/bionic
"

EXCL=()
add_excl() { EXCL+=( "--exclude=$1" ); }

add_excl '*.log'
add_excl '*.bak'
add_excl '*.bak.*'
add_excl '*.backup*'
add_excl '*.before-*'
add_excl '*.old'
add_excl '*.orig'
add_excl '*.tmp'
add_excl '*~'
add_excl '*.swp'
add_excl '__pycache__/'
add_excl '*.pyc'
add_excl 'openweather.key'
add_excl '*.key'
add_excl 'clockswitch'
add_excl 'fav_check.png'
add_excl 'preview.jpg'
add_excl 'README.md'
add_excl 'screenshot.png'

MODE="dry-run"
[ "${1:-}" = "--apply" ] && MODE="apply"

printf '%s\n' "$PAIRS" | while IFS=$'\t' read -r name src; do
  [ -z "$name" ] && continue
  [ -d "$src" ] || { echo "MISSING SOURCE: $src"; continue; }
  dest="$ROOT/$name"
  mkdir -p "$dest"
  if [ "$MODE" = "apply" ]; then
    rsync -a --delete "${EXCL[@]}" "$src/" "$dest/"
    echo "synced: $name -> $dest/"
  else
    echo "--- dry-run: $name ---"
    rsync -an --delete "${EXCL[@]}" "$src/" "$dest/"
  fi
done