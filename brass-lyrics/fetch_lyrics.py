#!/usr/bin/env python3
"""brass-lyrics fetcher -- watches the pianobar status cache and keeps a
synced-LRC cache next to it for the conky renderer.

Inputs : ~/.cache/conky/pianobar-widget.status   (title|artist|album|dur|pos|state)
Outputs: ~/.cache/conky/brass-lyrics.meta        (key=value lines, atomically replaced)
         ~/.cache/conky/brass-lyrics.lrc         (raw synced LRC, may be empty)

LRCLIB (https://lrclib.net) -- no API key. Tries the exact /api/get endpoint
first, falls back to /api/search (get has been flaky/503-prone). A track that
yields no lyrics is remembered for the session so we never re-hit the API.
"""

import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

HOME = os.path.expanduser("~")
CACHE = os.path.join(HOME, ".cache", "conky")
STATUS = os.path.join(CACHE, "pianobar-widget.status")
META = os.path.join(CACHE, "brass-lyrics.meta")
LRC = os.path.join(CACHE, "brass-lyrics.lrc")

POLL = 2.0
UA = {"User-Agent": "brass-lyrics-conky/1.0 (conky widget)",
      "Accept": "application/json"}


def http_json(url, timeout=12):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.load(r)


def read_status():
    try:
        with open(STATUS, "r", encoding="utf-8", errors="replace") as f:
            line = f.read().strip()
    except OSError:
        return None
    parts = line.split("|")
    if len(parts) < 6:
        return None
    return {"title": parts[0], "artist": parts[1], "album": parts[2],
            "duration": parts[3], "position": parts[4], "state": parts[5]}


def write_atomic(path, text):
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(text)
    os.replace(tmp, path)


def write_meta(st, found, source):
    lines = [
        "state=%s" % (st["state"] if st else "offline"),
        "title=%s" % (st["title"] if st else ""),
        "artist=%s" % (st["artist"] if st else ""),
        "album=%s" % (st["album"] if st else ""),
        "duration=%s" % (st["duration"] if st else "0"),
        "found=%d" % found,
        "source=%s" % source,
        "updated=%d" % int(time.time()),
    ]
    write_atomic(META, "\n".join(lines) + "\n")


def best_hit(hits, title, artist):
    """Prefer synced lyrics + closest title/artist match."""
    t = title.strip().lower()
    a = artist.strip().lower()

    def score(h):
        ht = (h.get("trackName") or "").strip().lower()
        ha = (h.get("artistName") or "").strip().lower()
        s = 0
        if h.get("syncedLyrics"):
            s += 100
        if ht == t:
            s += 20
        elif t in ht or ht in t:
            s += 10
        if a and (a in ha or ha in a):
            s += 8
        return s

    if not hits:
        return None
    return max(hits, key=score)


def backoff_for(attempts):
    """First try immediately, then 15s, 30s, ... capped at 60s.
    Never gives up while the track plays -- lrclib 503s are transient."""
    if attempts <= 0:
        return 0.0
    return float(min(15 * attempts, 60))


def fetch_lyrics(st):
    """Return (lrc_text, source). 'net-fail' means retry later,
    everything else is a DEFINITIVE answer safe to cache."""
    q_get = urllib.parse.urlencode({
        "track_name": st["title"],
        "artist_name": st["artist"],
        "album_name": st["album"],
    })
    plain = False
    try:
        d = http_json("https://lrclib.net/api/get?" + q_get)
        s = d.get("syncedLyrics") or ""
        if s:
            return s, "lrclib"
        if d.get("plainLyrics"):
            plain = True   # keep going -- search may still find a synced one
    except Exception:
        pass  # 503/404/timeout -- fall through to search

    time.sleep(0.4)  # polite gap between the two API calls
    q_s = urllib.parse.urlencode({"q": "%s %s" % (st["title"], st["artist"])})
    try:
        hits = http_json("https://lrclib.net/api/search?" + q_s)
    except Exception:
        return ("", "plain-only") if plain else ("", "net-fail")
    if isinstance(hits, dict):
        hits = [hits]
    h = best_hit(hits if isinstance(hits, list) else [], st["title"], st["artist"])
    if h and h.get("syncedLyrics"):
        return h["syncedLyrics"], "lrclib-search"
    return ("", "plain-only") if plain else ("", "none")


def main():
    os.makedirs(CACHE, exist_ok=True)
    last_key = None      # "title\nartist" of current track
    found = -1           # -1 unknown/retry, 0 definitively none, 1 have LRC
    attempt_ts = 0.0
    attempts = 0
    last_state = None

    while True:
        st = read_status()
        if st is None:
            if last_state != "offline":
                # wipe + FULL reset: on recovery even the same track must be
                # re-fetched, else found=1 with an emptied LRC sticks forever
                write_meta(None, -1, "offline")
                write_atomic(LRC, "")
                last_key, found, attempts, attempt_ts = None, -1, 0, 0.0
                last_state = "offline"
            time.sleep(POLL)
            continue

        key = "%s\n%s" % (st["title"], st["artist"])
        state = st["state"]

        if key != last_key:
            # new track: reset and fetch right away
            last_key, found, attempts, attempt_ts = key, -1, 0, 0.0

        # (re)try until the API gives a DEFINITIVE answer. A network failure
        # must never be cached as "no lyrics" -- lrclib 503s intermittently.
        if found == -1 and (time.time() - attempt_ts) >= backoff_for(attempts):
            attempt_ts = time.time()
            attempts += 1
            lrc, source = fetch_lyrics(st)
            if source == "net-fail":
                write_meta(st, -1, "retry")
                last_state = state
            else:
                write_atomic(LRC, lrc)
                found = 1 if lrc else 0
                write_meta(st, found, source)
                last_state = state
        elif state != last_state:
            write_meta(st, found, "cached")
            last_state = state

        time.sleep(POLL)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:
        # never let the watcher die silently -- log and keep going
        try:
            with open(META + ".err", "a") as f:
                f.write("%s %s\n" % (int(time.time()), e))
        except OSError:
            pass
        raise
