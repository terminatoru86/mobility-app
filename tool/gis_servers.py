"""Find bike-parking layers on the GIS servers that cities, counties, states and regional agencies host
themselves (ArcGIS Server / ArcGIS Enterprise, like maps.slc.gov), which the ArcGIS Online search in
build_packs.discover_arcgis does not see.

For every site (data/foia/cities_big.json + data/foia/gov_sites.json + the GIS portals found by the
city-files crawl) it probes the usual GIS host names and REST paths, walks the service directory, keeps the
point layers whose names are about bike racks / lockers / repair stations / scooter or motorcycle parking /
e-bike charging, downloads their features and writes, per shard:
  data/gis_servers/layers_<shard>.json   the layers found (url, name, count, category)
  data/gis_servers/pts_<shard>.json      [[id, lat, lon, tags], ...] read by build_packs.fetch_cityfiles
  data/gis_servers/REPORT_<shard>.md
Env: SHARD, NSHARDS, THREADS, BUDGET (seconds per site). Run in GitHub Actions."""
import concurrent.futures as cf, glob, hashlib, json, os, re, threading, time, urllib.parse
import requests

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'data', 'gis_servers')
SHARD, NSHARDS = int(os.environ.get('SHARD', 0)), int(os.environ.get('NSHARDS', 1))
THREADS, BUDGET = int(os.environ.get('THREADS', 24)), int(os.environ.get('BUDGET', 300))
UA = {'User-Agent': 'MOBIlity-data-bot/1.0 (public bike-parking data; albis_iulian@yahoo.com)'}

WANT = re.compile(r'bike\s*_?rack|bicycle\s*_?rack|bike\s*_?park|bicycle\s*_?park|bike\s*_?corral|bicycle\s*_?corral|'
                  r'micromobility|scooter|moped|motorcycle|motorbike|bike\s*_?repair|bicycle\s*_?repair|fix-?it|'
                  r'repair\s*_?station|bike\s*_?locker|bicycle\s*_?locker|bike\s*_?station|bike\s*_?share|bikeshare|'
                  r'e-?bike|bike\s*_?amenit|bicycle\s*_?amenit|bike\s*_?facilit|bicycle\s*_?facilit|\bbikes?\b|bicycl|'
                  r'\bracks?\b|corral', re.I)
SKIP = re.compile(r'propos|request|survey|counts?\b|counters?\b|demand|plan(ned|ning)?\b|candidate|suitab|crash|collision|'
                  r'injur|fatal|theft|stolen|citation|violation|complaint|lane|route|trail|path|network|segment|'
                  r'buffer|heat|density|hex|grid|zone_?poly|area|boundar', re.I)
CATS = [
    ('repair', re.compile(r'repair|fix-?it|tool\s*station|maintenance\s*station', re.I), {'amenity': 'bicycle_repair_station'}),
    ('charging', re.compile(r'charg', re.I), {'amenity': 'charging_station', 'bicycle': 'yes'}),
    ('moto', re.compile(r'motorcycle|motorbike|moped', re.I), {'amenity': 'motorcycle_parking'}),
    ('scooter', re.compile(r'scooter|micromobility|mobility\s*hub', re.I), {'amenity': 'small_electric_vehicle_parking'}),
    ('locker', re.compile(r'locker|cage|bike\s*room|bike\s*station', re.I), {'amenity': 'bicycle_parking', 'bicycle_parking': 'lockers'}),
    ('share', re.compile(r'share|divvy|citi\s*bike|b-?cycle', re.I), {'amenity': 'bicycle_rental'}),
    ('racks', re.compile(r'.', re.I), {'amenity': 'bicycle_parking'}),
]
HOSTS = ('', 'gis.', 'maps.', 'arcgis.', 'gisweb.', 'mapping.', 'geo.', 'gis2.', 'egis.', 'webgis.', 'map.', 'gisapps.')
PATHS = ('arcgis/rest/services', 'server/rest/services', 'gis/rest/services', 'arcgisserver/rest/services',
         'hosting/rest/services', 'agsserver/rest/services')
PORTALS = ('portal', 'arcgis', 'gisportal')
TERMS = ('bike rack', 'bicycle parking', 'bike parking', 'bike corral', 'bike repair', 'scooter parking',
         'motorcycle parking', 'bike locker', 'micromobility')
lock = threading.Lock()


def get(url, timeout=12, **params):
    try:
        r = requests.get(url, params=params or None, headers=UA, timeout=timeout)
        if r.status_code != 200 or 'json' not in r.headers.get('content-type', '') and not r.text[:1] in '{[':
            return None
        return r.json()
    except Exception:
        return None


def catalog(base, t_end):
    """All (service url, type) under an ArcGIS REST services root."""
    out, folders = [], ['']
    root = get(base, f='json')
    if not root or ('services' not in root and 'folders' not in root):
        return None
    folders += [f for f in root.get('folders', [])][:80]
    for f in folders:
        if time.time() > t_end:
            break
        j = root if f == '' else get(f'{base}/{f}', f='json')
        for s in (j or {}).get('services', []):
            if s.get('type') in ('MapServer', 'FeatureServer'):
                out.append((f"{base}/{s['name']}/{s['type']}", s['name']))
    return out


def layers_of(svc, t_end):
    j = get(svc, f='json')
    res = []
    for ly in (j or {}).get('layers', []) or []:
        name = ly.get('name') or ''
        gt = ly.get('geometryType')
        if gt not in (None, 'esriGeometryPoint', 'esriGeometryMultipoint') or ly.get('subLayerIds'):
            continue
        full = svc.rsplit('/', 2)[-2] + ' ' + name
        if WANT.search(full) and not SKIP.search(name):
            res.append((f"{svc}/{ly['id']}", name, full))
    return res


def portal_search(host, t_end):
    found = []
    for p in PORTALS:
        base = f'https://{host}/{p}/sharing/rest'
        if not get(f'{base}/info', f='json', timeout=8):
            continue
        for t in TERMS:
            if time.time() > t_end:
                break
            j = get(f'{base}/search', f='json', num=50, q=f'"{t}" AND (type:"Feature Service" OR type:"Map Service")')
            for it in (j or {}).get('results', []):
                if it.get('url'):
                    found.append((it['url'].rstrip('/'), it.get('title', '')))
        break
    return found


def features(lurl):
    """[(lat, lon, attrs)] of one point layer, WGS84."""
    out, off = [], 0
    meta = get(lurl, f='json') or {}
    page = bool((meta.get('advancedQueryCapabilities') or {}).get('supportsPagination'))
    step = min(int(meta.get('maxRecordCount') or 1000), 2000)
    while len(out) < 50000:
        params = dict(where='1=1', outFields='*', outSR=4326, f='json', returnGeometry='true')
        if page:
            params.update(resultOffset=off, resultRecordCount=step)
        j = get(lurl + '/query', timeout=60, **params)
        fs = (j or {}).get('features', [])
        for f in fs:
            g = f.get('geometry') or {}
            if 'x' in g and 'y' in g and g['x'] is not None:
                x, y = g['x'], g['y']
            elif g.get('points'):
                x, y = g['points'][0][:2]
            else:
                continue
            if 17 <= y <= 72 and -180 <= x <= -64:
                out.append((y, x, f.get('attributes') or {}))
        if not page or len(fs) < step:
            break
        off += len(fs)
    return out


def site_hosts(site):
    d = re.sub(r'^www\.', '', site.lower().split('/')[0])
    return [h + d for h in HOSTS]


def scan(entry):
    """Layers found for one site."""
    t_end = time.time() + BUDGET
    found, seen = [], set()
    hosts = entry.get('hosts') or site_hosts(entry['site'])
    for host in hosts:
        if time.time() > t_end:
            break
        for p in PATHS:
            base = f'https://{host}/{p}'
            svcs = catalog(base, t_end)
            if svcs is None:
                continue
            for svc, sname in svcs:
                if time.time() > t_end:
                    break
                # look inside services whose name hints at transport / parks / bikes, and at small catalogs fully
                if len(svcs) > 60 and not re.search(r'bik|bicycl|transport|traffic|mobility|park|street|row|public.?works|'
                                                    r'amenit|facilit|infrastr|scooter|motor', sname, re.I):
                    continue
                for l in layers_of(svc, t_end):
                    if l[0] not in seen:
                        seen.add(l[0]); found.append(l)
            break
        for url, title in portal_search(host, t_end):
            if url.endswith(('MapServer', 'FeatureServer')):
                for l in layers_of(url, t_end):
                    if l[0] not in seen:
                        seen.add(l[0]); found.append(l)
    return entry, found


def sites():
    out, seen = [], set()
    for f in ('cities_big.json', 'gov_sites.json', 'contacts.json'):
        p = os.path.join(ROOT, 'data', 'foia', f)
        if os.path.exists(p):
            for c in json.load(open(p)):
                d = re.sub(r'^www\.', '', (c.get('site') or '').lower().split('/')[0])
                if d and d not in seen:
                    seen.add(d); out.append({'city': c['city'], 'site': d})
    # GIS portals the city-files crawl saw on the city websites (gis.city.gov, maps.county.org ...)
    extra = {}
    for f in glob.glob(os.path.join(ROOT, 'data', 'city_files', 'index*.json')):
        try:
            idx = json.load(open(f))
        except Exception:
            continue
        for city, e in idx.items():
            for u in (e.get('portals') or {}):
                h = urllib.parse.urlparse(u).netloc.lower()
                if h and not h.endswith(('arcgis.com', 'arcgisonline.com')) and h not in seen:
                    extra.setdefault(h, city)
    for h, city in extra.items():
        seen.add(h); out.append({'city': city, 'site': h, 'hosts': [h]})
    return out


def main():
    os.makedirs(OUT, exist_ok=True)
    allsites = sites()
    mine = [s for i, s in enumerate(allsites) if i % NSHARDS == SHARD]
    print(f'{len(allsites)} sites, this shard {len(mine)}', flush=True)
    layers, pts, rep = [], [], []
    with cf.ThreadPoolExecutor(THREADS) as ex:
        for entry, found in ex.map(scan, mine):
            for lurl, name, full in found:
                try:
                    feats = features(lurl)
                except Exception:
                    feats = []
                cat = next((c, t) for c, rx, t in CATS if rx.search(full))
                layers.append({'city': entry['city'], 'url': lurl, 'name': name, 'count': len(feats), 'cat': cat[0]})
                rep.append(f"| {entry['city']} | {name} | {cat[0]} | {len(feats)} | {lurl} |")
                key = hashlib.md5(lurl.encode()).hexdigest()[:8]
                for i, (lat, lon, a) in enumerate(feats):
                    t = dict(cat[1])
                    nm = next((str(a[k]) for k in a if re.search(r'^(name|site_?name|location|loc_?name|address|facility)$', k, re.I) and a[k]), '')
                    if nm:
                        t['name'] = nm[:80]
                    t['source'] = f"City GIS: {entry['city']}"
                    pts.append([f'gs/{key}-{a.get("OBJECTID", a.get("objectid", i))}', round(lat, 6), round(lon, 6), t])
            with lock:
                json.dump(layers, open(f'{OUT}/layers_{SHARD}.json', 'w'), indent=0)
    json.dump(pts, open(f'{OUT}/pts_{SHARD}.json', 'w'), ensure_ascii=False)
    head = [f'# GIS servers, shard {SHARD}/{NSHARDS}\n', f'Sites: {len(mine)} · layers: {len(layers)} · points: {len(pts)}\n',
            '| Place | Layer | Category | Points | URL |', '|---|---|---|---|---|']
    open(f'{OUT}/REPORT_{SHARD}.md', 'w').write('\n'.join(head + rep) + '\n')
    print('\n'.join(head + rep[:80]))


if __name__ == '__main__':
    main()
