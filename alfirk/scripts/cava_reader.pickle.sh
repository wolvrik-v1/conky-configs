#!/bin/bash
FIFO=/tmp/cava_fifo
OUT=/tmp/cava_bars.txt
SPACES="            "

BARS=(" " " " " " "▂" "▃" "▄" "▅" "▆" "▇")

cleanup() {
  exec 3<&- 2>/dev/null
  exit 0
}
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
    if [ -n "$line" ]; then
      out=""
      IFS=';' read -ra vals <<< "$line"
      for v in "${vals[@]}"; do
        case "$v" in
          ''|*[!0-9]*) continue ;;
        esac
        [ "$v" -gt 8 ] && v=8
        out+="${BARS[$v]} "
      done
      printf '%s\n' "${out:-$SPACES}" > "$OUT"
    else
      printf '%s\n' "$SPACES" > "$OUT"
    fi
  else
    printf '%s\n' "$SPACES" > "$OUT"
    if [ -f /proc/self/fd/3 ]; then
      path_inode=$(stat -Lc %i "$FIFO" 2>/dev/null)
      fd_inode=$(stat -Lc %i /proc/self/fd/3 2>/dev/null)
      [ "$path_inode" = "$fd_inode" ] || reconnect
    else
      reconnect
    fi
  fi
done