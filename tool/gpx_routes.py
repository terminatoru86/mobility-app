"""Routes that cities, counties, park districts and visitor centers offer as files on their own websites (GPX / KML /
KMZ): self-guided bike tours, historic and heritage rides, scenic motorcycle / moped routes. Found by tool/venues.py
(data/venues/tracks/<group>.json); this downloads each file and turns it into a route for Explore.

  python3 tool/gpx_routes.py --test
  python3 tool/gpx_routes.py            -> data/trails/city_routes.json (+ data/trails/CITY_ROUTES.md)

Walking-only tours are left out (a walking / hiking word and no bike / scooter / moped / motorcycle word). Routes are
1 to 50 km, like the others.
"""
import io
import json
import os
import re
import sys
import urllib.request
import zipfile
from concurrent.futures import ThreadPoolExecutor
from xml.etree import ElementTree as ET

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from osm_routes import hav, join, simplify  # noqa: E402

UA = {'User-Agent': 'MOBIlityBot/1.0 (bike routes for a riders map; github.com/terminatoru86/mobility-app)'}
WALK = re.compile(r'\b(walk(ing)?|hik(e|ing)|stroll|on\s*foot|pedestrian|paddle|canoe|kayak)\b', re.I)
RIDE = re.compile(r'\b(bik(e|ing|es)|bicycl\w*|cycl(e|ing)|ride|riding|scooter|moped|motorcycl\w*|e-?bike|byway|scenic\s*drive|driving\s*tour|auto\s*tour)\b', re.I)
MOTO = re.compile(r'\b(motorcycl\w*|moped|scenic\s*drive|driving\s*tour|auto\s*tour|byway|road\s*trip)\b', re.I)
HIST = re.compile(r'histor\w*|heritage|civil\s*war|colonial|revolution\w*|pioneer|underground\s*railroad|landmark|monument|memorial|old\s*town', re.I)


def tag(e):
    return e.tag.rsplit('}', 1)[-1]


def lines_of(data):
    """(name, [[(lat, lon), ...], ...]) from GPX, KML or KMZ bytes."""
    if data[:2] == b'PK':
        z = zipfile.ZipFile(io.BytesIO(data))
        kml = next((n for n in z.namelist() if n.lower().endswith('.kml')), None)
        data = z.read(kml) if kml else b''
    root = ET.fromstring(data)
    name, lines = None, []
    for e in root.iter():
        t = tag(e)
        if t == 'name' and name is None and (e.text or '').strip():
            name = e.text.strip()
        if t in ('trkseg', 'rte'):
            pts = [(float(p.get('lat')), float(p.get('lon'))) for p in e if tag(p) in ('trkpt', 'rtept')]
            if len(pts) > 1:
                lines.append(pts)
        if t == 'LineString':
            for c in e:
                if tag(c) == 'coordinates' and c.text:
                    pts = []
                    for xy in c.text.split():
                        v = xy.split(',')
                        if len(v) >= 2:
                            pts.append((float(v[1]), float(v[0])))
                    if len(pts) > 1:
                        lines.append(pts)
    return name, lines


def fetch(item):
    try:
        req = urllib.request.Request(item['url'], headers=UA)
        with urllib.request.urlopen(req, timeout=30) as r:
            data = r.read(5_000_000)
        return item, lines_of(data)
    except Exception as err:
        return item, err


def route_of(item, name, lines):
    label = ' '.join(x for x in (name, item.get('label'), item['url'].rsplit('/', 1)[-1]) if x)
    if WALK.search(label) and not RIDE.search(label):
        return None, 'walking only'
    lines = [simplify(l) for l in join(lines)]
    km = sum(hav(l[i - 1], l[i]) for l in lines for i in range(1, len(l)))
    if km < 1 or km >= 50:
        return None, f'{km:.0f} km'
    nm = (name or item.get('label') or '').strip()
    if not nm or re.fullmatch(r'(gpx|kml|track|route|download|map)?\s*\d*', nm, re.I):
        nm = f"{item['place']} {'route' if MOTO.search(label) else 'bike route'}"
    return {'id': 'g/' + str(abs(hash(item['url'])) % 10 ** 12), 'name': nm[:90], 'ref': None,
            'kind': 'motorcycle' if MOTO.search(label) else 'bicycle', 'network': None, 'operator': item['place'],
            'km': round(km, 1), 'tags': {'website': item['site'], 'source': f"Website of {item['place']}",
                                         **({'mobility:historic': 'yes'} if HIST.search(label) else {})},
            'lines': [[round(v, 5) for p in l for v in p] for l in lines]}, None


def main():
    d = os.path.join(ROOT, 'data', 'venues', 'tracks')
    items, seen = [], set()
    for f in sorted(os.listdir(d)) if os.path.isdir(d) else []:
        for it in json.load(open(os.path.join(d, f))):
            if it['url'] not in seen:
                seen.add(it['url'])
                items.append(it)
    out, why = [], {}
    with ThreadPoolExecutor(32) as pool:
        for item, res in pool.map(fetch, items):
            if isinstance(res, Exception):
                why['could not read'] = why.get('could not read', 0) + 1
                continue
            r, w = route_of(item, *res)
            if r:
                out.append(r)
            else:
                why[w] = why.get(w, 0) + 1
    os.makedirs(os.path.join(ROOT, 'data', 'trails'), exist_ok=True)
    json.dump(out, open(os.path.join(ROOT, 'data', 'trails', 'city_routes.json'), 'w'), separators=(',', ':'), ensure_ascii=False)
    hist = sum(1 for r in out if r['tags'].get('mobility:historic'))
    with open(os.path.join(ROOT, 'data', 'trails', 'CITY_ROUTES.md'), 'w', encoding='utf-8') as f:
        f.write(f'# Routes from the websites of cities, parks and visitor centers: {len(out)} (historic: {hist})\n\n'
                f'Files found: {len(items)} · left out: {why}\n\n')
        for r in out[:300]:
            f.write(f"- {r['name']} · {r['kind']} · {r['km']} km · {r['operator']}{' · historic' if r['tags'].get('mobility:historic') else ''}\n")
    print(f'{len(out)} routes from {len(items)} files (historic {hist}) · left out {why}', flush=True)


def test():
    gpx = b'''<?xml version="1.0"?><gpx xmlns="http://www.topografix.com/GPX/1/1"><trk><name>Historic Downtown Bike Tour</name>
    <trkseg><trkpt lat="41.88" lon="-87.63"/><trkpt lat="41.89" lon="-87.63"/><trkpt lat="41.90" lon="-87.63"/></trkseg></trk></gpx>'''
    item = {'url': 'https://city.gov/tour.gpx', 'label': 'Download GPX', 'site': 'https://city.gov', 'place': 'City of X'}
    r, w = route_of(item, *lines_of(gpx))
    assert r and r['kind'] == 'bicycle' and r['tags'].get('mobility:historic') == 'yes' and 2 < r['km'] < 3, (r, w)
    kml = b'''<kml xmlns="http://www.opengis.net/kml/2.2"><Document><name>Scenic Byway Motorcycle Loop</name><Placemark><LineString>
    <coordinates>-87.63,41.88,0 -87.63,41.95,0 -87.60,41.99,0</coordinates></LineString></Placemark></Document></kml>'''
    r2, _ = route_of({**item, 'label': ''}, *lines_of(kml))
    assert r2 and r2['kind'] == 'motorcycle', r2
    r3, w3 = route_of({**item, 'label': 'Historic walking tour'}, 'Walking Tour', lines_of(gpx)[1])
    assert r3 is None and w3 == 'walking only'
    print('rules ok')


if __name__ == '__main__':
    test()
    if '--test' not in sys.argv:
        main()
