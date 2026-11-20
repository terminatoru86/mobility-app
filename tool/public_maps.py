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
]


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
    r = requests.get('https://www.google.com/maps/d/kml', params={'mid': s['mid'], 'forcekml': 1}, headers=UA, timeout=120)
    root = ET.fromstring(r.content)
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


def main():
    allp, rep = [], []
    for s in SOURCES:
        try:
            got = arcgis(s) if s['kind'] == 'arcgis' else mymaps(s)
        except Exception as e:
            got = []
            print(s['id'], 'ERROR', e)
        rep.append(f"{s['city']}: {len(got)}")
        allp += got
    json.dump(allp, open(os.path.join(ROOT, 'data', 'public_maps.json'), 'w'), ensure_ascii=False)
    print('\n'.join(rep), '\ntotal', len(allp))


if __name__ == '__main__':
    main()
