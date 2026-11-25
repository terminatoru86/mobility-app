"""Rio Rancho NM records reply (26-5558): park bike racks + MRCOG bikeways (2024-25, kept) + older city trails not in MRCOG."""
import sys, json, hashlib, math, collections
sys.path.insert(0, '/home/claude/out')
import shp
A = '/home/claude/att/files1'; REPO = '/home/claude/mob2'
S = 'City data: Rio Rancho NM (public records reply, Nov 2026)'
def km(l): return sum(math.hypot((c-a)*111.32*math.cos(math.radians(b)), (d-b)*110.57) for (a,b),(c,d) in zip(l,l[1:]))
pts = []
for r,k,g in shp.load(A+'/CoRR_bike_racks/CoRR_bike_racks/ParkAssets_bikeRack'):
    lon,lat = g[0]
    pts.append(['usr/'+hashlib.sha1(('rr|'+r['GlobalID']).encode()).hexdigest()[:10], round(lat,6), round(lon,6),
                {'amenity':'bicycle_parking','name':r['ParkName'],'source':S}])
TYP = {'BikeLane':'Bike lane','MultiUseTrail':'Multi-use trail','BikeRoute':'Bike route'}
groups = collections.defaultdict(list); verts = set()
for r,k,g in shp.load(A+'/MRCOG_bikeways/MRCOG_bikeways/COGbikeways'):
    if r['Status'] != 'Existing': continue
    groups[(r['ParentPath'] or 'Unnamed', TYP.get(r['PathType'],'Bikeway'), r['SurfaceMat'], r['Maintained'])] += g
    for ln in g:
        for lon,lat in ln: verts.add((round(lat,3), round(lon,3)))
extra = 0
for r,k,g in shp.load(A+'/CoRR_bikeways/CoRR_bikeways/Bikeways'):
    if r['Bikeway'] not in ('Bike Trail','Unpaved Trail'): continue
    pts_ = [p for ln in g for p in ln]
    if sum((round(lat,3),round(lon,3)) in verts for lon,lat in pts_) > len(pts_)*0.5: continue
    groups[(r['Road'] or 'Trail', 'Unpaved trail' if 'Unpaved' in r['Bikeway'] else 'Trail', r['SurfaceMat'], 'City of Rio Rancho')] += g; extra += 1
out = []
for (name,label,surf,maint),lines in sorted(groups.items()):
    out.append({'id':'a/'+hashlib.sha1(f'riorancho|{name}|{label}|{surf}|{maint}'.encode()).hexdigest()[:12],
        'name': name if label.lower() in name.lower() or 'trail' in name.lower() or 'path' in name.lower() else f'{name} {label.lower()}',
        'ref':None,'kind':'mtb' if label=='Unpaved trail' else 'bicycle','network':None,'operator':maint or 'City of Rio Rancho',
        'km':round(sum(km(l) for l in lines),1),'tags':{'bike_facility':label, **({'surface':surf} if surf else {})},
        'source':'City of Rio Rancho / MRCOG GIS (public records reply, Nov 2026)','url':None,
        'lines':[[v for lon,lat in ln for v in (round(lat,5),round(lon,5))] for ln in lines if len(ln)>1]})
uo = json.load(open(REPO+'/data/user_official.json'))
uo = [r for r in uo if r[3].get('source') != S] + pts
json.dump(uo, open(REPO+'/data/user_official.json','w'), separators=(',',':'))
json.dump(out, open(REPO+'/data/trails_user/rio_rancho_nm.json','w'), separators=(',',':'))
print('racks', len(pts), 'routes', len(out), round(sum(x['km'] for x in out)), 'km', 'extra city trails', extra,
      collections.Counter(x['tags']['bike_facility'] for x in out))
