"""Places to ride for fun across the US, for the BMX page: dirt jumps, pump tracks, bike parks, BMX tracks,
skills parks and velodromes, public or run by a business / club (like "The Garden - Chicago Dirt Jumps").

  python3 tool/ride_parks.py            -> assets/ride/ride_parks.json.gz + data/ride_parks/REPORT.md
  python3 tool/ride_parks.py --test     -> only checks the name rules
  python3 tool/ride_parks.py --pbf cut.osm.pbf part.json   -> OSM places of one Geofabrik extract
  python3 tool/ride_parks.py part1.json part2.json ...      -> the list, with OSM from those parts (no Overpass)

Sources (open data):
  1. OpenStreetMap (Overpass): leisure=bikepark, cycling=pump_track, sport=bmx, mtb / cycling tracks,
     and anything whose name says dirt jumps / pump track / bike park / BMX.
  2. Overture Maps places (CDLA-Permissive-2.0): the same, by category and name.
  3. Foursquare Open Source Places (Apache 2.0, needs HF_TOKEN): the same, by category and name.
The same place from two sources (within ~250 m, same or empty name) is kept once, with the phone,
website and hours of the business filled in.
Not kept: bike shops, cycling studios / gyms, tours, rentals, plain bike paths (like The 606), bike parking.
"""
import gzip
import json
import math
import os
import re
import sys
import time
import urllib.parse
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UA = {'User-Agent': 'MOBIlity-data/1.0 (github.com/terminatoru86/mobility-app)'}

RIDE = re.compile(
    r'\b(dirt[\s-]*jumps?|dirt[\s-]*(park|track|lot)|pump[\s-]*tracks?|bike[\s-]*parks?|bicycle[\s-]*parks?'
    r'|skate[\s-]*parks?|skateparks?|skate[\s-]*plazas?'
    r'|bmx|mtb[\s-]*(park|skills?)|mountain[\s-]*bike[\s-]*(park|skills?)|skills?[\s-]*(park|course|area|track|loop)'
    r'|jump[\s-]*(park|lines?|track)s?|velodrome|freeride|bike[\s-]*playground|bike[\s-]*(course|circuit)'
    r'|cyclocross[\s-]*(course|park)|flow[\s-]*trail)\b', re.I)
NOT_RIDE = re.compile(
    r'\b(shop|store|sales|cycles?\b(?! ?park)|bikes?\s*(&|and)\s*\w+|repair|rental|rentals|tours?|spin|studio|fitness|gym'
    r'|bootcamp|indoor cycling|cyclebar|soulcycle|parking|rack|dealer|motorsports?|powersports|apparel|school bus)\b', re.I)
CATEGORY = re.compile(r'skate[ _]?park|bmx|bike[ _]park|mountain[ _]bik\w*[ _]park|pump[ _]track|velodrome|dirt[ _]jump|skills[ _]park', re.I)

# The US in boxes Overpass can answer one by one (south, west, north, east)
BOXES = [(24, -125, 37, -110), (37, -125, 49.5, -110), (24, -110, 37, -95), (37, -110, 49.5, -95),
         (24, -95, 37, -82), (37, -95, 49.5, -82), (24, -82, 37, -66), (37, -82, 47.6, -66),
         (51, -180, 72, -129), (18, -161, 23, -154), (17.5, -68, 18.6, -65)]
OVERPASS = ['https://overpass-api.de/api/interpreter', 'https://overpass.private.coffee/api/interpreter',
            'https://maps.mail.ru/osm/tools/overpass/api/interpreter']


def http(url, data=None, timeout=300, headers=None):
    body = urllib.parse.urlencode(data).encode() if data else None
    req = urllib.request.Request(url, data=body, headers={**UA, **(headers or {})})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read()


def kind_of(name, tags=None, cat=''):
    """Dirt jumps / Pump track / BMX track / Bike park / Skills park / Velodrome, or None when it is not a place to ride."""
    t = tags or {}
    n = f'{name or ""} {cat or ""}'.lower()
    if re.search(r'dirt[\s_-]*(jumps?|park|lot)|jump[\s_-]*(park|lines?)', n):
        return 'Dirt jumps'
    if t.get('cycling') == 'pump_track' or re.search(r'pump[\s_-]*track', n):
        return 'Pump track'
    if 'bmx' in (t.get('sport') or '') or 'bmx' in n:
        return 'BMX track'
    if 'velodrome' in n:
        return 'Velodrome'
    if re.search(r'skills?[\s_-]*(park|course|area|track|loop)', n):
        return 'Skills park'
    if t.get('leisure') == 'skatepark' or re.search(r'skate[\s_-]*park|skatepark|skate[\s_-]*plaza|skate[\s_-]*spot', n):
        return 'Skatepark'
    if t.get('leisure') == 'bikepark' or re.search(r'bike[\s_-]*park|bicycle[\s_-]*park|mtb|mountain[\s_-]*bik|freeride|flow[\s_-]*trail'
                                                 r'|bike[\s_-]*(course|circuit|playground)|cyclocross', n):
        return 'Bike park'
    if t.get('sport') in ('mtb', 'cycling') and t.get('leisure') in ('track', 'pitch', 'sports_centre'):
        return 'Bike park'
    return None


def is_business_noise(name, tags=None):
    t = tags or {}
    if t.get('shop') or t.get('office') or t.get('amenity') in ('bicycle_parking', 'bicycle_rental', 'bicycle_repair_station'):
        return True
    if t.get('access') in ('private', 'no') and not (t.get('website') or t.get('phone')):
        return True  # behind a fence with no way to ask: not for the app
    return bool(NOT_RIDE.search(name or '')) and not re.search(r'pump[\s-]*track|dirt[\s-]*jump|bmx[\s-]*track', name or '', re.I)


# ── 1. OpenStreetMap ──
def osm_record(oid, lat, lon, t):
    """One OSM element (tags t) as a place to ride, or None."""
    name = t.get('name', '')
    if is_business_noise(name, t):
        return None
    if t.get('leisure') == 'skatepark' and t.get('bicycle') == 'no' and t.get('kick_scooter') == 'no':
        return None  # skateboards only, says the sign
    if t.get('leisure') in ('park', 'recreation_ground', 'pitch', 'track', 'sports_centre') and not (
            RIDE.search(name) or t.get('sport') or t.get('cycling')):
        return None
    k = kind_of(name, t)
    if not k:
        return None
    return [oid, round(lat, 6), round(lon, 6), clean({
        'name': name or None, 'ride': k, 'phone': t.get('phone') or t.get('contact:phone'),
        'website': t.get('website') or t.get('contact:website'), 'hours': t.get('opening_hours'),
        'street': ' '.join(x for x in (t.get('addr:housenumber'), t.get('addr:street')) if x) or None,
        'operator': t.get('operator'), 'fee': t.get('fee'), 'lit': t.get('lit'), 'surface': t.get('surface'),
        'access': t.get('access'), 'bikes': 'yes' if (t.get('bicycle') in ('yes', 'designated') or 'bmx' in (t.get('sport') or '')
                                                      or t.get('leisure') != 'skatepark') else None,
        'scooters': 'yes' if (t.get('kick_scooter') == 'yes' or 'scooter' in (t.get('sport') or '')) else None,
        'source': 'OpenStreetMap'})]


def osm_from_pbf(pbf, out_json):
    """From a Geofabrik extract already cut with osmium tags-filter (see ride-parks.yml). Ways: the middle of their nodes.
    Each place also gets the city / county park it sits in ('in_park'), like Google's "Located within: Clark Park"."""
    import osmium
    found, parks = [], []

    class H(osmium.SimpleHandler):
        def node(self, n):
            if n.tags and n.location.valid():
                r = osm_record(f'node/{n.id}', n.location.lat, n.location.lon, dict(n.tags))
                if r:
                    found.append(r)

        def way(self, w):
            if not w.tags:
                return
            pts = [(nd.lat, nd.lon) for nd in w.nodes if nd.location.valid()]
            if not pts:
                return
            r = osm_record(f'way/{w.id}', sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts), dict(w.tags))
            if r:
                found.append(r)

        def area(self, a):
            if a.tags.get('leisure') not in ('park', 'nature_reserve', 'recreation_ground') or not a.tags.get('name'):
                return
            try:
                for ring in a.outer_rings():
                    pts = [(nd.lat, nd.lon) for nd in ring if nd.location.valid()]
                    if len(pts) > 3:
                        la = [p[0] for p in pts]
                        lo = [p[1] for p in pts]
                        parks.append((min(la), max(la), min(lo), max(lo), pts, a.tags.get('name')))
            except Exception:
                pass

    H().apply_file(pbf, locations=True)
    for r in found:
        name = in_park(r[1], r[2], parks)
        if name and name != r[3].get('name'):
            r[3]['in_park'] = name
    json.dump(found, open(out_json, 'w'))
    print(f'{pbf}: {len(found)} places to ride, {sum(1 for r in found if r[3].get("in_park"))} inside a named park', flush=True)


def inside(lat, lon, pts):
    c = False
    j = len(pts) - 1
    for i in range(len(pts)):
        yi, xi = pts[i]
        yj, xj = pts[j]
        if (yi > lat) != (yj > lat) and lon < (xj - xi) * (lat - yi) / ((yj - yi) or 1e-12) + xi:
            c = not c
        j = i
    return c


def in_park(lat, lon, parks):
    """The smallest named park whose outline holds the point."""
    best = None
    for s_, n_, w_, e_, pts, name in parks:
        if s_ <= lat <= n_ and w_ <= lon <= e_ and inside(lat, lon, pts):
            size = (n_ - s_) * (e_ - w_)
            if best is None or size < best[0]:
                best = (size, name)
    return best[1] if best else None


def overpass_box(s, w, n, e, q_for, depth=0):
    """One box; when Overpass times out or refuses it, the box is cut in 4 and asked again (twice at most)."""
    bb = f'{s},{w},{n},{e}'
    for attempt in range(3):
        url = OVERPASS[attempt % len(OVERPASS)]
        try:
            got = json.loads(http(url, {'data': q_for(bb)}, timeout=280))
            remark = got.get('remark') or ''
            if 'error' in remark.lower():
                raise RuntimeError(remark[:120])
            return got
        except Exception as err:
            print(f'  Overpass {bb} on {url}: {err}', flush=True)
            time.sleep(15 + 15 * attempt)
    if depth >= 2 or (n - s) * (e - w) < 20:
        return None  # small boxes (Hawaii, Puerto Rico...) are not cut again
    ms, mw = (s + n) / 2, (w + e) / 2
    parts = [overpass_box(*b, q_for, depth + 1) for b in ((s, w, ms, mw), (s, mw, ms, e), (ms, w, n, mw), (ms, mw, n, e))]
    if any(p is None for p in parts):
        print(f'  box {bb}: some pieces failed', flush=True)
    return {'elements': [x for p in parts if p for x in p.get('elements', [])]}


def fetch_osm():
    out = []
    rx = 'dirt ?jump|pump ?track|bike ?park|bmx|skills? (park|course|area)|jump (park|line)|velodrome|freeride'
    for s, w, n, e in BOXES:
        bb = f'{s},{w},{n},{e}'
        q_for = lambda bb: ('[out:json][timeout:240];('
             f'nwr["leisure"="bikepark"]({bb});'
             f'nwr["cycling"="pump_track"]({bb});'
             f'nwr["sport"~"(^|;)bmx(;|$)"]({bb});'
             f'nwr["sport"~"(^|;)(mtb|cycling)(;|$)"]["leisure"~"^(track|pitch|sports_centre|park|recreation_ground)$"]({bb});'
             f'nwr["name"~"{rx}",i]["leisure"]({bb});'
             f'nwr["name"~"{rx}",i]["sport"]({bb});'
             ');out center tags;')
        got = overpass_box(s, w, n, e, q_for)
        if got is None:
            print(f'OSM box {bb}: FAILED', flush=True)
            continue
        n0 = len(out)
        for el in got.get('elements', []):
            t = el.get('tags') or {}
            lat = el.get('lat') or (el.get('center') or {}).get('lat')
            lon = el.get('lon') or (el.get('center') or {}).get('lon')
            if lat is not None and lon is not None:
                r = osm_record(f'{el["type"]}/{el["id"]}', lat, lon, t)
                if r:
                    out.append(r)
        print(f'OSM box {bb}: {len(out) - n0}', flush=True)
    return out


def clean(d):
    return {k: v for k, v in d.items() if v not in (None, '')}


# ── 2. Overture ──
def fetch_overture():
    try:
        import duckdb
    except ImportError:
        print('Overture skipped: duckdb not installed', flush=True)
        return []
    cat = json.loads(http('https://stac.overturemaps.org/catalog.json'))
    release = cat.get('latest') or sorted(l['href'].split('/')[1] for l in cat['links'] if l.get('rel') == 'child')[-1]
    release = release.strip('./').split('/')[0]
    con = duckdb.connect()
    con.execute("INSTALL httpfs; LOAD httpfs; SET s3_region='us-west-2';")
    q = f"""
      SELECT id, names.primary AS name, CAT_EXPR AS cat,
             (bbox.ymin + bbox.ymax) / 2 AS lat, (bbox.xmin + bbox.xmax) / 2 AS lon,
             websites[1] AS web, phones[1] AS phone, addresses[1].freeform AS street
      FROM read_parquet('s3://overturemaps-us-west-2/release/{release}/theme=places/type=place/*', hive_partitioning=1)
      WHERE bbox.xmin BETWEEN -180 AND -65 AND bbox.ymin BETWEEN 17 AND 72
        AND addresses[1].country = 'US' AND confidence >= 0.3
        AND (regexp_matches(lower(CAT_EXPR), 'bmx|bike_park|mountain_bik|pump_track|velodrome|dirt_jump|cycling|bike|bicycle')
             OR regexp_matches(lower(CAT_EXPR), 'skate')
             OR regexp_matches(lower(names.primary), 'dirt ?jumps?|pump ?track|bike ?park|bmx|skills? (park|course)|velodrome|skate ?park'))
    """
    rows = None
    for expr in ("coalesce(taxonomy.primary, basic_category)", "basic_category", "categories.primary"):
        try:
            rows = con.execute(q.replace('CAT_EXPR', expr)).fetchall()
            print(f'Overture {release} category field: {expr}', flush=True)
            break
        except Exception as err:
            last = err
    if rows is None:
        raise last
    out, cats = [], {}
    for oid, name, c, lat, lon, web, phone, street in rows:
        c = c or ''
        if re.search(r'store|shop|parking|gym|rental|repair|dealer|fitness', c):
            continue  # a bike shop or bike parking called "... Bike Park" is not a place to ride
        if not (CATEGORY.search(c) or RIDE.search(name or '')) or is_business_noise(name):
            continue
        k = kind_of(name, None, c)
        if not k:
            continue
        cats[c] = cats.get(c, 0) + 1
        out.append([f'ovt/{oid}', round(lat, 6), round(lon, 6), clean({
            'name': name, 'ride': k, 'phone': phone, 'website': web, 'street': street, 'source': 'Overture Maps'})])
    print(f'Overture: {len(out)} · categories {dict(sorted(cats.items(), key=lambda kv: -kv[1])[:12])}', flush=True)
    return out


# ── 3. Foursquare ──
def fetch_foursquare():
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
      SELECT fsq_place_id, name, latitude, longitude, address, tel, website, date_refreshed,
             array_to_string(fsq_category_labels, ' | ') AS cats
      FROM read_parquet('hf://datasets/foursquare/fsq-os-places/{rel}/places/parquet/*.parquet')
      WHERE country = 'US' AND date_closed IS NULL AND latitude IS NOT NULL
        AND (regexp_matches(lower(array_to_string(fsq_category_labels, ' | ')), 'bmx|bike park|velodrome|pump track|skate park')
             OR regexp_matches(lower(name), 'dirt ?jumps?|pump ?track|bike ?park|bmx|skills? (park|course)|velodrome|skate ?park'))
    """
    out = []
    for fid, name, lat, lon, addr, tel, web, refreshed, cats in con.execute(q).fetchall():
        last = (cats or '').lower().split('|')
        if (refreshed or '')[:10] < '2022-01-01' or is_business_noise(name) or (
                last and all(re.search(r'store|shop|parking|gym|rental|repair|fitness|studio', x) for x in last)):
            continue
        if not (CATEGORY.search(cats or '') or RIDE.search(name or '')):
            continue
        k = kind_of(name, None, cats or '')
        if not k:
            continue
        out.append([f'fsq/{fid}', round(lat, 6), round(lon, 6), clean({
            'name': name, 'ride': k, 'phone': tel, 'website': web, 'street': addr, 'source': 'Foursquare OS Places'})])
    print(f'Foursquare {rel}: {len(out)}', flush=True)
    return out


def words(n):
    return set(re.findall(r'[a-z0-9]{3,}', (n or '').lower())) - {'the', 'park', 'bike', 'track', 'and', 'trail'}


def norm(n):
    return re.sub(r'[^a-z0-9]', '', (n or '').lower())


def same(a, b):
    """One place: same name within 2 km ("The Garden - Chicago Dirt Jumps" / "The Garden Chicago Dirt Jumps"),
    a shared name word within 600 m, or one of them has no name and they are within 250 m."""
    d = math.hypot((a[1] - b[1]) * 111000, (a[2] - b[2]) * 111000 * math.cos(math.radians(a[1])))
    na, nb = a[3].get('name'), b[3].get('name')
    if na and nb and d < 2000 and (norm(na) == norm(nb) or norm(na).startswith(norm(nb)) or norm(nb).startswith(norm(na))):
        return True
    if d > 600:
        return False
    if not na or not nb:
        return d <= 250
    return bool(words(na) & words(nb))


def merge(lists):
    """OSM first (it has the outline and the details), then the businesses fill in what is missing."""
    G = 0.01
    grid, out = {}, []
    for lst in lists:
        for p in lst:
            cell = (math.floor(p[1] / G), math.floor(p[2] / G))
            hit = None
            for i in range(cell[0] - 2, cell[0] + 3):
                for j in range(cell[1] - 3, cell[1] + 4):
                    for q in grid.get((i, j), []):
                        if same(q, p):
                            hit = q
                            break
            if hit:
                for k, v in p[3].items():
                    if k == 'source':
                        if v not in hit[3]['source']:
                            hit[3]['source'] += f' · {v}'
                    elif k not in hit[3]:
                        hit[3][k] = v
                continue
            out.append(p)
            grid.setdefault(cell, []).append(p)
    return out


def test():
    ok = ['The Garden - Chicago Dirt Jumps', 'Bensenville BMX', 'Valmont Bike Park', 'Ray\'s Indoor Mountain Bike Park',
          'Lakewood Pump Track', 'Northbrook Velodrome', 'Calumet Skills Park']
    bad = ['The 606', 'Bikettle Indoor Cycling Bootcamp', 'Chicago Bike Adventures', 'Trek Bicycle Store', 'Bike Park Rentals',
           'Comrade Cycles', 'Bike parking garage']
    for n in ok:
        assert RIDE.search(n) and not is_business_noise(n) and kind_of(n), n
    for n in bad:
        assert not (RIDE.search(n) and not is_business_noise(n) and kind_of(n)), n
    assert kind_of('The Garden - Chicago Dirt Jumps') == 'Dirt jumps'
    assert kind_of('Logan Blvd. Skate Park') == 'Skatepark' and kind_of('Big Marsh Pump Track') == 'Pump track'
    assert kind_of('', None, 'skate_park') == 'Skatepark'
    sq = [(41.94, -87.70), (41.94, -87.68), (41.95, -87.68), (41.95, -87.70)]
    assert in_park(41.945, -87.69, [(41.94, 41.95, -87.70, -87.68, sq, 'Clark (Richard) Park')]) == 'Clark (Richard) Park'
    assert in_park(41.96, -87.69, [(41.94, 41.95, -87.70, -87.68, sq, 'Clark (Richard) Park')]) is None
    a = ['ovt/1', 41.942011, -87.693565, {'name': 'The Garden Chicago Dirt Jumps', 'ride': 'Dirt jumps', 'source': 'A'}]
    b = ['ovt/2', 41.943428, -87.687912, {'name': 'The Garden - Chicago Dirt Jumps', 'ride': 'Dirt jumps', 'website': 'x', 'source': 'B'}]
    c = ['ovt/3', 42.03, -88.28, {'name': 'The Hill BMX Elgin', 'ride': 'BMX track', 'source': 'A'}]
    dd = ['fsq/4', 42.031, -88.281, {'name': 'The Hill Bmx', 'ride': 'BMX track', 'source': 'B'}]
    assert len(merge([[a, c], [b, dd]])) == 2
    print('name rules ok')


def main():
    test()
    if '--test' in sys.argv:
        return
    if '--pbf' in sys.argv:
        i = sys.argv.index('--pbf')
        osm_from_pbf(sys.argv[i + 1], sys.argv[i + 2])
        return
    # the three sources at the same time: a slow Overpass does not hold up the other two
    from concurrent.futures import ThreadPoolExecutor

    def run(item):
        name, fn = item
        try:
            return fn()
        except Exception as err:
            print(f'{name} failed: {err}', flush=True)
            return []
    osm_files = [a for a in sys.argv[1:] if a.endswith('.json')]
    if osm_files:  # OSM already read from the Geofabrik extracts: no Overpass
        osm = lambda: [r for f in osm_files for r in json.load(open(f))]
    else:
        osm = fetch_osm
    with ThreadPoolExecutor(3) as ex:
        parts = list(ex.map(run, (('osm', osm), ('overture', fetch_overture), ('foursquare', fetch_foursquare))))
    allp = merge(parts)
    allp.sort(key=lambda p: (p[1], p[2]))
    out = os.path.join(ROOT, 'assets', 'ride', 'ride_parks.json.gz')
    os.makedirs(os.path.dirname(out), exist_ok=True)
    open(out, 'wb').write(gzip.compress(json.dumps(allp, separators=(',', ':'), ensure_ascii=False).encode(), 9, mtime=0))
    kinds, srcs = {}, {}
    for p in allp:
        kinds[p[3]['ride']] = kinds.get(p[3]['ride'], 0) + 1
        for s in p[3]['source'].split(' · '):
            srcs[s] = srcs.get(s, 0) + 1
    garden = [p for p in allp if 'garden' in (p[3].get('name') or '').lower() and 'jump' in (p[3].get('name') or '').lower()]
    rep = os.path.join(ROOT, 'data', 'ride_parks', 'REPORT.md')
    os.makedirs(os.path.dirname(rep), exist_ok=True)
    with open(rep, 'w', encoding='utf-8') as f:
        f.write(f'# Places to ride (BMX page): {len(allp)}\n\nBy kind: {kinds}\n\nBy source: {srcs}\n\n'
                f'With a phone: {sum(1 for p in allp if p[3].get("phone"))} · with a website: '
                f'{sum(1 for p in allp if p[3].get("website"))}\n\n## The Garden (check)\n')
        for p in garden:
            f.write(f'- {json.dumps(p, ensure_ascii=False)}\n')
        f.write('\n## Around Chicago\n')
        for p in allp:
            if abs(p[1] - 41.88) < 0.6 and abs(p[2] + 87.7) < 0.8:
                f.write(f'- {p[3].get("name") or "(no name)"} · {p[3]["ride"]} · {p[3]["source"]}\n')
    print(f'{len(allp)} places · {kinds} · {srcs} · The Garden found: {len(garden)}', flush=True)


if __name__ == '__main__':
    main()
