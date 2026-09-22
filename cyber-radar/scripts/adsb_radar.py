#!/usr/bin/env python3
import json
import math
import os
import signal
import sys
import time
import urllib.request

STATE = os.path.expanduser('~/.cache/conky/cyber-adsb.status')
LINK = os.path.expanduser('~/.cache/conky/cyber-adsb.link')
CONKY_GUARD = '[c]onky .*(cyber-deckrc|cyber-radarrc)'

CENTER_LAT, CENTER_LON = 40.4915, -80.2327   # Pittsburgh Intl (KPIT)
FETCH_DIST = 60                               # nm radius to ask the feed for
RANGE_NM = 55.0                               # display radius (radar rim position)
FETCH_URL = ('https://api.adsb.lol/v2/lat/%.4f/lon/%.4f/dist/%d'
             % (CENTER_LAT, CENTER_LON, FETCH_DIST))
POLL = 10
LOCK = STATE + '.lock'

R_EARTH_NM = 3440.065

def hav(a, b):
    p1, p2 = math.radians(a[0]), math.radians(b[0])
    dp = math.radians(a[0] - b[0])
    dl = math.radians(a[1] - b[1])
    h = math.sin(dp/2)**2 + math.cos(p1)*math.cos(p2)*math.sin(dl/2)**2
    return 2 * R_EARTH_NM * math.asin(math.sqrt(h))

def bearing(a, b):
    p1, p2 = math.radians(a[0]), math.radians(b[0])
    dl = math.radians(b[1] - a[1])
    y = math.sin(dl) * math.cos(p2)
    x = math.cos(p1)*math.sin(p2) - math.sin(p1)*math.cos(p2)*math.cos(dl)
    return (math.degrees(math.atan2(y, x)) + 360) % 360

def conky_alive():
    try:
        out = os.popen('pgrep -f "%s"' % CONKY_GUARD).read().strip()
        return bool(out)
    except Exception:
        return False

def fetch():
    req = urllib.request.Request(FETCH_URL, headers={'User-Agent': 'cyber-adsb/1.0'})
    with urllib.request.urlopen(req, timeout=15) as r:
        return json.load(r)

def main():
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    os.makedirs(os.path.dirname(STATE), exist_ok=True)
    while True:
        if not conky_alive():
            time.sleep(10)
            continue
        epoch = time.time()
        try:
            data = fetch()
            out = ['TS %.2f' % epoch]
            n = 0
            for a in data.get('ac', []):
                la, lo = a.get('lat'), a.get('lon')
                if la is None or lo is None:
                    continue
                d = hav((CENTER_LAT, CENTER_LON), (la, lo))
                if d > RANGE_NM:
                    continue
                brg = bearing((CENTER_LAT, CENTER_LON), (la, lo))
                fl = (a.get('flight') or '').strip()
                atype = (a.get('t') or '').strip()
                alt = a.get('alt_baro')
                try:
                    alt = int(float(alt))
                except (TypeError, ValueError):
                    alt = '-'
                gs = a.get('gs')
                try:
                    gs = int(float(gs))
                except (TypeError, ValueError):
                    gs = '-'
                out.append('%s %.1f %.1f %s %s %s %s' % (
                    a.get('hex', '?'), brg, d, alt, gs, fl or '-', atype or '-'))
                n += 1
            out.insert(1, 'N %d' % n)
            tmp = STATE + '.tmp'
            with open(tmp, 'w') as f:
                f.write('\n'.join(out) + '\n')
            os.replace(tmp, STATE)
            with open(LINK, 'w') as f:
                f.write('link ok %d tracks\n' % n)
        except Exception as e:
            with open(LINK, 'w') as f:
                f.write('link down %s\n' % e.__class__.__name__)
        time.sleep(POLL)

if __name__ == '__main__':
    main()