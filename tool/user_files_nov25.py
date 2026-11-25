"""Turn the files cities sent by email (25 Nov 2026) into app data:
 - Lawrence KS racks / lockers / repair stands / bike-moped + motorcycle stalls -> data/user_official.json
 - Lawrence KS existing bikeway network -> data/trails_user/lawrence_ks.json
 - Belton MO trails (KMZ) -> data/trails_user/belton_mo.json
"""
import sys, json, hashlib, math, re, collections
sys.path.insert(0, '/home/claude/out')
import shp

A = '/home/claude/att'
REPO = '/home/claude/mob2'
SRC_L = 'City data: Lawrence KS (public records reply, Nov 2026)'

def hid(*a):
    return hashlib.sha1('|'.join(map(str, a)).encode()).hexdigest()[:10]

def km(line):
    s = 0
    for (a, b), (c, d) in zip(line, line[1:]):
        s += math.hypot((c - a) * 111.32 * math.cos(math.radians(b)), (d - b) * 110.57)
    return s

pts = []
for r, k, g in shp.load(A + '/08a6407b-fAmenityPoint/fAmenityPoint'):
    lon, lat = g[0]
    t = r['assettype']; nm = r['assetname']
    p = {'amenity': 'bicycle_parking', 'source': SRC_L}
    if t == 'BikeRepair':
        p = {'amenity': 'bicycle_repair_station', 'source': SRC_L}
    elif 'Locker' in t or 'Locker' in nm:
        p['bicycle_parking'] = 'lockers'
    if nm and nm not in ('Bike Rack', 'Bike Racks', 'Bicycle Parking'):
        p['name'] = nm
    pts.append(['usr/' + hid('lawrence', r['GlobalID']), round(lat, 6), round(lon, 6), p])
for r, k, g in shp.load(A + '/5e6c436b-pStall/pStall'):
    lon, lat = g[0]
    if r['stallusety'] == 'Motorcycle':
        p = {'amenity': 'motorcycle_parking', 'source': SRC_L}
    else:
        p = {'amenity': 'bicycle_parking', 'note': 'bike / moped stall', 'source': SRC_L}
    loc = r.get('location') or r.get('block')
    if loc: p['name'] = loc
    pts.append(['usr/' + hid('lawrence', r['GlobalID']), round(lat, 6), round(lon, 6), p])

TYP = {'SUP': ('Shared use path', 'path'), 'CBL': ('Bike lane', 'lane'), 'BBL': ('Buffered bike lane', 'lane'),
       'MSL': ('Marked shared lane', 'shared'), 'SB': ('Signed bike route', 'route'), 'BB': ('Bike boulevard', 'route')}
groups = collections.defaultdict(list)
for r, k, g in shp.load(A + '/c897fee2-BikewayNetwork2026/BikewayNetwork2026'):
    if r['Status'] != 'Existing' or r['BikewayTyp'] not in TYP: continue
    groups[(r['Name'] or 'Unnamed', r['BikewayTyp'], r['SurfaceMat'])] += g
law = []
for (name, t, surf), lines in sorted(groups.items()):
    label, _ = TYP[t]
    flat = [[v for lon, lat in ln for v in (round(lat, 5), round(lon, 5))] for ln in lines if len(ln) > 1]
    law.append({'id': 'a/' + hashlib.sha1(f'lawrence|{name}|{t}|{surf}'.encode()).hexdigest()[:12],
                'name': f'{name} {label.lower()}', 'ref': None, 'kind': 'bicycle', 'network': None,
                'operator': 'City of Lawrence', 'km': round(sum(km(l) for l in lines), 1),
                'tags': {'bike_facility': label, **({'surface': surf} if surf else {})},
                'source': 'City of Lawrence GIS (public records reply, Nov 2026)', 'url': None, 'lines': flat})

kml = open(A + '/9e751867-archive/Belton_Trails_KMZ/kml/doc.kml', encoding='utf-8').read()
bel = []
for pm in re.findall(r'<Placemark.*?</Placemark>', kml, re.S):
    name = re.search(r'<name>(.*?)</name>', pm, re.S).group(1).strip()
    cells = re.findall(r'<td>(.*?)</td>\s*<td>(.*?)</td>', pm, re.S)
    attr = {a.strip(): b.strip() for a, b in cells}
    lines = []
    for c in re.findall(r'<coordinates>(.*?)</coordinates>', pm, re.S):
        ln = [tuple(map(float, x.split(',')[:2])) for x in c.split()]
        if len(ln) > 1: lines.append(ln)
    if not lines: continue
    fac = attr.get('Facility Type', '')
    bel.append({'id': 'a/' + hashlib.sha1(f'belton|{name}|{len(bel)}'.encode()).hexdigest()[:12],
                'name': name, 'ref': None, 'kind': 'bicycle' if 'Shared Use' in fac or 'Bike' in fac else 'hiking',
                'network': None, 'operator': 'City of Belton', 'km': round(sum(km(l) for l in lines), 1),
                'tags': {'trail_type': fac, 'surface': attr.get('Surface Type', '')},
                'source': 'City of Belton GIS (public records reply, Nov 2026)', 'url': None,
                'lines': [[v for lon, lat in ln for v in (round(lat, 5), round(lon, 5))] for ln in lines]})

uo = json.load(open(REPO + '/data/user_official.json'))
old = {r[0] for r in uo}
uo = [r for r in uo if not r[3].get('source', '').startswith('City data: Lawrence KS')] + pts
json.dump(uo, open(REPO + '/data/user_official.json', 'w'), separators=(',', ':'))
json.dump(law, open(REPO + '/data/trails_user/lawrence_ks.json', 'w'), separators=(',', ':'))
json.dump(bel, open(REPO + '/data/trails_user/belton_mo.json', 'w'), separators=(',', ':'))
print('Lawrence points', len(pts), collections.Counter(p[3]['amenity'] for p in pts))
print('Lawrence bikeways', len(law), round(sum(x['km'] for x in law)), 'km',
      collections.Counter(x['tags']['bike_facility'] for x in law))
print('Belton trails', len(bel), round(sum(x['km'] for x in bel), 1), 'km', collections.Counter(x['kind'] for x in bel))
