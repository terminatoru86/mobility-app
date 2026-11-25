"""Geocode address lists cities sent (data/inbox/<city>/*addresses.csv, columns name,address,...) with Nominatim
(1 request/s). Writes <same name>.geocoded.csv into data/inbox_out/<city>/."""
import csv, glob, json, os, time, urllib.parse, urllib.request
CITY = {'kansas_city_mo': 'Kansas City, Missouri', 'elko_nv': 'Elko, Nevada', 'clemmons_nc': 'Clemmons, North Carolina'}
UA = {'User-Agent': 'MOBIlity-app inbox geocoder (github.com/terminatoru86/mobility-app)'}


def q(s):
    u = 'https://nominatim.openstreetmap.org/search?format=json&limit=1&countrycodes=us&q=' + urllib.parse.quote(s)
    try:
        with urllib.request.urlopen(urllib.request.Request(u, headers=UA), timeout=30) as r:
            d = json.load(r)
        return (float(d[0]['lat']), float(d[0]['lon']), d[0]['display_name']) if d else None
    except Exception as e:
        print('ERR', s, e)
        return None


for f in glob.glob('data/inbox/*/*addresses.csv'):
    city = os.path.basename(os.path.dirname(f))
    place = CITY.get(city, city.replace('_', ' '))
    rows = list(csv.DictReader(open(f, encoding='utf-8')))
    out = os.path.join('data/inbox_out', city, os.path.basename(f).replace('.csv', '.geocoded.csv'))
    os.makedirs(os.path.dirname(out), exist_ok=True)
    ok = 0
    with open(out, 'w', newline='', encoding='utf-8') as fo:
        w = csv.writer(fo)
        w.writerow(list(rows[0].keys()) + ['lat', 'lon', 'match'])
        for r in rows:
            a = (r.get('address') or r.get('name') or '').strip().replace(' and ', ' & ')
            tries = [a if ',' in a else f'{a}, {place}']
            if r.get('name'):
                tries.append(f"{r['name']}, {place}")
            res = None
            for s in tries:
                res = q(s)
                time.sleep(1.1)
                if res:
                    break
            ok += bool(res)
            w.writerow(list(r.values()) + ([res[0], res[1], res[2][:120]] if res else ['', '', '']))
    print(f, ok, '/', len(rows))
