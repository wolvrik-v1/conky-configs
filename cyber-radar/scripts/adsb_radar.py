#!/usr/bin/env python3
import json
import math
import os
import re
import signal
import sys
import time
import urllib.request

STATE = os.path.expanduser('~/.cache/conky/cyber-adsb.status')
LINK = os.path.expanduser('~/.cache/conky/cyber-adsb.link')
METAR = os.path.expanduser('~/.cache/conky/cyber-atc.metar')
MTRLINK = os.path.expanduser('~/.cache/conky/cyber-atc.mtrlink')
CONKY_GUARD = '[c]onky .*(cyber-deckrc|cyber-radarrc|cyber-atcrc)'

CENTER_LAT, CENTER_LON = 40.4915, -80.2327   # Pittsburgh Intl (KPIT)
FETCH_DIST = 60                               # nm radius to ask the feed for
RANGE_NM = 55.0                               # display radius (radar rim position)
FETCH_URL = ('https://api.adsb.lol/v2/lat/%.4f/lon/%.4f/dist/%d'
             % (CENTER_LAT, CENTER_LON, FETCH_DIST))
METAR_URL = ('https://aviationweather.gov/api/data/metar?ids=KPIT&format=raw'
             '&taf=false')
POLL = 10
METAR_POLL = 60
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
    req = urllib.request.Request(FETCH_URL, headers={'User-Agent': 'cyber-adsb/2.0'})
    with urllib.request.urlopen(req, timeout=15) as r:
        return json.load(r)

def fetch_metar():
    req = urllib.request.Request(METAR_URL, headers={'User-Agent': 'cyber-atc/2.0'})
    with urllib.request.urlopen(req, timeout=15) as r:
        return r.read().decode().strip()

def parse_metar(raw):
    wind = vis = sky = None
    m = re.search(r'\b(VRB|\d{3})\d{2}G?\d*KT\b', raw)
    if m:
        wind = m.group(0)
    m = re.search(r'\b\d{1,2}\s?SM\b', raw)
    if m:
        vis = m.group(0)
    m = re.search(r'\b(FEW|SCT|BKN|OVC|VV)\d{3}\b', raw)
    if m:
        sky = m.group(0)
    if not wind:
        return None
    return 'W %s VIS %s %s' % (wind, vis or '--SM', sky or 'CLR')

def main():
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    os.makedirs(os.path.dirname(STATE), exist_ok=True)
    last_metar = 0.0
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
                sq = (a.get('squawk') or '-').strip() or '-'
                em = (a.get('emergency') or 'none').strip() or 'none'
                cat = (a.get('category') or '-').strip() or '-'
                out.append('%s %.1f %.1f %s %s %s %s %s %s %s' % (
                    a.get('hex', '?'), brg, d, alt, gs, fl or '-', atype or '-',
                    sq, em, cat))
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
        try:
            if epoch - last_metar >= METAR_POLL:
                raw = fetch_metar()
                with open(METAR, 'w') as f:
                    f.write(raw + '\n')
                with open(MTRLINK, 'w') as f:
                    f.write('metar ok\n')
                last_metar = epoch
        except Exception:
            with open(MTRLINK, 'w') as f:
                f.write('metar down\n')
        time.sleep(POLL)

if __name__ == '__main__':
    main()