#!/bin/bash
# Feeds the Bluetooth sink monitor audio into cava's fifo input.
# Resolve the Bluetooth A2DP sink monitor generically (no hardcoded MACs).
SRC=$(pactl list sources short 2>/dev/null | awk '{print $2}' \
      | grep 'bluez_sink\..*\.a2dp_sink\.monitor' | head -1)
SRC=${SRC:-'@DEFAULT_SOURCE@'}
IN=/tmp/cx_in_fifo

if [ ! -p "$IN" ]; then
  rm -f "$IN"
  mkfifo "$IN"
fi

while true; do
  parec --device="$SRC" --format=s16le --rate=44100 --channels=2 > "$IN" 2>/dev/null
  sleep 0.5
done