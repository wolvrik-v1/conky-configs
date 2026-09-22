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
metalsysmonitor		$HOME/.conky/metalsysmonitor
clockwork-alchemist	$HOME/.conky/clockwork-alchemist
bionic			$HOME/.conky/bionic
cyberdeck		$HOME/.conky/cyberdeck
adsbradar		$HOME/.conky/adsbradar
zenclock		$HOME/.conky/zenclock
clockwidget		$HOME/.conky/clockwidget
clockwidget-orig	$HOME/.conky/clockwidget-orig
etched			$HOME/.conky/Etched_conky_large
alfirk			$HOME/.conky/Alfirk
pickle-pianobar		$HOME/.config/pickle-pianobar-widget
pickle-weather		$HOME/.config/pickle-weather-widget
metal-pianobar		$HOME/.config/metal-pianobar-conky
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
add_excl 'zentimer'
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