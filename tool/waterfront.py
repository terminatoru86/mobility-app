"""Theme / water parks, marinas and harbours, and beaches (ocean, lakes, rivers) across the US: what riders need there.

For each such place we read its OWN website (often its manager's: a park district, a marina company, a park chain)
and look for everything in our categories: bike racks, motorcycle / moped / scooter parking (paid or free), bike and
scooter rentals, air pumps, bike repair stations, e-bike charging, bike washes. What the map does not have yet within
300 m is added, at the place, with the page it comes from. We also
collect the named bike paths along the water (riverwalks, boardwalks, lakefront / harbor trails, promenades) for
Explore. The places themselves do not become pins.

  python3 tool/waterfront.py --test
  python3 tool/waterfront.py --pbf cut.osm.pbf part.json       one Geofabrik extract (cut by the workflow)
  python3 tool/waterfront.py part1.json part2.json ...         join + Overture + Foursquare + websites ->
        data/waterfront.json (parking for the packs, ids wtr/...), data/waterfront_paths.json (routes),
        data/waterfront/places.json (the places, their websites and managers) and data/waterfront/REPORT.md
"""
import gzip
import html as htmllib
import json
import math
import os
import re
import sys
import urllib.parse
import urllib.request
import urllib.robotparser
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
AGENT = 'MOBIlityBot'
UA = {'User-Agent': f'{AGENT}/1.0 (bike and motorcycle parking for a riders map; github.com/terminatoru86/mobility-app)',
      'Accept': 'text/html'}

WATER = re.compile(r'\b(river\s*walk|riverwalk|river\s*(trail|path|front|greenway)|riverfront|board\s*walk|boardwalk|beach|'
                   r'lake\s*front|lakefront|lake\s*shore|lakeshore|lakewalk|lake\s*walk|harbou?r|bay\s*(trail|walk|path)|bayfront|bayshore|'
                   r'waterfront|promenade|sea\s*wall|seawall|shore(line)?\s*(trail|path|walk)|marina|pier|esplanade|canal\s*(trail|path|walk)|'
                   r'levee\s*(trail|path)|ocean\s*(front|walk|trail)|strand)\b', re.I)
KIND_LABEL = {'theme_park': 'Theme park', 'water_park': 'Water park', 'marina': 'Marina', 'harbour': 'Harbor', 'beach': 'Beach'}


def kind_of_osm(t):
    if t.get('tourism') == 'theme_park':
        return 'theme_park'
    if t.get('leisure') == 'water_park':
        return 'water_park'
    if t.get('leisure') == 'marina' or t.get('harbour') in ('yes', 'marina') or t.get('seamark:type') == 'harbour':
        return 'marina'
    if t.get('landuse') == 'port' or t.get('harbour') == 'port' or t.get('industrial') == 'port':
        return None  # cargo ports: no visitors to park for
    if t.get('natural') == 'beach' or t.get('leisure') == 'beach_resort':
        return 'beach'
    return None


def kind_of_cat(cat):
    c = (cat or '').lower()
    if re.search(r'water[\s_]*park', c):
        return 'water_park'
    if re.search(r'amusement|theme[\s_]*park', c):
        return 'theme_park'
    if re.search(r'marina|boat[\s_]*(dock|slip|harbou?r)|yacht[\s_]*club|harbou?r', c):
        return 'marina'
    if re.search(r'beach(?![\s_]*(bar|club|wear|house|front[\s_]*hotel))', c):
        return 'beach'
    return None


# ───────── 1. one Geofabrik extract ─────────
def from_pbf(pbf, out_json):
    import osmium
    from osm_routes import join, simplify, hav
    dest, paths = [], {}

    def rec(oid, lat, lon, t):
        k = kind_of_osm(t)
        name = t.get('name')
        if not k or not name:
            return
        dest.append([f'{oid}', round(lat, 6), round(lon, 6), {x: v for x, v in {
            'kind': k, 'name': name, 'website': t.get('website') or t.get('contact:website') or t.get('url'),
            'operator': t.get('operator'), 'phone': t.get('phone') or t.get('contact:phone'),
            'opening_hours': t.get('opening_hours'), 'source': 'OpenStreetMap'}.items() if v}])

    class H(osmium.SimpleHandler):
        def node(self, n):
            if n.tags and n.location.valid():
                rec(f'node/{n.id}', n.location.lat, n.location.lon, dict(n.tags))

        def way(self, w):
            t = dict(w.tags)
            pts = [(nd.lat, nd.lon) for nd in w.nodes if nd.location.valid()]
            if len(pts) < 2:
                return
            hw = t.get('highway')
            if hw:
                name = t.get('name') or ''
                bike_ok = hw == 'cycleway' or t.get('bicycle') in ('yes', 'designated', 'permissive')
                if name and bike_ok and WATER.search(name) and t.get('access') not in ('private', 'no'):
                    paths.setdefault(name, {'ids': [], 'ways': [], 'tags': {}})
                    p = paths[name]
                    p['ids'].append(w.id)
                    p['ways'].append(pts)
                    for k in ('surface', 'operator', 'website', 'lit'):
                        if t.get(k) and k not in p['tags']:
                            p['tags'][k] = t[k]
                return
            rec(f'way/{w.id}', sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts), t)

    H().apply_file(pbf, locations=True)
    routes = []
    for name, p in paths.items():
        lines = [simplify(l) for l in join(p['ways'])]
        km = sum(hav(l[i - 1], l[i]) for l in lines for i in range(1, len(l)))
        if km < 1 or km >= 50:
            continue
        # one name used by two far-apart paths (two "Beach Trail"s in two towns): split by distance
        groups = []
        for l in lines:
            for g in groups:
                if min(hav(l[0], x[0]) for x in g) < 15:
                    g.append(l)
                    break
            else:
                groups.append([l])
        for gi, g in enumerate(groups):
            gk = sum(hav(l[i - 1], l[i]) for l in g for i in range(1, len(l)))
            if gk < 1:
                continue
            routes.append({'id': f'w/{p["ids"][0]}' + (f'-{gi}' if gi else ''), 'name': name, 'ref': None, 'kind': 'bicycle',
                           'network': None, 'operator': p['tags'].get('operator'), 'km': round(gk, 1),
                           'tags': {k: v for k, v in p['tags'].items() if k != 'operator'},
                           'lines': [[round(v, 5) for pt in l for v in pt] for l in g]})
    json.dump({'dest': dest, 'paths': routes}, open(out_json, 'w'))
    print(f'{pbf}: {len(dest)} places ({sum(1 for d in dest if d[3].get("website"))} with a website), {len(routes)} waterfront paths', flush=True)


# ───────── 2. Overture + Foursquare ─────────
def fetch_overture():
    import duckdb
    cat = json.loads(urllib.request.urlopen('https://stac.overturemaps.org/catalog.json', timeout=60).read())
    release = cat.get('latest') or sorted(l['href'].split('/')[1] for l in cat['links'] if l.get('rel') == 'child')[-1]
    release = release.strip('./').split('/')[0]
    con = duckdb.connect()
    con.execute("INSTALL httpfs; LOAD httpfs; SET s3_region='us-west-2';")
    q = f"""
      SELECT id, names.primary, CAT_EXPR, (bbox.ymin + bbox.ymax) / 2, (bbox.xmin + bbox.xmax) / 2, websites[1], phones[1],
             brand.names.primary
      FROM read_parquet('s3://overturemaps-us-west-2/release/{release}/theme=places/type=place/*', hive_partitioning=1)
      WHERE bbox.xmin BETWEEN -180 AND -65 AND bbox.ymin BETWEEN 17 AND 72 AND addresses[1].country = 'US'
        AND confidence >= 0.6
        AND regexp_matches(lower(CAT_EXPR), 'amusement|theme_park|water_park|marina|harbor|harbour|boat_dock|yacht_club|beach')
    """
    rows, last = None, None
    for expr in ('coalesce(taxonomy.primary, basic_category)', 'basic_category', 'categories.primary'):
        try:
            rows = con.execute(q.replace('CAT_EXPR', expr)).fetchall()
            break
        except Exception as err:
            last = err
    if rows is None:
        raise last
    out = []
    for i, n, c, la, lo, w, ph, brand in rows:
        k = kind_of_cat(c)
        if k and n:
            out.append([f'ovt/{i}', round(la, 6), round(lo, 6), {x: v for x, v in {
                'kind': k, 'name': n, 'website': w, 'phone': ph, 'operator': brand, 'source': 'Overture Maps'}.items() if v}])
    print(f'Overture: {len(out)} places', flush=True)
    return out


def fetch_foursquare():
    token = os.environ.get('HF_TOKEN')
    if not token:
        return []
    import duckdb
    req = urllib.request.Request('https://huggingface.co/api/datasets/foursquare/fsq-os-places/tree/main/release',
                                 headers={'Authorization': f'Bearer {token}'})
    tree = json.loads(urllib.request.urlopen(req, timeout=60).read())
    rel = sorted(t['path'] for t in tree if t.get('type') == 'directory' and 'dt=' in t.get('path', ''))[-1]
    con = duckdb.connect()
    con.execute('INSTALL httpfs; LOAD httpfs;')
    con.execute(f"CREATE SECRET hf (TYPE huggingface, TOKEN '{token}');")
    rows = con.execute(f"""
      SELECT fsq_place_id, name, latitude, longitude, array_to_string(fsq_category_labels, ' | '), website, tel, date_refreshed
      FROM read_parquet('hf://datasets/foursquare/fsq-os-places/{rel}/places/parquet/*.parquet')
      WHERE country = 'US' AND date_closed IS NULL AND latitude IS NOT NULL
        AND regexp_matches(lower(array_to_string(fsq_category_labels, ' | ')), 'amusement|theme park|water park|marina|harbor|boat|beach')
    """).fetchall()
    out = []
    for i, n, la, lo, c, w, ph, d in rows:
        last = (c or '').split('|')[-1]
        k = kind_of_cat(last) or kind_of_cat(c)
        if k and n and (d or '')[:10] >= '2022-01-01':
            out.append([f'fsq/{i}', round(la, 6), round(lo, 6), {x: v for x, v in {
                'kind': k, 'name': n, 'website': w, 'phone': ph, 'source': 'Foursquare OS Places'}.items() if v}])
    print(f'Foursquare: {len(out)} places', flush=True)
    return out


def norm(n):
    return re.sub(r'[^a-z0-9]', '', (n or '').lower())


def merge_dest(lists):
    G = 0.01
    grid, out = {}, []
    for lst in lists:
        for p in lst:
            cell = (math.floor(p[1] / G), math.floor(p[2] / G))
            hit = None
            for i in range(cell[0] - 1, cell[0] + 2):
                for j in range(cell[1] - 1, cell[1] + 2):
                    for q in grid.get((i, j), []):
                        d = dist(p, q)
                        if q[3]['kind'] == p[3]['kind'] and ((norm(q[3]['name']) == norm(p[3]['name']) and d < 1500) or d < 120):
                            hit = q
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


def dist(a, b):
    return math.hypot((a[1] - b[1]) * 111000, (a[2] - b[2]) * 111000 * math.cos(math.radians(a[1])))


# ───────── 3. what the websites say ─────────
SAYS = {
    'bike': re.compile(r'\b(bike|bicycle)\s*(racks?|parking|lockers?|corrals?|valet|storage)\b|\bpark\s+(your\s+)?(bike|bicycle)s?\b', re.I),
    'moto': re.compile(r'\bmotorcycles?\s*(parking|spaces?|stalls?|lot|area|corral)\b|\bpark\s+(your\s+)?motorcycles?\b', re.I),
    'scooter': re.compile(r'\b(scooter|moped)s?\s*(parking|corrals?|spaces?)\b', re.I),
    'rent': re.compile(r'\b(rent|rental|rentals|hire)\s+(a\s+)?(e-?bikes?|bikes?|bicycles?|surreys?|tandems?|cruisers?|scooters?|mopeds?)\b|'
                       r'\b(e-?bikes?|bikes?|bicycles?|surreys?|cruisers?|scooters?|mopeds?)\s+(rentals?|for\s+rent|hire)\b', re.I),
    'pump': re.compile(r'\b(air\s+pumps?|bike\s+pumps?|tire\s+(pumps?|inflation)|free\s+air)\b', re.I),
    'repair': re.compile(r'\b(bike|bicycle)\s+(repair|fix-?it|tool)\s+(stations?|stands?)\b|\bfix-?it\s+stations?\b', re.I),
    'charge': re.compile(r'\b(e-?bike|electric\s+bike|scooter)\s+charging\b|\bcharg(e|ing)\s+(your\s+)?(e-?bikes?|scooters?)\b', re.I),
    'wash': re.compile(r'\b(bike|bicycle)\s+wash(ing)?\s*(stations?|area)?\b', re.I),
}
NOT_HERE = re.compile(r'\bno\s+(bikes?|bicycles?|motorcycles?|scooters?|mopeds?|rentals?)\b|not\s+(allowed|permitted|available)|prohibited', re.I)
PRICE = re.compile(r'\$\s?(\d{1,3}(?:\.\d{2})?)')


def visible(page):
    text = re.sub(r'(?is)<(script|style|noscript|svg)\b.*?</\1>|<[^>]+>', ' ', page or '')
    return re.sub(r'\s+', ' ', htmllib.unescape(text))


def what_page_says(text):
    """{'bike': {'snip':..., 'fee': 'yes'|'no'|None, 'charge': '$5'}, ...} for what the page says the place has.
    Free / price are read only in the sentence that names the thing."""
    out = {}
    sentences = re.split(r'(?<=[.!?;•|])\s+', text)
    for k, rx in SAYS.items():
        for i, sent in enumerate(sentences):
            m = rx.search(sent)
            if not m or NOT_HERE.search(sent):
                continue
            snip = ' '.join(sentences[max(0, i - 1):i + 2]).strip()
            fee = 'no' if re.search(r'\bfree\b|no\s+charge|complimentary', sent, re.I) else None
            pm = PRICE.search(sent)
            if pm and fee != 'no':
                fee = 'yes'
            out[k] = {'snip': snip[:240], 'fee': fee, 'charge': f'${pm.group(1)}' if pm and fee == 'yes' else None}
            break
    return out


def _get(url, timeout=10):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        if 'html' not in (r.headers.get('Content-Type') or 'html'):
            return ''
        return r.read(2_000_000).decode('utf-8', 'replace')


LINKS = re.compile(r'park(ing)?|getting[\s_-]*here|directions|plan[\s_-]*(your[\s_-]*)?visit|visit|transport|amenit|faq|'
                   r'bike|bicycle|access|hours|marina[\s_-]*info|facilities|guest[\s_-]*info', re.I)


def read_site(url):
    """{'pages': [...], 'says': {...}} or None."""
    try:
        parts = urllib.parse.urlsplit(url if '://' in url else 'https://' + url)
        if parts.scheme not in ('http', 'https') or not parts.netloc:
            return None
        url = urllib.parse.urlunsplit(parts)
        base = f'{parts.scheme}://{parts.netloc}'
        rp = urllib.robotparser.RobotFileParser()
        try:
            with urllib.request.urlopen(urllib.request.Request(base + '/robots.txt', headers=UA), timeout=8) as r:
                rp.parse(r.read(200_000).decode('utf-8', 'replace').splitlines())
        except Exception:
            rp.parse([])
        if not rp.can_fetch(AGENT, url):
            return {'no': 1}
        home = _get(url)
        says, pages = {}, [url]
        for k, v in what_page_says(visible(home)).items():
            says[k] = {**v, 'page': url}
        host = parts.netloc.lower().removeprefix('www.')
        extra = []
        for m in re.finditer(r'<a\b[^>]*href\s*=\s*["\']([^"\'#]+)["\'][^>]*>(.*?)</a>', home, re.S | re.I):
            href, label = m.group(1).strip(), re.sub(r'<[^>]+>', ' ', m.group(2))
            if not LINKS.search(href + ' ' + label):
                continue
            full = urllib.parse.urljoin(url, href)
            p2 = urllib.parse.urlsplit(full)
            if p2.scheme in ('http', 'https') and p2.netloc.lower().removeprefix('www.') == host and full not in extra \
                    and not re.search(r'\.(pdf|jpe?g|png|gif|zip)$', p2.path, re.I) and full.rstrip('/') != url.rstrip('/'):
                # the parking / getting-here pages first
                extra.insert(0, full) if re.search(r'park|getting|direction|bike|bicycle', href + label, re.I) else extra.append(full)
        for e in extra[:5]:
            if len(says) == len(SAYS) or not rp.can_fetch(AGENT, e):
                continue
            try:
                pg = visible(_get(e, timeout=8))
            except Exception:
                continue
            pages.append(e)
            for k, v in what_page_says(pg).items():
                says.setdefault(k, {**v, 'page': e})
        return {'pages': pages, 'says': says}
    except Exception:
        return None


def packs_parking():
    """Two-wheeler parking already in the map packs, by ~1 km cell."""
    grid = {}
    out_dir = os.path.join(ROOT, 'assets', 'osm', 'tiles')
    for f in os.listdir(out_dir):
        if not re.match(r't_-?\d+_-?\d+\.json\.gz$', f):
            continue
        for r in json.loads(gzip.decompress(open(os.path.join(out_dir, f), 'rb').read())):
            a, sh = r[3].get('amenity'), r[3].get('shop')
            k = {'bicycle_parking': 'bike', 'motorcycle_parking': 'moto', 'small_electric_vehicle_parking': 'scooter',
                 'kick-scooter_parking': 'scooter', 'bicycle_rental': 'rent', 'compressed_air': 'pump',
                 'bicycle_repair_station': 'repair', 'charging_station': 'charge', 'bicycle_wash': 'wash'}.get(a)
            if sh in ('bicycle', 'scooter') and r[3].get('service:bicycle:rental') == 'yes':
                k = 'rent'
            if k and not r[0].startswith('wtr/'):
                grid.setdefault((round(r[1] / 0.01), round(r[2] / 0.01)), []).append((k, r[1], r[2]))
    return grid


def has_near(grid, kind, lat, lon, m=300):
    gy, gx = round(lat / 0.01), round(lon / 0.01)
    for i in (-1, 0, 1):
        for j in (-1, 0, 1):
            for k, la, lo in grid.get((gy + i, gx + j), []):
                if k == kind and math.hypot((la - lat) * 111000, (lo - lon) * 111000 * math.cos(math.radians(lat))) < m:
                    return True
    return False


def main_join(parts):
    osm = [d for f in parts for d in json.load(open(f))['dest']]
    paths = [p for f in parts for p in json.load(open(f))['paths']]
    lists = [osm]
    for name, fn in (('overture', fetch_overture), ('foursquare', fetch_foursquare)):
        try:
            lists.append(fn())
        except Exception as err:
            print(f'{name} failed: {err}', flush=True)
    dest = merge_dest(lists)
    sites = {}
    for d in dest:
        w = (d[3].get('website') or '').strip()
        if w:
            sites.setdefault(w if '://' in w else 'https://' + w, []).append(d)
    # a website shared by many places (a whole park district, a chain) is read once and used for each of them
    print(f'{len(dest)} places, {len(sites)} websites to read', flush=True)
    with ThreadPoolExecutor(max_workers=48) as pool:
        got = dict(zip(sites, pool.map(read_site, sites)))
    grid = packs_parking()
    added, said = [], {k: 0 for k in SAYS}
    vlabel = {'bike': 'bike parking', 'moto': 'motorcycle parking', 'scooter': 'scooter parking', 'rent': 'bike rental',
              'pump': 'air pump', 'repair': 'bike repair station', 'charge': 'e-bike charging', 'wash': 'bike wash'}
    amen = {'bike': 'bicycle_parking', 'moto': 'motorcycle_parking', 'scooter': 'small_electric_vehicle_parking',
            'rent': 'bicycle_rental', 'pump': 'compressed_air', 'repair': 'bicycle_repair_station',
            'charge': 'charging_station', 'wash': 'bicycle_wash'}
    for url, ds in sites.items():
        r = got.get(url) or {}
        for d in ds:
            d[3]['site_read'] = bool(r.get('pages'))
            for k, v in (r.get('says') or {}).items():
                said[k] += 1
                d[3].setdefault('says', {})[k] = v
                if has_near(grid, k, d[1], d[2]):
                    continue
                t = {'amenity': amen[k], 'name': f'{d[3]["name"]} · {vlabel[k]}', 'fee': v.get('fee'), 'charge': v.get('charge'),
                     'website': v['page'], 'operator': d[3].get('operator'), 'phone': d[3].get('phone'),
                     'mobility:near': d[3]['name'], 'mobility:near_kind': KIND_LABEL[d[3]['kind']],
                     'mobility:approx': 'yes', 'description': v['snip'], 'source': f'Website of {d[3]["name"]}'}
                if k == 'bike':
                    t['bicycle_parking'] = 'stands'
                if k == 'charge':
                    t.update({'bicycle': 'yes', 'scooter': 'yes'})
                if k == 'rent' and re.search(r'scooter|moped', v['snip'], re.I) and not re.search(r'bike|bicycle', v['snip'], re.I):
                    t['rental'] = 'scooter'
                added.append([f'wtr/{d[0]}/{k}', d[1], d[2], {x: y for x, y in t.items() if y}])
                grid.setdefault((round(d[1] / 0.01), round(d[2] / 0.01)), []).append((k, d[1], d[2]))
    os.makedirs(os.path.join(ROOT, 'data', 'waterfront'), exist_ok=True)
    json.dump(added, open(os.path.join(ROOT, 'data', 'waterfront.json'), 'w'), separators=(',', ':'), ensure_ascii=False)
    json.dump(paths, open(os.path.join(ROOT, 'data', 'waterfront_paths.json'), 'w'), separators=(',', ':'), ensure_ascii=False)
    json.dump(dest, open(os.path.join(ROOT, 'data', 'waterfront', 'places.json'), 'w'), separators=(',', ':'), ensure_ascii=False)
    kinds = {}
    for d in dest:
        kinds[d[3]['kind']] = kinds.get(d[3]['kind'], 0) + 1
    read = sum(1 for v in got.values() if v and v.get('pages'))
    by_kind_added = {}
    for a in added:
        by_kind_added[a[3]['amenity']] = by_kind_added.get(a[3]['amenity'], 0) + 1
    with open(os.path.join(ROOT, 'data', 'waterfront', 'REPORT.md'), 'w', encoding='utf-8') as f:
        f.write(f'# Theme parks, marinas and beaches: {len(dest)} places\n\nBy kind: {kinds}\n\n'
                f'Websites: {len(sites)} · read: {read}\n\nWebsites that mention parking: {said}\n\n'
                f'Parking added (not on the map within 300 m): {len(added)} · {by_kind_added}\n\n'
                f'Waterfront bike paths: {len(paths)} ({round(sum(p["km"] for p in paths))} km)\n\n## Added around Chicago\n')
        for a in added:
            if abs(a[1] - 41.88) < 0.6 and abs(a[2] + 87.7) < 0.8:
                f.write(f'- {a[3]["name"]} · fee={a[3].get("fee", "?")} · {a[3]["website"]}\n  > {a[3]["description"][:200]}\n')
        f.write('\n## Waterfront paths around Chicago\n')
        for p in paths:
            l = p['lines'][0]
            if abs(l[0] - 41.88) < 0.6 and abs(l[1] + 87.7) < 0.8:
                f.write(f'- {p["name"]} · {p["km"]} km\n')
    print(f'{len(dest)} places {kinds} · sites read {read}/{len(sites)} · mention {said} · added {len(added)} · paths {len(paths)}', flush=True)


def test():
    s = what_page_says('Parking: Bike racks are available free of charge near the main gate. Motorcycle parking is $10 per day. '
                       'Rent a bike at the beach house. Free air pumps at the pier.')
    assert s['bike']['fee'] == 'no' and s['moto']['fee'] == 'yes' and s['moto']['charge'] == '$10', s
    assert 'rent' in s and s['pump']['fee'] == 'no', s
    assert 'bike' not in what_page_says('No bicycles allowed on the pier. Bike parking is not available.')
    assert kind_of_osm({'leisure': 'marina'}) == 'marina' and kind_of_osm({'landuse': 'port'}) is None
    assert kind_of_cat('amusement_park') == 'theme_park' and kind_of_cat('beach_bar') is None
    assert WATER.search('Chicago Riverwalk') and WATER.search('Lakefront Trail') and not WATER.search('Prairie Path')
    print('rules ok')


if __name__ == '__main__':
    test()
    if '--test' in sys.argv:
        sys.exit()
    if '--pbf' in sys.argv:
        i = sys.argv.index('--pbf')
        from_pbf(sys.argv[i + 1], sys.argv[i + 2])
    else:
        main_join([a for a in sys.argv[1:] if a.endswith('.json')])
