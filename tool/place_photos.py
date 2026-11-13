#!/usr/bin/env python3
"""Front photos of shops, service hubs and rentals, from open street-photo collections.

For every named shop, service hub and rental in the data packs it looks for street photos
  - taken from 2024 on,
  - 4-30 m away from the place,
  - with the camera turned towards the place (at most 25 degrees off),
in Mapillary, Panoramax and KartaView (all open licences; faces and number plates are blurred
by the source). 360-degree pictures are left out (flattened, they show the place bent).
The best ones (straight at the place, from about 12 m, newest) are kept in data/place_photos.json:

  { place id: { "t": day checked, "p": [[source, photo id or address, "YYYY-MM", metres, degrees off], ...] } }

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
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'assets', 'osm', 'tiles')
LIST = os.path.join(ROOT, 'data', 'place_photos.json')
SINCE = datetime(2024, 1, 1, tzinfo=timezone.utc)
RECHECK_DAYS = 60
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
        if len(g) < 2 or head is None or e.get('is_pano'):
            continue
        out.append(((g[1], g[0]), float(head), _date(e.get('captured_at')), 'mapillary', str(e['id'])))
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
        if len(g) < 2 or head is None or not url or (fov is not None and fov >= 300):
            continue
        out.append(((g[1], g[0]), float(head), _date(pr.get('datetime')), 'panoramax', url))
    return out


def kartaview(p):
    d = get_json(f'https://api.openstreetcam.org/2.0/photo/?lat={p[0]:.6f}&lng={p[1]:.6f}&radius=45&itemsPerPage=60')
    out = []
    for e in ((d.get('result') or {}).get('data')) or []:
        try:
            cam = (float(e['lat']), float(e['lng']))
            head = float(e['heading'])
        except Exception:
            continue
        url = e.get('fileurlProc') or e.get('fileurlLTh') or e.get('fileurl')
        if not url or str(e.get('projection') or 'PLANE').upper() not in ('PLANE', ''):
            continue
        out.append((cam, head, _date(e.get('shotDate') or e.get('dateAdded')), 'kartaview', str(url)))
    return out


def best(p, shots, now=None):
    """The photos that look at the place: straight at it, from close, new. At most 3 different views."""
    now = now or datetime.now(timezone.utc)
    scored = []
    for cam, head, at, src, ref in shots:
        if at is None or at < SINCE:
            continue
        m = meters(cam, p)
        off = abs((bearing(cam, p) - head) % 360)
        off = 360 - off if off > 180 else off
        if m < 4 or m > 30 or off > 25:
            continue
        years = (now - at).days / 365
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


def look(p, token):
    shots, failed = [], []
    for name, fn in (('mapillary', lambda: mapillary(p, token)), ('panoramax', lambda: panoramax(p)),
                     ('kartaview', lambda: kartaview(p))):
        try:
            shots += fn()
        except Exception as e:
            failed.append(f'{name}: {type(e).__name__}{" " + str(getattr(e, "code", "")) if getattr(e, "code", None) else ""}')
    return best(p, shots), failed


def load_places():
    out = {}
    for name in sorted(os.listdir(OUT)):
        if not re.match(r't_(-?\d+)_(-?\d+)\.json\.gz$', name):
            continue
        for r in json.loads(gzip.decompress(open(os.path.join(OUT, name), 'rb').read())):
            k = kind(r[3])
            if k and r[3].get('name'):
                out[str(r[0])] = (k, (float(r[1]), float(r[2])))
    return out


def self_test():
    p = (41.9611, -87.7073)
    new, old = datetime(2025, 6, 1, tzinfo=timezone.utc), datetime(2022, 6, 1, tzinfo=timezone.utc)
    south = (p[0] - 12 / 111200, p[1])  # 12 m south of the place
    shots = [
        (south, 0.0, new, 'a', 'front'),        # looks north, straight at it: kept
        (south, 180.0, new, 'a', 'back'),       # looks away
        (south, 0.0, old, 'a', 'old'),          # before 2024
        ((p[0] - 60 / 111200, p[1]), 0.0, new, 'a', 'far'),
        ((p[0] - 13 / 111200, p[1]), 5.0, new, 'a', 'same view'),
    ]
    got = [r[1] for r in best(p, shots, now=datetime(2026, 1, 1, tzinfo=timezone.utc))]
    assert got == ['front'], got
    assert 11 < meters(south, p) < 13 and bearing(south, p) < 1
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
            return k, None, []
        got, failed = look(places[k][1], token)
        return k, got, failed

    with ThreadPoolExecutor(max_workers=int(os.environ.get('PHOTO_THREADS', '16'))) as ex:
        for k, got, failed in ex.map(one, todo):
            if got is None:
                continue
            done += 1
            for f in failed:
                fails[f] = fails.get(f, 0) + 1
            # all three sources failed: not counted as "no photo", tried again next time
            if len(failed) < 3:
                known[k] = {'t': day, 'p': got}
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
            src[row[0]] = src.get(row[0], 0) + 1
    with_photo = sum(1 for e in known.values() if e['p'])
    print(f'looked up now: {done} of {len(todo)} · sources that did not answer: {fails}')
    print(f'by kind (checked, with a front photo): {by}')
    print(f'photos kept, by source: {src}')
    print(f'::notice::front photos (2024+) for {with_photo} of {len(known)} checked places ({len(places)} in all)')


if __name__ == '__main__':
    main()
