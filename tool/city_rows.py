"""Turn the rows found in city / state files (data/city_files, data/gov_sources: *.rows.json from tool/city_files.py)
into map points for the app: data/city_pts.json = [[id, lat, lon, tags], ...] and data/city_pts_REPORT.md.

Keeps a row only when it is clearly one of our categories AND has a place:
  - coordinates (GeoJSON geometry, KML coordinates, lat/lon columns, WKT POINT), or
  - a street address, which is geocoded with the US Census batch geocoder (free, no key).
Rows that only mention bikes (plans, budgets, minutes) are dropped. Run in GitHub Actions (needs internet)."""
import csv, glob, io, json, os, re, sys, time, hashlib
import requests

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIRS = [os.path.join(ROOT, 'data', 'city_files'), os.path.join(ROOT, 'data', 'gov_sources')]
OUT = os.path.join(ROOT, 'data', 'city_pts.json')
REPORT = os.path.join(ROOT, 'data', 'city_pts_REPORT.md')

# category: (regex on row text + file name, tags). The first match wins, so the specific ones come first.
CATS = [
    ('repair', re.compile(r'repair\s*station|fix-?it|bike\s*repair|tool\s*station|bike\s*service\s*station', re.I),
     {'amenity': 'bicycle_repair_station'}),
    ('air', re.compile(r'air\s*pump|bike\s*pump|tire\s*pump|compressed\s*air', re.I), {'amenity': 'compressed_air'}),
    ('charging', re.compile(r'e-?bike\s*charg|bike\s*charg|scooter\s*charg|charging\s*(dock|locker)', re.I),
     {'amenity': 'charging_station', 'bicycle': 'yes'}),
    ('moto_parking', re.compile(r'motorcycle\s*park|moped\s*park|motorcycle\s*(stall|space|zone)|moto(rcycle)?\s*only', re.I),
     {'amenity': 'motorcycle_parking'}),
    ('scooter_parking', re.compile(r'scooter\s*(park|corral|zone|hub|drop)|micromobility\s*(park|corral|zone|hub)|'
                                   r'mobility\s*hub|e-?scooter\s*(corral|parking)', re.I),
     {'amenity': 'small_electric_vehicle_parking'}),
    ('locker', re.compile(r'bike\s*locker|bicycle\s*locker|bike\s*cage|bike\s*room|secure\s*bike|bike\s*station|bikelink', re.I),
     {'amenity': 'bicycle_parking', 'bicycle_parking': 'lockers'}),
    ('racks', re.compile(r'bike\s*rack|bicycle\s*rack|bike\s*corral|bicycle\s*corral|bike\s*park|bicycle\s*park|'
                         r'u-?rack|inverted\s*u|hitch|bike\s*hoop|racks?\b', re.I),
     {'amenity': 'bicycle_parking'}),
]
NOISE = re.compile(r'budget|appropriat|invoice|minutes|agenda|resolution|ordinance\s*no|grant\s*award|\$\s*\d', re.I)
US = lambda lat, lon: 17 <= lat <= 72 and -180 <= lon <= -64
ADDR = re.compile(r'\b(\d{1,6})\s+((?:[NSEW]\.?\s+)?[A-Z0-9][A-Za-z0-9 .\'-]{1,40}?\s(?:St|Street|Ave|Avenue|Blvd|Boulevard|Rd|Road|Dr|Drive|'
                  r'Way|Pl|Place|Ln|Lane|Ct|Court|Pkwy|Parkway|Hwy|Highway|Ter|Terrace|Cir|Circle|Sq|Square|Plaza|Trl|Trail))\b\.?', re.I)
ZIP = re.compile(r'\b(\d{5})(?:-\d{4})?\b')
ST = re.compile(r'\b([A-Z]{2})$')


def num(x):
    try:
        v = float(str(x).strip())
        return v if v == v else None
    except Exception:
        return None


def coords(row):
    """(lat, lon) from a row, or None."""
    g = row.get('geometry')
    if isinstance(g, dict):
        c = g.get('coordinates')
        if g.get('type') == 'Point' and c and len(c) >= 2:
            lon, lat = num(c[0]), num(c[1])
            if lat is not None and lon is not None and US(lat, lon):
                return lat, lon
        if g.get('type') == 'MultiPoint' and c and c[0] and len(c[0]) >= 2:
            lon, lat = num(c[0][0]), num(c[0][1])
            if lat is not None and lon is not None and US(lat, lon):
                return lat, lon
    if row.get('lat') is not None and row.get('lon') is not None:  # shapefile points (already WGS84)
        lat, lon = num(row['lat']), num(row['lon'])
        if lat is not None and lon is not None and US(lat, lon):
            return lat, lon
    if row.get('coords'):  # KML lon,lat[,alt]
        p = row['coords'].split()[0].split(',')
        if len(p) >= 2:
            lon, lat = num(p[0]), num(p[1])
            if lat is not None and lon is not None and US(lat, lon):
                return lat, lon
    props = row.get('props') if isinstance(row.get('props'), dict) else {}
    keys = {k.lower(): v for k, v in props.items()} if props else {}
    for la, lo in (('latitude', 'longitude'), ('lat', 'lon'), ('lat', 'long'), ('lat', 'lng'), ('y', 'x'), ('point_y', 'point_x')):
        if la in keys and lo in keys:
            lat, lon = num(keys[la]), num(keys[lo])
            if lat is not None and lon is not None and US(lat, lon):
                return lat, lon
    txt = ' '.join(str(v) for v in (row.get('row') or [])) + ' ' + str(row.get('line') or '') + ' ' + json.dumps(props)[:2000]
    m = re.search(r'POINT\s*\(\s*(-?\d+\.\d+)\s+(-?\d+\.\d+)\s*\)', txt)
    if m:
        lon, lat = float(m[1]), float(m[2])
        if US(lat, lon):
            return lat, lon
    # two numbers in one row that look like US lat / lon
    vals = [num(v) for v in (row.get('row') or [])]
    lats = [v for v in vals if v is not None and 17 <= v <= 72 and '.' in str(v)]
    lons = [v for v in vals if v is not None and -180 <= v <= -64 and '.' in str(v)]
    if len(lats) == 1 and len(lons) == 1:
        return lats[0], lons[0]
    return None


def name_of(row):
    p = row.get('props') if isinstance(row.get('props'), dict) else {}
    for k in ('name', 'NAME', 'Name', 'location', 'LOCATION', 'Location', 'site', 'SITE', 'address', 'ADDRESS', 'Address'):
        if p.get(k):
            return str(p[k])[:80]
    if row.get('name'):
        return str(row['name'])[:80]
    return ''


def city_state(label):
    """'Fort Worth TX' -> ('Fort Worth', 'TX'); 'Norman' -> ('Norman', ''); 'state:txdot.gov' -> ('', '')."""
    if ':' in label:
        return '', ''
    label = label.replace('_', ' ').strip()
    m = ST.search(label)
    if m:
        return label[:m.start()].strip(), m[1]
    return label, ''


def census_batch(items):
    """items: [(id, street, city, state, zip)] -> {id: (lat, lon)}. Census batch geocoder, 1000 a call."""
    out = {}
    for i in range(0, len(items), 1000):
        buf = io.StringIO()
        csv.writer(buf).writerows(items[i:i + 1000])
        for attempt in range(3):
            try:
                r = requests.post('https://geocoding.geo.census.gov/geocoder/locations/addressbatch',
                                  files={'addressFile': ('a.csv', buf.getvalue(), 'text/csv')},
                                  data={'benchmark': 'Public_AR_Current'}, timeout=600)
                for rec in csv.reader(io.StringIO(r.text)):
                    if len(rec) >= 6 and rec[2] == 'Match' and rec[5]:
                        lon, lat = rec[5].split(',')
                        out[rec[0]] = (float(lat), float(lon))
                break
            except Exception as e:
                print('census retry', attempt, e, flush=True)
                time.sleep(20)
        print(f'geocoded {min(i + 1000, len(items))}/{len(items)}: {len(out)} matched', flush=True)
    return out


def main():
    pts, addr_q, stats = {}, [], {}
    files = [f for d in DIRS for f in glob.glob(os.path.join(d, '**', '*.rows.json'), recursive=True)]
    print(len(files), 'row files', flush=True)
    for f in files:
        place = os.path.basename(os.path.dirname(f))
        if place == 'files':  # gov_sources/files/<label>/...
            place = os.path.basename(os.path.dirname(os.path.dirname(f)))
        fname = os.path.basename(f).lower()
        try:
            rows = json.load(open(f, encoding='utf-8'))
        except Exception:
            continue
        st = stats.setdefault(place, {'rows': 0, 'kept': 0, 'cats': {}})
        for row in rows:
            st['rows'] += 1
            text = json.dumps(row, ensure_ascii=False)[:3000]
            if NOISE.search(text):
                continue
            cat = None
            for c, rx, tags in CATS:
                if rx.search(text) or rx.search(fname):
                    cat = (c, tags)
                    break
            if not cat:
                continue
            ll = coords(row)
            nm = name_of(row)
            key = hashlib.md5((place + text).encode()).hexdigest()[:12]
            if ll:
                pts[key] = [round(ll[0], 6), round(ll[1], 6), cat, nm, place]
            else:
                m = ADDR.search(' '.join(str(v) for v in (row.get('row') or [])) + ' ' + str(row.get('line') or '') + ' ' + nm)
                c_, s_ = city_state(place)
                if m and c_:
                    z = ZIP.search(text)
                    addr_q.append((key, f'{m[1]} {m[2]}', c_, s_, z[1] if z else ''))
                    pts[key] = [None, None, cat, nm or f'{m[1]} {m[2]}', place]
    if addr_q:
        geo = census_batch(addr_q)
        for k, ll in geo.items():
            if k in pts and US(*ll):
                pts[k][0], pts[k][1] = round(ll[0], 6), round(ll[1], 6)
    out, seen = [], set()
    for k, (lat, lon, (c, tags), nm, place) in pts.items():
        if lat is None:
            continue
        dk = (round(lat, 5), round(lon, 5), c)
        if dk in seen:
            continue
        seen.add(dk)
        t = dict(tags)
        if nm:
            t['name'] = nm
        t['source'] = f'City files: {place.replace("_", " ")}'
        out.append([f'cty/{k}', lat, lon, t])
        s = stats[place]
        s['kept'] += 1
        s['cats'][c] = s['cats'].get(c, 0) + 1
    json.dump(out, open(OUT, 'w'), ensure_ascii=False)
    tot = {}
    for s in stats.values():
        for c, n in s['cats'].items():
            tot[c] = tot.get(c, 0) + n
    rep = ['# Points from city / state files\n', f'Row files: {len(files)} · rows read: {sum(s["rows"] for s in stats.values())} · '
           f'addresses sent to the geocoder: {len(addr_q)} · map points kept: {len(out)}\n',
           'By category: ' + ', '.join(f'{c} {n}' for c, n in sorted(tot.items(), key=lambda x: -x[1])) + '\n',
           '| Place | Rows read | Points | Categories |', '|---|---|---|---|']
    for p, s in sorted(stats.items(), key=lambda x: -x[1]['kept']):
        if s['kept']:
            rep.append(f"| {p.replace('_', ' ')} | {s['rows']} | {s['kept']} | {', '.join(f'{c} {n}' for c, n in s['cats'].items())} |")
    open(REPORT, 'w').write('\n'.join(rep) + '\n')
    print('\n'.join(rep[:50]))


if __name__ == '__main__':
    main()
