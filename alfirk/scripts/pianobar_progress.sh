#!/bin/bash

DURATION=$(cat /tmp/pianobar_duration 2>/dev/null)
START=$(cat /tmp/pianobar_songstart 2>/dev/null)

if [ -z "$DURATION" ] || [ -z "$START" ] || [ "$DURATION" -eq 0 ] 2>/dev/null; then
    echo "───────────────────────"
    exit 0
fi

NOW=$(date +%s)
ELAPSED=$((NOW - START))

[ "$ELAPSED" -lt 0 ] && ELAPSED=0
[ "$ELAPSED" -gt "$DURATION" ] && ELAPSED="$DURATION"

PERCENT=$((ELAPSED * 100 / DURATION))

# 23 characters wide to match 12 CAVA bars + 11 spaces
FILLED=$((PERCENT * 23 / 100))
EMPTY=$((23 - FILLED))

SBAR=""
for ((i = 0; i < FILLED; i++)); do SBAR+="━"; done
for ((i = 0; i < EMPTY; i++)); do SBAR+="─"; done
echo "$SBAR"