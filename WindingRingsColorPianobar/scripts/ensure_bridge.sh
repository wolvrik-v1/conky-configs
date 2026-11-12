#!/bin/sh
# ensure_bridge.sh - keep the Pianobar -> Conky status bridge alive.
#
# The bridge (pianobar_control.py, bundled beside this script) normalizes
# Pianobar's event files into ~/.cache/conky/pianobar-widget.status, which
# WindingRingsColorPianobar reads. When it dies the panel silently stops
# updating, so run this from BOTH the login autostart (immediate) and a cron
# watchdog (self-healing):
#
#   @reboot  /path/to/ensure_bridge.sh
#   * * * *  /path/to/ensure_bridge.sh
#
# Idempotent and safe to run repeatedly. The bridge is flock-guarded, so even
# a duplicate launch exits immediately on its own.

PATH=/usr/local/bin:/usr/bin:/bin
export PATH

DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
BRIDGE="$DIR/pianobar_control.py"
LOG="$HOME/.cache/conky/pianobar-bridge.log"

[ -f "$BRIDGE" ] || exit 0

# Already running? The bracket trick keeps this pattern from matching the
# pgrep process's own command line. The broad pattern also matches a bridge
# started from another location (e.g. ~/.config/pianobar-widget).
if pgrep -f 'pianobar_contro[l].py' >/dev/null 2>&1; then
    exit 0
fi

mkdir -p "$HOME/.cache/conky" 2>/dev/null

setsid /usr/bin/python3 "$BRIDGE" </dev/null >>"$LOG" 2>&1 &
exit 0
