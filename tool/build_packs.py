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
import gzip
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
    'amenity', 'bicycle_parking', 'capacity', 'covered', 'fee', 'access', 'lit', 'surveillance', 'name', 'brand', 'manufacturer',
    'network', 'operator', 'shop', 'bicycle', 'bicycle_rental', 'motorcycle', 'scooter', 'small_electric_vehicle',
    'service:vehicle:repair', 'motorcycle:repair', 'opening_hours', 'phone', 'contact:phone', 'website',
    'contact:website', 'addr:housenumber', 'addr:street', 'service:bicycle:repair', 'service:bicycle:pump',
    'service:bicycle:tools', 'service:bicycle:stand', 'service:bicycle:chain_tool', 'service:bicycle:rental',
    'service:bicycle:second_hand',
    # photos, freshness and details
    'image', 'image:0', 'image:1', 'wikimedia_commons', 'mapillary', 'panoramax', 'check_date', 'survey:date',
    'cargo_bike', 'capacity:cargo_bike', 'supervised', 'maxstay', 'charge', 'valves', 'manometer', 'level', 'location',
    'description',
    'surveillance:type', 'private_area', 'self_service', 'automated', 'rental', 'sport', 'surface', 'email', 'contact:email',
}


def http(url, data=None, timeout=200, headers=None):
    body = urllib.parse.urlencode(data).encode() if data else None
    h = dict(UA)
    # Socrata (city portals): with our free app token the servers let us read more, faster
    tok = os.environ.get('SOCRATA_APP_TOKEN')
    if tok and ('/resource/' in url or 'api.us.socrata.com' in url or '/api/views/' in url):
        h['X-App-Token'] = tok
    h.update(headers or {})
    req = urllib.request.Request(url, data=body, headers=h)
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
         f'nwr["amenity"="charging_station"]["scooter"="yes"]({bbox});'
         f'nwr["amenity"="charging_station"]["motorcycle"="yes"]({bbox});'
         f'nwr["amenity"~"^(motorcycle_parking|small_electric_vehicle_parking|kick-scooter_parking|mobility_hub)$"]({bbox});'
         f'nwr["shop"~"^(motorcycle|scooter|motorcycle_repair)$"]({bbox});'
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
    tags = {k: v for k, v in (el.get('tags') or {}).items() if k in KEEP or k.startswith(('service:', 'socket:', 'motorcycle:'))}
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


# ───────── automatic discovery: every public bike-parking layer in the US ─────────
# Thousands of cities, counties, campuses, transit agencies and park districts publish on ArcGIS Online
# or Socrata. Instead of finding them one by one, we search both catalogues at every build.

WANT = re.compile(r'bike\s*rack|bicycle\s*rack|bike\s*parking|bicycle\s*parking|bike\s*corral|bicycle\s*corral|'
                  r'micromobility\s*(parking|corral)|scooter\s*corral|bike\s*repair|bicycle\s*repair|fix-?it|'
                  r'repair\s*station|bike\s*locker|bicycle\s*locker|bike\s*station', re.I)
SKIP = re.compile(r'propos|request|survey|count|demand|plan(ned|ning)?\b|candidate|suitab|crash|collision|'
                  r'heat\s*map|lane|route|trail|path|network|stress|study|draft|test|copy|sample|training|demo', re.I)


def discover_arcgis(known, budget_min=25):
    """Public point layers about bike parking / repair on ArcGIS Online, inside the US."""
    layers, seen = [], set()
    end = time.time() + budget_min * 60
    terms = ['"bike rack"', '"bike racks"', '"bicycle racks"', '"bicycle parking"', '"bike parking"',
             '"bike corral"', '"micromobility parking"', '"bike repair"', '"fix-it station"', '"bike lockers"']
    for t in terms:
        for start in range(1, 1000, 100):
            q = urllib.parse.urlencode({
                'q': f'{t} AND (type:"Feature Service" OR type:"Map Service")', 'num': 100, 'start': start,
                'bbox': '-170,17,-65,72', 'f': 'json', 'sortField': 'numviews', 'sortOrder': 'desc'})
            try:
                j = json.loads(http(f'https://www.arcgis.com/sharing/rest/search?{q}', timeout=60))
            except Exception as err:
                print(f'  search {t} failed: {err}', flush=True)
                break
            for it in j.get('results', []):
                url = (it.get('url') or '').rstrip('/')
                title = it.get('title') or ''
                if time.time() > end:
                    break
                if not url or url in seen or SKIP.search(title):
                    continue
                seen.add(url)
                try:
                    info = json.loads(http(f'{url}?f=json', timeout=40))
                except Exception:
                    continue
                for ly in info.get('layers') or []:
                    name = ly.get('name') or ''
                    if ly.get('geometryType') not in (None, 'esriGeometryPoint', 'esriGeometryMultipoint'):
                        continue
                    if SKIP.search(name) or not (WANT.search(name) or (WANT.search(title) and len(info['layers']) == 1)):
                        continue
                    lurl = f"{url}/{ly['id']}"
                    if lurl in known:
                        continue
                    layers.append({'key': 'ago-' + hashlib.md5(lurl.encode()).hexdigest()[:10], 'arcgis': lurl,
                                   'socrata': None, 'hubItem': None, 'layer': 0, 'where': None,
                                   'amenity': 'bicycle_repair_station' if re.search(r'repair|fix', name + title, re.I)
                                   else 'bicycle_parking',
                                   'label': f"{title} · {it.get('owner', '')}".strip(' ·')[:90]})
            if len(j.get('results', [])) < 100:
                break
            time.sleep(1)
    print(f'ArcGIS Online: {len(layers)} layers found', flush=True)
    return layers


def discover_socrata(known):
    """Bike-parking datasets on every Socrata portal (Discovery API), with a point column."""
    found, seen = [], set()
    for t in ['bike racks', 'bicycle parking', 'bike parking', 'bicycle racks', 'bike corrals', 'bike repair']:
        q = urllib.parse.urlencode({'q': t, 'only': 'dataset', 'limit': 100})
        try:
            j = json.loads(http(f'https://api.us.socrata.com/api/catalog/v1?{q}', timeout=60))
        except Exception as err:
            print(f'  socrata {t} failed: {err}', flush=True)
            continue
        for r in j.get('results', []):
            res, meta = r.get('resource') or {}, r.get('metadata') or {}
            name, dom, rid = res.get('name') or '', meta.get('domain') or '', res.get('id') or ''
            key = f'{dom}/{rid}'
            if not rid or key in seen or key in known or SKIP.search(name) or not WANT.search(name):
                continue
            types = res.get('columns_datatype') or []
            if not any(x in ('point', 'location', 'multipoint') for x in [str(x).lower() for x in types]):
                continue
            seen.add(key)
            found.append({'key': 'soc-' + rid, 'socrata': key, 'arcgis': None, 'hubItem': None, 'layer': 0,
                          'where': None, 'label': f'{name} · {dom}'[:90],
                          'amenity': 'bicycle_repair_station' if re.search(r'repair|fix', name, re.I) else 'bicycle_parking'})
    print(f'Socrata: {len(found)} datasets found', flush=True)
    return found


# ───────── Mapillary: bike racks detected automatically in street photos ─────────

METROS = {  # the larger US metro areas and college towns (center lat, lon)
    'New York': (40.73, -73.95), 'Los Angeles': (34.05, -118.25), 'Chicago': (41.88, -87.70), 'Dallas': (32.80, -96.90),
    'Houston': (29.76, -95.37), 'Washington': (38.90, -77.04), 'Philadelphia': (39.95, -75.17), 'Miami': (25.78, -80.21),
    'Atlanta': (33.75, -84.39), 'Boston': (42.36, -71.08), 'Phoenix': (33.45, -112.05), 'San Francisco': (37.78, -122.30),
    'Riverside': (33.95, -117.40), 'Detroit': (42.35, -83.10), 'Seattle': (47.61, -122.30), 'Minneapolis': (44.97, -93.20),
    'San Diego': (32.75, -117.15), 'Tampa': (27.95, -82.50), 'Denver': (39.74, -104.98), 'Baltimore': (39.29, -76.61),
    'St. Louis': (38.63, -90.25), 'Orlando': (28.54, -81.38), 'Charlotte': (35.23, -80.84), 'San Antonio': (29.42, -98.49),
    'Portland': (45.52, -122.65), 'Sacramento': (38.58, -121.45), 'Pittsburgh': (40.44, -79.99), 'Austin': (30.27, -97.74),
    'Las Vegas': (36.15, -115.17), 'Cincinnati': (39.10, -84.51), 'Kansas City': (39.10, -94.58), 'Columbus': (39.96, -83.00),
    'Indianapolis': (39.77, -86.16), 'Cleveland': (41.48, -81.69), 'San Jose': (37.34, -121.89), 'Nashville': (36.16, -86.78),
    'Virginia Beach': (36.85, -76.20), 'Providence': (41.82, -71.41), 'Jacksonville': (30.33, -81.66), 'Milwaukee': (43.04, -87.91),
    'Raleigh': (35.85, -78.75), 'Oklahoma City': (35.47, -97.52), 'Memphis': (35.15, -90.05), 'Richmond': (37.54, -77.44),
    'Louisville': (38.25, -85.76), 'New Orleans': (29.95, -90.07), 'Salt Lake City': (40.73, -111.90), 'Hartford': (41.76, -72.68),
    'Buffalo': (42.89, -78.85), 'Birmingham': (33.52, -86.80), 'Rochester': (43.16, -77.61), 'Grand Rapids': (42.96, -85.67),
    'Tucson': (32.22, -110.95), 'Honolulu': (21.31, -157.86), 'Tulsa': (36.15, -95.99), 'Fresno': (36.74, -119.79),
    'Omaha': (41.26, -96.01), 'Albuquerque': (35.09, -106.63), 'Boise': (43.62, -116.20), 'Madison': (43.07, -89.40),
    'Ann Arbor': (42.28, -83.74), 'Boulder': (40.02, -105.27), 'Eugene': (44.05, -123.09), 'Gainesville': (29.65, -82.33),
    'Champaign': (40.11, -88.23), 'Bloomington IN': (39.17, -86.53), 'Davis': (38.54, -121.74), 'Fort Collins': (40.58, -105.08),
    'Ithaca': (42.44, -76.50), 'State College': (40.79, -77.86), 'Lincoln': (40.81, -96.70), 'Spokane': (47.66, -117.42),
    'Burlington VT': (44.48, -73.21), 'Santa Barbara': (34.42, -119.70), 'Tallahassee': (30.44, -84.28), 'Knoxville': (35.96, -83.92),
    'Lexington': (38.04, -84.50), 'Des Moines': (41.59, -93.62), 'El Paso': (31.76, -106.49), 'Anchorage': (61.22, -149.90),
}


def mapillary_token():
    t = os.environ.get('MAPILLARY_TOKEN')
    if t:
        return t
    try:
        src = open(os.path.join(ROOT, 'lib', 'data', 'mapillary.dart'), encoding='utf-8').read()
        return re.search(r"kMapillaryToken = '([^']+)'", src).group(1)
    except Exception:
        return None


# ───────── tiny Mapbox Vector Tile reader (only what Mapillary point tiles need; no extra packages) ─────────

def _varint(b, i):
    r = shift = 0
    while True:
        c = b[i]
        i += 1
        r |= (c & 0x7F) << shift
        if c < 0x80:
            return r, i
        shift += 7


def _fields(b):
    """(field number, wire type, value) for each field of a protobuf message."""
    i = 0
    while i < len(b):
        key, i = _varint(b, i)
        f, w = key >> 3, key & 7
        if w == 0:
            v, i = _varint(b, i)
        elif w == 2:
            n, i = _varint(b, i)
            v, i = b[i:i + n], i + n
        elif w == 1:
            v, i = b[i:i + 8], i + 8
        elif w == 5:
            v, i = b[i:i + 4], i + 4
        else:
            raise ValueError(f'wire type {w}')
        yield f, w, v


def _packed(b):
    out, i = [], 0
    while i < len(b):
        v, i = _varint(b, i)
        out.append(v)
    return out


def _value(b):
    import struct
    for f, w, v in _fields(b):
        if f == 1:
            return v.decode('utf-8', 'replace')
        if f == 2:
            return struct.unpack('<f', v)[0]
        if f == 3:
            return struct.unpack('<d', v)[0]
        if f in (4, 5):
            return v
        if f == 6:
            return (v >> 1) ^ -(v & 1)
        if f == 7:
            return bool(v)
    return None


def mvt_points(raw, layer_name):
    """[(x, y, properties)] of the point features of one layer (x, y in tile units, y down)."""
    out = []
    for f, w, layer in _fields(raw):
        if f != 3:
            continue
        name, keys, values, feats, extent = None, [], [], [], 4096
        for lf, lw, lv in _fields(layer):
            if lf == 1:
                name = lv.decode()
            elif lf == 2:
                feats.append(lv)
            elif lf == 3:
                keys.append(lv.decode())
            elif lf == 4:
                values.append(_value(lv))
            elif lf == 5:
                extent = lv
        if name != layer_name:
            continue
        for ft in feats:
            tags, geom = [], []
            for ff, fw, fv in _fields(ft):
                if ff == 2:
                    tags = _packed(fv)
                elif ff == 4:
                    geom = _packed(fv)
            props = {keys[tags[k]]: values[tags[k + 1]] for k in range(0, len(tags) - 1, 2)}
            x = y = 0
            i = 0
            while i < len(geom):
                cmd, cnt = geom[i] & 7, geom[i] >> 3
                i += 1
                for _ in range(cnt):
                    if cmd in (1, 2):
                        dx, dy = geom[i], geom[i + 1]
                        i += 2
                        x += (dx >> 1) ^ -(dx & 1)
                        y += (dy >> 1) ^ -(dy & 1)
                        if cmd == 1:
                            out.append((x / extent, y / extent, props))
    return out


def fetch_mapillary(boxes=None, budget_min=75):
    """Bike racks Mapillary found in street photos, from its map-feature vector tiles (zoom 14, ~2.4 km),
    about 33 x 33 km around each metro. Tiles come from a cache, so this is fast; 16 at a time, with a time budget."""
    from concurrent.futures import ThreadPoolExecutor
    token = mapillary_token()
    if not token:
        stage('Mapillary skipped: no token')
        return []
    Z = 14
    n2 = 2 ** Z

    def tx(lon):
        return int((lon + 180) / 360 * n2)

    def ty(lat):
        r = math.radians(lat)
        return int((1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2 * n2)

    # metro by metro, in the order of METROS (Chicago first), so a time limit never skips our home area
    tiles_xy = []
    seen_t = set()
    for name, (la, lo) in METROS.items():
        for x in range(tx(lo - 0.2), tx(lo + 0.2) + 1):
            for y in range(ty(la + 0.15), ty(la - 0.15) + 1):
                if (x, y) not in seen_t:
                    seen_t.add((x, y))
                    tiles_xy.append((x, y))
    if boxes:
        def inside(x, y):
            lon = x / n2 * 360 - 180
            lat = math.degrees(math.atan(math.sinh(math.pi * (1 - 2 * y / n2))))
            return any(b[0] - 0.05 <= lat < b[2] + 0.05 and b[1] - 0.05 <= lon < b[3] + 0.05 for b in boxes)
        tiles_xy = [t for t in tiles_xy if inside(*t)]
    end = time.time() + budget_min * 60
    errors = []

    def one(t):
        if time.time() > end:
            return None
        x, y = t
        url = f'https://tiles.mapillary.com/maps/vtp/mly_map_feature_point/2/{Z}/{x}/{y}?access_token={token}'
        try:
            raw = http(url, timeout=30)
        except Exception as err:
            errors.append(str(err)[:150])
            return []
        for attempt in range(3):
            if raw and raw[:1] in (b'<', b'{'):  # an error page instead of a tile (busy server): wait and ask again
                if attempt == 0:
                    errors.append('busy: ' + raw[:80].decode('utf-8', 'replace'))
                time.sleep(2 + attempt * 4)
                try:
                    raw = http(url, timeout=30)
                except Exception:
                    raw = b''
            else:
                break
        if not raw or raw[:1] in (b'<', b'{'):
            return []
        try:
            pts = mvt_points(raw, 'point')
        except Exception as err:
            errors.append(f'decode: {str(err)[:120]}')
            return []
        got = []
        for fx, fy, pr in pts:
            if pr.get('value') != 'object--bike-rack':
                continue
            lon = (x + fx) / n2 * 360 - 180
            lat = math.degrees(math.atan(math.sinh(math.pi * (1 - 2 * (y + fy) / n2))))
            got.append((str(pr.get('id')), lat, lon, pr.get('last_seen_at')))
        return got

    out, seen, done = [], set(), 0
    with ThreadPoolExecutor(8) as ex:
        for got in ex.map(one, tiles_xy):
            if got is None:
                continue
            done += 1
            for fid, lat, lon, ls in got:
                if fid in seen:
                    continue
                seen.add(fid)
                tags = {'amenity': 'bicycle_parking', 'bicycle_parking': 'stands',
                        'source': 'Mapillary · seen in street photos'}
                if isinstance(ls, (int, float)):
                    tags['check_date'] = datetime.fromtimestamp(ls / 1000, timezone.utc).strftime('%Y-%m-%d')
                out.append([f'mly/{fid}', round(lat, 6), round(lon, 6), tags])
    stage(f'Mapillary: {len(out)} racks from {done}/{len(tiles_xy)} tiles, {len(errors)} errors'
          + (f' (first: {errors[0]})' if errors else ''))
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


def fetch_foursquare():
    """Foursquare Open Source Places (Apache 2.0, monthly): bike / moped / motorcycle / scooter shops,
    repair and rentals in the US, open places only. Read from Hugging Face with our token (HF_TOKEN)."""
    token = os.environ.get('HF_TOKEN')
    if not token:
        print('Foursquare skipped: no HF_TOKEN', flush=True)
        return []
    import duckdb
    auth = {'Authorization': f'Bearer {token}'}
    tree = json.loads(http('https://huggingface.co/api/datasets/foursquare/fsq-os-places/tree/main/release', headers=auth, timeout=60))
    rel = sorted(t['path'] for t in tree if t.get('type') == 'directory' and 'dt=' in t.get('path', ''))[-1]
    con = duckdb.connect()
    con.execute("INSTALL httpfs; LOAD httpfs;")
    con.execute(f"CREATE SECRET hf (TYPE huggingface, TOKEN '{token}');")
    q = f"""
      SELECT fsq_place_id, name, latitude, longitude, address, locality, region, tel, website, email,
             date_refreshed, array_to_string(fsq_category_labels, ' | ') AS cats
      FROM read_parquet('hf://datasets/foursquare/fsq-os-places/{rel}/places/parquet/*.parquet')
      WHERE country = 'US' AND date_closed IS NULL AND latitude IS NOT NULL
        AND regexp_matches(lower(array_to_string(fsq_category_labels, ' | ')), 'bicycle|bike|motorcycle|scooter|moped|cycling')
    """
    out = []
    for fid, name, lat, lon, addr, city, region, tel, web, email, refreshed, cats in con.execute(q).fetchall():
        c = (cats or '').lower()
        if 'motorcycle' in c or 'moped' in c:
            tags = {'shop': 'motorcycle_repair'} if 'repair' in c else {'shop': 'motorcycle'}
        elif 'scooter' in c and 'bike' not in c and 'bicycle' not in c:
            tags = {'shop': 'scooter'}
        elif 'rental' in c or 'share' in c:
            tags = {'amenity': 'bicycle_rental'}
        elif 'bicycle' in c or 'bike' in c:
            tags = {'shop': 'bicycle'}
            if 'repair' in c:
                tags['service:bicycle:repair'] = 'yes'
        else:
            continue  # cycling studios, clubs, trails... not places for the map
        tags.update({k: v for k, v in {'name': name, 'website': web, 'phone': tel, 'email': email,
                                        'addr:street': addr, 'check_date': (refreshed or '')[:10] or None}.items() if v})
        tags['source'] = 'Foursquare OS Places'
        out.append([f'fsq/{fid}', round(lat, 6), round(lon, 6), tags])
    print(f'Foursquare {rel}: {len(out)}', flush=True)
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
      SELECT id, names.primary AS name, CAT_EXPR AS cat,
             (bbox.ymin + bbox.ymax) / 2 AS lat, (bbox.xmin + bbox.xmax) / 2 AS lon, websites[1] AS web, phones[1] AS phone, emails[1] AS email,
             addresses[1].freeform AS street
      FROM read_parquet('s3://overturemaps-us-west-2/release/{release}/theme=places/type=place/*', hive_partitioning=1)
      WHERE bbox.xmin BETWEEN -170 AND -65 AND bbox.ymin BETWEEN 17 AND 72
        AND addresses[1].country = 'US'
        AND (CAT_EXPR ILIKE '%bicycle%' OR CAT_EXPR ILIKE '%bike%' OR CAT_EXPR ILIKE '%cycl%'
             OR CAT_EXPR ILIKE '%motorcycle%' OR CAT_EXPR ILIKE '%scooter%' OR CAT_EXPR ILIKE '%moped%')
        AND confidence >= 0.6
    """
    out = []
    # Overture renamed the category field in 2026 (categories -> taxonomy / basic_category): try the new one first
    rows = None
    for expr in ("coalesce(taxonomy.primary, basic_category)", "basic_category", "categories.primary"):
        try:
            rows = con.execute(q.replace('CAT_EXPR', expr)).fetchall()
            print(f'Overture category field: {expr}', flush=True)
            break
        except Exception as err:
            last = err
    if rows is None:
        raise last
    for oid, name, c, lat, lon, web, phone, email, street in rows:
        c = (c or '').lower()
        if 'motorcycle' in c or 'moped' in c or 'scooter' in c:
            kind = 'motorcycle' if ('motorcycle' in c or 'moped' in c) else 'scooter'
            if 'repair' in c:
                tags = {'shop': 'motorcycle_repair'}
            elif 'rent' in c:
                tags = {'amenity': 'motorcycle_rental'}
                continue  # no rental type for mopeds yet
            else:
                tags = {'shop': kind}
            tags.update({k: v for k, v in {'name': name, 'website': web, 'phone': phone, 'email': email, 'addr:street': street}.items() if v})
            tags['source'] = 'Overture Maps'
            out.append([f'ovt/{oid}', round(lat, 6), round(lon, 6), tags])
            continue
        if 'rent' in c or 'sharing' in c:
            tags = {'amenity': 'bicycle_rental'}
        elif 'repair' in c:
            tags = {'shop': 'bicycle', 'service:bicycle:repair': 'yes'}
        elif 'shop' in c or 'store' in c or 'dealer' in c:
            tags = {'shop': 'bicycle'}
        else:
            continue  # bike paths, clubs, tours... not places for the map
        tags.update({k: v for k, v in {'name': name, 'website': web, 'phone': phone, 'email': email, 'addr:street': street}.items() if v})
        tags['source'] = 'Overture Maps'
        out.append([f'ovt/{oid}', round(lat, 6), round(lon, 6), tags])
    print(f'Overture {release}: {len(out)}', flush=True)
    return out


ATP_SHOPS = {'bicycle', 'motorcycle', 'scooter', 'motorcycle_repair'}


def fetch_alltheplaces():
    """All The Places (data CC0, weekly): the store lists that chains and brands publish on their own
    websites (Trek, Harley-Davidson, Cycle Gear, dealers of the motorcycle makers...). The one open
    source that carries OPENING HOURS, with phone and the page of each store."""
    import tempfile
    import zipfile
    info = json.loads(http('https://data.alltheplaces.xyz/runs/latest.json', timeout=60))
    url = info.get('output_url')
    if not url:
        raise RuntimeError(f'no output_url in latest.json: {list(info)[:8]}')
    path = os.path.join(tempfile.gettempdir(), 'atp.zip')
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=600) as r, open(path, 'wb') as f:
        while True:
            chunk = r.read(1 << 20)
            if not chunk:
                break
            f.write(chunk)
    out, spiders, with_hours = [], set(), 0
    keys = (b'bicycle', b'motorcycle', b'scooter')
    seen_all = {}  # every candidate by store list and country, to see what the filter leaves out
    with zipfile.ZipFile(path) as z:
        for name in z.namelist():
            if not name.endswith('.geojson'):
                continue
            spider = os.path.basename(name)[:-8]
            with z.open(name) as f:
                for line in f:  # one place per line
                    if not any(k in line for k in keys):
                        continue
                    try:
                        feat = json.loads(line.strip().rstrip(b','))
                    except Exception:
                        continue
                    p = feat.get('properties') or {}
                    g = feat.get('geometry') or {}
                    # a rental SHOP: has its own page or phone. The share feeds (gbfs) are stations, which we already
                    # have live from the operators, so they are left out here
                    rental = (p.get('amenity') == 'bicycle_rental' and p.get('bicycle_rental') != 'docking_station'
                              and spider != 'gbfs' and bool(p.get('website') or p.get('phone')))
                    if not (p.get('shop') in ATP_SHOPS or rental) or g.get('type') != 'Point' or p.get('end_date'):
                        continue
                    country = (p.get('addr:country') or '').upper()
                    lon, lat = g['coordinates'][:2]
                    seen_all[(spider, country)] = seen_all.get((spider, country), 0) + 1
                    # the US by the country written, or, when none is written, by where the point is
                    inside = any(a <= lat < c and b <= lon < d for a, b, c, d in REGIONS)
                    if not (country in ('US', 'USA', 'PR', 'UNITED STATES') or (not country and inside)) or not inside:
                        continue
                    tags = {'shop': p['shop']} if p.get('shop') in ATP_SHOPS else {'amenity': 'bicycle_rental'}
                    street = p.get('addr:street_address') or ' '.join(x for x in (p.get('addr:housenumber'), p.get('addr:street')) if x) or p.get('addr:full')
                    tags.update({k: v for k, v in {
                        'name': p.get('name') or p.get('brand'), 'brand': p.get('brand'), 'website': p.get('website'),
                        'phone': p.get('phone'), 'email': p.get('email'), 'opening_hours': p.get('opening_hours'),
                        'addr:street': street}.items() if v and isinstance(v, str)})
                    if not tags.get('name'):
                        continue
                    if tags.get('opening_hours'):
                        with_hours += 1
                    tags['source'] = 'All The Places'
                    ref = re.sub(r'[^A-Za-z0-9_.-]+', '-', str(p.get('ref') or f'{lat:.5f},{lon:.5f}'))[:60]
                    out.append([f'atp/{spider}-{ref}', round(lat, 6), round(lon, 6), tags])
                    spiders.add(spider)
    os.remove(path)
    top = sorted(seen_all.items(), key=lambda x: -x[1])[:40]
    print('All The Places candidates (list, country): ' + ', '.join(f'{k[0]}/{k[1] or "?"}:{v}' for k, v in top), flush=True)
    print(f"All The Places {info.get('run_id')}: {len(out)} shops from {len(spiders)} store lists, {with_hours} with hours", flush=True)
    return out


CONTACTS = os.environ.get('CONTACTS_OUT') or os.path.join(ROOT, 'data', 'contacts', 'business_contacts.csv')


def contact_kind(t):
    """Which businesses go on our own contact list (not shown in the app)."""
    a, shop = t.get('amenity'), t.get('shop')
    if shop in ('bicycle', 'motorcycle', 'scooter', 'motorcycle_repair'):
        return 'service' if (t.get('service:bicycle:repair') == 'yes' or shop == 'motorcycle_repair') else 'shop'
    if a == 'bicycle_wash':
        return 'wash'
    if a == 'bicycle_rental' and t.get('bicycle_rental') != 'docking_station':
        return 'rent'
    if a in ('bicycle_parking', 'motorcycle_parking') and (t.get('access') in ('private', 'customers') or t.get('fee') == 'yes'):
        return 'private parking'
    if t.get('sport') == 'bmx':
        return 'bmx'
    return None


def write_contacts(tiles, save=True):
    """Emails of service hubs, shops, BMX, washes, private parking and rentals: a separate list for us.
    The emails are taken out of the app data (riders do not need them); BMX places stay off the map."""
    import csv
    rows = {}
    for d in tiles.values():
        for pid in list(d):
            row = d[pid]
            t = row[3]
            email = (t.pop('email', None) or t.pop('contact:email', None) or '').strip()
            t.pop('contact:email', None)
            kind = contact_kind(t)
            if t.get('sport') == 'bmx' and t.get('amenity') is None and t.get('shop') is None:
                d.pop(pid)  # BMX tracks: contacts only (no BMX filter on the map)
            if not kind or not email:
                continue
            for e in re.split(r'[;,\s]+', email):
                if '@' in e:
                    rows[(e.lower(), t.get('name', ''))] = [
                        e.lower(), kind, t.get('name', ''), t.get('website') or t.get('contact:website', ''),
                        t.get('phone') or t.get('contact:phone', ''),
                        ' '.join(x for x in (t.get('addr:housenumber'), t.get('addr:street')) if x),
                        row[1], row[2], pid, t.get('source', 'OpenStreetMap')]
    if not save:
        return  # partial build: keep the full list from the last full build
    os.makedirs(os.path.dirname(CONTACTS), exist_ok=True)
    with open(CONTACTS, 'w', newline='', encoding='utf-8') as f:
        w = csv.writer(f)
        w.writerow(['email', 'kind', 'name', 'website', 'phone', 'street', 'lat', 'lon', 'id', 'source'])
        for r in sorted(rows.values(), key=lambda r: (r[1], r[2])):
            w.writerow(r)
    print(f'contacts: {len(rows)} emails', flush=True)
    return len(rows)


def mark_private(tiles, files):
    """Racks and parking inside a private / customers-only area (parking lot of a building, residential complex,
    office, mall...) are on private property: they get access=private (or customers) and show as private parking."""
    G = 0.01  # grid of ~1 km for a fast lookup
    grid = {}
    n_areas = 0
    for fpath in files:
        try:
            for a in json.load(open(fpath, encoding='utf-8')):
                n_areas += 1
                for i in range(math.floor(a[0] / G), math.floor(a[2] / G) + 1):
                    for j in range(math.floor(a[1] / G), math.floor(a[3] / G) + 1):
                        grid.setdefault((i, j), []).append(a)
        except Exception as err:
            print(f'private areas {fpath}: {err}', flush=True)

    def inside(lat, lon, flat):
        # ray casting on the outer ring
        n = len(flat) // 2
        hit = False
        j = n - 1
        for i in range(n):
            yi, xi, yj, xj = flat[2 * i], flat[2 * i + 1], flat[2 * j], flat[2 * j + 1]
            if (yi > lat) != (yj > lat) and lon < (xj - xi) * (lat - yi) / ((yj - yi) or 1e-12) + xi:
                hit = not hit
            j = i
        return hit

    marked = 0
    for d in tiles.values():
        for r in d.values():
            t = r[3]
            if t.get('amenity') not in ('bicycle_parking', 'motorcycle_parking', 'small_electric_vehicle_parking'):
                continue
            if t.get('access') not in (None, '', 'yes', 'public', 'permissive'):
                continue  # already says who may use it
            if t.get('access') in ('yes', 'public'):
                continue  # explicitly public, even inside a private lot
            for a in grid.get((math.floor(r[1] / G), math.floor(r[2] / G)), ()):
                if a[0] <= r[1] <= a[2] and a[1] <= r[2] <= a[3] and inside(r[1], r[2], a[6]):
                    t['access'] = 'customers' if a[4] == 'customers' else 'private'
                    t['private_area'] = a[5]
                    marked += 1
                    break
    return n_areas, marked


def stage(msg):
    """A progress line GitHub shows on the run page (readable even when the full log is not)."""
    line = f'{datetime.now(timezone.utc).strftime("%H:%M")}Z {msg}'
    print(f'::notice title=Progress::{line}' if os.environ.get('GITHUB_ACTIONS') else line, flush=True)


def main():
    if '--export-cities' in sys.argv:
        json.dump(city_sources(), open(sys.argv[-1], 'w', encoding='utf-8'), indent=1, ensure_ascii=False)
        print('exported', sys.argv[-1])
        return
    args = [float(a) for a in sys.argv[1:] if not a.startswith('--')][:4]
    boxes = [tuple(int(math.floor(v)) if k < 2 else int(math.ceil(v)) for k, v in enumerate(args))] if args else REGIONS
    tiles = {}
    # --refresh=overture,foursquare,alltheplaces : only these sources again, everything else kept
    refresh = {x for a in sys.argv if a.startswith('--refresh=') for x in a.split('=', 1)[1].split(',') if x}
    osm_files = [a.split('=', 1)[1] for a in sys.argv if a.startswith('--osm-json=')]
    if osm_files:
        # fast path: places already taken out of the Geofabrik extracts (tool/osm_extract.py)
        for fpath in osm_files:
            for r in json.load(open(fpath, encoding='utf-8')):
                tiles.setdefault((math.floor(r[1]), math.floor(r[2])), {})[r[0]] = r
        print(f'OpenStreetMap from {len(osm_files)} extracts: {sum(len(d) for d in tiles.values())} places', flush=True)
    elif refresh:
        # light run: keep every place already built; read again only the named sources
        for name in os.listdir(OUT) if os.path.isdir(OUT) else []:
            m = re.match(r't_(-?\d+)_(-?\d+)\.json\.gz$', name)
            if m:
                rows = json.loads(gzip.decompress(open(os.path.join(OUT, name), 'rb').read()))
                tiles[(int(m.group(1)), int(m.group(2)))] = {r[0]: r for r in rows}
        print(f'Kept all places of {len(tiles)} tiles; reading again: {sorted(refresh)}', flush=True)
    elif '--extra-only' in sys.argv:
        # keep the OpenStreetMap places already built; only (re)add the other sources
        for name in os.listdir(OUT) if os.path.isdir(OUT) else []:
            m = re.match(r't_(-?\d+)_(-?\d+)\.json(\.gz)?$', name)
            if not m:
                continue
            raw = open(os.path.join(OUT, name), 'rb').read()
            rows = json.loads(gzip.decompress(raw) if m.group(3) else raw)
            tiles[(int(m.group(1)), int(m.group(2)))] = {
                r[0]: r for r in rows if not r[0].startswith(('city/', 'mbta/', 'ovt/', 'mly/'))}
        print(f'Kept OpenStreetMap places of {len(tiles)} tiles', flush=True)
    else:
        for box in boxes:
            collect_osm(box, tiles)
    stage(f'1/6 OpenStreetMap ready: {sum(len(d) for d in tiles.values())} places')
    cities = []
    # other open sources: one list each, added to the tiles (the app removes doubles near OpenStreetMap ones)
    # Mapillary racks from the last build: kept, so a slow Mapillary day (time limit) does not lose cities
    old_mly = []
    if os.path.isdir(OUT):
        for name in os.listdir(OUT):
            if re.match(r't_-?\d+_-?\d+\.json\.gz$', name):
                try:
                    old_mly += [r for r in json.loads(gzip.decompress(open(os.path.join(OUT, name), 'rb').read()))
                                if r[0].startswith('mly/')]
                except Exception:
                    pass
    counts_src = {}
    for name, fn in (('mbta', fetch_mbta), ('overture', fetch_overture), ('foursquare', fetch_foursquare),
                     ('alltheplaces', fetch_alltheplaces),
                     ('mapillary', lambda: fetch_mapillary(boxes if args else None))):
        if refresh and name not in refresh:
            continue
        try:
            got = fn()
            for x in got:
                if not args or (boxes[0][0] <= x[1] < boxes[0][2] and boxes[0][1] <= x[2] < boxes[0][3]):
                    tiles.setdefault((math.floor(x[1]), math.floor(x[2])), {})[x[0]] = x
            if name == 'mapillary':
                new_ids = {x[0] for x in got}
                kept = [r for r in old_mly if r[0] not in new_ids]
                for x in kept:
                    tiles.setdefault((math.floor(x[1]), math.floor(x[2])), {})[x[0]] = x
                got = got + kept
            counts_src[name] = len(got)
        except Exception as err:
            counts_src[name] = f'failed: {str(err)[:150]}'
    stage(f'2/6 sources {counts_src} · {sum(len(d) for d in tiles.values())} places')
    known_srcs = [] if refresh else city_sources()
    known = {s.get('arcgis') for s in known_srcs if s.get('arcgis')} | {s.get('socrata') for s in known_srcs if s.get('socrata')}
    discovered = []
    if not refresh:
        try:
            discovered += discover_arcgis(known)
        except Exception as err:
            print(f'ArcGIS discovery failed: {err}', flush=True)
        try:
            discovered += discover_socrata(known)
        except Exception as err:
            print(f'Socrata discovery failed: {err}', flush=True)
    stage(f'3/6 discovery done: {len(discovered)} new public layers')
    found_log = []
    city_end = time.time() + 45 * 60  # found-by-search layers get 45 min; our own list always runs
    for src in known_srcs + discovered:
        if src['key'].startswith(('ago-', 'soc-')) and time.time() > city_end:
            continue
        try:
            els = fetch_city(src)
            if len(els) > 150000:
                print(f"Skip {src['key']}: {len(els)} rows, not a rack list", flush=True)
                continue
            add_city = 0
            for x in els:
                if not args or (boxes[0][0] <= x[1] < boxes[0][2] and boxes[0][1] <= x[2] < boxes[0][3]):
                    tiles.setdefault((math.floor(x[1]), math.floor(x[2])), {})[x[0]] = x
                    add_city += 1
            if add_city:
                cities.append(src['key'])
                if src['key'].startswith(('ago-', 'soc-')):
                    found_log.append({'key': src['key'], 'label': src['label'], 'url': src.get('arcgis') or src.get('socrata'),
                                      'places': add_city})
            print(f"City {src['key']}: {add_city}", flush=True)
        except Exception as err:
            print(f"City {src['key']} failed: {err}", flush=True)
    stage(f'4/6 city sources added: {sum(len(d) for d in tiles.values())} places')
    priv_files = [x.split('=', 1)[1] for x in sys.argv if x.startswith('--private-json=')]
    n_areas, n_priv = mark_private(tiles, priv_files) if priv_files else (0, 0)
    print(f'private areas: {n_areas}, racks on private property: {n_priv}', flush=True)
    n_mail = write_contacts(tiles, save=not args and '--extra-only' not in sys.argv and not refresh)
    stage(f'5/6 emails: {n_mail} · private areas: {n_areas}, racks made private: {n_priv}')
    # the same place from several sources (e.g. copies of a city's rack list re-uploaded by students):
    # keep one per ~5 m. OpenStreetMap first, then our own city list, then everything else.
    def rank(r):
        k = r[0]
        return 0 if k.startswith(('node/', 'way/', 'relation/')) else 1 if k.startswith('city/') and not k.split('/')[1].startswith(('ago-', 'soc-')) else 2
    dropped = 0
    for key, d in tiles.items():
        seen = set()
        for r in sorted(d.values(), key=lambda r: (rank(r), r[0])):
            g = (round(r[1] / 0.00005), round(r[2] / 0.00005), r[3].get('amenity') or r[3].get('shop'))
            if g in seen and rank(r) > 0:
                d.pop(r[0])
                dropped += 1
            else:
                seen.add(g)
    # the same shop / rental from OpenStreetMap, Overture and Foursquare: same name within ~150 m, kept once
    import unicodedata
    def norm(n):
        n = unicodedata.normalize('NFKD', n or '').encode('ascii', 'ignore').decode().lower()
        return re.sub(r'[^a-z0-9]+', '', re.sub(r'\b(the|inc|llc|co|shop|store|bikes?|bicycles?|cycles?)\b', '', n))
    merged = {}
    for key, d in tiles.items():
        seen = {}
        # All The Places first among the others: it is the stores' own list, with hours
        for r in sorted(d.values(), key=lambda r: (rank(r), 0 if r[0].startswith('atp/') else 1 if r[0].startswith('ovt/') else 2, r[0])):
            t = r[3]
            if not (t.get('shop') or t.get('amenity') == 'bicycle_rental') or not t.get('name'):
                continue
            # by name, and by brand too ("Trek Bicycle Lincoln Park" and "Trek Bicycle Store" are one shop)
            ns = [x for x in dict.fromkeys([norm(t['name']), norm(t.get('brand', ''))]) if x]
            if not ns:
                continue
            cells = [(n, round(r[1] / 0.0015) + i, round(r[2] / 0.002) + j) for n in ns for i in (-1, 0, 1) for j in (-1, 0, 1)]
            first = next((seen[c] for c in cells if c in seen), None)
            if first is not None and rank(r) > 0:
                # the copy goes, but what it knows and the kept one lacks stays: website, phone, hours, email
                kt = first[3]
                for k in ('website', 'phone', 'opening_hours', 'email', 'brand'):
                    alt = {'website': 'contact:website', 'phone': 'contact:phone', 'email': 'contact:email'}.get(k)
                    if t.get(k) and not kt.get(k) and not (alt and kt.get(alt)):
                        kt[k] = t[k]
                        merged[k] = merged.get(k, 0) + 1
                d.pop(r[0])
                dropped += 1
            else:
                for n in ns:
                    seen[(n, round(r[1] / 0.0015), round(r[2] / 0.002))] = r
    print(f'duplicates removed: {dropped} · filled from the copies: {merged}', flush=True)
    # hours and phone read from the shops' own websites (our list, data/site_hours.json; tool/site_hours.py)
    try:
        import site_hours
        every = [r for d in tiles.values() for r in d.values()]
        n_hours = site_hours.apply(every, site_hours.load_list(), site_hours.shared_sites(every))
        print(f'hours from websites: {n_hours} places', flush=True)
    except Exception as err:
        print(f'hours from websites failed: {err}', flush=True)
    # only the US (some sources have places abroad or broken coordinates)
    for k in [k for k in tiles if not (17 <= k[0] < 72 and -180 <= k[1] < -64)]:
        tiles.pop(k)
    os.makedirs(OUT, exist_ok=True)
    if not args and '--extra-only' not in sys.argv and not refresh:
        # full build: pieces that no longer have places are removed
        keep = {f't_{a}_{b}.json.gz' for (a, b) in tiles}
        for name in os.listdir(OUT):
            if re.match(r't_-?\d+_-?\d+\.json(\.gz)?$', name) and name not in keep:
                os.remove(os.path.join(OUT, name))
    index_path = os.path.join(OUT, 'index.json')
    try:
        index = json.load(open(index_path))
    except Exception:
        index = {}
    counts = index.get('tiles', {}) if args else {}
    for (a, b), d in sorted(tiles.items()):
        rows = sorted(d.values(), key=lambda x: x[0])
        text = json.dumps(rows, separators=(',', ':'), ensure_ascii=False)
        # compressed (about 5 times smaller); the app unpacks it in a few milliseconds
        with open(os.path.join(OUT, f't_{a}_{b}.json.gz'), 'wb') as f:
            f.write(gzip.compress(text.encode('utf-8'), compresslevel=9, mtime=0))
        old = os.path.join(OUT, f't_{a}_{b}.json')
        if os.path.exists(old):
            os.remove(old)
        # [places, version]: the app downloads a piece again only when its version changed
        counts[f'{a}_{b}'] = [len(rows), hashlib.md5(text.encode('utf-8')).hexdigest()[:12]]
    index = {
        'at': datetime.now(timezone.utc).strftime('%Y-%m-%d'),
        'tiles': dict(sorted(counts.items())),
        'cities': sorted(set(cities) | (set(index.get('cities', [])) if args or refresh else set())),
        'total': sum(v[0] if isinstance(v, list) else v for v in counts.values()),
        # partial builds: which boxes are covered (the app asks OpenStreetMap live outside them)
        **({'boxes': (index.get('boxes', []) + [list(boxes[0])])} if args else {}),
    }
    with open(index_path, 'w') as f:
        json.dump(index, f, separators=(',', ':'))
    # list of the automatically found sources (for the manual / checking)
    if not refresh:
        with open(os.path.join(OUT, 'sources.json'), 'w', encoding='utf-8') as f:
            json.dump(sorted(found_log, key=lambda x: -x['places']), f, indent=1, ensure_ascii=False)
    stage(f"6/6 done: {index['total']} places in {len(counts)} tiles · duplicates removed: {dropped}")


if __name__ == '__main__':
    main()
