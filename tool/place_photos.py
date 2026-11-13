#!/usr/bin/env python3
"""Front photos of shops, service hubs and rentals, from open street-photo collections.

For every named shop, service hub and rental in the data packs it looks for street photos
  - taken from 2024 on,
  - 4-30 m away from the place,
  - with the camera turned towards the place (at most 25 degrees off),
in Mapillary, Panoramax and KartaView (all open licences; faces and number plates are blurred
by the source). 360-degree pictures taken 4-30 m away are kept too, marked "pano", with the direction
of the place inside the picture (the app has to cut that part out; flattened whole, they look bent).
Photos that mappers themselves linked to the place (image, mapillary, panoramax tags) come first.
It also reads the place's own website (robots.txt respected, like the hours reader) and keeps the
pictures the shop itself describes as its storefront / exterior / building (by the picture's
description or file name; logos, products and inside views are left out; a picture known to be
older than 2024 is left out). Websites shared by several places and social networks are not read.
When the site describes no picture as its storefront, the larger pictures of the page (and the one
it offers for link previews) are kept as candidates ("c"); tool/storefront_vision.py then looks at
them with an open image model and keeps the one that really shows a shop from the street.
The best ones (straight at the place, from about 12 m, newest) are kept in data/place_photos.json:

  { place id: { "t": day checked, "p": [[source, photo id or address, "YYYY-MM", metres, degrees off], ...] } }
  (for a picture from the website: ["website", address, "YYYY-MM" or "", 0, 0];
   for a 360-degree picture a sixth value "pano", and degrees = where the place is, -180..180, from the picture's middle)

Only where a photo is, not the picture itself: the app shows it from its source, with the credit.
A place is looked up again after RECHECK_DAYS. Nothing else is read: no private cameras, no
closed photo collections.
"""
import gzip
import json
import math
import os
import re
import sys
import time
import urllib.parse
import html as htmllib
import urllib.request
import urllib.robotparser
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'assets', 'osm', 'tiles')
LIST = os.path.join(ROOT, 'data', 'place_photos.json')
SINCE = datetime(2024, 1, 1, tzinfo=timezone.utc)
RECHECK_DAYS = 60
READER = 2  # raised when the rules change: every place is looked up again
UA = 'MOBIlityBot/1.0 (cycling app; front photos of bike shops from open street-photo collections)'


def mapillary_token():
    t = os.environ.get('MAPILLARY_TOKEN')
    if t:
        return t
    try:
        src = open(os.path.join(ROOT, 'lib', 'data', 'mapillary.dart'), encoding='utf-8').read()
        return re.search(r"kMapillaryToken = '([^']+)'", src).group(1)
    except Exception:
        return None


def kind(t):
    """Shop, Service hub or Rent: the same rule as in the app."""
    shop = t.get('shop')
    if shop in ('bicycle', 'motorcycle', 'scooter', 'motorcycle_repair'):
        return 'service' if (t.get('service:bicycle:repair') == 'yes' or shop == 'motorcycle_repair'
                             or t.get('motorcycle:repair') == 'yes') else 'shop'
    if t.get('amenity') == 'bicycle_rental' and t.get('bicycle_rental') != 'docking_station':
        return 'rent'
    return None


def meters(a, b):
    """Distance between two (lat, lon) points."""
    la1, lo1, la2, lo2 = map(math.radians, (a[0], a[1], b[0], b[1]))
    h = math.sin((la2 - la1) / 2) ** 2 + math.cos(la1) * math.cos(la2) * math.sin((lo2 - lo1) / 2) ** 2
    return 6371000 * 2 * math.asin(math.sqrt(h))


def bearing(a, b):
    """Compass direction from a to b, 0-360."""
    la1, la2, dlo = math.radians(a[0]), math.radians(b[0]), math.radians(b[1] - a[1])
    y = math.sin(dlo) * math.cos(la2)
    x = math.cos(la1) * math.sin(la2) - math.sin(la1) * math.cos(la2) * math.cos(dlo)
    return math.degrees(math.atan2(y, x)) % 360


def bbox(p, m):
    d_lat = m / 111200
    d_lon = d_lat / max(0.2, math.cos(math.radians(p[0])))
    return f'{p[1] - d_lon:.6f},{p[0] - d_lat:.6f},{p[1] + d_lon:.6f},{p[0] + d_lat:.6f}'


def get_json(url, timeout=12):
    req = urllib.request.Request(url, headers={'User-Agent': UA, 'Accept': 'application/json'})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode('utf-8', 'replace'))


def _date(v):
    """A datetime from epoch milliseconds or from text; None when it cannot be read."""
    try:
        if isinstance(v, (int, float)):
            return datetime.fromtimestamp(v / 1000, timezone.utc)
        s = str(v).strip().replace('Z', '+00:00').replace(' ', 'T', 1)
        d = datetime.fromisoformat(s)
        return d if d.tzinfo else d.replace(tzinfo=timezone.utc)
    except Exception:
        return None


# every source gives shots as: (camera (lat, lon), heading, taken at, source, photo id or address)

def mapillary(p, token):
    if not token:
        return []
    q = urllib.parse.urlencode({
        'access_token': token, 'bbox': bbox(p, 45), 'limit': 80, 'start_captured_at': SINCE.strftime('%Y-%m-%dT%H:%M:%SZ'),
        'fields': 'id,computed_geometry,geometry,computed_compass_angle,compass_angle,is_pano,captured_at'})
    out = []
    for e in get_json('https://graph.mapillary.com/images?' + q).get('data') or []:
        g = ((e.get('computed_geometry') or e.get('geometry') or {}).get('coordinates')) or []
        head = e.get('computed_compass_angle', e.get('compass_angle'))
        if len(g) < 2 or head is None:
            continue
        out.append(((g[1], g[0]), float(head), _date(e.get('captured_at')), 'mapillary', str(e['id']), bool(e.get('is_pano'))))
    return out


def panoramax(p):
    out = []
    for f in get_json(f'https://api.panoramax.xyz/api/search?bbox={bbox(p, 45)}&limit=40').get('features') or []:
        g = ((f.get('geometry') or {}).get('coordinates')) or []
        pr = f.get('properties') or {}
        head = pr.get('view:azimuth')
        fov = (pr.get('pers:interior_orientation') or {}).get('field_of_view')
        assets = f.get('assets') or {}
        url = (assets.get('sd') or assets.get('thumb') or {}).get('href')
        if len(g) < 2 or head is None or not url:
            continue
        out.append(((g[1], g[0]), float(head), _date(pr.get('datetime')), 'panoramax', url, fov is not None and fov >= 300))
    return out


KV = {'host': None, 'fails': 0, 'next': 0.0, 'busy': 0}  # KartaView moved its addresses in 2026: the first one that answers is used
_kv_lock = __import__('threading').Lock()


def _kv_wait():
    """KartaView answers "too many requests" quickly: at most 3 questions a second, one at a time."""
    with _kv_lock:
        now = time.time()
        wait = KV['next'] - now
        KV['next'] = max(now, KV['next']) + 0.34
    if wait > 0:
        time.sleep(wait)


def kartaview(p):
    if os.environ.get('PHOTO_KARTAVIEW') != '1':
        return []  # off: it says "too many requests" to almost everything and slowed the whole run for 11 photos
    if (KV['host'] is None and KV['fails'] >= 120) or KV['busy'] >= 40:
        return []  # it does not answer today (or keeps saying "too many"): not asked 30,000 times
    _kv_wait()
    d = None
    for host in ([KV['host']] if KV['host'] else ['api.kartaview.org', 'api.openstreetcam.org']):
        try:
            d = get_json(f'https://{host}/2.0/photo/?lat={p[0]:.6f}&lng={p[1]:.6f}&radius=45&itemsPerPage=60', timeout=10)
            KV['host'] = host
            KV['busy'] = 0
            break
        except Exception as err:
            if getattr(err, 'code', None) == 429:
                KV['busy'] += 1
                with _kv_lock:
                    KV['next'] = max(KV['next'], time.time()) + 20  # asked to slow down: a pause for everyone
            if KV['host'] is None:
                KV['fails'] += 1
                continue
            raise
    if d is None:
        raise OSError('no KartaView address answers')
    out = []
    for e in ((d.get('result') or {}).get('data')) or []:
        try:
            cam = (float(e['lat']), float(e['lng']))
            head = float(e['heading'])
        except Exception:
            continue
        url = e.get('fileurlProc') or e.get('fileurlLTh') or e.get('fileurl')
        if not url:
            continue
        out.append((cam, head, _date(e.get('shotDate') or e.get('dateAdded')), 'kartaview', str(url),
                    str(e.get('projection') or 'PLANE').upper() not in ('PLANE', '')))
    return out


# ───────── the shop's own website: pictures it describes as its storefront ─────────
FRONT = re.compile(r'store[\s_-]*front|shop[\s_-]*front|exterior|outside|fa[cç]ade|building|street[\s_-]*view|entrance'
                   r'|front[\s_-]*(of|door|view)|our[\s_-]*(shop|store|location|building)|(shop|store)[\s_-]*(photo|exterior|outside|building)', re.I)
NOT_FRONT = re.compile(r'logo|icon|sprite|avatar|badge|favicon|placeholder|product|interior|inside|map|payment|banner[\s_-]*ad'
                       r'|\.svg|\.gif|data:', re.I)
SOCIAL = re.compile(r'(^|\.)(facebook|instagram|yelp|google|goo|linktr|twitter|x|tiktok|youtube|linkedin)\.(com|gl|ee)$', re.I)
WEB_UA = {'User-Agent': 'MOBIlityBot/1.0 (storefront photo for a cycling map; github.com/terminatoru86/mobility-app)',
          'Accept': 'text/html,*/*;q=0.5'}


def _page(url, timeout=10):
    req = urllib.request.Request(url, headers=WEB_UA)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        if 'html' not in (r.headers.get('Content-Type') or 'html'):
            return ''
        return r.read(2_000_000).decode('utf-8', 'replace')


def front_pictures(page, url):
    """Addresses of the pictures on the page that the site itself describes as the storefront."""
    out = []
    for m in re.finditer(r'<img\b[^>]*>', page, re.I):
        tag = m.group(0)
        at = {k.lower(): htmllib.unescape(v) for k, _, v in re.findall(r'([\w:-]+)\s*=\s*(["\'])(.*?)\2', tag, re.S)}
        src = at.get('src') or at.get('data-src') or at.get('data-lazy-src') or ''
        if not src or src.startswith('data:'):
            src = (at.get('srcset') or at.get('data-srcset') or '').split(',')[-1].strip().split(' ')[0]
        if not src:
            continue
        name = urllib.parse.unquote(urllib.parse.urlsplit(src).path.rsplit('/', 1)[-1])
        said = ' '.join([at.get('alt', ''), at.get('title', ''), name])
        if not FRONT.search(said) or NOT_FRONT.search(said + ' ' + at.get('class', '')):
            continue
        try:  # tiny pictures are thumbnails or decorations
            if int(at.get('width', '9999')) < 300 or int(at.get('height', '9999')) < 200:
                continue
        except ValueError:
            pass
        full = urllib.parse.urljoin(url, src)
        if full.startswith('http') and full not in out:
            out.append(full)
    return out


def candidate_pictures(page, url):
    """Pictures that may show the shop, though the site does not say so: the one offered for link
    previews, the one in the business description, and the larger pictures of the page."""
    out = []

    def add(src):
        src = htmllib.unescape((src or '').strip())
        if not src or src.startswith('data:'):
            return
        full = urllib.parse.urljoin(url, src)
        name = urllib.parse.unquote(urllib.parse.urlsplit(full).path.rsplit('/', 1)[-1])
        if full.startswith('http') and full not in out and not NOT_FRONT.search(name):
            out.append(full)

    for m in re.finditer(r'<meta\b[^>]*>', page, re.I):
        tag = m.group(0)
        if re.search(r'(property|name)\s*=\s*["\'](og:image|og:image:secure_url|twitter:image)["\']', tag, re.I):
            c = re.search(r'content\s*=\s*(["\'])(.*?)\1', tag, re.S)
            if c:
                add(c.group(2))
    for m in re.finditer(r'"(?:image|photo)"\s*:\s*(?:\[\s*)?"(https?:[^"]+)"', page):
        add(m.group(1).replace('\\/', '/'))
    for m in re.finditer(r'<img\b[^>]*>', page, re.I):
        if len(out) >= 6:
            break
        tag = m.group(0)
        at = {k.lower(): htmllib.unescape(v) for k, _, v in re.findall(r'([\w:-]+)\s*=\s*(["\'])(.*?)\2', tag, re.S)}
        if NOT_FRONT.search(at.get('alt', '') + ' ' + at.get('class', '')):
            continue
        try:
            if int(at.get('width', '9999')) < 400 or int(at.get('height', '9999')) < 250:
                continue
        except ValueError:
            pass
        src = at.get('src') or at.get('data-src') or at.get('data-lazy-src') or ''
        if not src or src.startswith('data:'):
            src = (at.get('srcset') or at.get('data-srcset') or '').split(',')[-1].strip().split(' ')[0]
        add(src)
    return out[:6]


def picture_date(url):
    """(still there and a picture, 'YYYY-MM' or ''): from the address (/2023/05/) or the server's own date."""
    when = ''
    m = re.search(r'/(20[0-2]\d)/(0[1-9]|1[0-2])/', url)
    if m:
        when = f'{m.group(1)}-{m.group(2)}'
    for method in ('HEAD', 'GET'):
        try:
            req = urllib.request.Request(url, headers={**WEB_UA, 'Accept': 'image/*'}, method=method)
            with urllib.request.urlopen(req, timeout=8) as r:
                if not (r.headers.get('Content-Type') or '').startswith('image/'):
                    return False, when
                size = r.headers.get('Content-Length')
                if size and size.isdigit() and int(size) < 15000:
                    return False, when  # a thumbnail
                lm = r.headers.get('Last-Modified')
                if lm and not when:
                    try:
                        from email.utils import parsedate_to_datetime
                        when = parsedate_to_datetime(lm).strftime('%Y-%m')
                    except Exception:
                        pass
                return True, when
        except Exception:
            continue
    return False, when


def website(url):
    """Storefront pictures from the place's own website: (rows ['website', address, 'YYYY-MM' or '', 0, 0],
    candidates to be looked at when the site describes none as its storefront)."""
    parts = urllib.parse.urlsplit(url)
    host = parts.netloc.lower().removeprefix('www.')
    if parts.scheme not in ('http', 'https') or not host or SOCIAL.search(host):
        return [], []
    base = f'{parts.scheme}://{parts.netloc}'
    rp = urllib.robotparser.RobotFileParser()
    try:
        req = urllib.request.Request(base + '/robots.txt', headers=WEB_UA)
        with urllib.request.urlopen(req, timeout=8) as r:
            rp.parse(r.read(200_000).decode('utf-8', 'replace').splitlines())
    except Exception:
        rp.parse([])
    if not rp.can_fetch('MOBIlityBot', url):
        return [], []  # the site asks robots to stay out: we do
    home = _page(url)
    found = front_pictures(home, url)
    maybe = candidate_pictures(home, url)
    if not found:
        # the picture of the shop is often on the about / contact / location page
        seen = []
        for m in re.finditer(r'<a\b[^>]*href\s*=\s*["\']([^"\'#]+)["\'][^>]*>(.*?)</a>', home, re.S | re.I):
            if not re.search(r'about|contact|visit|location|find[\s_-]*us|our[\s_-]*(shop|store)', m.group(1) + ' ' + re.sub(r'<[^>]+>', ' ', m.group(2)), re.I):
                continue
            full = urllib.parse.urljoin(url, m.group(1).strip())
            fp = urllib.parse.urlsplit(full)
            if fp.scheme not in ('http', 'https') or fp.netloc.lower().removeprefix('www.') != host:
                continue
            if full.rstrip('/') == url.rstrip('/') or full in seen or re.search(r'\.(pdf|jpe?g|png|gif|zip)$', fp.path, re.I):
                continue
            seen.append(full)
            if len(seen) == 2:
                break
        for extra in seen:
            if not rp.can_fetch('MOBIlityBot', extra):
                continue
            try:
                inner = _page(extra, timeout=8)
            except Exception:
                continue
            found = front_pictures(inner, extra)
            maybe += [c for c in candidate_pictures(inner, extra) if c not in maybe]
            if found:
                break
    out = []
    for pic in found[:4]:
        ok, when = picture_date(pic)
        if not ok or (when and when < '2024-01'):
            continue  # gone, not a picture, or known to be older than 2024
        out.append(['website', pic, when, 0, 0])
        if len(out) == 2:
            break
    cands = []
    if not out:
        for pic in maybe[:8]:
            m = re.search(r'/(20[0-2]\d)/(0[1-9]|1[0-2])/', pic)
            if m and f'{m.group(1)}-{m.group(2)}' < '2024-01':
                continue  # the address itself says it is older than 2024
            cands.append(['website', pic, f'{m.group(1)}-{m.group(2)}' if m else ''])
    return out, cands[:6]


def best(p, shots, now=None):
    """The photos that look at the place: straight at it, from close, new. At most 3 different views."""
    now = now or datetime.now(timezone.utc)
    scored = []
    for cam, head, at, src, ref, pano in shots:
        if at is None or at < SINCE:
            continue
        m = meters(cam, p)
        rel = (bearing(cam, p) - head + 180) % 360 - 180  # where the place is, from the picture's middle
        off = abs(rel)
        years = (now - at).days / 365
        if pano:
            # a 360-degree picture sees the place whichever way it was driven: only the distance counts
            if m < 4 or m > 30:
                continue
            scored.append((12 + abs(m - 12) * 1.2 + years * 4, cam, [src, ref, at.strftime('%Y-%m'), round(m), round(rel), 'pano']))
            continue
        if m < 4 or m > 30 or off > 25:
            continue
        scored.append((off + abs(m - 12) * 1.2 + years * 4, cam, [src, ref, at.strftime('%Y-%m'), round(m), round(off)]))
    scored.sort(key=lambda s: s[0])
    kept, out = [], []
    for _, cam, row in scored:
        if len(out) >= 3:
            break
        if any(meters(cam, k) < 5 for k in kept):
            continue  # not the same view twice
        kept.append(cam)
        out.append(row)
    return out


def look(p, token, site=None, tags=None):
    shots, failed = [], []
    for name, fn in (('mapillary', lambda: mapillary(p, token)), ('panoramax', lambda: panoramax(p)),
                     ('kartaview', lambda: kartaview(p))):
        try:
            shots += fn()
        except Exception as e:
            failed.append(f'{name}: {type(e).__name__}{" " + str(getattr(e, "code", "")) if getattr(e, "code", None) else ""}')
    got = list(tags or []) + best(p, shots)
    cands = []
    if site:
        try:
            rows, cands = website(site)
            got += rows
        except Exception:
            _web[0] += 1
    return got, failed, cands


def linked(t):
    """Photos a mapper linked to this very place on the map."""
    out = []
    for k in ('mapillary', 'panoramax'):
        v = str(t.get(k) or '').split(';')[0].strip()
        if re.fullmatch(r'[0-9a-f-]{8,40}', v):
            out.append([k, v if k == 'mapillary' else f'https://api.panoramax.xyz/api/pictures/{v}/sd.jpg', '', 0, 0, 'linked'])
    for k in ('image', 'image:0'):
        v = str(t.get(k) or '').strip()
        if re.match(r'https?://\S+\.(jpe?g|png|webp)$', v, re.I):
            out.append(['mapper', v, '', 0, 0, 'linked'])
    return out[:2]


_web = [0]  # websites that did not answer


def load_places():
    out, sites = {}, {}
    for name in sorted(os.listdir(OUT)):
        if not re.match(r't_(-?\d+)_(-?\d+)\.json\.gz$', name):
            continue
        for r in json.loads(gzip.decompress(open(os.path.join(OUT, name), 'rb').read())):
            k = kind(r[3])
            if k and r[3].get('name'):
                u = (r[3].get('website') or r[3].get('contact:website') or '').strip().split('#')[0]
                if u and not re.match(r'https?://', u, re.I):
                    u = 'https://' + u
                out[str(r[0])] = (k, (float(r[1]), float(r[2])), u or None, linked(r[3]))
                if u:
                    sites.setdefault(u, set()).add((round(float(r[1]), 3), round(float(r[2]), 3)))
    # a website used by several places (a chain's page) shows no particular shop: not read
    shared = {u for u, where in sites.items() if len(where) > 1}
    return {k: (kd, pos, None if u in shared else u, ln) for k, (kd, pos, u, ln) in out.items()}


def self_test():
    p = (41.9611, -87.7073)
    new, old = datetime(2025, 6, 1, tzinfo=timezone.utc), datetime(2022, 6, 1, tzinfo=timezone.utc)
    south = (p[0] - 12 / 111200, p[1])  # 12 m south of the place
    shots = [
        (south, 0.0, new, 'a', 'front', False),        # looks north, straight at it: kept
        (south, 180.0, new, 'a', 'back', False),       # looks away
        (south, 0.0, old, 'a', 'old', False),          # before 2024
        ((p[0] - 60 / 111200, p[1]), 0.0, new, 'a', 'far', False),
        ((p[0] - 13 / 111200, p[1]), 5.0, new, 'a', 'same view', False),
        ((p[0], p[1] + 20 / 83000), 180.0, new, 'a', 'round', True),  # 360-degree, 20 m east, driven south
    ]
    rows = best(p, shots, now=datetime(2026, 1, 1, tzinfo=timezone.utc))
    assert [r[1] for r in rows] == ['front', 'round'], rows
    assert rows[1][5] == 'pano' and 85 <= rows[1][4] <= 95, rows[1]  # the place is to the right of the driving direction
    cand = candidate_pictures('<meta property="og:image" content="/share.jpg"><img src="/logo.png"><img src="/big.jpg" width="900">'
                              '<script>{"@type":"BikeStore","image":"https:\\/\\/x.example\\/shop.jpg"}</script>', 'https://shop.example/')
    assert cand == ['https://shop.example/share.jpg', 'https://x.example/shop.jpg', 'https://shop.example/big.jpg'], cand
    assert linked({'mapillary': '951395492878525', 'image': 'https://a.example/x.jpg'})[0][:2] == ['mapillary', '951395492878525']
    assert 11 < meters(south, p) < 13 and bearing(south, p) < 1
    page = ('<img src="/img/logo.png" alt="Store logo"><img src="/wp-content/uploads/2025/03/storefront.jpg" alt="x">'
            '<img data-src="a.jpg" alt="Our shop exterior on Main St"><img src="bike.jpg" alt="Trek product">'
            '<img src="in.jpg" alt="Inside our store"><img src="s.jpg" alt="storefront" width="80">')
    got = front_pictures(page, 'https://shop.example/')
    assert got == ['https://shop.example/wp-content/uploads/2025/03/storefront.jpg', 'https://shop.example/a.jpg'], got
    assert SOCIAL.search('instagram.com') and not SOCIAL.search('craftebikes.com')
    print('self-test ok')


def main():
    if '--test' in sys.argv:
        return self_test()
    places = load_places()
    try:
        known = json.load(open(LIST, encoding='utf-8'))
    except Exception:
        known = {}
    known = {k: v for k, v in known.items() if k in places}  # places that left the map leave the list
    today = datetime.now(timezone.utc)
    day = today.strftime('%Y-%m-%d')

    def due(k):
        e = known.get(k)
        if not e:
            return True
        if e.get('v') != READER:
            return True
        try:
            return (today - datetime.strptime(e['t'], '%Y-%m-%d').replace(tzinfo=timezone.utc)).days >= RECHECK_DAYS
        except Exception:
            return True

    todo = [k for k in places if due(k)]
    token = mapillary_token()
    print(f'places: {len(places)} · to look up now: {len(todo)} · Mapillary token: {"yes" if token else "NO"}', flush=True)
    end = time.time() + 60 * float(os.environ.get('PHOTO_MINUTES', '100'))
    fails, done = {}, 0

    def one(k):
        if time.time() > end:
            return k, None, [], []
        got, failed, cands = look(places[k][1], token, places[k][2], places[k][3])
        return k, got, failed, cands

    with ThreadPoolExecutor(max_workers=int(os.environ.get('PHOTO_THREADS', '32'))) as ex:
        for k, got, failed, cands in ex.map(one, todo):
            if got is None:
                continue
            done += 1
            for f in failed:
                fails[f] = fails.get(f, 0) + 1
            # all three sources failed: not counted as "no photo", tried again next time
            if len(failed) < 3:
                known[k] = {'t': day, 'v': READER, 'p': got}
                if cands:
                    known[k]['c'] = cands
            if done % 2000 == 0:
                print(f'  {done}/{len(todo)} · with a photo so far: {sum(1 for e in known.values() if e["p"])}', flush=True)

    json.dump(known, open(LIST, 'w', encoding='utf-8'), ensure_ascii=False, separators=(',', ':'), sort_keys=True)
    by = {}
    for k, e in known.items():
        b = by.setdefault(places[k][0], [0, 0])
        b[0] += 1
        b[1] += 1 if e['p'] else 0
    src = {}
    for e in known.values():
        for row in e['p']:
            name = row[0] + (' 360' if len(row) > 5 and row[5] == 'pano' else '')
            src[name] = src.get(name, 0) + 1
    print(f'KartaView address in use: {KV["host"]} · places with website pictures still to be looked at: '
          f'{sum(1 for e in known.values() if e.get("c"))}')
    with_photo = sum(1 for e in known.values() if e['p'])
    print(f'looked up now: {done} of {len(todo)} · sources that did not answer: {fails} · websites that did not answer: {_web[0]}')
    print(f'places with a website of their own: {sum(1 for v in places.values() if v[2])}')
    print(f'by kind (checked, with a front photo): {by}')
    print(f'photos kept, by source: {src}')
    print(f'::notice::front photos (2024+) for {with_photo} of {len(known)} checked places ({len(places)} in all)')


if __name__ == '__main__':
    main()
