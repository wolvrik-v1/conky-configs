#!/bin/bash
# Reads cava's raw ascii stream and publishes plain integers for the renderer.
# Range is 0..64 (not the shared conf's 0..8) -- 9 steps was too coarse: bands
# read as frozen. This file is brassviz's own; cava_bars.txt consumers untouched.
FIFO=/tmp/brassviz_fifo
OUT=/tmp/brassviz_vals.txt
N=12
ZERO=$(printf '0 %.0s' $(seq 1 $N)); ZERO=${ZERO% }

cleanup() { exec 3<&- 2>/dev/null; exit 0; }
trap cleanup EXIT INT TERM

[ -p "$FIFO" ] || mkfifo "$FIFO"
exec 3<>"$FIFO"

reconnect() {
  exec 3<&- 2>/dev/null
  [ -p "$FIFO" ] || mkfifo "$FIFO"
  exec 3<>"$FIFO"
}

while true; do
  if read -r -t 2 line <&3; then
    acc=""
    IFS=';' read -ra vals <<< "$line"
    for v in "${vals[@]}"; do
      case "$v" in ''|*[!0-9]*) continue ;; esac
      [ "$v" -gt 64 ] && v=64
      acc+="$v "
    done
    [ -n "$acc" ] && printf '%s\n' "${acc% }" > "$OUT" || printf '%s\n' "$ZERO" > "$OUT"
  else
    printf '%s\n' "$ZERO" > "$OUT"
    if [ -f /proc/self/fd/3 ]; then
      pi=$(stat -Lc %i "$FIFO" 2>/dev/null)
      fi=$(stat -Lc %i /proc/self/fd/3 2>/dev/null)
      [ "$pi" = "$fi" ] || reconnect
    else
      reconnect
    fi
  fi
done
