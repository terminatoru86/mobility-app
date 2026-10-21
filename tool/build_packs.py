#!/usr/bin/env python3
"""Builds the offline data packs shipped inside the app (assets/osm/tiles/).

Every rider place in the US from OpenStreetMap (racks, parking, pumps, repair stations, washes,
rental/sharing, bike shops, bike charging) plus the city-hall lists from lib/data/open_data.dart,
cut into 1 x 1 degree tiles. The app reads the tiles around the rider from its own files
(instant, no internet) and only refreshes online when the packs are old.

Runs on GitHub Actions (.github/workflows/data-packs.yml) twice a month; can also be run by hand:
    python3 tool/build_packs.py            # whole US
    python3 tool/build_packs.py 41 -89 43 -87   # only this box (south west north east)
Only the Python standard library is used.
"""
import hashlib
import json
import math
import os
import re
import sys
import time
import urllib.parse
import urllib.request
from datetime import datetime, timezone

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.environ.get('PACKS_OUT') or os.path.join(ROOT, 'assets', 'osm', 'tiles')
UA = {'User-Agent': 'MOBIlity data packs (github.com/terminatoru86/mobility-app)'}
OVERPASS = [
    'https://overpass-api.de/api/interpreter',
    'https://overpass.private.coffee/api/interpreter',
    'https://maps.mail.ru/osm/tools/overpass/api/interpreter',
]
# lower 48, Alaska, Hawaii, Puerto Rico
REGIONS = [(24, -125, 50, -66), (51, -170, 72, -129), (18, -161, 23, -154), (17, -68, 19, -65)]
KEEP = {
    'amenity', 'bicycle_parking', 'capacity', 'covered', 'fee', 'access', 'lit', 'surveillance', 'name', 'brand',
    'network', 'operator', 'shop', 'bicycle', 'bicycle_rental', 'opening_hours', 'phone', 'contact:phone', 'website',
    'contact:website', 'addr:housenumber', 'addr:street', 'service:bicycle:repair', 'service:bicycle:pump',
    'service:bicycle:tools', 'service:bicycle:stand', 'service:bicycle:chain_tool', 'service:bicycle:rental',
    'service:bicycle:second_hand',
}


def http(url, data=None, timeout=200):
    body = urllib.parse.urlencode(data).encode() if data else None
    req = urllib.request.Request(url, data=body, headers=UA)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read()


def overpass(s, w, n, e):
    bbox = f'{s},{w},{n},{e}'
    q = ('[out:json][timeout:180][maxsize:536870912];('
         f'nwr["amenity"="bicycle_parking"]({bbox});'
         f'nwr["amenity"="bicycle_repair_station"]({bbox});'
         f'nwr["amenity"="compressed_air"]({bbox});'
         f'nwr["amenity"="bicycle_wash"]({bbox});'
         f'nwr["amenity"="bicycle_rental"]({bbox});'
         f'nwr["shop"="bicycle"]({bbox});'
         f'nwr["amenity"="charging_station"]["bicycle"="yes"]({bbox});'
         ');out center tags;')
    for attempt in range(4):
        url = OVERPASS[attempt % len(OVERPASS)]
        try:
            j = json.loads(http(url, {'data': q}))
            if j.get('remark') and 'runtime error' in j['remark']:
                raise RuntimeError(j['remark'])
            return j['elements']
        except Exception as err:  # busy / timeout: wait and try the next server
            print(f'  {bbox} via {url}: {err}', flush=True)
            time.sleep(15 * (attempt + 1))
    return None


def slim(el):
    lat = el.get('lat') or (el.get('center') or {}).get('lat')
    lon = el.get('lon') or (el.get('center') or {}).get('lon')
    if lat is None or lon is None:
        return None
    tags = {k: v for k, v in (el.get('tags') or {}).items() if k in KEEP or k.startswith('service:bicycle:')}
    return [f"{el['type']}/{el['id']}", round(lat, 6), round(lon, 6), tags]


def collect_osm(box, tiles):
    s, w, n, e = box
    step = 2
    lat = s
    while lat < n:
        lon = w
        while lon < e:
            chunk = (lat, lon, min(lat + step, n), min(lon + step, e))
            els = overpass(*chunk)
            if els is None:  # too big or servers busy: try the four 1-degree pieces
                for a in range(chunk[0], chunk[2]):
                    for b in range(chunk[1], chunk[3]):
                        sub = overpass(a, b, a + 1, b + 1)
                        add(tiles, sub or [])
                        time.sleep(2)
            else:
                add(tiles, els)
            print(f'OSM {chunk}: {0 if els is None else len(els)}', flush=True)
            time.sleep(3)
            lon += step
        lat += step


def add(tiles, els):
    for el in els:
        x = slim(el)
        if x:
            tiles.setdefault((math.floor(x[1]), math.floor(x[2])), {})[x[0]] = x


# ───────── city halls (read from lib/data/open_data.dart, so the list lives in one place) ─────────

def city_sources():
    # in the data repository the list comes as city_sources.json (exported from the app with --export-cities)
    js = os.path.join(ROOT, 'city_sources.json')
    if os.path.exists(js):
        return json.load(open(js, encoding='utf-8'))
    src = open(os.path.join(ROOT, 'lib', 'data', 'open_data.dart'), encoding='utf-8').read()
    out = []
    for m in re.finditer(r"CitySource\('([^']+)',\s*'([^']+)',\s*'([^']+)',\s*([-\d.]+),\s*([-\d.]+),\s*([-\d.]+),\s*([-\d.]+),(.*?)\),\n", src, re.S):
        key, city, label = m.group(1), m.group(2), m.group(3)
        rest = m.group(8)

        def opt(name):
            mm = re.search(name + r":\s*'([^']*)'", rest)
            return mm.group(1) if mm else None

        def opt_raw(name):
            mm = re.search(name + r':\s*([\w.]+)', rest)
            return mm.group(1) if mm else None

        if opt_raw('national') == 'true':
            continue  # national layers stay live (asked only around the map)
        out.append({
            'key': key, 'label': label, 'socrata': opt('socrata'), 'arcgis': opt('arcgis'),
            'hubItem': opt('hubItem'), 'layer': int(opt_raw('layer') or 0), 'where': None,
            'amenity': opt('amenity') or 'bicycle_parking',
        })
    return out


def element(src, props, lat, lon, i):
    low = {str(k).lower(): v for k, v in props.items()}
    try:
        lat = float(lat if lat is not None else low.get('latitude') or low.get('lat') or low.get('y'))
        lon = float(lon if lon is not None else low.get('longitude') or low.get('lon') or low.get('long') or low.get('x'))
    except (TypeError, ValueError):
        return None
    if abs(lat) < 1 or abs(lon) < 1 or abs(lat) > 90:
        return None
    status = str(low.get('status') or low.get('current_status') or '').lower()
    if any(w in status for w in ('remov', 'retired', 'inactive')):
        return None

    def pick(test):
        for k, v in low.items():
            if v is None or isinstance(v, (dict, list)):
                continue
            if test(k) and str(v).strip() and str(v) != 'null':
                return str(v).strip()
        return None

    address = pick(lambda k: 'address' in k or k == 'location' or 'street' in k or k == 'site' or 'loc_desc' in k or k == 'name')
    spaces = pick(lambda k: 'capacity' in k or 'spaces' in k)
    racks = pick(lambda k: 'totinstall' in k or 'quantity' in k or 'numberofracks' in k or k == 'racks' or 'num_racks' in k)
    rid = pick(lambda k: 'rackid' in k or k in ('objectid', 'fid', 'assetid', 'id')) or str(i)

    def to_int(x):
        try:
            return round(float(x))
        except (TypeError, ValueError):
            return None

    cap = to_int(spaces) or (to_int(racks) * 2 if to_int(racks) else None)
    tags = {'amenity': src['amenity'], 'source': src['label']}
    if src['amenity'] == 'bicycle_parking':
        tags.update({'bicycle_parking': 'stands', 'fee': 'no'})
        if cap and cap > 0:
            tags['capacity'] = str(cap)
    if src['amenity'] == 'bicycle_repair_station':
        tags.update({'service:bicycle:pump': 'yes', 'service:bicycle:tools': 'yes'})
    if address:
        tags['addr:street'] = address.title() if address.isupper() else address
    return [f"city/{src['key']}/{rid}", round(lat, 6), round(lon, 6), tags]


def fetch_city(src):
    out = []
    if src['socrata']:
        dom, ds = src['socrata'].split('/', 1)
        j = json.loads(http(f'https://{dom}/resource/{ds}.geojson?$limit=200000', timeout=300))
        for i, f in enumerate(j.get('features', [])):
            c = (f.get('geometry') or {}).get('coordinates')
            while isinstance(c, list) and c and isinstance(c[0], list):
                c = c[0]
            ok = isinstance(c, list) and len(c) >= 2
            x = element(src, f.get('properties') or {}, c[1] if ok else None, c[0] if ok else None, i)
            if x:
                out.append(x)
        return out
    url = src['arcgis']
    if not url and src['hubItem']:
        item = json.loads(http(f"https://www.arcgis.com/sharing/rest/content/items/{src['hubItem']}?f=json"))
        url = (item.get('url') or '').rstrip('/')
        if not url:
            return out
        if re.search(r'(FeatureServer|MapServer)$', url):
            url += f"/{src['layer']}"
    offset, i = 0, 0
    for _ in range(200):
        q = urllib.parse.urlencode({'where': '1=1', 'outFields': '*', 'outSR': '4326', 'returnGeometry': 'true',
                                    'f': 'json', 'resultOffset': offset})
        j = json.loads(http(f'{url}/query?{q}'))
        if j.get('error'):
            break
        feats = j.get('features') or []
        for f in feats:
            g = f.get('geometry') or {}
            x = element(src, f.get('attributes') or {}, g.get('y'), g.get('x'), i)
            i += 1
            if x:
                out.append(x)
        if not feats or not j.get('exceededTransferLimit'):
            break
        offset += len(feats)
    return out


# ───────── transit and other open APIs ─────────

def fetch_mbta():
    """MBTA (Boston) 'Pedal & Park' cages and bike racks at stations, from the MBTA V3 API (no key needed)."""
    out = []
    j = json.loads(http('https://api-v3.mbta.com/facilities?filter%5Btype%5D=BIKE_STORAGE&page%5Blimit%5D=2000'))
    for f in j.get('data', []):
        a = f.get('attributes') or {}
        lat, lon = a.get('latitude'), a.get('longitude')
        if lat is None or lon is None:
            continue
        props = {p.get('name'): p.get('value') for p in a.get('properties') or []}
        tags = {'amenity': 'bicycle_parking', 'source': 'MBTA · station bike parking', 'fee': 'no',
                'name': a.get('long_name') or a.get('short_name') or 'MBTA bike parking'}
        cap = props.get('capacity')
        if cap:
            tags['capacity'] = str(cap)
        if props.get('enclosed') in (1, '1', True) or 'Pedal' in (a.get('long_name') or ''):
            tags.update({'covered': 'yes', 'bicycle_parking': 'shed', 'access': 'customers'})
        else:
            tags['bicycle_parking'] = 'stands'
        out.append([f"mbta/{f.get('id')}", round(float(lat), 6), round(float(lon), 6), tags])
    return out


def fetch_overture():
    """Bike shops, repair and rentals from Overture Maps places (CDLA-Permissive-2.0), via DuckDB on the public S3."""
    try:
        import duckdb  # installed by the workflow (pip install duckdb)
    except ImportError:
        print('Overture skipped: duckdb not installed', flush=True)
        return []
    cat = json.loads(http('https://stac.overturemaps.org/catalog.json'))
    release = cat.get('latest') or sorted(l['href'].split('/')[1] for l in cat['links'] if l.get('rel') == 'child')[-1]
    release = release.strip('./').split('/')[0]
    con = duckdb.connect()
    con.execute('INSTALL httpfs; LOAD httpfs; SET s3_region=\'us-west-2\';')
    q = f"""
      SELECT id, names.primary AS name, categories.primary AS cat,
             (bbox.ymin + bbox.ymax) / 2 AS lat, (bbox.xmin + bbox.xmax) / 2 AS lon, websites[1] AS web, phones[1] AS phone,
             addresses[1].freeform AS street
      FROM read_parquet('s3://overturemaps-us-west-2/release/{release}/theme=places/type=place/*', hive_partitioning=1)
      WHERE bbox.xmin BETWEEN -170 AND -65 AND bbox.ymin BETWEEN 17 AND 72
        AND addresses[1].country = 'US'
        AND (categories.primary ILIKE '%bicycle%' OR categories.primary ILIKE '%bike%')
        AND confidence >= 0.6
    """
    out = []
    for oid, name, c, lat, lon, web, phone, street in con.execute(q).fetchall():
        c = (c or '').lower()
        if 'rent' in c or 'sharing' in c:
            tags = {'amenity': 'bicycle_rental'}
        elif 'repair' in c:
            tags = {'shop': 'bicycle', 'service:bicycle:repair': 'yes'}
        elif 'shop' in c or 'store' in c or 'dealer' in c:
            tags = {'shop': 'bicycle'}
        else:
            continue  # bike paths, clubs, tours... not places for the map
        tags.update({k: v for k, v in {'name': name, 'website': web, 'phone': phone, 'addr:street': street}.items() if v})
        tags['source'] = 'Overture Maps'
        out.append([f'ovt/{oid}', round(lat, 6), round(lon, 6), tags])
    print(f'Overture {release}: {len(out)}', flush=True)
    return out


def main():
    if '--export-cities' in sys.argv:
        json.dump(city_sources(), open(sys.argv[-1], 'w', encoding='utf-8'), indent=1, ensure_ascii=False)
        print('exported', sys.argv[-1])
        return
    args = [float(a) for a in sys.argv[1:5]]
    boxes = [tuple(int(math.floor(v)) if k < 2 else int(math.ceil(v)) for k, v in enumerate(args))] if args else REGIONS
    tiles = {}
    for box in boxes:
        collect_osm(box, tiles)
    cities = []
    # other open sources: one list each, added to the tiles (the app removes doubles near OpenStreetMap ones)
    for name, fn in (('mbta', fetch_mbta), ('overture', fetch_overture)):
        try:
            for x in fn():
                if not args or (boxes[0][0] <= x[1] < boxes[0][2] and boxes[0][1] <= x[2] < boxes[0][3]):
                    tiles.setdefault((math.floor(x[1]), math.floor(x[2])), {})[x[0]] = x
        except Exception as err:
            print(f'{name} failed: {err}', flush=True)
    for src in city_sources():
        try:
            els = fetch_city(src)
            add_city = 0
            for x in els:
                if not args or (boxes[0][0] <= x[1] < boxes[0][2] and boxes[0][1] <= x[2] < boxes[0][3]):
                    tiles.setdefault((math.floor(x[1]), math.floor(x[2])), {})[x[0]] = x
                    add_city += 1
            if add_city:
                cities.append(src['key'])
            print(f"City {src['key']}: {add_city}", flush=True)
        except Exception as err:
            print(f"City {src['key']} failed: {err}", flush=True)
    os.makedirs(OUT, exist_ok=True)
    index_path = os.path.join(OUT, 'index.json')
    try:
        index = json.load(open(index_path))
    except Exception:
        index = {}
    counts = index.get('tiles', {}) if args else {}
    for (a, b), d in sorted(tiles.items()):
        rows = sorted(d.values(), key=lambda x: x[0])
        text = json.dumps(rows, separators=(',', ':'), ensure_ascii=False)
        with open(os.path.join(OUT, f't_{a}_{b}.json'), 'w', encoding='utf-8') as f:
            f.write(text)
        # [places, version]: the app downloads a piece again only when its version changed
        counts[f'{a}_{b}'] = [len(rows), hashlib.md5(text.encode('utf-8')).hexdigest()[:12]]
    index = {
        'at': datetime.now(timezone.utc).strftime('%Y-%m-%d'),
        'tiles': dict(sorted(counts.items())),
        'cities': sorted(set(cities) | (set(index.get('cities', [])) if args else set())),
        'total': sum(v[0] if isinstance(v, list) else v for v in counts.values()),
        # partial builds: which boxes are covered (the app asks OpenStreetMap live outside them)
        **({'boxes': (index.get('boxes', []) + [list(boxes[0])])} if args else {}),
    }
    with open(index_path, 'w') as f:
        json.dump(index, f, separators=(',', ':'))
    print(f"Done: {index['total']} places in {len(counts)} tiles, cities: {index['cities']}")


if __name__ == '__main__':
    main()
