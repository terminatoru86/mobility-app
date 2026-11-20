#!/usr/bin/env python3
"""Every bike rack Mapillary has detected in street photos, over the whole US (lower 48, Alaska, Hawaii;
Puerto Rico left out), through the Graph API map_features search (10,000 requests / minute per app), not the
vector tiles (50,000 / day). The country is cut into cells of 0.099 x 0.099 degrees (the API wants
less than 0.01 square degrees); cells outside the US are skipped; a cell with 2,000 answers (the most
one call returns) is cut in four and asked again. No time limit: a shard runs until its cells are done.

    SHARD=0 NSHARDS=20 python3 tool/mapillary_all.py      -> data/mapillary/racks_0.json
"""
import json
import os
import sys
import threading
import time
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, 'tool'))
from public_maps import in_us  # noqa: E402

SHARD, NSHARDS = int(os.environ.get('SHARD', 0)), int(os.environ.get('NSHARDS', 1))
THREADS = int(os.environ.get('THREADS', 6))
PER_MIN = int(os.environ.get('PER_MIN', 400))       # this shard's share of the 10,000 / minute
OUT = os.path.join(ROOT, 'data', 'mapillary')
STEP = 0.099
AREAS = [(-125.0, 24.3, -66.8, 49.5), (-170.0, 51.0, -129.9, 71.5), (-160.4, 18.8, -154.7, 22.4)]  # no Puerto Rico
VALUES = 'object--bike-rack'


def token():
    t = os.environ.get('MAPILLARY_TOKEN')
    if t:
        return t
    import re
    src = open(os.path.join(ROOT, 'lib', 'data', 'mapillary.dart'), encoding='utf-8').read()
    return re.search(r"kMapillaryToken = '([^']+)'", src).group(1)


def cells():
    out = []
    for x0, y0, x1, y1 in AREAS:
        x = x0
        while x < x1:
            y = y0
            while y < y1:
                pts = [(y + a * STEP, x + b * STEP) for a in (0, 0.5, 1) for b in (0, 0.5, 1)]
                if any(in_us(la, lo) for la, lo in pts):
                    out.append((round(x, 4), round(y, 4), round(x + STEP, 4), round(y + STEP, 4)))
                y += STEP
            x += STEP
    return out


class Pace:
    def __init__(self, per_min):
        self.gap, self.next, self.lock = 60.0 / per_min, time.time(), threading.Lock()

    def wait(self):
        with self.lock:
            now = time.time()
            if self.next > now:
                time.sleep(self.next - now)
            self.next = max(self.next, now) + self.gap


TOKEN, PACE = None, None
stats = {'calls': 0, 'retries': 0, 'split': 0}


def ask(b):
    q = urllib.parse.urlencode({'access_token': TOKEN, 'fields': 'id,geometry,object_value,last_seen_at',
                                'object_values': VALUES, 'bbox': ','.join(map(str, b)), 'limit': 2000})
    url = f'https://graph.mapillary.com/map_features?{q}'
    wait = 10
    while True:                      # no giving up: busy / limit -> wait longer and ask again
        PACE.wait()
        stats['calls'] += 1
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers={'User-Agent': 'MOBIlityBot/1.0'}),
                                        timeout=90) as r:
                return json.loads(r.read()).get('data') or []
        except urllib.error.HTTPError as e:
            body = e.read()[:200].decode('utf-8', 'replace')
            if e.code == 400 and 'bbox' in body.lower():
                return None
            if e.code in (400, 401, 403) and 'limit' not in body.lower():
                stats['auth'] = stats.get('auth', 0) + 1
                if stats['auth'] >= 20 and stats['auth'] >= stats['calls'] // 2:
                    raise SystemExit(f'token refused by the Graph API: {e.code} {body}')
            stats['retries'] += 1
            print(f'  {e.code} {body[:100]} -> wait {wait}s', flush=True)
        except Exception as e:
            stats['retries'] += 1
            print(f'  {str(e)[:100]} -> wait {wait}s', flush=True)
        time.sleep(wait)
        wait = min(wait * 2, 600)


def cell(b):
    d = ask(b)
    if d is None or len(d) >= 2000:
        stats['split'] += 1
        x0, y0, x1, y1 = b
        mx, my = (x0 + x1) / 2, (y0 + y1) / 2
        out = []
        for s in ((x0, y0, mx, my), (mx, y0, x1, my), (x0, my, mx, y1), (mx, my, x1, y1)):
            out += cell(tuple(round(v, 6) for v in s))
        return out
    got = []
    for f in d:
        g = f.get('geometry') or {}
        c = g.get('coordinates') or []
        if f.get('object_value') == VALUES and len(c) == 2:
            got.append([str(f['id']), round(c[1], 6), round(c[0], 6), f.get('last_seen_at')])
    return got


def main():
    global TOKEN, PACE
    TOKEN, PACE = token(), Pace(PER_MIN)
    allc = cells()
    mine = allc[SHARD::NSHARDS]
    print(f'{len(allc)} US cells, shard {SHARD}/{NSHARDS}: {len(mine)}', flush=True)
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, f'racks_{SHARD}.json')
    racks, done, t0 = {}, 0, time.time()
    with ThreadPoolExecutor(THREADS) as ex:
        for got in ex.map(cell, mine):
            done += 1
            for r in got:
                racks[r[0]] = r
            if done % 500 == 0 or done == len(mine):
                json.dump(list(racks.values()), open(path, 'w'), separators=(',', ':'))
                print(f'{done}/{len(mine)} cells · {len(racks)} racks · {stats} · {int(time.time() - t0)}s', flush=True)
    json.dump(list(racks.values()), open(path, 'w'), separators=(',', ':'))
    print(f'DONE shard {SHARD}: {len(racks)} racks from {len(mine)} cells · {stats}', flush=True)


if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == 'count':
        c = cells()
        print(len(c))
    else:
        main()
