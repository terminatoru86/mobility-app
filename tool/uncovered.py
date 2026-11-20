#!/usr/bin/env python3
"""US cities (75,000+ people) whose area on our map has (almost) no official data - only OpenStreetMap /
Mapillary - and that we have not written to yet. For each: state, population, official site, and where to send
a public-records request (portal / e-mail, found by tool/foia_contacts.py on the city's site).

    python3 tool/uncovered.py   -> data/foia/uncovered.json + data/foia/UNCOVERED.md
"""
import concurrent.futures as cf
import gzip
import json
import math
import os
import sys
import time
import urllib.parse
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, 'tool'))
from foia_contacts import city as find_contacts  # noqa: E402

MIN_POP = int(os.environ.get('MIN_POP', 75000))
OFFICIAL = ('city/', 'gs/', 'usr/', 'pm/', 'cty/', 'vnd/', 'mbta/', 'blk/', 'afdc/')
Q = """SELECT ?c ?cLabel ?site ?coord (MAX(?pop) AS ?p) WHERE {
  VALUES ?type { wd:Q1093829 wd:Q15127012 wd:Q3301053 wd:Q15284 wd:Q47168 wd:Q2154459 }
  ?c wdt:P31 ?type ; wdt:P17 wd:Q30 ; wdt:P1082 ?pop ; wdt:P625 ?coord .
  OPTIONAL { ?c wdt:P856 ?site }
  FILTER(?pop >= %d)
  SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
} GROUP BY ?c ?cLabel ?site ?coord ORDER BY DESC(?p)"""


def wikidata():
    url = 'https://query.wikidata.org/sparql?' + urllib.parse.urlencode({'query': Q % MIN_POP, 'format': 'json'})
    for i in range(5):
        try:
            req = urllib.request.Request(url, headers={'User-Agent': 'MOBIlityBot/1.0 (github.com/terminatoru86/mobility-app)'})
            return json.loads(urllib.request.urlopen(req, timeout=180).read())['results']['bindings']
        except Exception as e:
            print('wikidata', e, flush=True)
            time.sleep(20 * (i + 1))
    raise SystemExit('wikidata failed')


STATES = None


def state_of(lat, lon):
    global STATES
    if STATES is None:
        g = json.load(open(os.path.join(ROOT, 'data', 'us_states.json')))
        STATES = []
        for f in g['features']:
            geom = f['geometry']
            for poly in geom['coordinates'] if geom['type'] == 'MultiPolygon' else [geom['coordinates']]:
                ring = poly[0]
                STATES.append((f['properties']['name'], min(p[0] for p in ring), min(p[1] for p in ring),
                               max(p[0] for p in ring), max(p[1] for p in ring), ring))
    for name, x0, y0, x1, y1, ring in STATES:
        if not (x0 <= lon <= x1 and y0 <= lat <= y1):
            continue
        inside, j = False, len(ring) - 1
        for i in range(len(ring)):
            xi, yi = ring[i]
            xj, yj = ring[j]
            if (yi > lat) != (yj > lat) and lon < (xj - xi) * (lat - yi) / (yj - yi) + xi:
                inside = not inside
            j = i
        if inside:
            return name
    return None


TILES = {}


def tile(a, b):
    if (a, b) not in TILES:
        p = os.path.join(ROOT, 'assets', 'osm', 'tiles', f't_{a}_{b}.json.gz')
        TILES[(a, b)] = json.loads(gzip.decompress(open(p, 'rb').read())) if os.path.exists(p) else []
    return TILES[(a, b)]


def counts(lat, lon, km=8):
    off = osm = 0
    for a in (math.floor(lat) - 1, math.floor(lat), math.floor(lat) + 1):
        for b in (math.floor(lon) - 1, math.floor(lon), math.floor(lon) + 1):
            for r in tile(a, b):
                if abs(r[1] - lat) > 0.1 or abs(r[2] - lon) > 0.13:
                    continue
                d = math.hypot((r[1] - lat) * 111.3, (r[2] - lon) * 111.3 * math.cos(math.radians(lat)))
                if d > km:
                    continue
                if r[0].startswith(OFFICIAL):
                    off += 1
                elif (r[3] or {}).get('amenity') == 'bicycle_parking':
                    osm += 1
    return off, osm


def host(u):
    h = urllib.parse.urlparse(u if '//' in u else '//' + u).netloc.lower()
    return h[4:] if h.startswith('www.') else h


def main():
    done = {host(c['site']) for c in json.load(open(os.path.join(ROOT, 'data', 'foia', 'contacts.json')))}
    done_names = {c['city'].rsplit(' ', 1)[0].lower() for c in json.load(open(os.path.join(ROOT, 'data', 'foia', 'contacts.json')))}
    rows, seen = [], set()
    for b in wikidata():
        name = b['cLabel']['value']
        lon, lat = map(float, b['coord']['value'].replace('Point(', '').rstrip(')').split())
        st = state_of(lat, lon)
        if not st or (name, st) in seen:
            continue
        seen.add((name, st))
        site = host(b['site']['value']) if b.get('site') else ''
        if site in done or name.lower() in done_names:
            continue
        off, osm = counts(lat, lon)
        rows.append({'city': name, 'state': st, 'pop': int(float(b['p']['value'])), 'lat': lat, 'lon': lon,
                     'site': site, 'official': off, 'osm_racks': osm})
    need = [r for r in rows if r['official'] < 5]
    print(f'{len(rows)} cities {MIN_POP}+ not written to; {len(need)} without official data', flush=True)

    def look(r):
        if r['site']:
            try:
                c = find_contacts(f"{r['city']} {r['state']}", r['site'])
                r['portal'], r['email'], r['pages'] = c.get('portal') or [], c.get('email') or [], c.get('pages') or []
            except Exception as e:
                r['error'] = str(e)[:100]
        return r
    with cf.ThreadPoolExecutor(12) as ex:
        need = list(ex.map(look, need))
    need.sort(key=lambda r: -r['pop'])
    json.dump(need, open(os.path.join(ROOT, 'data', 'foia', 'uncovered.json'), 'w'), indent=1, ensure_ascii=False)
    lines = [f'# Cities {MIN_POP:,}+ without official data on our map, not yet written to ({len(need)})', '',
             '| City | State | Pop. | Official pts | OSM racks | E-mail | Portal |', '|---|---|---|---|---|---|---|']
    for r in need:
        lines.append(f"| {r['city']} | {r['state']} | {r['pop']:,} | {r['official']} | {r['osm_racks']} | "
                     f"{' '.join((r.get('email') or [])[:2])} | {' '.join((r.get('portal') or [])[:1])} |")
    open(os.path.join(ROOT, 'data', 'foia', 'UNCOVERED.md'), 'w').write('\n'.join(lines) + '\n')


if __name__ == '__main__':
    main()
