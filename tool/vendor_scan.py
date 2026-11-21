#!/usr/bin/env python3
"""Which companies install / run bike racks, lockers, repair stands, scooter parking and charging for US
municipalities, and which maps the municipalities publish.

  scan  (SHARD/NSHARDS): reads data/foia/cities_big.json (all municipalities with a website). On each site:
        home page, sitemap and the site search for a few words; keeps pages about bike parking / micromobility /
        vendors / contracts. From those pages: known vendor names, links to company sites, and embedded maps
        (Google My Maps, ArcGIS web maps / apps / layers, uMap, Felt, Leaflet). -> data/vendors/scan_N.json
  maps: joins the scans; reads every map found on city pages and on the vendor sites (their "locations" /
        "where to find" / "map" pages): My Maps KML, ArcGIS point layers, Leaflet markers, store-locator JSON.
        Keeps US points whose map / layer is about our kinds of place. -> data/vendors/points.json + REPORT.md
"""
import collections
import concurrent.futures as cf
import glob
import io
import json
import os
import re
import sys
import time
import urllib.parse
import zipfile

import requests

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, 'tool'))
from public_maps import in_us  # noqa: E402

OUT = os.path.join(ROOT, 'data', 'vendors')
UA = {'User-Agent': 'MOBIlity-data-bot/1.0 (public bike-parking data; contact albis_iulian@yahoo.com)'}
SHARD, NSHARDS = int(os.environ.get('SHARD', 0)), int(os.environ.get('NSHARDS', 1))
THREADS = int(os.environ.get('THREADS', 24))
PAGES = int(os.environ.get('PAGES', 25))
SECS = int(os.environ.get('SECS', 120))

# companies that make, install or run this infrastructure (name -> site)
VENDORS = {
    'Dero': 'dero.com', 'Madrax': 'madrax.com', 'Saris': 'saris.com', 'Huntco': 'huntco.com', 'Sportworks': 'sportworks.com',
    'CycleSafe': 'cyclesafe.com', 'Bikeep': 'bikeep.com', 'Oonee': 'oonee.com', 'Kuhmute': 'kuhmute.com',
    'Swiftmile': 'swiftmile.com', 'BikeLink': 'bikelink.org', 'eLock': 'elocktechnologies.com', 'Duo-Gard': 'duo-gard.com',
    'Ground Control Systems': 'groundcontrolsystems.com', 'Creative Pipe': 'creativepipe.com', 'Belson': 'belson.com',
    'Landscape Forms': 'landscapeforms.com', 'Victor Stanley': 'victorstanley.com', 'Reliance Foundry': 'reliance-foundry.com',
    'Park-A-Bike': 'parkabike.com', 'Cora Bike Rack': 'cora.com', 'Palmer Group': 'palmersite.com', 'BikeArc': 'bikearc.com',
    'Bike Fixtation': 'bikefixtation.com', 'Velopa': 'velopa.com', 'Cyclehoop': 'cyclehoop.com', 'Function Foundry': 'functionfoundry.com',
    'Ultra Site': 'ultrasite.com', 'Wabash Valley': 'wabashvalley.com', 'Thomas Steele': 'thomas-steele.com', 'Kay Park': 'kaypark.com',
    'Upbeat': 'upbeat.com', 'Global Industrial': 'globalindustrial.com', 'Bike Rack Company': 'bikerackco.com',
    'Bikesafe': 'bikesafe.com', 'American Bicycle Security': 'ameribike.com', 'Spacesaver': 'spacesaver.com',
    'Graber': 'graber.com', 'Movatic': 'movatic.co', 'PBSC': 'pbsc.com', 'BCycle': 'bcycle.com', 'Bewegen': 'bewegen.com',
    'Drop Mobility': 'drop-mobility.com', 'Lime': 'li.me', 'Bird': 'bird.co', 'Spin': 'spin.app', 'Veo': 'veoride.com',
    'Tier': 'tier.app', 'Neuron': 'rideneuron.com', 'Superpedestrian': 'superpedestrian.com', 'Gotcha': 'gotchamobility.com',
    'Lyft Urban Solutions': 'lyft.com', 'Zagster': 'zagster.com', 'Peddle': 'peddleshare.com', 'Bolt': 'bolt.eu',
    'Charge Enterprises': 'charge.enterprises', 'ChargePoint': 'chargepoint.com', 'Bikehub': 'bikehub.com',
    'Bike Valet': 'bikevalet.com', 'Bikestation': 'bikestation.com', 'ProPark': 'propark.com', 'SpotHero': 'spothero.com',
    'LAZ Parking': 'lazparking.com', 'SP+': 'spplus.com', 'ABM': 'abm.com', 'Premium Parking': 'premiumparking.com',
    'ParkMobile': 'parkmobile.io', 'Passport': 'passportinc.com', 'Flowbird': 'flowbird.group', 'IPS Group': 'ipsgroupinc.com',
    'Populus': 'populus.ai', 'Ride Report': 'ridereport.com', 'Vianova': 'vianova.io', 'Eco-Counter': 'eco-counter.com',
    'Fixit': 'dero.com', 'Bike Repair Station': 'bikerepairstation.com', 'Park Tool': 'parktool.com', 'Ibis': 'ibisrepair.com',
}
VENDOR_RX = re.compile(r'\b(' + '|'.join(re.escape(k) for k in sorted(VENDORS, key=len, reverse=True)) + r')\b')
PAGE_KEY = re.compile(r'bike|bicycl|cycl|rack|corral|locker|scooter|micromobil|e-?bike|moped|motorcycle|repair\s*station|'
                      r'fix-?it|charging|vendor|contract|bid|rfp|rfq|award|purchas|procure|parking|mobility|map', re.I)
WORDS = ('bike rack', 'bicycle parking', 'bike locker', 'scooter parking', 'repair station', 'micromobility', 'bike share')
SEARCH = ('/search?q={}', '/Search?searchPhrase={}', '/?s={}')
MAP_RX = re.compile(
    r'(https?://(?:www\.)?google\.com/maps/d/(?:u/\d+/)?(?:viewer|embed|edit)\?[^"\'\s<>]*mid=[\w-]+'
    r'|https?://[\w.-]*arcgis\.com/(?:apps/[^"\'\s<>]*|home/webmap/viewer\.html\?[^"\'\s<>]*|home/item\.html\?id=\w+|'
    r'sharing/rest/content/items/\w+)'
    r'|https?://[^"\'\s<>]+/(?:arcgis|server)/rest/services/[^"\'\s<>]+/(?:Feature|Map)Server(?:/\d+)?'
    r'|https?://umap\.openstreetmap\.fr/[^"\'\s<>]+'
    r'|https?://(?:www\.)?felt\.com/map/[^"\'\s<>]+'
    r'|https?://[\w.-]+\.maps\.arcgis\.com/[^"\'\s<>]+)', re.I)
GOOD_MAP = re.compile(r'bike|bicycl|cycl|rack|corral|locker|scooter|micromobil|e-?bike|moped|motorcycle|repair|fix-?it|'
                      r'pump|charg|outlet|parking|valet', re.I)
BAD_MAP = re.compile(r'lane|route|trail|path|network|crash|count|propos|plan|survey|zoning|parcel|street|hazard|sign', re.I)
FILE_RX = re.compile(r'\.(xlsx?|csv|geojson|json|kml|kmz|zip|gpx|dbf|xml|txt|docx?|ods)(\?|$)', re.I)
CLOUD_RX = re.compile(r'docs\.google\.com/spreadsheets/d/[\w-]+|drive\.google\.com/(?:file/d/|open\?id=)[\w-]+|'
                      r'dropbox\.com/s[hc]?/[^"\'\s<>]+|[\w-]+\.box\.com/s/\w+|1drv\.ms/[^"\'\s<>]+|'
                      r'[\w-]+\.sharepoint\.com/:[xbt]:/[^"\'\s<>]+', re.I)
SKIP_HOST = re.compile(r'facebook|twitter|x\.com|instagram|youtube|linkedin|google\.|apple\.com|microsoft|adobe|civicplus|'
                       r'granicus|municode|govdelivery|nextdoor|tiktok|pinterest|flickr|vimeo|\.gov$|\.us$|\.mil$', re.I)


def get(url, timeout=25, **kw):
    """GET with a hard limit on the WHOLE download (timeout x 3) and on size (60 MB): requests' own
    timeout is per read, so a server that trickles bytes would otherwise hold a thread forever."""
    try:
        r = requests.get(url, headers=UA, timeout=timeout, stream=True, **kw)
        if r.status_code != 200:
            r.close()
            return None
        stop, buf, size = time.time() + timeout * 3, [], 0
        for chunk in r.iter_content(65536):
            buf.append(chunk)
            size += len(chunk)
            if time.time() > stop or size > 60_000_000:
                r.close()
                return None
        r._content = b''.join(buf)
        r._content_consumed = True
        return r
    except Exception:
        return None


def host(u):
    try:
        h = urllib.parse.urlparse(u if '//' in u else '//' + u).netloc.lower()
    except ValueError:
        return ''
    return h[4:] if h.startswith('www.') else h


def page_links(base, html):
    for m in re.finditer(r'<a\b[^>]*href=["\']([^"\'#]+)["\'][^>]*>(.*?)</a>', html, re.S | re.I):
        yield urllib.parse.urljoin(base, m.group(1).strip()), ' '.join(re.sub(r'<[^>]+>', ' ', m.group(2)).split())[:120]


def scan_city(c):
    try:
        return _scan_city(c)
    except Exception as e:  # one broken site must not stop the shard
        print(f"  {c.get('site')}: {str(e)[:100]}", flush=True)
        return {'city': c['city'], 'site': c['site'], 'vendors': {}, 'links': {}, 'maps': [], 'pages': [], 'files': {}}


def _scan_city(c):
    site = c['site'].strip('/').replace('https://', '').replace('http://', '')
    base = 'https://' + (site if site.count('.') > 1 or site.startswith('www.') else 'www.' + site)
    end = time.time() + SECS
    queue = [base + '/'] + [base + s.format(urllib.parse.quote(w)) for w in WORDS[:4] for s in SEARCH[:2]]
    sm = get(base + '/sitemap.xml', timeout=20)
    if sm is not None:
        for u in re.findall(r'<loc>\s*([^<\s]+)\s*</loc>', sm.text)[:5000]:
            if PAGE_KEY.search(u.rsplit('/', 1)[-1]):
                queue.append(u)
    seen, vendors, ext, maps, pages, files = set(), collections.Counter(), collections.Counter(), set(), [], {}
    while queue and len(seen) < PAGES and time.time() < end:
        u = queue.pop(0)
        if u in seen:
            continue
        seen.add(u)
        r = get(u)
        if r is None or 'html' not in (r.headers.get('Content-Type') or ''):
            continue
        html = r.text[:2_000_000]
        rel = bool(PAGE_KEY.search(u)) or u == base + '/'
        if rel:
            for m in VENDOR_RX.finditer(html):
                vendors[m.group(1)] += 1
            for m in MAP_RX.finditer(html):
                maps.add(m.group(0).replace('&amp;', '&'))
        for lu, text in page_links(r.url, html):
            h = host(lu)
            if not h:
                continue
            if h.endswith(host(base).split('.', 1)[-1] if host(base).count('.') > 1 else host(base)):
                if PAGE_KEY.search(text) or PAGE_KEY.search(lu.rsplit('/', 1)[-1]):
                    queue.append(lu)
            elif rel and not SKIP_HOST.search(h) and (PAGE_KEY.search(text) or VENDOR_RX.search(text)):
                ext[h] += 1
            if MAP_RX.match(lu):
                maps.add(lu)
            if rel and (CLOUD_RX.search(lu) or (FILE_RX.search(lu) and (GOOD_MAP.search(lu + ' ' + text)))):
                files[lu] = text
        if rel:
            for m in CLOUD_RX.finditer(html):
                files.setdefault(m.group(0), '')
        if rel and u != base + '/':
            pages.append(u)
    return {'city': c['city'], 'site': site, 'vendors': dict(vendors), 'links': dict(ext), 'maps': sorted(maps)[:40],
            'pages': pages[:15], 'files': dict(list(files.items())[:40])}


def scan():
    cities = json.load(open(os.path.join(ROOT, 'data', 'foia', 'cities_big.json')))
    ag = os.path.join(ROOT, 'data', 'foia', 'agencies.json')  # transit agencies (tool/transitland.py)
    if os.path.exists(ag):
        have = {c['site'] for c in cities}
        cities += [a for a in json.load(open(ag)) if a['site'] not in have]
    cities = cities[SHARD::NSHARDS]
    print(f'shard {SHARD}/{NSHARDS}: {len(cities)} municipalities', flush=True)
    os.makedirs(OUT, exist_ok=True)
    path, out, t0 = os.path.join(OUT, f'scan_{SHARD}.json'), [], time.time()
    with cf.ThreadPoolExecutor(THREADS) as ex:
        for i, r in enumerate(ex.map(scan_city, cities)):
            if r['vendors'] or r['links'] or r['maps'] or r['files']:
                out.append(r)
            if i % 200 == 0:
                json.dump(out, open(path, 'w'), separators=(',', ':'))
                print(f'{i}/{len(cities)} · with finds {len(out)} · {int(time.time() - t0)}s', flush=True)
    json.dump(out, open(path, 'w'), separators=(',', ':'))
    print(f'DONE {len(out)} municipalities with vendors / links / maps', flush=True)


# ───────── maps ─────────
KIND = [('bicycle_repair_station', re.compile(r'repair|fix-?it|tool\s*stand|pump', re.I), {'amenity': 'bicycle_repair_station'}),
        ('charging', re.compile(r'charg|outlet|swiftmile|kuhmute', re.I), {'amenity': 'charging_station', 'bicycle': 'yes', 'scooter': 'yes'}),
        ('locker', re.compile(r'locker|bikelink|elock|oonee|bikeep|cage|secure', re.I), {'amenity': 'bicycle_parking', 'bicycle_parking': 'lockers'}),
        ('scooter', re.compile(r'scooter|micromobil|corral|e-?scoot|mobility\s*hub', re.I), {'amenity': 'small_electric_vehicle_parking'}),
        ('moto', re.compile(r'motorcycle|moped', re.I), {'amenity': 'motorcycle_parking'}),
        ('racks', re.compile(r'rack|bike\s*parking|bicycle\s*parking|bike\s*valet', re.I), {'amenity': 'bicycle_parking'})]


SELLERS = re.compile(r'dealer|retailer|distributor|store-?locator|where-?to-?buy|sales\s*rep|showroom|reseller', re.I)


def kind_of(text):
    if SELLERS.search(text):
        return None
    if BAD_MAP.search(text) and not re.search(r'rack|parking|locker|repair|charg', text, re.I):
        return None
    for k, rx, tags in KIND:
        if rx.search(text):
            return k, tags
    return None


def kml_points(raw):
    if raw[:2] == b'PK':
        z = zipfile.ZipFile(io.BytesIO(raw))
        raw = z.read([n for n in z.namelist() if n.endswith('.kml')][0])
    txt = raw.decode('utf-8', 'replace')
    out = []
    for pm in re.findall(r'<Placemark>(.*?)</Placemark>', txt, re.S):
        c = re.search(r'<Point>\s*<coordinates>\s*([-\d.]+),([-\d.]+)', pm)
        if c:
            nm = re.search(r'<name>(.*?)</name>', pm, re.S)
            out.append((float(c.group(2)), float(c.group(1)), re.sub(r'<!\[CDATA\[|\]\]>', '', nm.group(1)).strip()[:80] if nm else ''))
    return out


def mymaps(url):
    mid = re.search(r'mid=([\w-]+)', url).group(1)
    r = get(f'https://www.google.com/maps/d/kml?mid={mid}&forcekml=1', timeout=60)
    if r is None:
        return '', []
    title = re.search(rb'<name>(.*?)</name>', r.content[:5000])
    return (title.group(1).decode('utf-8', 'replace') if title else ''), kml_points(r.content)


def arcgis_layer(url):
    info = get(url + '?f=json', timeout=40)
    if info is None:
        return '', []
    j = info.json()
    if j.get('geometryType') != 'esriGeometryPoint':
        return j.get('name', ''), []
    pts, off = [], 0
    for _ in range(40):
        r = get(url + '/query', timeout=90, params={'where': '1=1', 'outFields': '*', 'outSR': 4326, 'f': 'json',
                                                     'resultOffset': off, 'resultRecordCount': 2000})
        if r is None:
            break
        d = r.json()
        for f in d.get('features') or []:
            g = f.get('geometry') or {}
            if 'x' in g and 'y' in g:
                a = f.get('attributes') or {}
                nm = next((str(a[k]) for k in a if re.search(r'name|location|site|address', k, re.I) and a[k]), '')
                pts.append((g['y'], g['x'], nm[:80]))
        if not d.get('exceededTransferLimit'):
            break
        off += 2000
    return j.get('name', ''), pts


def arcgis_service(url):
    """FeatureServer / MapServer: every point layer whose name is about our places."""
    out = []
    info = get(url.rstrip('/') + '?f=json', timeout=40)
    if info is None:
        return out
    for ly in (info.json().get('layers') or [])[:30]:
        if GOOD_MAP.search(ly.get('name', '')) and kind_of(ly.get('name', '')):
            name, pts = arcgis_layer(f"{url.rstrip('/')}/{ly['id']}")
            out.append((name, pts))
    return out


def arcgis_item(item_id):
    """web map / app / item id -> its point layers."""
    out = []
    r = get(f'https://www.arcgis.com/sharing/rest/content/items/{item_id}?f=json', timeout=40)
    if r is None:
        return out
    try:
        it = r.json()
    except Exception:
        return out
    if not isinstance(it, dict):
        return out
    if isinstance(it.get('url'), str) and re.search(r'(Feature|Map)Server', it['url']):
        return arcgis_service(re.sub(r'/\d+$', '', it['url']))
    d = get(f'https://www.arcgis.com/sharing/rest/content/items/{item_id}/data?f=json', timeout=40)
    if d is None:
        return out
    try:
        data = d.json()
    except Exception:
        return out
    if not isinstance(data, dict):
        return out
    m_ = data.get('map')
    if isinstance(m_, dict) and isinstance(m_.get('itemId'), str):
        return arcgis_item(m_['itemId'])
    for wid in re.findall(r'"(?:webmap|itemId)"\s*:\s*"(\w{32})"', json.dumps(data))[:3]:
        if wid != item_id:
            out += arcgis_item(wid)
    for ly in (data.get('operationalLayers') or [])[:20]:
        if not isinstance(ly, dict):
            continue
        u = ly.get('url') or ''
        if not isinstance(u, str):
            continue
        if u and GOOD_MAP.search((ly.get('title') or '') + u) and kind_of((ly.get('title') or '') + ' ' + u):
            name, pts = arcgis_layer(u) if re.search(r'Server/\d+$', u) else ('', [])
            out.append((ly.get('title') or name, pts))
    return out


LEAFLET = re.compile(r'L\.(?:circle)?[mM]arker\(\s*\[\s*(-?\d+\.\d+)\s*,\s*(-?\d+\.\d+)\s*\]')
JSON_LL = re.compile(r'"(?:lat|latitude)"\s*:\s*"?(-?\d{1,2}\.\d{3,})"?\s*,\s*"(?:lng|lon|long|longitude)"\s*:\s*"?(-?\d{2,3}\.\d{3,})')


def vendor_maps(site):
    """A vendor's locations: pages called map / locations / find / where; Leaflet markers, JSON lat/lng, My Maps,
    ArcGIS. Returns [(title, points)]."""
    out, seen = [], set()
    home = get(f'https://www.{site}/') or get(f'https://{site}/')
    if home is None:
        return out
    cand = [home.url]
    for u, text in page_links(home.url, home.text):
        if host(u).endswith(site) and re.search(r'map|location|find|where|locator|install|network|stations?\b', text + ' ' + u, re.I):
            cand.append(u)
    for u in cand[:12]:
        if u in seen:
            continue
        seen.add(u)
        r = get(u)
        if r is None:
            continue
        html = r.text
        for src in re.findall(r'<script[^>]+src=["\']([^"\']+)["\']', html)[:20]:
            if re.search(r'map|locat|store|marker', src, re.I) and host(urllib.parse.urljoin(u, src)).endswith(site):
                s = get(urllib.parse.urljoin(u, src))
                if s is not None:
                    html += s.text[:3_000_000]
        pts = [(float(a), float(b), '') for a, b in LEAFLET.findall(html)] + [(float(a), float(b), '') for a, b in JSON_LL.findall(html)]
        if len(pts) >= 3:
            out.append((f'{site} {u}', pts))
        for m in set(MAP_RX.findall(html)):
            out += read_map(m, f'{site} ')
    return out


def read_map(url, prefix=''):
    try:
        if 'google.com/maps/d/' in url:
            t, pts = mymaps(url)
            return [(prefix + t + ' ' + url, pts)]
        ids = re.findall(r'(?:id|webmap|appid)=(\w{32})', url) or re.findall(r'items/(\w{32})', url)
        if ids:
            return [(prefix + n, p) for n, p in arcgis_item(ids[0])]
        if re.search(r'(Feature|Map)Server/\d+$', url):
            n, p = arcgis_layer(url)
            return [(prefix + n, p)]
        if re.search(r'(Feature|Map)Server$', url):
            return [(prefix + n, p) for n, p in arcgis_service(url)]
    except Exception as e:
        print('map failed', url[:120], str(e)[:80], flush=True)
    return []


PORTAL_Q = ('bike rack', 'bicycle parking', 'bike parking', 'bike locker', 'scooter parking', 'micromobility',
            'repair station', 'motorcycle parking', 'e-bike charging')


def geo_points(j):
    out = []
    for f in (j.get('features') or []) if isinstance(j, dict) else []:
        g = f.get('geometry') or {}
        c = g.get('coordinates')
        if g.get('type') == 'Point' and c and len(c) >= 2:
            p = f.get('properties') or {}
            nm = next((str(p[k]) for k in p if re.search(r'name|location|site|address', k, re.I) and p[k]), '')
            out.append((float(c[1]), float(c[0]), nm[:80]))
    return out


def portal_points(dom):
    """Socrata and CKAN open-data portals: datasets about our kinds of place, as points."""
    out, seen = [], set()
    for q in PORTAL_Q:
        r = get(f'https://api.us.socrata.com/api/catalog/v1', timeout=40, params={'domains': dom, 'q': q, 'limit': 20})
        for it in (r.json().get('results') or []) if r is not None else []:
            res = it.get('resource') or {}
            rid, name = res.get('id'), res.get('name') or ''
            if not rid or rid in seen or not kind_of(name):
                continue
            seen.add(rid)
            g = get(f'https://{dom}/resource/{rid}.geojson', timeout=90, params={'$limit': 50000})
            if g is not None:
                try:
                    out.append((name, geo_points(g.json())))
                except Exception:
                    pass
        r = get(f'https://{dom}/api/3/action/package_search', timeout=40, params={'q': q, 'rows': 20})
        try:
            pk = r.json()['result']['results'] if r is not None else []
        except Exception:
            pk = []
        for p in pk:
            for res in p.get('resources') or []:
                u, name = res.get('url') or '', (p.get('title') or '') + ' ' + (res.get('name') or '')
                if u in seen or not kind_of(name):
                    continue
                seen.add(u)
                fmt = (res.get('format') or '').lower()
                if 'geojson' in fmt or u.lower().endswith('.geojson'):
                    g = get(u, timeout=90)
                    if g is not None:
                        try:
                            out.append((name, geo_points(g.json())))
                        except Exception:
                            pass
                elif 'kml' in fmt or re.search(r'\.km[lz](\?|$)', u, re.I):
                    g = get(u, timeout=90)
                    if g is not None:
                        try:
                            out.append((name, kml_points(g.content)))
                        except Exception:
                            pass
                elif re.search(r'(Feature|Map)Server', u):
                    out += read_map(u, name + ' ')
    return out


def direct(u):
    m = re.search(r'docs\.google\.com/spreadsheets/d/([\w-]+)', u)
    if m:
        return f'https://docs.google.com/spreadsheets/d/{m.group(1)}/export?format=xlsx', 'xlsx'
    m = re.search(r'drive\.google\.com/(?:file/d/|open\?id=)([\w-]+)', u)
    if m:
        return f'https://drive.google.com/uc?export=download&id={m.group(1)}', None
    if 'dropbox.com' in u:
        return re.sub(r'([?&])dl=0', r'\1dl=1', u) + ('' if 'dl=1' in u else ('&' if '?' in u else '?') + 'dl=1'), None
    return u, None


def files():
    """Files and shared documents (Google Sheets / Drive, Dropbox, Box, OneDrive) linked from municipal bike /
    parking pages: downloaded, read like the city files, rows saved for tool/city_rows.py."""
    import city_files as cfm
    import requests as rq
    os.chdir(ROOT)
    scans = [r for f in sorted(glob.glob(os.path.join(OUT, 'scan_*.json'))) for r in json.load(open(f))]
    todo = [(r['city'], u, t) for r in scans for u, t in (r.get('files') or {}).items()]
    print(f'{len(todo)} files / shared documents', flush=True)
    kept = rows_n = 0

    def one(item):
        city, u, text = item
        url, ext = direct(u)
        try:
            resp = rq.get(url, headers=UA, timeout=60, stream=True)
            if resp.status_code != 200:
                return city, u, None
            ct = resp.headers.get('Content-Type') or ''
            if not ext:
                cd = resp.headers.get('Content-Disposition') or ''
                m = re.search(r'filename\*?=(?:UTF-8\'\')?"?([^";]+)', cd)
                ext = (m.group(1) if m else url.split('?')[0]).rsplit('.', 1)[-1].lower()
                if 'html' in ct and ext not in ('csv', 'json', 'geojson', 'kml', 'xml', 'txt'):
                    return city, u, None
            d = os.path.join(cfm.OUT, re.sub(r'[^A-Za-z0-9]+', '_', city).strip('_'))
            os.makedirs(d, exist_ok=True)
            path = os.path.join(d, 'v_' + __import__('hashlib').md5(u.encode()).hexdigest()[:8] + '.' + ext[:8])
            n = 0
            with open(path, 'wb') as fh:
                for ch in resp.iter_content(1 << 16):
                    n += len(ch)
                    if n > 40 << 20:
                        break
                    fh.write(ch)
            rows = cfm.extract(path)
            useful = [r for r in rows if 'error' not in r and (cfm.STRONG.search(json.dumps(r, ensure_ascii=False)) or GOOD_MAP.search(u + ' ' + text))]
            if useful:
                json.dump(useful[:5000], open(path + '.rows.json', 'w'), ensure_ascii=False)
            os.remove(path)
            return city, u, len(useful)
        except Exception as e:
            return city, u, None
    log = []
    with cf.ThreadPoolExecutor(12) as ex:
        for city, u, n in ex.map(one, todo):
            log.append(f'{n if n is not None else "-":>6}  {city}  {u[:120]}')
            if n:
                kept += 1
                rows_n += n
    open(os.path.join(OUT, 'FILES.md'), 'w').write(f'# Files linked from municipal pages\n\nRead: {len(todo)} · with rows: {kept} · '
                                                   f'rows: {rows_n}\n\n```\n' + '\n'.join(log) + '\n```\n')
    print(f'files with rows: {kept} · rows: {rows_n}', flush=True)


def maps():
    scans = [r for f in sorted(glob.glob(os.path.join(OUT, 'scan_*.json'))) for r in json.load(open(f))]
    vend = collections.Counter()
    linked = collections.Counter()
    cities_by_vendor = collections.defaultdict(list)
    city_maps = []
    for r in scans:
        for v, n in r['vendors'].items():
            vend[v] += 1
            cities_by_vendor[v].append(r['city'])
        for h in r['links']:
            linked[h] += 1
        for m in r['maps']:
            city_maps.append((r['city'], m))
    data_portals = set()
    for f in sorted(glob.glob(os.path.join(ROOT, 'data', 'city_files', 'index_*.json'))):
        for city, v in json.load(open(f)).items():
            for u, text in (v.get('portals') or {}).items():
                text = str(text)
                if MAP_RX.match(u) and (GOOD_MAP.search(text + ' ' + u)):
                    city_maps.append((city, u))
                m = re.match(r'https?://(data\.[\w.-]+|opendata\.[\w.-]+|[\w.-]*data[\w.-]*\.(?:gov|org|us|com))/?$', u.strip())
                if m:
                    data_portals.add((city, m.group(1)))
    city_maps = list(dict.fromkeys(city_maps))
    print(f'{len(scans)} municipalities with finds · {len(vend)} vendors · {len(city_maps)} city maps · '
          f'{len(data_portals)} open-data portals', flush=True)
    sites = sorted({VENDORS[v] for v in vend} | {h for h, n in linked.items() if n >= 3 and VENDOR_RX.search(h) is None} |
                   set(VENDORS.values()))
    found, log = {}, []

    def take(src, title, pts):
        k = kind_of(title)
        if not k or not pts:
            log.append(f'skip  {len(pts):6d}  {title[:110]}')
            return
        n = 0
        for lat, lon, nm in pts:
            if not (-90 < lat < 90 and -180 < lon < 180) or not in_us(lat, lon) or (17.4 <= lat < 18.9 and -68.2 <= lon < -65.0):
                continue
            key = f'vnd/{round(lat, 5)}_{round(lon, 5)}_{k[0]}'
            tags = dict(k[1])
            tags['source'] = src[:80]
            if nm:
                tags['name'] = nm
            found[key] = [key, round(lat, 6), round(lon, 6), tags]
            n += 1
        log.append(f'kept  {n:6d}  {k[0]:22s}  {title[:100]}')

    # time budget: what is read by then is kept (the job has a limit); the order puts vendor sites and portals first
    end = time.time() + 60 * int(os.environ.get('MAPS_MIN', 200))
    jobs = ([('site', s_, None) for s_ in sites] + [('portal', c_, d_) for c_, d_ in sorted(data_portals)] +
            [('map', c_, m_) for c_, m_ in city_maps])
    print(f'{len(jobs)} things to read (vendor sites, portals, maps)', flush=True)

    def run(j):
        if time.time() > end:
            return j, None
        kind, a, b = j
        try:
            if kind == 'site':
                return j, vendor_maps(a)
            if kind == 'portal':
                return j, portal_points(b)
            return j, read_map(b, a + ' · ')
        except Exception as e:
            return j, []
    done_n = skipped = 0
    # results as they come (one slow site must not hold the rest), and a hard stop at the time budget:
    # requests' timeout is per read, so a server that trickles bytes could otherwise hang the job for hours
    ex = cf.ThreadPoolExecutor(32)
    futs = [ex.submit(run, j) for j in jobs]
    try:
        for f in cf.as_completed(futs, timeout=max(60, end - time.time() + 120)):
            (kind, a, b), res = f.result()
            if res is None:
                skipped += 1
                continue
            done_n += 1
            src = f'{a} map' if kind == 'site' else f'{a} open data' if kind == 'portal' else f'{a} map'
            for title, pts_ in res:
                take(src, title, pts_)
            if done_n % 500 == 0:
                json.dump(list(found.values()), open(os.path.join(OUT, 'points.json'), 'w'), separators=(',', ':'))
                print(f'{done_n}/{len(jobs)} read · {len(found)} points', flush=True)
    except cf.TimeoutError:
        print('time budget reached: stopping the reads still hanging', flush=True)
    skipped = len(jobs) - done_n
    ex.shutdown(wait=False, cancel_futures=True)
    log.insert(0, f'read {done_n} of {len(jobs)} · not read (time): {skipped}')
    pts = list(found.values())
    json.dump(pts, open(os.path.join(OUT, 'points.json'), 'w'), separators=(',', ':'))
    lines = [f'# Vendors and maps of US municipalities', '',
             f'Municipalities + transit agencies scanned with finds: {len(scans)} · city maps: {len(city_maps)} · vendor sites: {len(sites)} · open-data portals: {len(data_portals)} · {log[0]}',
             f'**Map points kept (US, our kinds of place): {len(pts)}** · by kind: '
             f'{dict(collections.Counter(p[0].rsplit("_", 1)[1] for p in pts))}', '',
             '## Vendors named on municipal pages (number of municipalities)', *[f'- {v}: {n}' for v, n in vend.most_common(60)], '',
             '## Company sites most linked from municipal bike / parking pages', *[f'- {h}: {n}' for h, n in linked.most_common(60)], '',
             '## Maps read', '```', *log[:3000], '```']
    open(os.path.join(OUT, 'REPORT.md'), 'w').write('\n'.join(lines) + '\n')
    print('\n'.join(lines[:6]), flush=True)
    os._exit(0)  # threads still stuck on a slow server must not keep the process alive


if __name__ == '__main__':
    {'scan': scan, 'maps': maps, 'files': files}[sys.argv[1] if len(sys.argv) > 1 else 'scan']()
