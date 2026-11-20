"""Bike-parking maps that cities publish but do not list as open data, found by hand on their websites.
Writes data/public_maps.json = [[id, lat, lon, tags], ...] (read by build_packs.fetch_cityfiles). Run in GitHub Actions."""
import json, os, re, xml.etree.ElementTree as ET
import requests

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UA = {'User-Agent': 'MOBIlity-data-bot/1.0 (albis_iulian@yahoo.com)'}
SOURCES = [
    # Salt Lake City: ~1,400 public racks in the right-of-way (slc.gov/transportation/bike/bikeparking)
    {'id': 'slc', 'city': 'Salt Lake City UT', 'kind': 'arcgis',
     'url': 'https://maps.slc.gov/server/rest/services/Hosted/Bike_Racks/FeatureServer/0', 'where': 'retired_date IS NULL',
     'name': 'site_name', 'cap': 'stall'},
    # Durham NC: city bike parking map (Google My Maps on durhamnc.gov/1033)
    {'id': 'durham', 'city': 'Durham NC', 'kind': 'mymaps', 'mid': '1DHI3dY9fgIBKUqkieifCrc-pUlU'},
    # Dero (maker of the Fixit public repair stand): its world map of installed Fixits (~2,600, ~2,400 in the US)
    {'id': 'dero', 'city': 'Dero Fixit map', 'kind': 'dero', 'url': 'https://www.dero.com/fixitmap/fixitmap.html'},
]


_STATES = None
def in_us(lat, lon):
    """Inside a US state, or within ~3 km of one (the state shapes are simplified: coasts, piers)."""
    return any(_in_us(lat + a, lon + b) for a, b in ((0, 0), (0.03, 0), (-0.03, 0), (0, 0.03), (0, -0.03)))


def _in_us(lat, lon):
    """Point inside one of the US states (data/us_states.json), so Canada / Mexico points stay out."""
    global _STATES
    if _STATES is None:
        g = json.load(open(os.path.join(ROOT, 'data', 'us_states.json')))
        _STATES = []
        for f in g['features']:
            geom = f['geometry']
            polys = geom['coordinates'] if geom['type'] == 'MultiPolygon' else [geom['coordinates']]
            for poly in polys:
                ring = poly[0]
                xs, ys = [p[0] for p in ring], [p[1] for p in ring]
                _STATES.append((min(xs), min(ys), max(xs), max(ys), ring))
    for x0, y0, x1, y1, ring in _STATES:
        if not (x0 <= lon <= x1 and y0 <= lat <= y1):
            continue
        inside, j = False, len(ring) - 1
        for i in range(len(ring)):
            xi, yi = ring[i][0], ring[i][1]
            xj, yj = ring[j][0], ring[j][1]
            if (yi > lat) != (yj > lat) and lon < (xj - xi) * (lat - yi) / (yj - yi) + xi:
                inside = not inside
            j = i
        if inside:
            return True
    return False


def dero(s):
    html = requests.get(s['url'], headers=UA, timeout=120).text
    out = []
    for i, m in enumerate(re.finditer(r'L\.marker\(\[\s*(-?\d+\.\d+)\s*,\s*(-?\d+\.\d+)\s*\][^)]*\)\.bindPopup\("((?:[^"\\]|\\.)*)"\)', html)):
        lat, lon, name = float(m.group(1)), float(m.group(2)), re.sub(r'<[^>]+>', ' ', m.group(3)).strip()
        if not in_us(lat, lon):
            continue
        t = {'amenity': 'bicycle_repair_station', 'brand': 'Dero Fixit', 'manufacturer': 'Dero'}
        if name:
            t['name'] = name[:80]
        t['source'] = 'Maker map: Dero Fixit'
        out.append([f"pm/dero-{i}", round(lat, 6), round(lon, 6), t])
    return out


def arcgis(s):
    out, off = [], 0
    while True:
        r = requests.get(s['url'] + '/query', headers=UA, timeout=120, params={
            'where': s.get('where', '1=1'), 'outFields': '*', 'outSR': 4326, 'f': 'json',
            'resultOffset': off, 'resultRecordCount': 2000})
        d = r.json()
        if 'error' in d and s.get('where'):
            s = dict(s, where='1=1'); continue
        feats = d.get('features', [])
        for f in feats:
            g, a = f.get('geometry') or {}, f.get('attributes') or {}
            if 'x' not in g:
                continue
            t = {'amenity': 'bicycle_parking'}
            if a.get(s.get('name')):
                t['name'] = str(a[s['name']])[:80]
            try:
                c = int(float(a.get(s.get('cap')) or 0))
                if 0 < c < 200:
                    t['capacity'] = str(c)
            except Exception:
                pass
            t['source'] = f"City map: {s['city']}"
            out.append([f"pm/{s['id']}-{a.get('objectid', len(out))}", round(g['y'], 6), round(g['x'], 6), t])
        if not d.get('exceededTransferLimit') and len(feats) < 2000:
            break
        off += len(feats)
    return out


def mymaps(s):
    import io, zipfile
    data = b''
    for url in ('https://www.google.com/maps/d/kml', 'https://www.google.com/maps/d/u/0/kml'):
        r = requests.get(url, params={'mid': s['mid'], 'forcekml': 1}, headers=UA, timeout=120,
                         cookies={'CONSENT': 'YES+cb'})
        data = r.content
        if data[:2] == b'PK':
            z = zipfile.ZipFile(io.BytesIO(data))
            data = z.read([n for n in z.namelist() if n.endswith('.kml')][0])
        if data.lstrip()[:5] in (b'<?xml', b'<kml ') or b'<kml' in data[:300]:
            break
        print('mymaps', url, r.status_code, r.headers.get('content-type'), data[:80])
    else:
        return mymaps_embed(s)
    root = ET.fromstring(data)
    ns = {'k': 'http://www.opengis.net/kml/2.2'}
    out = []
    for i, pm in enumerate(root.iter('{http://www.opengis.net/kml/2.2}Placemark')):
        c = pm.find('.//k:Point/k:coordinates', ns)
        if c is None:
            continue
        lon, lat = map(float, c.text.strip().split(',')[:2])
        name = (pm.findtext('k:name', default='', namespaces=ns) or '').strip()
        desc = (pm.findtext('k:description', default='', namespaces=ns) or '')
        t = {'amenity': 'bicycle_parking'}
        txt = (name + ' ' + desc).lower()
        if re.search(r'locker', txt):
            t['bicycle_parking'] = 'lockers'
        if re.search(r'repair|fix-?it', txt):
            t = {'amenity': 'bicycle_repair_station'}
        if name:
            t['name'] = name[:80]
        t['source'] = f"City map: {s['city']}"
        out.append([f"pm/{s['id']}-{i}", round(lat, 6), round(lon, 6), t])
    return out


def mymaps_embed(s):
    """KML download switched off by the map owner: read the points from the embed page (_pageData)."""
    r = requests.get('https://www.google.com/maps/d/embed', params={'mid': s['mid']}, headers=UA, timeout=120,
                     cookies={'CONSENT': 'YES+cb'})
    m = re.search(r'var _pageData = "(.*?)";', r.text, re.S)
    if not m:
        print('embed: no _pageData', r.status_code)
        return []
    raw = json.loads('"' + m.group(1) + '"')
    out, seen = [], set()
    # placemarks look like  [[[lat,lng]]] ... ["name"] near them
    for i, mm in enumerate(re.finditer(r'\[\[\[(-?\d{1,2}\.\d+),(-?\d{2,3}\.\d+)\]\]', raw)):
        lat, lon = float(mm.group(1)), float(mm.group(2))
        if not (17 <= lat <= 72 and -180 <= lon <= -64) or (round(lat, 6), round(lon, 6)) in seen:
            continue
        seen.add((round(lat, 6), round(lon, 6)))
        out.append([f"pm/{s['id']}-{i}", round(lat, 6), round(lon, 6),
                    {'amenity': 'bicycle_parking', 'source': f"City map: {s['city']}"}])
    print('embed points', len(out))
    return out


def main():
    allp, rep = [], []
    for s in SOURCES:
        try:
            got = arcgis(s) if s['kind'] == 'arcgis' else dero(s) if s['kind'] == 'dero' else mymaps(s)
        except Exception as e:
            got = []
            print(s['id'], 'ERROR', e)
        rep.append(f"{s['city']}: {len(got)}")
        allp += got
    json.dump(allp, open(os.path.join(ROOT, 'data', 'public_maps.json'), 'w'), ensure_ascii=False)
    print('\n'.join(rep), '\ntotal', len(allp))


if __name__ == '__main__':
    main()
