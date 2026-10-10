#!/bin/bash
# ---------------------------------------------------------------------------
# Sync the curated Conky widgets from their live install dirs into this
# repository staging tree.
#
#   ./sync.sh            dry-run (show what would be copied)
#   ./sync.sh --apply    actually sync
#
# Repo-authored files (README.md, ATTRIBUTION.md, screenshots/, wallpapers/,
# fonts/ and .gitignore) are excluded so they survive rsync --delete. Runtime
# logs, backups, session state and secrets are never copied. Live install dirs
# are never modified.
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
cyber-atc		$HOME/.conky/cyber-atc
clockwidget		$HOME/.conky/clockwidget
clockwork-alchemist	$HOME/.conky/clockwork-alchemist
bionic			$HOME/.conky/bionic
orrery-brass		$HOME/.conky/orrery-brass
brasspianobar		$HOME/.conky/brasspianobar
brassviz		$HOME/.conky/brassviz
brass-sysmon		$HOME/.conky/brass-sysmon
brass-lyrics		$HOME/.conky/brass-lyrics
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
add_excl '*.checkpoint-*'
add_excl '*.pre-*'
add_excl 'debug'
add_excl 'plaque-mode'

# Fonts are repo-owned. They ship in the release zip but are not kept in the
# live widget dir, so `rsync --delete` would strip them on every sync. rsync
# leaves excluded files alone unless --delete-excluded is passed, so excluding
# 'fonts' both protects them from deletion and keeps them out of the sync set.
add_excl 'fonts'

# Release imagery is repo-owned. Screenshots (kept at full resolution) and the
# bundled wallpapers ship in the release zips but are not kept in the live
# widget dirs, so `rsync --delete` would strip them on every sync. Excluding
# them keeps them in place and out of the sync set.
add_excl 'wallpapers'
add_excl 'screenshot.png'
add_excl 'screenshot-*.png'

add_excl 'README.md'
add_excl 'ATTRIBUTION.md'

MODE="dry-run"
[ "${1:-}" = "--apply" ] && { MODE="apply"; shift; }

# Optional: restrict the sync to one or more theme names, e.g.
#   ./sync.sh --apply brasspianobar brassviz brass-sysmon brass-lyrics
# With no extra args every pair is synced.
ONLY="${*:-}"

printf '%s\n' "$PAIRS" | while IFS=$'\t' read -r name src; do
  [ -z "$name" ] && continue
  if [ -n "$ONLY" ]; then
    case " $ONLY " in
      *" $name "*) : ;;
      *) continue ;;
    esac
  fi
  [ -d "$src" ] || { echo "MISSING SOURCE: $src"; continue; }
  dest="$ROOT/$name"
  mkdir -p "$dest"
  if [ "$MODE" = "apply" ]; then
    rsync -a --delete "${EXCL[@]}" "$src/" "$dest/"
    echo "synced: $name -> $dest/"
  else
    echo "--- dry-run: $name ---"
    rsync -ainv --delete "${EXCL[@]}" "$src/" "$dest/"
  fi
done