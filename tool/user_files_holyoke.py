"""Holyoke MA records reply (Google Drive folder, Nov 2026) -> ValleyBike stations + existing bike lanes/trails."""
import sys, json, hashlib, math, collections
sys.path.insert(0, '/home/claude/out'); import shp
D = '/home/claude/holy/Bikes - Public Records Request/'; REPO = '/home/claude/mob2'
SRC = 'City data: Holyoke MA (public records reply, Nov 2026)'
def km(l): return sum(math.hypot((c-a)*111.32*math.cos(math.radians(b)), (d-b)*110.57) for (a,b),(c,d) in zip(l,l[1:]))
pts = []
for r, k, p in shp.load(D+'BikeInfra/BikeStations'):
    lon, lat = p[0]
    pts.append(['usr/'+hashlib.sha1(f"holy|{r['Name']}".encode()).hexdigest()[:10], round(lat,6), round(lon,6),
                {'amenity':'bicycle_rental','bicycle_rental':'docking_station','name':f"ValleyBike – {r['Name']}",'network':'ValleyBike Share','source':SRC}])
g = collections.defaultdict(list)
for r, k, parts in shp.load(D+'BikeInfra/20190320_BikeNetwork'):
    if r['Lane_Type'] == 'Existing Bike Lane':
        g[(r['NAME2_'] or r['NAME_ABBR'] or 'Unnamed').title(), 'Bike lane'] += [l for l in parts if len(l) > 1]
for r, k, parts in shp.load(D+'Bikes/biketrails_arc'):
    if r['TRAILNAME'] and any(42.15<la<42.27 and -72.72<lo<-72.58 for l in parts for lo,la in l):
        print('trail', r['TRAILNAME'], r['TRAIL_STAT'])
        if r['TRAIL_STAT'] in ('E','A','C'): g[(r['TRAILNAME'], 'Shared use path')] += [l for l in parts if len(l) > 1]
trails = []
for (name, lab), lines in sorted(g.items()):
    trails.append({'id':'a/'+hashlib.sha1(f'holy|{name}|{lab}'.encode()).hexdigest()[:12],
                   'name': name if lab != 'Bike lane' else f'{name} bike lane', 'ref':None, 'kind':'bicycle', 'network':None,
                   'operator':'City of Holyoke MA', 'km':round(sum(km(l) for l in lines),1), 'tags':{'bike_facility':lab},
                   'source':'City of Holyoke MA (public records reply, Nov 2026)', 'url':None,
                   'lines':[[v for lon,lat in ln for v in (round(lat,5),round(lon,5))] for ln in lines]})
uo = json.load(open(REPO+'/data/user_official.json'))
uo = [r for r in uo if r[3].get('source') != SRC] + pts
json.dump(uo, open(REPO+'/data/user_official.json','w'), separators=(',',':'))
json.dump(trails, open(REPO+'/data/trails_user/holyoke_ma.json','w'), separators=(',',':'))
print('stations', len(pts), 'trails', len(trails), round(sum(t['km'] for t in trails),1), 'km')
