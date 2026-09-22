#!/bin/bash
# Supervisor for the Alfirk cava bars pipeline (flock-guarded).
# Invoked periodically by conky ${execi}; only one instance wins the lock.
# Children are spawned with fd 9 closed so they never hold the lock.
DIR="$(cd "$(dirname "$0")" && pwd)"
READER=$DIR/cava_reader.pickle.sh
CAVA_CONF=$DIR/cava_fifo_input.conf
FEEDER=$DIR/parec_feed.pickle.sh
LOCK=/tmp/cava_sup.lock

exec 9>"$LOCK"
flock -n 9 || exit 0

ensure_reader() {
  [ -p /tmp/cava_fifo ] || mkfifo /tmp/cava_fifo
  n=$(pgrep -fc "scripts/cava_reader.pickle.sh")
  if [ "$n" -lt 1 ]; then
    setsid "$READER" 9>&- >/dev/null 2>&1 </dev/null &
  elif [ "$n" -gt 1 ]; then
    pkill -9 -f "scripts/cava_reader.pickle.sh"
    setsid "$READER" 9>&- >/dev/null 2>&1 </dev/null &
  fi
}

ensure_cava() {
  pgrep -f "cava.*cava_fifo_input.conf" >/dev/null || \
    setsid cava -p "$CAVA_CONF" 9>&- >/dev/null 2>&1 </dev/null &
}

ensure_feeder() {
  pgrep -f "scripts/parec_feed.pickle.sh" >/dev/null || \
    setsid "$FEEDER" 9>&- >/dev/null 2>&1 </dev/null &
}

while true; do
  ensure_reader
  ensure_cava
  ensure_feeder
  sleep 3
done